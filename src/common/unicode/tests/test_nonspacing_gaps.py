"""Run the full Perl generator against an unchanged Unicode 17 data excerpt."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


SOURCE_ROOT = Path(
    os.environ.get("IVORY_SOURCE_ROOT", Path(__file__).resolve().parents[4])
).resolve()
GENERATOR = SOURCE_ROOT / "src/common/unicode/generate-unicode_nonspacing_table.pl"
FIXTURE = Path(__file__).resolve().parent / "fixtures/UnicodeData-17.0.0-tags.txt"
PERL = os.environ.get("PERL_EXECUTABLE", "perl")


@unittest.skipUnless(shutil.which(PERL), "requires genuine Perl")
class NonspacingGapsCliTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not GENERATOR.is_file():
            raise RuntimeError("missing complete generator: " + str(GENERATOR))
        with tempfile.TemporaryDirectory(prefix="unicode-nonspacing-") as temporary:
            work = Path(temporary).resolve()
            data = work / "UnicodeData.txt"
            data.write_bytes(FIXTURE.read_bytes())
            result = subprocess.run(
                [PERL, str(GENERATOR), str(data)],
                cwd=work,
                capture_output=True,
                check=False,
                timeout=30,
            )
        if result.returncode != 0:
            raise RuntimeError(
                "generator failed before output assertions: "
                + result.stderr.decode("utf-8", errors="replace")
            )
        output = result.stdout.decode("ascii")
        cls.intervals = [
            (int(first, 16), int(last, 16))
            for first, last in re.findall(r"\{0x([0-9A-F]+), 0x([0-9A-F]+)\}", output)
        ]
        if not cls.intervals:
            raise RuntimeError("generator emitted no C intervals: " + output)

    def includes(self, codepoint):
        return any(first <= codepoint <= last for first, last in self.intervals)

    def test_unassigned_gap_after_language_tag_is_excluded(self):
        unexpected = [
            codepoint
            for codepoint in (0xE0002, 0xE0010, 0xE001F)
            if self.includes(codepoint)
        ]
        self.assertEqual(unexpected, [], "unassigned code points became nonspacing")

    def test_unassigned_gap_before_variation_selectors_is_excluded(self):
        unexpected = [
            codepoint
            for codepoint in (0xE0080, 0xE00A0, 0xE00FF)
            if self.includes(codepoint)
        ]
        self.assertEqual(unexpected, [], "unassigned code points became nonspacing")

    def test_assigned_format_and_nonspacing_marks_control(self):
        for codepoint in (0xE0001, 0xE0020, 0xE0041, 0xE007F, 0xE0100, 0xE01EF):
            with self.subTest(codepoint=hex(codepoint)):
                self.assertTrue(self.includes(codepoint))

    def test_private_use_rows_still_close_the_nonspacing_range_control(self):
        for codepoint in (0xF0000, 0xFFFFD, 0x100000, 0x10FFFD):
            with self.subTest(codepoint=hex(codepoint)):
                self.assertFalse(self.includes(codepoint))


if __name__ == "__main__":
    unittest.main()
