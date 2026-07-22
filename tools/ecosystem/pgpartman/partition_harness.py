#!/usr/bin/env python3
"""Provision and audit a pg_partman lifecycle for IvorySQL tables."""

from __future__ import annotations

import argparse
import calendar
import csv
import dataclasses
import datetime as dt
import enum
import getpass
import io
import json
import os
import pathlib
import re
import subprocess
import sys
from collections.abc import Mapping, Sequence
from typing import Any


UTC = dt.timezone.utc
IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,62}$")


class HarnessError(RuntimeError):
    """Base class for actionable partition-management failures."""


class ConfigurationError(HarnessError):
    """Raised for an invalid or dangerous lifecycle policy."""


class CommandError(HarnessError):
    """Raised when a database command cannot be completed."""


class AuditError(HarnessError):
    """Raised when the live partition set violates declared policy."""


class IntervalKind(str, enum.Enum):
    HOUR = "1 hour"
    DAY = "1 day"
    WEEK = "1 week"
    MONTH = "1 month"


def env_value(env: Mapping[str, str], key: str, default: str) -> str:
    result = env.get(key, default).strip()
    if not result:
        raise ConfigurationError(f"{key} must not be empty")
    return result


def parse_int(
    raw: str,
    *,
    name: str,
    minimum: int | None = None,
    maximum: int | None = None,
) -> int:
    try:
        result = int(raw, 10)
    except ValueError as exc:
        raise ConfigurationError(f"{name} must be an integer") from exc
    if minimum is not None and result < minimum:
        raise ConfigurationError(f"{name} must be at least {minimum}")
    if maximum is not None and result > maximum:
        raise ConfigurationError(f"{name} must be at most {maximum}")
    return result


def parse_bool(raw: str, *, name: str) -> bool:
    normalized = raw.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ConfigurationError(f"{name} must be true or false")


def identifier(raw: str, *, name: str) -> str:
    if not IDENTIFIER_PATTERN.fullmatch(raw):
        raise ConfigurationError(f"{name} must be an unquoted SQL identifier")
    return raw


def quote_literal(raw: str) -> str:
    if "\x00" in raw:
        raise ConfigurationError("SQL values must not contain NUL bytes")
    return "'" + raw.replace("'", "''") + "'"


def parse_timestamp(raw: str) -> dt.datetime:
    normalized = raw.strip().replace("Z", "+00:00")
    try:
        result = dt.datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise AuditError(f"invalid partition boundary {raw!r}") from exc
    if result.tzinfo is None:
        result = result.replace(tzinfo=UTC)
    return result.astimezone(UTC)


def floor_boundary(moment: dt.datetime, interval: IntervalKind) -> dt.datetime:
    value = moment.astimezone(UTC)
    if interval is IntervalKind.HOUR:
        return value.replace(minute=0, second=0, microsecond=0)
    if interval is IntervalKind.DAY:
        return value.replace(hour=0, minute=0, second=0, microsecond=0)
    if interval is IntervalKind.WEEK:
        day = value.replace(hour=0, minute=0, second=0, microsecond=0)
        return day - dt.timedelta(days=day.weekday())
    if interval is IntervalKind.MONTH:
        return value.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    raise AssertionError(interval)


def add_intervals(moment: dt.datetime, count: int, interval: IntervalKind) -> dt.datetime:
    if interval is IntervalKind.HOUR:
        return moment + dt.timedelta(hours=count)
    if interval is IntervalKind.DAY:
        return moment + dt.timedelta(days=count)
    if interval is IntervalKind.WEEK:
        return moment + dt.timedelta(weeks=count)
    if interval is IntervalKind.MONTH:
        month_index = moment.year * 12 + (moment.month - 1) + count
        year, month_zero = divmod(month_index, 12)
        month = month_zero + 1
        day = min(moment.day, calendar.monthrange(year, month)[1])
        return moment.replace(year=year, month=month, day=day)
    raise AssertionError(interval)


def interval_count(span: dt.timedelta, interval: IntervalKind) -> int:
    seconds = span.total_seconds()
    divisors = {
        IntervalKind.HOUR: 3600,
        IntervalKind.DAY: 86400,
        IntervalKind.WEEK: 604800,
    }
    if interval is IntervalKind.MONTH:
        return max(1, int(seconds // (28 * 86400)))
    return max(1, int(seconds // divisors[interval]))


@dataclasses.dataclass(frozen=True, slots=True)
class ConnectionSpec:
    host: str
    port: int
    database: str
    superuser: str
    superuser_password: str
    owner: str
    owner_password: str

    def __post_init__(self) -> None:
        if not self.host or any(character.isspace() for character in self.host):
            raise ConfigurationError("IVORYSQL_HOST is invalid")
        if not 1 <= self.port <= 65535:
            raise ConfigurationError("IVORYSQL_PORT is out of range")
        for label, raw in (
            ("IVORYSQL_DATABASE", self.database),
            ("IVORYSQL_SUPERUSER", self.superuser),
            ("PARTMAN_OWNER", self.owner),
        ):
            identifier(raw, name=label)
        if self.owner == self.superuser:
            raise ConfigurationError("partition owner must be a non-superuser role")
        if len(self.superuser_password) < 12:
            raise ConfigurationError("IVORYSQL_SUPERUSER_PASSWORD must contain at least 12 characters")
        if len(self.owner_password) < 12:
            raise ConfigurationError("PARTMAN_OWNER_PASSWORD must contain at least 12 characters")


@dataclasses.dataclass(frozen=True, slots=True)
class PartitionPolicy:
    schema: str
    table: str
    control_column: str
    interval: IntervalKind
    premake: int
    retention: dt.timedelta
    retention_keep_table: bool
    retention_keep_index: bool
    infinite_time_partitions: bool
    automatic_maintenance: bool
    default_partition: bool
    default_row_limit: int
    maintenance_interval_seconds: int
    maintenance_analyze: bool
    history_intervals: int

    def __post_init__(self) -> None:
        for label, raw in (
            ("PARTMAN_SCHEMA", self.schema),
            ("PARTMAN_TABLE", self.table),
            ("PARTMAN_CONTROL_COLUMN", self.control_column),
        ):
            identifier(raw, name=label)
        if self.premake < 1:
            raise ConfigurationError("PARTMAN_PREMAKE must be positive")
        if self.history_intervals < 1:
            raise ConfigurationError("PARTMAN_HISTORY_INTERVALS must be positive")
        minimum_retention = add_intervals(
            dt.datetime(2020, 1, 1, tzinfo=UTC),
            self.history_intervals,
            self.interval,
        ) - dt.datetime(2020, 1, 1, tzinfo=UTC)
        if self.retention < minimum_retention:
            raise ConfigurationError(
                "retention must cover at least PARTMAN_HISTORY_INTERVALS partitions"
            )
        if self.default_row_limit < 0:
            raise ConfigurationError("PARTMAN_DEFAULT_ROW_LIMIT must not be negative")
        if self.maintenance_interval_seconds < 15:
            raise ConfigurationError("PARTMAN_BGW_INTERVAL must be at least 15 seconds")

    @property
    def parent(self) -> str:
        return f"{self.schema}.{self.table}"

    @property
    def default_table(self) -> str:
        return f"{self.schema}.{self.table}_default"

    @property
    def retention_sql(self) -> str:
        total = int(self.retention.total_seconds())
        if total % 86400 == 0:
            return f"{total // 86400} days"
        if total % 3600 == 0:
            return f"{total // 3600} hours"
        return f"{total} seconds"


@dataclasses.dataclass(frozen=True, slots=True)
class RuntimeSpec:
    connection: ConnectionSpec
    policy: PartitionPolicy
    partman_schema: str

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "RuntimeSpec":
        source = os.environ if env is None else env
        connection = ConnectionSpec(
            host=env_value(source, "IVORYSQL_HOST", "127.0.0.1"),
            port=parse_int(
                env_value(source, "IVORYSQL_PORT", "5333"),
                name="IVORYSQL_PORT",
                minimum=1,
                maximum=65535,
            ),
            database=env_value(source, "IVORYSQL_DATABASE", "partitiondb"),
            superuser=env_value(source, "IVORYSQL_SUPERUSER", "ivorysql"),
            superuser_password=env_value(
                source, "IVORYSQL_SUPERUSER_PASSWORD", "superuser-secret"
            ),
            owner=env_value(source, "PARTMAN_OWNER", "partition_owner"),
            owner_password=env_value(source, "PARTMAN_OWNER_PASSWORD", "partition-owner-secret"),
        )
        interval_raw = env_value(source, "PARTMAN_INTERVAL", "1 day").lower()
        try:
            interval = IntervalKind(interval_raw)
        except ValueError as exc:
            raise ConfigurationError(
                "PARTMAN_INTERVAL must be one of: "
                + ", ".join(item.value for item in IntervalKind)
            ) from exc
        retention_days = parse_int(
            env_value(source, "PARTMAN_RETENTION_DAYS", "90"),
            name="PARTMAN_RETENTION_DAYS",
            minimum=1,
        )
        policy = PartitionPolicy(
            schema=env_value(source, "PARTMAN_SCHEMA", "app"),
            table=env_value(source, "PARTMAN_TABLE", "events"),
            control_column=env_value(source, "PARTMAN_CONTROL_COLUMN", "created_at"),
            interval=interval,
            premake=parse_int(
                env_value(source, "PARTMAN_PREMAKE", "7"),
                name="PARTMAN_PREMAKE",
                minimum=1,
                maximum=366,
            ),
            retention=dt.timedelta(days=retention_days),
            retention_keep_table=parse_bool(
                env_value(source, "PARTMAN_RETENTION_KEEP_TABLE", "false"),
                name="PARTMAN_RETENTION_KEEP_TABLE",
            ),
            retention_keep_index=parse_bool(
                env_value(source, "PARTMAN_RETENTION_KEEP_INDEX", "true"),
                name="PARTMAN_RETENTION_KEEP_INDEX",
            ),
            infinite_time_partitions=parse_bool(
                env_value(source, "PARTMAN_INFINITE_TIME_PARTITIONS", "true"),
                name="PARTMAN_INFINITE_TIME_PARTITIONS",
            ),
            automatic_maintenance=parse_bool(
                env_value(source, "PARTMAN_AUTOMATIC_MAINTENANCE", "true"),
                name="PARTMAN_AUTOMATIC_MAINTENANCE",
            ),
            default_partition=parse_bool(
                env_value(source, "PARTMAN_DEFAULT_PARTITION", "true"),
                name="PARTMAN_DEFAULT_PARTITION",
            ),
            default_row_limit=parse_int(
                env_value(source, "PARTMAN_DEFAULT_ROW_LIMIT", "0"),
                name="PARTMAN_DEFAULT_ROW_LIMIT",
                minimum=0,
            ),
            maintenance_interval_seconds=parse_int(
                env_value(source, "PARTMAN_BGW_INTERVAL", "60"),
                name="PARTMAN_BGW_INTERVAL",
                minimum=15,
            ),
            maintenance_analyze=parse_bool(
                env_value(source, "PARTMAN_MAINTENANCE_ANALYZE", "false"),
                name="PARTMAN_MAINTENANCE_ANALYZE",
            ),
            history_intervals=parse_int(
                env_value(source, "PARTMAN_HISTORY_INTERVALS", "2"),
                name="PARTMAN_HISTORY_INTERVALS",
                minimum=1,
                maximum=100,
            ),
        )
        partman_schema = identifier(
            env_value(source, "PARTMAN_EXTENSION_SCHEMA", "partman"),
            name="PARTMAN_EXTENSION_SCHEMA",
        )
        return cls(connection=connection, policy=policy, partman_schema=partman_schema)


def render_install_sql(spec: RuntimeSpec, *, now: dt.datetime | None = None) -> str:
    connection = spec.connection
    policy = spec.policy
    current = floor_boundary(now or dt.datetime.now(UTC), policy.interval)
    start = add_intervals(current, -policy.history_intervals, policy.interval)
    parent = quote_literal(policy.parent)
    owner = connection.owner
    automatic = "on" if policy.automatic_maintenance else "off"
    return f"""CREATE SCHEMA IF NOT EXISTS {spec.partman_schema};
CREATE EXTENSION IF NOT EXISTS pg_partman WITH SCHEMA {spec.partman_schema};
ALTER PROCEDURE {spec.partman_schema}.run_maintenance_proc(integer, boolean, boolean)
    RESET ivorysql.compatible_mode;

CREATE SCHEMA IF NOT EXISTS {policy.schema} AUTHORIZATION {owner};
CREATE TABLE IF NOT EXISTS {policy.parent} (
    event_id bigint GENERATED ALWAYS AS IDENTITY,
    {policy.control_column} timestamptz NOT NULL,
    tenant_id bigint NOT NULL,
    event_type text NOT NULL,
    payload jsonb NOT NULL,
    PRIMARY KEY (event_id, {policy.control_column})
) PARTITION BY RANGE ({policy.control_column});
ALTER TABLE {policy.parent} OWNER TO {owner};

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM {spec.partman_schema}.part_config
         WHERE parent_table = {parent}
    ) THEN
        PERFORM {spec.partman_schema}.create_parent(
            p_parent_table := {parent},
            p_control := {quote_literal(policy.control_column)},
            p_interval := {quote_literal(policy.interval.value)},
            p_type := 'range',
            p_premake := {policy.premake},
            p_start_partition := {quote_literal(start.isoformat())},
            p_default_table := {'true' if policy.default_partition else 'false'},
            p_automatic_maintenance := {quote_literal(automatic)}
        );
    END IF;
END;
$$;

UPDATE {spec.partman_schema}.part_config
   SET premake = {policy.premake},
       automatic_maintenance = {quote_literal(automatic)},
       infinite_time_partitions = {'true' if policy.infinite_time_partitions else 'false'},
       retention = {quote_literal(policy.retention_sql)},
       retention_keep_table = {'true' if policy.retention_keep_table else 'false'},
       retention_keep_index = {'true' if policy.retention_keep_index else 'false'}
 WHERE parent_table = {parent};

GRANT USAGE ON SCHEMA {spec.partman_schema} TO {owner};
GRANT ALL ON ALL TABLES IN SCHEMA {spec.partman_schema} TO {owner};
GRANT ALL ON ALL SEQUENCES IN SCHEMA {spec.partman_schema} TO {owner};
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA {spec.partman_schema} TO {owner};
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA {spec.partman_schema} TO {owner};
"""


def render_inventory_sql(spec: RuntimeSpec) -> str:
    policy = spec.policy
    parent = quote_literal(policy.parent)
    default_inventory = ""
    if policy.default_partition:
        default_inventory = f"""
UNION ALL
SELECT {quote_literal(policy.schema)},
       {quote_literal(policy.table + '_default')},
       NULL,
       NULL,
       pg_total_relation_size({quote_literal(policy.default_table)}::regclass),
       COALESCE(stat.n_live_tup, 0)::bigint,
       true
  FROM pg_stat_user_tables AS stat
 WHERE stat.schemaname = {quote_literal(policy.schema)}
   AND stat.relname = {quote_literal(policy.table + '_default')}"""
    return f"""WITH children AS (
    SELECT partition_schemaname, partition_tablename
      FROM {spec.partman_schema}.show_partitions({parent}, 'ASC')
), boundaries AS (
    SELECT child.partition_schemaname,
           child.partition_tablename,
           info.child_start_time,
           info.child_end_time
      FROM children AS child
      CROSS JOIN LATERAL {spec.partman_schema}.show_partition_info(
          p_child_table := format(
              '%I.%I', child.partition_schemaname, child.partition_tablename
          ),
          p_parent_table := {parent}
      ) AS info
)
SELECT partition_schemaname AS schema_name,
       partition_tablename AS table_name,
       child_start_time AS range_start,
       child_end_time AS range_end,
       pg_total_relation_size(
           format('%I.%I', partition_schemaname, partition_tablename)::regclass
       ) AS total_bytes,
       COALESCE(stat.n_live_tup, 0)::bigint AS estimated_rows,
       false AS is_default
  FROM boundaries
  LEFT JOIN pg_stat_user_tables AS stat
    ON stat.schemaname = partition_schemaname
   AND stat.relname = partition_tablename
{default_inventory}
ORDER BY range_start NULLS LAST;
"""


def render_maintenance_sql(spec: RuntimeSpec) -> str:
    return f"""CALL {spec.partman_schema}.run_maintenance_proc(
    p_wait := 0,
    p_analyze := {'true' if spec.policy.maintenance_analyze else 'false'},
    p_jobmon := false
);
"""


def render_workload_sql(spec: RuntimeSpec, rows: int = 10000) -> str:
    if rows < 1 or rows > 10_000_000:
        raise ConfigurationError("workload rows must be between 1 and 10000000")
    policy = spec.policy
    return f"""INSERT INTO {policy.parent} (
    {policy.control_column}, tenant_id, event_type, payload
)
SELECT clock_timestamp() - (random() * interval '48 hours'),
       1 + (value % 100),
       CASE value % 4
           WHEN 0 THEN 'created'
           WHEN 1 THEN 'updated'
           WHEN 2 THEN 'viewed'
           ELSE 'deleted'
       END,
       jsonb_build_object('sequence', value, 'source', 'partman-verifier')
  FROM generate_series(1, {rows}) AS value;
ANALYZE {policy.parent};
"""


def write_sql_files(spec: RuntimeSpec, output: pathlib.Path) -> list[pathlib.Path]:
    output.mkdir(parents=True, exist_ok=True)
    files = {
        "install.sql": render_install_sql(spec),
        "inventory.sql": render_inventory_sql(spec),
        "maintenance.sql": render_maintenance_sql(spec),
        "workload.sql": render_workload_sql(spec),
    }
    paths: list[pathlib.Path] = []
    for name, contents in files.items():
        target = output / name
        target.write_text(contents, encoding="utf-8", newline="\n")
        paths.append(target)
    return paths


@dataclasses.dataclass(frozen=True, slots=True)
class PartitionRecord:
    schema_name: str
    table_name: str
    range_start: dt.datetime | None
    range_end: dt.datetime | None
    total_bytes: int
    estimated_rows: int
    is_default: bool

    @property
    def qualified_name(self) -> str:
        return f"{self.schema_name}.{self.table_name}"

    @classmethod
    def from_row(cls, row: Mapping[str, str]) -> "PartitionRecord":
        required = {
            "schema_name",
            "table_name",
            "range_start",
            "range_end",
            "total_bytes",
            "estimated_rows",
            "is_default",
        }
        missing = required - set(row)
        if missing:
            raise AuditError("inventory is missing columns: " + ", ".join(sorted(missing)))
        try:
            start = parse_timestamp(row["range_start"]) if row["range_start"] else None
            end = parse_timestamp(row["range_end"]) if row["range_end"] else None
            default = row["is_default"].lower() in {"t", "true", "1", "yes"}
            return cls(
                schema_name=row["schema_name"],
                table_name=row["table_name"],
                range_start=start,
                range_end=end,
                total_bytes=int(row["total_bytes"]),
                estimated_rows=int(row["estimated_rows"]),
                is_default=default,
            )
        except (ValueError, KeyError) as exc:
            raise AuditError(f"invalid partition inventory row: {exc}") from exc


def parse_inventory(raw: str) -> tuple[PartitionRecord, ...]:
    reader = csv.DictReader(io.StringIO(raw))
    if not reader.fieldnames:
        raise AuditError("partition inventory is empty")
    records = tuple(PartitionRecord.from_row(row) for row in reader)
    if not records:
        raise AuditError("partition inventory contains no records")
    return records


@dataclasses.dataclass(frozen=True, slots=True)
class PartitionPlan:
    expected_start: dt.datetime
    expected_end: dt.datetime
    current_start: dt.datetime
    retention_cutoff: dt.datetime
    required_boundaries: tuple[tuple[dt.datetime, dt.datetime], ...]


def build_plan(
    policy: PartitionPolicy,
    *,
    now: dt.datetime | None = None,
) -> PartitionPlan:
    current = floor_boundary(now or dt.datetime.now(UTC), policy.interval)
    retention_cutoff = current - policy.retention
    history = interval_count(policy.retention, policy.interval)
    expected_start = add_intervals(current, -history, policy.interval)
    expected_end = add_intervals(current, policy.premake + 1, policy.interval)
    bounds: list[tuple[dt.datetime, dt.datetime]] = []
    cursor = expected_start
    while cursor < expected_end:
        next_boundary = add_intervals(cursor, 1, policy.interval)
        bounds.append((cursor, next_boundary))
        cursor = next_boundary
        if len(bounds) > 10000:
            raise ConfigurationError("partition plan exceeds 10000 partitions")
    return PartitionPlan(
        expected_start=expected_start,
        expected_end=expected_end,
        current_start=current,
        retention_cutoff=retention_cutoff,
        required_boundaries=tuple(bounds),
    )


def audit_inventory(
    spec: RuntimeSpec,
    records: Sequence[PartitionRecord],
    *,
    now: dt.datetime | None = None,
) -> list[str]:
    plan = build_plan(spec.policy, now=now)
    problems: list[str] = []
    defaults = [record for record in records if record.is_default]
    ranged = sorted(
        (record for record in records if not record.is_default),
        key=lambda record: record.range_start or dt.datetime.min.replace(tzinfo=UTC),
    )
    if spec.policy.default_partition and not defaults:
        problems.append("configured default partition is missing")
    if len(defaults) > 1:
        problems.append("multiple default partitions were reported")
    if defaults and defaults[0].estimated_rows > spec.policy.default_row_limit:
        problems.append(
            f"default partition contains {defaults[0].estimated_rows} rows; "
            f"limit is {spec.policy.default_row_limit}"
        )
    if not ranged:
        problems.append("no ranged child partitions were reported")
        return problems
    for record in ranged:
        if record.range_start is None or record.range_end is None:
            problems.append(f"{record.qualified_name} has no parseable range")
        elif record.range_start >= record.range_end:
            problems.append(f"{record.qualified_name} has an empty or reversed range")
        if record.total_bytes < 0 or record.estimated_rows < 0:
            problems.append(f"{record.qualified_name} reports negative statistics")
    for previous, current in zip(ranged, ranged[1:]):
        if previous.range_end and current.range_start:
            if previous.range_end < current.range_start:
                problems.append(
                    f"partition gap from {previous.range_end.isoformat()} "
                    f"to {current.range_start.isoformat()}"
                )
            elif previous.range_end > current.range_start:
                problems.append(
                    f"partition overlap at {current.range_start.isoformat()}"
                )
    available = {
        (record.range_start, record.range_end)
        for record in ranged
        if record.range_start is not None and record.range_end is not None
    }
    future_required = [
        boundary
        for boundary in plan.required_boundaries
        if boundary[0] >= plan.current_start
    ]
    missing_future = [boundary for boundary in future_required if boundary not in available]
    if missing_future:
        problems.append(
            f"{len(missing_future)} current/future partitions are missing; first starts "
            f"{missing_future[0][0].isoformat()}"
        )
    expired = [
        record
        for record in ranged
        if record.range_end is not None and record.range_end < plan.retention_cutoff
    ]
    if expired and not spec.policy.retention_keep_table:
        problems.append(
            f"{len(expired)} partitions are older than retention cutoff "
            f"{plan.retention_cutoff.isoformat()}"
        )
    return problems


class CommandRunner:
    def run(
        self,
        command: Sequence[str],
        *,
        env: Mapping[str, str] | None = None,
        timeout: float = 300,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        merged = os.environ.copy()
        if env:
            merged.update(env)
        try:
            result = subprocess.run(
                list(command),
                capture_output=True,
                text=True,
                encoding="utf-8",
                check=False,
                env=merged,
                timeout=timeout,
            )
        except FileNotFoundError as exc:
            raise CommandError(f"required executable not found: {command[0]}") from exc
        except subprocess.TimeoutExpired as exc:
            raise CommandError(f"database command timed out after {timeout:g}s") from exc
        if check and result.returncode:
            details = (result.stderr or result.stdout).strip()[-2000:]
            raise CommandError(f"database command failed ({result.returncode}): {details}")
        return result


def psql(
    spec: RuntimeSpec,
    *,
    sql: str | None = None,
    file: pathlib.Path | None = None,
    csv_output: bool = False,
    runner: CommandRunner | None = None,
    owner: bool = False,
    session_options: Mapping[str, str] | None = None,
    timeout: float = 300,
) -> str:
    if (sql is None) == (file is None):
        raise ValueError("exactly one of sql or file is required")
    connection = spec.connection
    user = connection.owner if owner else connection.superuser
    password = connection.owner_password if owner else connection.superuser_password
    command = [
        "psql",
        "--no-psqlrc",
        "--set",
        "ON_ERROR_STOP=1",
        "--host",
        connection.host,
        "--port",
        str(connection.port),
        "--username",
        user,
        "--dbname",
        connection.database,
    ]
    if csv_output:
        command.append("--csv")
    if sql is not None:
        command.extend(("--command", sql))
    else:
        assert file is not None
        command.extend(("--file", str(file)))
    environment = {"PGPASSWORD": password}
    if session_options:
        environment["PGOPTIONS"] = " ".join(
            f"-c {name}={setting}" for name, setting in session_options.items()
        )
    result = (runner or CommandRunner()).run(
        command,
        env=environment,
        timeout=timeout,
    )
    return result.stdout


def preflight(spec: RuntimeSpec) -> dict[str, Any]:
    policy = spec.policy
    warnings: list[str] = []
    if policy.retention_keep_table:
        warnings.append("expired partitions are detached but retained as tables")
    if not policy.maintenance_analyze:
        warnings.append("maintenance does not analyze the partitioned parent")
    if policy.default_row_limit == 0:
        warnings.append("any row in the default partition fails the audit")
    return {
        "parent": policy.parent,
        "control_column": policy.control_column,
        "interval": policy.interval.value,
        "premake": policy.premake,
        "retention": policy.retention_sql,
        "background_worker_interval": policy.maintenance_interval_seconds,
        "owner": spec.connection.owner,
        "operator": getpass.getuser(),
        "warnings": warnings,
    }


def inventory_dict(records: Sequence[PartitionRecord], problems: Sequence[str]) -> dict[str, Any]:
    return {
        "partition_count": len([item for item in records if not item.is_default]),
        "default_rows": sum(item.estimated_rows for item in records if item.is_default),
        "total_bytes": sum(item.total_bytes for item in records),
        "problems": list(problems),
        "partitions": [
            {
                **dataclasses.asdict(item),
                "range_start": item.range_start.isoformat() if item.range_start else None,
                "range_end": item.range_end.isoformat() if item.range_end else None,
            }
            for item in records
        ],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage pg_partman partitions for IvorySQL")
    subparsers = parser.add_subparsers(dest="command", required=True)
    render = subparsers.add_parser("render")
    render.add_argument("--output", type=pathlib.Path, default=pathlib.Path("generated"))
    subparsers.add_parser("preflight")
    subparsers.add_parser("install")
    workload = subparsers.add_parser("workload")
    workload.add_argument("--rows", type=int, default=10000)
    subparsers.add_parser("maintenance")
    subparsers.add_parser("inventory")
    subparsers.add_parser("audit")
    plan = subparsers.add_parser("plan")
    plan.add_argument("--at")
    return parser


def execute(args: argparse.Namespace, spec: RuntimeSpec, runner: CommandRunner | None = None) -> int:
    if args.command == "render":
        result: Any = {"rendered": [str(path) for path in write_sql_files(spec, args.output)]}
    elif args.command == "preflight":
        result = preflight(spec)
    elif args.command == "install":
        output = psql(spec, sql=render_install_sql(spec), runner=runner, timeout=900)
        result = {"installed": spec.policy.parent, "output": output.strip()}
    elif args.command == "workload":
        output = psql(
            spec,
            sql=render_workload_sql(spec, args.rows),
            runner=runner,
            owner=True,
            timeout=900,
        )
        result = {"inserted": args.rows, "output": output.strip()}
    elif args.command == "maintenance":
        output = psql(
            spec,
            sql=render_maintenance_sql(spec),
            runner=runner,
            session_options={"statement_timeout": "15min", "lock_timeout": "5s"},
            timeout=900,
        )
        result = {"maintained": spec.policy.parent, "output": output.strip()}
    elif args.command in {"inventory", "audit"}:
        raw = psql(spec, sql=render_inventory_sql(spec), csv_output=True, runner=runner)
        records = parse_inventory(raw)
        problems = audit_inventory(spec, records)
        result = inventory_dict(records, problems)
        if args.command == "audit" and problems:
            raise AuditError("; ".join(problems))
    elif args.command == "plan":
        moment = parse_timestamp(args.at) if args.at else dt.datetime.now(UTC)
        plan = build_plan(spec.policy, now=moment)
        result = {
            "expected_start": plan.expected_start.isoformat(),
            "expected_end": plan.expected_end.isoformat(),
            "current_start": plan.current_start.isoformat(),
            "retention_cutoff": plan.retention_cutoff.isoformat(),
            "partition_count": len(plan.required_boundaries),
            "boundaries": [
                {"start": start.isoformat(), "end": end.isoformat()}
                for start, end in plan.required_boundaries
            ],
        }
    else:
        raise AssertionError(f"unhandled command {args.command}")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return execute(args, RuntimeSpec.from_env())
    except HarnessError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
