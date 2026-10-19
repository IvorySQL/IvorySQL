#!/usr/bin/env python3
"""Run the Bash external-diff wrapper without executing Git configuration.

Run: python3 src/tools/t/test_git_external_diff.py [git-external-diff]
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else (
    Path(__file__).resolve().parents[1] / 'git-external-diff')

GIT = r'''#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import sys
args = sys.argv[1:]
with open(os.environ['GIT_LOG'], 'a', encoding='utf-8') as log:
    log.write(json.dumps(args) + '\n')
if args[0] == 'hash-object':
    data = Path(args[1]).read_bytes()
    print(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest())
else:
    # Record but never run the config/diff examples embedded in the old script.
    sys.exit(1)
'''


def blob_hash(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


class ExternalDiff(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        bindir = self.root / 'bin'
        bindir.mkdir()
        git = bindir / 'git'
        git.write_text(GIT, encoding='utf-8')
        git.chmod(0o755)
        self.log = self.root / 'git.jsonl'
        self.env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ['PATH'],
                        GIT_LOG=str(self.log), DIFF_OPTS='')
        self.old = self.root / 'old file'
        self.new = self.root / 'new file'

    def run_diff(self, old, new):
        self.old.write_bytes(old)
        self.new.write_bytes(new)
        result = subprocess.run(
            ['bash', str(SCRIPT), 'source file.c', str(self.old), blob_hash(old),
             '100644', str(self.new), blob_hash(new), '100644'],
            cwd=self.root, env=self.env, capture_output=True, text=True,
            check=False)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [['hash-object', str(self.new)]])
        self.assertEqual(result.stderr, '')
        return result.stdout

    def test_changed_content_produces_context_diff(self):
        output = self.run_diff(b'old line\n', b'new line\n')
        self.assertIn('diff --git a/source file.c b/source file.c\n', output)
        self.assertIn('*** a/source file.c\n--- b/source file.c\n', output)
        self.assertIn('! old line\n', output)
        self.assertIn('! new line\n', output)

    def test_unchanged_content_is_silent(self):
        self.assertEqual(self.run_diff(b'same line\n', b'same line\n'), '')

    def test_custom_diff_options_remain_supported(self):
        self.env['DIFF_OPTS'] = '-u'
        output = self.run_diff(b'old line\n', b'new line\n')
        self.assertIn('--- a/source file.c\n+++ b/source file.c\n', output)
        self.assertIn('-old line\n+new line\n', output)


if __name__ == '__main__':
    unittest.main()
