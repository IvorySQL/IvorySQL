from __future__ import annotations

import contextlib
import datetime as dt
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "partition_harness.py"
SPEC = importlib.util.spec_from_file_location("partition_harness", MODULE_PATH)
assert SPEC and SPEC.loader
harness = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = harness
SPEC.loader.exec_module(harness)


UTC = dt.timezone.utc
NOW = dt.datetime(2026, 7, 22, 10, 30, tzinfo=UTC)


def valid_env(**overrides: str) -> dict[str, str]:
    result = {
        "IVORYSQL_HOST": "database",
        "IVORYSQL_PORT": "5333",
        "IVORYSQL_DATABASE": "partitiondb",
        "IVORYSQL_SUPERUSER": "ivorysql",
        "IVORYSQL_SUPERUSER_PASSWORD": "superuser-password",
        "PARTMAN_OWNER": "partition_owner",
        "PARTMAN_OWNER_PASSWORD": "partition-owner-password",
        "PARTMAN_EXTENSION_SCHEMA": "partman",
        "PARTMAN_SCHEMA": "app",
        "PARTMAN_TABLE": "events",
        "PARTMAN_CONTROL_COLUMN": "created_at",
        "PARTMAN_INTERVAL": "1 day",
        "PARTMAN_PREMAKE": "7",
        "PARTMAN_RETENTION_DAYS": "90",
        "PARTMAN_RETENTION_KEEP_TABLE": "false",
        "PARTMAN_RETENTION_KEEP_INDEX": "true",
        "PARTMAN_INFINITE_TIME_PARTITIONS": "true",
        "PARTMAN_AUTOMATIC_MAINTENANCE": "true",
        "PARTMAN_DEFAULT_PARTITION": "true",
        "PARTMAN_DEFAULT_ROW_LIMIT": "0",
        "PARTMAN_BGW_INTERVAL": "60",
        "PARTMAN_MAINTENANCE_ANALYZE": "false",
        "PARTMAN_HISTORY_INTERVALS": "2",
    }
    result.update(overrides)
    return result


def record(
    name: str,
    start: dt.datetime | None,
    end: dt.datetime | None,
    *,
    rows: int = 0,
    size: int = 8192,
    default: bool = False,
) -> harness.PartitionRecord:
    return harness.PartitionRecord("app", name, start, end, size, rows, default)


def healthy_records(spec: harness.RuntimeSpec, now: dt.datetime = NOW) -> list[harness.PartitionRecord]:
    plan = harness.build_plan(spec.policy, now=now)
    records = [
        record(f"events_p{index:04d}", start, end, rows=100)
        for index, (start, end) in enumerate(plan.required_boundaries)
    ]
    records.append(record("events_default", None, None, default=True))
    return records


def records_csv(records: list[harness.PartitionRecord]) -> str:
    output = io.StringIO()
    output.write(
        "schema_name,table_name,range_start,range_end,total_bytes,estimated_rows,is_default\n"
    )
    for item in records:
        output.write(
            ",".join(
                (
                    item.schema_name,
                    item.table_name,
                    item.range_start.isoformat() if item.range_start else "",
                    item.range_end.isoformat() if item.range_end else "",
                    str(item.total_bytes),
                    str(item.estimated_rows),
                    "true" if item.is_default else "false",
                )
            )
            + "\n"
        )
    return output.getvalue()


class ParsingTests(unittest.TestCase):
    def test_parse_int_and_bounds(self) -> None:
        self.assertEqual(harness.parse_int("7", name="count", minimum=1), 7)
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_int("many", name="count")
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_int("0", name="count", minimum=1)
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_int("8", name="count", maximum=7)

    def test_parse_bool(self) -> None:
        for raw in ("true", "yes", "1", "on"):
            self.assertTrue(harness.parse_bool(raw, name="flag"))
        for raw in ("false", "no", "0", "off"):
            self.assertFalse(harness.parse_bool(raw, name="flag"))
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_bool("maybe", name="flag")

    def test_identifier(self) -> None:
        self.assertEqual(harness.identifier("event_table", name="table"), "event_table")
        for raw in ("9table", "table-name", "table;drop", "a" * 64):
            with self.subTest(raw=raw):
                with self.assertRaises(harness.ConfigurationError):
                    harness.identifier(raw, name="table")

    def test_quote_literal(self) -> None:
        self.assertEqual(harness.quote_literal("owner's"), "'owner''s'")
        with self.assertRaises(harness.ConfigurationError):
            harness.quote_literal("bad\x00value")

    def test_parse_timestamp(self) -> None:
        self.assertEqual(harness.parse_timestamp("2026-07-22T10:00:00Z"), NOW.replace(minute=0))
        naive = harness.parse_timestamp("2026-07-22T10:00:00")
        self.assertEqual(naive.tzinfo, UTC)
        with self.assertRaises(harness.AuditError):
            harness.parse_timestamp("not-a-time")


class BoundaryTests(unittest.TestCase):
    def test_floor_hour(self) -> None:
        self.assertEqual(
            harness.floor_boundary(NOW, harness.IntervalKind.HOUR),
            dt.datetime(2026, 7, 22, 10, tzinfo=UTC),
        )

    def test_floor_day(self) -> None:
        self.assertEqual(
            harness.floor_boundary(NOW, harness.IntervalKind.DAY),
            dt.datetime(2026, 7, 22, tzinfo=UTC),
        )

    def test_floor_week_starts_monday(self) -> None:
        self.assertEqual(
            harness.floor_boundary(NOW, harness.IntervalKind.WEEK),
            dt.datetime(2026, 7, 20, tzinfo=UTC),
        )

    def test_floor_month(self) -> None:
        self.assertEqual(
            harness.floor_boundary(NOW, harness.IntervalKind.MONTH),
            dt.datetime(2026, 7, 1, tzinfo=UTC),
        )

    def test_add_fixed_intervals(self) -> None:
        self.assertEqual(
            harness.add_intervals(NOW, 2, harness.IntervalKind.HOUR),
            NOW + dt.timedelta(hours=2),
        )
        self.assertEqual(
            harness.add_intervals(NOW, -2, harness.IntervalKind.DAY),
            NOW - dt.timedelta(days=2),
        )
        self.assertEqual(
            harness.add_intervals(NOW, 2, harness.IntervalKind.WEEK),
            NOW + dt.timedelta(weeks=2),
        )

    def test_add_month_handles_short_month(self) -> None:
        january_end = dt.datetime(2024, 1, 31, tzinfo=UTC)
        self.assertEqual(
            harness.add_intervals(january_end, 1, harness.IntervalKind.MONTH),
            dt.datetime(2024, 2, 29, tzinfo=UTC),
        )
        self.assertEqual(
            harness.add_intervals(january_end, 12, harness.IntervalKind.MONTH),
            dt.datetime(2025, 1, 31, tzinfo=UTC),
        )

    def test_interval_count(self) -> None:
        span = dt.timedelta(days=14)
        self.assertEqual(harness.interval_count(span, harness.IntervalKind.HOUR), 336)
        self.assertEqual(harness.interval_count(span, harness.IntervalKind.DAY), 14)
        self.assertEqual(harness.interval_count(span, harness.IntervalKind.WEEK), 2)
        self.assertGreaterEqual(harness.interval_count(span, harness.IntervalKind.MONTH), 1)


class RuntimeSpecTests(unittest.TestCase):
    def test_default_spec(self) -> None:
        spec = harness.RuntimeSpec.from_env(valid_env())
        self.assertEqual(spec.connection.database, "partitiondb")
        self.assertEqual(spec.policy.parent, "app.events")
        self.assertEqual(spec.policy.interval, harness.IntervalKind.DAY)
        self.assertEqual(spec.policy.premake, 7)
        self.assertEqual(spec.policy.retention_sql, "90 days")

    def test_owner_must_not_be_superuser(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "non-superuser"):
            harness.RuntimeSpec.from_env(valid_env(PARTMAN_OWNER="ivorysql"))

    def test_password_lengths(self) -> None:
        for variable in ("IVORYSQL_SUPERUSER_PASSWORD", "PARTMAN_OWNER_PASSWORD"):
            with self.subTest(variable=variable):
                with self.assertRaisesRegex(harness.ConfigurationError, "at least 12"):
                    harness.RuntimeSpec.from_env(valid_env(**{variable: "short"}))

    def test_interval_choices(self) -> None:
        for interval in harness.IntervalKind:
            spec = harness.RuntimeSpec.from_env(valid_env(PARTMAN_INTERVAL=interval.value))
            self.assertEqual(spec.policy.interval, interval)
        with self.assertRaisesRegex(harness.ConfigurationError, "must be one of"):
            harness.RuntimeSpec.from_env(valid_env(PARTMAN_INTERVAL="2 days"))

    def test_retention_must_cover_history(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "retention must cover"):
            harness.RuntimeSpec.from_env(
                valid_env(PARTMAN_RETENTION_DAYS="1", PARTMAN_HISTORY_INTERVALS="2")
            )

    def test_background_interval_minimum(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "at least 15"):
            harness.RuntimeSpec.from_env(valid_env(PARTMAN_BGW_INTERVAL="14"))

    def test_default_row_limit_cannot_be_negative(self) -> None:
        with self.assertRaises(harness.ConfigurationError):
            harness.RuntimeSpec.from_env(valid_env(PARTMAN_DEFAULT_ROW_LIMIT="-1"))

    def test_invalid_identifier_is_rejected(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "SQL identifier"):
            harness.RuntimeSpec.from_env(valid_env(PARTMAN_TABLE="events;drop"))


class RenderingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.RuntimeSpec.from_env(valid_env())

    def test_install_sql_creates_declarative_parent(self) -> None:
        text = harness.render_install_sql(self.spec, now=NOW)
        self.assertIn("CREATE EXTENSION IF NOT EXISTS pg_partman", text)
        self.assertIn("CREATE TABLE IF NOT EXISTS app.events", text)
        self.assertIn("PARTITION BY RANGE (created_at)", text)
        self.assertIn("PRIMARY KEY (event_id, created_at)", text)
        self.assertIn("partman.create_parent", text)
        self.assertIn("p_interval := '1 day'", text)
        self.assertIn("p_premake := 7", text)

    def test_install_sql_configures_retention_and_maintenance(self) -> None:
        text = harness.render_install_sql(self.spec, now=NOW)
        self.assertIn("retention = '90 days'", text)
        self.assertIn("retention_keep_table = false", text)
        self.assertIn("infinite_time_partitions = true", text)
        self.assertIn("run_maintenance_proc", text)
        self.assertIn("p_jobmon := false", text)

    def test_inventory_sql_uses_partman_boundaries(self) -> None:
        text = harness.render_inventory_sql(self.spec)
        self.assertIn("partman.show_partitions", text)
        self.assertIn("partman.show_partition_info", text)
        self.assertIn("pg_total_relation_size", text)
        self.assertIn("events_default", text)

    def test_maintenance_sql_keeps_procedure_outside_a_transaction_block(self) -> None:
        text = harness.render_maintenance_sql(self.spec)
        self.assertIn("run_maintenance_proc", text)
        self.assertNotIn("SET ", text)

    def test_workload_sql(self) -> None:
        text = harness.render_workload_sql(self.spec, 100)
        self.assertIn("INSERT INTO app.events", text)
        self.assertIn("generate_series(1, 100)", text)
        self.assertIn("random() * interval '48 hours'", text)
        with self.assertRaises(harness.ConfigurationError):
            harness.render_workload_sql(self.spec, 0)
        with self.assertRaises(harness.ConfigurationError):
            harness.render_workload_sql(self.spec, 10_000_001)

    def test_write_sql_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = harness.write_sql_files(self.spec, pathlib.Path(directory))
            self.assertEqual(len(paths), 4)
            self.assertEqual(
                {path.name for path in paths},
                {"install.sql", "inventory.sql", "maintenance.sql", "workload.sql"},
            )


class InventoryParsingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.RuntimeSpec.from_env(valid_env())

    def test_parse_inventory(self) -> None:
        parsed = harness.parse_inventory(records_csv(healthy_records(self.spec)))
        self.assertGreater(len(parsed), 90)
        self.assertEqual(parsed[0].schema_name, "app")
        self.assertEqual(parsed[-1].table_name, "events_default")
        self.assertTrue(parsed[-1].is_default)

    def test_qualified_name(self) -> None:
        item = record("events_p1", NOW, NOW + dt.timedelta(days=1))
        self.assertEqual(item.qualified_name, "app.events_p1")

    def test_empty_inventory_fails(self) -> None:
        with self.assertRaises(harness.AuditError):
            harness.parse_inventory("")
        with self.assertRaisesRegex(harness.AuditError, "no records"):
            harness.parse_inventory(
                "schema_name,table_name,range_start,range_end,total_bytes,estimated_rows,is_default\n"
            )

    def test_missing_column_fails(self) -> None:
        with self.assertRaisesRegex(harness.AuditError, "missing columns"):
            harness.parse_inventory("schema_name,table_name\napp,events\n")

    def test_invalid_number_fails(self) -> None:
        raw = records_csv([record("events_p1", NOW, NOW + dt.timedelta(days=1))])
        raw = raw.replace(",8192,0,false", ",many,0,false")
        with self.assertRaisesRegex(harness.AuditError, "invalid partition inventory"):
            harness.parse_inventory(raw)


class PlanningTests(unittest.TestCase):
    def test_daily_plan_includes_retention_and_premake(self) -> None:
        spec = harness.RuntimeSpec.from_env(valid_env())
        plan = harness.build_plan(spec.policy, now=NOW)
        self.assertEqual(plan.current_start, dt.datetime(2026, 7, 22, tzinfo=UTC))
        self.assertEqual(plan.expected_start, dt.datetime(2026, 4, 23, tzinfo=UTC))
        self.assertEqual(plan.expected_end, dt.datetime(2026, 7, 30, tzinfo=UTC))
        self.assertEqual(len(plan.required_boundaries), 98)

    def test_hourly_plan(self) -> None:
        spec = harness.RuntimeSpec.from_env(
            valid_env(
                PARTMAN_INTERVAL="1 hour",
                PARTMAN_RETENTION_DAYS="1",
                PARTMAN_PREMAKE="4",
            )
        )
        plan = harness.build_plan(spec.policy, now=NOW)
        self.assertEqual(len(plan.required_boundaries), 29)
        self.assertEqual(plan.current_start.hour, 10)

    def test_monthly_plan(self) -> None:
        spec = harness.RuntimeSpec.from_env(
            valid_env(
                PARTMAN_INTERVAL="1 month",
                PARTMAN_RETENTION_DAYS="365",
                PARTMAN_PREMAKE="3",
            )
        )
        plan = harness.build_plan(spec.policy, now=NOW)
        self.assertEqual(plan.current_start.day, 1)
        self.assertEqual(plan.expected_end, dt.datetime(2026, 11, 1, tzinfo=UTC))
        self.assertGreaterEqual(len(plan.required_boundaries), 16)


class AuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.RuntimeSpec.from_env(valid_env())

    def test_healthy_inventory_passes(self) -> None:
        self.assertEqual(harness.audit_inventory(self.spec, healthy_records(self.spec), now=NOW), [])

    def test_missing_default_partition_fails(self) -> None:
        records = [item for item in healthy_records(self.spec) if not item.is_default]
        problems = harness.audit_inventory(self.spec, records, now=NOW)
        self.assertIn("configured default partition is missing", problems)

    def test_default_rows_fail(self) -> None:
        records = healthy_records(self.spec)
        records[-1] = record("events_default", None, None, rows=1, default=True)
        problems = harness.audit_inventory(self.spec, records, now=NOW)
        self.assertTrue(any("default partition contains 1 rows" in problem for problem in problems))

    def test_multiple_defaults_fail(self) -> None:
        records = healthy_records(self.spec)
        records.append(record("events_default_2", None, None, default=True))
        problems = harness.audit_inventory(self.spec, records, now=NOW)
        self.assertIn("multiple default partitions were reported", problems)

    def test_no_ranged_partitions_fail(self) -> None:
        problems = harness.audit_inventory(
            self.spec,
            [record("events_default", None, None, default=True)],
            now=NOW,
        )
        self.assertIn("no ranged child partitions were reported", problems)

    def test_gap_fails(self) -> None:
        records = healthy_records(self.spec)
        del records[10]
        problems = harness.audit_inventory(self.spec, records, now=NOW)
        self.assertTrue(any("partition gap" in problem for problem in problems))

    def test_overlap_fails(self) -> None:
        records = healthy_records(self.spec)
        original = records[10]
        records[10] = record(
            original.table_name,
            original.range_start - dt.timedelta(hours=1),
            original.range_end,
        )
        problems = harness.audit_inventory(self.spec, records, now=NOW)
        self.assertTrue(any("partition overlap" in problem for problem in problems))

    def test_missing_future_partition_fails(self) -> None:
        records = healthy_records(self.spec)
        records = records[:-2] + records[-1:]
        problems = harness.audit_inventory(self.spec, records, now=NOW)
        self.assertTrue(any("future partitions are missing" in problem for problem in problems))

    def test_reversed_range_fails(self) -> None:
        records = healthy_records(self.spec)
        original = records[0]
        records[0] = record(original.table_name, original.range_end, original.range_start)
        problems = harness.audit_inventory(self.spec, records, now=NOW)
        self.assertTrue(any("reversed range" in problem for problem in problems))

    def test_negative_statistics_fail(self) -> None:
        records = healthy_records(self.spec)
        original = records[0]
        records[0] = record(original.table_name, original.range_start, original.range_end, size=-1)
        problems = harness.audit_inventory(self.spec, records, now=NOW)
        self.assertTrue(any("negative statistics" in problem for problem in problems))

    def test_expired_partition_fails_when_tables_are_dropped(self) -> None:
        records = healthy_records(self.spec)
        old_end = NOW - dt.timedelta(days=100)
        records.insert(0, record("events_old", old_end - dt.timedelta(days=1), old_end))
        problems = harness.audit_inventory(self.spec, records, now=NOW)
        self.assertTrue(any("older than retention cutoff" in problem for problem in problems))

    def test_retained_expired_table_is_allowed(self) -> None:
        spec = harness.RuntimeSpec.from_env(valid_env(PARTMAN_RETENTION_KEEP_TABLE="true"))
        records = healthy_records(spec)
        old_end = NOW - dt.timedelta(days=100)
        records.insert(0, record("events_old", old_end - dt.timedelta(days=1), old_end))
        problems = harness.audit_inventory(spec, records, now=NOW)
        self.assertFalse(any("older than retention cutoff" in problem for problem in problems))


class FakeRunner:
    def __init__(self, outputs: list[str]) -> None:
        self.outputs = outputs
        self.calls: list[tuple[list[str], dict[str, object]]] = []

    def run(self, command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        self.calls.append((command, kwargs))
        output = self.outputs.pop(0) if self.outputs else ""
        return subprocess.CompletedProcess(command, 0, output, "")


class CommandTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.RuntimeSpec.from_env(valid_env())

    def test_psql_uses_password_environment(self) -> None:
        runner = FakeRunner(["ok"])
        result = harness.psql(self.spec, sql="SELECT 1", runner=runner)
        self.assertEqual(result, "ok")
        command, kwargs = runner.calls[0]
        self.assertIn("--no-psqlrc", command)
        self.assertNotIn(self.spec.connection.superuser_password, command)
        self.assertEqual(kwargs["env"]["PGPASSWORD"], self.spec.connection.superuser_password)

    def test_owner_psql_uses_owner_secret(self) -> None:
        runner = FakeRunner([""])
        harness.psql(self.spec, sql="SELECT 1", owner=True, runner=runner)
        command, kwargs = runner.calls[0]
        self.assertIn(self.spec.connection.owner, command)
        self.assertEqual(kwargs["env"]["PGPASSWORD"], self.spec.connection.owner_password)

    def test_psql_sets_session_options_through_connection_environment(self) -> None:
        runner = FakeRunner([""])
        harness.psql(
            self.spec,
            sql="CALL partman.run_maintenance_proc()",
            session_options={"statement_timeout": "15min", "lock_timeout": "5s"},
            runner=runner,
        )
        _, kwargs = runner.calls[0]
        self.assertEqual(
            kwargs["env"]["PGOPTIONS"],
            "-c statement_timeout=15min -c lock_timeout=5s",
        )

    def test_psql_requires_exactly_one_input(self) -> None:
        with self.assertRaises(ValueError):
            harness.psql(self.spec)
        with self.assertRaises(ValueError):
            harness.psql(self.spec, sql="SELECT 1", file=pathlib.Path("test.sql"))

    def test_preflight(self) -> None:
        result = harness.preflight(self.spec)
        self.assertEqual(result["parent"], "app.events")
        self.assertEqual(result["interval"], "1 day")
        self.assertEqual(len(result["warnings"]), 2)

    def test_plan_cli(self) -> None:
        args = harness.build_parser().parse_args(["plan", "--at", NOW.isoformat()])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            harness.execute(args, self.spec)
        result = json.loads(output.getvalue())
        self.assertEqual(result["partition_count"], 98)

    def test_inventory_cli(self) -> None:
        runner = FakeRunner([records_csv(healthy_records(self.spec))])
        args = harness.build_parser().parse_args(["inventory"])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            harness.execute(args, self.spec, runner)
        result = json.loads(output.getvalue())
        self.assertEqual(result["partition_count"], 98)
        self.assertEqual(result["problems"], [])

    def test_render_cli(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = harness.build_parser().parse_args(["render", "--output", directory])
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                harness.execute(args, self.spec)
            self.assertEqual(len(json.loads(output.getvalue())["rendered"]), 4)

    def test_main_returns_two_for_invalid_environment(self) -> None:
        stderr = io.StringIO()
        with mock.patch.dict(os.environ, valid_env(PARTMAN_INTERVAL="quarter"), clear=True):
            with contextlib.redirect_stderr(stderr):
                result = harness.main(["preflight"])
        self.assertEqual(result, 2)
        self.assertIn("must be one of", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
