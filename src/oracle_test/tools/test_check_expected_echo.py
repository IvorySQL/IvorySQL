#!/usr/bin/env python3
#
# Unit tests for check_expected_echo.py.
#
# Run with:
#     python3 src/oracle_test/tools/test_check_expected_echo.py

import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from check_expected_echo import (check_target, echoed_lines, is_unmodelled,
                                 missing_lines)


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
    def test_gexec_is_unmodelled(self):
        self.assertTrue(is_unmodelled('SELECT 1 \\gexec\n'))

    def test_echo_is_unmodelled(self):
        self.assertTrue(is_unmodelled('\\echo hello\n'))

    def test_set_echo_is_unmodelled(self):
        self.assertTrue(is_unmodelled('\\set ECHO errors\n'))

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


if __name__ == '__main__':
    unittest.main()
