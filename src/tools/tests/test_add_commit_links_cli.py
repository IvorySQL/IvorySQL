"""Exercise the complete release-link CLI with genuine git_changelog output."""

from __future__ import annotations

import datetime
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Dict, List, Optional


SOURCE_ROOT = Path(
    os.environ.get("IVORYSQL_SOURCE_ROOT", Path(__file__).resolve().parents[3])
)
CASES = json.loads(
    Path(__file__).with_name("add_commit_links_cases.json").read_text(encoding="utf-8")
)


def executable(variable: str, name: str, windows_path: str) -> Path:
    """Resolve an existing real executable; never install or substitute it."""
    requested = os.environ.get(variable)
    if requested:
        resolved = shutil.which(requested) or requested
    else:
        resolved = shutil.which(name)
        if resolved is None and os.name == "nt":
            resolved = windows_path
    if resolved is None:
        raise RuntimeError(f"Set {variable} to the existing {name} executable")
    path = Path(resolved).resolve()
    if not path.is_file():
        raise RuntimeError(f"{variable} is not an existing executable: {path}")
    return path


class CommitLinksCliTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.git = executable("GIT_EXECUTABLE", "git", "D:/Git/cmd/git.exe")
        cls.perl = executable("PERL_EXECUTABLE", "perl", "D:/Git/usr/bin/perl.exe")
        cls.source_tools = SOURCE_ROOT / "src" / "tools"
        for name in ("git_changelog", "add_commit_links.pl"):
            if not (cls.source_tools / name).is_file():
                raise RuntimeError(
                    f"Missing complete source: {cls.source_tools / name}"
                )
        declaration = re.search(
            r"my @BRANCHES = qw\((.*?)\);",
            (cls.source_tools / "git_changelog").read_text(encoding="utf-8"),
            flags=re.DOTALL,
        )
        if declaration is None:
            raise RuntimeError("Cannot read the actual producer's branch configuration")
        cls.branches = declaration.group(1).split()
        if "master" not in cls.branches or "REL_18_STABLE" not in cls.branches:
            raise RuntimeError("This fixture requires the published master/18 branches")

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="commit-links-")
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        tools = self.repo / "src" / "tools"
        tools.mkdir(parents=True)
        for name in ("git_changelog", "add_commit_links.pl"):
            shutil.copy2(self.source_tools / name, tools / name)

        # Keep real Git entirely inside the temporary repository.
        self.environment = {
            key: value
            for key, value in os.environ.items()
            if not key.upper().startswith("GIT_")
        }
        path_key = next(
            (key for key in self.environment if key.upper() == "PATH"), "PATH"
        )
        self.environment[path_key] = (
            str(self.git.parent) + os.pathsep + self.environment.get(path_key, "")
        )
        self.environment.update(
            {
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": os.devnull,
                "GIT_TERMINAL_PROMPT": "0",
                "GIT_AUTHOR_NAME": "Release CLI fixture",
                "GIT_AUTHOR_EMAIL": "release-cli@example.invalid",
                "GIT_COMMITTER_NAME": "Release CLI fixture",
                "GIT_COMMITTER_EMAIL": "release-cli@example.invalid",
                "LC_ALL": "C",
                "TZ": "UTC",
            }
        )
        self.invoke([str(self.git), "init", "-q"])
        self.invoke([str(self.git), "symbolic-ref", "HEAD", "refs/heads/master"])

    def invoke(
        self,
        arguments: List[str],
        *,
        input_text: Optional[str] = None,
        environment: Optional[Dict[str, str]] = None,
    ) -> str:
        result = subprocess.run(
            arguments,
            cwd=self.repo,
            env=self.environment if environment is None else environment,
            input=None if input_text is None else input_text.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=90,
        )
        stdout = result.stdout.decode("utf-8", errors="strict")
        stderr = result.stderr.decode("utf-8", errors="strict")
        self.assertEqual(
            result.returncode,
            0,
            f"Real CLI setup/execution failed: {arguments}\n"
            f"stdout:\n{stdout}\nstderr:\n{stderr}",
        )
        return stdout

    def commit(
        self, tree: str, message: str, date: str, parent: Optional[str] = None
    ) -> str:
        environment = self.environment.copy()
        environment["GIT_AUTHOR_DATE"] = date
        environment["GIT_COMMITTER_DATE"] = date
        arguments = [str(self.git), "commit-tree", tree]
        if parent is not None:
            arguments.extend(["-p", parent])
        return self.invoke(
            arguments, input_text=message + "\n", environment=environment
        ).strip()

    def make_history(self, case: str, *, backport: bool = False) -> Dict[str, str]:
        record = CASES[case]
        tree = self.invoke([str(self.git), "mktree"], input_text="").strip()
        base = self.commit(
            tree, "Private regression repository base", "2010-01-01T00:00:00+0000"
        )
        current = self.commit(tree, record["message"], record["date"], parent=base)
        revisions = {"master": current}
        refs = [
            f"update refs/remotes/origin/{branch} {base}"
            for branch in self.branches
            if branch != "master"
        ]
        refs.extend(
            [
                f"update refs/heads/master {current}",
                f"update refs/remotes/origin/master {current}",
            ]
        )
        self.invoke(
            [str(self.git), "update-ref", "--stdin"],
            input_text="\n".join(refs) + "\n",
        )
        if backport:
            later = datetime.datetime.fromisoformat(
                record["date"].replace("Z", "+00:00")
            ) + datetime.timedelta(seconds=30)
            stable = self.commit(
                tree,
                record["message"],
                later.strftime("%Y-%m-%dT%H:%M:%S%z"),
                parent=base,
            )
            self.invoke(
                [
                    str(self.git),
                    "update-ref",
                    "refs/remotes/origin/REL_18_STABLE",
                    stable,
                ]
            )
            self.invoke([str(self.git), "tag", "REL_18_1", stable])
            revisions["stable"] = stable
        return revisions

    def changelog(self, *options: str) -> str:
        return self.invoke(
            [
                str(self.perl),
                "src/tools/git_changelog",
                "--since=2017-01-05T00:00:00+0000",
                *options,
            ]
        )

    def write_note(self, transcript: str, version: int = 19) -> Path:
        path = self.repo / f"release-{version}.sgml"
        text = (
            f'<sect1 id="release-{version}">\n<title>Release {version}</title>\n'
            "<itemizedlist>\n<!--\n"
            + transcript.rstrip("\n")
            + "\n-->\n<listitem>\n<para>\n"
            "Release entry (Release CLI fixture)\n"
            "</para>\n</listitem>\n</itemizedlist>\n</sect1>\n"
        )
        path.write_bytes(text.encode("utf-8"))
        return path

    def add_links(self, path: Path) -> str:
        self.invoke([str(self.perl), "src/tools/add_commit_links.pl", path.name])
        self.assertFalse(path.with_name(path.name + ".tmp").exists())
        return path.read_text(encoding="utf-8")

    def assert_links(self, text: str, expected: List[str]) -> None:
        actual = re.findall(
            r'<ulink url="&commit_baseurl;([0-9a-f]+)">&sect;</ulink>',
            text,
        )
        self.assertEqual(actual, [revision[:9] for revision in expected])

    def test_brief_major_output_does_not_link_an_array_subscript(self) -> None:
        revisions = self.make_history("array")
        transcript = self.changelog("--master-only", "--brief")
        self.assertIn("array[0]", transcript, "retain the real commit message")
        note = self.write_note(transcript)
        result = self.add_links(note)
        self.assert_links(result, [revisions["master"]])
        self.assertIn("array[0]", result)

    def test_full_master_output_keeps_only_its_annotation_hash(self) -> None:
        revisions = self.make_history("array")
        transcript = self.changelog("--master-only")
        self.assertIn("array[0]", transcript)
        self.assertNotIn("Branch:", transcript)
        result = self.add_links(self.write_note(transcript))
        self.assert_links(result, [revisions["master"]])

    def test_full_minor_output_selects_the_matching_branch_only(self) -> None:
        revisions = self.make_history("array", backport=True)
        transcript = self.changelog()
        self.assertIn("Branch: master ", transcript)
        self.assertIn("Branch: REL_18_STABLE Release: REL_18_1 ", transcript)
        self.assertIn("array[0]", transcript)
        result = self.add_links(self.write_note(transcript, version=18))
        self.assert_links(result, [revisions["stable"]])

    def test_plain_real_commit_links_remain_idempotent_control(self) -> None:
        revisions = self.make_history("plain")
        transcript = self.changelog("--master-only", "--brief", "--details-after")
        note = self.write_note(transcript)
        first = self.add_links(note)
        self.assert_links(first, [revisions["master"]])
        second = self.add_links(note)
        self.assertEqual(second, first)
        self.assert_links(second, [revisions["master"]])


if __name__ == "__main__":
    unittest.main()
