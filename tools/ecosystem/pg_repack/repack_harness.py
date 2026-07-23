#!/usr/bin/env python3
"""Policy validation and evidence auditing for the IvorySQL pg_repack sample.

The shell integration is deliberately small and observable: it produces four
JSON evidence documents and delegates all policy decisions to this module.  The
module uses only Python's standard library so it can run in the runtime image,
in CI, and on an operator workstation before Docker is started.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from dataclasses import asdict, dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path, PurePosixPath
from typing import Any, Mapping, Sequence


class HarnessError(ValueError):
    """Base class for deterministic, user-facing harness failures."""


class ConfigurationError(HarnessError):
    """Raised when the environment describes an unsafe or invalid run."""


class EvidenceError(HarnessError):
    """Raised when an evidence document is missing or malformed."""


_SIZE_UNITS = {
    "b": 1,
    "kib": 1024,
    "mib": 1024**2,
    "gib": 1024**3,
}
_DURATION_UNITS = {
    "ms": Decimal("1"),
    "s": Decimal("1000"),
    "m": Decimal("60000"),
}
_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]*$")
_SIZE = re.compile(r"^([0-9]+)(B|KiB|MiB|GiB)$", re.IGNORECASE)
_DURATION = re.compile(r"^([0-9]+(?:\.[0-9]+)?)(ms|s|m)$", re.IGNORECASE)
_SYSTEM_SCHEMAS = {"information_schema", "pg_catalog", "pg_toast"}
_EXPECTED_EXTENSION_VERSION = "1.5.3"


def parse_integer(
    value: str,
    name: str,
    *,
    minimum: int | None = None,
    maximum: int | None = None,
) -> int:
    """Parse a base-10 integer and enforce optional inclusive bounds."""

    if not re.fullmatch(r"[0-9]+", value):
        raise ConfigurationError(f"{name} must be a non-negative base-10 integer")
    result = int(value)
    if minimum is not None and result < minimum:
        raise ConfigurationError(f"{name} must be at least {minimum}")
    if maximum is not None and result > maximum:
        raise ConfigurationError(f"{name} must be at most {maximum}")
    return result


def parse_size(value: str, name: str) -> int:
    """Parse an explicit IEC byte quantity such as ``8MiB``."""

    match = _SIZE.fullmatch(value)
    if match is None:
        raise ConfigurationError(f"{name} must use B, KiB, MiB, or GiB")
    amount = int(match.group(1))
    return amount * _SIZE_UNITS[match.group(2).lower()]


def parse_duration_ms(value: str, name: str) -> int:
    """Parse a duration with an explicit unit and return whole milliseconds."""

    match = _DURATION.fullmatch(value)
    if match is None:
        raise ConfigurationError(f"{name} must use ms, s, or m")
    try:
        amount = Decimal(match.group(1))
    except InvalidOperation as exc:  # pragma: no cover - guarded by the regex
        raise ConfigurationError(f"{name} is not a valid duration") from exc
    milliseconds = amount * _DURATION_UNITS[match.group(2).lower()]
    if milliseconds != milliseconds.to_integral_value():
        raise ConfigurationError(f"{name} must resolve to whole milliseconds")
    result = int(milliseconds)
    if result <= 0:
        raise ConfigurationError(f"{name} must be greater than zero")
    return result


def parse_ratio(value: str, name: str) -> Decimal:
    """Parse a finite decimal ratio in the closed operational range."""

    try:
        result = Decimal(value)
    except InvalidOperation as exc:
        raise ConfigurationError(f"{name} must be a decimal number") from exc
    if not result.is_finite():
        raise ConfigurationError(f"{name} must be finite")
    if result < Decimal("0.10") or result > Decimal("0.95"):
        raise ConfigurationError(f"{name} must be between 0.10 and 0.95")
    return result


def parse_identifier(value: str, name: str) -> str:
    """Accept a PostgreSQL identifier that is safe to pass as a psql value."""

    if len(value.encode("utf-8")) > 63:
        raise ConfigurationError(f"{name} must fit PostgreSQL's 63-byte limit")
    if _IDENTIFIER.fullmatch(value) is None:
        raise ConfigurationError(f"{name} is not a valid SQL identifier")
    return value


def parse_report_dir(value: str) -> str:
    """Require a narrow absolute POSIX path for container-owned reports."""

    path = PurePosixPath(value)
    if not path.is_absolute():
        raise ConfigurationError("REPACK_REPORT_DIR must be an absolute POSIX path")
    if ".." in path.parts:
        raise ConfigurationError("REPACK_REPORT_DIR must not contain parent traversal")
    if path in {PurePosixPath("/"), PurePosixPath("/tmp"), PurePosixPath("/var")}:
        raise ConfigurationError("REPACK_REPORT_DIR is too broad")
    if len(path.parts) < 4:
        raise ConfigurationError("REPACK_REPORT_DIR must contain at least three components")
    return str(path)


class Environment:
    """Typed access to a supplied environment mapping."""

    def __init__(self, values: Mapping[str, str]):
        self._values = values

    def text(self, name: str, default: str | None = None) -> str:
        value = self._values.get(name, default)
        if value is None or value == "":
            raise ConfigurationError(f"{name} is required")
        if "\x00" in value or "\n" in value or "\r" in value:
            raise ConfigurationError(f"{name} contains a forbidden control character")
        return value


@dataclass(frozen=True)
class RepackPolicy:
    """Validated operational contract derived from environment variables."""

    database: str
    user: str
    password: str
    schema: str
    table: str
    initial_rows: int
    delete_percent: int
    payload_bytes: int
    minimum_before_size: int
    minimum_saved_bytes: int
    maximum_final_ratio: Decimal
    concurrent_writes: int
    minimum_concurrent_writes: int
    maximum_write_latency_ms: int
    wait_timeout_seconds: int
    report_dir: str

    @classmethod
    def from_environment(cls, values: Mapping[str, str]) -> "RepackPolicy":
        env = Environment(values)
        database = parse_identifier(
            env.text("IVORYSQL_DATABASE", "maintenancedb"), "IVORYSQL_DATABASE"
        )
        user = parse_identifier(env.text("IVORYSQL_USER", "ivorysql"), "IVORYSQL_USER")
        password = env.text("IVORYSQL_PASSWORD")
        if len(password) < 16:
            raise ConfigurationError("IVORYSQL_PASSWORD must contain at least 16 characters")

        schema = parse_identifier(env.text("REPACK_SCHEMA", "maintenance"), "REPACK_SCHEMA")
        if schema.lower() in _SYSTEM_SCHEMAS or schema.lower().startswith("pg_"):
            raise ConfigurationError("REPACK_SCHEMA must not be a PostgreSQL system schema")
        table = parse_identifier(env.text("REPACK_TABLE", "orders"), "REPACK_TABLE")
        if schema == table:
            raise ConfigurationError("REPACK_SCHEMA and REPACK_TABLE must be distinct")

        initial_rows = parse_integer(
            env.text("REPACK_INITIAL_ROWS", "24000"),
            "REPACK_INITIAL_ROWS",
            minimum=5000,
            maximum=2_000_000,
        )
        delete_percent = parse_integer(
            env.text("REPACK_DELETE_PERCENT", "75"),
            "REPACK_DELETE_PERCENT",
            minimum=20,
            maximum=90,
        )
        payload_bytes = parse_integer(
            env.text("REPACK_PAYLOAD_BYTES", "1024"),
            "REPACK_PAYLOAD_BYTES",
            minimum=128,
            maximum=4096,
        )
        minimum_before_size = parse_size(
            env.text("REPACK_MIN_BEFORE_SIZE", "8MiB"), "REPACK_MIN_BEFORE_SIZE"
        )
        minimum_saved_bytes = parse_size(
            env.text("REPACK_MIN_SAVED_BYTES", "4MiB"), "REPACK_MIN_SAVED_BYTES"
        )
        if minimum_saved_bytes >= minimum_before_size:
            raise ConfigurationError(
                "REPACK_MIN_SAVED_BYTES must be smaller than REPACK_MIN_BEFORE_SIZE"
            )

        maximum_final_ratio = parse_ratio(
            env.text("REPACK_MAX_FINAL_RATIO", "0.55"), "REPACK_MAX_FINAL_RATIO"
        )
        concurrent_writes = parse_integer(
            env.text("REPACK_CONCURRENT_WRITES", "40"),
            "REPACK_CONCURRENT_WRITES",
            minimum=10,
            maximum=1000,
        )
        minimum_concurrent_writes = parse_integer(
            env.text("REPACK_MIN_CONCURRENT_WRITES", "30"),
            "REPACK_MIN_CONCURRENT_WRITES",
            minimum=1,
            maximum=1000,
        )
        if minimum_concurrent_writes > concurrent_writes:
            raise ConfigurationError(
                "REPACK_MIN_CONCURRENT_WRITES must not exceed REPACK_CONCURRENT_WRITES"
            )

        maximum_write_latency_ms = parse_duration_ms(
            env.text("REPACK_MAX_WRITE_LATENCY", "5s"),
            "REPACK_MAX_WRITE_LATENCY",
        )
        wait_timeout_seconds = parse_integer(
            env.text("REPACK_WAIT_TIMEOUT", "60"),
            "REPACK_WAIT_TIMEOUT",
            minimum=1,
            maximum=300,
        )
        report_dir = parse_report_dir(
            env.text("REPACK_REPORT_DIR", "/var/lib/ivorysql/reports")
        )
        return cls(
            database=database,
            user=user,
            password=password,
            schema=schema,
            table=table,
            initial_rows=initial_rows,
            delete_percent=delete_percent,
            payload_bytes=payload_bytes,
            minimum_before_size=minimum_before_size,
            minimum_saved_bytes=minimum_saved_bytes,
            maximum_final_ratio=maximum_final_ratio,
            concurrent_writes=concurrent_writes,
            minimum_concurrent_writes=minimum_concurrent_writes,
            maximum_write_latency_ms=maximum_write_latency_ms,
            wait_timeout_seconds=wait_timeout_seconds,
            report_dir=report_dir,
        )

    def public_dict(self) -> dict[str, Any]:
        """Return reportable policy values without exposing the password."""

        data = asdict(self)
        data.pop("password")
        data["maximum_final_ratio"] = str(self.maximum_final_ratio)
        return data


def _object(value: Any, document: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise EvidenceError(f"{document} must contain one JSON object")
    return value


def _integer(
    values: Mapping[str, Any], name: str, document: str, *, minimum: int = 0
) -> int:
    value = values.get(name)
    if isinstance(value, bool) or not isinstance(value, int):
        raise EvidenceError(f"{document}.{name} must be an integer")
    if value < minimum:
        raise EvidenceError(f"{document}.{name} must be at least {minimum}")
    return value


def _boolean(values: Mapping[str, Any], name: str, document: str) -> bool:
    value = values.get(name)
    if not isinstance(value, bool):
        raise EvidenceError(f"{document}.{name} must be a boolean")
    return value


def _text(values: Mapping[str, Any], name: str, document: str) -> str:
    value = values.get(name)
    if not isinstance(value, str) or value == "":
        raise EvidenceError(f"{document}.{name} must be a non-empty string")
    return value


def load_json(path: Path, document: str) -> Mapping[str, Any]:
    """Load one bounded JSON object from disk with useful error messages."""

    try:
        size = path.stat().st_size
    except OSError as exc:
        raise EvidenceError(f"cannot read {document}: {exc}") from exc
    if size == 0:
        raise EvidenceError(f"{document} is empty")
    if size > 1024 * 1024:
        raise EvidenceError(f"{document} exceeds the 1 MiB evidence limit")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise EvidenceError(f"cannot parse {document}: {exc}") from exc
    return _object(value, document)


@dataclass(frozen=True)
class RelationMetrics:
    total_size: int
    heap_size: int
    index_size: int
    row_count: int
    stable_rows: int
    stable_checksum: str
    index_count: int
    indexes_healthy: bool
    extension_version: str
    server_version: str

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any], document: str) -> "RelationMetrics":
        result = cls(
            total_size=_integer(value, "total_size", document),
            heap_size=_integer(value, "heap_size", document),
            index_size=_integer(value, "index_size", document),
            row_count=_integer(value, "row_count", document),
            stable_rows=_integer(value, "stable_rows", document),
            stable_checksum=_text(value, "stable_checksum", document),
            index_count=_integer(value, "index_count", document),
            indexes_healthy=_boolean(value, "indexes_healthy", document),
            extension_version=_text(value, "extension_version", document),
            server_version=_text(value, "server_version", document),
        )
        if result.heap_size > result.total_size:
            raise EvidenceError(f"{document}.heap_size exceeds total_size")
        if result.index_size > result.total_size:
            raise EvidenceError(f"{document}.index_size exceeds total_size")
        if result.stable_rows > result.row_count:
            raise EvidenceError(f"{document}.stable_rows exceeds row_count")
        if re.fullmatch(r"[0-9a-f]{32}", result.stable_checksum) is None:
            raise EvidenceError(f"{document}.stable_checksum must be lowercase MD5 hex")
        return result


@dataclass(frozen=True)
class WriterMetrics:
    started_ms: int
    finished_ms: int
    attempted: int
    succeeded: int
    errors: int
    max_latency_ms: int

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> "WriterMetrics":
        result = cls(
            started_ms=_integer(value, "started_ms", "writer", minimum=1),
            finished_ms=_integer(value, "finished_ms", "writer", minimum=1),
            attempted=_integer(value, "attempted", "writer"),
            succeeded=_integer(value, "succeeded", "writer"),
            errors=_integer(value, "errors", "writer"),
            max_latency_ms=_integer(value, "max_latency_ms", "writer"),
        )
        if result.finished_ms < result.started_ms:
            raise EvidenceError("writer.finished_ms precedes writer.started_ms")
        if result.succeeded + result.errors != result.attempted:
            raise EvidenceError("writer outcomes do not equal attempted operations")
        return result


@dataclass(frozen=True)
class ExecutionMetrics:
    started_ms: int
    finished_ms: int
    exit_code: int

    @classmethod
    def from_mapping(cls, value: Mapping[str, Any]) -> "ExecutionMetrics":
        result = cls(
            started_ms=_integer(value, "started_ms", "execution", minimum=1),
            finished_ms=_integer(value, "finished_ms", "execution", minimum=1),
            exit_code=_integer(value, "exit_code", "execution"),
        )
        if result.finished_ms < result.started_ms:
            raise EvidenceError("execution.finished_ms precedes execution.started_ms")
        return result


@dataclass(frozen=True)
class Finding:
    code: str
    passed: bool
    expected: Any
    actual: Any
    detail: str


@dataclass(frozen=True)
class AuditReport:
    passed: bool
    target: str
    reclaimed_bytes: int
    final_ratio: str
    policy: Mapping[str, Any]
    evidence: Mapping[str, Any]
    checks: Sequence[Finding]

    def as_dict(self) -> dict[str, Any]:
        return {
            "passed": self.passed,
            "target": self.target,
            "reclaimed_bytes": self.reclaimed_bytes,
            "final_ratio": self.final_ratio,
            "policy": dict(self.policy),
            "evidence": dict(self.evidence),
            "checks": [asdict(check) for check in self.checks],
        }


def _finding(code: str, passed: bool, expected: Any, actual: Any, detail: str) -> Finding:
    return Finding(code=code, passed=passed, expected=expected, actual=actual, detail=detail)


def audit(
    policy: RepackPolicy,
    before: RelationMetrics,
    after: RelationMetrics,
    writer: WriterMetrics,
    execution: ExecutionMetrics,
) -> AuditReport:
    """Evaluate all online-reorganization invariants without short-circuiting."""

    reclaimed = before.total_size - after.total_size
    ratio = (
        Decimal(after.total_size) / Decimal(before.total_size)
        if before.total_size
        else Decimal("Infinity")
    )
    ratio_text = format(ratio.quantize(Decimal("0.0001")), "f") if ratio.is_finite() else "Infinity"
    expected_rows = before.row_count + writer.succeeded
    overlap_ms = max(
        0,
        min(writer.finished_ms, execution.finished_ms)
        - max(writer.started_ms, execution.started_ms),
    )

    checks = [
        _finding(
            "repack-exit",
            execution.exit_code == 0,
            0,
            execution.exit_code,
            "pg_repack must finish successfully",
        ),
        _finding(
            "minimum-before-size",
            before.total_size >= policy.minimum_before_size,
            f">={policy.minimum_before_size}",
            before.total_size,
            "the fixture must be large enough for a meaningful storage assertion",
        ),
        _finding(
            "minimum-reclaimed-bytes",
            reclaimed >= policy.minimum_saved_bytes,
            f">={policy.minimum_saved_bytes}",
            reclaimed,
            "online reorganization must reclaim the configured byte floor",
        ),
        _finding(
            "maximum-final-ratio",
            ratio <= policy.maximum_final_ratio,
            f"<={policy.maximum_final_ratio}",
            ratio_text,
            "the rebuilt relation must meet the configured compaction ratio",
        ),
        _finding(
            "stable-row-count",
            before.stable_rows == after.stable_rows,
            before.stable_rows,
            after.stable_rows,
            "rows outside the concurrent-writer namespace must not disappear",
        ),
        _finding(
            "stable-row-checksum",
            before.stable_checksum == after.stable_checksum,
            before.stable_checksum,
            after.stable_checksum,
            "stable application data must remain byte-for-byte equivalent",
        ),
        _finding(
            "final-row-count",
            after.row_count == expected_rows,
            expected_rows,
            after.row_count,
            "final rows must equal the baseline plus committed writer inserts",
        ),
        _finding(
            "writer-attempt-count",
            writer.attempted == policy.concurrent_writes,
            policy.concurrent_writes,
            writer.attempted,
            "the writer must execute the configured transaction count",
        ),
        _finding(
            "writer-success-floor",
            writer.succeeded >= policy.minimum_concurrent_writes,
            f">={policy.minimum_concurrent_writes}",
            writer.succeeded,
            "enough foreground transactions must commit during maintenance",
        ),
        _finding(
            "writer-errors",
            writer.errors == 0,
            0,
            writer.errors,
            "foreground writes must not fail",
        ),
        _finding(
            "writer-latency",
            writer.max_latency_ms <= policy.maximum_write_latency_ms,
            f"<={policy.maximum_write_latency_ms}",
            writer.max_latency_ms,
            "maximum foreground transaction latency must stay within policy",
        ),
        _finding(
            "timeline-overlap",
            overlap_ms > 0,
            ">0",
            overlap_ms,
            "writer and pg_repack intervals must overlap",
        ),
        _finding(
            "index-count-before",
            before.index_count >= 3,
            ">=3",
            before.index_count,
            "fixture must cover primary, unique, and secondary indexes",
        ),
        _finding(
            "index-count-preserved",
            after.index_count == before.index_count,
            before.index_count,
            after.index_count,
            "online reorganization must preserve every table index",
        ),
        _finding(
            "indexes-healthy-before",
            before.indexes_healthy,
            True,
            before.indexes_healthy,
            "baseline indexes must be valid and ready",
        ),
        _finding(
            "indexes-healthy-after",
            after.indexes_healthy,
            True,
            after.indexes_healthy,
            "rebuilt indexes must be valid and ready",
        ),
        _finding(
            "extension-version-before",
            before.extension_version == _EXPECTED_EXTENSION_VERSION,
            _EXPECTED_EXTENSION_VERSION,
            before.extension_version,
            "the tested pg_repack version must match the pinned integration",
        ),
        _finding(
            "extension-version-preserved",
            after.extension_version == before.extension_version,
            before.extension_version,
            after.extension_version,
            "maintenance must not change the extension version",
        ),
        _finding(
            "ivorysql-server-before",
            "IvorySQL" in before.server_version,
            "contains IvorySQL",
            before.server_version,
            "the integration must run against IvorySQL",
        ),
        _finding(
            "server-version-preserved",
            after.server_version == before.server_version,
            before.server_version,
            after.server_version,
            "server identity must remain stable across the run",
        ),
    ]
    evidence = {
        "before": asdict(before),
        "after": asdict(after),
        "writer": asdict(writer),
        "execution": asdict(execution),
        "overlap_ms": overlap_ms,
    }
    return AuditReport(
        passed=all(check.passed for check in checks),
        target=f"{policy.schema}.{policy.table}",
        reclaimed_bytes=reclaimed,
        final_ratio=ratio_text,
        policy=policy.public_dict(),
        evidence=evidence,
        checks=checks,
    )


def atomic_write_json(path: Path, value: Mapping[str, Any]) -> None:
    """Write a report atomically so readers never observe partial JSON."""

    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("preflight", help="validate environment policy")
    audit_parser = commands.add_parser("audit", help="audit captured evidence")
    audit_parser.add_argument("--before", type=Path, required=True)
    audit_parser.add_argument("--after", type=Path, required=True)
    audit_parser.add_argument("--writer", type=Path, required=True)
    audit_parser.add_argument("--execution", type=Path, required=True)
    audit_parser.add_argument("--output", type=Path, required=True)
    return parser


def run(arguments: Sequence[str], environment: Mapping[str, str]) -> int:
    options = build_parser().parse_args(arguments)
    try:
        policy = RepackPolicy.from_environment(environment)
        if options.command == "preflight":
            print(json.dumps({"valid": True, "policy": policy.public_dict()}, sort_keys=True))
            return 0

        before = RelationMetrics.from_mapping(load_json(options.before, "before"), "before")
        after = RelationMetrics.from_mapping(load_json(options.after, "after"), "after")
        writer = WriterMetrics.from_mapping(load_json(options.writer, "writer"))
        execution = ExecutionMetrics.from_mapping(load_json(options.execution, "execution"))
        report = audit(policy, before, after, writer, execution)
        atomic_write_json(options.output, report.as_dict())
        print(json.dumps({"passed": report.passed, "output": str(options.output)}))
        return 0 if report.passed else 1
    except HarnessError as exc:
        print(f"repack harness: {exc}", file=sys.stderr)
        return 2


def main() -> int:
    return run(sys.argv[1:], os.environ)


if __name__ == "__main__":
    raise SystemExit(main())
