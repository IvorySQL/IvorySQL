from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import math
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "vector_harness.py"
SPEC = importlib.util.spec_from_file_location("vector_harness", MODULE_PATH)
assert SPEC and SPEC.loader
harness = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = harness
SPEC.loader.exec_module(harness)


def valid_env(**overrides: str) -> dict[str, str]:
    result = {
        "IVORYSQL_HOST": "database",
        "IVORYSQL_PORT": "5333",
        "IVORYSQL_DATABASE": "vectordb",
        "IVORYSQL_USER": "ivorysql",
        "IVORYSQL_PASSWORD": "ivorysql-vector-password",
        "VECTOR_SCHEMA": "ai",
        "VECTOR_TABLE": "documents",
        "VECTOR_INDEX_NAME": "documents_embedding_vchordrq",
        "VECTOR_DIMENSION": "4",
        "VECTOR_DISTANCE_METRIC": "cosine",
        "VECTOR_DATASET_ROWS": "10000",
        "VECTOR_LIST_COUNT": "64",
        "VECTOR_PROBES": "8",
        "VECTOR_EPSILON": "1.9",
        "VECTOR_BUILD_THREADS": "4",
        "VECTOR_SAMPLING_FACTOR": "64",
        "VECTOR_RESIDUAL_QUANTIZATION": "true",
        "VECTOR_SPHERICAL_CENTROIDS": "true",
        "VECTOR_QUERY_COUNT": "5",
        "VECTOR_NEIGHBORS": "10",
        "VECTOR_MIN_AVERAGE_RECALL": "0.90",
        "VECTOR_MIN_QUERY_RECALL": "0.70",
        "VECTOR_MAXIMUM_P95_MS": "500",
        "VECTOR_MAX_INDEX_TABLE_RATIO": "1.50",
    }
    result.update(overrides)
    return result


def metadata(**overrides: object) -> dict[str, object]:
    result: dict[str, object] = {
        "ivorysql_version": "IvorySQL 5.4",
        "server_version": "18.4",
        "vector_version": "0.8.5",
        "vchord_version": "1.1.1",
        "row_count": 10000,
        "table_bytes": 10_000_000,
        "index_bytes": 5_000_000,
        "index_valid": True,
    }
    result.update(overrides)
    return result


def explain_payload(
    *,
    execution_ms: float = 12.5,
    planning_ms: float = 0.4,
    index_name: str = "documents_embedding_vchordrq",
    use_index: bool = True,
) -> list[dict[str, object]]:
    if use_index:
        child: dict[str, object] = {
            "Node Type": "Index Scan",
            "Index Name": index_name,
            "Actual Rows": 10,
            "Shared Hit Blocks": 20,
            "Shared Read Blocks": 2,
        }
    else:
        child = {
            "Node Type": "Seq Scan",
            "Actual Rows": 10000,
            "Shared Hit Blocks": 100,
            "Shared Read Blocks": 10,
        }
    return [
        {
            "Plan": {
                "Node Type": "Limit",
                "Actual Rows": 10,
                "Shared Hit Blocks": 1,
                "Shared Read Blocks": 0,
                "Plans": [child],
            },
            "Planning Time": planning_ms,
            "Execution Time": execution_ms,
        }
    ]


def sample(
    query_id: int,
    recall: float = 0.95,
    execution_ms: float = 10.0,
    *,
    use_index: bool = True,
) -> harness.QuerySample:
    plan = harness.PlanMetrics.from_explain(
        explain_payload(execution_ms=execution_ms, use_index=use_index),
        "documents_embedding_vchordrq",
    )
    return harness.QuerySample(query_id, recall, plan)


class ParsingTests(unittest.TestCase):
    def test_parse_int_and_bounds(self) -> None:
        self.assertEqual(harness.parse_int("10", name="count", minimum=1), 10)
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_int("many", name="count")
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_int("0", name="count", minimum=1)
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_int("11", name="count", maximum=10)

    def test_parse_float_and_finite_check(self) -> None:
        self.assertEqual(harness.parse_float("1.9", name="epsilon"), 1.9)
        for raw in ("bad", "nan", "inf", "-inf"):
            with self.subTest(raw=raw):
                with self.assertRaises(harness.ConfigurationError):
                    harness.parse_float(raw, name="epsilon")
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_float("-1", name="epsilon", minimum=0)

    def test_parse_bool(self) -> None:
        for raw in ("true", "yes", "1", "on"):
            self.assertTrue(harness.parse_bool(raw, name="flag"))
        for raw in ("false", "no", "0", "off"):
            self.assertFalse(harness.parse_bool(raw, name="flag"))
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_bool("maybe", name="flag")

    def test_identifier(self) -> None:
        self.assertEqual(harness.identifier("embedding_idx", name="index"), "embedding_idx")
        for raw in ("9index", "bad-index", "idx;drop", "a" * 64):
            with self.subTest(raw=raw):
                with self.assertRaises(harness.ConfigurationError):
                    harness.identifier(raw, name="index")

    def test_quote_literal(self) -> None:
        self.assertEqual(harness.quote_literal("owner's"), "'owner''s'")
        with self.assertRaises(harness.ConfigurationError):
            harness.quote_literal("bad\x00value")

    def test_percentile(self) -> None:
        values = [1.0, 2.0, 3.0, 4.0]
        self.assertEqual(harness.percentile(values, 0), 1.0)
        self.assertEqual(harness.percentile(values, 50), 2.5)
        self.assertEqual(harness.percentile(values, 100), 4.0)
        self.assertEqual(harness.percentile([5.0], 95), 5.0)
        with self.assertRaises(ValueError):
            harness.percentile([], 50)


class MetricTests(unittest.TestCase):
    def test_l2_mapping(self) -> None:
        self.assertEqual(harness.DistanceMetric.L2.operator, "<->")
        self.assertEqual(harness.DistanceMetric.L2.operator_class, "vector_l2_ops")

    def test_cosine_mapping(self) -> None:
        self.assertEqual(harness.DistanceMetric.COSINE.operator, "<=>")
        self.assertEqual(
            harness.DistanceMetric.COSINE.operator_class,
            "vector_cosine_ops",
        )

    def test_inner_product_mapping(self) -> None:
        self.assertEqual(harness.DistanceMetric.INNER_PRODUCT.operator, "<#>")
        self.assertEqual(
            harness.DistanceMetric.INNER_PRODUCT.operator_class,
            "vector_ip_ops",
        )


class RuntimeSpecTests(unittest.TestCase):
    def test_default_policy(self) -> None:
        spec = harness.RuntimeSpec.from_env(valid_env())
        self.assertEqual(spec.policy.qualified_table, "ai.documents")
        self.assertEqual(
            spec.policy.qualified_index,
            "ai.documents_embedding_vchordrq",
        )
        self.assertEqual(spec.policy.metric, harness.DistanceMetric.COSINE)
        self.assertEqual(spec.policy.dimension, 4)
        self.assertEqual(spec.policy.dataset_rows, 10000)

    def test_password_length(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "at least 12"):
            harness.RuntimeSpec.from_env(valid_env(IVORYSQL_PASSWORD="short"))

    def test_dimension_range(self) -> None:
        for raw in ("0", "16001"):
            with self.subTest(raw=raw):
                with self.assertRaises(harness.ConfigurationError):
                    harness.RuntimeSpec.from_env(valid_env(VECTOR_DIMENSION=raw))

    def test_dataset_minimum(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "at least 1000"):
            harness.RuntimeSpec.from_env(valid_env(VECTOR_DATASET_ROWS="999"))

    def test_lists_must_be_smaller_than_dataset(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "smaller than dataset"):
            harness.RuntimeSpec.from_env(
                valid_env(VECTOR_DATASET_ROWS="1000", VECTOR_LIST_COUNT="1000")
            )

    def test_probes_range(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "between 1 and list"):
            harness.RuntimeSpec.from_env(
                valid_env(VECTOR_LIST_COUNT="64", VECTOR_PROBES="65")
            )

    def test_epsilon_range(self) -> None:
        with self.assertRaises(harness.ConfigurationError):
            harness.RuntimeSpec.from_env(valid_env(VECTOR_EPSILON="4.1"))

    def test_build_thread_range(self) -> None:
        with self.assertRaises(harness.ConfigurationError):
            harness.RuntimeSpec.from_env(valid_env(VECTOR_BUILD_THREADS="256"))

    def test_sampling_factor_range(self) -> None:
        with self.assertRaises(harness.ConfigurationError):
            harness.RuntimeSpec.from_env(valid_env(VECTOR_SAMPLING_FACTOR="1025"))

    def test_query_count_range(self) -> None:
        with self.assertRaises(harness.ConfigurationError):
            harness.RuntimeSpec.from_env(valid_env(VECTOR_QUERY_COUNT="0"))

    def test_recall_threshold_invariant(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "minimum query"):
            harness.RuntimeSpec.from_env(
                valid_env(
                    VECTOR_MIN_QUERY_RECALL="0.95",
                    VECTOR_MIN_AVERAGE_RECALL="0.90",
                )
            )

    def test_spherical_centroids_require_cosine(self) -> None:
        for metric in ("l2", "inner_product"):
            with self.subTest(metric=metric):
                with self.assertRaisesRegex(harness.ConfigurationError, "only valid for cosine"):
                    harness.RuntimeSpec.from_env(
                        valid_env(VECTOR_DISTANCE_METRIC=metric)
                    )
        spec = harness.RuntimeSpec.from_env(
            valid_env(
                VECTOR_DISTANCE_METRIC="l2",
                VECTOR_SPHERICAL_CENTROIDS="false",
            )
        )
        self.assertEqual(spec.policy.metric, harness.DistanceMetric.L2)

    def test_unknown_metric(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "must be l2"):
            harness.RuntimeSpec.from_env(valid_env(VECTOR_DISTANCE_METRIC="hamming"))

    def test_invalid_identifier(self) -> None:
        with self.assertRaises(harness.ConfigurationError):
            harness.RuntimeSpec.from_env(valid_env(VECTOR_TABLE="documents;drop"))


class RenderingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.RuntimeSpec.from_env(valid_env())

    def test_index_options(self) -> None:
        text = harness.index_options(self.spec.policy)
        self.assertIn("residual_quantization = true", text)
        self.assertIn("[build.internal]", text)
        self.assertIn("lists = [64]", text)
        self.assertIn("spherical_centroids = true", text)
        self.assertIn("build_threads = 4", text)
        self.assertIn("sampling_factor = 64", text)

    def test_setup_sql_creates_extensions_and_dataset(self) -> None:
        text = harness.render_setup_sql(self.spec)
        self.assertIn("CREATE EXTENSION IF NOT EXISTS vector", text)
        self.assertIn("CREATE EXTENSION IF NOT EXISTS vchord CASCADE", text)
        self.assertIn("embedding vector(4)", text)
        self.assertIn("generate_series(1, 10000)", text)
        self.assertIn("hashtextextended", text)
        self.assertIn("USING vchordrq", text)
        self.assertIn("vector_cosine_ops", text)

    def test_smoke_sql_uses_policy(self) -> None:
        text = harness.render_smoke_sql(self.spec)
        self.assertIn("SET vchordrq.probes = '8'", text)
        self.assertIn("SET vchordrq.epsilon = 1.9", text)
        self.assertIn("embedding <=>", text)
        self.assertIn("LIMIT 10", text)

    def test_metadata_sql(self) -> None:
        text = harness.render_metadata_sql(self.spec)
        self.assertIn("'ivorysql_version', version()", text)
        self.assertIn("extname = 'vector'", text)
        self.assertIn("extname = 'vchord'", text)
        self.assertIn("pg_table_size", text)
        self.assertIn("indisvalid AND indisready", text)

    def test_query_ids_cover_dataset(self) -> None:
        self.assertEqual(harness.query_ids(self.spec.policy), (1, 2501, 5001, 7500, 10000))
        one = harness.RuntimeSpec.from_env(valid_env(VECTOR_QUERY_COUNT="1"))
        self.assertEqual(harness.query_ids(one.policy), (5000,))

    def test_vector_validation(self) -> None:
        self.assertEqual(harness.validate_vector("[1, 2, -3.5, 4e-2]", 4), "[1,2,-3.5,4e-2]")
        with self.assertRaisesRegex(harness.BenchmarkError, "wrong dimension"):
            harness.validate_vector("[1,2,3]", 4)
        with self.assertRaisesRegex(harness.BenchmarkError, "invalid vector"):
            harness.validate_vector("[1,drop table,3,4]", 4)

    def test_recall_sql_uses_exact_ground_truth(self) -> None:
        text = harness.render_recall_sql(self.spec, "[1,2,3,4]")
        self.assertIn("vchordrq_evaluate_query_recall", text)
        self.assertIn("SELECT ctid", text)
        self.assertIn("exact_search => true", text)
        self.assertIn("ORDER BY embedding <=>", text)

    def test_explain_sql_is_analyzed(self) -> None:
        text = harness.render_explain_sql(self.spec, "[1,2,3,4]")
        self.assertIn("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)", text)
        self.assertIn("documents", text)

    def test_write_sql_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = harness.write_sql_files(self.spec, pathlib.Path(directory))
            self.assertEqual(len(paths), 3)
            self.assertEqual(
                {path.name for path in paths},
                {"setup.sql", "smoke.sql", "metadata.sql"},
            )


class PlanTests(unittest.TestCase):
    def test_walk_plan(self) -> None:
        root = explain_payload()[0]["Plan"]
        nodes = harness.walk_plan(root)
        self.assertEqual(len(nodes), 2)
        self.assertEqual(nodes[1]["Node Type"], "Index Scan")

    def test_parse_index_plan(self) -> None:
        metrics = harness.PlanMetrics.from_explain(
            explain_payload(),
            "documents_embedding_vchordrq",
        )
        self.assertEqual(metrics.execution_ms, 12.5)
        self.assertEqual(metrics.planning_ms, 0.4)
        self.assertTrue(metrics.index_used)
        self.assertEqual(metrics.index_name, "documents_embedding_vchordrq")
        self.assertEqual(metrics.shared_hit_blocks, 21)
        self.assertEqual(metrics.shared_read_blocks, 2)
        self.assertEqual(metrics.rows_returned, 10)

    def test_seq_scan_is_not_index_usage(self) -> None:
        metrics = harness.PlanMetrics.from_explain(
            explain_payload(use_index=False),
            "documents_embedding_vchordrq",
        )
        self.assertFalse(metrics.index_used)
        self.assertIsNone(metrics.index_name)

    def test_wrong_index_is_not_accepted(self) -> None:
        metrics = harness.PlanMetrics.from_explain(
            explain_payload(index_name="other_index"),
            "documents_embedding_vchordrq",
        )
        self.assertFalse(metrics.index_used)

    def test_malformed_explain_fails(self) -> None:
        for payload in (None, [], {}, [{}], [{"Plan": {}}]):
            with self.subTest(payload=payload):
                with self.assertRaises(harness.BenchmarkError):
                    harness.PlanMetrics.from_explain(
                        payload,
                        "documents_embedding_vchordrq",
                    )

    def test_parse_json_value(self) -> None:
        self.assertEqual(harness.parse_json_value('\n{"a": 1}\n', name="test"), {"a": 1})
        with self.assertRaises(harness.BenchmarkError):
            harness.parse_json_value("", name="test")
        with self.assertRaises(harness.BenchmarkError):
            harness.parse_json_value("not-json", name="test")


class ReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.RuntimeSpec.from_env(valid_env())

    def test_healthy_report(self) -> None:
        samples = [
            sample(1, 0.9, 8),
            sample(2501, 1.0, 10),
            sample(5001, 0.9, 12),
            sample(7500, 1.0, 14),
            sample(10000, 0.9, 16),
        ]
        report = harness.build_report(self.spec, metadata(), samples)
        self.assertAlmostEqual(report.average_recall, 0.94)
        self.assertEqual(report.minimum_recall, 0.9)
        self.assertEqual(report.p50_ms, 12)
        self.assertEqual(report.p95_ms, 15.6)
        self.assertEqual(report.maximum_ms, 16)
        self.assertEqual(report.index_usage_rate, 1)
        self.assertEqual(report.index_table_ratio, 0.5)
        self.assertEqual(report.problems, ())

    def test_average_recall_failure(self) -> None:
        report = harness.build_report(
            self.spec,
            metadata(),
            [sample(1, 0.8), sample(2, 0.9)],
        )
        self.assertTrue(any("average recall" in problem for problem in report.problems))

    def test_minimum_recall_failure(self) -> None:
        report = harness.build_report(
            self.spec,
            metadata(),
            [sample(1, 0.6), sample(2, 1.0), sample(3, 1.0), sample(4, 1.0)],
        )
        self.assertTrue(any("minimum recall" in problem for problem in report.problems))

    def test_latency_failure(self) -> None:
        report = harness.build_report(
            self.spec,
            metadata(),
            [sample(1, 1.0, 600), sample(2, 1.0, 700)],
        )
        self.assertTrue(any("p95 execution time" in problem for problem in report.problems))

    def test_index_usage_failure(self) -> None:
        report = harness.build_report(
            self.spec,
            metadata(),
            [sample(1, use_index=False), sample(2)],
        )
        self.assertTrue(any("index usage rate" in problem for problem in report.problems))

    def test_size_ratio_failure(self) -> None:
        report = harness.build_report(
            self.spec,
            metadata(index_bytes=16_000_000),
            [sample(1)],
        )
        self.assertTrue(any("size ratio" in problem for problem in report.problems))

    def test_zero_table_size_is_infinite_ratio(self) -> None:
        report = harness.build_report(
            self.spec,
            metadata(table_bytes=0),
            [sample(1)],
        )
        self.assertTrue(math.isinf(report.index_table_ratio))
        self.assertTrue(any("size ratio" in problem for problem in report.problems))

    def test_metadata_validation(self) -> None:
        self.assertEqual(harness.validate_metadata(self.spec, metadata()), [])
        problems = harness.validate_metadata(
            self.spec,
            metadata(
                ivorysql_version="PostgreSQL 18.4",
                row_count=9999,
                vector_version=None,
                vchord_version=None,
                index_valid=False,
            ),
        )
        self.assertEqual(len(problems), 5)

    def test_missing_metadata_fields(self) -> None:
        problems = harness.validate_metadata(self.spec, {"row_count": 10000})
        self.assertEqual(len(problems), 1)
        self.assertIn("metadata is missing", problems[0])

    def test_report_requires_samples(self) -> None:
        with self.assertRaisesRegex(harness.BenchmarkError, "no query samples"):
            harness.build_report(self.spec, metadata(), [])

    def test_report_serialization(self) -> None:
        report = harness.build_report(self.spec, metadata(), [sample(1)])
        payload = report.as_dict()
        self.assertEqual(payload["summary"]["query_count"], 1)
        self.assertEqual(payload["samples"][0]["query_id"], 1)
        self.assertEqual(payload["problems"], [])


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
        runner = FakeRunner(["1\n"])
        self.assertEqual(harness.psql(self.spec, "SELECT 1", runner=runner), "1")
        command, kwargs = runner.calls[0]
        self.assertIn("--no-psqlrc", command)
        self.assertIn("ON_ERROR_STOP=1", command)
        self.assertNotIn(self.spec.connection.password, command)
        self.assertEqual(kwargs["env"]["PGPASSWORD"], self.spec.connection.password)

    def test_preflight(self) -> None:
        result = harness.preflight(self.spec)
        self.assertEqual(result["table"], "ai.documents")
        self.assertEqual(result["distance_metric"], "cosine")
        self.assertEqual(result["lists"], 64)
        self.assertEqual(result["warnings"], [])

    def test_preflight_warns_for_small_dataset_and_all_probes(self) -> None:
        spec = harness.RuntimeSpec.from_env(
            valid_env(
                VECTOR_DATASET_ROWS="1000",
                VECTOR_LIST_COUNT="8",
                VECTOR_PROBES="8",
            )
        )
        self.assertEqual(len(harness.preflight(spec)["warnings"]), 2)

    def test_render_cli(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = harness.build_parser().parse_args(["render", "--output", directory])
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                harness.execute(args, self.spec)
            self.assertEqual(len(json.loads(output.getvalue())["rendered"]), 3)

    def test_setup_cli(self) -> None:
        runner = FakeRunner(["CREATE INDEX\n"])
        args = harness.build_parser().parse_args(["setup"])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            harness.execute(args, self.spec, runner)
        payload = json.loads(output.getvalue())
        self.assertEqual(payload["table"], "ai.documents")
        self.assertIn("elapsed_seconds", payload)

    def test_main_returns_two_for_invalid_policy(self) -> None:
        stderr = io.StringIO()
        with mock.patch.dict(os.environ, valid_env(VECTOR_EPSILON="bad"), clear=True):
            with contextlib.redirect_stderr(stderr):
                result = harness.main(["preflight"])
        self.assertEqual(result, 2)
        self.assertIn("must be a number", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
