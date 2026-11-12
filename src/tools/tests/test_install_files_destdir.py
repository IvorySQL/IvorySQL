"""Exercise the complete install_files CLI with real private files and directories."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SOURCE_ROOT = Path(
    os.environ.get("IVORY_SOURCE_ROOT", Path(__file__).resolve().parents[3])
).resolve()
SCRIPT = SOURCE_ROOT / "src/tools/install_files"


class InstallFilesDestdirCliTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="ivory-install-destdir-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.cwd = self.root / "working directory"
        self.cwd.mkdir()
        self.prefix = self.root / "install prefix"
        self.stage = self.root / "staging directory"
        inputs = self.root / "input files"
        inputs.mkdir()
        self.control = inputs / "fixture.control"
        self.control.write_bytes(b"default_version = '1.0'\n")
        self.man = inputs / "man1"
        self.man.mkdir()
        (self.man / "fixture.1").write_bytes(b".TH FIXTURE 1\n.SH NAME\nfixture\n")
        self.html = inputs / "html"
        self.html.mkdir()
        (self.html / "index.html").write_bytes(
            b"<!doctype html><title>Fixture</title>\n"
        )
        (self.html / "images").mkdir()
        (self.html / "images" / "fixture.bin").write_bytes(b"\x00\x01\xfe\xff")

    def install(self, *arguments, destdir=None, cli_destdir=None):
        environment = os.environ.copy()
        environment.pop("DESTDIR", None)
        if destdir is not None:
            environment["DESTDIR"] = str(destdir)
        command = [sys.executable, str(SCRIPT), "--prefix", str(self.prefix)]
        if cli_destdir is not None:
            command += ["--destdir", str(cli_destdir)]
        result = subprocess.run(
            command + [str(argument) for argument in arguments],
            cwd=self.cwd,
            env=environment,
            capture_output=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            0,
            (result.stdout + result.stderr).decode("utf-8", errors="replace"),
        )

    def assert_file_at(self, prefix):
        installed = prefix / "share" / "extension" / self.control.name
        self.assertTrue(
            installed.is_file(), "missing installed file: " + str(installed)
        )
        self.assertEqual(installed.read_bytes(), self.control.read_bytes())

    def assert_man_at(self, prefix):
        installed = prefix / "share" / "man" / "man1" / "fixture.1"
        self.assertTrue(
            installed.is_file(), "missing installed man page: " + str(installed)
        )
        self.assertEqual(installed.read_bytes(), (self.man / "fixture.1").read_bytes())

    def assert_html_at(self, prefix):
        target = prefix / "share" / "doc" / "html"
        installed = target / "index.html"
        self.assertTrue(
            installed.is_file(), "missing installed HTML: " + str(installed)
        )
        self.assertEqual(
            installed.read_bytes(), (self.html / "index.html").read_bytes()
        )
        self.assertEqual(
            (target / "images" / "fixture.bin").read_bytes(),
            (self.html / "images" / "fixture.bin").read_bytes(),
        )
        self.assertFalse((target / "html").exists())

    def all_install_arguments(self):
        return [
            "--install",
            "share/extension",
            self.control,
            "--install-dirs",
            "share/man",
            self.man,
            "--install-dir-contents",
            "share/doc/html",
            self.html,
        ]

    def test_empty_environment_destdir_installs_files_under_prefix(self):
        self.install("--install", "share/extension", self.control, destdir="")
        self.assert_file_at(self.prefix)

    def test_empty_cli_destdir_overrides_inherited_staging(self):
        self.install(
            "--install",
            self.prefix / "share" / "extension",
            self.control,
            destdir=self.stage,
            cli_destdir="",
        )
        self.assert_file_at(self.prefix)
        self.assertFalse(self.stage.exists())

    def test_empty_destdir_preserves_man_directory_destination(self):
        self.install("--install-dirs", "share/man", self.man, destdir="")
        self.assert_man_at(self.prefix)

    def test_empty_destdir_preserves_html_contents_destination(self):
        self.install("--install-dir-contents", "share/doc/html", self.html, destdir="")
        self.assert_html_at(self.prefix)

    def test_unset_destdir_control_for_all_copy_modes(self):
        self.install(*self.all_install_arguments())
        self.assert_file_at(self.prefix)
        self.assert_man_at(self.prefix)
        self.assert_html_at(self.prefix)

    def test_nonempty_destdir_control_for_all_copy_modes(self):
        self.install(*self.all_install_arguments(), destdir=self.stage)
        staged_prefix = self.stage / self.prefix.relative_to(self.prefix.anchor)
        self.assert_file_at(staged_prefix)
        self.assert_man_at(staged_prefix)
        self.assert_html_at(staged_prefix)
        self.assertFalse(self.prefix.exists())


if __name__ == "__main__":
    unittest.main()
