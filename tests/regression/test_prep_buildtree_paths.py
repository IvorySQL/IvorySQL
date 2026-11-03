#!/usr/bin/env python3
"""Exercise the whole configure build-tree helper with real shell/FS tools.

PREP_BUILDTREE_SCRIPT selects a baseline or candidate complete script.
PREP_SOURCE_ROOT selects a real repository/input tree for the five Makefiles.
PREP_SHELL selects an existing POSIX shell, e.g. D:/Git/bin/bash.exe.
"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(
    os.environ.get("PREP_BUILDTREE_SCRIPT", str(ROOT / "config/prep_buildtree"))
).resolve()
SOURCE_ROOT = Path(os.environ.get("PREP_SOURCE_ROOT", str(ROOT))).resolve()
SHELL = os.environ.get("PREP_SHELL", "sh")
INPUTS = (
    Path("Makefile"),
    Path("config/Makefile"),
    Path("contrib/Makefile"),
    Path("doc/Makefile"),
    Path("src/Makefile"),
)


class PrepBuildtreePaths(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="prep-cli-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        if any(character.isspace() for character in self.root.as_posix()):
            self.skipTest("Use a private TMP without whitespace to isolate this root")

    def run_source_tree(self, source_name):
        source = self.root / source_name
        build = self.root / "build"
        build.mkdir()
        originals = {}
        for relative in INPUTS:
            data = (SOURCE_ROOT / relative).read_bytes()
            source_file = source / relative
            source_file.parent.mkdir(parents=True, exist_ok=True)
            source_file.write_bytes(data)
            originals[relative] = data
        completed = subprocess.run(
            [SHELL, SCRIPT.as_posix(), source_name, "build"],
            cwd=self.root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        self.assertEqual(
            completed.returncode,
            0,
            completed.stderr.decode("utf-8", errors="replace"),
        )
        for relative, expected in originals.items():
            with self.subTest(path=relative.as_posix()):
                target = build / relative
                self.assertTrue(target.is_file(), "Missing build path: " + str(target))
                self.assertEqual(target.read_bytes(), expected)
                self.assertEqual((source / relative).read_bytes(), expected)
        self.assertFalse((build / "0").exists(), "Regex no-match became a build path")
        self.assertEqual(completed.stderr, b"")

    def test_bracketed_source_directory(self):
        self.run_source_tree("source[1]")

    def test_plain_source_directory_control(self):
        self.run_source_tree("source")


if __name__ == "__main__":
    unittest.main()
