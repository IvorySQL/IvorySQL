"""Check unused_oids suggestions against unchanged shipped catalog inputs."""

import hashlib
import os
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(
    os.environ.get("IVORY_SOURCE_ROOT", Path(__file__).resolve().parents[2])
).resolve()
PERL = os.environ.get("IVORY_PERL", "perl")
PRELUDE = (
    "srand shift @ARGV; "
    "my $script = shift @ARGV; "
    "$0 = $script; "
    "my $result = do $script; "
    "die $@ if $@; "
    'die "$script: $!" unless defined $result;'
)
SUGGESTION = re.compile(
    r"Suggested random unused OID: (\d+) "
    r"\((\d+) consecutive OID\(s\) available starting here\)"
)
RANGE = re.compile(r"^(\d+)(?: - (\d+))?$", re.MULTILINE)


class UnusedOidReservedRegression(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = ROOT / "src/include/catalog"
        cls.script = cls.catalog / "unused_oids"
        constants = ROOT / "src/include/access/transam.h"
        module = ROOT / "src/backend/catalog/Catalog.pm"
        for path in (cls.script, constants, module):
            if not path.is_file():
                raise RuntimeError(f"Complete source prerequisite missing: {path}")
        text = constants.read_text(encoding="utf-8")
        cls.minimum = cls.read_constant(text, "MinTypeObjectId")
        cls.maximum = cls.read_constant(text, "MaxTypeObjectId")
        cls.inputs = sorted(cls.catalog.glob("pg_*.h"))
        cls.inputs += sorted(cls.catalog.glob("pg_*.dat"))
        cls.inputs += [constants, module, cls.script]
        cls.original = cls.fingerprints()
        cls.samples = {}
        # Seed the interpreter, then execute the complete script without changing
        # its text, Catalog implementation, random function or catalog inputs.
        for seed in range(64):
            result = subprocess.run(
                [PERL, "-e", PRELUDE, str(seed), cls.script.as_posix()],
                cwd=cls.catalog,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
                check=False,
            )
            if result.returncode != 0:
                raise RuntimeError(
                    result.stderr.decode("utf-8", errors="replace")
                )
            output = result.stdout.decode("utf-8")
            match = SUGGESTION.search(output)
            if match is None:
                raise RuntimeError(f"Missing suggestion in real CLI output: {output}")
            suggestion, available = map(int, match.groups())
            intervals = [
                (int(first), int(last or first))
                for first, last in RANGE.findall(output)
            ]
            containing = [
                pair for pair in intervals if pair[0] <= suggestion <= pair[1]
            ]
            if len(containing) != 1:
                raise RuntimeError(
                    f"Suggestion {suggestion} not in exactly one printed free range"
                )
            sample = (suggestion, available, intervals, containing[0], seed)
            if suggestion < cls.minimum and containing[0][1] == cls.minimum - 1:
                cls.samples.setdefault("before", sample)
            if suggestion > cls.maximum:
                cls.samples.setdefault("after", sample)
            if set(cls.samples) == {"before", "after"}:
                break
        if set(cls.samples) != {"before", "after"}:
            raise RuntimeError(
                "The shipped data/runtime did not supply both target and control "
                "suggestions in 64 fixed seeds; no synthetic data was substituted"
            )
        if cls.fingerprints() != cls.original:
            raise RuntimeError("CLI modified its source or catalog inputs")

    @staticmethod
    def read_constant(text: str, name: str) -> int:
        match = re.search(rf"^#define\s+{name}\s+(\d+)\b", text, re.MULTILINE)
        if match is None:
            raise RuntimeError(f"Missing numeric constant {name}")
        return int(match.group(1))

    @classmethod
    def fingerprints(cls) -> dict:
        return {
            str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in cls.inputs
        }

    def test_count_stops_before_reserved_types(self) -> None:
        suggestion, available, _, interval, seed = self.samples["before"]
        self.assertEqual(interval[1], self.minimum - 1)
        self.assertEqual(
            available,
            interval[1] - suggestion + 1,
            f"seed {seed}, suggestion {suggestion}: reported block crosses reserved types",
        )

    def test_after_reserved_count_retains_printed_gap(self) -> None:
        suggestion, available, _, interval, seed = self.samples["after"]
        self.assertGreater(suggestion, self.maximum)
        self.assertEqual(
            available, interval[1] - suggestion + 1, f"control seed {seed}"
        )

    def test_ranges_and_suggestions_exclude_reserved_types(self) -> None:
        for name, sample in self.samples.items():
            suggestion, available, intervals, _, seed = sample
            with self.subTest(sample=name, seed=seed):
                self.assertTrue(8000 <= suggestion <= 9999)
                self.assertTrue(
                    suggestion < self.minimum or suggestion > self.maximum
                )
                self.assertGreater(available, 0)
                for first, last in intervals:
                    self.assertTrue(
                        last < self.minimum or first > self.maximum,
                        f"printed range {first}-{last} overlaps reserved types",
                    )
        self.assertEqual(self.fingerprints(), self.original)


if __name__ == "__main__":
    unittest.main()
