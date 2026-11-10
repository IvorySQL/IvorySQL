"""Exercise PL/iSQL's explicit Make dependencies without a configured server."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]


class MakeDependencies(unittest.TestCase):
    def test_header_changes_rebuild_consumers(self):
        cases = [(obj, header) for obj in
                 ('pl_package.o', 'pl_subproc_function.o', 'pl_exception_type.o')
                 for header in ('plisql.h', 'pl_subproc_function.h',
                                'pl_package.h', 'pl_autonomous.h')]
        cases += [(obj, 'pl_exception_type.h') for obj in
                  ('pl_comp.o', 'pl_exec.o', 'pl_funcs.o', 'pl_gram.o',
                   'pl_exception_type.o')]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build = root / 'src/pl/plisql/src'
            build.mkdir(parents=True)
            # Run the real Makefile, replacing only configured build globals
            # and shared-library linkage rules. No compiler or database is used.
            for path in SOURCE.iterdir():
                if path.is_file():
                    shutil.copyfile(path, build / path.name)
            (root / 'src/Makefile.global').write_text(
                'top_srcdir := ' + str(root) + '\nsrcdir := .\n')
            (root / 'src/Makefile.shlib').write_text('')
            inputs = root / 'src/backend/utils'
            inputs.mkdir(parents=True)
            (inputs / 'ora_errcodes.txt').touch()
            for name in ('pl_gram.c', 'pl_gram.h', 'plerrcodes.h',
                         'pl_reserved_kwlist_d.h', 'pl_unreserved_kwlist_d.h'):
                (build / name).touch()
            for obj, header in cases:
                with self.subTest(object=obj, header=header):
                    for path in root.rglob('*'):
                        if path.is_file():
                            os.utime(path, (1000000000, 1000000000))
                    target = build / obj
                    target.touch()
                    os.utime(target, (1000000020, 1000000020))
                    command = ['make', '-q', obj]
                    clean = subprocess.run(command, cwd=build, capture_output=True)
                    self.assertEqual(clean.returncode, 0, clean.stderr.decode())
                    os.utime(build / header, (1000000040, 1000000040))
                    stale = subprocess.run(command, cwd=build, capture_output=True)
                    self.assertEqual(stale.returncode, 1, stale.stderr.decode())


if __name__ == '__main__':
    unittest.main()
