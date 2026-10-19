#!/usr/bin/env python3
"""Exercise pgindent's formatter invocation using a controlled formatter.

Run: python3 src/tools/pgindent/t/test_pgindent_paths.py [pgindent]
No backend or pg_bsd_indent build is required.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else (
    Path(__file__).resolve().parents[1] / 'pgindent')
FORMATTER = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
args = sys.argv[1:]
with open(os.environ['FORMATTER_LOG'], 'a', encoding='utf-8') as log:
    log.write(json.dumps(args) + '\n')
if args == ['-?']:
    sys.exit(1)
if args == ['--version']:
    print('pg_bsd_indent ' + os.environ.get('TEST_VERSION', '2.1.3') + ' (fixture)')
    sys.exit(0)
if args == ['-gnu']:
    sys.exit(0 if os.environ.get('TEST_GNU') else 1)
if os.environ.get('TEST_FAILURE'):
    print('formatter stdout diagnostic')
    print('formatter stderr diagnostic', file=sys.stderr)
    sys.exit(5)
if os.environ.get('TEST_WARNING'):
    print('formatter warning', file=sys.stderr)
    sys.exit(0)
source = Path(args[-1])
source.write_text(source.read_text().replace('int x=0;', 'int x = 0;'))
'''


class FormatterPaths(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.typedefs = self.root / 'typedefs.list'
        self.typedefs.write_text('Datum\n')
        self.source = self.root / 'source.c'
        self.source.write_text('int x=0;\n')
        self.log = self.root / 'formatter.jsonl'
        self.env = dict(os.environ, FORMATTER_LOG=str(self.log))
        self.env.pop('PGINDENT', None)
        self.env.pop('INDENT', None)

    def formatter(self, name):
        tool = self.root / name
        tool.parent.mkdir(parents=True, exist_ok=True)
        tool.write_text(FORMATTER, encoding='utf-8')
        tool.chmod(0o755)
        return tool

    def invoke(self, tool, flags=(), via_env=False, include_source=True):
        args = ['perl', str(SCRIPT), '--typedefs', str(self.typedefs)]
        if via_env:
            self.env['PGINDENT'] = str(tool)
        else:
            args += ['--indent', str(tool)]
        if include_source:
            flags = list(flags) + [str(self.source)]
        return subprocess.run(args + list(flags),
                              cwd=self.root, env=self.env,
                              capture_output=True, text=True, check=False)

    def test_formatter_paths_are_literal(self):
        for name in ('plain/pg_bsd_indent', 'checkout with spaces/pg_bsd_indent',
                     "checkout's build/pg_bsd_indent", 'checkout$HOME/pg_bsd_indent'):
            with self.subTest(name=name):
                self.source.write_text('int x=0;\n')
                tool = self.formatter(name)
                result = self.invoke(tool)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.source.read_text(), 'int x = 0;\n')
                self.assertEqual(result.stderr, '')

    def test_pgindent_environment_used_by_hook(self):
        tool = self.formatter('repository root/src/tools/pg_bsd_indent')
        result = self.invoke(tool, via_env=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.source.read_text(), 'int x = 0;\n')

    def test_check_mode_preserves_source(self):
        tool = self.formatter('formatter with spaces')
        result = self.invoke(tool, ['--check'])
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.source.read_text(), 'int x=0;\n')

    def test_formatter_failure_keeps_both_diagnostics(self):
        tool = self.formatter('formatter with spaces')
        self.env['TEST_FAILURE'] = '1'
        result = self.invoke(tool)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn('formatter stdout diagnostic', result.stderr)
        self.assertIn('formatter stderr diagnostic', result.stderr)
        self.assertEqual(self.source.read_text(), 'int x=0;\n')

    def test_formatter_warning_still_prevents_rewrite(self):
        tool = self.formatter('formatter with spaces')
        self.env['TEST_WARNING'] = '1'
        result = self.invoke(tool)
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn('formatter warning', result.stderr)
        self.assertEqual(self.source.read_text(), 'int x=0;\n')

    def test_missing_formatter_reports_setup_error(self):
        result = self.invoke(self.root / 'missing formatter')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('installed on your system', result.stderr)
        self.assertEqual(self.source.read_text(), 'int x=0;\n')

    def test_version_and_gnu_checks_remain(self):
        tool = self.formatter('formatter with spaces')
        self.env['TEST_VERSION'] = '0.0.0'
        result = self.invoke(tool)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('version 2.1.3', result.stderr)
        self.env.pop('TEST_VERSION')
        self.env['TEST_GNU'] = '1'
        result = self.invoke(tool)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('GNU indent rather than BSD indent', result.stderr)

    def test_diff_receives_literal_source_path(self):
        real_diff = shutil.which('diff')
        self.assertIsNotNone(real_diff)
        bindir = self.root / 'bin'
        bindir.mkdir()
        diff = bindir / 'diff'
        diff.write_text("""#!/usr/bin/env python3
import json, os, sys
with open(os.environ['DIFF_LOG'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
os.execv(os.environ['REAL_DIFF'], [os.environ['REAL_DIFF'], *sys.argv[1:]])
""")
        diff.chmod(0o755)
        log = self.root / 'diff.jsonl'
        self.env.update(PATH=str(bindir) + os.pathsep + self.env['PATH'],
                        DIFF_LOG=str(log), REAL_DIFF=real_diff)
        tool = self.formatter('formatter')
        for name in ('cash$HOME.c', 'quote"name.c', 'line\nname.c'):
            with self.subTest(name=name):
                self.source = self.root / name
                self.source.write_text('int x=0;\n')
                result = self.invoke(tool, ['--diff', '--check'])
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(result.stderr, '')
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertEqual(calls[-1][:3], ['-upd', '--', str(self.source)])
                self.assertIn('-int x=0;', result.stdout)
                self.assertIn('+int x = 0;', result.stdout)
                self.assertEqual(self.source.read_text(), 'int x=0;\n')

    def git(self, *args):
        command = ['git', '-c', 'user.name=Test Fixture', '-c',
                   'user.email=test@example.invalid', '-c',
                   'commit.gpgsign=false', '-c',
                   'core.hooksPath=' + str(self.root / 'empty-hooks'), *args]
        return subprocess.run(command, cwd=self.root, env=self.env,
                              text=True, capture_output=True, check=True)

    def prepare_commits(self):
        (self.root / 'empty-hooks').mkdir()
        self.git('init', '-q')
        self.git('commit', '--allow-empty', '-qm', 'base')
        names = ['naïve.c', 'tab\tname.c', 'line\nname.c',
                 'quote"name.c', 'cash$HOME.c']
        for name in names:
            (self.root / name).write_text('int x=0;\n')
        self.git('add', '--', *names)
        self.git('commit', '-qm', 'add unusual source paths')
        return names

    def test_commit_preserves_git_quoted_and_newline_paths(self):
        names = self.prepare_commits()
        tool = self.formatter('formatter')
        result = self.invoke(tool, ['--commit', 'HEAD'], include_source=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        for name in names:
            self.assertEqual((self.root / name).read_text(), 'int x = 0;\n')

    def test_commit_revision_is_passed_literally(self):
        names = self.prepare_commits()
        branch = "topic'$HOME"
        self.git('branch', branch)
        tool = self.formatter('formatter')
        result = self.invoke(tool, ['--commit', branch], include_source=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        for name in names:
            self.assertEqual((self.root / name).read_text(), 'int x = 0;\n')

    def test_failed_git_command_remains_fatal(self):
        self.prepare_commits()
        tool = self.formatter('formatter')
        result = self.invoke(tool, ['--commit', 'no-such-revision'],
                             include_source=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('git error', result.stderr)
        self.assertEqual(self.source.read_text(), 'int x=0;\n')


if __name__ == '__main__':
    unittest.main()
