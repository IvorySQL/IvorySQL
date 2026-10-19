#!/usr/bin/env python3
"""Check pgperlsyncheck's exit status with real Perl and xargs.

Run: python3 src/tools/perlcheck/t/test_pgperlsyncheck.py [script [finder]]
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else (
    Path(__file__).resolve().parents[1] / 'pgperlsyncheck')
FINDER = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else (
    SCRIPT.parent / 'find_perl_files')


class SyntaxCheckStatus(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        finder_dir = self.root / 'src/tools/perlcheck'
        finder_dir.mkdir(parents=True)
        shutil.copyfile(FINDER, finder_dir / 'find_perl_files')

    def invoke(self, sources):
        paths = []
        for name, contents in sources:
            path = self.root / name
            path.write_text(contents)
            paths.append(str(path))
        return subprocess.run(['sh', str(SCRIPT), *paths], cwd=self.root,
                              text=True, capture_output=True, check=False)

    def test_success_is_silent_and_zero(self):
        result = self.invoke([('good.pl', 'use strict; print "ok";\n')])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertEqual(result.stderr, '')

    def test_multiple_successful_files(self):
        result = self.invoke([('one.pl', 'use strict; 1;\n'),
                              ('two.pm', 'package Two; use warnings; 1;\n')])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertEqual(result.stderr, '')

    def test_syntax_error_returns_failure(self):
        result = self.invoke([('bad.pl', 'use strict; my $x = ;\n')])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('syntax error', result.stdout)
        self.assertIn('had compilation errors', result.stdout)

    def test_mixed_inputs_return_failure(self):
        result = self.invoke([('a_good.pl', 'use strict; 1;\n'),
                              ('b_bad.pl', 'use strict; my $x = ;\n')])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('syntax error', result.stdout)
        self.assertNotIn('syntax OK', result.stdout)

    def test_compile_warning_is_preserved(self):
        result = self.invoke([('warning.pl', 'use warnings; $main::once = 1;\n')])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('used only once', result.stdout)
        self.assertNotIn('syntax OK', result.stdout)

    def test_diagnostic_containing_ok_is_not_filtered(self):
        result = self.invoke([('bad.pl', 'use strict; $OK = 1;\n')])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Global symbol "$OK"', result.stdout)


if __name__ == '__main__':
    unittest.main()
