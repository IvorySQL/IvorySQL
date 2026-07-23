from __future__ import annotations

import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from dataclasses import replace
from decimal import Decimal
from pathlib import Path

import repack_harness as harness


MIB = 1024 * 1024


def valid_environment(**overrides: str) -> dict[str, str]:
    values = {
        "IVORYSQL_DATABASE": "maintenancedb",
        "IVORYSQL_USER": "ivorysql",
        "IVORYSQL_PASSWORD": "ivorysql-repack-ci-password",
        "REPACK_SCHEMA": "maintenance",
        "REPACK_TABLE": "orders",
        "REPACK_INITIAL_ROWS": "24000",
        "REPACK_DELETE_PERCENT": "75",
        "REPACK_PAYLOAD_BYTES": "1024",
        "REPACK_MIN_BEFORE_SIZE": "8MiB",
        "REPACK_MIN_SAVED_BYTES": "4MiB",
        "REPACK_MAX_FINAL_RATIO": "0.55",
        "REPACK_CONCURRENT_WRITES": "40",
        "REPACK_MIN_CONCURRENT_WRITES": "30",
        "REPACK_MAX_WRITE_LATENCY": "5s",
        "REPACK_WAIT_TIMEOUT": "60",
        "REPACK_REPORT_DIR": "/var/lib/ivorysql/reports",
    }
    values.update(overrides)
    return values


def valid_policy(**overrides: str) -> harness.RepackPolicy:
    return harness.RepackPolicy.from_environment(valid_environment(**overrides))


def before_metrics(**overrides: object) -> harness.RelationMetrics:
    values = {
        "total_size": 16 * MIB,
        "heap_size": 12 * MIB,
        "index_size": 3 * MIB,
        "row_count": 6000,
        "stable_rows": 6000,
        "stable_checksum": "0123456789abcdef0123456789abcdef",
        "index_count": 3,
        "indexes_healthy": True,
        "extension_version": "1.5.3",
        "server_version": "IvorySQL 5.4 on x86_64-pc-linux-gnu",
    }
    values.update(overrides)
    return harness.RelationMetrics(**values)


def after_metrics(**overrides: object) -> harness.RelationMetrics:
    values = {
        "total_size": 5 * MIB,
        "heap_size": 3 * MIB,
        "index_size": 1 * MIB,
        "row_count": 6040,
        "stable_rows": 6000,
        "stable_checksum": "0123456789abcdef0123456789abcdef",
        "index_count": 3,
        "indexes_healthy": True,
        "extension_version": "1.5.3",
        "server_version": "IvorySQL 5.4 on x86_64-pc-linux-gnu",
    }
    values.update(overrides)
    return harness.RelationMetrics(**values)


def writer_metrics(**overrides: int) -> harness.WriterMetrics:
    values = {
        "started_ms": 1000,
        "finished_ms": 5000,
        "attempted": 40,
        "succeeded": 40,
        "errors": 0,
        "max_latency_ms": 100,
    }
    values.update(overrides)
    return harness.WriterMetrics(**values)


def execution_metrics(**overrides: int) -> harness.ExecutionMetrics:
    values = {
        "started_ms": 2000,
        "finished_ms": 4000,
        "exit_code": 0,
    }
    values.update(overrides)
    return harness.ExecutionMetrics(**values)


def check_map(report: harness.AuditReport) -> dict[str, harness.Finding]:
    return {check.code: check for check in report.checks}


class ScalarParserTests(unittest.TestCase):
    def test_parse_integer_accepts_bounds(self) -> None:
        self.assertEqual(harness.parse_integer("10", "VALUE", minimum=10, maximum=10), 10)

    def test_parse_integer_rejects_negative(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "non-negative"):
            harness.parse_integer("-1", "VALUE")

    def test_parse_integer_rejects_sign(self) -> None:
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_integer("+1", "VALUE")

    def test_parse_integer_rejects_fraction(self) -> None:
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_integer("1.5", "VALUE")

    def test_parse_integer_rejects_low_value(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "at least 2"):
            harness.parse_integer("1", "VALUE", minimum=2)

    def test_parse_integer_rejects_high_value(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "at most 2"):
            harness.parse_integer("3", "VALUE", maximum=2)

    def test_parse_size_supports_all_units(self) -> None:
        cases = {"7B": 7, "2KiB": 2048, "3MiB": 3 * MIB, "1GiB": 1024 * MIB}
        for value, expected in cases.items():
            with self.subTest(value=value):
                self.assertEqual(harness.parse_size(value, "SIZE"), expected)

    def test_parse_size_is_case_insensitive(self) -> None:
        self.assertEqual(harness.parse_size("8mib", "SIZE"), 8 * MIB)

    def test_parse_size_requires_iec_unit(self) -> None:
        for value in ("8", "8MB", "8 MiB", "-8MiB", "1.5MiB"):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                harness.parse_size(value, "SIZE")

    def test_parse_duration_supports_units(self) -> None:
        cases = {"250ms": 250, "1.5s": 1500, "2m": 120000}
        for value, expected in cases.items():
            with self.subTest(value=value):
                self.assertEqual(harness.parse_duration_ms(value, "DURATION"), expected)

    def test_parse_duration_rejects_fractional_millisecond(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "whole milliseconds"):
            harness.parse_duration_ms("0.0001s", "DURATION")

    def test_parse_duration_rejects_zero(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "greater than zero"):
            harness.parse_duration_ms("0s", "DURATION")

    def test_parse_duration_requires_unit(self) -> None:
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_duration_ms("5000", "DURATION")

    def test_parse_ratio_accepts_operational_edges(self) -> None:
        self.assertEqual(harness.parse_ratio("0.10", "RATIO"), Decimal("0.10"))
        self.assertEqual(harness.parse_ratio("0.95", "RATIO"), Decimal("0.95"))

    def test_parse_ratio_rejects_outside_range(self) -> None:
        for value in ("0.09", "0.951", "-1", "2"):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                harness.parse_ratio(value, "RATIO")

    def test_parse_ratio_rejects_non_finite(self) -> None:
        for value in ("NaN", "Infinity", "-Infinity"):
            with self.subTest(value=value), self.assertRaisesRegex(
                harness.ConfigurationError, "finite"
            ):
                harness.parse_ratio(value, "RATIO")

    def test_parse_identifier_accepts_quoted_safe_characters(self) -> None:
        for value in ("orders", "Orders_2026", "tenant$data"):
            with self.subTest(value=value):
                self.assertEqual(harness.parse_identifier(value, "NAME"), value)

    def test_parse_identifier_rejects_sql_fragments(self) -> None:
        for value in ("orders;drop", "two words", "a.b", 'a"b', "1table"):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                harness.parse_identifier(value, "NAME")

    def test_parse_identifier_rejects_postgresql_truncation(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "63-byte"):
            harness.parse_identifier("a" * 64, "NAME")

    def test_parse_report_dir_accepts_scoped_absolute_path(self) -> None:
        value = "/var/lib/ivorysql/reports"
        self.assertEqual(harness.parse_report_dir(value), value)

    def test_parse_report_dir_rejects_relative_path(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "absolute"):
            harness.parse_report_dir("var/lib/reports")

    def test_parse_report_dir_rejects_broad_paths(self) -> None:
        for value in ("/", "/tmp", "/var", "/one"):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                harness.parse_report_dir(value)


class PolicyTests(unittest.TestCase):
    def test_valid_policy_contains_expected_values(self) -> None:
        policy = valid_policy()
        self.assertEqual(policy.schema, "maintenance")
        self.assertEqual(policy.table, "orders")
        self.assertEqual(policy.minimum_saved_bytes, 4 * MIB)
        self.assertEqual(policy.maximum_write_latency_ms, 5000)

    def test_public_policy_redacts_password_and_serializes_decimal(self) -> None:
        public = valid_policy().public_dict()
        self.assertNotIn("password", public)
        self.assertEqual(public["maximum_final_ratio"], "0.55")

    def test_environment_defaults_are_applied(self) -> None:
        policy = harness.RepackPolicy.from_environment(
            {"IVORYSQL_PASSWORD": "sixteen-characters"}
        )
        self.assertEqual(policy.database, "maintenancedb")
        self.assertEqual(policy.concurrent_writes, 40)

    def test_missing_password_is_rejected(self) -> None:
        environment = valid_environment()
        del environment["IVORYSQL_PASSWORD"]
        with self.assertRaisesRegex(harness.ConfigurationError, "required"):
            harness.RepackPolicy.from_environment(environment)

    def test_weak_password_is_rejected(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "16 characters"):
            valid_policy(IVORYSQL_PASSWORD="too-short")

    def test_control_characters_are_rejected(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "control"):
            valid_policy(IVORYSQL_PASSWORD="long-enough-value\nsecond-line")

    def test_system_schemas_are_rejected(self) -> None:
        for schema in ("pg_catalog", "PG_TOAST", "information_schema", "pg_temp_7"):
            with self.subTest(schema=schema), self.assertRaisesRegex(
                harness.ConfigurationError, "system schema"
            ):
                valid_policy(REPACK_SCHEMA=schema)

    def test_schema_and_table_must_be_distinct(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "distinct"):
            valid_policy(REPACK_SCHEMA="orders", REPACK_TABLE="orders")

    def test_initial_rows_bounds(self) -> None:
        for value in ("4999", "2000001"):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                valid_policy(REPACK_INITIAL_ROWS=value)

    def test_delete_percent_bounds(self) -> None:
        for value in ("19", "91"):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                valid_policy(REPACK_DELETE_PERCENT=value)

    def test_payload_bounds(self) -> None:
        for value in ("127", "4097"):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                valid_policy(REPACK_PAYLOAD_BYTES=value)

    def test_saved_floor_must_be_below_baseline_floor(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "smaller"):
            valid_policy(REPACK_MIN_BEFORE_SIZE="8MiB", REPACK_MIN_SAVED_BYTES="8MiB")

    def test_concurrent_write_bounds(self) -> None:
        for value in ("9", "1001"):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                valid_policy(REPACK_CONCURRENT_WRITES=value)

    def test_minimum_writes_cannot_exceed_attempts(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "must not exceed"):
            valid_policy(REPACK_CONCURRENT_WRITES="40", REPACK_MIN_CONCURRENT_WRITES="41")

    def test_wait_timeout_bounds(self) -> None:
        for value in ("0", "301"):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                valid_policy(REPACK_WAIT_TIMEOUT=value)


class EvidenceModelTests(unittest.TestCase):
    def relation_mapping(self, **overrides: object) -> dict[str, object]:
        values = {
            "total_size": 1000,
            "heap_size": 600,
            "index_size": 300,
            "row_count": 100,
            "stable_rows": 90,
            "stable_checksum": "0123456789abcdef0123456789abcdef",
            "index_count": 3,
            "indexes_healthy": True,
            "extension_version": "1.5.3",
            "server_version": "IvorySQL test",
        }
        values.update(overrides)
        return values

    def test_relation_metrics_parse_valid_object(self) -> None:
        metrics = harness.RelationMetrics.from_mapping(self.relation_mapping(), "before")
        self.assertEqual(metrics.row_count, 100)
        self.assertTrue(metrics.indexes_healthy)

    def test_relation_metrics_require_integer_not_boolean(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "must be an integer"):
            harness.RelationMetrics.from_mapping(
                self.relation_mapping(total_size=True), "before"
            )

    def test_relation_metrics_reject_negative_size(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "at least 0"):
            harness.RelationMetrics.from_mapping(
                self.relation_mapping(index_size=-1), "before"
            )

    def test_relation_metrics_reject_heap_larger_than_total(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "heap_size exceeds"):
            harness.RelationMetrics.from_mapping(
                self.relation_mapping(heap_size=1001), "before"
            )

    def test_relation_metrics_reject_indexes_larger_than_total(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "index_size exceeds"):
            harness.RelationMetrics.from_mapping(
                self.relation_mapping(index_size=1001), "before"
            )

    def test_relation_metrics_reject_stable_rows_larger_than_total_rows(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "stable_rows exceeds"):
            harness.RelationMetrics.from_mapping(
                self.relation_mapping(stable_rows=101), "before"
            )

    def test_relation_metrics_require_strict_md5(self) -> None:
        for checksum in ("ABCDEF0123456789ABCDEF0123456789", "short", "z" * 32):
            with self.subTest(checksum=checksum), self.assertRaisesRegex(
                harness.EvidenceError, "lowercase MD5"
            ):
                harness.RelationMetrics.from_mapping(
                    self.relation_mapping(stable_checksum=checksum), "before"
                )

    def test_writer_metrics_parse_valid_object(self) -> None:
        metrics = harness.WriterMetrics.from_mapping(
            {
                "started_ms": 1,
                "finished_ms": 2,
                "attempted": 4,
                "succeeded": 3,
                "errors": 1,
                "max_latency_ms": 10,
            }
        )
        self.assertEqual(metrics.succeeded, 3)

    def test_writer_metrics_reject_reverse_timeline(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "precedes"):
            harness.WriterMetrics.from_mapping(
                {
                    "started_ms": 10,
                    "finished_ms": 9,
                    "attempted": 1,
                    "succeeded": 1,
                    "errors": 0,
                    "max_latency_ms": 1,
                }
            )

    def test_writer_metrics_require_complete_outcomes(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "outcomes"):
            harness.WriterMetrics.from_mapping(
                {
                    "started_ms": 1,
                    "finished_ms": 2,
                    "attempted": 3,
                    "succeeded": 1,
                    "errors": 1,
                    "max_latency_ms": 1,
                }
            )

    def test_execution_metrics_reject_reverse_timeline(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "precedes"):
            harness.ExecutionMetrics.from_mapping(
                {"started_ms": 20, "finished_ms": 10, "exit_code": 0}
            )

    def test_load_json_accepts_object(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "evidence.json")
            path.write_text('{"value": 1}', encoding="utf-8")
            self.assertEqual(harness.load_json(path, "evidence"), {"value": 1})

    def test_load_json_rejects_array(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "evidence.json")
            path.write_text("[]", encoding="utf-8")
            with self.assertRaisesRegex(harness.EvidenceError, "one JSON object"):
                harness.load_json(path, "evidence")

    def test_load_json_rejects_empty_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "evidence.json")
            path.touch()
            with self.assertRaisesRegex(harness.EvidenceError, "empty"):
                harness.load_json(path, "evidence")

    def test_load_json_rejects_oversized_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "evidence.json")
            path.write_bytes(b"x" * (1024 * 1024 + 1))
            with self.assertRaisesRegex(harness.EvidenceError, "1 MiB"):
                harness.load_json(path, "evidence")


class AuditTests(unittest.TestCase):
    def audit(
        self,
        *,
        policy: harness.RepackPolicy | None = None,
        before: harness.RelationMetrics | None = None,
        after: harness.RelationMetrics | None = None,
        writer: harness.WriterMetrics | None = None,
        execution: harness.ExecutionMetrics | None = None,
    ) -> harness.AuditReport:
        return harness.audit(
            policy or valid_policy(),
            before or before_metrics(),
            after or after_metrics(),
            writer or writer_metrics(),
            execution or execution_metrics(),
        )

    def assert_only_failed(self, report: harness.AuditReport, *codes: str) -> None:
        failures = {check.code for check in report.checks if not check.passed}
        self.assertEqual(failures, set(codes))
        self.assertFalse(report.passed)

    def test_valid_audit_passes_all_checks(self) -> None:
        report = self.audit()
        self.assertTrue(report.passed)
        self.assertTrue(all(check.passed for check in report.checks))
        self.assertEqual(report.target, "maintenance.orders")
        self.assertEqual(report.reclaimed_bytes, 11 * MIB)
        self.assertEqual(report.final_ratio, "0.3125")
        self.assertEqual(report.evidence["overlap_ms"], 2000)

    def test_nonzero_repack_exit_fails(self) -> None:
        report = self.audit(execution=execution_metrics(exit_code=2))
        self.assert_only_failed(report, "repack-exit")

    def test_small_fixture_fails(self) -> None:
        report = self.audit(
            before=before_metrics(total_size=7 * MIB, heap_size=4 * MIB),
            after=after_metrics(total_size=2 * MIB, heap_size=MIB),
        )
        self.assert_only_failed(report, "minimum-before-size")

    def test_insufficient_reclaimed_bytes_fails(self) -> None:
        report = self.audit(after=after_metrics(total_size=13 * MIB, heap_size=9 * MIB))
        self.assert_only_failed(
            report, "minimum-reclaimed-bytes", "maximum-final-ratio"
        )

    def test_final_ratio_policy_fails_independently(self) -> None:
        policy = valid_policy(REPACK_MIN_SAVED_BYTES="1MiB", REPACK_MAX_FINAL_RATIO="0.50")
        report = self.audit(policy=policy, after=after_metrics(total_size=9 * MIB))
        self.assert_only_failed(report, "maximum-final-ratio")

    def test_stable_row_loss_fails(self) -> None:
        report = self.audit(after=after_metrics(stable_rows=5999))
        self.assert_only_failed(report, "stable-row-count")

    def test_stable_data_change_fails(self) -> None:
        report = self.audit(
            after=after_metrics(stable_checksum="fedcba9876543210fedcba9876543210")
        )
        self.assert_only_failed(report, "stable-row-checksum")

    def test_unexpected_final_rows_fail(self) -> None:
        report = self.audit(after=after_metrics(row_count=6039))
        self.assert_only_failed(report, "final-row-count")

    def test_writer_attempt_count_must_match_policy(self) -> None:
        report = self.audit(writer=writer_metrics(attempted=39, succeeded=39))
        self.assert_only_failed(report, "final-row-count", "writer-attempt-count")

    def test_writer_success_floor_fails(self) -> None:
        report = self.audit(
            after=after_metrics(row_count=6029),
            writer=writer_metrics(succeeded=29, errors=11),
        )
        self.assert_only_failed(report, "writer-success-floor", "writer-errors")

    def test_writer_errors_fail(self) -> None:
        report = self.audit(
            after=after_metrics(row_count=6039),
            writer=writer_metrics(succeeded=39, errors=1),
        )
        self.assert_only_failed(report, "writer-errors")

    def test_writer_latency_fails(self) -> None:
        report = self.audit(writer=writer_metrics(max_latency_ms=5001))
        self.assert_only_failed(report, "writer-latency")

    def test_disjoint_timeline_fails(self) -> None:
        report = self.audit(writer=writer_metrics(started_ms=5000, finished_ms=9000))
        self.assert_only_failed(report, "timeline-overlap")

    def test_touching_timeline_is_not_overlap(self) -> None:
        report = self.audit(writer=writer_metrics(started_ms=4000, finished_ms=8000))
        self.assert_only_failed(report, "timeline-overlap")

    def test_missing_index_coverage_fails(self) -> None:
        report = self.audit(
            before=before_metrics(index_count=2), after=after_metrics(index_count=2)
        )
        self.assert_only_failed(report, "index-count-before")

    def test_index_loss_fails(self) -> None:
        report = self.audit(after=after_metrics(index_count=2))
        self.assert_only_failed(report, "index-count-preserved")

    def test_invalid_baseline_index_fails(self) -> None:
        report = self.audit(before=before_metrics(indexes_healthy=False))
        self.assert_only_failed(report, "indexes-healthy-before")

    def test_invalid_rebuilt_index_fails(self) -> None:
        report = self.audit(after=after_metrics(indexes_healthy=False))
        self.assert_only_failed(report, "indexes-healthy-after")

    def test_wrong_pinned_extension_version_fails(self) -> None:
        report = self.audit(
            before=before_metrics(extension_version="1.5.2"),
            after=after_metrics(extension_version="1.5.2"),
        )
        self.assert_only_failed(report, "extension-version-before")

    def test_extension_version_change_fails(self) -> None:
        report = self.audit(after=after_metrics(extension_version="1.5.4"))
        self.assert_only_failed(report, "extension-version-preserved")

    def test_non_ivorysql_baseline_fails(self) -> None:
        report = self.audit(before=before_metrics(server_version="PostgreSQL 18"))
        self.assert_only_failed(report, "ivorysql-server-before", "server-version-preserved")

    def test_server_change_fails(self) -> None:
        report = self.audit(after=after_metrics(server_version="IvorySQL changed"))
        self.assert_only_failed(report, "server-version-preserved")

    def test_report_dict_is_json_serializable(self) -> None:
        encoded = json.dumps(self.audit().as_dict(), sort_keys=True)
        decoded = json.loads(encoded)
        self.assertTrue(decoded["passed"])
        self.assertEqual(len(decoded["checks"]), 20)


class FileAndCliTests(unittest.TestCase):
    def write_evidence(self, directory: Path) -> dict[str, Path]:
        documents = {
            "before": before_metrics(),
            "after": after_metrics(),
            "writer": writer_metrics(),
            "execution": execution_metrics(),
        }
        paths: dict[str, Path] = {}
        for name, document in documents.items():
            path = directory / f"{name}.json"
            path.write_text(json.dumps(document.__dict__), encoding="utf-8")
            paths[name] = path
        return paths

    def audit_arguments(self, paths: dict[str, Path], output: Path) -> list[str]:
        return [
            "audit",
            "--before",
            str(paths["before"]),
            "--after",
            str(paths["after"]),
            "--writer",
            str(paths["writer"]),
            "--execution",
            str(paths["execution"]),
            "--output",
            str(output),
        ]

    def test_atomic_write_creates_parent_and_newline(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory, "nested", "report.json")
            harness.atomic_write_json(output, {"passed": True})
            self.assertTrue(output.exists())
            self.assertTrue(output.read_bytes().endswith(b"\n"))
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), {"passed": True})

    def test_atomic_write_replaces_existing_document(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory, "report.json")
            output.write_text('{"old": true}', encoding="utf-8")
            harness.atomic_write_json(output, {"new": True})
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), {"new": True})

    def test_preflight_cli_succeeds_and_redacts_password(self) -> None:
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            result = harness.run(["preflight"], valid_environment())
        self.assertEqual(result, 0)
        payload = json.loads(stdout.getvalue())
        self.assertTrue(payload["valid"])
        self.assertNotIn("password", payload["policy"])

    def test_preflight_cli_returns_two_for_bad_configuration(self) -> None:
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            result = harness.run(
                ["preflight"], valid_environment(REPACK_SCHEMA="pg_catalog")
            )
        self.assertEqual(result, 2)
        self.assertIn("system schema", stderr.getvalue())

    def test_audit_cli_writes_passing_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            paths = self.write_evidence(directory)
            output = directory / "audit.json"
            with redirect_stdout(io.StringIO()):
                result = harness.run(
                    self.audit_arguments(paths, output), valid_environment()
                )
            self.assertEqual(result, 0)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertTrue(report["passed"])
            self.assertNotIn("password", report["policy"])

    def test_audit_cli_returns_one_and_writes_failure_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            paths = self.write_evidence(directory)
            execution = json.loads(paths["execution"].read_text(encoding="utf-8"))
            execution["exit_code"] = 1
            paths["execution"].write_text(json.dumps(execution), encoding="utf-8")
            output = directory / "audit.json"
            with redirect_stdout(io.StringIO()):
                result = harness.run(
                    self.audit_arguments(paths, output), valid_environment()
                )
            self.assertEqual(result, 1)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertFalse(report["passed"])

    def test_audit_cli_returns_two_for_missing_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            paths = self.write_evidence(directory)
            paths["before"].unlink()
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                result = harness.run(
                    self.audit_arguments(paths, directory / "audit.json"),
                    valid_environment(),
                )
            self.assertEqual(result, 2)
            self.assertIn("cannot read before", stderr.getvalue())

    def test_audit_cli_does_not_overwrite_output_on_parse_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            paths = self.write_evidence(directory)
            paths["after"].write_text("not-json", encoding="utf-8")
            output = directory / "audit.json"
            output.write_text('{"previous": true}', encoding="utf-8")
            with redirect_stderr(io.StringIO()):
                result = harness.run(
                    self.audit_arguments(paths, output), valid_environment()
                )
            self.assertEqual(result, 2)
            self.assertEqual(
                json.loads(output.read_text(encoding="utf-8")), {"previous": True}
            )


if __name__ == "__main__":
    unittest.main()
