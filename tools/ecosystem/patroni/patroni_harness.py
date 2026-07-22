#!/usr/bin/env python3
"""Operate and validate a Patroni-managed IvorySQL test cluster.

The harness deliberately uses only the Python standard library so that config
generation and policy validation can run on developer machines and in CI
before Docker is available. Runtime operations talk to Patroni's REST API and
use psql for SQL-level checks.
"""

from __future__ import annotations

import argparse
import dataclasses
import getpass
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Iterable, Mapping, Sequence
from typing import Any, TextIO


DEFAULT_SCOPE = "ivorysql-ha"
DEFAULT_NAMESPACE = "/ivorysql/"
DEFAULT_PORT = 8008
DEFAULT_SQL_PORT = 5432
DEFAULT_TIMEOUT = 120.0
DEFAULT_LAG_LIMIT = 16 * 1024 * 1024
NAME_PATTERN = re.compile(r"^[a-z][a-z0-9-]{0,62}$")
LSN_PATTERN = re.compile(r"^[0-9A-F]+/[0-9A-F]+$", re.IGNORECASE)


class HarnessError(RuntimeError):
    """Base error for a user-actionable harness failure."""


class ConfigurationError(HarnessError):
    """Raised when environment or CLI input is unsafe or inconsistent."""


class PatroniAPIError(HarnessError):
    """Raised when Patroni returns an unexpected response."""


class VerificationError(HarnessError):
    """Raised when cluster invariants do not hold."""


def env_value(env: Mapping[str, str], key: str, default: str) -> str:
    value = env.get(key, default).strip()
    if not value:
        raise ConfigurationError(f"{key} must not be empty")
    return value


def parse_int(
    value: str,
    *,
    name: str,
    minimum: int | None = None,
    maximum: int | None = None,
) -> int:
    try:
        result = int(value, 10)
    except ValueError as exc:
        raise ConfigurationError(f"{name} must be an integer") from exc
    if minimum is not None and result < minimum:
        raise ConfigurationError(f"{name} must be at least {minimum}")
    if maximum is not None and result > maximum:
        raise ConfigurationError(f"{name} must be at most {maximum}")
    return result


def parse_duration(value: str, *, name: str) -> float:
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)(ms|s|m|h)?", value.strip())
    if not match:
        raise ConfigurationError(f"{name} must be a duration such as 30s or 2m")
    amount = float(match.group(1))
    multiplier = {None: 1.0, "ms": 0.001, "s": 1.0, "m": 60.0, "h": 3600.0}
    result = amount * multiplier[match.group(2)]
    if result <= 0:
        raise ConfigurationError(f"{name} must be greater than zero")
    return result


def parse_bytes(value: str, *, name: str) -> int:
    match = re.fullmatch(r"([0-9]+)(B|KiB|MiB|GiB)?", value.strip(), re.IGNORECASE)
    if not match:
        raise ConfigurationError(f"{name} must be a size such as 16MiB")
    units = {None: 1, "b": 1, "kib": 1024, "mib": 1024**2, "gib": 1024**3}
    return int(match.group(1)) * units[match.group(2).lower() if match.group(2) else None]


def parse_bool(value: str, *, name: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ConfigurationError(f"{name} must be true or false")


def parse_csv(value: str, *, name: str) -> tuple[str, ...]:
    result = tuple(part.strip() for part in value.split(",") if part.strip())
    if not result:
        raise ConfigurationError(f"{name} must contain at least one value")
    if len(set(result)) != len(result):
        raise ConfigurationError(f"{name} contains duplicate values")
    return result


def validate_name(value: str, *, name: str) -> str:
    if not NAME_PATTERN.fullmatch(value):
        raise ConfigurationError(
            f"{name} must start with a lowercase letter and contain only "
            "lowercase letters, digits, and hyphens"
        )
    return value


def lsn_to_int(value: str | None) -> int | None:
    if value is None or value == "":
        return None
    if not LSN_PATTERN.fullmatch(value):
        raise VerificationError(f"invalid PostgreSQL LSN returned by Patroni: {value!r}")
    high, low = value.split("/", 1)
    return (int(high, 16) << 32) + int(low, 16)


def quote_yaml(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


@dataclasses.dataclass(frozen=True, slots=True)
class NodeSpec:
    """Network and identity settings for one Patroni member."""

    name: str
    host: str
    rest_port: int = DEFAULT_PORT
    sql_port: int = DEFAULT_SQL_PORT
    api_url: str | None = None

    def __post_init__(self) -> None:
        validate_name(self.name, name="node name")
        if not self.host or any(character.isspace() for character in self.host):
            raise ConfigurationError(f"invalid host for {self.name}")
        for label, port in (("REST", self.rest_port), ("SQL", self.sql_port)):
            if not 1 <= port <= 65535:
                raise ConfigurationError(f"{label} port for {self.name} is out of range")

    @property
    def rest_url(self) -> str:
        return self.api_url or f"http://{self.host}:{self.rest_port}"

    @property
    def sql_endpoint(self) -> str:
        return f"{self.host}:{self.sql_port}"


@dataclasses.dataclass(frozen=True, slots=True)
class ClusterSpec:
    """Validated deployment policy used by rendering and runtime checks."""

    scope: str
    namespace: str
    nodes: tuple[NodeSpec, ...]
    etcd_hosts: tuple[str, ...]
    superuser: str
    superuser_password: str
    replication_user: str
    replication_password: str
    api_user: str
    api_password: str
    database: str
    ttl: int = 30
    loop_wait: int = 10
    retry_timeout: int = 10
    maximum_lag_on_failover: int = 1024 * 1024
    synchronous_mode: bool = True
    synchronous_node_count: int = 1
    maximum_replication_lag: int = DEFAULT_LAG_LIMIT

    def __post_init__(self) -> None:
        validate_name(self.scope, name="cluster scope")
        if not self.namespace.startswith("/") or not self.namespace.endswith("/"):
            raise ConfigurationError("namespace must begin and end with '/'")
        if len(self.nodes) < 3:
            raise ConfigurationError("a failover test cluster requires at least three nodes")
        if len({node.name for node in self.nodes}) != len(self.nodes):
            raise ConfigurationError("node names must be unique")
        if not self.etcd_hosts:
            raise ConfigurationError("at least one etcd endpoint is required")
        if self.loop_wait + 2 * self.retry_timeout > self.ttl:
            raise ConfigurationError(
                "Patroni safety rule requires loop_wait + 2 * retry_timeout <= ttl"
            )
        if self.synchronous_node_count < 1:
            raise ConfigurationError("synchronous_node_count must be positive")
        if self.synchronous_node_count >= len(self.nodes):
            raise ConfigurationError("synchronous_node_count must be smaller than node count")
        for label, secret in (
            ("PATRONI_SUPERUSER_PASSWORD", self.superuser_password),
            ("PATRONI_REPLICATION_PASSWORD", self.replication_password),
            ("PATRONI_API_PASSWORD", self.api_password),
        ):
            if len(secret) < 8:
                raise ConfigurationError(f"{label} must contain at least eight characters")

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "ClusterSpec":
        source = os.environ if env is None else env
        node_names = parse_csv(
            env_value(source, "PATRONI_NODES", "ivory-1,ivory-2,ivory-3"),
            name="PATRONI_NODES",
        )
        rest_port = parse_int(
            env_value(source, "PATRONI_REST_PORT", str(DEFAULT_PORT)),
            name="PATRONI_REST_PORT",
            minimum=1,
            maximum=65535,
        )
        sql_port = parse_int(
            env_value(source, "PATRONI_SQL_PORT", str(DEFAULT_SQL_PORT)),
            name="PATRONI_SQL_PORT",
            minimum=1,
            maximum=65535,
        )
        nodes = tuple(
            NodeSpec(name=name, host=source.get(f"PATRONI_HOST_{index}", name), rest_port=rest_port, sql_port=sql_port)
            for index, name in enumerate(node_names, start=1)
        )
        return cls(
            scope=env_value(source, "PATRONI_SCOPE", DEFAULT_SCOPE),
            namespace=env_value(source, "PATRONI_NAMESPACE", DEFAULT_NAMESPACE),
            nodes=nodes,
            etcd_hosts=parse_csv(
                env_value(source, "PATRONI_ETCD_HOSTS", "etcd:2379"),
                name="PATRONI_ETCD_HOSTS",
            ),
            superuser=env_value(source, "PATRONI_SUPERUSER", "postgres"),
            superuser_password=env_value(source, "PATRONI_SUPERUSER_PASSWORD", "ivorysql-admin"),
            replication_user=env_value(source, "PATRONI_REPLICATION_USER", "replicator"),
            replication_password=env_value(source, "PATRONI_REPLICATION_PASSWORD", "ivorysql-repl"),
            api_user=env_value(source, "PATRONI_API_USER", "patroni"),
            api_password=env_value(source, "PATRONI_API_PASSWORD", "ivorysql-api"),
            database=env_value(source, "PATRONI_DATABASE", "postgres"),
            ttl=parse_int(env_value(source, "PATRONI_TTL", "30"), name="PATRONI_TTL", minimum=20),
            loop_wait=parse_int(env_value(source, "PATRONI_LOOP_WAIT", "10"), name="PATRONI_LOOP_WAIT", minimum=1),
            retry_timeout=parse_int(
                env_value(source, "PATRONI_RETRY_TIMEOUT", "10"),
                name="PATRONI_RETRY_TIMEOUT",
                minimum=1,
            ),
            maximum_lag_on_failover=parse_bytes(
                env_value(source, "PATRONI_FAILOVER_LAG", "1MiB"),
                name="PATRONI_FAILOVER_LAG",
            ),
            synchronous_mode=parse_bool(
                env_value(source, "PATRONI_SYNCHRONOUS_MODE", "true"),
                name="PATRONI_SYNCHRONOUS_MODE",
            ),
            synchronous_node_count=parse_int(
                env_value(source, "PATRONI_SYNCHRONOUS_NODE_COUNT", "1"),
                name="PATRONI_SYNCHRONOUS_NODE_COUNT",
                minimum=1,
            ),
            maximum_replication_lag=parse_bytes(
                env_value(source, "PATRONI_MAXIMUM_REPLICATION_LAG", "16MiB"),
                name="PATRONI_MAXIMUM_REPLICATION_LAG",
            ),
        )

    def node(self, name: str) -> NodeSpec:
        for node in self.nodes:
            if node.name == name:
                return node
        raise ConfigurationError(f"unknown member {name!r}")


def render_patroni_config(spec: ClusterSpec, node: NodeSpec) -> str:
    """Render a per-node Patroni YAML file without a YAML dependency."""
    etcd_hosts = ",".join(spec.etcd_hosts)
    synchronous_mode = "true" if spec.synchronous_mode else "false"
    return f"""scope: {quote_yaml(spec.scope)}
namespace: {quote_yaml(spec.namespace)}
name: {quote_yaml(node.name)}

restapi:
  listen: 0.0.0.0:{node.rest_port}
  connect_address: {node.host}:{node.rest_port}
  authentication:
    username: {quote_yaml(spec.api_user)}
    password: {quote_yaml(spec.api_password)}

etcd3:
  hosts: {quote_yaml(etcd_hosts)}

bootstrap:
  dcs:
    ttl: {spec.ttl}
    loop_wait: {spec.loop_wait}
    retry_timeout: {spec.retry_timeout}
    maximum_lag_on_failover: {spec.maximum_lag_on_failover}
    synchronous_mode: {synchronous_mode}
    synchronous_node_count: {spec.synchronous_node_count}
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        wal_log_hints: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        max_connections: 200
        password_encryption: scram-sha-256
        ivorysql.compatible_mode: oracle
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - host replication {spec.replication_user} 0.0.0.0/0 scram-sha-256
    - host all all 0.0.0.0/0 scram-sha-256

postgresql:
  listen: 0.0.0.0:{node.sql_port}
  connect_address: {node.host}:{node.sql_port}
  data_dir: /var/lib/ivorysql/data
  bin_dir: /opt/ivorysql/bin
  pgpass: /var/lib/ivorysql/.pgpass
  authentication:
    superuser:
      username: {quote_yaml(spec.superuser)}
      password: {quote_yaml(spec.superuser_password)}
    replication:
      username: {quote_yaml(spec.replication_user)}
      password: {quote_yaml(spec.replication_password)}
  parameters:
    unix_socket_directories: /var/run/ivorysql
  create_replica_methods:
    - basebackup
  basebackup:
    checkpoint: fast

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
"""


def render_all(spec: ClusterSpec, output: pathlib.Path) -> list[pathlib.Path]:
    output.mkdir(parents=True, exist_ok=True)
    rendered: list[pathlib.Path] = []
    for node in spec.nodes:
        target = output / f"{node.name}.yml"
        target.write_text(render_patroni_config(spec, node), encoding="utf-8", newline="\n")
        try:
            target.chmod(0o600)
        except OSError:
            pass
        rendered.append(target)
    manifest = {
        "scope": spec.scope,
        "namespace": spec.namespace,
        "nodes": [dataclasses.asdict(node) for node in spec.nodes],
        "synchronous_mode": spec.synchronous_mode,
        "synchronous_node_count": spec.synchronous_node_count,
        "maximum_replication_lag": spec.maximum_replication_lag,
    }
    manifest_path = output / "cluster.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    rendered.append(manifest_path)
    return rendered


class HTTPTransport:
    """Small injectable HTTP transport used by PatroniClient."""

    def request(
        self,
        url: str,
        *,
        method: str,
        headers: Mapping[str, str],
        body: bytes | None,
        timeout: float,
    ) -> tuple[int, bytes]:
        request = urllib.request.Request(url, data=body, headers=dict(headers), method=method)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read()
        except urllib.error.URLError as exc:
            raise PatroniAPIError(f"cannot reach {url}: {exc.reason}") from exc


class PatroniClient:
    """Authenticated client for one member's Patroni REST API."""

    def __init__(
        self,
        node: NodeSpec,
        username: str,
        password: str,
        *,
        timeout: float = 5.0,
        transport: HTTPTransport | None = None,
    ) -> None:
        self.node = node
        self.username = username
        self.password = password
        self.timeout = timeout
        self.transport = transport or HTTPTransport()

    def request(
        self,
        method: str,
        path: str,
        payload: Mapping[str, Any] | None = None,
        *,
        expected: Iterable[int] = (200,),
    ) -> Any:
        if not path.startswith("/"):
            raise ValueError("Patroni API paths must start with '/'")
        credentials = f"{self.username}:{self.password}".encode("utf-8")
        import base64

        headers = {
            "Accept": "application/json",
            "Authorization": "Basic " + base64.b64encode(credentials).decode("ascii"),
        }
        body = None
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        status, response = self.transport.request(
            self.node.rest_url + path,
            method=method,
            headers=headers,
            body=body,
            timeout=self.timeout,
        )
        accepted = tuple(expected)
        if status not in accepted:
            detail = response.decode("utf-8", errors="replace")[:500]
            raise PatroniAPIError(
                f"{self.node.name} {method} {path} returned HTTP {status}: {detail}"
            )
        if not response:
            return None
        try:
            return json.loads(response)
        except json.JSONDecodeError as exc:
            raise PatroniAPIError(f"{self.node.name} returned invalid JSON") from exc

    def health(self) -> dict[str, Any]:
        result = self.request("GET", "/patroni")
        if not isinstance(result, dict):
            raise PatroniAPIError(f"{self.node.name} health response is not an object")
        return result

    def cluster(self) -> dict[str, Any]:
        result = self.request("GET", "/cluster")
        if not isinstance(result, dict):
            raise PatroniAPIError(f"{self.node.name} cluster response is not an object")
        return result

    def switchover(self, leader: str, candidate: str | None = None) -> Any:
        payload: dict[str, Any] = {"leader": leader}
        if candidate:
            payload["candidate"] = candidate
        return self.request("POST", "/switchover", payload, expected=(200, 202))

    def failover(self, candidate: str | None = None) -> Any:
        payload: dict[str, Any] = {}
        if candidate:
            payload["candidate"] = candidate
        return self.request("POST", "/failover", payload, expected=(200, 202))

    def reload(self) -> Any:
        return self.request("POST", "/reload", {}, expected=(200, 202))


@dataclasses.dataclass(frozen=True, slots=True)
class MemberStatus:
    name: str
    role: str
    state: str
    host: str
    port: int
    timeline: int | None
    lag: int | None
    api_url: str | None

    @classmethod
    def from_payload(cls, payload: Mapping[str, Any]) -> "MemberStatus":
        required = ("name", "role", "state", "host", "port")
        missing = [key for key in required if key not in payload]
        if missing:
            raise VerificationError(f"Patroni member is missing fields: {', '.join(missing)}")
        lag = payload.get("lag")
        if lag is not None:
            try:
                lag = int(lag)
            except (TypeError, ValueError) as exc:
                raise VerificationError(f"invalid lag for member {payload['name']}") from exc
        timeline = payload.get("timeline")
        if timeline is not None:
            try:
                timeline = int(timeline)
            except (TypeError, ValueError) as exc:
                raise VerificationError(f"invalid timeline for member {payload['name']}") from exc
        return cls(
            name=str(payload["name"]),
            role=str(payload["role"]).lower(),
            state=str(payload["state"]).lower(),
            host=str(payload["host"]),
            port=int(payload["port"]),
            timeline=timeline,
            lag=lag,
            api_url=str(payload["api_url"]) if payload.get("api_url") else None,
        )


@dataclasses.dataclass(frozen=True, slots=True)
class ClusterSnapshot:
    scope: str
    members: tuple[MemberStatus, ...]

    @classmethod
    def from_payload(cls, payload: Mapping[str, Any]) -> "ClusterSnapshot":
        members_payload = payload.get("members")
        if not isinstance(members_payload, list):
            raise VerificationError("Patroni cluster response does not contain a member list")
        members = tuple(MemberStatus.from_payload(item) for item in members_payload)
        return cls(scope=str(payload.get("scope", "")), members=members)

    @property
    def leaders(self) -> tuple[MemberStatus, ...]:
        return tuple(member for member in self.members if member.role in {"leader", "primary"})

    @property
    def replicas(self) -> tuple[MemberStatus, ...]:
        return tuple(member for member in self.members if member.role in {"replica", "standby_leader"})

    def member(self, name: str) -> MemberStatus:
        for member in self.members:
            if member.name == name:
                return member
        raise VerificationError(f"member {name!r} is absent from Patroni topology")


def validate_snapshot(spec: ClusterSpec, snapshot: ClusterSnapshot) -> list[str]:
    problems: list[str] = []
    expected = {node.name for node in spec.nodes}
    actual = {member.name for member in snapshot.members}
    if expected != actual:
        missing = sorted(expected - actual)
        unexpected = sorted(actual - expected)
        if missing:
            problems.append("missing members: " + ", ".join(missing))
        if unexpected:
            problems.append("unexpected members: " + ", ".join(unexpected))
    if len(snapshot.leaders) != 1:
        problems.append(f"expected exactly one leader, found {len(snapshot.leaders)}")
    if len(snapshot.replicas) < len(spec.nodes) - 1:
        problems.append(
            f"expected at least {len(spec.nodes) - 1} replicas, found {len(snapshot.replicas)}"
        )
    for member in snapshot.members:
        if member.state != "running":
            problems.append(f"{member.name} is in state {member.state!r}")
        if member in snapshot.replicas and member.lag is not None:
            if member.lag > spec.maximum_replication_lag:
                problems.append(
                    f"{member.name} lag {member.lag} exceeds {spec.maximum_replication_lag} bytes"
                )
    timelines = {member.timeline for member in snapshot.members if member.timeline is not None}
    if len(timelines) > 1:
        problems.append("members report different timelines: " + ", ".join(map(str, sorted(timelines))))
    return problems


class CommandRunner:
    """Subprocess adapter that keeps secrets out of command-line arguments."""

    def run(
        self,
        command: Sequence[str],
        *,
        env: Mapping[str, str] | None = None,
        timeout: float = 30.0,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        merged = os.environ.copy()
        if env:
            merged.update(env)
        try:
            result = subprocess.run(
                list(command),
                check=False,
                capture_output=True,
                text=True,
                encoding="utf-8",
                env=merged,
                timeout=timeout,
            )
        except FileNotFoundError as exc:
            raise HarnessError(f"required executable not found: {command[0]}") from exc
        except subprocess.TimeoutExpired as exc:
            raise HarnessError(f"command timed out after {timeout:g}s: {command[0]}") from exc
        if check and result.returncode:
            detail = (result.stderr or result.stdout).strip()[-1000:]
            raise HarnessError(f"command failed ({result.returncode}): {detail}")
        return result


def run_sql(
    spec: ClusterSpec,
    node: NodeSpec,
    sql: str,
    *,
    runner: CommandRunner | None = None,
    timeout: float = 30.0,
) -> str:
    executor = runner or CommandRunner()
    command = [
        "psql",
        "--no-psqlrc",
        "--set",
        "ON_ERROR_STOP=1",
        "--tuples-only",
        "--no-align",
        "--host",
        node.host,
        "--port",
        str(node.sql_port),
        "--username",
        spec.superuser,
        "--dbname",
        spec.database,
        "--command",
        sql,
    ]
    result = executor.run(
        command,
        env={"PGPASSWORD": spec.superuser_password},
        timeout=timeout,
    )
    return result.stdout.strip()


def verify_sql_semantics(
    spec: ClusterSpec,
    snapshot: ClusterSnapshot,
    *,
    runner: CommandRunner | None = None,
) -> list[str]:
    executor = runner or CommandRunner()
    problems: list[str] = []
    leader_name = snapshot.leaders[0].name if len(snapshot.leaders) == 1 else None
    for member in snapshot.members:
        try:
            node = spec.node(member.name)
            recovery = run_sql(spec, node, "SELECT pg_is_in_recovery();", runner=executor)
            expected_recovery = member.name != leader_name
            if recovery not in {"t", "f"}:
                problems.append(f"{member.name} returned invalid recovery status {recovery!r}")
            elif (recovery == "t") != expected_recovery:
                problems.append(f"{member.name} SQL recovery role disagrees with Patroni")
            version = run_sql(spec, node, "SELECT version();", runner=executor)
            if "ivorysql" not in version.lower():
                problems.append(f"{member.name} does not report an IvorySQL server")
            mode = run_sql(
                spec,
                node,
                "SELECT setting FROM pg_settings WHERE name='ivorysql.compatible_mode';",
                runner=executor,
            )
            if mode.lower() != "oracle":
                problems.append(f"{member.name} does not have Oracle compatibility enabled")
        except HarnessError as exc:
            problems.append(f"{member.name} SQL verification failed: {exc}")
    return problems


def wait_for_healthy(
    spec: ClusterSpec,
    *,
    timeout: float = DEFAULT_TIMEOUT,
    poll_interval: float = 2.0,
    verify_sql: bool = False,
    runner: CommandRunner | None = None,
) -> ClusterSnapshot:
    client = PatroniClient(spec.nodes[0], spec.api_user, spec.api_password)
    deadline = time.monotonic() + timeout
    last_error = "cluster has not responded"
    while time.monotonic() < deadline:
        try:
            snapshot = ClusterSnapshot.from_payload(client.cluster())
            problems = validate_snapshot(spec, snapshot)
            if not problems and verify_sql:
                problems.extend(verify_sql_semantics(spec, snapshot, runner=runner))
            if not problems:
                return snapshot
            last_error = "; ".join(problems)
        except HarnessError as exc:
            last_error = str(exc)
        time.sleep(poll_interval)
    raise VerificationError(f"cluster did not become healthy within {timeout:g}s: {last_error}")


def wait_for_leader_change(
    spec: ClusterSpec,
    previous: str,
    *,
    timeout: float = DEFAULT_TIMEOUT,
) -> ClusterSnapshot:
    deadline = time.monotonic() + timeout
    last_error = "leader did not change"
    while time.monotonic() < deadline:
        try:
            snapshot = wait_for_healthy(spec, timeout=min(15.0, timeout), poll_interval=1.0)
            if snapshot.leaders[0].name != previous:
                return snapshot
            last_error = f"{previous} remains leader"
        except HarnessError as exc:
            last_error = str(exc)
        time.sleep(1.0)
    raise VerificationError(f"leader transition timed out: {last_error}")


def snapshot_as_dict(snapshot: ClusterSnapshot) -> dict[str, Any]:
    return {
        "scope": snapshot.scope,
        "leader": snapshot.leaders[0].name if len(snapshot.leaders) == 1 else None,
        "members": [dataclasses.asdict(member) for member in snapshot.members],
    }


def print_snapshot(snapshot: ClusterSnapshot, output: TextIO = sys.stdout) -> None:
    headers = ("NAME", "ROLE", "STATE", "HOST", "PORT", "TIMELINE", "LAG")
    rows = [
        (
            member.name,
            member.role,
            member.state,
            member.host,
            str(member.port),
            "-" if member.timeline is None else str(member.timeline),
            "-" if member.lag is None else str(member.lag),
        )
        for member in snapshot.members
    ]
    widths = [max(len(headers[index]), *(len(row[index]) for row in rows)) for index in range(len(headers))]
    print("  ".join(value.ljust(widths[index]) for index, value in enumerate(headers)), file=output)
    print("  ".join("-" * width for width in widths), file=output)
    for row in rows:
        print("  ".join(value.ljust(widths[index]) for index, value in enumerate(row)), file=output)


def require_confirmation(action: str, *, assume_yes: bool) -> None:
    if assume_yes:
        return
    if not sys.stdin.isatty():
        raise ConfigurationError(f"{action} requires --yes in non-interactive mode")
    answer = input(f"{action}. Continue? [y/N] ").strip().lower()
    if answer not in {"y", "yes"}:
        raise HarnessError("operation cancelled")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Render, inspect, and exercise a Patroni-managed IvorySQL cluster"
    )
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    subparsers = parser.add_subparsers(dest="command", required=True)

    render = subparsers.add_parser("render", help="render per-node Patroni configuration")
    render.add_argument("--output", type=pathlib.Path, default=pathlib.Path("generated"))

    subparsers.add_parser("preflight", help="validate deployment environment without connecting")
    subparsers.add_parser("status", help="show Patroni topology")

    wait = subparsers.add_parser("wait", help="wait until topology and SQL checks pass")
    wait.add_argument("--timeout", default="2m")
    wait.add_argument("--skip-sql", action="store_true")

    switch = subparsers.add_parser("switchover", help="perform a planned leader switchover")
    switch.add_argument("--candidate")
    switch.add_argument("--timeout", default="2m")
    switch.add_argument("--yes", action="store_true")

    failover = subparsers.add_parser("failover", help="request an emergency failover")
    failover.add_argument("--candidate")
    failover.add_argument("--timeout", default="2m")
    failover.add_argument("--yes", action="store_true")

    reload_parser = subparsers.add_parser("reload", help="reload every Patroni member")
    reload_parser.add_argument("--yes", action="store_true")
    return parser


def perform_preflight(spec: ClusterSpec) -> dict[str, Any]:
    warnings: list[str] = []
    if spec.superuser_password == "ivorysql-admin":
        warnings.append("default superuser password is in use")
    if spec.replication_password == "ivorysql-repl":
        warnings.append("default replication password is in use")
    if spec.api_password == "ivorysql-api":
        warnings.append("default REST API password is in use")
    return {
        "scope": spec.scope,
        "node_count": len(spec.nodes),
        "etcd_endpoints": len(spec.etcd_hosts),
        "synchronous_mode": spec.synchronous_mode,
        "maximum_replication_lag": spec.maximum_replication_lag,
        "operator": getpass.getuser(),
        "warnings": warnings,
    }


def execute(args: argparse.Namespace, spec: ClusterSpec) -> int:
    if args.command == "render":
        files = render_all(spec, args.output)
        result: Any = {"rendered": [str(path) for path in files]}
    elif args.command == "preflight":
        result = perform_preflight(spec)
    elif args.command == "status":
        client = PatroniClient(spec.nodes[0], spec.api_user, spec.api_password)
        snapshot = ClusterSnapshot.from_payload(client.cluster())
        problems = validate_snapshot(spec, snapshot)
        if problems:
            raise VerificationError("; ".join(problems))
        if not args.json:
            print_snapshot(snapshot)
            return 0
        result = snapshot_as_dict(snapshot)
    elif args.command == "wait":
        snapshot = wait_for_healthy(
            spec,
            timeout=parse_duration(args.timeout, name="timeout"),
            verify_sql=not args.skip_sql,
        )
        result = snapshot_as_dict(snapshot)
    elif args.command == "switchover":
        before = wait_for_healthy(spec, timeout=30.0)
        leader = before.leaders[0].name
        if args.candidate:
            spec.node(args.candidate)
            if args.candidate == leader:
                raise ConfigurationError("switchover candidate is already leader")
        require_confirmation(
            f"Switchover leader {leader} to {args.candidate or 'an eligible replica'}",
            assume_yes=args.yes,
        )
        client = PatroniClient(spec.node(leader), spec.api_user, spec.api_password)
        client.switchover(leader, args.candidate)
        after = wait_for_leader_change(
            spec,
            leader,
            timeout=parse_duration(args.timeout, name="timeout"),
        )
        result = {"previous_leader": leader, "cluster": snapshot_as_dict(after)}
    elif args.command == "failover":
        before = wait_for_healthy(spec, timeout=30.0)
        previous = before.leaders[0].name
        if args.candidate:
            spec.node(args.candidate)
            if args.candidate == previous:
                raise ConfigurationError("failover candidate is already leader")
        require_confirmation(
            f"Emergency failover away from {previous}",
            assume_yes=args.yes,
        )
        client = PatroniClient(spec.node(previous), spec.api_user, spec.api_password)
        client.failover(args.candidate)
        after = wait_for_leader_change(
            spec,
            previous,
            timeout=parse_duration(args.timeout, name="timeout"),
        )
        result = {"previous_leader": previous, "cluster": snapshot_as_dict(after)}
    elif args.command == "reload":
        require_confirmation("Reload all Patroni members", assume_yes=args.yes)
        reloaded = []
        for node in spec.nodes:
            PatroniClient(node, spec.api_user, spec.api_password).reload()
            reloaded.append(node.name)
        result = {"reloaded": reloaded}
    else:
        raise AssertionError(f"unhandled command: {args.command}")

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    elif args.command in {"render", "preflight", "reload"}:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        cluster = result.get("cluster") if isinstance(result, dict) else None
        print(json.dumps(cluster or result, indent=2, sort_keys=True))
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        spec = ClusterSpec.from_env()
        return execute(args, spec)
    except HarnessError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
