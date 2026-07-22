#!/usr/bin/env python3
"""Build, benchmark, and audit VectorChord search on IvorySQL."""

from __future__ import annotations

import argparse
import dataclasses
import enum
import getpass
import json
import math
import os
import pathlib
import re
import statistics
import subprocess
import sys
import time
from collections.abc import Mapping, Sequence
from typing import Any


IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,62}$")
VECTOR_PATTERN = re.compile(r"^\[(?:-?[0-9]+(?:\.[0-9]+)?(?:e[+-]?[0-9]+)?)(?:,-?[0-9]+(?:\.[0-9]+)?(?:e[+-]?[0-9]+)?)*\]$", re.IGNORECASE)


class HarnessError(RuntimeError):
    """Base class for actionable vector-search failures."""


class ConfigurationError(HarnessError):
    """Raised when benchmark or index policy is invalid."""


class CommandError(HarnessError):
    """Raised when an IvorySQL command fails."""


class BenchmarkError(HarnessError):
    """Raised when output is malformed or search quality misses policy."""


class DistanceMetric(str, enum.Enum):
    L2 = "l2"
    COSINE = "cosine"
    INNER_PRODUCT = "inner_product"

    @property
    def operator(self) -> str:
        return {
            DistanceMetric.L2: "<->",
            DistanceMetric.COSINE: "<=>",
            DistanceMetric.INNER_PRODUCT: "<#>",
        }[self]

    @property
    def operator_class(self) -> str:
        return {
            DistanceMetric.L2: "vector_l2_ops",
            DistanceMetric.COSINE: "vector_cosine_ops",
            DistanceMetric.INNER_PRODUCT: "vector_ip_ops",
        }[self]


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


def parse_float(
    raw: str,
    *,
    name: str,
    minimum: float | None = None,
    maximum: float | None = None,
) -> float:
    try:
        result = float(raw)
    except ValueError as exc:
        raise ConfigurationError(f"{name} must be a number") from exc
    if not math.isfinite(result):
        raise ConfigurationError(f"{name} must be finite")
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


def percentile(values: Sequence[float], percentage: float) -> float:
    if not values:
        raise ValueError("cannot calculate percentile of an empty sequence")
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = percentage / 100 * (len(ordered) - 1)
    lower = int(rank)
    upper = min(lower + 1, len(ordered) - 1)
    fraction = rank - lower
    return ordered[lower] + fraction * (ordered[upper] - ordered[lower])


@dataclasses.dataclass(frozen=True, slots=True)
class ConnectionSpec:
    host: str
    port: int
    database: str
    user: str
    password: str

    def __post_init__(self) -> None:
        if not self.host or any(character.isspace() for character in self.host):
            raise ConfigurationError("IVORYSQL_HOST is invalid")
        if not 1 <= self.port <= 65535:
            raise ConfigurationError("IVORYSQL_PORT is out of range")
        identifier(self.database, name="IVORYSQL_DATABASE")
        identifier(self.user, name="IVORYSQL_USER")
        if len(self.password) < 12:
            raise ConfigurationError("IVORYSQL_PASSWORD must contain at least 12 characters")


@dataclasses.dataclass(frozen=True, slots=True)
class IndexPolicy:
    schema: str
    table: str
    index_name: str
    dimension: int
    metric: DistanceMetric
    dataset_rows: int
    list_count: int
    probes: int
    epsilon: float
    build_threads: int
    sampling_factor: int
    residual_quantization: bool
    spherical_centroids: bool
    query_count: int
    neighbors: int
    minimum_average_recall: float
    minimum_query_recall: float
    maximum_p95_ms: float
    maximum_index_table_ratio: float

    def __post_init__(self) -> None:
        for label, raw in (
            ("VECTOR_SCHEMA", self.schema),
            ("VECTOR_TABLE", self.table),
            ("VECTOR_INDEX_NAME", self.index_name),
        ):
            identifier(raw, name=label)
        if not 1 <= self.dimension <= 16000:
            raise ConfigurationError("VECTOR_DIMENSION must be between 1 and 16000")
        if self.dataset_rows < 1000:
            raise ConfigurationError("VECTOR_DATASET_ROWS must be at least 1000")
        if self.list_count < 1 or self.list_count >= self.dataset_rows:
            raise ConfigurationError("VECTOR_LIST_COUNT must be positive and smaller than dataset rows")
        if not 1 <= self.probes <= self.list_count:
            raise ConfigurationError("VECTOR_PROBES must be between 1 and list count")
        if not 0 <= self.epsilon <= 4:
            raise ConfigurationError("VECTOR_EPSILON must be between 0 and 4")
        if not 1 <= self.build_threads <= 255:
            raise ConfigurationError("VECTOR_BUILD_THREADS must be between 1 and 255")
        if not 0 <= self.sampling_factor <= 1024:
            raise ConfigurationError("VECTOR_SAMPLING_FACTOR must be between 0 and 1024")
        if not 1 <= self.neighbors <= 1000:
            raise ConfigurationError("VECTOR_NEIGHBORS must be between 1 and 1000")
        if not 1 <= self.query_count <= min(self.dataset_rows, 1000):
            raise ConfigurationError("VECTOR_QUERY_COUNT is out of range")
        if not 0 <= self.minimum_query_recall <= self.minimum_average_recall <= 1:
            raise ConfigurationError(
                "recall thresholds must satisfy 0 <= minimum query <= minimum average <= 1"
            )
        if self.maximum_p95_ms <= 0:
            raise ConfigurationError("VECTOR_MAXIMUM_P95_MS must be positive")
        if self.maximum_index_table_ratio <= 0:
            raise ConfigurationError("VECTOR_MAX_INDEX_TABLE_RATIO must be positive")
        if self.metric is not DistanceMetric.COSINE and self.spherical_centroids:
            raise ConfigurationError("spherical centroids are only valid for cosine distance")

    @property
    def qualified_table(self) -> str:
        return f"{self.schema}.{self.table}"

    @property
    def qualified_index(self) -> str:
        return f"{self.schema}.{self.index_name}"


@dataclasses.dataclass(frozen=True, slots=True)
class RuntimeSpec:
    connection: ConnectionSpec
    policy: IndexPolicy

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
            database=env_value(source, "IVORYSQL_DATABASE", "vectordb"),
            user=env_value(source, "IVORYSQL_USER", "ivorysql"),
            password=env_value(source, "IVORYSQL_PASSWORD", "ivorysql-vector-secret"),
        )
        try:
            metric = DistanceMetric(
                env_value(source, "VECTOR_DISTANCE_METRIC", "cosine").lower()
            )
        except ValueError as exc:
            raise ConfigurationError(
                "VECTOR_DISTANCE_METRIC must be l2, cosine, or inner_product"
            ) from exc
        policy = IndexPolicy(
            schema=env_value(source, "VECTOR_SCHEMA", "ai"),
            table=env_value(source, "VECTOR_TABLE", "documents"),
            index_name=env_value(source, "VECTOR_INDEX_NAME", "documents_embedding_vchordrq"),
            dimension=parse_int(
                env_value(source, "VECTOR_DIMENSION", "128"),
                name="VECTOR_DIMENSION",
                minimum=1,
                maximum=16000,
            ),
            metric=metric,
            dataset_rows=parse_int(
                env_value(source, "VECTOR_DATASET_ROWS", "25000"),
                name="VECTOR_DATASET_ROWS",
                minimum=1000,
            ),
            list_count=parse_int(
                env_value(source, "VECTOR_LIST_COUNT", "64"),
                name="VECTOR_LIST_COUNT",
                minimum=1,
            ),
            probes=parse_int(
                env_value(source, "VECTOR_PROBES", "8"),
                name="VECTOR_PROBES",
                minimum=1,
            ),
            epsilon=parse_float(
                env_value(source, "VECTOR_EPSILON", "1.9"),
                name="VECTOR_EPSILON",
                minimum=0,
                maximum=4,
            ),
            build_threads=parse_int(
                env_value(source, "VECTOR_BUILD_THREADS", "4"),
                name="VECTOR_BUILD_THREADS",
                minimum=1,
                maximum=255,
            ),
            sampling_factor=parse_int(
                env_value(source, "VECTOR_SAMPLING_FACTOR", "64"),
                name="VECTOR_SAMPLING_FACTOR",
                minimum=0,
                maximum=1024,
            ),
            residual_quantization=parse_bool(
                env_value(source, "VECTOR_RESIDUAL_QUANTIZATION", "true"),
                name="VECTOR_RESIDUAL_QUANTIZATION",
            ),
            spherical_centroids=parse_bool(
                env_value(source, "VECTOR_SPHERICAL_CENTROIDS", "true"),
                name="VECTOR_SPHERICAL_CENTROIDS",
            ),
            query_count=parse_int(
                env_value(source, "VECTOR_QUERY_COUNT", "20"),
                name="VECTOR_QUERY_COUNT",
                minimum=1,
                maximum=1000,
            ),
            neighbors=parse_int(
                env_value(source, "VECTOR_NEIGHBORS", "10"),
                name="VECTOR_NEIGHBORS",
                minimum=1,
                maximum=1000,
            ),
            minimum_average_recall=parse_float(
                env_value(source, "VECTOR_MIN_AVERAGE_RECALL", "0.90"),
                name="VECTOR_MIN_AVERAGE_RECALL",
                minimum=0,
                maximum=1,
            ),
            minimum_query_recall=parse_float(
                env_value(source, "VECTOR_MIN_QUERY_RECALL", "0.70"),
                name="VECTOR_MIN_QUERY_RECALL",
                minimum=0,
                maximum=1,
            ),
            maximum_p95_ms=parse_float(
                env_value(source, "VECTOR_MAXIMUM_P95_MS", "500"),
                name="VECTOR_MAXIMUM_P95_MS",
                minimum=0.001,
            ),
            maximum_index_table_ratio=parse_float(
                env_value(source, "VECTOR_MAX_INDEX_TABLE_RATIO", "1.50"),
                name="VECTOR_MAX_INDEX_TABLE_RATIO",
                minimum=0.001,
            ),
        )
        return cls(connection=connection, policy=policy)


def index_options(policy: IndexPolicy) -> str:
    return "\n".join(
        (
            f"residual_quantization = {'true' if policy.residual_quantization else 'false'}",
            "[build.internal]",
            f"lists = [{policy.list_count}]",
            f"spherical_centroids = {'true' if policy.spherical_centroids else 'false'}",
            f"build_threads = {policy.build_threads}",
            f"sampling_factor = {policy.sampling_factor}",
        )
    )


def render_setup_sql(spec: RuntimeSpec) -> str:
    policy = spec.policy
    return f"""CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS vchord CASCADE;
CREATE SCHEMA IF NOT EXISTS {policy.schema};

DROP TABLE IF EXISTS {policy.qualified_table} CASCADE;
CREATE TABLE {policy.qualified_table} (
    document_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id integer NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    embedding vector({policy.dimension}) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

INSERT INTO {policy.qualified_table} (tenant_id, title, body, embedding)
SELECT 1 + (item % 100),
       'document-' || item,
       'deterministic VectorChord verification row ' || item,
       ARRAY(
           SELECT (
               (hashtextextended(item::text || ':' || dimension::text, 42)::bigint % 2000001)
               / 1000000.0
           )::real
             FROM generate_series(1, {policy.dimension}) AS dimension
            ORDER BY dimension
       )::vector
  FROM generate_series(1, {policy.dataset_rows}) AS item;

ANALYZE {policy.qualified_table};
SET maintenance_work_mem = '512MB';
SET max_parallel_maintenance_workers = {min(policy.build_threads, 8)};
CREATE INDEX {policy.index_name}
    ON {policy.qualified_table}
 USING vchordrq (embedding {policy.metric.operator_class})
 WITH (options = $options$
{index_options(policy)}
$options$);
ANALYZE {policy.qualified_table};
"""


def render_smoke_sql(spec: RuntimeSpec) -> str:
    policy = spec.policy
    query_id = max(1, policy.dataset_rows // 2)
    return f"""SET vchordrq.probes = '{policy.probes}';
SET vchordrq.epsilon = {policy.epsilon:g};
SELECT document_id, title,
       embedding {policy.metric.operator} (
           SELECT embedding FROM {policy.qualified_table} WHERE document_id = {query_id}
       ) AS distance
  FROM {policy.qualified_table}
 ORDER BY embedding {policy.metric.operator} (
           SELECT embedding FROM {policy.qualified_table} WHERE document_id = {query_id}
       )
 LIMIT {policy.neighbors};
"""


def render_metadata_sql(spec: RuntimeSpec) -> str:
    policy = spec.policy
    return f"""SELECT json_build_object(
    'ivorysql_version', version(),
    'server_version', current_setting('server_version'),
    'vector_version', (SELECT extversion FROM pg_extension WHERE extname = 'vector'),
    'vchord_version', (SELECT extversion FROM pg_extension WHERE extname = 'vchord'),
    'row_count', (SELECT count(*) FROM {policy.qualified_table}),
    'table_bytes', pg_table_size({quote_literal(policy.qualified_table)}),
    'index_bytes', pg_relation_size({quote_literal(policy.qualified_index)}),
    'index_valid', (
        SELECT indisvalid AND indisready
          FROM pg_index
         WHERE indexrelid = {quote_literal(policy.qualified_index)}::regclass
    )
);"""


def query_ids(policy: IndexPolicy) -> tuple[int, ...]:
    if policy.query_count == 1:
        return (max(1, policy.dataset_rows // 2),)
    step = (policy.dataset_rows - 1) / (policy.query_count - 1)
    values = tuple(1 + round(index * step) for index in range(policy.query_count))
    return tuple(dict.fromkeys(values))


def validate_vector(raw: str, dimension: int) -> str:
    compact = raw.strip().replace(" ", "")
    if not VECTOR_PATTERN.fullmatch(compact):
        raise BenchmarkError("database returned an invalid vector literal")
    if compact.count(",") + 1 != dimension:
        raise BenchmarkError("database returned a vector with the wrong dimension")
    return compact


def render_recall_sql(spec: RuntimeSpec, vector: str) -> str:
    policy = spec.policy
    validate_vector(vector, policy.dimension)
    search = (
        f"SELECT ctid FROM {policy.qualified_table} "
        f"ORDER BY embedding {policy.metric.operator} {quote_literal(vector)}::vector "
        f"LIMIT {policy.neighbors}"
    )
    return f"""SET vchordrq.probes = '{policy.probes}';
SET vchordrq.epsilon = {policy.epsilon:g};
SELECT vchordrq_evaluate_query_recall(
    query => {quote_literal(search)},
    exact_search => true
);"""


def render_explain_sql(spec: RuntimeSpec, vector: str) -> str:
    policy = spec.policy
    validate_vector(vector, policy.dimension)
    return f"""SET vchordrq.probes = '{policy.probes}';
SET vchordrq.epsilon = {policy.epsilon:g};
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT document_id
  FROM {policy.qualified_table}
 ORDER BY embedding {policy.metric.operator} {quote_literal(vector)}::vector
 LIMIT {policy.neighbors};"""


def write_sql_files(spec: RuntimeSpec, output: pathlib.Path) -> list[pathlib.Path]:
    output.mkdir(parents=True, exist_ok=True)
    files = {
        "setup.sql": render_setup_sql(spec),
        "smoke.sql": render_smoke_sql(spec),
        "metadata.sql": render_metadata_sql(spec),
    }
    paths: list[pathlib.Path] = []
    for name, contents in files.items():
        target = output / name
        target.write_text(contents, encoding="utf-8", newline="\n")
        paths.append(target)
    return paths


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
                timeout=timeout,
                env=merged,
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
    sql: str,
    *,
    runner: CommandRunner | None = None,
    timeout: float = 300,
) -> str:
    connection = spec.connection
    command = [
        "psql",
        "--no-psqlrc",
        "--set",
        "ON_ERROR_STOP=1",
        "--tuples-only",
        "--no-align",
        "--quiet",
        "--host",
        connection.host,
        "--port",
        str(connection.port),
        "--username",
        connection.user,
        "--dbname",
        connection.database,
        "--command",
        sql,
    ]
    result = (runner or CommandRunner()).run(
        command,
        env={"PGPASSWORD": connection.password},
        timeout=timeout,
    )
    return result.stdout.strip()


def parse_json_value(raw: str, *, name: str) -> Any:
    value = raw.strip()
    if not value:
        raise BenchmarkError(f"{name} query returned no data")
    try:
        return json.loads(value)
    except json.JSONDecodeError as exc:
        raise BenchmarkError(f"{name} query returned invalid JSON") from exc


def walk_plan(node: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    result = [node]
    for child in node.get("Plans", []):
        if isinstance(child, dict):
            result.extend(walk_plan(child))
    return result


@dataclasses.dataclass(frozen=True, slots=True)
class PlanMetrics:
    execution_ms: float
    planning_ms: float
    index_used: bool
    index_name: str | None
    shared_hit_blocks: int
    shared_read_blocks: int
    rows_returned: int

    @classmethod
    def from_explain(cls, payload: Any, expected_index: str) -> "PlanMetrics":
        try:
            if not isinstance(payload, list) or not payload:
                raise TypeError("top level is not a non-empty list")
            document = payload[0]
            root = document["Plan"]
            nodes = walk_plan(root)
            index_nodes = [
                node
                for node in nodes
                if "Index" in str(node.get("Node Type", ""))
                and node.get("Index Name") == expected_index
            ]
            used = bool(index_nodes)
            index_name = str(index_nodes[0]["Index Name"]) if index_nodes else None
            return cls(
                execution_ms=float(document["Execution Time"]),
                planning_ms=float(document["Planning Time"]),
                index_used=used,
                index_name=index_name,
                shared_hit_blocks=sum(int(node.get("Shared Hit Blocks", 0)) for node in nodes),
                shared_read_blocks=sum(int(node.get("Shared Read Blocks", 0)) for node in nodes),
                rows_returned=int(root.get("Actual Rows", 0)),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise BenchmarkError(f"malformed EXPLAIN JSON: {exc}") from exc


@dataclasses.dataclass(frozen=True, slots=True)
class QuerySample:
    query_id: int
    recall: float
    plan: PlanMetrics


@dataclasses.dataclass(frozen=True, slots=True)
class BenchmarkReport:
    metadata: Mapping[str, Any]
    samples: tuple[QuerySample, ...]
    average_recall: float
    minimum_recall: float
    p50_ms: float
    p95_ms: float
    maximum_ms: float
    index_usage_rate: float
    index_table_ratio: float
    problems: tuple[str, ...]

    def as_dict(self) -> dict[str, Any]:
        return {
            "metadata": dict(self.metadata),
            "summary": {
                "query_count": len(self.samples),
                "average_recall": self.average_recall,
                "minimum_recall": self.minimum_recall,
                "p50_ms": self.p50_ms,
                "p95_ms": self.p95_ms,
                "maximum_ms": self.maximum_ms,
                "index_usage_rate": self.index_usage_rate,
                "index_table_ratio": self.index_table_ratio,
            },
            "problems": list(self.problems),
            "samples": [
                {
                    "query_id": sample.query_id,
                    "recall": sample.recall,
                    "plan": dataclasses.asdict(sample.plan),
                }
                for sample in self.samples
            ],
        }


def validate_metadata(spec: RuntimeSpec, metadata: Mapping[str, Any]) -> list[str]:
    policy = spec.policy
    problems: list[str] = []
    required = {
        "ivorysql_version",
        "server_version",
        "vector_version",
        "vchord_version",
        "row_count",
        "table_bytes",
        "index_bytes",
        "index_valid",
    }
    missing = required - set(metadata)
    if missing:
        return ["metadata is missing: " + ", ".join(sorted(missing))]
    if "ivorysql" not in str(metadata["ivorysql_version"]).lower():
        problems.append("server does not report IvorySQL")
    if int(metadata["row_count"]) != policy.dataset_rows:
        problems.append(
            f"dataset contains {metadata['row_count']} rows, expected {policy.dataset_rows}"
        )
    if not metadata["vector_version"]:
        problems.append("pgvector extension version is missing")
    if not metadata["vchord_version"]:
        problems.append("VectorChord extension version is missing")
    if metadata["index_valid"] is not True:
        problems.append("VectorChord index is not valid and ready")
    return problems


def build_report(
    spec: RuntimeSpec,
    metadata: Mapping[str, Any],
    samples: Sequence[QuerySample],
) -> BenchmarkReport:
    if not samples:
        raise BenchmarkError("benchmark produced no query samples")
    recalls = [sample.recall for sample in samples]
    latencies = [sample.plan.execution_ms for sample in samples]
    average_recall = statistics.fmean(recalls)
    minimum_recall = min(recalls)
    index_usage_rate = sum(sample.plan.index_used for sample in samples) / len(samples)
    table_bytes = int(metadata.get("table_bytes", 0))
    index_bytes = int(metadata.get("index_bytes", 0))
    ratio = index_bytes / table_bytes if table_bytes else math.inf
    problems = validate_metadata(spec, metadata)
    if average_recall < spec.policy.minimum_average_recall:
        problems.append(
            f"average recall {average_recall:.4f} is below "
            f"{spec.policy.minimum_average_recall:.4f}"
        )
    if minimum_recall < spec.policy.minimum_query_recall:
        problems.append(
            f"minimum recall {minimum_recall:.4f} is below "
            f"{spec.policy.minimum_query_recall:.4f}"
        )
    p95 = percentile(latencies, 95)
    if p95 > spec.policy.maximum_p95_ms:
        problems.append(
            f"p95 execution time {p95:.3f}ms exceeds {spec.policy.maximum_p95_ms:.3f}ms"
        )
    if index_usage_rate < 1:
        problems.append(f"VectorChord index usage rate is {index_usage_rate:.3f}, expected 1.000")
    if ratio > spec.policy.maximum_index_table_ratio:
        problems.append(
            f"index/table size ratio {ratio:.3f} exceeds "
            f"{spec.policy.maximum_index_table_ratio:.3f}"
        )
    return BenchmarkReport(
        metadata=metadata,
        samples=tuple(samples),
        average_recall=average_recall,
        minimum_recall=minimum_recall,
        p50_ms=percentile(latencies, 50),
        p95_ms=p95,
        maximum_ms=max(latencies),
        index_usage_rate=index_usage_rate,
        index_table_ratio=ratio,
        problems=tuple(problems),
    )


def run_benchmark(spec: RuntimeSpec, runner: CommandRunner | None = None) -> BenchmarkReport:
    metadata_raw = psql(spec, render_metadata_sql(spec), runner=runner)
    metadata = parse_json_value(metadata_raw, name="metadata")
    if not isinstance(metadata, dict):
        raise BenchmarkError("metadata query did not return an object")
    samples: list[QuerySample] = []
    for query_id in query_ids(spec.policy):
        vector_raw = psql(
            spec,
            f"SELECT embedding::text FROM {spec.policy.qualified_table} "
            f"WHERE document_id = {query_id};",
            runner=runner,
        )
        vector = validate_vector(vector_raw.splitlines()[-1], spec.policy.dimension)
        recall_raw = psql(spec, render_recall_sql(spec, vector), runner=runner, timeout=900)
        try:
            recall = float(recall_raw.splitlines()[-1])
        except (ValueError, IndexError) as exc:
            raise BenchmarkError(f"invalid recall result for query {query_id}") from exc
        if not 0 <= recall <= 1:
            raise BenchmarkError(f"recall for query {query_id} is outside [0, 1]")
        explain_raw = psql(spec, render_explain_sql(spec, vector), runner=runner, timeout=900)
        explain = parse_json_value(explain_raw, name="EXPLAIN")
        plan = PlanMetrics.from_explain(explain, spec.policy.index_name)
        samples.append(QuerySample(query_id, recall, plan))
    return build_report(spec, metadata, samples)


def preflight(spec: RuntimeSpec) -> dict[str, Any]:
    warnings: list[str] = []
    if spec.policy.dataset_rows < 10000:
        warnings.append("small datasets may not demonstrate approximate-index speedups")
    if spec.policy.probes == spec.policy.list_count:
        warnings.append("probing every list prioritizes recall over pruning")
    return {
        "table": spec.policy.qualified_table,
        "dimension": spec.policy.dimension,
        "distance_metric": spec.policy.metric.value,
        "dataset_rows": spec.policy.dataset_rows,
        "lists": spec.policy.list_count,
        "probes": spec.policy.probes,
        "epsilon": spec.policy.epsilon,
        "query_count": spec.policy.query_count,
        "minimum_average_recall": spec.policy.minimum_average_recall,
        "maximum_p95_ms": spec.policy.maximum_p95_ms,
        "operator": getpass.getuser(),
        "warnings": warnings,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Benchmark VectorChord on IvorySQL")
    subparsers = parser.add_subparsers(dest="command", required=True)
    render = subparsers.add_parser("render")
    render.add_argument("--output", type=pathlib.Path, default=pathlib.Path("generated"))
    subparsers.add_parser("preflight")
    subparsers.add_parser("setup")
    subparsers.add_parser("smoke")
    benchmark = subparsers.add_parser("benchmark")
    benchmark.add_argument("--output", type=pathlib.Path)
    audit = subparsers.add_parser("audit")
    audit.add_argument("--output", type=pathlib.Path)
    return parser


def execute(args: argparse.Namespace, spec: RuntimeSpec, runner: CommandRunner | None = None) -> int:
    if args.command == "render":
        result: Any = {"rendered": [str(path) for path in write_sql_files(spec, args.output)]}
    elif args.command == "preflight":
        result = preflight(spec)
    elif args.command == "setup":
        started = time.monotonic()
        output = psql(spec, render_setup_sql(spec), runner=runner, timeout=7200)
        result = {"table": spec.policy.qualified_table, "elapsed_seconds": time.monotonic() - started, "output": output}
    elif args.command == "smoke":
        output = psql(spec, render_smoke_sql(spec), runner=runner, timeout=300)
        result = {"neighbors": output.splitlines()}
    elif args.command in {"benchmark", "audit"}:
        report = run_benchmark(spec, runner)
        result = report.as_dict()
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        if args.command == "audit" and report.problems:
            raise BenchmarkError("; ".join(report.problems))
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
