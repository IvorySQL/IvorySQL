"""Check branch selection in the actual pg-ci.yml concurrency condition."""

from pathlib import Path
import re
import unittest


class ConcurrencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow = Path(__file__).resolve().parents[3] / ".github/workflows/pg-ci.yml"
        text = workflow.read_text(encoding="utf-8")
        condition = re.search(r"case\((.*?),\s*github\.run_id,", text, re.S).group(1)
        # Translate this condition's Actions operators to Python. Evaluate the
        # workflow condition itself so changing a branch prefix breaks the test.
        cls.condition = condition.replace("github.ref", "ref").replace(
            "||", " or ").replace("&&", " and ").strip()

    def unique_group(self, ref):
        return eval("(" + self.condition + ")", {"__builtins__": {}}, {
            "ref": ref,
            "startsWith": lambda value, prefix: value.lower().startswith(prefix.lower()),
            "endsWith": lambda value, suffix: value.lower().endswith(suffix.lower()),
        })

    def test_ivorysql_release_branches_keep_each_run(self):
        for branch in ["IVORY_REL_4_STABLE", "IVORY_REL_5_STABLE",
                       "IVORY_REL_6_STABLE", "IVORYSQL_REL_1_STABLE"]:
            with self.subTest(branch=branch):
                self.assertTrue(self.unique_group("refs/heads/" + branch))

    def test_existing_master_and_postgres_stable_behavior(self):
        for branch in ["master", "REL_14_STABLE", "REL_18_STABLE"]:
            with self.subTest(branch=branch):
                self.assertTrue(self.unique_group("refs/heads/" + branch))

    def test_development_branches_share_the_ref_group(self):
        for branch in ["feature", "IVORY_REL_6_feature", "IVORYSQL_REL_1_PERF",
                       "feature_STABLE", "IVORY_REL_6_STABLE-fix"]:
            with self.subTest(branch=branch):
                self.assertFalse(self.unique_group("refs/heads/" + branch))

    def test_tags_and_pull_refs_are_not_release_branch_pushes(self):
        for ref in ["refs/tags/IVORY_REL_6_STABLE", "refs/pull/123/merge"]:
            with self.subTest(ref=ref):
                self.assertFalse(self.unique_group(ref))


if __name__ == "__main__":
    unittest.main()
