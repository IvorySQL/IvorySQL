#!/usr/bin/env python3
"""Configure, operate, and audit pgBackRest backups for IvorySQL."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import enum
import getpass
import json
import os
import pathlib
import re
import subprocess
import sys
from collections.abc import Mapping, Sequence
from typing import Any


UTC = dt.timezone.utc
STANZA_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,62}$")
LSN_PATTERN = re.compile(r"^[0-9A-F]+/[0-9A-F]+$", re.IGNORECASE)
NAME_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{1,128}$")


class HarnessError(RuntimeError):
    """Base class for actionable backup harness errors."""


class ConfigurationError(HarnessError):
    """Raised for unsafe or contradictory policy configuration."""


class CommandError(HarnessError):
    """Raised when pgBackRest or IvorySQL commands fail."""


class PolicyError(HarnessError):
    """Raised when repository state violates the declared backup policy."""


def value(env: Mapping[str, str], key: str, default: str) -> str:
    result = env.get(key, default).strip()
    if not result:
        raise ConfigurationError(f"{key} must not be empty")
    return result


def integer(
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


def boolean(raw: str, *, name: str) -> bool:
    normalized = raw.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ConfigurationError(f"{name} must be true or false")


def duration(raw: str, *, name: str) -> dt.timedelta:
    match = re.fullmatch(r"([0-9]+)(m|h|d|w)?", raw.strip(), re.IGNORECASE)
    if not match:
        raise ConfigurationError(f"{name} must be a duration such as 12h or 7d")
    count = int(match.group(1))
    if count <= 0:
        raise ConfigurationError(f"{name} must be greater than zero")
    seconds = {None: 60, "m": 60, "h": 3600, "d": 86400, "w": 604800}
    return dt.timedelta(seconds=count * seconds[match.group(2).lower() if match.group(2) else None])


def byte_size(raw: str, *, name: str) -> int:
    match = re.fullmatch(r"([0-9]+)(B|KiB|MiB|GiB|TiB)?", raw.strip(), re.IGNORECASE)
    if not match:
        raise ConfigurationError(f"{name} must be a size such as 1GiB")
    unit = match.group(2).lower() if match.group(2) else None
    multiplier = {
        None: 1,
        "b": 1,
        "kib": 1024,
        "mib": 1024**2,
        "gib": 1024**3,
        "tib": 1024**4,
    }
    return int(match.group(1)) * multiplier[unit]


def mode(raw: str, *, name: str, choices: set[str]) -> str:
    normalized = raw.strip().lower()
    if normalized not in choices:
        raise ConfigurationError(f"{name} must be one of: {', '.join(sorted(choices))}")
    return normalized


def quote_config(raw: str) -> str:
    if "\n" in raw or "\r" in raw:
        raise ConfigurationError("pgBackRest config values must not contain newlines")
    return raw.replace("\\", "\\\\").replace("#", "\\#")


def parse_timestamp(raw: str) -> dt.datetime:
    normalized = raw.strip().replace("Z", "+00:00")
    try:
        result = dt.datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ConfigurationError(f"invalid ISO-8601 timestamp: {raw!r}") from exc
    if result.tzinfo is None:
        raise ConfigurationError("recovery timestamps must include a UTC offset")
    return result.astimezone(UTC)


class RepositoryType(str, enum.Enum):
    POSIX = "posix"
    S3 = "s3"


class BackupType(str, enum.Enum):
    FULL = "full"
    DIFF = "diff"
    INCR = "incr"


@dataclasses.dataclass(frozen=True, slots=True)
class RepositorySpec:
    kind: RepositoryType
    path: str
    cipher_type: str
    cipher_pass: str | None
    s3_bucket: str | None = None
    s3_endpoint: str | None = None
    s3_region: str | None = None
    s3_key: str | None = None
    s3_key_secret: str | None = None
    s3_uri_style: str = "host"
    storage_verify_tls: bool = True

    def __post_init__(self) -> None:
        if not self.path.startswith("/"):
            raise ConfigurationError("BACKUP_REPO_PATH must be absolute")
        if self.cipher_type not in {"none", "aes-256-cbc"}:
            raise ConfigurationError("BACKUP_CIPHER_TYPE must be none or aes-256-cbc")
        if self.cipher_type != "none" and not self.cipher_pass:
            raise ConfigurationError("BACKUP_CIPHER_PASS is required when encryption is enabled")
        if self.cipher_pass and len(self.cipher_pass) < 16:
            raise ConfigurationError("BACKUP_CIPHER_PASS must contain at least 16 characters")
        if self.kind is RepositoryType.S3:
            required = {
                "BACKUP_S3_BUCKET": self.s3_bucket,
                "BACKUP_S3_ENDPOINT": self.s3_endpoint,
                "BACKUP_S3_REGION": self.s3_region,
                "BACKUP_S3_KEY": self.s3_key,
                "BACKUP_S3_KEY_SECRET": self.s3_key_secret,
            }
            missing = [key for key, item in required.items() if not item]
            if missing:
                raise ConfigurationError("S3 repository is missing: " + ", ".join(missing))
        if self.s3_uri_style not in {"host", "path"}:
            raise ConfigurationError("BACKUP_S3_URI_STYLE must be host or path")


@dataclasses.dataclass(frozen=True, slots=True)
class BackupPolicy:
    retention_full: int
    retention_diff: int
    full_max_age: dt.timedelta
    any_backup_max_age: dt.timedelta
    minimum_backup_size: int
    require_encryption: bool
    process_max: int
    compression_type: str
    compression_level: int

    def __post_init__(self) -> None:
        if self.retention_full < 2:
            raise ConfigurationError("BACKUP_RETENTION_FULL must be at least 2")
        if self.retention_diff < self.retention_full:
            raise ConfigurationError(
                "BACKUP_RETENTION_DIFF must not be smaller than BACKUP_RETENTION_FULL"
            )
        if self.compression_type not in {"none", "gz", "bz2", "lz4", "zst"}:
            raise ConfigurationError("unsupported BACKUP_COMPRESS_TYPE")
        if not 0 <= self.compression_level <= 9:
            raise ConfigurationError("BACKUP_COMPRESS_LEVEL must be between 0 and 9")
        if self.process_max < 1:
            raise ConfigurationError("BACKUP_PROCESS_MAX must be positive")


@dataclasses.dataclass(frozen=True, slots=True)
class RuntimeSpec:
    stanza: str
    pg_path: pathlib.Path
    pg_port: int
    db_user: str
    config_path: pathlib.Path
    log_path: pathlib.Path
    lock_path: pathlib.Path
    spool_path: pathlib.Path
    repository: RepositorySpec
    policy: BackupPolicy

    def __post_init__(self) -> None:
        if not STANZA_PATTERN.fullmatch(self.stanza):
            raise ConfigurationError("BACKUP_STANZA contains unsafe characters")
        if not path_is_absolute(self.pg_path):
            raise ConfigurationError("IVORYSQL_DATA_DIR must be absolute")
        if path_is_root(self.pg_path):
            raise ConfigurationError("IVORYSQL_DATA_DIR must not be a filesystem root")
        if not 1 <= self.pg_port <= 65535:
            raise ConfigurationError("IVORYSQL_PORT is out of range")
        for path, label in (
            (self.config_path, "BACKUP_CONFIG_PATH"),
            (self.log_path, "BACKUP_LOG_PATH"),
            (self.lock_path, "BACKUP_LOCK_PATH"),
            (self.spool_path, "BACKUP_SPOOL_PATH"),
        ):
            if not path_is_absolute(path):
                raise ConfigurationError(f"{label} must be absolute")

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "RuntimeSpec":
        source = os.environ if env is None else env
        repo_type = RepositoryType(
            mode(
                value(source, "BACKUP_REPO_TYPE", "posix"),
                name="BACKUP_REPO_TYPE",
                choices={item.value for item in RepositoryType},
            )
        )
        cipher_type = mode(
            value(source, "BACKUP_CIPHER_TYPE", "aes-256-cbc"),
            name="BACKUP_CIPHER_TYPE",
            choices={"none", "aes-256-cbc"},
        )
        repository = RepositorySpec(
            kind=repo_type,
            path=value(source, "BACKUP_REPO_PATH", "/var/lib/pgbackrest"),
            cipher_type=cipher_type,
            cipher_pass=source.get("BACKUP_CIPHER_PASS") or None,
            s3_bucket=source.get("BACKUP_S3_BUCKET") or None,
            s3_endpoint=source.get("BACKUP_S3_ENDPOINT") or None,
            s3_region=source.get("BACKUP_S3_REGION") or None,
            s3_key=source.get("BACKUP_S3_KEY") or None,
            s3_key_secret=source.get("BACKUP_S3_KEY_SECRET") or None,
            s3_uri_style=source.get("BACKUP_S3_URI_STYLE", "host"),
            storage_verify_tls=boolean(
                source.get("BACKUP_STORAGE_VERIFY_TLS", "true"),
                name="BACKUP_STORAGE_VERIFY_TLS",
            ),
        )
        policy = BackupPolicy(
            retention_full=integer(
                value(source, "BACKUP_RETENTION_FULL", "2"),
                name="BACKUP_RETENTION_FULL",
                minimum=2,
            ),
            retention_diff=integer(
                value(source, "BACKUP_RETENTION_DIFF", "4"),
                name="BACKUP_RETENTION_DIFF",
                minimum=2,
            ),
            full_max_age=duration(
                value(source, "BACKUP_FULL_MAX_AGE", "8d"),
                name="BACKUP_FULL_MAX_AGE",
            ),
            any_backup_max_age=duration(
                value(source, "BACKUP_ANY_MAX_AGE", "26h"),
                name="BACKUP_ANY_MAX_AGE",
            ),
            minimum_backup_size=byte_size(
                value(source, "BACKUP_MINIMUM_SIZE", "1MiB"),
                name="BACKUP_MINIMUM_SIZE",
            ),
            require_encryption=boolean(
                value(source, "BACKUP_REQUIRE_ENCRYPTION", "true"),
                name="BACKUP_REQUIRE_ENCRYPTION",
            ),
            process_max=integer(
                value(source, "BACKUP_PROCESS_MAX", "2"),
                name="BACKUP_PROCESS_MAX",
                minimum=1,
                maximum=64,
            ),
            compression_type=mode(
                value(source, "BACKUP_COMPRESS_TYPE", "zst"),
                name="BACKUP_COMPRESS_TYPE",
                choices={"none", "gz", "bz2", "lz4", "zst"},
            ),
            compression_level=integer(
                value(source, "BACKUP_COMPRESS_LEVEL", "3"),
                name="BACKUP_COMPRESS_LEVEL",
                minimum=0,
                maximum=9,
            ),
        )
        return cls(
            stanza=value(source, "BACKUP_STANZA", "ivorysql"),
            pg_path=pathlib.Path(value(source, "IVORYSQL_DATA_DIR", "/var/lib/ivorysql/data")),
            pg_port=integer(
                value(source, "IVORYSQL_PORT", "5333"),
                name="IVORYSQL_PORT",
                minimum=1,
                maximum=65535,
            ),
            db_user=value(source, "IVORYSQL_USER", "ivorysql"),
            config_path=pathlib.Path(
                value(source, "BACKUP_CONFIG_PATH", "/etc/pgbackrest/pgbackrest.conf")
            ),
            log_path=pathlib.Path(value(source, "BACKUP_LOG_PATH", "/var/log/pgbackrest")),
            lock_path=pathlib.Path(value(source, "BACKUP_LOCK_PATH", "/tmp/pgbackrest")),
            spool_path=pathlib.Path(value(source, "BACKUP_SPOOL_PATH", "/var/spool/pgbackrest")),
            repository=repository,
            policy=policy,
        )


def render_config(spec: RuntimeSpec) -> str:
    repo = spec.repository
    policy = spec.policy
    lines = [
        f"[{spec.stanza}]",
        f"pg1-path={quote_config(spec.pg_path.as_posix())}",
        f"pg1-port={spec.pg_port}",
        "",
        "[global]",
        f"repo1-type={repo.kind.value}",
        f"repo1-path={quote_config(repo.path)}",
        f"repo1-retention-full={policy.retention_full}",
        f"repo1-retention-diff={policy.retention_diff}",
        "repo1-retention-archive-type=full",
        f"repo1-cipher-type={repo.cipher_type}",
        f"process-max={policy.process_max}",
        f"compress-type={policy.compression_type}",
        f"compress-level={policy.compression_level}",
        "archive-async=y",
        "archive-timeout=60",
        "backup-standby=n",
        "delta=y",
        "start-fast=y",
        "stop-auto=y",
        "resume=y",
        f"log-path={quote_config(spec.log_path.as_posix())}",
        f"lock-path={quote_config(spec.lock_path.as_posix())}",
        f"spool-path={quote_config(spec.spool_path.as_posix())}",
        "log-level-console=info",
        "log-level-file=detail",
    ]
    if repo.cipher_type != "none":
        lines.append(f"repo1-cipher-pass={quote_config(repo.cipher_pass or '')}")
    if repo.kind is RepositoryType.S3:
        lines.extend(
            [
                f"repo1-s3-bucket={quote_config(repo.s3_bucket or '')}",
                f"repo1-s3-endpoint={quote_config(repo.s3_endpoint or '')}",
                f"repo1-s3-region={quote_config(repo.s3_region or '')}",
                f"repo1-s3-key={quote_config(repo.s3_key or '')}",
                f"repo1-s3-key-secret={quote_config(repo.s3_key_secret or '')}",
                f"repo1-s3-uri-style={repo.s3_uri_style}",
                f"repo1-storage-verify-tls={'y' if repo.storage_verify_tls else 'n'}",
            ]
        )
    lines.extend(["", "[global:archive-push]", "process-max=2", ""])
    return "\n".join(lines)


def path_is_absolute(path: pathlib.Path) -> bool:
    """Treat container-style POSIX paths as absolute on non-POSIX hosts."""
    portable = path.as_posix()
    return portable.startswith("/") or path.is_absolute()


def path_is_root(path: pathlib.Path) -> bool:
    portable = path.as_posix().rstrip("/")
    return portable == "" or (path.is_absolute() and path.parent == path)


def write_config(spec: RuntimeSpec, output: pathlib.Path | None = None) -> pathlib.Path:
    target = output or spec.config_path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render_config(spec), encoding="utf-8", newline="\n")
    try:
        target.chmod(0o600)
    except OSError:
        pass
    return target


@dataclasses.dataclass(frozen=True, slots=True)
class BackupSet:
    label: str
    backup_type: BackupType
    timestamp_start: dt.datetime
    timestamp_stop: dt.datetime
    database_size: int
    repository_size: int
    archive_start: str | None
    archive_stop: str | None
    error: bool
    prior: str | None
    reference: tuple[str, ...]

    @property
    def duration(self) -> dt.timedelta:
        return self.timestamp_stop - self.timestamp_start

    @property
    def complete(self) -> bool:
        return not self.error and self.timestamp_stop >= self.timestamp_start

    @classmethod
    def from_payload(cls, payload: Mapping[str, Any]) -> "BackupSet":
        try:
            timestamps = payload["timestamp"]
            info = payload["info"]
            repo = info["repository"]
            backup_type = BackupType(str(payload["type"]))
            started = dt.datetime.fromtimestamp(int(timestamps["start"]), tz=UTC)
            stopped = dt.datetime.fromtimestamp(int(timestamps["stop"]), tz=UTC)
            reference_value = payload.get("reference", [])
            if not isinstance(reference_value, list):
                raise TypeError("reference is not a list")
            return cls(
                label=str(payload["label"]),
                backup_type=backup_type,
                timestamp_start=started,
                timestamp_stop=stopped,
                database_size=int(info["size"]),
                repository_size=int(repo["size"]),
                archive_start=str(payload["archive"]["start"]) if payload.get("archive", {}).get("start") else None,
                archive_stop=str(payload["archive"]["stop"]) if payload.get("archive", {}).get("stop") else None,
                error=bool(payload.get("error", False)),
                prior=str(payload["prior"]) if payload.get("prior") else None,
                reference=tuple(str(item) for item in reference_value),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise PolicyError(f"malformed pgBackRest backup record: {exc}") from exc


@dataclasses.dataclass(frozen=True, slots=True)
class RepositoryStatus:
    stanza: str
    status_code: int
    status_message: str
    cipher: str
    backups: tuple[BackupSet, ...]
    database_version: str | None
    database_system_id: int | None

    @property
    def latest(self) -> BackupSet | None:
        return max(self.backups, key=lambda item: item.timestamp_stop, default=None)

    @property
    def latest_full(self) -> BackupSet | None:
        return max(
            (item for item in self.backups if item.backup_type is BackupType.FULL),
            key=lambda item: item.timestamp_stop,
            default=None,
        )

    @classmethod
    def from_payload(cls, payload: Mapping[str, Any]) -> "RepositoryStatus":
        try:
            status = payload["status"]
            databases = payload.get("db", [])
            current = databases[-1] if databases else {}
            backups = tuple(BackupSet.from_payload(item) for item in payload.get("backup", []))
            return cls(
                stanza=str(payload["name"]),
                status_code=int(status["code"]),
                status_message=str(status["message"]),
                cipher=str(payload.get("cipher", "none")),
                backups=backups,
                database_version=str(current["version"]) if current.get("version") else None,
                database_system_id=int(current["system-id"]) if current.get("system-id") else None,
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise PolicyError(f"malformed pgBackRest stanza record: {exc}") from exc


def parse_info(raw: str, stanza: str) -> RepositoryStatus:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise PolicyError("pgBackRest info did not return valid JSON") from exc
    if not isinstance(payload, list):
        raise PolicyError("pgBackRest info JSON must be a list")
    matches = [item for item in payload if isinstance(item, dict) and item.get("name") == stanza]
    if not matches:
        raise PolicyError(f"stanza {stanza!r} is absent from repository info")
    if len(matches) > 1:
        raise PolicyError(f"repository info contains duplicate stanza {stanza!r}")
    return RepositoryStatus.from_payload(matches[0])


def audit_repository(
    spec: RuntimeSpec,
    status: RepositoryStatus,
    *,
    now: dt.datetime | None = None,
) -> list[str]:
    current = (now or dt.datetime.now(UTC)).astimezone(UTC)
    problems: list[str] = []
    if status.status_code != 0:
        problems.append(f"stanza status is {status.status_code}: {status.status_message}")
    if status.stanza != spec.stanza:
        problems.append(f"repository stanza {status.stanza!r} does not match {spec.stanza!r}")
    if spec.policy.require_encryption and status.cipher == "none":
        problems.append("repository encryption is required but cipher is none")
    if not status.backups:
        problems.append("repository contains no backups")
        return problems
    latest = status.latest
    latest_full = status.latest_full
    assert latest is not None
    if current - latest.timestamp_stop > spec.policy.any_backup_max_age:
        problems.append(
            f"latest backup {latest.label} is older than {spec.policy.any_backup_max_age}"
        )
    if latest_full is None:
        problems.append("repository contains no full backup")
    elif current - latest_full.timestamp_stop > spec.policy.full_max_age:
        problems.append(
            f"latest full backup {latest_full.label} is older than {spec.policy.full_max_age}"
        )
    for backup in status.backups:
        if not backup.complete:
            problems.append(f"backup {backup.label} is incomplete or failed")
        if backup.repository_size < spec.policy.minimum_backup_size:
            problems.append(
                f"backup {backup.label} repository size {backup.repository_size} is below "
                f"{spec.policy.minimum_backup_size}"
            )
        if not backup.archive_start or not backup.archive_stop:
            problems.append(f"backup {backup.label} does not include a complete WAL archive range")
        if backup.backup_type is not BackupType.FULL and not backup.prior:
            problems.append(f"dependent backup {backup.label} does not identify a prior backup")
    labels = {backup.label for backup in status.backups}
    for backup in status.backups:
        missing_references = set(backup.reference) - labels
        if missing_references:
            problems.append(
                f"backup {backup.label} references missing sets: "
                + ", ".join(sorted(missing_references))
            )
    return problems


class RecoveryTargetType(str, enum.Enum):
    DEFAULT = "default"
    TIME = "time"
    LSN = "lsn"
    XID = "xid"
    NAME = "name"
    IMMEDIATE = "immediate"


@dataclasses.dataclass(frozen=True, slots=True)
class RecoveryPlan:
    target_type: RecoveryTargetType
    target: str | None
    backup_set: str | None
    timeline: str
    action: str
    delta: bool
    link_all: bool
    process_max: int

    def __post_init__(self) -> None:
        if self.target_type in {RecoveryTargetType.DEFAULT, RecoveryTargetType.IMMEDIATE}:
            if self.target:
                raise ConfigurationError(f"{self.target_type.value} recovery must not specify a target")
        elif not self.target:
            raise ConfigurationError(f"{self.target_type.value} recovery requires a target")
        if self.target_type is RecoveryTargetType.TIME:
            parse_timestamp(self.target or "")
        elif self.target_type is RecoveryTargetType.LSN:
            if not LSN_PATTERN.fullmatch(self.target or ""):
                raise ConfigurationError("recovery LSN must use hexadecimal X/Y format")
        elif self.target_type is RecoveryTargetType.XID:
            integer(self.target or "", name="recovery XID", minimum=1)
        elif self.target_type is RecoveryTargetType.NAME:
            if not NAME_PATTERN.fullmatch(self.target or ""):
                raise ConfigurationError("recovery point name contains unsafe characters")
        if self.backup_set and not NAME_PATTERN.fullmatch(self.backup_set):
            raise ConfigurationError("backup set label contains unsafe characters")
        if self.timeline not in {"current", "latest"} and not self.timeline.isdigit():
            raise ConfigurationError("recovery timeline must be current, latest, or a number")
        if self.action not in {"pause", "promote", "shutdown"}:
            raise ConfigurationError("recovery action must be pause, promote, or shutdown")
        if not 1 <= self.process_max <= 64:
            raise ConfigurationError("restore process count must be between 1 and 64")

    def arguments(self) -> list[str]:
        result = [
            "--type=" + self.target_type.value,
            "--target-timeline=" + self.timeline,
            "--target-action=" + self.action,
            "--process-max=" + str(self.process_max),
        ]
        if self.target:
            result.append("--target=" + self.target)
        if self.backup_set:
            result.append("--set=" + self.backup_set)
        if self.delta:
            result.append("--delta")
        if self.link_all:
            result.append("--link-all")
        return result


class CommandRunner:
    def run(
        self,
        command: Sequence[str],
        *,
        timeout: float = 300.0,
        check: bool = True,
        env: Mapping[str, str] | None = None,
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
            raise CommandError(f"command timed out after {timeout:g}s: {command[0]}") from exc
        if check and result.returncode:
            details = (result.stderr or result.stdout).strip()[-2000:]
            raise CommandError(f"command failed ({result.returncode}): {details}")
        return result


class PgBackRest:
    def __init__(self, spec: RuntimeSpec, runner: CommandRunner | None = None) -> None:
        self.spec = spec
        self.runner = runner or CommandRunner()

    def command(self, *arguments: str, timeout: float = 300.0) -> subprocess.CompletedProcess[str]:
        command = [
            "pgbackrest",
            f"--config={self.spec.config_path.as_posix()}",
            f"--stanza={self.spec.stanza}",
            *arguments,
        ]
        return self.runner.run(command, timeout=timeout)

    def version(self) -> str:
        return self.runner.run(["pgbackrest", "version"], timeout=15.0).stdout.strip()

    def stanza_create(self) -> str:
        return self.command("stanza-create", timeout=120.0).stdout

    def check(self) -> str:
        return self.command("check", timeout=120.0).stdout

    def backup(self, backup_type: BackupType) -> str:
        return self.command(f"--type={backup_type.value}", "backup", timeout=86400.0).stdout

    def expire(self) -> str:
        return self.command("expire", timeout=3600.0).stdout

    def info(self) -> RepositoryStatus:
        raw = self.command("--output=json", "info", timeout=60.0).stdout
        return parse_info(raw, self.spec.stanza)

    def restore(self, plan: RecoveryPlan) -> str:
        return self.command(*plan.arguments(), "restore", timeout=86400.0).stdout


def preflight(spec: RuntimeSpec, service: PgBackRest | None = None) -> dict[str, Any]:
    warnings: list[str] = []
    if spec.repository.kind is RepositoryType.POSIX and spec.repository.path.startswith("/tmp"):
        warnings.append("repository is under /tmp and may not be durable")
    if spec.repository.kind is RepositoryType.S3 and not spec.repository.storage_verify_tls:
        warnings.append("S3 TLS certificate verification is disabled")
    if not spec.policy.require_encryption:
        warnings.append("repository encryption policy is disabled")
    if spec.repository.cipher_type == "none":
        warnings.append("repository data is not encrypted by pgBackRest")
    version = None
    if service is not None:
        version = service.version()
    return {
        "stanza": spec.stanza,
        "data_directory": str(spec.pg_path),
        "repository_type": spec.repository.kind.value,
        "repository_path": spec.repository.path,
        "retention_full": spec.policy.retention_full,
        "retention_diff": spec.policy.retention_diff,
        "operator": getpass.getuser(),
        "pgbackrest_version": version,
        "warnings": warnings,
    }


def ensure_safe_restore_path(path: pathlib.Path) -> None:
    if not path_is_absolute(path):
        raise ConfigurationError("restore path must be absolute")
    portable = "/" + path.as_posix().lstrip("/")
    normalized = str(pathlib.PurePosixPath(portable))
    forbidden = {"/", "/var", "/var/lib", "/var/lib/ivorysql", "/home"}
    if normalized in forbidden:
        raise ConfigurationError(f"refusing restore into broad path {normalized}")
    if len(pathlib.PurePosixPath(normalized).parts) < 4:
        raise ConfigurationError(f"restore path is too broad: {normalized}")


def require_confirmation(message: str, *, assume_yes: bool) -> None:
    if assume_yes:
        return
    if not sys.stdin.isatty():
        raise ConfigurationError("restore requires --yes in non-interactive mode")
    response = input(message + " [y/N] ").strip().lower()
    if response not in {"y", "yes"}:
        raise HarnessError("operation cancelled")


def status_dict(status: RepositoryStatus, problems: Sequence[str] = ()) -> dict[str, Any]:
    return {
        "stanza": status.stanza,
        "status": {"code": status.status_code, "message": status.status_message},
        "cipher": status.cipher,
        "database": {
            "version": status.database_version,
            "system_id": status.database_system_id,
        },
        "backup_count": len(status.backups),
        "latest": dataclasses.asdict(status.latest) if status.latest else None,
        "latest_full": dataclasses.asdict(status.latest_full) if status.latest_full else None,
        "policy_problems": list(problems),
    }


def json_default(item: Any) -> Any:
    if isinstance(item, (dt.datetime, dt.timedelta, enum.Enum, pathlib.Path)):
        return str(item)
    raise TypeError(f"cannot serialize {type(item).__name__}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage pgBackRest backups for IvorySQL")
    parser.add_argument("--json", action="store_true")
    subparsers = parser.add_subparsers(dest="command", required=True)

    render = subparsers.add_parser("render", help="write a validated pgBackRest config")
    render.add_argument("--output", type=pathlib.Path)

    preflight_parser = subparsers.add_parser("preflight", help="validate backup policy")
    preflight_parser.add_argument("--check-binary", action="store_true")

    subparsers.add_parser("stanza-create", help="create or upgrade repository stanza")
    subparsers.add_parser("check", help="verify database and archive connectivity")

    backup_parser = subparsers.add_parser("backup", help="run a full, differential, or incremental backup")
    backup_parser.add_argument("--type", choices=[item.value for item in BackupType], default="incr")
    backup_parser.add_argument("--expire", action="store_true")

    subparsers.add_parser("info", help="show machine-readable repository state")
    subparsers.add_parser("audit", help="enforce age, WAL, size, and encryption policy")

    restore = subparsers.add_parser("restore", help="restore the configured data directory")
    restore.add_argument(
        "--type",
        choices=[item.value for item in RecoveryTargetType],
        default="default",
    )
    restore.add_argument("--target")
    restore.add_argument("--set", dest="backup_set")
    restore.add_argument("--timeline", default="latest")
    restore.add_argument("--action", choices=["pause", "promote", "shutdown"], default="promote")
    restore.add_argument("--process-max", type=int)
    restore.add_argument("--delta", action="store_true")
    restore.add_argument("--link-all", action="store_true")
    restore.add_argument("--dry-run", action="store_true")
    restore.add_argument("--yes", action="store_true")
    return parser


def execute(args: argparse.Namespace, spec: RuntimeSpec, runner: CommandRunner | None = None) -> int:
    service = PgBackRest(spec, runner)
    result: Any
    if args.command == "render":
        target = write_config(spec, args.output)
        result = {"config": str(target)}
    elif args.command == "preflight":
        result = preflight(spec, service if args.check_binary else None)
    elif args.command == "stanza-create":
        result = {"output": service.stanza_create().strip()}
    elif args.command == "check":
        result = {"output": service.check().strip()}
    elif args.command == "backup":
        output = service.backup(BackupType(args.type))
        expired = service.expire() if args.expire else ""
        result = {"backup_output": output.strip(), "expire_output": expired.strip()}
    elif args.command in {"info", "audit"}:
        status = service.info()
        problems = audit_repository(spec, status) if args.command == "audit" else []
        result = status_dict(status, problems)
        if problems:
            raise PolicyError("; ".join(problems))
    elif args.command == "restore":
        plan = RecoveryPlan(
            target_type=RecoveryTargetType(args.type),
            target=args.target,
            backup_set=args.backup_set,
            timeline=args.timeline,
            action=args.action,
            delta=args.delta,
            link_all=args.link_all,
            process_max=args.process_max or spec.policy.process_max,
        )
        ensure_safe_restore_path(spec.pg_path)
        result = {
            "data_directory": str(spec.pg_path),
            "arguments": plan.arguments(),
            "destructive": True,
        }
        if not args.dry_run:
            require_confirmation(
                f"Restore will replace the IvorySQL data directory at {spec.pg_path}",
                assume_yes=args.yes,
            )
            result["output"] = service.restore(plan).strip()
    else:
        raise AssertionError(f"unhandled command {args.command}")
    print(json.dumps(result, indent=2, sort_keys=True, default=json_default))
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
