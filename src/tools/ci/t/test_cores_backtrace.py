#!/usr/bin/env python3
"""Exercise core-file argument handling without requiring actual debuggers.

Run: python3 src/tools/ci/t/test_cores_backtrace.py [cores_backtrace.sh]
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else (
    Path(__file__).resolve().parents[1] / 'cores_backtrace.sh')

DEBUGGER = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
args = sys.argv[1:]
with open(os.environ['DEBUGGER_LOG'], 'a', encoding='utf-8') as log:
    log.write(json.dumps(args) + '\n')
if '--core' in args:
    core = args[args.index('--core') + 1]
elif '-c' in args:
    core = args[args.index('-c') + 1]
else:
    core = args[-1]
if not Path(core).is_file():
    sys.exit(1)
if 'info auxv' in args:
    for name in ('AT_EXECFN', 'AT_EXECPATH', 'AT_SUN_EXECNAME'):
        print('31 ' + name + ' executable: "/tmp/postgres binary"')
'''


class CorePaths(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bindir = self.root / 'bin'
        self.bindir.mkdir()
        for name in ('gdb', 'lldb'):
            tool = self.bindir / name
            tool.write_text(DEBUGGER, encoding='utf-8')
            tool.chmod(0o755)
        self.log = self.root / 'debugger.jsonl'
        self.env = dict(os.environ,
                        PATH=str(self.bindir) + os.pathsep + os.environ['PATH'],
                        DEBUGGER_LOG=str(self.log))

    def run_cores(self, platform, directory, *extra):
        if self.log.exists():
            self.log.unlink()
        result = subprocess.run(['sh', str(SCRIPT), platform, str(directory),
                                 *map(str, extra)], env=self.env,
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = ([json.loads(line) for line in self.log.read_text().splitlines()]
                 if self.log.exists() else [])
        seen = []
        for args in calls:
            if '--core' in args:
                seen.append(args[args.index('--core') + 1])
            elif '-c' in args:
                seen.append(args[args.index('-c') + 1])
            else:
                seen.append(args[-1])
        return seen, calls

    def test_file_paths_are_preserved_on_all_platforms(self):
        cores = self.root / 'core directory'
        cores.mkdir()
        # Include a matching wildcard target: accidental expansion must not
        # substitute postgres1.core for the literal postgres[1].core name.
        names = ['plain.core', 'post gres.core', 'post\tgres.core',
                 'post\ngres.core', 'postgres[1].core', 'postgres1.core',
                 'post\\gres.core', "post'gres.core"]
        expected = []
        for name in names:
            core = cores / name
            core.touch()
            expected.append(str(core))
        for platform in ('linux', 'freebsd', 'netbsd', 'macos', 'openbsd'):
            with self.subTest(platform=platform):
                extra = [self.bindir] if platform == 'openbsd' else []
                seen, calls = self.run_cores(platform, cores, *extra)
                copies = 1 if platform in ('macos', 'openbsd') else 2
                self.assertCountEqual(seen, expected * copies)
                if copies == 2:
                    for args in calls:
                        if '--core' not in args:
                            self.assertEqual(args[-2], '/tmp/postgres binary')

    def test_empty_directory_does_not_invoke_debugger(self):
        cores = self.root / 'empty'
        cores.mkdir()
        seen, calls = self.run_cores('linux', cores)
        self.assertEqual(calls, [])

    def test_openbsd_resolves_executable_with_spaces(self):
        cores = self.root / 'cores'
        cores.mkdir()
        (cores / 'post gres.core').touch()
        binary = self.bindir / 'post gres'
        binary.write_text('#!/bin/sh\nexit 0\n')
        binary.chmod(0o755)
        seen, calls = self.run_cores('openbsd', cores, self.bindir)
        self.assertEqual(calls[0][0], str(binary))


if __name__ == '__main__':
    unittest.main()
