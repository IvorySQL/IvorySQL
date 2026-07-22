#!/usr/bin/env python3
"""Generate and verify a production-shaped PgBouncer setup for IvorySQL."""

from __future__ import annotations

import argparse
import concurrent.futures
import csv
import dataclasses
import enum
import getpass
import io
import json
import os
import pathlib
import re
import statistics
import subprocess
import sys
import time
from collections.abc import Iterable, Mapping, Sequence
from typing import Any


IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,62}$")
HOST_PATTERN = re.compile(r"^[A-Za-z0-9_.:-]+$")


class HarnessError(RuntimeError):
    """Base class for user-actionable errors."""


class ConfigurationError(HarnessError):
    """Raised when a pool policy is invalid or unsafe."""


class CommandError(HarnessError):
    """Raised when a psql or PgBouncer command fails."""


class MetricsError(HarnessError):
    """Raised when console metrics are malformed or violate policy."""


class PoolMode(str, enum.Enum):
    SESSION = "session"
    TRANSACTION = "transaction"
    STATEMENT = "statement"


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


def host(raw: str, *, name: str) -> str:
    if not HOST_PATTERN.fullmatch(raw):
        raise ConfigurationError(f"{name} contains unsafe characters")
    return raw


def quote_ini(raw: str) -> str:
    if any(character in raw for character in "\r\n;"):
        raise ConfigurationError("PgBouncer config values must not contain newlines or semicolons")
    return raw


def quote_userlist(raw: str) -> str:
    return raw.replace('"', '""')


def percentile(values: Sequence[float], percent: float) -> float:
    if not values:
        raise ValueError("cannot calculate percentile of an empty sequence")
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = percent / 100 * (len(ordered) - 1)
    lower = int(rank)
    upper = min(lower + 1, len(ordered) - 1)
    fraction = rank - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


@dataclasses.dataclass(frozen=True, slots=True)
class BackendSpec:
    host: str
    port: int
    database: str
    application_user: str
    application_password: str
    auth_user: str
    auth_password: str
    admin_user: str
    admin_password: str

    def __post_init__(self) -> None:
        host(self.host, name="IVORYSQL_HOST")
        if not 1 <= self.port <= 65535:
            raise ConfigurationError("IVORYSQL_PORT is out of range")
        for label, value in (
            ("IVORYSQL_DATABASE", self.database),
            ("PGBOUNCER_APPLICATION_USER", self.application_user),
            ("PGBOUNCER_AUTH_USER", self.auth_user),
            ("PGBOUNCER_ADMIN_USER", self.admin_user),
        ):
            identifier(value, name=label)
        if len({self.application_user, self.auth_user, self.admin_user}) != 3:
            raise ConfigurationError("application, authentication, and admin users must be distinct")
        for label, secret in (
            ("PGBOUNCER_APPLICATION_PASSWORD", self.application_password),
            ("PGBOUNCER_AUTH_PASSWORD", self.auth_password),
            ("PGBOUNCER_ADMIN_PASSWORD", self.admin_password),
        ):
            if len(secret) < 12:
                raise ConfigurationError(f"{label} must contain at least 12 characters")


@dataclasses.dataclass(frozen=True, slots=True)
class PoolPolicy:
    mode: PoolMode
    listen_port: int
    max_client_connections: int
    default_pool_size: int
    minimum_pool_size: int
    reserve_pool_size: int
    reserve_pool_timeout: float
    max_database_connections: int
    max_user_connections: int
    max_prepared_statements: int
    query_timeout: float
    idle_transaction_timeout: float
    client_idle_timeout: float
    server_idle_timeout: float
    server_lifetime: float
    waiting_ratio_limit: float
    average_query_limit_ms: float
    require_tls: bool

    def __post_init__(self) -> None:
        if not 1 <= self.listen_port <= 65535:
            raise ConfigurationError("PGBOUNCER_PORT is out of range")
        if self.minimum_pool_size > self.default_pool_size:
            raise ConfigurationError("minimum pool size must not exceed default pool size")
        if self.max_database_connections < self.default_pool_size:
            raise ConfigurationError("database connection limit must cover the default pool")
        if self.max_user_connections > self.max_database_connections:
            raise ConfigurationError("user connection limit must not exceed database limit")
        server_capacity = self.default_pool_size + self.reserve_pool_size
        if self.max_client_connections <= server_capacity:
            raise ConfigurationError(
                "max client connections must exceed server pool capacity to provide pooling"
            )
        if self.mode is PoolMode.STATEMENT and self.max_prepared_statements:
            raise ConfigurationError("statement pooling cannot safely expose prepared statements")
        if self.mode is PoolMode.TRANSACTION and self.max_prepared_statements < 1:
            raise ConfigurationError(
                "transaction pooling requires max_prepared_statements for modern clients"
            )
        if not 0 <= self.waiting_ratio_limit <= 1:
            raise ConfigurationError("waiting ratio limit must be between zero and one")
        for label, item in (
            ("query timeout", self.query_timeout),
            ("idle transaction timeout", self.idle_transaction_timeout),
            ("client idle timeout", self.client_idle_timeout),
            ("server idle timeout", self.server_idle_timeout),
            ("server lifetime", self.server_lifetime),
        ):
            if item < 0:
                raise ConfigurationError(f"{label} must not be negative")


@dataclasses.dataclass(frozen=True, slots=True)
class RuntimeSpec:
    backend: BackendSpec
    policy: PoolPolicy
    config_path: pathlib.Path
    userlist_path: pathlib.Path
    hba_path: pathlib.Path
    log_path: pathlib.Path
    pid_path: pathlib.Path

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "RuntimeSpec":
        source = os.environ if env is None else env
        backend = BackendSpec(
            host=env_value(source, "IVORYSQL_HOST", "database"),
            port=parse_int(
                env_value(source, "IVORYSQL_PORT", "5333"),
                name="IVORYSQL_PORT",
                minimum=1,
                maximum=65535,
            ),
            database=env_value(source, "IVORYSQL_DATABASE", "appdb"),
            application_user=env_value(source, "PGBOUNCER_APPLICATION_USER", "app_user"),
            application_password=env_value(
                source, "PGBOUNCER_APPLICATION_PASSWORD", "application-secret"
            ),
            auth_user=env_value(source, "PGBOUNCER_AUTH_USER", "pool_auth"),
            auth_password=env_value(source, "PGBOUNCER_AUTH_PASSWORD", "authentication-secret"),
            admin_user=env_value(source, "PGBOUNCER_ADMIN_USER", "pool_admin"),
            admin_password=env_value(source, "PGBOUNCER_ADMIN_PASSWORD", "administration-secret"),
        )
        policy = PoolPolicy(
            mode=PoolMode(env_value(source, "PGBOUNCER_POOL_MODE", "transaction").lower()),
            listen_port=parse_int(
                env_value(source, "PGBOUNCER_PORT", "6432"),
                name="PGBOUNCER_PORT",
                minimum=1,
                maximum=65535,
            ),
            max_client_connections=parse_int(
                env_value(source, "PGBOUNCER_MAX_CLIENT_CONN", "500"),
                name="PGBOUNCER_MAX_CLIENT_CONN",
                minimum=10,
            ),
            default_pool_size=parse_int(
                env_value(source, "PGBOUNCER_DEFAULT_POOL_SIZE", "40"),
                name="PGBOUNCER_DEFAULT_POOL_SIZE",
                minimum=1,
            ),
            minimum_pool_size=parse_int(
                env_value(source, "PGBOUNCER_MIN_POOL_SIZE", "5"),
                name="PGBOUNCER_MIN_POOL_SIZE",
                minimum=0,
            ),
            reserve_pool_size=parse_int(
                env_value(source, "PGBOUNCER_RESERVE_POOL_SIZE", "10"),
                name="PGBOUNCER_RESERVE_POOL_SIZE",
                minimum=0,
            ),
            reserve_pool_timeout=parse_float(
                env_value(source, "PGBOUNCER_RESERVE_POOL_TIMEOUT", "3"),
                name="PGBOUNCER_RESERVE_POOL_TIMEOUT",
                minimum=0,
            ),
            max_database_connections=parse_int(
                env_value(source, "PGBOUNCER_MAX_DB_CONNECTIONS", "50"),
                name="PGBOUNCER_MAX_DB_CONNECTIONS",
                minimum=1,
            ),
            max_user_connections=parse_int(
                env_value(source, "PGBOUNCER_MAX_USER_CONNECTIONS", "50"),
                name="PGBOUNCER_MAX_USER_CONNECTIONS",
                minimum=1,
            ),
            max_prepared_statements=parse_int(
                env_value(source, "PGBOUNCER_MAX_PREPARED_STATEMENTS", "200"),
                name="PGBOUNCER_MAX_PREPARED_STATEMENTS",
                minimum=0,
            ),
            query_timeout=parse_float(
                env_value(source, "PGBOUNCER_QUERY_TIMEOUT", "60"),
                name="PGBOUNCER_QUERY_TIMEOUT",
                minimum=0,
            ),
            idle_transaction_timeout=parse_float(
                env_value(source, "PGBOUNCER_IDLE_TRANSACTION_TIMEOUT", "30"),
                name="PGBOUNCER_IDLE_TRANSACTION_TIMEOUT",
                minimum=0,
            ),
            client_idle_timeout=parse_float(
                env_value(source, "PGBOUNCER_CLIENT_IDLE_TIMEOUT", "300"),
                name="PGBOUNCER_CLIENT_IDLE_TIMEOUT",
                minimum=0,
            ),
            server_idle_timeout=parse_float(
                env_value(source, "PGBOUNCER_SERVER_IDLE_TIMEOUT", "300"),
                name="PGBOUNCER_SERVER_IDLE_TIMEOUT",
                minimum=0,
            ),
            server_lifetime=parse_float(
                env_value(source, "PGBOUNCER_SERVER_LIFETIME", "3600"),
                name="PGBOUNCER_SERVER_LIFETIME",
                minimum=0,
            ),
            waiting_ratio_limit=parse_float(
                env_value(source, "PGBOUNCER_WAITING_RATIO_LIMIT", "0.10"),
                name="PGBOUNCER_WAITING_RATIO_LIMIT",
                minimum=0,
                maximum=1,
            ),
            average_query_limit_ms=parse_float(
                env_value(source, "PGBOUNCER_AVERAGE_QUERY_LIMIT_MS", "250"),
                name="PGBOUNCER_AVERAGE_QUERY_LIMIT_MS",
                minimum=0,
            ),
            require_tls=parse_bool(
                env_value(source, "PGBOUNCER_REQUIRE_TLS", "false"),
                name="PGBOUNCER_REQUIRE_TLS",
            ),
        )
        result = cls(
            backend=backend,
            policy=policy,
            config_path=pathlib.Path(
                env_value(source, "PGBOUNCER_CONFIG", "/etc/pgbouncer/pgbouncer.ini")
            ),
            userlist_path=pathlib.Path(
                env_value(source, "PGBOUNCER_USERLIST", "/etc/pgbouncer/userlist.txt")
            ),
            hba_path=pathlib.Path(
                env_value(source, "PGBOUNCER_HBA", "/etc/pgbouncer/pgbouncer_hba.conf")
            ),
            log_path=pathlib.Path(env_value(source, "PGBOUNCER_LOG", "/var/log/pgbouncer.log")),
            pid_path=pathlib.Path(env_value(source, "PGBOUNCER_PID", "/var/run/pgbouncer/pgbouncer.pid")),
        )
        for path, label in (
            (result.config_path, "PGBOUNCER_CONFIG"),
            (result.userlist_path, "PGBOUNCER_USERLIST"),
            (result.hba_path, "PGBOUNCER_HBA"),
            (result.log_path, "PGBOUNCER_LOG"),
            (result.pid_path, "PGBOUNCER_PID"),
        ):
            if not path.as_posix().startswith("/") and not path.is_absolute():
                raise ConfigurationError(f"{label} must be absolute")
        return result


def render_ini(spec: RuntimeSpec) -> str:
    backend = spec.backend
    policy = spec.policy
    tls_mode = "require" if policy.require_tls else "prefer"
    return f"""[databases]
{backend.database} = host={quote_ini(backend.host)} port={backend.port} dbname={backend.database} auth_user={backend.auth_user} pool_size={policy.default_pool_size} min_pool_size={policy.minimum_pool_size} reserve_pool_size={policy.reserve_pool_size} max_db_connections={policy.max_database_connections}

[users]
{backend.application_user} = pool_mode={policy.mode.value} max_user_connections={policy.max_user_connections} query_timeout={policy.query_timeout:g} idle_transaction_timeout={policy.idle_transaction_timeout:g}

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = {policy.listen_port}
unix_socket_dir = /var/run/pgbouncer
auth_type = hba
auth_hba_file = {spec.hba_path.as_posix()}
auth_file = {spec.userlist_path.as_posix()}
auth_user = {backend.auth_user}
auth_query = SELECT * FROM pgbouncer.user_lookup($1)
admin_users = {backend.admin_user}
stats_users = {backend.admin_user}
pool_mode = {policy.mode.value}
max_client_conn = {policy.max_client_connections}
default_pool_size = {policy.default_pool_size}
min_pool_size = {policy.minimum_pool_size}
reserve_pool_size = {policy.reserve_pool_size}
reserve_pool_timeout = {policy.reserve_pool_timeout:g}
max_db_connections = {policy.max_database_connections}
max_user_connections = {policy.max_user_connections}
max_prepared_statements = {policy.max_prepared_statements}
query_timeout = {policy.query_timeout:g}
idle_transaction_timeout = {policy.idle_transaction_timeout:g}
client_idle_timeout = {policy.client_idle_timeout:g}
server_idle_timeout = {policy.server_idle_timeout:g}
server_lifetime = {policy.server_lifetime:g}
server_connect_timeout = 10
server_login_retry = 2
server_tls_sslmode = {tls_mode}
server_check_query = SELECT 1
server_check_delay = 15
stats_period = 30
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
log_stats = 1
logfile = {spec.log_path.as_posix()}
pidfile = {spec.pid_path.as_posix()}
ignore_startup_parameters = extra_float_digits
application_name_add_host = 1
"""


def render_userlist(spec: RuntimeSpec) -> str:
    backend = spec.backend
    entries = (
        (backend.auth_user, backend.auth_password),
        (backend.admin_user, backend.admin_password),
    )
    return "".join(
        f'"{quote_userlist(user)}" "{quote_userlist(password)}"\n'
        for user, password in entries
    )


def render_hba(spec: RuntimeSpec) -> str:
    return f"""# TYPE  DATABASE             USER                       ADDRESS       METHOD
local   pgbouncer            {spec.backend.admin_user}               scram-sha-256
host    pgbouncer            {spec.backend.admin_user}  0.0.0.0/0     scram-sha-256
host    pgbouncer            {spec.backend.admin_user}  ::/0          scram-sha-256
host    {spec.backend.database}  all                    0.0.0.0/0     scram-sha-256
host    {spec.backend.database}  all                    ::/0          scram-sha-256
"""


def render_auth_sql(spec: RuntimeSpec) -> str:
    backend = spec.backend
    return f"""CREATE SCHEMA IF NOT EXISTS pgbouncer;

CREATE OR REPLACE FUNCTION pgbouncer.user_lookup(
    IN i_username text,
    OUT uname text,
    OUT phash text
)
RETURNS record
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    SELECT rolname,
           CASE WHEN rolvaliduntil IS NOT NULL AND rolvaliduntil < now()
                THEN NULL ELSE rolpassword END
      INTO uname, phash
      FROM pg_authid
     WHERE rolname = i_username
       AND rolcanlogin;
END;
$$;

REVOKE ALL ON FUNCTION pgbouncer.user_lookup(text) FROM PUBLIC;
GRANT USAGE ON SCHEMA pgbouncer TO {backend.auth_user};
GRANT EXECUTE ON FUNCTION pgbouncer.user_lookup(text) TO {backend.auth_user};
"""


def write_files(spec: RuntimeSpec, output: pathlib.Path) -> list[pathlib.Path]:
    output.mkdir(parents=True, exist_ok=True)
    contents = {
        "pgbouncer.ini": render_ini(spec),
        "userlist.txt": render_userlist(spec),
        "pgbouncer_hba.conf": render_hba(spec),
        "install_auth.sql": render_auth_sql(spec),
    }
    paths = []
    for name, text in contents.items():
        target = output / name
        target.write_text(text, encoding="utf-8", newline="\n")
        if name in {"pgbouncer.ini", "userlist.txt"}:
            try:
                target.chmod(0o600)
            except OSError:
                pass
        paths.append(target)
    return paths


@dataclasses.dataclass(frozen=True, slots=True)
class PoolMetrics:
    database: str
    user: str
    pool_mode: str
    client_active: int
    client_waiting: int
    client_active_cancel: int
    client_waiting_cancel: int
    server_active: int
    server_active_cancel: int
    server_idle: int
    server_used: int
    server_tested: int
    server_login: int
    max_wait_seconds: int
    max_wait_microseconds: int

    @property
    def clients(self) -> int:
        return self.client_active + self.client_waiting

    @property
    def waiting_ratio(self) -> float:
        return self.client_waiting / self.clients if self.clients else 0.0

    @property
    def servers(self) -> int:
        return (
            self.server_active
            + self.server_active_cancel
            + self.server_idle
            + self.server_used
            + self.server_tested
            + self.server_login
        )

    @property
    def max_wait(self) -> float:
        return self.max_wait_seconds + self.max_wait_microseconds / 1_000_000

    @classmethod
    def from_row(cls, row: Mapping[str, str]) -> "PoolMetrics":
        aliases = {
            "database": "database",
            "user": "user",
            "pool_mode": "pool_mode",
            "cl_active": "client_active",
            "cl_waiting": "client_waiting",
            "cl_active_cancel_req": "client_active_cancel",
            "cl_waiting_cancel_req": "client_waiting_cancel",
            "sv_active": "server_active",
            "sv_active_cancel": "server_active_cancel",
            "sv_idle": "server_idle",
            "sv_used": "server_used",
            "sv_tested": "server_tested",
            "sv_login": "server_login",
            "maxwait": "max_wait_seconds",
            "maxwait_us": "max_wait_microseconds",
        }
        missing = [name for name in aliases if name not in row]
        if missing:
            raise MetricsError("SHOW POOLS is missing columns: " + ", ".join(missing))
        values: dict[str, Any] = {}
        for source, target in aliases.items():
            if source in {"database", "user", "pool_mode"}:
                values[target] = row[source]
            else:
                try:
                    values[target] = int(row[source])
                except ValueError as exc:
                    raise MetricsError(f"SHOW POOLS column {source} is not an integer") from exc
        return cls(**values)


@dataclasses.dataclass(frozen=True, slots=True)
class DatabaseStats:
    database: str
    total_xact_count: int
    total_query_count: int
    total_received: int
    total_sent: int
    total_xact_time: int
    total_query_time: int
    total_wait_time: int
    average_xact_count: int
    average_query_count: int
    average_received: int
    average_sent: int
    average_xact_time: int
    average_query_time: int
    average_wait_time: int

    @property
    def average_query_ms(self) -> float:
        return self.average_query_time / 1000

    @classmethod
    def from_row(cls, row: Mapping[str, str]) -> "DatabaseStats":
        names = {
            "database": "database",
            "total_xact_count": "total_xact_count",
            "total_query_count": "total_query_count",
            "total_received": "total_received",
            "total_sent": "total_sent",
            "total_xact_time": "total_xact_time",
            "total_query_time": "total_query_time",
            "total_wait_time": "total_wait_time",
            "avg_xact_count": "average_xact_count",
            "avg_query_count": "average_query_count",
            "avg_recv": "average_received",
            "avg_sent": "average_sent",
            "avg_xact_time": "average_xact_time",
            "avg_query_time": "average_query_time",
            "avg_wait_time": "average_wait_time",
        }
        missing = [name for name in names if name not in row]
        if missing:
            raise MetricsError("SHOW STATS is missing columns: " + ", ".join(missing))
        values: dict[str, Any] = {"database": row["database"]}
        for source, target in names.items():
            if source == "database":
                continue
            try:
                values[target] = int(row[source])
            except ValueError as exc:
                raise MetricsError(f"SHOW STATS column {source} is not an integer") from exc
        return cls(**values)


def parse_tsv(raw: str) -> list[dict[str, str]]:
    reader = csv.DictReader(io.StringIO(raw), delimiter="\t")
    if not reader.fieldnames:
        raise MetricsError("console output does not include a header")
    return [dict(row) for row in reader]


def parse_pools(raw: str) -> tuple[PoolMetrics, ...]:
    return tuple(PoolMetrics.from_row(row) for row in parse_tsv(raw))


def parse_stats(raw: str) -> tuple[DatabaseStats, ...]:
    return tuple(DatabaseStats.from_row(row) for row in parse_tsv(raw))


def audit_metrics(
    spec: RuntimeSpec,
    pools: Iterable[PoolMetrics],
    stats: Iterable[DatabaseStats],
) -> list[str]:
    policy = spec.policy
    problems: list[str] = []
    matching_pools = [item for item in pools if item.database == spec.backend.database]
    if not matching_pools:
        problems.append(f"no pool exists for database {spec.backend.database}")
    for pool in matching_pools:
        if pool.pool_mode != policy.mode.value:
            problems.append(
                f"pool {pool.database}/{pool.user} uses {pool.pool_mode}, expected {policy.mode.value}"
            )
        if pool.clients > policy.max_client_connections:
            problems.append(
                f"pool reports {pool.clients} clients above limit {policy.max_client_connections}"
            )
        if pool.servers > policy.max_database_connections:
            problems.append(
                f"pool reports {pool.servers} servers above database limit "
                f"{policy.max_database_connections}"
            )
        if pool.waiting_ratio > policy.waiting_ratio_limit:
            problems.append(
                f"waiting ratio {pool.waiting_ratio:.3f} exceeds {policy.waiting_ratio_limit:.3f}"
            )
    matching_stats = [item for item in stats if item.database == spec.backend.database]
    if not matching_stats:
        problems.append(f"no statistics exist for database {spec.backend.database}")
    for item in matching_stats:
        if item.average_query_ms > policy.average_query_limit_ms:
            problems.append(
                f"average query time {item.average_query_ms:.3f}ms exceeds "
                f"{policy.average_query_limit_ms:.3f}ms"
            )
    return problems


class CommandRunner:
    def run(
        self,
        command: Sequence[str],
        *,
        env: Mapping[str, str] | None = None,
        timeout: float = 30,
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
            raise CommandError(f"command timed out after {timeout:g}s") from exc
        if check and result.returncode:
            details = (result.stderr or result.stdout).strip()[-1000:]
            raise CommandError(f"command failed ({result.returncode}): {details}")
        return result


def psql_command(
    host_name: str,
    port: int,
    user: str,
    database: str,
    sql: str,
) -> list[str]:
    return [
        "psql",
        "--no-psqlrc",
        "--set",
        "ON_ERROR_STOP=1",
        "--host",
        host_name,
        "--port",
        str(port),
        "--username",
        user,
        "--dbname",
        database,
        "--command",
        sql,
    ]


def console_query(
    spec: RuntimeSpec,
    sql: str,
    *,
    runner: CommandRunner | None = None,
    host_name: str = "127.0.0.1",
) -> str:
    executor = runner or CommandRunner()
    command = psql_command(
        host_name,
        spec.policy.listen_port,
        spec.backend.admin_user,
        "pgbouncer",
        sql,
    )
    command[1:1] = ["--csv"]
    result = executor.run(
        command,
        env={"PGPASSWORD": spec.backend.admin_password},
    )
    # psql --csv is comma-separated. Re-emit TSV for the common parsers.
    rows = list(csv.reader(io.StringIO(result.stdout)))
    return "\n".join("\t".join(row) for row in rows) + ("\n" if rows else "")


@dataclasses.dataclass(frozen=True, slots=True)
class ClientResult:
    index: int
    elapsed_ms: float
    backend_pid: int
    success: bool
    error: str | None


def run_client(
    spec: RuntimeSpec,
    index: int,
    *,
    statements: int,
    hold_ms: int,
    runner: CommandRunner | None = None,
    host_name: str = "127.0.0.1",
) -> ClientResult:
    executor = runner or CommandRunner()
    sql = (
        "BEGIN; "
        "SELECT pg_backend_pid(); "
        f"SELECT count(*) FROM generate_series(1, {statements}); "
        f"SELECT pg_sleep({hold_ms / 1000:.3f}); "
        "COMMIT;"
    )
    command = psql_command(
        host_name,
        spec.policy.listen_port,
        spec.backend.application_user,
        spec.backend.database,
        sql,
    )
    command[1:1] = ["--tuples-only", "--no-align"]
    started = time.monotonic()
    try:
        result = executor.run(
            command,
            env={"PGPASSWORD": spec.backend.application_password},
            timeout=max(30, spec.policy.query_timeout + 5),
        )
        elapsed = (time.monotonic() - started) * 1000
        numbers = [int(line) for line in result.stdout.splitlines() if line.strip().isdigit()]
        backend_pid = numbers[0] if numbers else -1
        return ClientResult(index, elapsed, backend_pid, True, None)
    except HarnessError as exc:
        elapsed = (time.monotonic() - started) * 1000
        return ClientResult(index, elapsed, -1, False, str(exc))


def run_load(
    spec: RuntimeSpec,
    *,
    clients: int,
    concurrency: int,
    statements: int,
    hold_ms: int,
    runner: CommandRunner | None = None,
    host_name: str = "127.0.0.1",
) -> dict[str, Any]:
    if clients < 1 or concurrency < 1:
        raise ConfigurationError("clients and concurrency must be positive")
    if concurrency > clients:
        raise ConfigurationError("concurrency must not exceed clients")
    if clients > spec.policy.max_client_connections:
        raise ConfigurationError("requested clients exceed configured PgBouncer limit")
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [
            executor.submit(
                run_client,
                spec,
                index,
                statements=statements,
                hold_ms=hold_ms,
                runner=runner,
                host_name=host_name,
            )
            for index in range(clients)
        ]
        results = [future.result() for future in futures]
    successes = [item for item in results if item.success]
    failures = [item for item in results if not item.success]
    elapsed = [item.elapsed_ms for item in successes]
    backend_pids = {item.backend_pid for item in successes if item.backend_pid > 0}
    return {
        "clients": clients,
        "concurrency": concurrency,
        "succeeded": len(successes),
        "failed": len(failures),
        "backend_connections_observed": len(backend_pids),
        "pooling_ratio": len(successes) / len(backend_pids) if backend_pids else None,
        "latency_ms": {
            "minimum": min(elapsed) if elapsed else None,
            "mean": statistics.fmean(elapsed) if elapsed else None,
            "p50": percentile(elapsed, 50) if elapsed else None,
            "p95": percentile(elapsed, 95) if elapsed else None,
            "maximum": max(elapsed) if elapsed else None,
        },
        "errors": [item.error for item in failures[:10]],
    }


def preflight(spec: RuntimeSpec) -> dict[str, Any]:
    warnings: list[str] = []
    if not spec.policy.require_tls:
        warnings.append("client and server TLS are not required in this example")
    if spec.policy.mode is PoolMode.TRANSACTION:
        warnings.append(
            "transaction pooling does not preserve session state, LISTEN, session locks, or SQL PREPARE"
        )
    if spec.policy.max_client_connections > 1000:
        warnings.append("raise the PgBouncer process file-descriptor limit")
    return {
        "database": spec.backend.database,
        "backend": f"{spec.backend.host}:{spec.backend.port}",
        "pool_mode": spec.policy.mode.value,
        "max_clients": spec.policy.max_client_connections,
        "database_connection_limit": spec.policy.max_database_connections,
        "prepared_statement_cache": spec.policy.max_prepared_statements,
        "operator": getpass.getuser(),
        "warnings": warnings,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Configure and validate PgBouncer for IvorySQL")
    parser.add_argument("--host", default="127.0.0.1", help="PgBouncer host for runtime commands")
    subparsers = parser.add_subparsers(dest="command", required=True)
    render = subparsers.add_parser("render")
    render.add_argument("--output", type=pathlib.Path, default=pathlib.Path("generated"))
    subparsers.add_parser("preflight")
    subparsers.add_parser("status")
    subparsers.add_parser("audit")
    load = subparsers.add_parser("load")
    load.add_argument("--clients", type=int, default=100)
    load.add_argument("--concurrency", type=int, default=50)
    load.add_argument("--statements", type=int, default=100)
    load.add_argument("--hold-ms", type=int, default=50)
    return parser


def execute(args: argparse.Namespace, spec: RuntimeSpec, runner: CommandRunner | None = None) -> int:
    if args.command == "render":
        result: Any = {"rendered": [str(path) for path in write_files(spec, args.output)]}
    elif args.command == "preflight":
        result = preflight(spec)
    elif args.command in {"status", "audit"}:
        pools = parse_pools(console_query(spec, "SHOW POOLS", runner=runner, host_name=args.host))
        stats = parse_stats(console_query(spec, "SHOW STATS", runner=runner, host_name=args.host))
        problems = audit_metrics(spec, pools, stats)
        result = {
            "pools": [dataclasses.asdict(item) for item in pools],
            "stats": [dataclasses.asdict(item) for item in stats],
            "problems": problems,
        }
        if args.command == "audit" and problems:
            raise MetricsError("; ".join(problems))
    elif args.command == "load":
        result = run_load(
            spec,
            clients=args.clients,
            concurrency=args.concurrency,
            statements=args.statements,
            hold_ms=args.hold_ms,
            runner=runner,
            host_name=args.host,
        )
        if result["failed"]:
            raise MetricsError(f"{result['failed']} load clients failed")
    else:
        raise AssertionError(f"unhandled command {args.command}")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return execute(args, RuntimeSpec.from_env())
    except (HarnessError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
