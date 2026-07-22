from __future__ import annotations

import contextlib
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


MODULE_PATH = pathlib.Path(__file__).parents[1] / "patroni_harness.py"
SPEC = importlib.util.spec_from_file_location("patroni_harness", MODULE_PATH)
assert SPEC and SPEC.loader
harness = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = harness
SPEC.loader.exec_module(harness)


def valid_env(**overrides: str) -> dict[str, str]:
    result = {
        "PATRONI_SCOPE": "ivorysql-ha",
        "PATRONI_NAMESPACE": "/ivorysql/",
        "PATRONI_NODES": "ivory-1,ivory-2,ivory-3",
        "PATRONI_ETCD3_HOSTS": "etcd-a:2379,etcd-b:2379,etcd-c:2379",
        "PATRONI_SUPERUSER": "postgres",
        "PATRONI_SUPERUSER_PASSWORD": "admin-secret",
        "PATRONI_REPLICATION_USER": "replicator",
        "PATRONI_REPLICATION_PASSWORD": "repl-secret",
        "PATRONI_API_USER": "patroni",
        "PATRONI_API_PASSWORD": "api-secret",
        "PATRONI_DATABASE": "postgres",
        "PATRONI_TTL": "30",
        "PATRONI_LOOP_WAIT": "10",
        "PATRONI_RETRY_TIMEOUT": "10",
        "PATRONI_FAILOVER_LAG": "1MiB",
        "PATRONI_MAXIMUM_REPLICATION_LAG": "16MiB",
        "PATRONI_SYNCHRONOUS_MODE": "true",
        "PATRONI_SYNCHRONOUS_NODE_COUNT": "1",
    }
    result.update(overrides)
    return result


def member(
    name: str,
    role: str,
    *,
    state: str = "running",
    lag: int | None = 0,
    timeline: int | None = 5,
) -> dict[str, object]:
    return {
        "name": name,
        "role": role,
        "state": state,
        "host": name,
        "port": 5432,
        "lag": lag,
        "timeline": timeline,
        "api_url": f"http://{name}:8008/patroni",
    }


def healthy_payload() -> dict[str, object]:
    return {
        "scope": "ivorysql-ha",
        "members": [
            member("ivory-1", "leader", lag=None),
            member("ivory-2", "replica", state="streaming", lag=1024),
            member("ivory-3", "replica", state="streaming", lag=2048),
        ],
    }


class ParsingTests(unittest.TestCase):
    def test_parse_int_accepts_boundaries(self) -> None:
        self.assertEqual(harness.parse_int("1", name="port", minimum=1), 1)
        self.assertEqual(harness.parse_int("65535", name="port", maximum=65535), 65535)

    def test_parse_int_rejects_text(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "must be an integer"):
            harness.parse_int("5.5", name="count")

    def test_parse_int_rejects_out_of_range(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "at least 1"):
            harness.parse_int("0", name="count", minimum=1)
        with self.assertRaisesRegex(harness.ConfigurationError, "at most 10"):
            harness.parse_int("11", name="count", maximum=10)

    def test_parse_duration_supports_units(self) -> None:
        self.assertAlmostEqual(harness.parse_duration("500ms", name="timeout"), 0.5)
        self.assertAlmostEqual(harness.parse_duration("2m", name="timeout"), 120.0)
        self.assertAlmostEqual(harness.parse_duration("1.5h", name="timeout"), 5400.0)

    def test_parse_duration_rejects_invalid_values(self) -> None:
        for value in ("", "zero", "-1s", "1d", "0s"):
            with self.subTest(value=value):
                with self.assertRaises(harness.ConfigurationError):
                    harness.parse_duration(value, name="timeout")

    def test_parse_bytes_supports_binary_units(self) -> None:
        self.assertEqual(harness.parse_bytes("512B", name="lag"), 512)
        self.assertEqual(harness.parse_bytes("2KiB", name="lag"), 2048)
        self.assertEqual(harness.parse_bytes("16MiB", name="lag"), 16 * 1024 * 1024)
        self.assertEqual(harness.parse_bytes("1GiB", name="lag"), 1024**3)

    def test_parse_bytes_rejects_ambiguous_decimal_units(self) -> None:
        for value in ("1KB", "3MB", "-1MiB", "one"):
            with self.subTest(value=value):
                with self.assertRaises(harness.ConfigurationError):
                    harness.parse_bytes(value, name="lag")

    def test_parse_bool(self) -> None:
        for value in ("1", "true", "YES", "on"):
            self.assertTrue(harness.parse_bool(value, name="flag"))
        for value in ("0", "false", "NO", "off"):
            self.assertFalse(harness.parse_bool(value, name="flag"))
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_bool("sometimes", name="flag")

    def test_parse_csv_trims_and_deduplicates(self) -> None:
        self.assertEqual(harness.parse_csv("a, b,c", name="nodes"), ("a", "b", "c"))
        with self.assertRaisesRegex(harness.ConfigurationError, "duplicate"):
            harness.parse_csv("a,b,a", name="nodes")
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_csv(" , ", name="nodes")

    def test_validate_name(self) -> None:
        self.assertEqual(harness.validate_name("ivory-1", name="node"), "ivory-1")
        for value in ("Ivory", "1ivory", "ivory_sql", "ivory.sql", "a" * 64):
            with self.subTest(value=value):
                with self.assertRaises(harness.ConfigurationError):
                    harness.validate_name(value, name="node")

    def test_lsn_to_int(self) -> None:
        self.assertIsNone(harness.lsn_to_int(None))
        self.assertEqual(harness.lsn_to_int("0/10"), 16)
        self.assertEqual(harness.lsn_to_int("1/0"), 1 << 32)
        with self.assertRaises(harness.VerificationError):
            harness.lsn_to_int("not-an-lsn")


class ClusterSpecTests(unittest.TestCase):
    def test_builds_three_nodes_from_environment(self) -> None:
        spec = harness.ClusterSpec.from_env(valid_env())
        self.assertEqual(spec.scope, "ivorysql-ha")
        self.assertEqual([node.name for node in spec.nodes], ["ivory-1", "ivory-2", "ivory-3"])
        self.assertEqual(spec.etcd_hosts, ("etcd-a:2379", "etcd-b:2379", "etcd-c:2379"))
        self.assertTrue(spec.synchronous_mode)
        self.assertEqual(spec.maximum_replication_lag, 16 * 1024 * 1024)

    def test_supports_per_node_host_override(self) -> None:
        spec = harness.ClusterSpec.from_env(valid_env(PATRONI_HOST_2="10.0.0.22"))
        self.assertEqual(spec.nodes[1].host, "10.0.0.22")

    def test_requires_three_members(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "at least three"):
            harness.ClusterSpec.from_env(valid_env(PATRONI_NODES="ivory-1,ivory-2"))

    def test_rejects_unsafe_patroni_timing(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "safety rule"):
            harness.ClusterSpec.from_env(
                valid_env(PATRONI_TTL="20", PATRONI_LOOP_WAIT="10", PATRONI_RETRY_TIMEOUT="10")
            )

    def test_rejects_too_many_synchronous_nodes(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "smaller than node count"):
            harness.ClusterSpec.from_env(valid_env(PATRONI_SYNCHRONOUS_NODE_COUNT="3"))

    def test_rejects_short_secrets(self) -> None:
        for variable in (
            "PATRONI_SUPERUSER_PASSWORD",
            "PATRONI_REPLICATION_PASSWORD",
            "PATRONI_API_PASSWORD",
        ):
            with self.subTest(variable=variable):
                with self.assertRaisesRegex(harness.ConfigurationError, variable):
                    harness.ClusterSpec.from_env(valid_env(**{variable: "short"}))

    def test_namespace_must_be_absolute(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "begin and end"):
            harness.ClusterSpec.from_env(valid_env(PATRONI_NAMESPACE="ivorysql"))

    def test_node_lookup(self) -> None:
        spec = harness.ClusterSpec.from_env(valid_env())
        self.assertEqual(spec.node("ivory-2").host, "ivory-2")
        with self.assertRaisesRegex(harness.ConfigurationError, "unknown member"):
            spec.node("missing")


class RenderingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.ClusterSpec.from_env(valid_env())

    def test_render_contains_required_ivorysql_and_patroni_settings(self) -> None:
        text = harness.render_patroni_config(self.spec, self.spec.nodes[0])
        self.assertIn('scope: "ivorysql-ha"', text)
        self.assertIn('name: "ivory-1"', text)
        self.assertIn("etcd3:", text)
        self.assertIn("dbmode: oracle", text)
        self.assertIn('hosts: "etcd-a:2379,etcd-b:2379,etcd-c:2379"', text)
        self.assertIn("use_pg_rewind: true", text)
        self.assertIn("data-checksums", text)
        self.assertNotIn("ivorysql.compatible_mode: oracle", text)
        self.assertIn("password_encryption: scram-sha-256", text)

    def test_render_quotes_secrets(self) -> None:
        spec = harness.ClusterSpec.from_env(
            valid_env(PATRONI_SUPERUSER_PASSWORD='value: with "quotes"')
        )
        text = harness.render_patroni_config(spec, spec.nodes[0])
        self.assertIn('password: "value: with \\"quotes\\""', text)

    def test_render_all_writes_configs_and_non_secret_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = harness.render_all(self.spec, pathlib.Path(directory))
            self.assertEqual(len(paths), 4)
            for name in ("ivory-1.yml", "ivory-2.yml", "ivory-3.yml", "cluster.json"):
                self.assertTrue((pathlib.Path(directory) / name).is_file())
            manifest = json.loads((pathlib.Path(directory) / "cluster.json").read_text())
            self.assertEqual(manifest["scope"], "ivorysql-ha")
            self.assertNotIn("password", json.dumps(manifest).lower())

    def test_node_ports_are_rendered(self) -> None:
        node = harness.NodeSpec("ivory-4", "db.internal", rest_port=18008, sql_port=15432)
        spec = harness.ClusterSpec(
            scope=self.spec.scope,
            namespace=self.spec.namespace,
            nodes=self.spec.nodes + (node,),
            etcd_hosts=self.spec.etcd_hosts,
            superuser=self.spec.superuser,
            superuser_password=self.spec.superuser_password,
            replication_user=self.spec.replication_user,
            replication_password=self.spec.replication_password,
            api_user=self.spec.api_user,
            api_password=self.spec.api_password,
            database=self.spec.database,
        )
        text = harness.render_patroni_config(spec, node)
        self.assertIn("listen: 0.0.0.0:18008", text)
        self.assertIn("connect_address: db.internal:15432", text)


class FakeTransport:
    def __init__(self, responses: list[tuple[int, bytes]]) -> None:
        self.responses = responses
        self.calls: list[dict[str, object]] = []

    def request(self, url: str, **kwargs: object) -> tuple[int, bytes]:
        self.calls.append({"url": url, **kwargs})
        return self.responses.pop(0)


class PatroniClientTests(unittest.TestCase):
    def setUp(self) -> None:
        self.node = harness.NodeSpec("ivory-1", "ivory-1")

    def test_get_cluster_decodes_json_and_authenticates(self) -> None:
        transport = FakeTransport([(200, json.dumps(healthy_payload()).encode())])
        client = harness.PatroniClient(self.node, "patroni", "secret", transport=transport)
        self.assertEqual(client.cluster()["scope"], "ivorysql-ha")
        call = transport.calls[0]
        self.assertEqual(call["url"], "http://ivory-1:8008/cluster")
        self.assertEqual(call["method"], "GET")
        self.assertTrue(str(call["headers"]["Authorization"]).startswith("Basic "))

    def test_switchover_sends_leader_and_candidate(self) -> None:
        transport = FakeTransport([(202, b'{"message":"scheduled"}')])
        client = harness.PatroniClient(self.node, "patroni", "secret", transport=transport)
        client.switchover("ivory-1", "ivory-2")
        call = transport.calls[0]
        self.assertEqual(call["url"], "http://ivory-1:8008/switchover")
        self.assertEqual(call["method"], "POST")
        self.assertEqual(json.loads(call["body"]), {"leader": "ivory-1", "candidate": "ivory-2"})

    def test_failover_can_omit_candidate(self) -> None:
        transport = FakeTransport([(200, b"{}")])
        client = harness.PatroniClient(self.node, "patroni", "secret", transport=transport)
        client.failover()
        self.assertEqual(json.loads(transport.calls[0]["body"]), {})

    def test_http_error_includes_response_detail(self) -> None:
        transport = FakeTransport([(503, b"no eligible candidates")])
        client = harness.PatroniClient(self.node, "patroni", "secret", transport=transport)
        with self.assertRaisesRegex(harness.PatroniAPIError, "no eligible candidates"):
            client.failover()

    def test_invalid_json_is_reported(self) -> None:
        transport = FakeTransport([(200, b"not json")])
        client = harness.PatroniClient(self.node, "patroni", "secret", transport=transport)
        with self.assertRaisesRegex(harness.PatroniAPIError, "invalid JSON"):
            client.cluster()

    def test_path_must_be_absolute(self) -> None:
        client = harness.PatroniClient(
            self.node,
            "patroni",
            "secret",
            transport=FakeTransport([]),
        )
        with self.assertRaises(ValueError):
            client.request("GET", "cluster")


class SnapshotTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.ClusterSpec.from_env(valid_env())

    def test_healthy_snapshot_has_one_leader_and_two_replicas(self) -> None:
        snapshot = harness.ClusterSnapshot.from_payload(healthy_payload())
        self.assertEqual(snapshot.leaders[0].name, "ivory-1")
        self.assertEqual(len(snapshot.replicas), 2)
        self.assertEqual(harness.validate_snapshot(self.spec, snapshot), [])

    def test_synchronous_and_asynchronous_standbys_are_replicas(self) -> None:
        payload = healthy_payload()
        payload["members"][1]["role"] = "sync_standby"
        payload["members"][2]["role"] = "async_standby"
        snapshot = harness.ClusterSnapshot.from_payload(payload)
        self.assertEqual([member.name for member in snapshot.replicas], ["ivory-2", "ivory-3"])
        self.assertEqual(harness.validate_snapshot(self.spec, snapshot), [])

    def test_missing_member_is_reported(self) -> None:
        payload = healthy_payload()
        payload["members"] = payload["members"][:2]
        problems = harness.validate_snapshot(
            self.spec, harness.ClusterSnapshot.from_payload(payload)
        )
        self.assertTrue(any("missing members: ivory-3" in problem for problem in problems))
        self.assertTrue(any("expected at least 2 replicas" in problem for problem in problems))

    def test_multiple_leaders_are_reported(self) -> None:
        payload = healthy_payload()
        payload["members"][1]["role"] = "leader"
        problems = harness.validate_snapshot(
            self.spec, harness.ClusterSnapshot.from_payload(payload)
        )
        self.assertIn("expected exactly one leader, found 2", problems)

    def test_stopped_member_is_reported(self) -> None:
        payload = healthy_payload()
        payload["members"][2]["state"] = "stopped"
        problems = harness.validate_snapshot(
            self.spec, harness.ClusterSnapshot.from_payload(payload)
        )
        self.assertIn("ivory-3 is in state 'stopped'", problems)

    def test_excessive_lag_is_reported(self) -> None:
        payload = healthy_payload()
        payload["members"][1]["lag"] = 17 * 1024 * 1024
        problems = harness.validate_snapshot(
            self.spec, harness.ClusterSnapshot.from_payload(payload)
        )
        self.assertTrue(any("exceeds" in problem for problem in problems))

    def test_different_timelines_are_reported(self) -> None:
        payload = healthy_payload()
        payload["members"][2]["timeline"] = 4
        problems = harness.validate_snapshot(
            self.spec, harness.ClusterSnapshot.from_payload(payload)
        )
        self.assertTrue(any("different timelines" in problem for problem in problems))

    def test_missing_required_member_field_is_rejected(self) -> None:
        broken = member("ivory-1", "leader")
        del broken["state"]
        with self.assertRaisesRegex(harness.VerificationError, "missing fields"):
            harness.MemberStatus.from_payload(broken)

    def test_invalid_member_lag_is_rejected(self) -> None:
        broken = member("ivory-1", "replica")
        broken["lag"] = "far"
        with self.assertRaisesRegex(harness.VerificationError, "invalid lag"):
            harness.MemberStatus.from_payload(broken)

    def test_snapshot_requires_member_list(self) -> None:
        with self.assertRaisesRegex(harness.VerificationError, "member list"):
            harness.ClusterSnapshot.from_payload({"members": {}})


class FakeRunner:
    def __init__(self, outputs: list[str] | None = None) -> None:
        self.outputs = outputs or []
        self.calls: list[tuple[list[str], dict[str, object]]] = []

    def run(self, command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        self.calls.append((command, kwargs))
        output = self.outputs.pop(0) if self.outputs else ""
        return subprocess.CompletedProcess(command, 0, output, "")


class SQLVerificationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.ClusterSpec.from_env(valid_env())
        self.snapshot = harness.ClusterSnapshot.from_payload(healthy_payload())

    def test_run_sql_uses_pgpassword_environment(self) -> None:
        runner = FakeRunner(["f\n"])
        value = harness.run_sql(
            self.spec,
            self.spec.nodes[0],
            "SELECT pg_is_in_recovery();",
            runner=runner,
        )
        self.assertEqual(value, "f")
        command, kwargs = runner.calls[0]
        self.assertIn("--no-psqlrc", command)
        self.assertIn("ON_ERROR_STOP=1", command)
        self.assertNotIn(self.spec.superuser_password, command)
        self.assertEqual(kwargs["env"]["PGPASSWORD"], self.spec.superuser_password)

    def test_verify_sql_semantics_accepts_matching_roles(self) -> None:
        runner = FakeRunner(
            [
                "f\n", "IvorySQL 4.6\n", "oracle\n",
                "t\n", "IvorySQL 4.6\n", "oracle\n",
                "t\n", "IvorySQL 4.6\n", "oracle\n",
            ]
        )
        self.assertEqual(
            harness.verify_sql_semantics(self.spec, self.snapshot, runner=runner),
            [],
        )
        mode_query = runner.calls[2][0][-1]
        self.assertEqual(
            mode_query,
            "SELECT current_setting('ivorysql.compatible_mode');",
        )

    def test_verify_sql_semantics_reports_role_mismatch(self) -> None:
        runner = FakeRunner(
            [
                "t\n", "IvorySQL 4.6\n", "oracle\n",
                "t\n", "IvorySQL 4.6\n", "oracle\n",
                "t\n", "IvorySQL 4.6\n", "oracle\n",
            ]
        )
        problems = harness.verify_sql_semantics(self.spec, self.snapshot, runner=runner)
        self.assertTrue(any("ivory-1 SQL recovery role" in problem for problem in problems))

    def test_verify_sql_semantics_reports_non_ivory_server(self) -> None:
        runner = FakeRunner(
            [
                "f\n", "PostgreSQL 17\n", "oracle\n",
                "t\n", "IvorySQL 4.6\n", "oracle\n",
                "t\n", "IvorySQL 4.6\n", "oracle\n",
            ]
        )
        problems = harness.verify_sql_semantics(self.spec, self.snapshot, runner=runner)
        self.assertTrue(any("does not report an IvorySQL" in problem for problem in problems))

    def test_verify_sql_semantics_reports_disabled_oracle_mode(self) -> None:
        runner = FakeRunner(
            [
                "f\n", "IvorySQL 4.6\n", "pg\n",
                "t\n", "IvorySQL 4.6\n", "oracle\n",
                "t\n", "IvorySQL 4.6\n", "oracle\n",
            ]
        )
        problems = harness.verify_sql_semantics(self.spec, self.snapshot, runner=runner)
        self.assertTrue(any("Oracle compatibility" in problem for problem in problems))


class CommandLineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.ClusterSpec.from_env(valid_env())

    def test_preflight_warns_for_default_secrets(self) -> None:
        spec = harness.ClusterSpec.from_env({})
        result = harness.perform_preflight(spec)
        self.assertEqual(len(result["warnings"]), 3)
        self.assertEqual(result["node_count"], 3)

    def test_preflight_json_output(self) -> None:
        parser = harness.build_parser()
        args = parser.parse_args(["--json", "preflight"])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(harness.execute(args, self.spec), 0)
        result = json.loads(output.getvalue())
        self.assertEqual(result["scope"], "ivorysql-ha")

    def test_render_command_writes_requested_directory(self) -> None:
        parser = harness.build_parser()
        with tempfile.TemporaryDirectory() as directory:
            args = parser.parse_args(["--json", "render", "--output", directory])
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                harness.execute(args, self.spec)
            result = json.loads(output.getvalue())
            self.assertEqual(len(result["rendered"]), 4)

    def test_print_snapshot_table(self) -> None:
        snapshot = harness.ClusterSnapshot.from_payload(healthy_payload())
        output = io.StringIO()
        harness.print_snapshot(snapshot, output)
        text = output.getvalue()
        self.assertIn("NAME", text)
        self.assertIn("ivory-1", text)
        self.assertIn("replica", text)

    def test_confirmation_requires_yes_without_tty(self) -> None:
        with mock.patch.object(harness.sys.stdin, "isatty", return_value=False):
            with self.assertRaisesRegex(harness.ConfigurationError, "requires --yes"):
                harness.require_confirmation("Failover", assume_yes=False)

    def test_confirmation_can_be_bypassed(self) -> None:
        harness.require_confirmation("Failover", assume_yes=True)

    def test_main_reports_configuration_errors(self) -> None:
        stderr = io.StringIO()
        with mock.patch.dict(os.environ, valid_env(PATRONI_TTL="bad"), clear=True):
            with contextlib.redirect_stderr(stderr):
                result = harness.main(["preflight"])
        self.assertEqual(result, 2)
        self.assertIn("PATRONI_TTL must be an integer", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
