#!/usr/bin/env python3
"""Validate and audit the IvorySQL + orafce migration compatibility contract."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping, Sequence


class HarnessError(ValueError):
    """Base class for concise failures that do not need a traceback."""


class ConfigurationError(HarnessError):
    """The environment or contract manifest is invalid."""


class EvidenceError(HarnessError):
    """Runtime evidence is missing, malformed, or internally inconsistent."""


_CASE_ID = re.compile(r"^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$")
_CATEGORY = re.compile(r"^[a-z][a-z0-9_]*$")
_VERSION = re.compile(r"^[0-9]+(?:\.[0-9]+){1,3}$")
_SOURCE_REF = re.compile(r"^VERSION_[0-9]+(?:_[0-9]+){2,3}$")
_SQL_TYPE = re.compile(r"^(?:boolean|integer|bigint|numeric|text)$")
_MAX_DOCUMENT_BYTES = 1024 * 1024
_MAX_RESULTS_BYTES = 2 * 1024 * 1024
_MAX_RESULT_LINE_BYTES = 64 * 1024
_MIN_CASES = 30


def _read_json_object(path: Path, label: str) -> Mapping[str, Any]:
    """Read one bounded UTF-8 JSON object."""

    try:
        size = path.stat().st_size
    except OSError as exc:
        raise EvidenceError(f"cannot read {label}: {exc}") from exc
    if size == 0:
        raise EvidenceError(f"{label} is empty")
    if size > _MAX_DOCUMENT_BYTES:
        raise EvidenceError(f"{label} exceeds the 1 MiB document limit")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise EvidenceError(f"cannot parse {label}: {exc}") from exc
    if not isinstance(value, dict):
        raise EvidenceError(f"{label} must contain one JSON object")
    return value


def _require_keys(
    value: Mapping[str, Any],
    required: Iterable[str],
    label: str,
    *,
    exact: bool = True,
    error: type[HarnessError] = HarnessError,
) -> None:
    required_set = set(required)
    missing = required_set - value.keys()
    if missing:
        raise error(f"{label} is missing keys: {', '.join(sorted(missing))}")
    if exact:
        extra = value.keys() - required_set
        if extra:
            raise error(f"{label} has unknown keys: {', '.join(sorted(extra))}")


def _nonempty_text(value: Any, name: str, error: type[HarnessError]) -> str:
    if not isinstance(value, str) or value.strip() == "":
        raise error(f"{name} must be a non-empty string")
    if value != value.strip():
        raise error(f"{name} must not have surrounding whitespace")
    if any(character in value for character in ("\x00", "\r", "\n")):
        raise error(f"{name} contains a forbidden control character")
    return value


def _boolean(value: Any, name: str, error: type[HarnessError]) -> bool:
    if not isinstance(value, bool):
        raise error(f"{name} must be a boolean")
    return value


def _integer(value: Any, name: str, error: type[HarnessError], minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise error(f"{name} must be an integer")
    if value < minimum:
        raise error(f"{name} must be at least {minimum}")
    return value


def _json_scalar(value: Any, name: str) -> Any:
    if value is None or isinstance(value, (str, bool, int)):
        return value
    raise ConfigurationError(f"{name} must be a string, integer, boolean, or null")


def _report_directory(value: str) -> str:
    path = PurePosixPath(value)
    if not path.is_absolute():
        raise ConfigurationError("ORAFCE_REPORT_DIR must be an absolute POSIX path")
    if ".." in path.parts:
        raise ConfigurationError("ORAFCE_REPORT_DIR must not contain parent traversal")
    if path in {PurePosixPath("/"), PurePosixPath("/tmp"), PurePosixPath("/var")}:
        raise ConfigurationError("ORAFCE_REPORT_DIR is too broad")
    if len(path.parts) < 4:
        raise ConfigurationError("ORAFCE_REPORT_DIR must contain at least three components")
    return str(path)


@dataclass(frozen=True)
class RuntimePolicy:
    expected_extension_version: str
    expected_source_version: str
    contract_path: str
    report_directory: str

    @classmethod
    def from_environment(cls, environment: Mapping[str, str]) -> "RuntimePolicy":
        password = _nonempty_text(
            environment.get("IVORYSQL_PASSWORD"),
            "IVORYSQL_PASSWORD",
            ConfigurationError,
        )
        if len(password) < 16:
            raise ConfigurationError("IVORYSQL_PASSWORD must contain at least 16 characters")
        extension_version = _nonempty_text(
            environment.get("ORAFCE_EXPECTED_EXTENSION_VERSION", "4.16"),
            "ORAFCE_EXPECTED_EXTENSION_VERSION",
            ConfigurationError,
        )
        if _VERSION.fullmatch(extension_version) is None:
            raise ConfigurationError("ORAFCE_EXPECTED_EXTENSION_VERSION is not a version")
        source_version = _nonempty_text(
            environment.get("ORAFCE_EXPECTED_SOURCE_VERSION", "4.16.7"),
            "ORAFCE_EXPECTED_SOURCE_VERSION",
            ConfigurationError,
        )
        if _VERSION.fullmatch(source_version) is None:
            raise ConfigurationError("ORAFCE_EXPECTED_SOURCE_VERSION is not a version")
        contract_path = _nonempty_text(
            environment.get(
                "ORAFCE_CONTRACT", "/usr/local/share/orafce/compatibility_contract.json"
            ),
            "ORAFCE_CONTRACT",
            ConfigurationError,
        )
        if not PurePosixPath(contract_path).is_absolute():
            raise ConfigurationError("ORAFCE_CONTRACT must be an absolute POSIX path")
        report_directory = _report_directory(
            environment.get("ORAFCE_REPORT_DIR", "/var/lib/ivorysql/reports")
        )
        return cls(
            expected_extension_version=extension_version,
            expected_source_version=source_version,
            contract_path=contract_path,
            report_directory=report_directory,
        )


@dataclass(frozen=True)
class IntegrationIdentity:
    ivorysql_ref: str
    orafce_source_version: str
    orafce_source_ref: str
    orafce_extension_version: str

    @classmethod
    def from_mapping(cls, value: Any) -> "IntegrationIdentity":
        if not isinstance(value, dict):
            raise ConfigurationError("contract.integration must be an object")
        _require_keys(
            value,
            {
                "ivorysql_ref",
                "orafce_source_version",
                "orafce_source_ref",
                "orafce_extension_version",
            },
            "contract.integration",
            error=ConfigurationError,
        )
        identity = cls(
            ivorysql_ref=_nonempty_text(
                value["ivorysql_ref"], "contract.integration.ivorysql_ref", ConfigurationError
            ),
            orafce_source_version=_nonempty_text(
                value["orafce_source_version"],
                "contract.integration.orafce_source_version",
                ConfigurationError,
            ),
            orafce_source_ref=_nonempty_text(
                value["orafce_source_ref"],
                "contract.integration.orafce_source_ref",
                ConfigurationError,
            ),
            orafce_extension_version=_nonempty_text(
                value["orafce_extension_version"],
                "contract.integration.orafce_extension_version",
                ConfigurationError,
            ),
        )
        if not identity.ivorysql_ref.startswith("IvorySQL_"):
            raise ConfigurationError("contract IvorySQL ref must be a release tag")
        if _VERSION.fullmatch(identity.orafce_source_version) is None:
            raise ConfigurationError("contract orafce source version is invalid")
        if _SOURCE_REF.fullmatch(identity.orafce_source_ref) is None:
            raise ConfigurationError("contract orafce source ref is invalid")
        if _VERSION.fullmatch(identity.orafce_extension_version) is None:
            raise ConfigurationError("contract orafce extension version is invalid")
        expected_ref = "VERSION_" + identity.orafce_source_version.replace(".", "_")
        if identity.orafce_source_ref != expected_ref:
            raise ConfigurationError("contract orafce source ref does not match source version")
        return identity


@dataclass(frozen=True)
class ContractCase:
    id: str
    category: str
    capability: str
    expected: Any
    sql_type: str
    required: bool
    migration_risk: str

    @classmethod
    def from_mapping(cls, value: Any, position: int) -> "ContractCase":
        label = f"contract.cases[{position}]"
        if not isinstance(value, dict):
            raise ConfigurationError(f"{label} must be an object")
        _require_keys(
            value,
            {
                "id",
                "category",
                "capability",
                "expected",
                "sql_type",
                "required",
                "migration_risk",
            },
            label,
            error=ConfigurationError,
        )
        case_id = _nonempty_text(value["id"], f"{label}.id", ConfigurationError)
        category = _nonempty_text(
            value["category"], f"{label}.category", ConfigurationError
        )
        sql_type = _nonempty_text(
            value["sql_type"], f"{label}.sql_type", ConfigurationError
        )
        if _CASE_ID.fullmatch(case_id) is None:
            raise ConfigurationError(f"{label}.id has an invalid format")
        if _CATEGORY.fullmatch(category) is None:
            raise ConfigurationError(f"{label}.category has an invalid format")
        if not case_id.startswith(f"{category}."):
            raise ConfigurationError(f"{label}.id must start with its category")
        if _SQL_TYPE.fullmatch(sql_type) is None:
            raise ConfigurationError(f"{label}.sql_type is unsupported")
        expected = _json_scalar(value["expected"], f"{label}.expected")
        if sql_type == "boolean" and not isinstance(expected, bool):
            raise ConfigurationError(f"{label}.expected must match boolean sql_type")
        if sql_type in {"integer", "bigint"} and (
            isinstance(expected, bool) or not isinstance(expected, int)
        ):
            raise ConfigurationError(f"{label}.expected must match integer sql_type")
        if sql_type == "text" and not isinstance(expected, str):
            raise ConfigurationError(f"{label}.expected must match text sql_type")
        return cls(
            id=case_id,
            category=category,
            capability=_nonempty_text(
                value["capability"], f"{label}.capability", ConfigurationError
            ),
            expected=expected,
            sql_type=sql_type,
            required=_boolean(value["required"], f"{label}.required", ConfigurationError),
            migration_risk=_nonempty_text(
                value["migration_risk"], f"{label}.migration_risk", ConfigurationError
            ),
        )


@dataclass(frozen=True)
class Contract:
    schema_version: int
    integration: IntegrationIdentity
    required_categories: tuple[str, ...]
    cases: tuple[ContractCase, ...]

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> "Contract":
        _require_keys(
            value,
            {"schema_version", "integration", "required_categories", "cases"},
            "contract",
            error=ConfigurationError,
        )
        schema_version = _integer(
            value["schema_version"], "contract.schema_version", ConfigurationError, 1
        )
        if schema_version != 1:
            raise ConfigurationError("contract.schema_version must be 1")
        raw_categories = value["required_categories"]
        if not isinstance(raw_categories, list) or not raw_categories:
            raise ConfigurationError("contract.required_categories must be a non-empty array")
        categories = tuple(
            _nonempty_text(item, "contract.required_categories item", ConfigurationError)
            for item in raw_categories
        )
        if tuple(sorted(categories)) != categories:
            raise ConfigurationError("contract.required_categories must be sorted")
        if len(set(categories)) != len(categories):
            raise ConfigurationError("contract.required_categories must be unique")
        if any(_CATEGORY.fullmatch(category) is None for category in categories):
            raise ConfigurationError("contract.required_categories contains an invalid name")

        raw_cases = value["cases"]
        if not isinstance(raw_cases, list):
            raise ConfigurationError("contract.cases must be an array")
        cases = tuple(
            ContractCase.from_mapping(item, position)
            for position, item in enumerate(raw_cases)
        )
        if len(cases) < _MIN_CASES:
            raise ConfigurationError(f"contract must contain at least {_MIN_CASES} cases")
        identifiers = [case.id for case in cases]
        if len(set(identifiers)) != len(identifiers):
            raise ConfigurationError("contract case identifiers must be unique")
        covered_categories = {case.category for case in cases if case.required}
        missing_categories = set(categories) - covered_categories
        if missing_categories:
            raise ConfigurationError(
                "required categories lack a required case: "
                + ", ".join(sorted(missing_categories))
            )
        unknown_categories = covered_categories - set(categories)
        if unknown_categories:
            raise ConfigurationError(
                "required cases use undeclared categories: "
                + ", ".join(sorted(unknown_categories))
            )
        return cls(
            schema_version=schema_version,
            integration=IntegrationIdentity.from_mapping(value["integration"]),
            required_categories=categories,
            cases=cases,
        )

    @classmethod
    def load(cls, path: Path) -> "Contract":
        try:
            return cls.from_mapping(_read_json_object(path, "contract"))
        except EvidenceError as exc:
            raise ConfigurationError(str(exc)) from exc

    def case_map(self) -> dict[str, ContractCase]:
        return {case.id: case for case in self.cases}


@dataclass(frozen=True)
class ResultRow:
    id: str
    actual: Any
    actual_type: str

    @classmethod
    def from_mapping(cls, value: Any, line_number: int) -> "ResultRow":
        label = f"results line {line_number}"
        if not isinstance(value, dict):
            raise EvidenceError(f"{label} must contain a JSON object")
        try:
            _require_keys(value, {"id", "actual", "actual_type"}, label)
        except HarnessError as exc:
            raise EvidenceError(str(exc)) from exc
        case_id = _nonempty_text(value["id"], f"{label}.id", EvidenceError)
        if _CASE_ID.fullmatch(case_id) is None:
            raise EvidenceError(f"{label}.id has an invalid format")
        actual_type = _nonempty_text(
            value["actual_type"], f"{label}.actual_type", EvidenceError
        )
        if _SQL_TYPE.fullmatch(actual_type) is None:
            raise EvidenceError(f"{label}.actual_type is unsupported")
        actual = value["actual"]
        if actual is not None and not isinstance(actual, (str, bool, int, float)):
            raise EvidenceError(f"{label}.actual must be a JSON scalar")
        return cls(id=case_id, actual=actual, actual_type=actual_type)


def load_results(path: Path) -> dict[str, ResultRow]:
    """Load bounded JSON Lines results and reject duplicate identifiers."""

    try:
        size = path.stat().st_size
    except OSError as exc:
        raise EvidenceError(f"cannot read results: {exc}") from exc
    if size == 0:
        raise EvidenceError("results are empty")
    if size > _MAX_RESULTS_BYTES:
        raise EvidenceError("results exceed the 2 MiB evidence limit")
    rows: dict[str, ResultRow] = {}
    try:
        with path.open("r", encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, start=1):
                if len(line.encode("utf-8")) > _MAX_RESULT_LINE_BYTES:
                    raise EvidenceError(f"results line {line_number} exceeds 64 KiB")
                if line.strip() == "":
                    raise EvidenceError(f"results line {line_number} is blank")
                try:
                    raw = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise EvidenceError(
                        f"cannot parse results line {line_number}: {exc}"
                    ) from exc
                row = ResultRow.from_mapping(raw, line_number)
                if row.id in rows:
                    raise EvidenceError(f"duplicate result identifier: {row.id}")
                rows[row.id] = row
    except (OSError, UnicodeError) as exc:
        raise EvidenceError(f"cannot read results: {exc}") from exc
    return rows


@dataclass(frozen=True)
class Metadata:
    extension_version: str
    server_version: str
    database_mode: str | None
    plisql_installed: bool
    result_count: int

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> "Metadata":
        try:
            _require_keys(
                value,
                {
                    "extension_version",
                    "server_version",
                    "database_mode",
                    "plisql_installed",
                    "result_count",
                },
                "metadata",
            )
        except HarnessError as exc:
            raise EvidenceError(str(exc)) from exc
        mode = value["database_mode"]
        if mode is not None and not isinstance(mode, str):
            raise EvidenceError("metadata.database_mode must be a string or null")
        return cls(
            extension_version=_nonempty_text(
                value["extension_version"], "metadata.extension_version", EvidenceError
            ),
            server_version=_nonempty_text(
                value["server_version"], "metadata.server_version", EvidenceError
            ),
            database_mode=mode,
            plisql_installed=_boolean(
                value["plisql_installed"], "metadata.plisql_installed", EvidenceError
            ),
            result_count=_integer(
                value["result_count"], "metadata.result_count", EvidenceError
            ),
        )


@dataclass(frozen=True)
class Check:
    id: str
    category: str
    passed: bool
    expected: Any
    actual: Any
    expected_sql_type: str
    actual_sql_type: str | None
    capability: str
    migration_risk: str


@dataclass(frozen=True)
class AuditReport:
    passed: bool
    summary: Mapping[str, int]
    integration: Mapping[str, Any]
    metadata: Mapping[str, Any]
    checks: tuple[Check, ...]

    def as_dict(self) -> dict[str, Any]:
        return {
            "passed": self.passed,
            "summary": dict(self.summary),
            "integration": dict(self.integration),
            "metadata": dict(self.metadata),
            "checks": [asdict(check) for check in self.checks],
        }


def audit(
    policy: RuntimePolicy,
    contract: Contract,
    results: Mapping[str, ResultRow],
    metadata: Metadata,
) -> AuditReport:
    """Join actual results to the manifest and evaluate every contract case."""

    declared = contract.case_map()
    unknown_results = set(results) - set(declared)
    if unknown_results:
        raise EvidenceError(
            "results contain unknown identifiers: " + ", ".join(sorted(unknown_results))
        )
    checks: list[Check] = []
    for case in contract.cases:
        row = results.get(case.id)
        actual = row.actual if row else None
        actual_type = row.actual_type if row else None
        passed = (
            row is not None
            and row.actual_type == case.sql_type
            and type(row.actual) is type(case.expected)
            and row.actual == case.expected
        )
        checks.append(
            Check(
                id=case.id,
                category=case.category,
                passed=passed,
                expected=case.expected,
                actual=actual,
                expected_sql_type=case.sql_type,
                actual_sql_type=actual_type,
                capability=case.capability,
                migration_risk=case.migration_risk,
            )
        )

    metadata_checks = {
        "extension_version": metadata.extension_version
        == contract.integration.orafce_extension_version
        == policy.expected_extension_version,
        "source_version": contract.integration.orafce_source_version
        == policy.expected_source_version,
        "server_identity": "IvorySQL" in metadata.server_version,
        "plisql_installed": metadata.plisql_installed,
        "result_count": metadata.result_count == len(results) == len(contract.cases),
    }
    required_checks = [check for check, case in zip(checks, contract.cases) if case.required]
    required_failed = sum(not check.passed for check in required_checks)
    optional_failed = sum(
        not check.passed for check, case in zip(checks, contract.cases) if not case.required
    )
    missing = sum(case.id not in results for case in contract.cases)
    summary = {
        "declared": len(contract.cases),
        "observed": len(results),
        "missing": missing,
        "required_failed": required_failed,
        "optional_failed": optional_failed,
        "passed_cases": sum(check.passed for check in checks),
        "metadata_failed": sum(not value for value in metadata_checks.values()),
    }
    integration = asdict(contract.integration)
    integration["required_categories"] = list(contract.required_categories)
    metadata_value = asdict(metadata)
    metadata_value["checks"] = metadata_checks
    passed = required_failed == 0 and all(metadata_checks.values())
    return AuditReport(
        passed=passed,
        summary=summary,
        integration=integration,
        metadata=metadata_value,
        checks=tuple(checks),
    )


def atomic_write_json(path: Path, value: Mapping[str, Any]) -> None:
    """Atomically replace a report with sorted, human-readable JSON."""

    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def validate_identity(policy: RuntimePolicy, contract: Contract) -> None:
    if policy.expected_extension_version != contract.integration.orafce_extension_version:
        raise ConfigurationError(
            "environment extension version does not match compatibility contract"
        )
    if policy.expected_source_version != contract.integration.orafce_source_version:
        raise ConfigurationError(
            "environment source version does not match compatibility contract"
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    preflight = commands.add_parser("preflight", help="validate policy and contract")
    preflight.add_argument("--contract", type=Path, required=True)
    audit_parser = commands.add_parser("audit", help="audit runtime evidence")
    audit_parser.add_argument("--contract", type=Path, required=True)
    audit_parser.add_argument("--results", type=Path, required=True)
    audit_parser.add_argument("--metadata", type=Path, required=True)
    audit_parser.add_argument("--output", type=Path, required=True)
    return parser


def run(arguments: Sequence[str], environment: Mapping[str, str]) -> int:
    options = build_parser().parse_args(arguments)
    try:
        policy = RuntimePolicy.from_environment(environment)
        contract = Contract.load(options.contract)
        validate_identity(policy, contract)
        if options.command == "preflight":
            print(
                json.dumps(
                    {
                        "valid": True,
                        "cases": len(contract.cases),
                        "categories": len(contract.required_categories),
                        "integration": asdict(contract.integration),
                    },
                    sort_keys=True,
                )
            )
            return 0

        results = load_results(options.results)
        metadata = Metadata.from_mapping(_read_json_object(options.metadata, "metadata"))
        report = audit(policy, contract, results, metadata)
        atomic_write_json(options.output, report.as_dict())
        print(json.dumps({"passed": report.passed, "output": str(options.output)}))
        return 0 if report.passed else 1
    except HarnessError as exc:
        print(f"orafce migration harness: {exc}", file=sys.stderr)
        return 2


def main() -> int:
    return run(sys.argv[1:], os.environ)


if __name__ == "__main__":
    raise SystemExit(main())
