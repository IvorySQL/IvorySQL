from __future__ import annotations

import contextlib
import datetime as dt
import io
import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import cdc_harness as harness


BASE_ENV = {
    "IVORYSQL_DATABASE": "cdcdb",
    "IVORYSQL_USER": "ivorysql",
    "IVORYSQL_PASSWORD": "long-enough-test-password",
    "CDC_SLOT": "ivorysql_cdc",
    "CDC_SCHEMA": "cdc",
    "CDC_TABLES": "cdc.accounts,cdc.staging",
    "CDC_REPORT_DIR": "/var/lib/ivorysql/reports",
    "CDC_MIN_INSERTS": "4",
    "CDC_MIN_UPDATES": "2",
    "CDC_MIN_DELETES": "1",
    "CDC_MIN_TRUNCATES": "1",
    "CDC_MAX_SLOT_LAG": "16MiB",
    "CDC_REQUIRE_TRANSACTION_MARKERS": "true",
    "CDC_REQUIRE_XIDS": "true",
    "CDC_REQUIRE_TIMESTAMPS": "true",
    "CDC_REQUIRE_TYPES": "true",
    "CDC_REQUIRE_PRIMARY_KEYS": "true",
}


def column(name: str, value: object, type_name: str = "text") -> dict[str, object]:
    return {"name": name, "type": type_name, "value": value}


def pk(name: str = "account_id", type_name: str = "bigint") -> dict[str, str]:
    return {"name": name, "type": type_name}


def event(action: str, xid: int, **extra: object) -> dict[str, object]:
    document: dict[str, object] = {"action": action, "xid": xid}
    document.update(extra)
    return document


def valid_documents() -> list[dict[str, object]]:
    commit_time = "2026-07-23T08:10:00+00:00"
    documents: list[dict[str, object]] = [event("B", 101)]
    for account_id, email in enumerate(
        (
            "ada@example.test",
            "linus@example.test",
            "grace@example.test",
            "margaret@example.test",
        ),
        1,
    ):
        documents.append(
            event(
                "I",
                101,
                schema="cdc",
                table="accounts",
                columns=[
                    column("account_id", account_id, "bigint"),
                    column("email", email),
                ],
                pk=[pk()],
            )
        )
    documents.extend(
        [
            event("C", 101, timestamp=commit_time),
            event("B", 102),
            event(
                "U",
                102,
                schema="cdc",
                table="accounts",
                columns=[
                    column("account_id", 1, "bigint"),
                    column("balance", "130.50", "numeric(14,2)"),
                ],
                identity=[column("account_id", 1, "bigint")],
                pk=[pk()],
            ),
            event(
                "U",
                102,
                schema="cdc",
                table="accounts",
                columns=[
                    column("account_id", 2, "bigint"),
                    column("balance", "90.00", "numeric(14,2)"),
                ],
                identity=[column("account_id", 2, "bigint")],
                pk=[pk()],
            ),
            event(
                "D",
                102,
                schema="cdc",
                table="accounts",
                identity=[column("account_id", 3, "bigint")],
            ),
            event("C", 102, timestamp=commit_time),
            event("B", 103),
            event(
                "I",
                103,
                schema="cdc",
                table="staging",
                columns=[
                    column("batch_id", 7, "bigint"),
                    column("payload", "first"),
                ],
                pk=[pk("batch_id")],
            ),
            event(
                "T",
                103,
                schema="cdc",
                table="staging",
            ),
            event("C", 103, timestamp=commit_time),
        ]
    )
    return documents


def parse_documents(
    documents: list[dict[str, object]] | None = None,
) -> tuple[harness.ChangeEvent, ...]:
    source = valid_documents() if documents is None else documents
    return tuple(
        harness.ChangeEvent.parse(json.dumps(document), index)
        for index, document in enumerate(source, 1)
    )


def valid_slot(**overrides: object) -> harness.SlotMetrics:
    values: dict[str, object] = {
        "slot_name": "ivorysql_cdc",
        "plugin": "wal2json",
        "slot_type": "logical",
        "database": "cdcdb",
        "active": False,
        "restart_lsn": "0/1600000",
        "confirmed_flush_lsn": "0/1700000",
        "retained_bytes": 4096,
    }
    values.update(overrides)
    return harness.SlotMetrics(**values)


class ScalarParsingTests(unittest.TestCase):
    def test_boolean_true_variants(self) -> None:
        for value in ("1", "true", "TRUE", "yes", "on"):
            with self.subTest(value=value):
                self.assertTrue(harness.parse_bool(value, "flag"))

    def test_boolean_false_variants(self) -> None:
        for value in ("0", "false", "FALSE", "no", "off"):
            with self.subTest(value=value):
                self.assertFalse(harness.parse_bool(value, "flag"))

    def test_boolean_rejects_unknown_value(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "boolean"):
            harness.parse_bool("sometimes", "flag")

    def test_positive_integer(self) -> None:
        self.assertEqual(harness.parse_positive_int("7", "count"), 7)

    def test_positive_integer_rejects_zero(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "positive"):
            harness.parse_positive_int("0", "count")

    def test_non_negative_integer_allows_zero(self) -> None:
        self.assertEqual(
            harness.parse_positive_int("0", "count", allow_zero=True), 0
        )

    def test_integer_rejects_text(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "integer"):
            harness.parse_positive_int("many", "count")

    def test_byte_size_units(self) -> None:
        expected = {
            "1B": 1,
            "2KiB": 2 * 1024,
            "3MiB": 3 * 1024**2,
            "4GiB": 4 * 1024**3,
        }
        for value, result in expected.items():
            with self.subTest(value=value):
                self.assertEqual(harness.parse_byte_size(value, "size"), result)

    def test_byte_size_rejects_decimal_and_si_units(self) -> None:
        for value in ("1.5MiB", "10MB", "0B", "-1KiB"):
            with self.subTest(value=value):
                with self.assertRaises(harness.ConfigurationError):
                    harness.parse_byte_size(value, "size")

    def test_identifier_validation(self) -> None:
        self.assertEqual(harness.validate_identifier("cdc_42", "name"), "cdc_42")

    def test_identifier_rejects_quoted_or_uppercase(self) -> None:
        for value in ('"cdc"', "CDC", "cdc-name", "1cdc", ""):
            with self.subTest(value=value):
                with self.assertRaises(harness.ConfigurationError):
                    harness.validate_identifier(value, "name")

    def test_password_policy(self) -> None:
        self.assertEqual(
            harness.validate_password("abcdefghijkl", "password"), "abcdefghijkl"
        )
        for value in ("short", "valid-length\nbut-newline", "valid-length\x00null"):
            with self.subTest(value=value):
                with self.assertRaises(harness.ConfigurationError):
                    harness.validate_password(value, "password")


class TableTests(unittest.TestCase):
    def test_table_reference(self) -> None:
        table = harness.TableRef.parse("cdc.accounts")
        self.assertEqual(table.schema, "cdc")
        self.assertEqual(table.table, "accounts")
        self.assertEqual(table.qualified, "cdc.accounts")

    def test_table_requires_exact_qualification(self) -> None:
        for value in ("accounts", "db.cdc.accounts", "", "cdc."):
            with self.subTest(value=value):
                with self.assertRaises(harness.ConfigurationError):
                    harness.TableRef.parse(value)

    def test_table_rejects_system_schemas(self) -> None:
        for value in (
            "pg_catalog.pg_class",
            "information_schema.tables",
            "pg_temp.data",
        ):
            with self.subTest(value=value):
                with self.assertRaisesRegex(harness.ConfigurationError, "system"):
                    harness.TableRef.parse(value)

    def test_table_rejects_wildcard_and_escape(self) -> None:
        for value in ("cdc.*", "cdc.account\\s"):
            with self.subTest(value=value):
                with self.assertRaises(harness.ConfigurationError):
                    harness.TableRef.parse(value)

    def test_table_list_is_sorted(self) -> None:
        tables = harness.parse_tables("cdc.staging,cdc.accounts")
        self.assertEqual(
            [table.qualified for table in tables],
            ["cdc.accounts", "cdc.staging"],
        )

    def test_table_list_rejects_duplicates(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "duplicate"):
            harness.parse_tables("cdc.accounts,cdc.accounts")

    def test_table_list_rejects_empty(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "at least one"):
            harness.parse_tables(" , ")


class PolicyTests(unittest.TestCase):
    def test_default_policy(self) -> None:
        policy = harness.CdcPolicy.from_environment(BASE_ENV)
        self.assertEqual(policy.slot, "ivorysql_cdc")
        self.assertEqual(policy.max_slot_lag_bytes, 16 * 1024**2)
        self.assertEqual(policy.minimum_actions["I"], 4)

    def test_public_policy_redacts_password(self) -> None:
        public = harness.CdcPolicy.from_environment(BASE_ENV).public_dict()
        self.assertNotIn("password", public)
        self.assertNotIn(BASE_ENV["IVORYSQL_PASSWORD"], json.dumps(public))

    def test_plugin_options_are_explicit(self) -> None:
        options = dict(harness.CdcPolicy.from_environment(BASE_ENV).plugin_options())
        self.assertEqual(options["format-version"], "2")
        self.assertEqual(options["include-transaction"], "1")
        self.assertEqual(options["actions"], "insert,update,delete,truncate")
        self.assertEqual(options["add-tables"], "cdc.accounts,cdc.staging")

    def test_plugin_options_remove_disabled_action(self) -> None:
        env = dict(BASE_ENV, CDC_MIN_TRUNCATES="0")
        options = dict(harness.CdcPolicy.from_environment(env).plugin_options())
        self.assertEqual(options["actions"], "insert,update,delete")

    def test_policy_rejects_all_zero_action_minimums(self) -> None:
        env = dict(
            BASE_ENV,
            CDC_MIN_INSERTS="0",
            CDC_MIN_UPDATES="0",
            CDC_MIN_DELETES="0",
            CDC_MIN_TRUNCATES="0",
        )
        with self.assertRaisesRegex(harness.ConfigurationError, "at least one"):
            harness.CdcPolicy.from_environment(env)

    def test_policy_rejects_table_from_other_schema(self) -> None:
        env = dict(BASE_ENV, CDC_TABLES="cdc.accounts,other.events")
        with self.assertRaisesRegex(harness.ConfigurationError, "CDC_SCHEMA"):
            harness.CdcPolicy.from_environment(env)

    def test_policy_rejects_broad_report_paths(self) -> None:
        for path in ("/", "/var", "/var/lib", "/tmp", "relative/reports"):
            with self.subTest(path=path):
                env = dict(BASE_ENV, CDC_REPORT_DIR=path)
                with self.assertRaises(harness.ConfigurationError):
                    harness.CdcPolicy.from_environment(env)

    def test_policy_rejects_large_wal_budget(self) -> None:
        env = dict(BASE_ENV, CDC_MAX_SLOT_LAG="2GiB")
        with self.assertRaisesRegex(harness.ConfigurationError, "1GiB"):
            harness.CdcPolicy.from_environment(env)

    def test_slot_name_validation(self) -> None:
        self.assertEqual(harness.validate_slot("cdc_slot_1"), "cdc_slot_1")
        for value in ("x", "default", "CDC_SLOT", "slot-name"):
            with self.subTest(value=value):
                with self.assertRaises(harness.ConfigurationError):
                    harness.validate_slot(value)


class TimestampTests(unittest.TestCase):
    def test_timestamp_with_offset(self) -> None:
        parsed = harness.parse_timestamp(
            "2026-07-23T10:00:00+08:00", "timestamp"
        )
        self.assertEqual(parsed.utcoffset(), dt.timedelta(hours=8))

    def test_timestamp_zulu(self) -> None:
        parsed = harness.parse_timestamp("2026-07-23T02:00:00Z", "timestamp")
        self.assertEqual(parsed.utcoffset(), dt.timedelta(0))

    def test_timestamp_postgres_hour_offset(self) -> None:
        parsed = harness.parse_timestamp(
            "2026-07-23 10:00:00.123456+08", "timestamp"
        )
        self.assertEqual(parsed.utcoffset(), dt.timedelta(hours=8))

    def test_timestamp_requires_timezone(self) -> None:
        with self.assertRaisesRegex(harness.ParseError, "timezone"):
            harness.parse_timestamp("2026-07-23T10:00:00", "timestamp")

    def test_timestamp_rejects_non_string(self) -> None:
        with self.assertRaisesRegex(harness.ParseError, "string"):
            harness.parse_timestamp(123, "timestamp")


class EventParsingTests(unittest.TestCase):
    def test_parse_insert(self) -> None:
        parsed = harness.ChangeEvent.parse(
            json.dumps(valid_documents()[1]), 2
        )
        self.assertEqual(parsed.action, "I")
        self.assertEqual(parsed.table.qualified, "cdc.accounts")
        self.assertEqual(len(parsed.columns), 2)
        self.assertEqual(len(parsed.fingerprint), 64)

    def test_parse_empty_line(self) -> None:
        with self.assertRaisesRegex(harness.ParseError, "empty"):
            harness.ChangeEvent.parse("", 1)

    def test_parse_invalid_json(self) -> None:
        with self.assertRaisesRegex(harness.ParseError, "invalid JSON"):
            harness.ChangeEvent.parse("{", 1)

    def test_parse_requires_object(self) -> None:
        with self.assertRaisesRegex(harness.ParseError, "object"):
            harness.ChangeEvent.parse("[]", 1)

    def test_parse_unknown_action(self) -> None:
        with self.assertRaisesRegex(harness.ParseError, "unknown action"):
            harness.ChangeEvent.parse('{"action":"X","xid":1}', 1)

    def test_parse_requires_positive_xid(self) -> None:
        for xid in (0, -1, "42", False):
            with self.subTest(xid=xid):
                with self.assertRaisesRegex(harness.ParseError, "positive"):
                    harness.ChangeEvent.parse(
                        json.dumps({"action": "B", "xid": xid}), 1
                    )

    def test_row_action_requires_table(self) -> None:
        with self.assertRaisesRegex(harness.ParseError, "schema and table"):
            harness.ChangeEvent.parse('{"action":"I","xid":1}', 1)

    def test_columns_require_array(self) -> None:
        document = event(
            "I", 1, schema="cdc", table="accounts", columns={"name": "id"}
        )
        with self.assertRaisesRegex(harness.ParseError, "array"):
            harness.ChangeEvent.parse(json.dumps(document), 1)

    def test_columns_reject_duplicate_names(self) -> None:
        document = event(
            "I",
            1,
            schema="cdc",
            table="accounts",
            columns=[column("id", 1), column("id", 2)],
        )
        with self.assertRaisesRegex(harness.ParseError, "duplicate"):
            harness.ChangeEvent.parse(json.dumps(document), 1)

    def test_columns_require_name(self) -> None:
        document = event(
            "I",
            1,
            schema="cdc",
            table="accounts",
            columns=[{"type": "bigint", "value": 1}],
        )
        with self.assertRaisesRegex(harness.ParseError, "name"):
            harness.ChangeEvent.parse(json.dumps(document), 1)


class SlotMetricTests(unittest.TestCase):
    def test_parse_slot_metrics(self) -> None:
        slot = harness.SlotMetrics.parse(json.dumps(valid_slot().as_dict()))
        self.assertEqual(slot.plugin, "wal2json")
        self.assertFalse(slot.active)

    def test_slot_metrics_reject_invalid_json(self) -> None:
        with self.assertRaisesRegex(harness.ParseError, "valid JSON"):
            harness.SlotMetrics.parse("{")

    def test_slot_metrics_require_strings(self) -> None:
        values = valid_slot().as_dict()
        values["plugin"] = None
        with self.assertRaisesRegex(harness.ParseError, "plugin"):
            harness.SlotMetrics.parse(json.dumps(values))

    def test_slot_metrics_require_boolean_active(self) -> None:
        values = valid_slot().as_dict()
        values["active"] = "false"
        with self.assertRaisesRegex(harness.ParseError, "boolean"):
            harness.SlotMetrics.parse(json.dumps(values))

    def test_slot_metrics_require_nonnegative_lag(self) -> None:
        values = valid_slot().as_dict()
        values["retained_bytes"] = -1
        with self.assertRaisesRegex(harness.ParseError, "non-negative"):
            harness.SlotMetrics.parse(json.dumps(values))


class AuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.policy = harness.CdcPolicy.from_environment(BASE_ENV)

    def assert_audit_problem(
        self,
        pattern: str,
        documents: list[dict[str, object]] | None = None,
        slot: harness.SlotMetrics | None = None,
        policy: harness.CdcPolicy | None = None,
    ) -> None:
        with self.assertRaisesRegex(harness.AuditFailure, pattern):
            harness.audit(
                policy or self.policy,
                parse_documents(documents),
                slot or valid_slot(),
            )

    def test_valid_stream(self) -> None:
        report = harness.audit(self.policy, parse_documents(), valid_slot())
        self.assertTrue(report["passed"])
        self.assertEqual(report["transaction_count"], 3)
        self.assertEqual(report["action_counts"]["insert"], 5)
        self.assertEqual(report["tables"], ["cdc.accounts", "cdc.staging"])

    def test_missing_insert_coverage(self) -> None:
        docs = [
            doc
            for doc in valid_documents()
            if not (doc.get("action") == "I" and doc.get("table") == "accounts")
        ]
        self.assert_audit_problem("insert count", docs)

    def test_missing_configured_table(self) -> None:
        docs = [
            doc
            for doc in valid_documents()
            if doc.get("table") != "staging"
        ]
        self.assert_audit_problem("configured tables absent", docs)

    def test_forbidden_table(self) -> None:
        docs = valid_documents()
        docs.insert(
            -1,
            event(
                "I",
                103,
                schema="private",
                table="customer_secrets",
                columns=[column("secret", "leak")],
                pk=[pk("customer_id")],
            ),
        )
        self.assert_audit_problem("forbidden table", docs)

    def test_unbalanced_transactions(self) -> None:
        docs = valid_documents()[:-1]
        self.assert_audit_problem("still open|unbalanced", docs)

    def test_commit_without_begin(self) -> None:
        docs = valid_documents()
        docs.insert(0, event("C", 99, timestamp="2026-07-23T00:00:00Z"))
        self.assert_audit_problem("without a begin", docs)

    def test_nested_begin(self) -> None:
        docs = valid_documents()
        docs.insert(1, event("B", 100))
        self.assert_audit_problem("while xid", docs)

    def test_row_xid_must_match_transaction(self) -> None:
        docs = valid_documents()
        docs[1] = dict(docs[1], xid=999)
        self.assert_audit_problem("differs from open xid", docs)

    def test_commit_xid_must_match_transaction(self) -> None:
        docs = valid_documents()
        docs[5] = dict(docs[5], xid=999)
        self.assert_audit_problem("expected 101", docs)

    def test_update_requires_identity(self) -> None:
        docs = valid_documents()
        docs[7] = {key: value for key, value in docs[7].items() if key != "identity"}
        self.assert_audit_problem("no old-row identity", docs)

    def test_delete_requires_identity(self) -> None:
        docs = valid_documents()
        docs[9] = {key: value for key, value in docs[9].items() if key != "identity"}
        self.assert_audit_problem("no old-row identity", docs)

    def test_insert_requires_primary_key(self) -> None:
        docs = valid_documents()
        docs[1] = {key: value for key, value in docs[1].items() if key != "pk"}
        self.assert_audit_problem("no primary-key metadata", docs)

    def test_update_requires_primary_key(self) -> None:
        docs = valid_documents()
        docs[7] = {key: value for key, value in docs[7].items() if key != "pk"}
        self.assert_audit_problem("no primary-key metadata", docs)

    def test_columns_require_types(self) -> None:
        docs = valid_documents()
        docs[1] = dict(docs[1])
        docs[1]["columns"] = [{"name": "account_id", "value": 1}]
        self.assert_audit_problem("untyped columns", docs)

    def test_commit_requires_timestamp(self) -> None:
        docs = valid_documents()
        docs[5] = {key: value for key, value in docs[5].items() if key != "timestamp"}
        self.assert_audit_problem("has no timestamp", docs)

    def test_every_event_requires_xid(self) -> None:
        docs = valid_documents()
        docs[1] = {key: value for key, value in docs[1].items() if key != "xid"}
        self.assert_audit_problem("has no xid", docs)

    def test_duplicate_event_payload(self) -> None:
        docs = valid_documents()
        docs.insert(2, dict(docs[1]))
        self.assert_audit_problem("duplicate event", docs)

    def test_committed_xids_must_be_ordered(self) -> None:
        docs = valid_documents()
        mapping = {101: 201, 102: 199, 103: 202}
        docs = [
            dict(doc, xid=mapping[doc["xid"]]) if "xid" in doc else doc
            for doc in docs
        ]
        self.assert_audit_problem("out of order", docs)

    def test_slot_name_policy(self) -> None:
        self.assert_audit_problem(
            "slot name", slot=valid_slot(slot_name="other_slot")
        )

    def test_slot_plugin_policy(self) -> None:
        self.assert_audit_problem(
            "slot plugin", slot=valid_slot(plugin="test_decoding")
        )

    def test_slot_type_policy(self) -> None:
        self.assert_audit_problem(
            "slot type", slot=valid_slot(slot_type="physical")
        )

    def test_slot_database_policy(self) -> None:
        self.assert_audit_problem(
            "slot database", slot=valid_slot(database="postgres")
        )

    def test_slot_must_not_be_active(self) -> None:
        self.assert_audit_problem(
            "remains active", slot=valid_slot(active=True)
        )

    def test_slot_lag_budget(self) -> None:
        self.assert_audit_problem(
            "policy allows",
            slot=valid_slot(retained_bytes=32 * 1024**2),
        )

    def test_markers_can_be_disabled(self) -> None:
        env = dict(BASE_ENV, CDC_REQUIRE_TRANSACTION_MARKERS="false")
        policy = harness.CdcPolicy.from_environment(env)
        docs = [
            doc for doc in valid_documents() if doc.get("action") not in {"B", "C"}
        ]
        report = harness.audit(policy, parse_documents(docs), valid_slot())
        self.assertTrue(report["passed"])

    def test_types_can_be_disabled(self) -> None:
        env = dict(BASE_ENV, CDC_REQUIRE_TYPES="false")
        policy = harness.CdcPolicy.from_environment(env)
        docs = valid_documents()
        docs[1] = dict(docs[1])
        docs[1]["columns"] = [{"name": "account_id", "value": 1}]
        report = harness.audit(policy, parse_documents(docs), valid_slot())
        self.assertTrue(report["passed"])

    def test_primary_keys_can_be_disabled(self) -> None:
        env = dict(BASE_ENV, CDC_REQUIRE_PRIMARY_KEYS="false")
        policy = harness.CdcPolicy.from_environment(env)
        docs = []
        for doc in valid_documents():
            docs.append({key: value for key, value in doc.items() if key != "pk"})
        report = harness.audit(policy, parse_documents(docs), valid_slot())
        self.assertTrue(report["passed"])


class FileAndCliTests(unittest.TestCase):
    def test_read_events(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory, "events.jsonl")
            path.write_text(
                "\n".join(json.dumps(item) for item in valid_documents()) + "\n",
                encoding="utf-8",
            )
            self.assertEqual(len(harness.read_events(path)), len(valid_documents()))

    def test_read_events_rejects_empty_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory, "events.jsonl")
            path.write_text("", encoding="utf-8")
            with self.assertRaisesRegex(harness.ParseError, "empty"):
                harness.read_events(path)

    def test_read_slot_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory, "slot.json")
            path.write_text(json.dumps(valid_slot().as_dict()), encoding="utf-8")
            self.assertEqual(harness.read_slot_metrics(path).slot_name, "ivorysql_cdc")

    def test_write_json_is_atomic_and_terminated(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory, "nested", "report.json")
            harness.write_json(path, {"passed": True})
            self.assertTrue(path.read_text(encoding="utf-8").endswith("\n"))
            self.assertFalse(path.with_suffix(".json.tmp").exists())

    def test_preflight_json(self) -> None:
        output = io.StringIO()
        with mock.patch.dict(os.environ, BASE_ENV, clear=True):
            with contextlib.redirect_stdout(output):
                code = harness.main(["preflight", "--json"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(output.getvalue())["slot"], "ivorysql_cdc")

    def test_options_text(self) -> None:
        output = io.StringIO()
        with mock.patch.dict(os.environ, BASE_ENV, clear=True):
            with contextlib.redirect_stdout(output):
                code = harness.main(["options"])
        self.assertEqual(code, 0)
        self.assertIn("format-version=2", output.getvalue())
        self.assertIn("add-tables=cdc.accounts,cdc.staging", output.getvalue())

    def test_invalid_environment_returns_two(self) -> None:
        error = io.StringIO()
        with mock.patch.dict(os.environ, {}, clear=True):
            with contextlib.redirect_stderr(error):
                code = harness.main(["preflight"])
        self.assertEqual(code, 2)
        self.assertIn("configuration error", error.getvalue())

    def test_audit_command_writes_success_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            events_path = root / "events.jsonl"
            slot_path = root / "slot.json"
            report_path = root / "report.json"
            events_path.write_text(
                "\n".join(json.dumps(item) for item in valid_documents()) + "\n",
                encoding="utf-8",
            )
            slot_path.write_text(
                json.dumps(valid_slot().as_dict()) + "\n", encoding="utf-8"
            )
            with mock.patch.dict(os.environ, BASE_ENV, clear=True):
                with contextlib.redirect_stdout(io.StringIO()):
                    code = harness.main(
                        [
                            "audit",
                            "--events",
                            str(events_path),
                            "--slot-metrics",
                            str(slot_path),
                            "--output",
                            str(report_path),
                        ]
                    )
            self.assertEqual(code, 0)
            self.assertTrue(json.loads(report_path.read_text())["passed"])

    def test_audit_command_writes_failure_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            events_path = root / "events.jsonl"
            slot_path = root / "slot.json"
            report_path = root / "report.json"
            documents = valid_documents()[:-1]
            events_path.write_text(
                "\n".join(json.dumps(item) for item in documents) + "\n",
                encoding="utf-8",
            )
            slot_path.write_text(
                json.dumps(valid_slot().as_dict()) + "\n", encoding="utf-8"
            )
            with mock.patch.dict(os.environ, BASE_ENV, clear=True):
                with contextlib.redirect_stderr(io.StringIO()):
                    code = harness.main(
                        [
                            "audit",
                            "--events",
                            str(events_path),
                            "--slot-metrics",
                            str(slot_path),
                            "--output",
                            str(report_path),
                        ]
                    )
            self.assertEqual(code, 1)
            report = json.loads(report_path.read_text())
            self.assertFalse(report["passed"])
            self.assertTrue(report["problems"])


if __name__ == "__main__":
    unittest.main()
