#!/usr/bin/env python3
"""Configuration, parsing, and policy audit for the wal2json integration."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import sys
from collections import Counter
from collections.abc import Iterable, Mapping, Sequence
from typing import Any


IDENTIFIER = re.compile(r"^[a-z_][a-z0-9_]{0,62}$")
SLOT_IDENTIFIER = re.compile(r"^[a-z_][a-z0-9_]{2,62}$")
SIZE = re.compile(r"^([1-9][0-9]*)(B|KiB|MiB|GiB)$")
SYSTEM_SCHEMAS = {"information_schema", "pg_catalog", "pg_toast"}
ROW_ACTIONS = frozenset({"I", "U", "D", "T"})
KNOWN_ACTIONS = frozenset({"B", "C", "I", "U", "D", "T", "M"})
ACTION_NAMES = {
    "B": "begin",
    "C": "commit",
    "I": "insert",
    "U": "update",
    "D": "delete",
    "T": "truncate",
    "M": "message",
}
SIZE_MULTIPLIERS = {
    "B": 1,
    "KiB": 1024,
    "MiB": 1024**2,
    "GiB": 1024**3,
}


class ConfigurationError(ValueError):
    """Raised when the requested CDC policy is unsafe or ambiguous."""


class ParseError(ValueError):
    """Raised when plugin output is not valid wal2json format version 2."""


class AuditFailure(RuntimeError):
    """Raised when decoded events violate the configured CDC contract."""

    def __init__(self, problems: Sequence[str], report: Mapping[str, Any] | None = None):
        super().__init__("; ".join(problems))
        self.problems = tuple(problems)
        self.report = dict(report or {})


def parse_bool(value: str, name: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ConfigurationError(f"{name} must be a boolean, got {value!r}")


def parse_positive_int(value: str, name: str, *, allow_zero: bool = False) -> int:
    try:
        parsed = int(value, 10)
    except ValueError as exc:
        raise ConfigurationError(f"{name} must be an integer, got {value!r}") from exc
    minimum = 0 if allow_zero else 1
    if parsed < minimum:
        comparator = "non-negative" if allow_zero else "positive"
        raise ConfigurationError(f"{name} must be {comparator}, got {parsed}")
    return parsed


def parse_byte_size(value: str, name: str) -> int:
    match = SIZE.fullmatch(value.strip())
    if not match:
        raise ConfigurationError(
            f"{name} must use B, KiB, MiB, or GiB with a positive integer"
        )
    amount = int(match.group(1), 10)
    return amount * SIZE_MULTIPLIERS[match.group(2)]


def validate_identifier(value: str, name: str) -> str:
    if not IDENTIFIER.fullmatch(value):
        raise ConfigurationError(
            f"{name} must be a lowercase PostgreSQL identifier without quoting"
        )
    return value


def validate_slot(value: str) -> str:
    if not SLOT_IDENTIFIER.fullmatch(value):
        raise ConfigurationError(
            "CDC_SLOT must contain 3-63 lowercase letters, digits, or underscores"
        )
    if value in {"default", "postgres", "replication", "slot"}:
        raise ConfigurationError("CDC_SLOT is too broad or reserved")
    return value


def validate_password(value: str, name: str) -> str:
    if len(value) < 12:
        raise ConfigurationError(f"{name} must contain at least 12 characters")
    if "\n" in value or "\r" in value or "\x00" in value:
        raise ConfigurationError(f"{name} contains a forbidden control character")
    return value


@dataclasses.dataclass(frozen=True, order=True)
class TableRef:
    schema: str
    table: str

    @classmethod
    def parse(cls, value: str) -> "TableRef":
        raw = value.strip()
        if raw.count(".") != 1:
            raise ConfigurationError(
                f"CDC table {value!r} must be schema-qualified exactly once"
            )
        schema, table = raw.split(".", 1)
        validate_identifier(schema, "CDC table schema")
        validate_identifier(table, "CDC table name")
        if schema in SYSTEM_SCHEMAS or schema.startswith("pg_"):
            raise ConfigurationError(f"system schema {schema!r} is not allowed")
        if "*" in raw or "\\" in raw or "," in raw:
            raise ConfigurationError(f"wildcards and escapes are not allowed in {raw!r}")
        return cls(schema, table)

    @property
    def qualified(self) -> str:
        return f"{self.schema}.{self.table}"


def parse_tables(value: str) -> tuple[TableRef, ...]:
    entries = [entry.strip() for entry in value.split(",") if entry.strip()]
    if not entries:
        raise ConfigurationError("CDC_TABLES must contain at least one table")
    tables = tuple(TableRef.parse(entry) for entry in entries)
    if len(set(tables)) != len(tables):
        raise ConfigurationError("CDC_TABLES contains duplicate tables")
    if len(tables) > 32:
        raise ConfigurationError("CDC_TABLES may contain at most 32 tables")
    return tuple(sorted(tables))


@dataclasses.dataclass(frozen=True)
class CdcPolicy:
    database: str
    user: str
    password: str
    slot: str
    schema: str
    tables: tuple[TableRef, ...]
    report_dir: pathlib.Path
    minimum_actions: Mapping[str, int]
    max_slot_lag_bytes: int
    require_transaction_markers: bool
    require_xids: bool
    require_timestamps: bool
    require_types: bool
    require_primary_keys: bool

    @classmethod
    def from_environment(
        cls, environ: Mapping[str, str] | None = None
    ) -> "CdcPolicy":
        env = dict(os.environ if environ is None else environ)
        database = validate_identifier(env.get("IVORYSQL_DATABASE", "cdcdb"), "database")
        user = validate_identifier(env.get("IVORYSQL_USER", "ivorysql"), "user")
        password = validate_password(
            env.get("IVORYSQL_PASSWORD", ""), "IVORYSQL_PASSWORD"
        )
        slot = validate_slot(env.get("CDC_SLOT", "ivorysql_cdc"))
        schema = validate_identifier(env.get("CDC_SCHEMA", "cdc"), "CDC_SCHEMA")
        if schema in SYSTEM_SCHEMAS or schema.startswith("pg_"):
            raise ConfigurationError("CDC_SCHEMA cannot be a system schema")
        tables = parse_tables(env.get("CDC_TABLES", "cdc.accounts,cdc.staging"))
        if any(table.schema != schema for table in tables):
            raise ConfigurationError("every CDC_TABLES entry must use CDC_SCHEMA")
        report_value = env.get("CDC_REPORT_DIR", "/var/lib/ivorysql/reports")
        report_posix = pathlib.PurePosixPath(report_value)
        report_dir = pathlib.Path(report_value)
        if not report_posix.is_absolute():
            raise ConfigurationError("CDC_REPORT_DIR must be absolute")
        if report_posix in {
            pathlib.PurePosixPath("/"),
            pathlib.PurePosixPath("/var"),
            pathlib.PurePosixPath("/var/lib"),
            pathlib.PurePosixPath("/tmp"),
        }:
            raise ConfigurationError("CDC_REPORT_DIR is too broad")
        minimum_actions = {
            "I": parse_positive_int(
                env.get("CDC_MIN_INSERTS", "4"), "CDC_MIN_INSERTS", allow_zero=True
            ),
            "U": parse_positive_int(
                env.get("CDC_MIN_UPDATES", "2"), "CDC_MIN_UPDATES", allow_zero=True
            ),
            "D": parse_positive_int(
                env.get("CDC_MIN_DELETES", "1"), "CDC_MIN_DELETES", allow_zero=True
            ),
            "T": parse_positive_int(
                env.get("CDC_MIN_TRUNCATES", "1"),
                "CDC_MIN_TRUNCATES",
                allow_zero=True,
            ),
        }
        if not any(minimum_actions.values()):
            raise ConfigurationError("at least one CDC action minimum must be non-zero")
        max_slot_lag = parse_byte_size(
            env.get("CDC_MAX_SLOT_LAG", "16MiB"), "CDC_MAX_SLOT_LAG"
        )
        if max_slot_lag > 1024**3:
            raise ConfigurationError("CDC_MAX_SLOT_LAG must not exceed 1GiB")
        return cls(
            database=database,
            user=user,
            password=password,
            slot=slot,
            schema=schema,
            tables=tables,
            report_dir=report_dir,
            minimum_actions=minimum_actions,
            max_slot_lag_bytes=max_slot_lag,
            require_transaction_markers=parse_bool(
                env.get("CDC_REQUIRE_TRANSACTION_MARKERS", "true"),
                "CDC_REQUIRE_TRANSACTION_MARKERS",
            ),
            require_xids=parse_bool(
                env.get("CDC_REQUIRE_XIDS", "true"), "CDC_REQUIRE_XIDS"
            ),
            require_timestamps=parse_bool(
                env.get("CDC_REQUIRE_TIMESTAMPS", "true"),
                "CDC_REQUIRE_TIMESTAMPS",
            ),
            require_types=parse_bool(
                env.get("CDC_REQUIRE_TYPES", "true"), "CDC_REQUIRE_TYPES"
            ),
            require_primary_keys=parse_bool(
                env.get("CDC_REQUIRE_PRIMARY_KEYS", "true"),
                "CDC_REQUIRE_PRIMARY_KEYS",
            ),
        )

    def plugin_options(self) -> tuple[tuple[str, str], ...]:
        actions = [
            ACTION_NAMES[action]
            for action in ("I", "U", "D", "T")
            if self.minimum_actions[action] > 0
        ]
        return (
            ("format-version", "2"),
            ("include-xids", "1" if self.require_xids else "0"),
            ("include-timestamp", "1" if self.require_timestamps else "0"),
            ("include-types", "1" if self.require_types else "0"),
            ("include-pk", "1" if self.require_primary_keys else "0"),
            (
                "include-transaction",
                "1" if self.require_transaction_markers else "0",
            ),
            ("actions", ",".join(actions)),
            ("add-tables", ",".join(table.qualified for table in self.tables)),
        )

    def public_dict(self) -> dict[str, Any]:
        return {
            "database": self.database,
            "user": self.user,
            "slot": self.slot,
            "schema": self.schema,
            "tables": [table.qualified for table in self.tables],
            "report_dir": str(self.report_dir),
            "minimum_actions": dict(self.minimum_actions),
            "max_slot_lag_bytes": self.max_slot_lag_bytes,
            "require_transaction_markers": self.require_transaction_markers,
            "require_xids": self.require_xids,
            "require_timestamps": self.require_timestamps,
            "require_types": self.require_types,
            "require_primary_keys": self.require_primary_keys,
            "plugin_options": [list(item) for item in self.plugin_options()],
        }


def _require_object(value: Any, context: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ParseError(f"{context} must be a JSON object")
    return value


def _parse_columns(value: Any, context: str) -> tuple[Mapping[str, Any], ...]:
    if value is None:
        return ()
    if not isinstance(value, list):
        raise ParseError(f"{context} must be a JSON array")
    parsed: list[Mapping[str, Any]] = []
    names: set[str] = set()
    for index, raw_column in enumerate(value):
        column = _require_object(raw_column, f"{context}[{index}]")
        name = column.get("name")
        if not isinstance(name, str) or not name:
            raise ParseError(f"{context}[{index}].name must be a non-empty string")
        if name in names:
            raise ParseError(f"{context} contains duplicate column {name!r}")
        names.add(name)
        parsed.append(column)
    return tuple(parsed)


def parse_timestamp(value: Any, context: str) -> dt.datetime | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise ParseError(f"{context} must be a string")
    normalized = value.strip()
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    if re.search(r"[+-][0-9]{2}$", normalized):
        normalized += ":00"
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ParseError(f"{context} is not an ISO-8601 timestamp") from exc
    if parsed.tzinfo is None:
        raise ParseError(f"{context} must include a timezone offset")
    return parsed


@dataclasses.dataclass(frozen=True)
class ChangeEvent:
    sequence: int
    action: str
    xid: int | None
    timestamp: dt.datetime | None
    table: TableRef | None
    columns: tuple[Mapping[str, Any], ...]
    identity: tuple[Mapping[str, Any], ...]
    primary_key: tuple[Mapping[str, Any], ...]
    raw: Mapping[str, Any]
    fingerprint: str

    @classmethod
    def parse(cls, raw_line: str, sequence: int) -> "ChangeEvent":
        if not raw_line.strip():
            raise ParseError(f"line {sequence} is empty")
        try:
            document = json.loads(raw_line)
        except json.JSONDecodeError as exc:
            raise ParseError(f"line {sequence} is invalid JSON: {exc.msg}") from exc
        document = _require_object(document, f"line {sequence}")
        action = document.get("action")
        if action not in KNOWN_ACTIONS:
            raise ParseError(f"line {sequence} has unknown action {action!r}")
        xid_value = document.get("xid")
        if xid_value is None:
            xid = None
        elif isinstance(xid_value, int) and xid_value > 0:
            xid = xid_value
        else:
            raise ParseError(f"line {sequence}.xid must be a positive integer")
        timestamp = parse_timestamp(document.get("timestamp"), f"line {sequence}.timestamp")
        table_ref: TableRef | None = None
        if action in ROW_ACTIONS:
            schema = document.get("schema")
            table = document.get("table")
            if not isinstance(schema, str) or not isinstance(table, str):
                raise ParseError(
                    f"line {sequence} row action requires string schema and table"
                )
            try:
                table_ref = TableRef.parse(f"{schema}.{table}")
            except ConfigurationError as exc:
                raise ParseError(f"line {sequence} has unsafe table: {exc}") from exc
        columns = _parse_columns(document.get("columns"), f"line {sequence}.columns")
        identity = _parse_columns(document.get("identity"), f"line {sequence}.identity")
        primary_key = _parse_columns(document.get("pk"), f"line {sequence}.pk")
        canonical = json.dumps(document, sort_keys=True, separators=(",", ":"))
        fingerprint = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
        return cls(
            sequence=sequence,
            action=action,
            xid=xid,
            timestamp=timestamp,
            table=table_ref,
            columns=columns,
            identity=identity,
            primary_key=primary_key,
            raw=document,
            fingerprint=fingerprint,
        )


@dataclasses.dataclass(frozen=True)
class SlotMetrics:
    slot_name: str
    plugin: str
    slot_type: str
    database: str
    active: bool
    restart_lsn: str
    confirmed_flush_lsn: str
    retained_bytes: int

    @classmethod
    def parse(cls, value: str) -> "SlotMetrics":
        try:
            document = json.loads(value)
        except json.JSONDecodeError as exc:
            raise ParseError("slot metrics are not valid JSON") from exc
        document = _require_object(document, "slot metrics")
        required_strings = (
            "slot_name",
            "plugin",
            "slot_type",
            "database",
            "restart_lsn",
            "confirmed_flush_lsn",
        )
        for key in required_strings:
            if not isinstance(document.get(key), str) or not document[key]:
                raise ParseError(f"slot metrics {key} must be a non-empty string")
        if not isinstance(document.get("active"), bool):
            raise ParseError("slot metrics active must be a boolean")
        retained = document.get("retained_bytes")
        if not isinstance(retained, int) or retained < 0:
            raise ParseError("slot metrics retained_bytes must be non-negative")
        return cls(
            slot_name=document["slot_name"],
            plugin=document["plugin"],
            slot_type=document["slot_type"],
            database=document["database"],
            active=document["active"],
            restart_lsn=document["restart_lsn"],
            confirmed_flush_lsn=document["confirmed_flush_lsn"],
            retained_bytes=retained,
        )

    def as_dict(self) -> dict[str, Any]:
        return dataclasses.asdict(self)


def read_events(path: pathlib.Path) -> tuple[ChangeEvent, ...]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ParseError(f"cannot read event file {path}: {exc}") from exc
    if not lines:
        raise ParseError("event file is empty")
    return tuple(ChangeEvent.parse(line, index) for index, line in enumerate(lines, 1))


def read_slot_metrics(path: pathlib.Path) -> SlotMetrics:
    try:
        value = path.read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise ParseError(f"cannot read slot metrics {path}: {exc}") from exc
    if not value:
        raise ParseError("slot metrics file is empty")
    return SlotMetrics.parse(value)


def _column_types_present(columns: Iterable[Mapping[str, Any]]) -> bool:
    return all(isinstance(column.get("type"), str) and column["type"] for column in columns)


def _xid_sequence(events: Sequence[ChangeEvent]) -> list[int]:
    result: list[int] = []
    for event in events:
        if event.xid is not None and (not result or result[-1] != event.xid):
            result.append(event.xid)
    return result


def audit(
    policy: CdcPolicy,
    events: Sequence[ChangeEvent],
    slot: SlotMetrics,
) -> dict[str, Any]:
    problems: list[str] = []
    counts = Counter(event.action for event in events)
    allowed_tables = set(policy.tables)
    seen_tables = {event.table for event in events if event.table is not None}
    fingerprints = [event.fingerprint for event in events]
    transaction_count = 0
    open_xid: int | None = None
    committed_xids: list[int] = []

    if len(fingerprints) != len(set(fingerprints)):
        problems.append("decoded stream contains duplicate event payloads")

    for event in events:
        if policy.require_xids and event.xid is None:
            problems.append(f"event {event.sequence} action {event.action} has no xid")
        if event.table is not None and event.table not in allowed_tables:
            problems.append(
                f"event {event.sequence} exposes forbidden table {event.table.qualified}"
            )
        if event.action == "B":
            if open_xid is not None:
                problems.append(
                    f"event {event.sequence} begins xid {event.xid} while xid {open_xid} is open"
                )
            open_xid = event.xid
            transaction_count += 1
        elif event.action == "C":
            if open_xid is None:
                problems.append(f"event {event.sequence} commits without a begin marker")
            elif event.xid != open_xid:
                problems.append(
                    f"event {event.sequence} commits xid {event.xid}, expected {open_xid}"
                )
            if policy.require_timestamps and event.timestamp is None:
                problems.append(f"commit event {event.sequence} has no timestamp")
            if event.xid is not None:
                committed_xids.append(event.xid)
            open_xid = None
        elif event.action in ROW_ACTIONS:
            if policy.require_transaction_markers and open_xid is None:
                problems.append(
                    f"row event {event.sequence} appears outside transaction markers"
                )
            if open_xid is not None and event.xid != open_xid:
                problems.append(
                    f"row event {event.sequence} xid {event.xid} differs from open xid {open_xid}"
                )
            if event.action in {"I", "U"} and not event.columns:
                problems.append(f"event {event.sequence} has no new columns")
            if policy.require_types:
                typed = event.columns + event.identity + event.primary_key
                if typed and not _column_types_present(typed):
                    problems.append(f"event {event.sequence} has untyped columns")
            if policy.require_primary_keys and event.action in {"I", "U"}:
                if not event.primary_key:
                    problems.append(f"event {event.sequence} has no primary-key metadata")
            if event.action in {"U", "D"} and not event.identity:
                problems.append(f"event {event.sequence} has no old-row identity")

    if open_xid is not None:
        problems.append(f"stream ends while xid {open_xid} is still open")
    if policy.require_transaction_markers:
        if counts["B"] == 0 or counts["C"] == 0:
            problems.append("transaction begin/commit markers are missing")
        if counts["B"] != counts["C"]:
            problems.append(
                f"transaction markers are unbalanced: {counts['B']} begins, {counts['C']} commits"
            )

    for action, minimum in policy.minimum_actions.items():
        if counts[action] < minimum:
            problems.append(
                f"{ACTION_NAMES[action]} count {counts[action]} is below minimum {minimum}"
            )
    missing_tables = allowed_tables - seen_tables
    if missing_tables:
        problems.append(
            "configured tables absent from stream: "
            + ", ".join(sorted(table.qualified for table in missing_tables))
        )
    if committed_xids != sorted(set(committed_xids)):
        problems.append("committed transaction identifiers are duplicate or out of order")

    if slot.slot_name != policy.slot:
        problems.append(f"slot name {slot.slot_name!r} does not match {policy.slot!r}")
    if slot.plugin != "wal2json":
        problems.append(f"slot plugin is {slot.plugin!r}, expected 'wal2json'")
    if slot.slot_type != "logical":
        problems.append(f"slot type is {slot.slot_type!r}, expected 'logical'")
    if slot.database != policy.database:
        problems.append(
            f"slot database {slot.database!r} does not match {policy.database!r}"
        )
    if slot.active:
        problems.append("slot remains active after SQL consumption")
    if slot.retained_bytes > policy.max_slot_lag_bytes:
        problems.append(
            f"slot retains {slot.retained_bytes} bytes, policy allows "
            f"{policy.max_slot_lag_bytes}"
        )

    report = {
        "passed": not problems,
        "event_count": len(events),
        "transaction_count": transaction_count,
        "action_counts": {
            ACTION_NAMES[action]: counts[action]
            for action in ("B", "I", "U", "D", "T", "C", "M")
        },
        "tables": sorted(table.qualified for table in seen_tables),
        "xids": _xid_sequence(events),
        "unique_fingerprints": len(set(fingerprints)),
        "slot": slot.as_dict(),
        "policy": policy.public_dict(),
        "problems": problems,
    }
    if problems:
        raise AuditFailure(problems, report)
    return report


def write_json(path: pathlib.Path, document: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    temporary.replace(path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate and audit the IvorySQL wal2json CDC contract"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    preflight = subparsers.add_parser("preflight", help="validate environment policy")
    preflight.add_argument("--json", action="store_true", dest="as_json")
    options = subparsers.add_parser("options", help="print wal2json option pairs")
    options.add_argument("--json", action="store_true", dest="as_json")
    audit_parser = subparsers.add_parser("audit", help="audit JSONL events and slot")
    audit_parser.add_argument("--events", type=pathlib.Path, required=True)
    audit_parser.add_argument("--slot-metrics", type=pathlib.Path, required=True)
    audit_parser.add_argument("--output", type=pathlib.Path, required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        policy = CdcPolicy.from_environment()
        if args.command == "preflight":
            if args.as_json:
                print(json.dumps(policy.public_dict(), indent=2, sort_keys=True))
            else:
                print(
                    f"CDC policy valid for {policy.slot}: "
                    + ", ".join(table.qualified for table in policy.tables)
                )
            return 0
        if args.command == "options":
            if args.as_json:
                print(json.dumps(policy.plugin_options()))
            else:
                for key, value in policy.plugin_options():
                    print(f"{key}={value}")
            return 0
        if args.command == "audit":
            events = read_events(args.events)
            slot = read_slot_metrics(args.slot_metrics)
            try:
                report = audit(policy, events, slot)
            except AuditFailure as exc:
                write_json(args.output, exc.report)
                raise
            write_json(args.output, report)
            print(json.dumps(report, indent=2, sort_keys=True))
            return 0
        parser.error(f"unknown command {args.command}")
    except ConfigurationError as exc:
        print(f"configuration error: {exc}", file=sys.stderr)
        return 2
    except ParseError as exc:
        print(f"parse error: {exc}", file=sys.stderr)
        return 2
    except AuditFailure as exc:
        for problem in exc.problems:
            print(f"audit failure: {problem}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
