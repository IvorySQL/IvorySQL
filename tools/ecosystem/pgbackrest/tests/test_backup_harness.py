from __future__ import annotations

import contextlib
import dataclasses
import datetime as dt
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


MODULE_PATH = pathlib.Path(__file__).parents[1] / "backup_harness.py"
SPEC = importlib.util.spec_from_file_location("backup_harness", MODULE_PATH)
assert SPEC and SPEC.loader
harness = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = harness
SPEC.loader.exec_module(harness)


UTC = dt.timezone.utc


def valid_env(**overrides: str) -> dict[str, str]:
    result = {
        "IVORYSQL_DATA_DIR": "/var/lib/ivorysql/data",
        "IVORYSQL_PORT": "5333",
        "IVORYSQL_USER": "ivorysql",
        "BACKUP_STANZA": "ivorysql",
        "BACKUP_CONFIG_PATH": "/etc/pgbackrest/pgbackrest.conf",
        "BACKUP_LOG_PATH": "/var/log/pgbackrest",
        "BACKUP_LOCK_PATH": "/tmp/pgbackrest",
        "BACKUP_SPOOL_PATH": "/var/spool/pgbackrest",
        "BACKUP_REPO_TYPE": "posix",
        "BACKUP_REPO_PATH": "/var/lib/pgbackrest",
        "BACKUP_CIPHER_TYPE": "aes-256-cbc",
        "BACKUP_CIPHER_PASS": "a-strong-cipher-passphrase",
        "BACKUP_REQUIRE_ENCRYPTION": "true",
        "BACKUP_RETENTION_FULL": "2",
        "BACKUP_RETENTION_DIFF": "4",
        "BACKUP_FULL_MAX_AGE": "8d",
        "BACKUP_ANY_MAX_AGE": "26h",
        "BACKUP_MINIMUM_SIZE": "1MiB",
        "BACKUP_PROCESS_MAX": "2",
        "BACKUP_COMPRESS_TYPE": "zst",
        "BACKUP_COMPRESS_LEVEL": "3",
    }
    result.update(overrides)
    return result


def backup_payload(
    label: str,
    backup_type: str,
    stopped: dt.datetime,
    *,
    size: int = 2 * 1024 * 1024,
    error: bool = False,
    prior: str | None = None,
    reference: list[str] | None = None,
) -> dict[str, object]:
    started = stopped - dt.timedelta(minutes=3)
    return {
        "label": label,
        "type": backup_type,
        "timestamp": {
            "start": int(started.timestamp()),
            "stop": int(stopped.timestamp()),
        },
        "info": {
            "size": 4 * 1024 * 1024,
            "repository": {"size": size},
        },
        "archive": {
            "start": "000000010000000000000001",
            "stop": "000000010000000000000002",
        },
        "error": error,
        "prior": prior,
        "reference": reference or [],
    }


def info_payload(now: dt.datetime | None = None) -> list[dict[str, object]]:
    current = now or dt.datetime.now(UTC)
    full_label = "20260721-010000F"
    incr_label = "20260721-010000F_20260722-010000I"
    return [
        {
            "name": "ivorysql",
            "status": {"code": 0, "message": "ok"},
            "cipher": "aes-256-cbc",
            "db": [{"version": "17", "system-id": 123456789}],
            "backup": [
                backup_payload(full_label, "full", current - dt.timedelta(days=1)),
                backup_payload(
                    incr_label,
                    "incr",
                    current - dt.timedelta(hours=1),
                    prior=full_label,
                    reference=[full_label],
                ),
            ],
        }
    ]


class ParsingTests(unittest.TestCase):
    def test_integer_validation(self) -> None:
        self.assertEqual(harness.integer("3", name="count", minimum=1, maximum=4), 3)
        with self.assertRaises(harness.ConfigurationError):
            harness.integer("bad", name="count")
        with self.assertRaises(harness.ConfigurationError):
            harness.integer("0", name="count", minimum=1)
        with self.assertRaises(harness.ConfigurationError):
            harness.integer("5", name="count", maximum=4)

    def test_boolean_validation(self) -> None:
        for raw in ("true", "yes", "1", "ON"):
            self.assertTrue(harness.boolean(raw, name="flag"))
        for raw in ("false", "no", "0", "OFF"):
            self.assertFalse(harness.boolean(raw, name="flag"))
        with self.assertRaises(harness.ConfigurationError):
            harness.boolean("maybe", name="flag")

    def test_duration_units(self) -> None:
        self.assertEqual(harness.duration("30m", name="age"), dt.timedelta(minutes=30))
        self.assertEqual(harness.duration("12h", name="age"), dt.timedelta(hours=12))
        self.assertEqual(harness.duration("7d", name="age"), dt.timedelta(days=7))
        self.assertEqual(harness.duration("2w", name="age"), dt.timedelta(weeks=2))

    def test_duration_rejects_zero_and_unknown_units(self) -> None:
        for raw in ("0h", "1y", "-1d", "soon"):
            with self.subTest(raw=raw):
                with self.assertRaises(harness.ConfigurationError):
                    harness.duration(raw, name="age")

    def test_byte_size(self) -> None:
        self.assertEqual(harness.byte_size("1KiB", name="size"), 1024)
        self.assertEqual(harness.byte_size("3MiB", name="size"), 3 * 1024**2)
        self.assertEqual(harness.byte_size("2GiB", name="size"), 2 * 1024**3)
        self.assertEqual(harness.byte_size("1TiB", name="size"), 1024**4)
        with self.assertRaises(harness.ConfigurationError):
            harness.byte_size("10MB", name="size")

    def test_mode_reports_choices(self) -> None:
        self.assertEqual(harness.mode("POSIX", name="repo", choices={"posix", "s3"}), "posix")
        with self.assertRaisesRegex(harness.ConfigurationError, "posix, s3"):
            harness.mode("azure", name="repo", choices={"posix", "s3"})

    def test_config_quoting_rejects_newlines(self) -> None:
        self.assertEqual(harness.quote_config("path#one"), "path\\#one")
        with self.assertRaises(harness.ConfigurationError):
            harness.quote_config("line1\nline2")

    def test_timestamp_requires_offset(self) -> None:
        parsed = harness.parse_timestamp("2026-07-22T10:30:00+08:00")
        self.assertEqual(parsed.hour, 2)
        self.assertEqual(parsed.tzinfo, UTC)
        with self.assertRaisesRegex(harness.ConfigurationError, "UTC offset"):
            harness.parse_timestamp("2026-07-22T10:30:00")


class RuntimeSpecTests(unittest.TestCase):
    def test_builds_encrypted_posix_policy(self) -> None:
        spec = harness.RuntimeSpec.from_env(valid_env())
        self.assertEqual(spec.stanza, "ivorysql")
        self.assertEqual(spec.repository.kind, harness.RepositoryType.POSIX)
        self.assertEqual(spec.repository.cipher_type, "aes-256-cbc")
        self.assertEqual(spec.policy.retention_full, 2)
        self.assertTrue(spec.policy.require_encryption)

    def test_requires_cipher_passphrase(self) -> None:
        env = valid_env()
        del env["BACKUP_CIPHER_PASS"]
        with self.assertRaisesRegex(harness.ConfigurationError, "CIPHER_PASS"):
            harness.RuntimeSpec.from_env(env)

    def test_rejects_short_cipher_passphrase(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "at least 16"):
            harness.RuntimeSpec.from_env(valid_env(BACKUP_CIPHER_PASS="too-short"))

    def test_allows_unencrypted_repo_when_explicit(self) -> None:
        env = valid_env(BACKUP_CIPHER_TYPE="none", BACKUP_REQUIRE_ENCRYPTION="false")
        del env["BACKUP_CIPHER_PASS"]
        spec = harness.RuntimeSpec.from_env(env)
        self.assertEqual(spec.repository.cipher_type, "none")
        self.assertFalse(spec.policy.require_encryption)

    def test_s3_requires_all_credentials(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "S3 repository is missing"):
            harness.RuntimeSpec.from_env(valid_env(BACKUP_REPO_TYPE="s3"))

    def test_s3_configuration(self) -> None:
        spec = harness.RuntimeSpec.from_env(
            valid_env(
                BACKUP_REPO_TYPE="s3",
                BACKUP_S3_BUCKET="ivory-backups",
                BACKUP_S3_ENDPOINT="s3.example.test",
                BACKUP_S3_REGION="us-east-1",
                BACKUP_S3_KEY="key-id",
                BACKUP_S3_KEY_SECRET="key-secret",
                BACKUP_S3_URI_STYLE="path",
            )
        )
        self.assertEqual(spec.repository.kind, harness.RepositoryType.S3)
        self.assertEqual(spec.repository.s3_bucket, "ivory-backups")
        self.assertEqual(spec.repository.s3_uri_style, "path")

    def test_rejects_broad_data_directories(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "filesystem root"):
            harness.RuntimeSpec.from_env(valid_env(IVORYSQL_DATA_DIR="/"))

    def test_rejects_non_absolute_paths(self) -> None:
        for key in (
            "IVORYSQL_DATA_DIR",
            "BACKUP_CONFIG_PATH",
            "BACKUP_LOG_PATH",
            "BACKUP_LOCK_PATH",
            "BACKUP_SPOOL_PATH",
        ):
            with self.subTest(key=key):
                with self.assertRaises(harness.ConfigurationError):
                    harness.RuntimeSpec.from_env(valid_env(**{key: "relative/path"}))

    def test_retention_policy_invariant(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "must not be smaller"):
            harness.RuntimeSpec.from_env(
                valid_env(BACKUP_RETENTION_FULL="4", BACKUP_RETENTION_DIFF="2")
            )

    def test_stanza_rejects_shell_characters(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "unsafe"):
            harness.RuntimeSpec.from_env(valid_env(BACKUP_STANZA="ivory;rm"))


class RenderingTests(unittest.TestCase):
    def test_render_posix_configuration(self) -> None:
        text = harness.render_config(harness.RuntimeSpec.from_env(valid_env()))
        self.assertIn("[ivorysql]", text)
        self.assertIn("pg1-path=/var/lib/ivorysql/data", text)
        self.assertIn("pg1-socket-path=/var/run/ivorysql", text)
        self.assertIn("repo1-type=posix", text)
        self.assertIn("repo1-cipher-type=aes-256-cbc", text)
        self.assertIn("archive-async=y", text)
        self.assertIn("start-fast=y", text)
        self.assertIn("[global:archive-push]", text)

    def test_render_s3_configuration(self) -> None:
        spec = harness.RuntimeSpec.from_env(
            valid_env(
                BACKUP_REPO_TYPE="s3",
                BACKUP_S3_BUCKET="bucket",
                BACKUP_S3_ENDPOINT="minio.example.test",
                BACKUP_S3_REGION="us-east-1",
                BACKUP_S3_KEY="access",
                BACKUP_S3_KEY_SECRET="secret",
                BACKUP_STORAGE_VERIFY_TLS="false",
            )
        )
        text = harness.render_config(spec)
        self.assertIn("repo1-s3-bucket=bucket", text)
        self.assertIn("repo1-s3-endpoint=minio.example.test", text)
        self.assertIn("repo1-storage-verify-tls=n", text)

    def test_write_config_uses_requested_path(self) -> None:
        spec = harness.RuntimeSpec.from_env(valid_env())
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory) / "config" / "pgbackrest.conf"
            self.assertEqual(harness.write_config(spec, target), target)
            self.assertIn("repo1-retention-full=2", target.read_text())


class InformationParsingTests(unittest.TestCase):
    def test_parse_repository_info(self) -> None:
        payload = info_payload()
        payload[0]["backup"][0]["reference"] = None
        status = harness.parse_info(json.dumps(payload), "ivorysql")
        self.assertEqual(status.status_code, 0)
        self.assertEqual(status.cipher, "aes-256-cbc")
        self.assertEqual(status.database_version, "17")
        self.assertEqual(len(status.backups), 2)
        self.assertEqual(status.latest.backup_type, harness.BackupType.INCR)
        self.assertEqual(status.latest_full.backup_type, harness.BackupType.FULL)
        self.assertEqual(status.latest_full.reference, ())

    def test_parse_info_rejects_invalid_json(self) -> None:
        with self.assertRaisesRegex(harness.PolicyError, "valid JSON"):
            harness.parse_info("broken", "ivorysql")

    def test_parse_info_requires_list(self) -> None:
        with self.assertRaisesRegex(harness.PolicyError, "must be a list"):
            harness.parse_info("{}", "ivorysql")

    def test_parse_info_requires_requested_stanza(self) -> None:
        with self.assertRaisesRegex(harness.PolicyError, "absent"):
            harness.parse_info(json.dumps(info_payload()), "missing")

    def test_parse_info_rejects_duplicate_stanza(self) -> None:
        payload = info_payload()
        payload.append(payload[0])
        with self.assertRaisesRegex(harness.PolicyError, "duplicate"):
            harness.parse_info(json.dumps(payload), "ivorysql")

    def test_backup_duration(self) -> None:
        status = harness.parse_info(json.dumps(info_payload()), "ivorysql")
        self.assertEqual(status.latest.duration, dt.timedelta(minutes=3))
        self.assertTrue(status.latest.complete)

    def test_malformed_backup_record(self) -> None:
        payload = info_payload()
        del payload[0]["backup"][0]["timestamp"]
        with self.assertRaisesRegex(harness.PolicyError, "malformed"):
            harness.parse_info(json.dumps(payload), "ivorysql")


class AuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.now = dt.datetime(2026, 7, 22, 8, 0, tzinfo=UTC)
        self.spec = harness.RuntimeSpec.from_env(valid_env())

    def audit(self, payload: list[dict[str, object]]) -> list[str]:
        return harness.audit_repository(
            self.spec,
            harness.parse_info(json.dumps(payload), "ivorysql"),
            now=self.now,
        )

    def test_healthy_repository_passes(self) -> None:
        self.assertEqual(self.audit(info_payload(self.now)), [])

    def test_nonzero_stanza_status_fails(self) -> None:
        payload = info_payload(self.now)
        payload[0]["status"] = {"code": 1, "message": "missing stanza"}
        self.assertTrue(any("stanza status" in item for item in self.audit(payload)))

    def test_encryption_policy_fails_plain_repository(self) -> None:
        payload = info_payload(self.now)
        payload[0]["cipher"] = "none"
        self.assertTrue(any("encryption" in item for item in self.audit(payload)))

    def test_empty_repository_fails(self) -> None:
        payload = info_payload(self.now)
        payload[0]["backup"] = []
        self.assertIn("repository contains no backups", self.audit(payload))

    def test_stale_latest_backup_fails(self) -> None:
        payload = info_payload(self.now - dt.timedelta(days=3))
        self.assertTrue(any("latest backup" in item for item in self.audit(payload)))

    def test_stale_full_backup_fails(self) -> None:
        payload = info_payload(self.now)
        payload[0]["backup"][0] = backup_payload(
            "20260701-010000F",
            "full",
            self.now - dt.timedelta(days=10),
        )
        self.assertTrue(any("latest full backup" in item for item in self.audit(payload)))

    def test_missing_full_backup_fails(self) -> None:
        payload = info_payload(self.now)
        payload[0]["backup"] = [payload[0]["backup"][1]]
        self.assertIn("repository contains no full backup", self.audit(payload))

    def test_small_backup_fails(self) -> None:
        payload = info_payload(self.now)
        payload[0]["backup"][0]["info"]["repository"]["size"] = 128
        self.assertTrue(any("repository size" in item for item in self.audit(payload)))

    def test_failed_backup_fails(self) -> None:
        payload = info_payload(self.now)
        payload[0]["backup"][1]["error"] = True
        self.assertTrue(any("incomplete or failed" in item for item in self.audit(payload)))

    def test_missing_wal_range_fails(self) -> None:
        payload = info_payload(self.now)
        payload[0]["backup"][0]["archive"]["stop"] = None
        self.assertTrue(any("WAL archive range" in item for item in self.audit(payload)))

    def test_dependent_backup_requires_prior(self) -> None:
        payload = info_payload(self.now)
        payload[0]["backup"][1]["prior"] = None
        self.assertTrue(any("prior backup" in item for item in self.audit(payload)))

    def test_missing_reference_fails(self) -> None:
        payload = info_payload(self.now)
        payload[0]["backup"][1]["reference"] = ["missing-full"]
        self.assertTrue(any("missing sets" in item for item in self.audit(payload)))


class RecoveryPlanTests(unittest.TestCase):
    def test_default_restore_arguments(self) -> None:
        plan = harness.RecoveryPlan(
            harness.RecoveryTargetType.DEFAULT,
            None,
            None,
            "latest",
            "promote",
            False,
            False,
            4,
        )
        self.assertEqual(
            plan.arguments(),
            ["--process-max=4"],
        )

    def test_time_target_must_have_timezone(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "UTC offset"):
            harness.RecoveryPlan(
                harness.RecoveryTargetType.TIME,
                "2026-07-22T10:00:00",
                None,
                "latest",
                "promote",
                False,
                False,
                2,
            )

    def test_lsn_target_validation(self) -> None:
        plan = harness.RecoveryPlan(
            harness.RecoveryTargetType.LSN,
            "0/16B6C50",
            "20260721-010000F",
            "current",
            "pause",
            True,
            True,
            8,
        )
        self.assertIn("--target=0/16B6C50", plan.arguments())
        self.assertIn("--set=20260721-010000F", plan.arguments())
        self.assertIn("--delta", plan.arguments())
        self.assertIn("--link-all", plan.arguments())
        with self.assertRaises(harness.ConfigurationError):
            dataclasses.replace(plan, target="bad-lsn")

    def test_xid_and_name_targets(self) -> None:
        for target_type, target in (
            (harness.RecoveryTargetType.XID, "12345"),
            (harness.RecoveryTargetType.NAME, "before_release_42"),
        ):
            with self.subTest(target_type=target_type):
                plan = harness.RecoveryPlan(
                    target_type, target, None, "latest", "shutdown", False, False, 1
                )
                self.assertIn("--target=" + target, plan.arguments())

    def test_immediate_restore_rejects_target(self) -> None:
        with self.assertRaisesRegex(harness.ConfigurationError, "must not specify"):
            harness.RecoveryPlan(
                harness.RecoveryTargetType.IMMEDIATE,
                "unexpected",
                None,
                "latest",
                "promote",
                False,
                False,
                2,
            )

    def test_immediate_restore_omits_timeline(self) -> None:
        plan = harness.RecoveryPlan(
            harness.RecoveryTargetType.IMMEDIATE,
            None,
            None,
            "latest",
            "promote",
            False,
            False,
            2,
        )
        self.assertEqual(
            plan.arguments(),
            ["--process-max=2", "--type=immediate", "--target-action=promote"],
        )

    def test_restore_path_guard(self) -> None:
        for path in (pathlib.Path("/"), pathlib.Path("/var/lib"), pathlib.Path("/home")):
            with self.subTest(path=path):
                with self.assertRaises(harness.ConfigurationError):
                    harness.ensure_safe_restore_path(path)
        harness.ensure_safe_restore_path(pathlib.Path("/var/lib/ivorysql/data"))


class FakeRunner:
    def __init__(self, outputs: list[str]) -> None:
        self.outputs = outputs
        self.calls: list[tuple[list[str], dict[str, object]]] = []

    def run(self, command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        self.calls.append((command, kwargs))
        output = self.outputs.pop(0) if self.outputs else ""
        return subprocess.CompletedProcess(command, 0, output, "")


class ServiceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = harness.RuntimeSpec.from_env(valid_env())

    def test_pgbackrest_command_contains_config_and_stanza(self) -> None:
        runner = FakeRunner(["ok"])
        service = harness.PgBackRest(self.spec, runner)
        self.assertEqual(service.check(), "ok")
        command = runner.calls[0][0]
        self.assertEqual(command[0], "pgbackrest")
        self.assertIn("--config=/etc/pgbackrest/pgbackrest.conf", command)
        self.assertIn("--stanza=ivorysql", command)
        self.assertEqual(command[-1], "check")

    def test_backup_type_is_forwarded(self) -> None:
        runner = FakeRunner(["backup complete"])
        service = harness.PgBackRest(self.spec, runner)
        service.backup(harness.BackupType.DIFF)
        self.assertIn("--type=diff", runner.calls[0][0])

    def test_info_is_parsed(self) -> None:
        runner = FakeRunner([json.dumps(info_payload())])
        service = harness.PgBackRest(self.spec, runner)
        self.assertEqual(service.info().stanza, "ivorysql")

    def test_preflight_reports_unsafe_choices(self) -> None:
        env = valid_env(
            BACKUP_CIPHER_TYPE="none",
            BACKUP_REQUIRE_ENCRYPTION="false",
            BACKUP_REPO_PATH="/tmp/backups",
        )
        del env["BACKUP_CIPHER_PASS"]
        result = harness.preflight(harness.RuntimeSpec.from_env(env))
        self.assertEqual(len(result["warnings"]), 3)

    def test_restore_requires_yes_without_tty(self) -> None:
        with mock.patch.object(harness.sys.stdin, "isatty", return_value=False):
            with self.assertRaisesRegex(harness.ConfigurationError, "requires --yes"):
                harness.require_confirmation("restore", assume_yes=False)

    def test_preflight_cli_output(self) -> None:
        args = harness.build_parser().parse_args(["--json", "preflight"])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(harness.execute(args, self.spec), 0)
        parsed = json.loads(output.getvalue())
        self.assertEqual(parsed["repository_type"], "posix")

    def test_restore_dry_run_does_not_execute_command(self) -> None:
        args = harness.build_parser().parse_args(
            ["restore", "--type", "lsn", "--target", "0/16B6C50", "--dry-run"]
        )
        runner = FakeRunner([])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            harness.execute(args, self.spec, runner)
        self.assertEqual(runner.calls, [])
        self.assertTrue(json.loads(output.getvalue())["destructive"])

    def test_main_returns_two_for_invalid_environment(self) -> None:
        stderr = io.StringIO()
        with mock.patch.dict(os.environ, valid_env(BACKUP_STANZA="bad stanza"), clear=True):
            with contextlib.redirect_stderr(stderr):
                result = harness.main(["preflight"])
        self.assertEqual(result, 2)
        self.assertIn("unsafe", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
