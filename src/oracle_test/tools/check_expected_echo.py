#!/usr/bin/env python3
#
# check_expected_echo.py
#
# Verify that the expected output of an Oracle-compatible pg_regress test still
# contains every line that psql is supposed to echo for it.
#
# pg_regress runs psql with -a (echo all), so psql copies every line of a test's
# .sql file into results/ as it is read, except for blank lines and the data of
# a COPY ... FROM stdin block, which psql takes straight from the client.  The
# expected file therefore has to repeat those lines verbatim and in the same
# order -- backslash meta-commands such as \set or \d, and the lone "/" that
# terminates a PL/SQL block in Oracle mode, are echoed too.  When a .sql file
# is edited, or a test is re-synced from src/test, and the matching expected
# file is not regenerated, the test fails on every machine even though the SQL
# itself may still be correct.
#
# This checker rebuilds the echoed lines of a test and looks for them, in order,
# in one of the test's expected variants.  It needs neither a built server nor a
# running cluster, so it can be used right after a sync to find drift before the
# regression suite is started.
#
# Usage:
#     python3 src/oracle_test/tools/check_expected_echo.py [--dir DIR] [--all]
#
# By default only the tests that the Oracle-compatible suite actually executes
# are checked: the tests named in regress/parallel_schedule and
# regress/serial_schedule plus every test found under modules/.  Pass --all to
# also walk the remaining sql/expected pairs, which may include tests that no
# schedule runs.

import argparse
import os
import re
import sys

# A COPY command whose data comes from the client, written either as the
# server command "COPY ... FROM stdin" or as psql's "\copy ... from
# stdin".  The table name is matched explicitly so that a COPY (SELECT ...)
# statement, which never reads client data, is not mistaken for one.  psql
# echoes the command line itself but not the data lines that follow it up to
# the terminating "\." line.  "stdout" is accepted as a client-side spelling
# of "stdin", as a few tests use.
_COPY_FROM_STDIN = re.compile(
    r'\bCOPY\s+(?:"[^"]*"|[\w$.]+)(?:\s*\([^)]*\))?\s+FROM\s+std(?:in|out)\b',
    re.IGNORECASE)


def _strip_comments_and_literals(line):
    r"""Line with SQL comments and single-quoted literals blanked out.

    The COPY detector has to look at code only: a commented-out COPY, or the
    words COPY ... FROM stdin inside a string literal, is echoed text rather
    than a command that reads client data.  Single quotes are blanked and a
    doubled quote inside a literal is skipped, so E'it''s' survives intact;
    double-quoted names are kept because COPY "t" FROM stdin is code, and
    their contents are copied verbatim so a marker such as "--" inside an
    identifier is not mistaken for a comment.
    """
    out = []
    index = 0
    length = len(line)
    while index < length:
        char = line[index]
        if char == "'":
            index += 1
            while index < length:
                if line[index] == "'":
                    if index + 1 < length and line[index + 1] == "'":
                        index += 2
                        continue
                    index += 1
                    break
                index += 1
            out.append(' ')
        elif char == '"':
            out.append(char)
            index += 1
            while index < length:
                out.append(line[index])
                if line[index] == '"':
                    if index + 1 < length and line[index + 1] == '"':
                        out.append(line[index + 1])
                        index += 2
                        continue
                    index += 1
                    break
                index += 1
        elif line.startswith('--', index):
            break
        elif line.startswith('/*', index):
            end = line.find('*/', index + 2)
            if end == -1:
                break
            index = end + 2
            out.append(' ')
        else:
            out.append(char)
            index += 1
    return ''.join(out)


# \set ECHO is the only construct that changes what psql echoes from that
# point on, so a file that uses it cannot be modelled line by line.  \if,
# \echo and \gexec are different: MainLoop echoes every input line before it
# decides whether a \if branch is active, and the text \echo or \gexec
# produce is extra output rather than a replacement for the echoed input
# line.  Those tests are therefore checked normally; only input lines are
# compared, so generated output is simply ignored.
_UNMODELLED = re.compile(r'\\set\s+ECHO\b', re.IGNORECASE)


def echoed_lines(sql_text):
    r"""Lines of a .sql file that psql -a copies into the results file.

    --echo-all prints every nonempty input line as it is read, meta-commands
    included; only blank lines and the contents of a COPY ... FROM stdin block
    (its data plus the terminating "\." line) are left out.

    A single input line can hold more than one command string separated by
    "\;", and a test may start two COPY ... FROM stdin blocks on one line, so
    each occurrence opens its own data block.  The number of terminators that
    still have to be skipped is therefore counted rather than tracked as a
    simple on/off flag.
    """
    echoed = []
    skip_blocks = 0
    for raw_line in sql_text.splitlines():
        line = raw_line.rstrip()
        if skip_blocks:
            if line.strip() == r'\.':
                skip_blocks -= 1
            continue
        if not line.strip():
            continue
        if line.strip() == r'\.':
            # A terminator never reaches results/ as input text.
            continue
        count = len(_COPY_FROM_STDIN.findall(
            _strip_comments_and_literals(line.lstrip())))
        if count:
            echoed.append(line)
            skip_blocks = count
            continue
        echoed.append(line)
    return echoed


def is_unmodelled(sql_text):
    """True when the echo model cannot be applied to this test."""
    return bool(_UNMODELLED.search(sql_text))


def missing_lines(expected_text, echoed):
    """Echoed lines that are absent from expected_text, in order.

    The comparison is a greedy in-order subsequence match, which is how
    pg_regress itself lines the echoed statements up with the results.
    Trailing whitespace is ignored on both sides.
    """
    expected = [line.rstrip() for line in expected_text.splitlines()]
    position = 0
    missing = []
    for line in echoed:
        try:
            position = expected.index(line, position) + 1
        except ValueError:
            missing.append(line)
    return missing


def _scheduled_tests(regress_dir):
    """Test names listed in parallel_schedule or serial_schedule."""
    names = set()
    for schedule in ('parallel_schedule', 'serial_schedule'):
        path = os.path.join(regress_dir, schedule)
        if not os.path.isfile(path):
            continue
        with open(path, encoding='utf-8', errors='replace') as handle:
            for line in handle:
                line = line.strip()
                if line.startswith('test:'):
                    names.update(line[len('test:'):].split())
    return names


def _expected_variants(expected_dir, base):
    """All expected files for a test: base.out and base_<n>.out."""
    variants = []
    for name in sorted(os.listdir(expected_dir)):
        if name == base + '.out' or (name.startswith(base + '_')
                                     and name.endswith('.out')):
            variants.append(os.path.join(expected_dir, name))
    return variants


def _read(path):
    with open(path, encoding='utf-8', errors='replace') as handle:
        return handle.read()


def collect_targets(root, include_all):
    """Return (sql_path, expected_dir, base, scheduled) for every test."""
    targets = []

    regress = os.path.join(root, 'regress')
    sql_dir = os.path.join(regress, 'sql')
    if os.path.isdir(sql_dir):
        scheduled = _scheduled_tests(regress)
        for name in sorted(os.listdir(sql_dir)):
            if not name.endswith('.sql'):
                continue
            base = name[:-len('.sql')]
            if not include_all and base not in scheduled:
                continue
            targets.append((os.path.join(sql_dir, name),
                            os.path.join(regress, 'expected'), base,
                            base in scheduled))

    modules = os.path.join(root, 'modules')
    if os.path.isdir(modules):
        for module in sorted(os.listdir(modules)):
            module_sql = os.path.join(modules, module, 'sql')
            module_expected = os.path.join(modules, module, 'expected')
            if not (os.path.isdir(module_sql) and os.path.isdir(module_expected)):
                continue
            for name in sorted(os.listdir(module_sql)):
                if name.endswith('.sql'):
                    targets.append((os.path.join(module_sql, name),
                                    module_expected, name[:-len('.sql')],
                                    True))

    return targets


def check_target(sql_path, expected_dir, base):
    """Missing echoed lines for one test, or None when it is unmodelled."""
    sql_text = _read(sql_path)
    if is_unmodelled(sql_text):
        return None
    echoed = echoed_lines(sql_text)
    best = None
    for variant in _expected_variants(expected_dir, base):
        missing = missing_lines(_read(variant), echoed)
        if best is None or len(missing) < len(best):
            best = missing
    return best


def main(argv=None):
    parser = argparse.ArgumentParser(
        description='Check that expected outputs still echo every line of their .sql files.')
    parser.add_argument('--dir',
                        default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                             os.pardir),
                        help='oracle_test directory (default: the parent of this script)')
    parser.add_argument('--all', action='store_true',
                        help='also check tests that no schedule runs; drift '
                             'found there is reported but does not fail the '
                             'check')
    args = parser.parse_args(argv)

    root = os.path.abspath(args.dir)
    targets = collect_targets(root, args.all)
    drift = 0
    unscheduled_drift = 0
    skipped = 0
    for sql_path, expected_dir, base, scheduled in targets:
        missing = check_target(sql_path, expected_dir, base)
        if missing is None:
            skipped += 1
            continue
        if not missing:
            continue
        if scheduled:
            drift += 1
        else:
            unscheduled_drift += 1
        print('%s: %d echoed line(s) missing from expected output:' %
              (os.path.relpath(sql_path, root), len(missing)))
        for line in missing:
            print('    %s' % line)

    if unscheduled_drift:
        print('%d unscheduled test(s) with drift; no schedule runs them, so '
              'they do not fail the check' % unscheduled_drift)
    print('%d test(s) checked, %d unmodelled, %d with drift' %
          (len(targets), skipped, drift))
    return 1 if drift else 0


if __name__ == '__main__':
    sys.exit(main())
