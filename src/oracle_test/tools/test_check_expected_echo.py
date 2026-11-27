#!/usr/bin/env python3
#
# Unit tests for check_expected_echo.py.
#
# Run with:
#     python3 src/oracle_test/tools/test_check_expected_echo.py

import contextlib
import io
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from check_expected_echo import (MISSING_EXPECTED, _module_subdirs,
                                 check_target, collect_targets, echoed_lines,
                                 is_unmodelled, main, missing_lines)


class EchoedLinesTest(unittest.TestCase):
    def test_blank_lines_are_not_echoed(self):
        self.assertEqual(echoed_lines('SELECT 1;\n\nSELECT 2;\n'),
                         ['SELECT 1;', 'SELECT 2;'])

    def test_meta_commands_are_echoed(self):
        # psql -a prints meta-commands too, so a \set or \d line has to be
        # repeated in the expected output like any other input line.
        self.assertEqual(echoed_lines('\\d t\nSELECT 1;\n'),
                         ['\\d t', 'SELECT 1;'])

    def test_copy_from_stdin_keeps_command_and_drops_data(self):
        sql = 'COPY t FROM stdin;\n1\tfoo\n\\.\nSELECT 1;\n'
        self.assertEqual(echoed_lines(sql), ['COPY t FROM stdin;', 'SELECT 1;'])

    def test_copy_from_stdout_is_treated_like_stdin(self):
        sql = 'copy t from stdout;\n1\tbaz\n2\tqux\n\\.\n'
        self.assertEqual(echoed_lines(sql), ['copy t from stdout;'])

    def test_psql_copy_keeps_command_and_drops_data(self):
        # The \copy command itself is an input line and is echoed; only its
        # inline data is read out of band and therefore not echoed.
        sql = '\\copy t from stdin\n1\tfoo\n\\.\nSELECT 1;\n'
        self.assertEqual(echoed_lines(sql),
                         ['\\copy t from stdin', 'SELECT 1;'])

    def test_data_line_that_looks_like_terminator_stays_data(self):
        # A data line of "\.foo" is not the terminator, so the block goes on
        # until the real "\." line.
        sql = 'COPY t FROM stdin;\n\\.foo\n\\.\nSELECT 1;\n'
        self.assertEqual(echoed_lines(sql), ['COPY t FROM stdin;', 'SELECT 1;'])

    def test_copy_select_from_stdin_is_not_client_data(self):
        # COPY (SELECT ...) FROM stdin is invalid and never reads data, so it
        # must not swallow the lines that follow it.
        sql = 'copy (select * from test1) from stdin;\nSELECT 1;\n'
        self.assertEqual(echoed_lines(sql),
                         ['copy (select * from test1) from stdin;', 'SELECT 1;'])

    def test_two_copy_blocks_on_one_line_skip_two_data_blocks(self):
        sql = ('select 0\\; copy t3 from stdin\\; copy t3 from stdin\\; '
               'select 1;\n1\n\\.\n2\n\\.\nselect * from t3;\n')
        self.assertEqual(
            echoed_lines(sql),
            ['select 0\\; copy t3 from stdin\\; copy t3 from stdin\\; select 1;',
             'select * from t3;'])

    def test_terminator_outside_a_block_is_not_echoed(self):
        self.assertEqual(echoed_lines('\\.\nSELECT 1;\n'), ['SELECT 1;'])

    def test_trailing_whitespace_is_ignored(self):
        self.assertEqual(echoed_lines('SELECT 1;   \n'), ['SELECT 1;'])

    def test_comments_are_echoed(self):
        self.assertEqual(echoed_lines('-- cleanup\ndrop table t;\n'),
                         ['-- cleanup', 'drop table t;'])


class CopyDetectionTest(unittest.TestCase):
    """A COPY that only appears in a comment or a literal reads no data."""

    def test_copy_in_a_comment_is_not_client_data(self):
        sql = '-- COPY t FROM stdin\nSELECT 1;\nSELECT 2;\n'
        self.assertEqual(echoed_lines(sql),
                         ['-- COPY t FROM stdin', 'SELECT 1;', 'SELECT 2;'])

    def test_copy_inside_a_string_literal_is_not_client_data(self):
        sql = "SELECT 'COPY t FROM stdin';\nSELECT 1;\n"
        self.assertEqual(echoed_lines(sql),
                         ["SELECT 'COPY t FROM stdin';", 'SELECT 1;'])

    def test_copy_after_a_closed_block_comment_is_still_detected(self):
        sql = '/* note */ COPY t FROM stdin;\n1\n\\.\nSELECT 1;\n'
        self.assertEqual(echoed_lines(sql),
                         ['/* note */ COPY t FROM stdin;', 'SELECT 1;'])

    def test_doubled_quote_inside_literal_does_not_end_it(self):
        sql = "SELECT 'it''s a literal' AS s; COPY t FROM stdin;\n1\n\\.\n"
        self.assertEqual(echoed_lines(sql),
                         ["SELECT 'it''s a literal' AS s; COPY t FROM stdin;"])


    def test_comment_markers_inside_quoted_identifier_are_kept(self):
        sql = 'COPY "order--archive" FROM stdin;\n1\n\\.\nSELECT 1;\n'
        self.assertEqual(echoed_lines(sql),
                         ['COPY "order--archive" FROM stdin;', 'SELECT 1;'])


class MissingLinesTest(unittest.TestCase):
    def test_lines_in_order_are_matched(self):
        expected = 'SELECT 1;\n 1\n(1 row)\nSELECT 2;\n 2\n(1 row)\n'
        self.assertEqual(missing_lines(expected, ['SELECT 1;', 'SELECT 2;']), [])

    def test_missing_line_is_reported(self):
        expected = 'SELECT 1;\n'
        self.assertEqual(missing_lines(expected, ['SELECT 1;', 'SELECT 2;']),
                         ['SELECT 2;'])

    def test_line_out_of_order_is_reported(self):
        expected = 'SELECT 2;\nSELECT 1;\n'
        self.assertEqual(missing_lines(expected, ['SELECT 1;', 'SELECT 2;']),
                         ['SELECT 2;'])

    def test_trailing_whitespace_is_ignored(self):
        self.assertEqual(missing_lines('SELECT 1;   \n', ['SELECT 1;']), [])

    def test_repeated_line_matches_each_occurrence(self):
        expected = 'SELECT 1;\n 1\nSELECT 1;\n 1\n'
        self.assertEqual(missing_lines(expected, ['SELECT 1;', 'SELECT 1;']), [])


class UnmodelledTest(unittest.TestCase):
    def test_set_echo_errors_is_unmodelled(self):
        self.assertTrue(is_unmodelled('\\set ECHO errors\nSELECT 1;\n'))

    def test_comment_mentioning_echo_is_ignored(self):
        self.assertFalse(is_unmodelled(
            '-- \\set ECHO errors is documented here\nSELECT 1;\n'))

    def test_set_echo_queries_is_unmodelled(self):
        self.assertTrue(is_unmodelled('\\set ECHO queries\nSELECT 1;\n'))

    def test_set_echo_none_is_modelled(self):
        self.assertFalse(is_unmodelled('\\set ECHO none\nSELECT 1;\n'))

    def test_unset_echo_is_modelled(self):
        self.assertFalse(is_unmodelled('\\unset ECHO\nSELECT 1;\n'))

    def test_conditional_echo_toggle_is_unmodelled(self):
        # The toggle is skipped when the \if branch is inactive, so the
        # state after the branch cannot be known without running it.
        self.assertTrue(is_unmodelled(
            '\\if :foo\n\\set ECHO none\n\\endif\nSELECT 1;\n'))

    def test_if_does_not_suppress_the_echo(self):
        # MainLoop echoes an input line before it checks whether the \if
        # branch is active, so the echo model still applies.
        self.assertFalse(is_unmodelled('\\if :foo\nSELECT 1;\n\\endif\n'))

    def test_gexec_keeps_the_input_line(self):
        # The statements that \gexec generates are not echoed, but the
        # \gexec line itself is, so the test can still be compared.
        self.assertFalse(is_unmodelled('SELECT 1 \\gexec\n'))

    def test_echo_keeps_the_input_line(self):
        # \echo prints an extra output line; its command line is still
        # echoed like any other input line.
        self.assertFalse(is_unmodelled('\\echo hello\n'))

    def test_plain_script_is_modelled(self):
        self.assertFalse(is_unmodelled('SELECT 1;\n'))


class EchoStateTest(unittest.TestCase):
    def test_none_suppresses_lines_until_all(self):
        sql = '\\set ECHO none\nSELECT 1;\n\\set ECHO all\nSELECT 2;\n'
        self.assertEqual(echoed_lines(sql),
                         ['\\set ECHO none', 'SELECT 2;'])

    def test_unset_echo_suppresses_lines(self):
        self.assertEqual(echoed_lines('\\unset ECHO\nSELECT 1;\n'),
                         ['\\unset ECHO'])

    def test_copy_data_is_consumed_while_echo_is_off(self):
        # The \copy command is not echoed, but its data still has to be
        # skipped so that later lines are not mistaken for input.
        sql = ('\\set ECHO none\n\\copy t from stdin\n1\n\\.\n'
               '\\set ECHO all\nSELECT 1;\n')
        self.assertEqual(echoed_lines(sql),
                         ['\\set ECHO none', 'SELECT 1;'])


class CheckTargetTest(unittest.TestCase):
    """End-to-end check of one sql/expected pair through check_target()."""

    def setUp(self):
        # The tool finds expected files by listing the expected directory, so a
        # throwaway tree with the same layout is enough to exercise it fully.
        self.tmp = tempfile.mkdtemp(prefix='echo_check_')
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.sql_dir = os.path.join(self.tmp, 'sql')
        self.expected_dir = os.path.join(self.tmp, 'expected')
        os.makedirs(self.sql_dir)
        os.makedirs(self.expected_dir)
        self.sql_path = os.path.join(self.sql_dir, 't.sql')
        with open(self.sql_path, 'w', encoding='utf-8') as handle:
            handle.write('-- cleanup\nSELECT 1;\nSELECT 2;\n')

    def _write_expected(self, text, name='t.out'):
        with open(os.path.join(self.expected_dir, name), 'w',
                  encoding='utf-8') as handle:
            handle.write(text)

    def test_stale_expected_file_is_reported(self):
        self._write_expected('-- cleanup\nSELECT 1;\n')
        self.assertEqual(check_target(self.sql_path, self.expected_dir, 't'),
                         ['SELECT 2;'])

    def test_variant_that_matches_is_accepted(self):
        # A platform-specific variant may hold the drifted-away line while the
        # primary expected file does not; the checker must accept either.
        self._write_expected('-- cleanup\nSELECT 1;\n')
        self._write_expected('-- cleanup\nSELECT 1;\nSELECT 2;\n', name='t_1.out')
        self.assertEqual(check_target(self.sql_path, self.expected_dir, 't'), [])

    def test_synced_expected_file_is_accepted(self):
        self._write_expected('-- cleanup\nSELECT 1;\nSELECT 2;\n')
        self.assertEqual(check_target(self.sql_path, self.expected_dir, 't'), [])

    def test_missing_expected_file_is_reported(self):
        # pg_regress has nothing to compare the results with, so a test whose
        # expected output was never generated must fail the check instead of
        # being skipped as unmodelled.
        self.assertIs(check_target(self.sql_path, self.expected_dir, 't'),
                      MISSING_EXPECTED)

    def test_missing_expected_directory_is_reported(self):
        # Losing the whole expected/ directory is just as broken as losing a
        # single file, and used to raise an unhandled FileNotFoundError from
        # os.listdir().
        self.assertIs(check_target(self.sql_path,
                                   os.path.join(self.tmp, 'no_expected'), 't'),
                      MISSING_EXPECTED)


class ModuleSubdirsTest(unittest.TestCase):
    """Only the modules that modules/Makefile builds run in a normal suite."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='echo_modules_')
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.modules = os.path.join(self.tmp, 'modules')
        os.makedirs(self.modules)

    def _write_makefile(self, text):
        with open(os.path.join(self.modules, 'Makefile'), 'w',
                  encoding='utf-8') as handle:
            handle.write(text)

    def _add_test(self, module, expected_text):
        sql_dir = os.path.join(self.modules, module, 'sql')
        expected_dir = os.path.join(self.modules, module, 'expected')
        os.makedirs(sql_dir)
        os.makedirs(expected_dir)
        with open(os.path.join(sql_dir, 't.sql'), 'w',
                  encoding='utf-8') as handle:
            handle.write('SELECT 1;\nSELECT 2;\n')
        with open(os.path.join(expected_dir, 't.out'), 'w',
                  encoding='utf-8') as handle:
            handle.write(expected_text)

    def test_continuation_lines_and_conditional_appends(self):
        # SUBDIRS is spread over continuation lines, and the "+=" additions
        # sit under configure conditionals whose value a static reader cannot
        # evaluate; only the unconditional assignment is authoritative.
        self._write_makefile(
            'SUBDIRS = \\\n'
            '\t\t  alpha \\\n'
            '\t\t  beta\n'
            '\n'
            'ifeq ($(enable_injection_points),yes)\n'
            'SUBDIRS += gamma\n'
            'else\n'
            'ALWAYS_SUBDIRS += gamma\n'
            'endif\n')
        self.assertEqual(_module_subdirs(self.modules), {'alpha', 'beta'})

    def test_commented_out_assignment_is_ignored(self):
        # A module name in a comment must not sneak into the build list.
        self._write_makefile('SUBDIRS = alpha\n# SUBDIRS += beta\n')
        self.assertEqual(_module_subdirs(self.modules), {'alpha'})

    def test_missing_makefile_means_unknown(self):
        # Falling back to every directory is safer than checking nothing when
        # the build list cannot be read.
        self.assertIsNone(_module_subdirs(self.modules))

    def test_makefile_without_subdirs_means_unknown(self):
        self._write_makefile('include ../Makefile.global\n')
        self.assertIsNone(_module_subdirs(self.modules))

    def test_unlisted_module_is_skipped_by_default(self):
        self._write_makefile('SUBDIRS = alpha\n')
        self._add_test('alpha', 'SELECT 1;\nSELECT 2;\n')
        self._add_test('gamma', 'SELECT 1;\n')
        default = collect_targets(self.tmp, False)
        self.assertEqual(len(default), 1)
        self.assertEqual(default[0][0],
                         os.path.join(self.modules, 'alpha', 'sql', 't.sql'))
        self.assertTrue(default[0][3])

    def test_unlisted_module_is_unscheduled_with_all(self):
        # --all still reports the module, but as unscheduled so that its drift
        # cannot fail the check on a configuration that does not build it.
        self._write_makefile('SUBDIRS = alpha\n')
        self._add_test('alpha', 'SELECT 1;\nSELECT 2;\n')
        self._add_test('gamma', 'SELECT 1;\n')
        everything = collect_targets(self.tmp, True)
        by_module = {}
        for sql_path, dummy_expected, dummy_base, scheduled in everything:
            module = os.path.basename(os.path.dirname(os.path.dirname(sql_path)))
            by_module[module] = scheduled
        self.assertEqual(by_module, {'alpha': True, 'gamma': False})

    def test_missing_makefile_keeps_modules_scheduled(self):
        self._add_test('alpha', 'SELECT 1;\nSELECT 2;\n')
        targets = collect_targets(self.tmp, False)
        self.assertEqual(len(targets), 1)
        self.assertTrue(targets[0][3])

    def test_module_without_expected_directory_is_collected(self):
        # If the whole expected/ directory is gone the module must still be
        # reported as broken instead of silently disappearing from the check.
        sql_dir = os.path.join(self.modules, 'alpha', 'sql')
        os.makedirs(sql_dir)
        with open(os.path.join(sql_dir, 't.sql'), 'w',
                  encoding='utf-8') as handle:
            handle.write('SELECT 1;\n')
        self._write_makefile('SUBDIRS = alpha\n')
        targets = collect_targets(self.tmp, False)
        self.assertEqual(len(targets), 1)
        sql_path, expected_dir, base, scheduled = targets[0]
        self.assertTrue(scheduled)
        self.assertIs(check_target(sql_path, expected_dir, base),
                      MISSING_EXPECTED)


class MainExitStatusTest(unittest.TestCase):
    """Drift in a test that no schedule runs must not fail the check."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='echo_main_')
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.regress = os.path.join(self.tmp, 'regress')
        sql_dir = os.path.join(self.regress, 'sql')
        expected_dir = os.path.join(self.regress, 'expected')
        os.makedirs(sql_dir)
        os.makedirs(expected_dir)
        with open(os.path.join(sql_dir, 't.sql'), 'w', encoding='utf-8') as handle:
            handle.write('SELECT 1;\nSELECT 2;\n')
        # Only the first statement made it into the expected output.
        with open(os.path.join(expected_dir, 't.out'), 'w', encoding='utf-8') as handle:
            handle.write('SELECT 1;\n')

    def _run(self, argv):
        with contextlib.redirect_stdout(io.StringIO()):
            return main(argv)

    def test_scheduled_drift_fails(self):
        with open(os.path.join(self.regress, 'parallel_schedule'), 'w',
                  encoding='utf-8') as handle:
            handle.write('test: t\n')
        self.assertEqual(self._run(['--dir', self.tmp]), 1)

    def test_unscheduled_drift_is_reported_but_passes(self):
        self.assertEqual(self._run(['--dir', self.tmp]), 0)
        self.assertEqual(self._run(['--dir', self.tmp, '--all']), 0)

    def test_missing_expected_file_fails_scheduled_test(self):
        # No expected output means no possible pass, whether or not there is
        # an echoed line to compare.
        os.remove(os.path.join(self.regress, 'expected', 't.out'))
        with open(os.path.join(self.regress, 'parallel_schedule'), 'w',
                  encoding='utf-8') as handle:
            handle.write('test: t\n')
        self.assertEqual(self._run(['--dir', self.tmp]), 1)

    def test_missing_expected_file_passes_when_unscheduled(self):
        os.remove(os.path.join(self.regress, 'expected', 't.out'))
        # Only --all reaches the test when no schedule lists it.
        self.assertEqual(self._run(['--dir', self.tmp, '--all']), 0)


if __name__ == '__main__':
    unittest.main()
