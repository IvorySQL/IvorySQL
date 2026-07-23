from __future__ import annotations

import io
import importlib.util
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
from pathlib import Path

import migration_harness as harness


HERE = Path(__file__).resolve().parents[1]
CONTRACT_PATH = HERE / "compatibility_contract.json"


def load_source_transformer():
    path = HERE / "scripts" / "patch-orafce-pg18.py"
    specification = importlib.util.spec_from_file_location("patch_orafce_pg18", path)
    if specification is None or specification.loader is None:
        raise RuntimeError("cannot load source transformer")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def valid_environment(**overrides: str) -> dict[str, str]:
    values = {
        "IVORYSQL_PASSWORD": "ivorysql-orafce-ci-password",
        "ORAFCE_EXPECTED_EXTENSION_VERSION": "4.16",
        "ORAFCE_EXPECTED_SOURCE_VERSION": "4.16.7",
        "ORAFCE_CONTRACT": "/usr/local/share/orafce/compatibility_contract.json",
        "ORAFCE_REPORT_DIR": "/var/lib/ivorysql/reports",
    }
    values.update(overrides)
    return values


def integration_mapping(**overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "ivorysql_ref": "IvorySQL_5.4",
        "orafce_source_version": "4.16.7",
        "orafce_source_ref": "VERSION_4_16_7",
        "orafce_extension_version": "4.16",
    }
    value.update(overrides)
    return value


def case_mapping(number: int = 0, **overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "id": f"core.case_{number}",
        "category": "core",
        "capability": f"Capability {number}",
        "expected": f"value-{number}",
        "sql_type": "text",
        "required": True,
        "migration_risk": f"Migration risk {number}.",
    }
    value.update(overrides)
    return value


def contract_mapping() -> dict[str, object]:
    return {
        "schema_version": 1,
        "integration": integration_mapping(),
        "required_categories": ["core"],
        "cases": [case_mapping(number) for number in range(30)],
    }


def loaded_contract() -> harness.Contract:
    return harness.Contract.load(CONTRACT_PATH)


def valid_metadata(**overrides: object) -> harness.Metadata:
    values: dict[str, object] = {
        "extension_version": "4.16",
        "server_version": "IvorySQL 5.4 on x86_64-pc-linux-gnu",
        "database_mode": "pg",
        "plisql_installed": True,
        "result_count": 36,
    }
    values.update(overrides)
    return harness.Metadata(**values)


def matching_results(contract: harness.Contract) -> dict[str, harness.ResultRow]:
    return {
        case.id: harness.ResultRow(
            id=case.id, actual=case.expected, actual_type=case.sql_type
        )
        for case in contract.cases
    }


class RuntimePolicyTests(unittest.TestCase):
    def test_valid_policy(self) -> None:
        policy = harness.RuntimePolicy.from_environment(valid_environment())
        self.assertEqual(policy.expected_extension_version, "4.16")
        self.assertEqual(policy.expected_source_version, "4.16.7")

    def test_defaults_except_password(self) -> None:
        policy = harness.RuntimePolicy.from_environment(
            {"IVORYSQL_PASSWORD": "sixteen-characters"}
        )
        self.assertEqual(policy.report_directory, "/var/lib/ivorysql/reports")

    def test_missing_password(self) -> None:
        environment = valid_environment()
        del environment["IVORYSQL_PASSWORD"]
        with self.assertRaisesRegex(harness.ConfigurationError, "non-empty"):
            harness.RuntimePolicy.from_environment(environment)

    def test_short_password(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "16 characters"):
            harness.RuntimePolicy.from_environment(
                valid_environment(IVORYSQL_PASSWORD="short")
            )

    def test_control_character_in_password(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "control"):
            harness.RuntimePolicy.from_environment(
                valid_environment(IVORYSQL_PASSWORD="long-password-value\nleak")
            )

    def test_invalid_extension_version(self) -> None:
        for value in ("4", "v4.16", "4.16-beta", ""):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                harness.RuntimePolicy.from_environment(
                    valid_environment(ORAFCE_EXPECTED_EXTENSION_VERSION=value)
                )

    def test_invalid_source_version(self) -> None:
        for value in ("VERSION_4_16_7", "latest", "4.16.x"):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                harness.RuntimePolicy.from_environment(
                    valid_environment(ORAFCE_EXPECTED_SOURCE_VERSION=value)
                )

    def test_contract_path_must_be_absolute(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "absolute"):
            harness.RuntimePolicy.from_environment(
                valid_environment(ORAFCE_CONTRACT="compatibility_contract.json")
            )

    def test_report_path_must_be_absolute(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "absolute"):
            harness.RuntimePolicy.from_environment(
                valid_environment(ORAFCE_REPORT_DIR="reports")
            )

    def test_report_path_rejects_broad_directory(self) -> None:
        for value in ("/", "/tmp", "/var", "/one"):
            with self.subTest(value=value), self.assertRaises(harness.ConfigurationError):
                harness.RuntimePolicy.from_environment(
                    valid_environment(ORAFCE_REPORT_DIR=value)
                )


class SourceTransformerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.transformer = load_source_transformer()

    def test_exact_orafce_block_is_guarded(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "regexp.c")
            path.write_text(
                "prefix\n" + self.transformer.ORIGINAL + "suffix\n", encoding="utf-8"
            )
            self.transformer.patch_source(path)
            updated = path.read_text(encoding="utf-8")
            self.assertNotIn(self.transformer.ORIGINAL, updated)
            self.assertEqual(updated.count(self.transformer.REPLACEMENT), 1)
            self.assertIn("#if PG_VERSION_NUM < 180000", updated)

    def test_source_drift_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "regexp.c")
            path.write_text("typedef struct changed_flags;\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "found 0"):
                self.transformer.patch_source(path)

    def test_duplicate_blocks_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "regexp.c")
            path.write_text(self.transformer.ORIGINAL * 2, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "found 2"):
                self.transformer.patch_source(path)


class IdentityAndCaseTests(unittest.TestCase):
    def test_valid_identity(self) -> None:
        identity = harness.IntegrationIdentity.from_mapping(integration_mapping())
        self.assertEqual(identity.orafce_source_ref, "VERSION_4_16_7")

    def test_identity_requires_exact_keys(self) -> None:
        value = integration_mapping(extra="value")
        with self.assertRaisesRegex(harness.ConfigurationError, "unknown keys"):
            harness.IntegrationIdentity.from_mapping(value)

    def test_identity_requires_ivorysql_release(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "release tag"):
            harness.IntegrationIdentity.from_mapping(
                integration_mapping(ivorysql_ref="master")
            )

    def test_identity_rejects_invalid_source_ref(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "source ref"):
            harness.IntegrationIdentity.from_mapping(
                integration_mapping(orafce_source_ref="4.16.7")
            )

    def test_identity_ref_must_match_version(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "does not match"):
            harness.IntegrationIdentity.from_mapping(
                integration_mapping(orafce_source_ref="VERSION_4_16_6")
            )

    def test_valid_case(self) -> None:
        case = harness.ContractCase.from_mapping(case_mapping(), 0)
        self.assertEqual(case.id, "core.case_0")
        self.assertTrue(case.required)

    def test_case_requires_object(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "must be an object"):
            harness.ContractCase.from_mapping([], 0)

    def test_case_requires_exact_keys(self) -> None:
        value = case_mapping()
        del value["migration_risk"]
        with self.assertRaisesRegex(harness.ConfigurationError, "missing keys"):
            harness.ContractCase.from_mapping(value, 0)

    def test_case_identifier_format(self) -> None:
        for value in ("no-dot", "Core.case", "core.1case", "core.case.more"):
            with self.subTest(value=value), self.assertRaisesRegex(
                harness.ConfigurationError, "invalid format"
            ):
                harness.ContractCase.from_mapping(case_mapping(id=value), 0)

    def test_case_identifier_must_match_category(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "start with"):
            harness.ContractCase.from_mapping(
                case_mapping(id="other.case", category="core"), 0
            )

    def test_case_rejects_unsupported_sql_type(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "unsupported"):
            harness.ContractCase.from_mapping(case_mapping(sql_type="jsonb"), 0)

    def test_boolean_expected_type_must_match(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "match boolean"):
            harness.ContractCase.from_mapping(
                case_mapping(expected="true", sql_type="boolean"), 0
            )

    def test_integer_expected_type_must_match(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "match integer"):
            harness.ContractCase.from_mapping(
                case_mapping(expected=True, sql_type="integer"), 0
            )

    def test_text_expected_type_must_match(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "match text"):
            harness.ContractCase.from_mapping(
                case_mapping(expected=3, sql_type="text"), 0
            )

    def test_expected_rejects_array(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "must be a string"):
            harness.ContractCase.from_mapping(case_mapping(expected=[]), 0)


class ContractTests(unittest.TestCase):
    def test_repository_contract_is_valid_and_broad(self) -> None:
        contract = loaded_contract()
        self.assertEqual(contract.schema_version, 1)
        self.assertEqual(len(contract.cases), 36)
        self.assertGreaterEqual(len(contract.required_categories), 10)
        self.assertTrue(all(case.required for case in contract.cases))

    def test_contract_requires_exact_keys(self) -> None:
        value = contract_mapping()
        value["extra"] = True
        with self.assertRaisesRegex(harness.ConfigurationError, "unknown keys"):
            harness.Contract.from_mapping(value)

    def test_contract_schema_version_is_fixed(self) -> None:
        value = contract_mapping()
        value["schema_version"] = 2
        with self.assertRaisesRegex(harness.ConfigurationError, "must be 1"):
            harness.Contract.from_mapping(value)

    def test_categories_must_be_array(self) -> None:
        value = contract_mapping()
        value["required_categories"] = "core"
        with self.assertRaisesRegex(harness.ConfigurationError, "array"):
            harness.Contract.from_mapping(value)

    def test_categories_must_be_sorted(self) -> None:
        value = contract_mapping()
        value["required_categories"] = ["second", "core"]
        with self.assertRaisesRegex(harness.ConfigurationError, "sorted"):
            harness.Contract.from_mapping(value)

    def test_categories_must_be_unique(self) -> None:
        value = contract_mapping()
        value["required_categories"] = ["core", "core"]
        with self.assertRaisesRegex(harness.ConfigurationError, "unique"):
            harness.Contract.from_mapping(value)

    def test_contract_requires_thirty_cases(self) -> None:
        value = contract_mapping()
        value["cases"] = value["cases"][:29]
        with self.assertRaisesRegex(harness.ConfigurationError, "at least 30"):
            harness.Contract.from_mapping(value)

    def test_contract_rejects_duplicate_case_ids(self) -> None:
        value = contract_mapping()
        value["cases"][1]["id"] = "core.case_0"
        with self.assertRaisesRegex(harness.ConfigurationError, "unique"):
            harness.Contract.from_mapping(value)

    def test_required_category_needs_required_case(self) -> None:
        value = contract_mapping()
        value["required_categories"] = ["core", "missing"]
        with self.assertRaisesRegex(harness.ConfigurationError, "lack a required case"):
            harness.Contract.from_mapping(value)

    def test_required_case_category_must_be_declared(self) -> None:
        value = contract_mapping()
        value["cases"][0] = case_mapping(0, id="other.case_0", category="other")
        with self.assertRaisesRegex(harness.ConfigurationError, "undeclared"):
            harness.Contract.from_mapping(value)

    def test_contract_load_reports_invalid_json_as_configuration(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "contract.json")
            path.write_text("not-json", encoding="utf-8")
            with self.assertRaises(harness.ConfigurationError):
                harness.Contract.load(path)

    def test_case_map_covers_all_cases(self) -> None:
        contract = loaded_contract()
        self.assertEqual(set(contract.case_map()), {case.id for case in contract.cases})


class ResultAndMetadataTests(unittest.TestCase):
    def test_valid_result_row(self) -> None:
        row = harness.ResultRow.from_mapping(
            {"id": "core.value", "actual": 3, "actual_type": "integer"}, 1
        )
        self.assertEqual(row.actual, 3)

    def test_result_requires_exact_keys(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "missing keys"):
            harness.ResultRow.from_mapping(
                {"id": "core.value", "actual": 3}, 1
            )

    def test_result_rejects_invalid_identifier(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "invalid format"):
            harness.ResultRow.from_mapping(
                {"id": "INVALID", "actual": 3, "actual_type": "integer"}, 1
            )

    def test_result_rejects_complex_actual(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "JSON scalar"):
            harness.ResultRow.from_mapping(
                {"id": "core.value", "actual": [], "actual_type": "text"}, 1
            )

    def test_load_results(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "results.jsonl")
            path.write_text(
                '{"id":"core.first","actual":true,"actual_type":"boolean"}\n'
                '{"id":"core.second","actual":"ok","actual_type":"text"}\n',
                encoding="utf-8",
            )
            rows = harness.load_results(path)
            self.assertEqual(set(rows), {"core.first", "core.second"})

    def test_load_results_rejects_duplicate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "results.jsonl")
            row = '{"id":"core.first","actual":true,"actual_type":"boolean"}\n'
            path.write_text(row + row, encoding="utf-8")
            with self.assertRaisesRegex(harness.EvidenceError, "duplicate"):
                harness.load_results(path)

    def test_load_results_rejects_blank_line(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "results.jsonl")
            path.write_text("\n", encoding="utf-8")
            with self.assertRaisesRegex(harness.EvidenceError, "blank"):
                harness.load_results(path)

    def test_load_results_rejects_invalid_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "results.jsonl")
            path.write_text("not-json\n", encoding="utf-8")
            with self.assertRaisesRegex(harness.EvidenceError, "cannot parse"):
                harness.load_results(path)

    def test_metadata_parses_valid_object(self) -> None:
        metadata = harness.Metadata.from_mapping(
            {
                "extension_version": "4.16",
                "server_version": "IvorySQL test",
                "database_mode": None,
                "plisql_installed": True,
                "result_count": 36,
            }
        )
        self.assertIsNone(metadata.database_mode)

    def test_metadata_rejects_boolean_result_count(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "integer"):
            harness.Metadata.from_mapping(
                {
                    "extension_version": "4.16",
                    "server_version": "IvorySQL test",
                    "database_mode": "pg",
                    "plisql_installed": True,
                    "result_count": True,
                }
            )

    def test_metadata_requires_boolean_plisql(self) -> None:
        with self.assertRaisesRegex(harness.EvidenceError, "boolean"):
            harness.Metadata.from_mapping(
                {
                    "extension_version": "4.16",
                    "server_version": "IvorySQL test",
                    "database_mode": "pg",
                    "plisql_installed": "yes",
                    "result_count": 36,
                }
            )


class AuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = loaded_contract()
        self.policy = harness.RuntimePolicy.from_environment(valid_environment())
        self.results = matching_results(self.contract)

    def audit(
        self,
        results: dict[str, harness.ResultRow] | None = None,
        metadata: harness.Metadata | None = None,
    ) -> harness.AuditReport:
        return harness.audit(
            self.policy,
            self.contract,
            results if results is not None else self.results,
            metadata or valid_metadata(),
        )

    def test_matching_evidence_passes(self) -> None:
        report = self.audit()
        self.assertTrue(report.passed)
        self.assertEqual(report.summary["declared"], 36)
        self.assertEqual(report.summary["passed_cases"], 36)
        self.assertEqual(report.summary["metadata_failed"], 0)

    def test_wrong_value_fails_one_case(self) -> None:
        results = dict(self.results)
        identifier = self.contract.cases[0].id
        row = results[identifier]
        results[identifier] = harness.ResultRow(row.id, False, row.actual_type)
        report = self.audit(results)
        self.assertFalse(report.passed)
        self.assertEqual(report.summary["required_failed"], 1)

    def test_wrong_sql_type_fails_case(self) -> None:
        results = dict(self.results)
        identifier = "string.instr_occurrence"
        row = results[identifier]
        results[identifier] = harness.ResultRow(row.id, row.actual, "bigint")
        report = self.audit(results)
        self.assertFalse(report.passed)
        failed = [check for check in report.checks if not check.passed]
        self.assertEqual([check.id for check in failed], [identifier])

    def test_strict_json_type_prevents_true_equaling_one(self) -> None:
        results = dict(self.results)
        identifier = "dictionary.dual"
        results[identifier] = harness.ResultRow(identifier, True, "bigint")
        self.assertFalse(self.audit(results).passed)

    def test_missing_result_fails(self) -> None:
        results = dict(self.results)
        results.pop("null.nvl")
        metadata = valid_metadata(result_count=35)
        report = self.audit(results, metadata)
        self.assertFalse(report.passed)
        self.assertEqual(report.summary["missing"], 1)

    def test_unknown_result_is_evidence_error(self) -> None:
        results = dict(self.results)
        results["unknown.case"] = harness.ResultRow("unknown.case", True, "boolean")
        with self.assertRaisesRegex(harness.EvidenceError, "unknown identifiers"):
            self.audit(results)

    def test_wrong_extension_version_fails_metadata(self) -> None:
        report = self.audit(metadata=valid_metadata(extension_version="4.15"))
        self.assertFalse(report.passed)
        self.assertFalse(report.metadata["checks"]["extension_version"])

    def test_non_ivorysql_server_fails_metadata(self) -> None:
        report = self.audit(metadata=valid_metadata(server_version="PostgreSQL 18"))
        self.assertFalse(report.passed)
        self.assertFalse(report.metadata["checks"]["server_identity"])

    def test_missing_plisql_fails_metadata(self) -> None:
        report = self.audit(metadata=valid_metadata(plisql_installed=False))
        self.assertFalse(report.passed)

    def test_result_count_mismatch_fails_metadata(self) -> None:
        report = self.audit(metadata=valid_metadata(result_count=35))
        self.assertFalse(report.passed)
        self.assertFalse(report.metadata["checks"]["result_count"])

    def test_report_is_json_serializable(self) -> None:
        encoded = json.dumps(self.audit().as_dict(), ensure_ascii=False)
        decoded = json.loads(encoded)
        self.assertTrue(decoded["passed"])
        self.assertEqual(len(decoded["checks"]), 36)

    def test_validate_identity_rejects_environment_extension_drift(self) -> None:
        policy = harness.RuntimePolicy.from_environment(
            valid_environment(ORAFCE_EXPECTED_EXTENSION_VERSION="4.15")
        )
        with self.assertRaisesRegex(harness.ConfigurationError, "extension version"):
            harness.validate_identity(policy, self.contract)

    def test_validate_identity_rejects_environment_source_drift(self) -> None:
        policy = harness.RuntimePolicy.from_environment(
            valid_environment(ORAFCE_EXPECTED_SOURCE_VERSION="4.16.6")
        )
        with self.assertRaisesRegex(harness.ConfigurationError, "source version"):
            harness.validate_identity(policy, self.contract)


class CliTests(unittest.TestCase):
    def write_runtime_files(self, directory: Path) -> tuple[Path, Path]:
        contract = loaded_contract()
        results_path = directory / "results.jsonl"
        with results_path.open("w", encoding="utf-8", newline="\n") as stream:
            for case in contract.cases:
                stream.write(
                    json.dumps(
                        {
                            "id": case.id,
                            "actual": case.expected,
                            "actual_type": case.sql_type,
                        },
                        ensure_ascii=False,
                    )
                    + "\n"
                )
        metadata_path = directory / "metadata.json"
        metadata_path.write_text(json.dumps(valid_metadata().__dict__), encoding="utf-8")
        return results_path, metadata_path

    def test_preflight_cli(self) -> None:
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            result = harness.run(
                ["preflight", "--contract", str(CONTRACT_PATH)], valid_environment()
            )
        self.assertEqual(result, 0)
        payload = json.loads(stdout.getvalue())
        self.assertTrue(payload["valid"])
        self.assertEqual(payload["cases"], 36)

    def test_preflight_cli_returns_two_for_invalid_policy(self) -> None:
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            result = harness.run(
                ["preflight", "--contract", str(CONTRACT_PATH)],
                valid_environment(ORAFCE_EXPECTED_SOURCE_VERSION="4.16.6"),
            )
        self.assertEqual(result, 2)
        self.assertIn("source version", stderr.getvalue())

    def test_audit_cli_writes_passing_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            results, metadata = self.write_runtime_files(directory)
            output = directory / "audit.json"
            arguments = [
                "audit",
                "--contract",
                str(CONTRACT_PATH),
                "--results",
                str(results),
                "--metadata",
                str(metadata),
                "--output",
                str(output),
            ]
            with redirect_stdout(io.StringIO()):
                result = harness.run(arguments, valid_environment())
            self.assertEqual(result, 0)
            self.assertTrue(json.loads(output.read_text(encoding="utf-8"))["passed"])

    def test_audit_cli_returns_one_for_contract_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            results, metadata = self.write_runtime_files(directory)
            lines = results.read_text(encoding="utf-8").splitlines()
            first = json.loads(lines[0])
            first["actual"] = not first["actual"] if isinstance(first["actual"], bool) else "wrong"
            lines[0] = json.dumps(first)
            results.write_text("\n".join(lines) + "\n", encoding="utf-8")
            output = directory / "audit.json"
            with redirect_stdout(io.StringIO()):
                result = harness.run(
                    [
                        "audit",
                        "--contract",
                        str(CONTRACT_PATH),
                        "--results",
                        str(results),
                        "--metadata",
                        str(metadata),
                        "--output",
                        str(output),
                    ],
                    valid_environment(),
                )
            self.assertEqual(result, 1)
            self.assertFalse(json.loads(output.read_text(encoding="utf-8"))["passed"])

    def test_audit_cli_returns_two_for_bad_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            results, metadata = self.write_runtime_files(directory)
            results.write_text("bad-json\n", encoding="utf-8")
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                result = harness.run(
                    [
                        "audit",
                        "--contract",
                        str(CONTRACT_PATH),
                        "--results",
                        str(results),
                        "--metadata",
                        str(metadata),
                        "--output",
                        str(directory / "audit.json"),
                    ],
                    valid_environment(),
                )
            self.assertEqual(result, 2)
            self.assertIn("cannot parse results", stderr.getvalue())

    def test_atomic_write_replaces_old_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory, "nested", "audit.json")
            harness.atomic_write_json(output, {"passed": True, "message": "兼容"})
            payload = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(payload["message"], "兼容")
            self.assertTrue(output.read_bytes().endswith(b"\n"))


if __name__ == "__main__":
    unittest.main()
