#!/usr/bin/env python3
"""Run the complete Perl documentation generator against official input files.

KEYWORD_TABLE_SCRIPT selects the unchanged baseline or isolated candidate.
KEYWORD_SOURCE_ROOT selects a complete repository/input tree (default: repo root).
PERL selects an existing Perl executable; no replacement modules/tools are used.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]
SOURCE = Path(
    os.environ.get(
        "KEYWORD_TABLE_SCRIPT",
        str(REPO_ROOT / "doc/src/sgml/generate-keywords-table.pl"),
    )
).resolve()
SOURCE_ROOT = Path(os.environ.get("KEYWORD_SOURCE_ROOT", str(REPO_ROOT))).resolve()
SQL_KEYWORD_FILES = (
    "sql1992-nonreserved.txt",
    "sql1992-reserved.txt",
    "sql2016-02-nonreserved.txt",
    "sql2016-02-reserved.txt",
    "sql2016-09-nonreserved.txt",
    "sql2016-09-reserved.txt",
    "sql2016-14-nonreserved.txt",
    "sql2016-14-reserved.txt",
    "sql2023-02-nonreserved.txt",
    "sql2023-02-reserved.txt",
    "sql2023-09-nonreserved.txt",
    "sql2023-09-reserved.txt",
    "sql2023-14-nonreserved.txt",
    "sql2023-14-reserved.txt",
    "sql2023-16-nonreserved.txt",
    "sql2023-16-reserved.txt",
)
INPUT_PATHS = tuple(
    Path("doc/src/sgml/keywords") / name for name in SQL_KEYWORD_FILES
) + (Path("src/include/parser/kwlist.h"), Path("COPYRIGHT"))
PERL = os.environ.get("PERL", "perl")


class KeywordSourcePaths(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="keyword-cli-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()

    def stage(self, name):
        destination = self.root / name
        for relative_path in INPUT_PATHS:
            target = destination / relative_path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SOURCE_ROOT / relative_path, target)
        return destination / "doc/src/sgml"

    def generate(self, source_directory):
        completed = subprocess.run(
            [PERL, SOURCE.as_posix(), source_directory.as_posix()],
            cwd=self.root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        self.assertEqual(
            completed.returncode,
            0,
            "Complete generator failed: "
            + completed.stderr.decode("utf-8", errors="replace"),
        )
        self.assertEqual(completed.stderr, b"")
        return completed.stdout

    def assert_table(self, output):
        # ABS is a real SQL standard keyword absent from the PG keyword list.
        self.assertIn(b"<entry><token>ABS</token></entry>", output)
        self.assertIn(b"<entry><token>SELECT</token></entry>", output)
        self.assertIn(b"<entry>SQL:2023</entry>", output)
        self.assertTrue(output.endswith(b"</table>\n"))

    def test_plain_relative_source_control(self):
        self.stage("plain")
        output = self.generate(Path("plain/doc/src/sgml"))
        self.assert_table(output)

    def test_relative_checkout_with_spaces(self):
        self.stage("plain")
        self.stage("source checkout")
        expected = self.generate(Path("plain/doc/src/sgml"))
        self.assert_table(expected)
        actual = self.generate(Path("source checkout/doc/src/sgml"))
        self.assert_table(actual)
        self.assertEqual(actual, expected)

    def test_absolute_checkout_with_spaces(self):
        self.stage("plain")
        spaced_source = self.stage("source checkout")
        expected = self.generate(Path("plain/doc/src/sgml"))
        self.assert_table(expected)
        actual = self.generate(spaced_source)
        self.assert_table(actual)
        self.assertEqual(actual, expected)


if __name__ == "__main__":
    unittest.main()
