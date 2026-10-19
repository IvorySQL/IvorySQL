#!/usr/bin/env python3
"""Test msvc_gendef argument handling with a controlled dumpbin executable.

Run on a POSIX host with Perl, without MSVC or a PostgreSQL build:
python3 src/tools/t/test_msvc_gendef.py [msvc_gendef.pl]
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else (
    Path(__file__).resolve().parents[1] / 'msvc_gendef.pl')

DUMPBIN = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
args = sys.argv[1:]
with open(os.environ['DUMPBIN_LOG'], 'a', encoding='utf-8') as log:
    log.write(json.dumps(args) + '\n')
print('dumpbin stdout')
print('dumpbin stderr', file=sys.stderr)
if os.environ.get('DUMPBIN_FAIL'):
    sys.exit(23)
output = next(arg[5:] for arg in args if arg.startswith('/out:'))
inputs = [arg for arg in args
          if arg not in ('/nologo', '/symbols') and not arg.startswith('/out:')]
if not inputs or not all(Path(arg).is_file() for arg in inputs):
    sys.exit(24)
Path(output).write_text(
    '02E 00000000 SECTA notype External | _test_data\n'
    '02F 00000001 SECTB notype () External | _test_func\n'
    '030 00000000 UNDEF notype External | _imported\n'
    '031 00000000 SECTC notype Static | _local\n')
'''


class GendefPaths(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bindir = self.root / 'bin'
        self.bindir.mkdir()
        tool = self.bindir / 'dumpbin'
        tool.write_text(DUMPBIN, encoding='utf-8')
        tool.chmod(0o755)
        self.log = self.root / 'dumpbin.jsonl'
        self.env = dict(os.environ,
                        PATH=str(self.bindir) + os.pathsep + os.environ['PATH'],
                        DUMPBIN_LOG=str(self.log))
        self.output = self.root / 'postgres.def'

    def run_gendef(self, inputs, tempdir=None, arch='x86_64'):
        tempdir = tempdir or self.root / 'temp'
        result = subprocess.run(
            ['perl', str(SCRIPT), '--arch', arch, '--deffile', str(self.output),
             '--tempdir', str(tempdir), *map(str, inputs)],
            env=self.env, cwd=self.root, capture_output=True, text=True,
            check=False)
        return result

    def check_success(self, result, expected_inputs, tempdir, arch='x86_64'):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('dumpbin stdout', result.stdout)
        self.assertIn('dumpbin stderr', result.stderr)
        self.assertEqual(json.loads(self.log.read_text().splitlines()[-1]),
                         ['/nologo', '/symbols', '/out:' + str(tempdir / 'tmp.sym'),
                          *map(str, expected_inputs)])
        prefix = '' if arch == 'x86' else '_'
        self.assertEqual(self.output.read_text(),
                         'EXPORTS\n  ' + prefix + 'test_data DATA\n  '
                         + prefix + 'test_func\n')

    def test_file_and_temp_paths_with_spaces(self):
        obj = self.root / 'object file.obj'
        obj.touch()
        tempdir = self.root / 'temporary symbols'
        self.check_success(self.run_gendef([obj], tempdir), [obj], tempdir)

    def test_directory_with_spaces_and_glob_characters(self):
        directory = self.root / 'object files[1]'
        directory.mkdir()
        objects = [directory / 'a.obj', directory / 'b file.obj']
        for obj in objects:
            obj.touch()
        (directory / 'ignored.txt').touch()
        tempdir = self.root / 'temp'
        self.check_success(self.run_gendef([directory]), objects, tempdir)

    def test_filename_with_shell_metacharacters_is_literal(self):
        obj = self.root / "object 'file&name'.obj"
        obj.touch()
        tempdir = self.root / 'temp'
        self.check_success(self.run_gendef([obj]), [obj], tempdir)

    def test_architecture_controls_decoration(self):
        obj = self.root / 'file.obj'
        obj.touch()
        for arch in ('x86', 'x86_64', 'aarch64'):
            with self.subTest(arch=arch):
                if self.output.exists():
                    self.output.unlink()
                self.check_success(self.run_gendef([obj], arch=arch), [obj],
                                   self.root / 'temp', arch)

    def test_dumpbin_failure_is_reported_without_a_def_file(self):
        obj = self.root / 'file.obj'
        obj.touch()
        self.env['DUMPBIN_FAIL'] = '1'
        result = self.run_gendef([obj])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('dumpbin stdout', result.stdout)
        self.assertIn('dumpbin stderr', result.stderr)
        self.assertIn('Could not call dumpbin', result.stderr)
        self.assertFalse(self.output.exists())

    def test_newer_def_file_skips_dumpbin(self):
        obj = self.root / 'file.obj'
        obj.touch()
        self.output.write_text('existing output\n')
        os.utime(obj, (1000000000, 1000000000))
        result = self.run_gendef([obj])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Not re-generating', result.stdout)
        self.assertFalse(self.log.exists())
        self.assertEqual(self.output.read_text(), 'existing output\n')


if __name__ == '__main__':
    unittest.main()
