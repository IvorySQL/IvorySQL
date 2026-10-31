"""Full git_changelog CLI against real Git history and color configuration."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SOURCE_ROOT = Path(
    os.environ.get("IVORY_SOURCE_ROOT", Path(__file__).resolve().parents[1])
)
SCRIPT = SOURCE_ROOT / "src/tools/git_changelog"
PERL = os.environ.get("PERL", "perl")
GIT = os.environ.get("GIT", "git")

# Historical origin refs expected by the published maintenance CLI. Each is a
# genuine Git ref in this fixture; there is no replacement Git executable.
BRANCHES = """
master REL_18_STABLE REL_17_STABLE REL_16_STABLE REL_15_STABLE REL_14_STABLE
REL_13_STABLE REL_12_STABLE REL_11_STABLE REL_10_STABLE
REL9_6_STABLE REL9_5_STABLE REL9_4_STABLE REL9_3_STABLE REL9_2_STABLE
REL9_1_STABLE REL9_0_STABLE REL8_4_STABLE REL8_3_STABLE REL8_2_STABLE
REL8_1_STABLE REL8_0_STABLE REL7_4_STABLE REL7_3_STABLE REL7_2_STABLE
REL7_1_STABLE REL7_0_PATCHES REL6_5_PATCHES REL6_4
""".split()


@unittest.skipUnless(
    shutil.which(PERL) and shutil.which(GIT), "requires genuine Perl and Git"
)
class GitChangelogColorCliTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="git-changelog-color-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment = dict(
            os.environ,
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_AUTHOR_NAME="Changelog Fixture",
            GIT_AUTHOR_EMAIL="fixture@example.invalid",
            GIT_COMMITTER_NAME="Changelog Fixture",
            GIT_COMMITTER_EMAIL="fixture@example.invalid",
            GIT_AUTHOR_DATE="2026-01-02T03:04:05+0000",
            GIT_COMMITTER_DATE="2026-01-02T03:04:05+0000",
            GIT_TERMINAL_PROMPT="0",
        )
        self.git("-c", "init.defaultBranch=master", "init", "--quiet")
        (self.root / "release.txt").write_text(
            "real changelog commit\n", encoding="utf-8"
        )
        self.git("add", "release.txt")
        self.git("commit", "--quiet", "-m", "Preserve release changelog fixture")
        self.commit = self.git("rev-parse", "HEAD").stdout.strip()
        updates = "".join(
            "create refs/remotes/origin/" + branch + " " + self.commit + "\n"
            for branch in BRANCHES
        )
        self.git("update-ref", "--stdin", input=updates)

    def git(self, *arguments, input=None):
        result = subprocess.run(
            [GIT, *arguments],
            cwd=self.root,
            env=self.environment,
            input=input.encode("utf-8") if input is not None else None,
            capture_output=True,
            check=True,
            timeout=30,
        )
        result.stdout = result.stdout.decode("utf-8")
        result.stderr = result.stderr.decode("utf-8")
        return result

    def run_changelog(self):
        return subprocess.run(
            [PERL, str(SCRIPT), "--master-only", "--brief"],
            cwd=self.root,
            env=self.environment,
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
            timeout=60,
        )

    def assert_changelog(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Preserve release changelog fixture", result.stdout)
        self.assertIn("[" + self.commit[:9] + "]", result.stdout)
        self.assertIn("2026-01-02", result.stdout)
        self.assertNotIn("\x1b[", result.stdout)

    def test_forced_git_color_still_produces_complete_changelog(self):
        self.git("config", "color.ui", "always")
        # Establish that the genuine producer really emits color in this host;
        # this output is never injected into or substituted for the product.
        producer = self.git("log", "--format=fuller", "--date=iso", "origin/master")
        self.assertIn("\x1b[", producer.stdout)
        self.assert_changelog(self.run_changelog())

    def test_noncolored_git_history_control(self):
        self.git("config", "color.ui", "never")
        self.assert_changelog(self.run_changelog())


if __name__ == "__main__":
    unittest.main()
