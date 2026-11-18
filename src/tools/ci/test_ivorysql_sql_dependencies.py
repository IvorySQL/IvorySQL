#!/usr/bin/env python3
# Portions Copyright (c) 2026, IvorySQL Global Development Team

"""Check incremental SQL generation using the real ivorysql_ora Meson target.

Run on Linux with python3 src/tools/ci/test_ivorysql_sql_dependencies.py. Requires Meson,
Ninja, Perl and a C compiler. Uses a disposable extension copy; no database
server or configured PostgreSQL build is needed.
"""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class SqlDependenciesTest(unittest.TestCase):
    """Exercise the real SQL target without compiling or starting a server."""

    def test_incremental_generation(self):
        """Verify input changes rebuild SQL and unchanged inputs leave it intact."""
        source = Path(__file__).resolve().parents[3] / 'contrib/ivorysql_ora'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            extension = root / 'contrib/ivorysql_ora'
            shutil.copytree(source, extension)
            # Include the actual extension meson.build. C targets are declared
            # but never built: this test requests only the generated SQL target.
            (root / 'meson.build').write_text("""
project('ivorysql-sql-dependencies', 'c')
fs = import('fs')
perl = find_program('perl')
host_system = host_machine.system()
contrib_data_args = {'install_dir': 'share/extension'}
contrib_mod_args = {'build_by_default': false}
contrib_targets = []
tests = []
dir_data = 'share'
subdir('contrib/ivorysql_ora')
""", encoding='utf-8')
            build = root / 'build'

            def run(*command):
                """Run a build command and include its output on failure."""
                result = subprocess.run(command, cwd=root, capture_output=True,
                                        text=True, encoding='utf-8')
                self.assertEqual(result.returncode, 0,
                                 result.stdout + result.stderr)

            def rebuild():
                """Build the SQL target and return its generated contents."""
                run('ninja', '-C', str(build),
                    'contrib/ivorysql_ora/ivorysql_ora--1.0.sql')
                return output.read_text(encoding='utf-8')

            run('meson', 'setup', str(build))
            output = build / 'contrib/ivorysql_ora/ivorysql_ora--1.0.sql'
            rebuild()

            manifest = extension / 'ivorysql_ora_merge_sqls'
            original_manifest = manifest.read_text(encoding='utf-8')
            for index, fragment in enumerate(original_manifest.splitlines()):
                marker = '-- incremental fragment {}\n'.format(index)
                path = extension / (fragment + '--1.0.sql')
                with path.open('a', encoding='utf-8') as stream:
                    stream.write('\n' + marker)
                self.assertTrue(marker in rebuild(),
                                'SQL edit was not rebuilt: ' + fragment)

            # Changing the manifest must reconfigure the dependency graph as
            # well as regenerate the SQL, including subsequent edits to a newly
            # listed fragment.
            extra = extension / 'incremental-test--1.0.sql'
            extra.write_text('-- newly listed fragment\n', encoding='utf-8')
            manifest.write_text(original_manifest.rstrip() + '\nincremental-test\n',
                                encoding='utf-8')
            self.assertIn('-- newly listed fragment', rebuild())
            extra.write_text('-- changed new fragment\n', encoding='utf-8')
            self.assertIn('-- changed new fragment', rebuild())
            manifest.write_text(original_manifest, encoding='utf-8')
            self.assertNotIn('-- changed new fragment', rebuild())

            with (extension / 'gensql.pl').open('a', encoding='utf-8') as stream:
                stream.write('\nprint "-- changed generator\\n";\n')
            self.assertIn('-- changed generator', rebuild())

            unchanged_mtime = output.stat().st_mtime_ns
            rebuild()
            self.assertEqual(output.stat().st_mtime_ns, unchanged_mtime,
                             'unchanged inputs must not regenerate SQL')


if __name__ == '__main__':
    unittest.main()
