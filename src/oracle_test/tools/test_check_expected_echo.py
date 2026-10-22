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

from check_expected_echo import (check_target, echoed_lines, is_unmodelled,
                                 main, missing_lines)


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
    def test_set_echo_is_unmodelled(self):
        self.assertTrue(is_unmodelled('\\set ECHO errors\n'))

    def test_set_echo_none_is_unmodelled(self):
        self.assertTrue(is_unmodelled('\\set ECHO none\nSELECT 1;\n'))

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


if __name__ == '__main__':
    unittest.main()
