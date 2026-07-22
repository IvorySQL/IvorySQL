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
import threading
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "pool_harness.py"
SPEC = importlib.util.spec_from_file_location("pool_harness", MODULE_PATH)
assert SPEC and SPEC.loader
harness = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = harness
SPEC.loader.exec_module(harness)


def valid_env(**overrides: str) -> dict[str, str]:
    result = {
        "IVORYSQL_HOST": "database",
        "IVORYSQL_PORT": "5333",
        "IVORYSQL_DATABASE": "appdb",
        "PGBOUNCER_APPLICATION_USER": "app_user",
        "PGBOUNCER_APPLICATION_PASSWORD": "application-password",
        "PGBOUNCER_AUTH_USER": "pool_auth",
        "PGBOUNCER_AUTH_PASSWORD": "authentication-password",
        "PGBOUNCER_ADMIN_USER": "pool_admin",
        "PGBOUNCER_ADMIN_PASSWORD": "administration-password",
        "PGBOUNCER_POOL_MODE": "transaction",
        "PGBOUNCER_PORT": "6432",
        "PGBOUNCER_MAX_CLIENT_CONN": "500",
        "PGBOUNCER_DEFAULT_POOL_SIZE": "40",
        "PGBOUNCER_MIN_POOL_SIZE": "5",
        "PGBOUNCER_RESERVE_POOL_SIZE": "10",
        "PGBOUNCER_RESERVE_POOL_TIMEOUT": "3",
        "PGBOUNCER_MAX_DB_CONNECTIONS": "50",
        "PGBOUNCER_MAX_USER_CONNECTIONS": "50",
        "PGBOUNCER_MAX_PREPARED_STATEMENTS": "200",
        "PGBOUNCER_QUERY_TIMEOUT": "60",
        "PGBOUNCER_IDLE_TRANSACTION_TIMEOUT": "30",
        "PGBOUNCER_CLIENT_IDLE_TIMEOUT": "300",
        "PGBOUNCER_SERVER_IDLE_TIMEOUT": "300",
        "PGBOUNCER_SERVER_LIFETIME": "3600",
        "PGBOUNCER_WAITING_RATIO_LIMIT": "0.10",
        "PGBOUNCER_AVERAGE_QUERY_LIMIT_MS": "250",
        "PGBOUNCER_REQUIRE_TLS": "false",
        "PGBOUNCER_CONFIG": "/etc/pgbouncer/pgbouncer.ini",
        "PGBOUNCER_USERLIST": "/etc/pgbouncer/userlist.txt",
        "PGBOUNCER_HBA": "/etc/pgbouncer/pgbouncer_hba.conf",
        "PGBOUNCER_LOG": "/var/log/pgbouncer.log",
        "PGBOUNCER_PID": "/var/run/pgbouncer/pgbouncer.pid",
    }
    result.update(overrides)
    return result


POOL_HEADER = (
    "database\tuser\tcl_active\tcl_waiting\tcl_active_cancel_req\t"
    "cl_waiting_cancel_req\tsv_active\tsv_active_cancel\tsv_idle\tsv_used\t"
    "sv_tested\tsv_login\tmaxwait\tmaxwait_us\tpool_mode"
)


def pool_tsv(
    *,
    database: str = "appdb",
    user: str = "app_user",
    active: int = 20,
    waiting: int = 0,
    server_active: int = 10,
    server_idle: int = 20,
    pool_mode: str = "transaction",
) -> str:
    values = (
        database,
        user,
        str(active),
        str(waiting),
        "0",
        "0",
        str(server_active),
        "0",
        str(server_idle),
        "0",
        "0",
        "0",
        "0",
        "0",
        pool_mode,
    )
    return POOL_HEADER + "\n" + "\t".join(values) + "\n"


STATS_HEADER = (
    "database\ttotal_xact_count\ttotal_query_count\ttotal_received\t"
    "total_sent\ttotal_xact_time\ttotal_query_time\ttotal_wait_time\t"
    "avg_xact_count\tavg_query_count\tavg_recv\tavg_sent\tavg_xact_time\t"
    "avg_query_time\tavg_wait_time"
)


def stats_tsv(*, database: str = "appdb", average_query_us: int = 1000) -> str:
    values = (
        database,
        "100",
        "300",
        "10000",
        "20000",
        "200000",
        "300000",
        "10000",
        "10",
        "30",
        "1000",
        "2000",
        "2000",
        str(average_query_us),
        "100",
    )
    return STATS_HEADER + "\n" + "\t".join(values) + "\n"


class ParsingTests(unittest.TestCase):
    def test_parse_int_and_bounds(self) -> None:
        self.assertEqual(harness.parse_int("10", name="count", minimum=1), 10)
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_int("bad", name="count")
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_int("0", name="count", minimum=1)
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_int("11", name="count", maximum=10)

    def test_parse_float_and_bounds(self) -> None:
        self.assertEqual(harness.parse_float("0.25", name="ratio"), 0.25)
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_float("many", name="ratio")
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_float("-1", name="ratio", minimum=0)

    def test_parse_bool(self) -> None:
        for value in ("true", "yes", "1", "on"):
            self.assertTrue(harness.parse_bool(value, name="flag"))
        for value in ("false", "no", "0", "off"):
            self.assertFalse(harness.parse_bool(value, name="flag"))
        with self.assertRaises(harness.ConfigurationError):
            harness.parse_bool("maybe", name="flag")

    def test_identifier_validation(self) -> None:
        self.assertEqual(harness.identifier("app_user", name="user"), "app_user")
        for value in ("9user", "user-name", "user;drop", "a" * 64):
            with self.subTest(value=value):
                with self.assertRaises(harness.ConfigurationError):
                    harness.identifier(value, name="user")

    def test_host_validation(self) -> None:
        self.assertEqual(harness.host("database.internal", name="host"), "database.internal")
        self.assertEqual(harness.host("2001:db8::1", name="host"), "2001:db8::1")
        with self.assertRaises(harness.ConfigurationError):
            harness.host("database;command", name="host")

    def test_ini_quote_rejects_injection(self) -> None:
        self.assertEqual(harness.quote_ini("database.internal"), "database.internal")
        for value in ("value\nnext=bad", "value;bad"):
            with self.assertRaises(harness.ConfigurationError):
                harness.quote_ini(value)

    def test_userlist_escaping(self) -> None:
        self.assertEqual(harness.quote_userlist('a"b'), 'a""b')

    def test_percentile(self) -> None:
        values = [1.0, 2.0, 3.0, 4.0]
        self.assertEqual(harness.percentile(values, 0), 1.0)
        self.assertEqual(harness.percentile(values, 50), 2.5)
        self.assertEqual(harness.percentile(values, 100), 4.0)
        self.assertEqual(harness.percentile([7.0], 95), 7.0)
        with self.assertRaises(ValueError):
            harness.percentile([], 50)


class RuntimeSpecTests(unittest.TestCase):
    def test_default_policy(self) -> None:
        spec = harness.RuntimeSpec.from_env(valid_env())
        self.assertEqual(spec.backend.database, "appdb")
        self.assertEqual(spec.policy.mode, harness.PoolMode.TRANSACTION)
        self.assertEqual(spec.policy.max_client_connections, 500)
        self.assertEqual(spec.policy.max_database_connections, 50)
        self.assertEqual(spec.policy.max_prepared_statements, 200)

    def test_users_must_be_distinct(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "must be distinct"):
            harness.RuntimeSpec.from_env(valid_env(PGBOUNCER_AUTH_USER="app_user"))

    def test_passwords_must_be_long(self) -> None:
        for variable in (
            "PGBOUNCER_APPLICATION_PASSWORD",
            "PGBOUNCER_AUTH_PASSWORD",
            "PGBOUNCER_ADMIN_PASSWORD",
        ):
            with self.subTest(variable=variable):
                with self.assertRaisesRegex(harness.ConfigurationError, variable):
                    harness.RuntimeSpec.from_env(valid_env(**{variable: "short"}))

    def test_minimum_pool_cannot_exceed_default(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "minimum pool"):
            harness.RuntimeSpec.from_env(
                valid_env(PGBOUNCER_MIN_POOL_SIZE="41", PGBOUNCER_DEFAULT_POOL_SIZE="40")
            )

    def test_database_limit_must_cover_pool(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "database connection limit"):
            harness.RuntimeSpec.from_env(
                valid_env(PGBOUNCER_DEFAULT_POOL_SIZE="40", PGBOUNCER_MAX_DB_CONNECTIONS="39")
            )

    def test_user_limit_cannot_exceed_database_limit(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "user connection limit"):
            harness.RuntimeSpec.from_env(
                valid_env(PGBOUNCER_MAX_DB_CONNECTIONS="50", PGBOUNCER_MAX_USER_CONNECTIONS="51")
            )

    def test_clients_must_exceed_pool_capacity(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "provide pooling"):
            harness.RuntimeSpec.from_env(
                valid_env(
                    PGBOUNCER_MAX_CLIENT_CONN="50",
                    PGBOUNCER_DEFAULT_POOL_SIZE="40",
                    PGBOUNCER_RESERVE_POOL_SIZE="10",
                )
            )

    def test_transaction_mode_requires_prepared_cache(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "requires max_prepared"):
            harness.RuntimeSpec.from_env(valid_env(PGBOUNCER_MAX_PREPARED_STATEMENTS="0"))

    def test_statement_mode_rejects_prepared_cache(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "statement pooling"):
            harness.RuntimeSpec.from_env(
                valid_env(
                    PGBOUNCER_POOL_MODE="statement",
                    PGBOUNCER_MAX_PREPARED_STATEMENTS="1",
                )
            )

    def test_session_mode_allows_zero_prepared_cache(self) -> None:
        spec = harness.RuntimeSpec.from_env(
            valid_env(
                PGBOUNCER_POOL_MODE="session",
                PGBOUNCER_MAX_PREPARED_STATEMENTS="0",
            )
        )
        self.assertEqual(spec.policy.mode, harness.PoolMode.SESSION)

    def test_waiting_ratio_range(self) -> None:
        with self.assertRaises(harness.ConfigurationError):
            harness.RuntimeSpec.from_env(valid_env(PGBOUNCER_WAITING_RATIO_LIMIT="1.1"))

    def test_paths_must_be_absolute(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "must be absolute"):
            harness.RuntimeSpec.from_env(valid_env(PGBOUNCER_CONFIG="config/pgbouncer.ini"))


class RenderingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.RuntimeSpec.from_env(valid_env())

    def test_ini_contains_capacity_and_timeout_policy(self) -> None:
        text = harness.render_ini(self.spec)
        self.assertIn("[databases]", text)
        self.assertIn("host=database port=5333 dbname=appdb", text)
        self.assertIn("auth_user=pool_auth", text)
        self.assertIn("pool_mode = transaction", text)
        self.assertIn("max_client_conn = 500", text)
        self.assertIn("max_db_connections = 50", text)
        self.assertIn("max_prepared_statements = 200", text)
        self.assertIn("idle_transaction_timeout = 30", text)

    def test_tls_policy_changes_server_mode(self) -> None:
        spec = harness.RuntimeSpec.from_env(valid_env(PGBOUNCER_REQUIRE_TLS="true"))
        self.assertIn("server_tls_sslmode = require", harness.render_ini(spec))
        self.assertIn("server_tls_sslmode = prefer", harness.render_ini(self.spec))

    def test_userlist_contains_only_auth_and_admin(self) -> None:
        text = harness.render_userlist(self.spec)
        self.assertIn('"pool_auth" "authentication-password"', text)
        self.assertIn('"pool_admin" "administration-password"', text)
        self.assertNotIn("app_user", text)

    def test_hba_separates_console_and_database(self) -> None:
        text = harness.render_hba(self.spec)
        self.assertIn("pgbouncer", text)
        self.assertIn("pool_admin", text)
        self.assertIn("appdb", text)
        self.assertIn("scram-sha-256", text)

    def test_auth_function_has_safe_security_context(self) -> None:
        text = harness.render_auth_sql(self.spec)
        self.assertIn("SECURITY DEFINER", text)
        self.assertIn("SET search_path = pg_catalog, pg_temp", text)
        self.assertIn("rolvaliduntil", text)
        self.assertIn("REVOKE ALL", text)
        self.assertIn("GRANT EXECUTE", text)

    def test_write_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            paths = harness.write_files(self.spec, pathlib.Path(directory))
            self.assertEqual(len(paths), 4)
            names = {path.name for path in paths}
            self.assertEqual(
                names,
                {"pgbouncer.ini", "userlist.txt", "pgbouncer_hba.conf", "install_auth.sql"},
            )


class MetricsParsingTests(unittest.TestCase):
    def test_parse_pool_metrics(self) -> None:
        pool = harness.parse_pools(pool_tsv())[0]
        self.assertEqual(pool.database, "appdb")
        self.assertEqual(pool.clients, 20)
        self.assertEqual(pool.servers, 30)
        self.assertEqual(pool.waiting_ratio, 0)
        self.assertEqual(pool.max_wait, 0)

    def test_waiting_ratio(self) -> None:
        pool = harness.parse_pools(pool_tsv(active=90, waiting=10))[0]
        self.assertEqual(pool.clients, 100)
        self.assertAlmostEqual(pool.waiting_ratio, 0.1)

    def test_parse_stats(self) -> None:
        stats = harness.parse_stats(stats_tsv(average_query_us=2500))[0]
        self.assertEqual(stats.total_query_count, 300)
        self.assertEqual(stats.average_query_ms, 2.5)

    def test_missing_pool_column_is_reported(self) -> None:
        raw = "database\tuser\nappdb\tapp_user\n"
        with self.assertRaisesRegex(harness.MetricsError, "missing columns"):
            harness.parse_pools(raw)

    def test_noninteger_pool_column_is_reported(self) -> None:
        raw = pool_tsv().replace("\t20\t0\t", "\tmany\t0\t")
        with self.assertRaisesRegex(harness.MetricsError, "not an integer"):
            harness.parse_pools(raw)

    def test_missing_stats_column_is_reported(self) -> None:
        raw = "database\ttotal_xact_count\nappdb\t10\n"
        with self.assertRaisesRegex(harness.MetricsError, "missing columns"):
            harness.parse_stats(raw)

    def test_parse_tsv_requires_header(self) -> None:
        with self.assertRaises(harness.MetricsError):
            harness.parse_tsv("")


class AuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.RuntimeSpec.from_env(valid_env())

    def audit(self, pool: str = "", stats: str = "") -> list[str]:
        return harness.audit_metrics(
            self.spec,
            harness.parse_pools(pool or pool_tsv()),
            harness.parse_stats(stats or stats_tsv()),
        )

    def test_healthy_metrics_pass(self) -> None:
        self.assertEqual(self.audit(), [])

    def test_missing_database_pool_fails(self) -> None:
        problems = self.audit(pool=pool_tsv(database="other"))
        self.assertIn("no pool exists for database appdb", problems)

    def test_wrong_pool_mode_fails(self) -> None:
        problems = self.audit(pool=pool_tsv(pool_mode="session"))
        self.assertTrue(any("expected transaction" in problem for problem in problems))

    def test_client_limit_fails(self) -> None:
        problems = self.audit(pool=pool_tsv(active=501))
        self.assertTrue(any("above limit 500" in problem for problem in problems))

    def test_server_limit_fails(self) -> None:
        problems = self.audit(pool=pool_tsv(server_active=31, server_idle=20))
        self.assertTrue(any("above database limit" in problem for problem in problems))

    def test_waiting_ratio_fails(self) -> None:
        problems = self.audit(pool=pool_tsv(active=80, waiting=20))
        self.assertTrue(any("waiting ratio" in problem for problem in problems))

    def test_missing_database_stats_fails(self) -> None:
        problems = self.audit(stats=stats_tsv(database="other"))
        self.assertIn("no statistics exist for database appdb", problems)

    def test_slow_average_query_fails(self) -> None:
        problems = self.audit(stats=stats_tsv(average_query_us=251000))
        self.assertTrue(any("average query time" in problem for problem in problems))


class FakeRunner:
    def __init__(self, outputs: list[str]) -> None:
        self.outputs = outputs
        self.calls: list[tuple[list[str], dict[str, object]]] = []
        self.lock = threading.Lock()

    def run(self, command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        with self.lock:
            self.calls.append((command, kwargs))
            output = self.outputs.pop(0) if self.outputs else "1234\n100\n"
        return subprocess.CompletedProcess(command, 0, output, "")


class RuntimeCommandTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.RuntimeSpec.from_env(valid_env())

    def test_psql_command_does_not_contain_password(self) -> None:
        command = harness.psql_command("pool", 6432, "app_user", "appdb", "SELECT 1")
        self.assertIn("--no-psqlrc", command)
        self.assertIn("ON_ERROR_STOP=1", command)
        self.assertNotIn(self.spec.backend.application_password, command)

    def test_console_query_uses_admin_password_environment(self) -> None:
        csv_output = "database,user\nappdb,app_user\n"
        runner = FakeRunner([csv_output])
        converted = harness.console_query(self.spec, "SHOW POOLS", runner=runner, host_name="pool")
        self.assertEqual(converted, "database\tuser\nappdb\tapp_user\n")
        command, kwargs = runner.calls[0]
        self.assertIn("--csv", command)
        self.assertIn("pgbouncer", command)
        self.assertEqual(kwargs["env"]["PGPASSWORD"], self.spec.backend.admin_password)

    def test_run_client_extracts_backend_pid(self) -> None:
        runner = FakeRunner(["4321\n100\n"])
        result = harness.run_client(
            self.spec,
            0,
            statements=100,
            hold_ms=0,
            runner=runner,
        )
        self.assertTrue(result.success)
        self.assertEqual(result.backend_pid, 4321)

    def test_run_load_reports_connection_reuse(self) -> None:
        runner = FakeRunner(["1001\n100\n", "1001\n100\n", "1002\n100\n"])
        result = harness.run_load(
            self.spec,
            clients=3,
            concurrency=1,
            statements=100,
            hold_ms=0,
            runner=runner,
        )
        self.assertEqual(result["succeeded"], 3)
        self.assertEqual(result["failed"], 0)
        self.assertEqual(result["backend_connections_observed"], 2)
        self.assertEqual(result["pooling_ratio"], 1.5)
        self.assertIsNotNone(result["latency_ms"]["p95"])

    def test_run_load_validates_limits(self) -> None:
        with self.assertRaises(harness.ConfigurationError):
            harness.run_load(self.spec, clients=0, concurrency=1, statements=1, hold_ms=0)
        with self.assertRaises(harness.ConfigurationError):
            harness.run_load(self.spec, clients=10, concurrency=11, statements=1, hold_ms=0)
        with self.assertRaisesRegex(harness.ConfigurationError, "exceed"):
            harness.run_load(self.spec, clients=501, concurrency=1, statements=1, hold_ms=0)

    def test_preflight_warns_about_transaction_semantics_and_tls(self) -> None:
        result = harness.preflight(self.spec)
        self.assertEqual(len(result["warnings"]), 2)
        self.assertEqual(result["pool_mode"], "transaction")

    def test_preflight_cli(self) -> None:
        args = harness.build_parser().parse_args(["preflight"])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(harness.execute(args, self.spec), 0)
        self.assertEqual(json.loads(output.getvalue())["max_clients"], 500)

    def test_render_cli(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            args = harness.build_parser().parse_args(["render", "--output", directory])
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                harness.execute(args, self.spec)
            self.assertEqual(len(json.loads(output.getvalue())["rendered"]), 4)

    def test_main_returns_two_for_bad_policy(self) -> None:
        stderr = io.StringIO()
        with mock.patch.dict(
            os.environ,
            valid_env(PGBOUNCER_WAITING_RATIO_LIMIT="bad"),
            clear=True,
        ):
            with contextlib.redirect_stderr(stderr):
                result = harness.main(["preflight"])
        self.assertEqual(result, 2)
        self.assertIn("must be a number", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
