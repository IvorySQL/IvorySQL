"""Regression tests for the Cirrus formatting driver (no build required)."""

import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import check_format


class FormatCheckTests(unittest.TestCase):
    def test_real_git_diff_selects_only_surviving_sources(self):
        with tempfile.TemporaryDirectory(prefix="format check ") as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args],
                                               stderr=subprocess.PIPE).decode().strip()

            git("init", "-q")
            git("config", "core.hooksPath", str(root / "no-hooks"))
            git("config", "user.name", "Format test")
            git("config", "user.email", "test@example.invalid")
            for name in ["removed.c", "before.h", "changed.cpp"]:
                (root / name).write_text("old\n")
            git("add", ".")
            git("commit", "-qm", "base")
            base = git("rev-parse", "HEAD")
            (root / "removed.c").unlink()
            (root / "before.h").rename(root / "after rename.h")
            (root / "changed.cpp").write_text("new\n")
            (root / "space name.c").write_text("new\n")
            (root / "UPPER.HPP").write_text("new\n")
            (root / "notes.md").write_text("new\n")
            excluded = root / "src/tools/pg_bsd_indent/ignored.c"
            excluded.parent.mkdir(parents=True)
            excluded.write_text("new\n")
            git("add", "-A")
            git("commit", "-qm", "changes")
            original = subprocess.check_output

            def in_repository(args):
                return original(["git", "-C", directory, *args[1:]])

            with patch.object(check_format.subprocess, "check_output", in_repository):
                self.assertEqual(set(check_format.changed_files(base)), {
                    "after rename.h", "changed.cpp", "space name.c", "UPPER.HPP",
                })

    def test_nul_paths_are_not_split_or_git_unquoted(self):
        paths = b'space name.c\0tab\tname.h\0line\nname.cpp\0quote"name.hpp\0'
        with patch.object(check_format.subprocess, "check_output", return_value=paths):
            self.assertEqual(check_format.changed_files("base"), [
                'space name.c', 'tab\tname.h', 'line\nname.cpp', 'quote"name.hpp',
            ])

    def test_git_errors_are_not_reported_as_no_changes(self):
        with patch.object(check_format.subprocess, "check_output",
                          side_effect=subprocess.CalledProcessError(128, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                check_format.changed_files("invalid")

    def test_no_sources_skips_formatter(self):
        with patch.object(check_format, "changed_files", return_value=[]), \
             patch.object(check_format.subprocess, "call") as formatter:
            self.assertEqual(check_format.main("base"), 0)
            formatter.assert_not_called()

    def test_success_preserves_each_literal_argument(self):
        paths = ["space name.c", "-option.h", "glob[1].cpp"]
        with patch.object(check_format, "changed_files", return_value=paths), \
             patch.object(check_format.subprocess, "call", return_value=0) as formatter:
            self.assertEqual(check_format.main("base"), 0)
            formatter.assert_called_once_with([
                "./src/tools/pgindent/pgindent", "--check",
                "./space name.c", "./-option.h", "./glob[1].cpp",
            ])

    def test_failure_prints_diff_and_preserves_check_status(self):
        with patch.object(check_format, "changed_files", return_value=["file.c"]), \
             patch.object(check_format.subprocess, "call", side_effect=[2, 1]) as formatter:
            self.assertEqual(check_format.main("base"), 2)
            self.assertEqual(formatter.call_args_list[1].args[0], [
                "./src/tools/pgindent/pgindent", "--diff", "./file.c",
            ])


if __name__ == "__main__":
    with contextlib.redirect_stdout(io.StringIO()):
        unittest.main()
