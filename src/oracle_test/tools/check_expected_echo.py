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
# regress/serial_schedule plus the modules that modules/Makefile builds.  Pass
# --all to also walk the remaining sql/expected pairs, which may include tests
# that no schedule runs and module directories that the build skips; their
# drift is reported but does not fail the check.  A test whose expected file is
# missing altogether is always an error, because pg_regress cannot pass it on
# any machine.

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


# psql's ECHO setting decides whether an input line reaches results/.  "all"
# echoes everything and "none" stops echoing, so both can be followed line by
# line; "queries" and "errors" print the query buffer at a different point, and
# a toggle inside an inactive \if branch never runs, so those files are left
# unmodelled.  \if without a toggle, and \echo/\gexec, do not change the echo
# of input lines: MainLoop echoes a line before it decides whether the branch
# is active, and the text \echo or \gexec produce is extra output rather than
# a replacement for the echoed input line.
_ECHO_SETTING = re.compile(r'\\(set|unset)\s+ECHO\b\s*(\S*)', re.IGNORECASE)
_IF_COMMAND = re.compile(r'\\if\b', re.IGNORECASE)

# Returned by check_target() when the expected directory holds no file for the
# test at all.  That is different from an unmodelled test: an expected file
# that does not exist makes pg_regress fail on every platform, so the caller
# has to count it as drift rather than skipping the test.
MISSING_EXPECTED = object()


def echoed_lines(sql_text):
    r"""Lines of a .sql file that psql -a copies into the results file.

    With ECHO all psql prints every nonempty input line as it is read,
    meta-commands included; blank lines, the contents of a COPY ... FROM stdin
    block (its data plus the terminating "\." line), and lines read while
    ECHO is none are left out.  \set ECHO none and \set ECHO all are followed
    so the suppressed window is skipped; the toggle line itself is echoed
    according to the state before it takes effect, exactly as psql does.

    A single input line can hold more than one command string separated by
    "\;", and a test may start two COPY ... FROM stdin blocks on one line, so
    each occurrence opens its own data block.  The number of terminators that
    still have to be skipped is therefore counted rather than tracked as a
    simple on/off flag.
    """
    echoed = []
    skip_blocks = 0
    echo_enabled = True
    for raw_line in sql_text.splitlines():
        line = raw_line.rstrip()
        stripped = line.lstrip()
        if skip_blocks:
            if stripped == r'\.':
                skip_blocks -= 1
            continue
        if not stripped:
            continue
        if stripped == r'\.':
            # A terminator never reaches results/ as input text.
            continue
        count = len(_COPY_FROM_STDIN.findall(
            _strip_comments_and_literals(stripped)))
        if count:
            if echo_enabled:
                echoed.append(line)
            skip_blocks = count
            continue
        if echo_enabled:
            echoed.append(line)
        setting = _ECHO_SETTING.match(stripped)
        if setting:
            if setting.group(1).lower() == 'unset':
                echo_enabled = False
            else:
                value = setting.group(2).strip().strip("'\"").lower()
                if value == 'none':
                    echo_enabled = False
                elif value == 'all':
                    echo_enabled = True
    return echoed


def is_unmodelled(sql_text):
    """True when the echo state cannot be followed statically."""
    settings = []
    conditional = False
    for raw_line in sql_text.splitlines():
        stripped = raw_line.lstrip()
        if _IF_COMMAND.match(stripped):
            conditional = True
        match = _ECHO_SETTING.match(stripped)
        if match:
            settings.append(match)
    if not settings:
        return False
    if conditional:
        # A toggle inside an inactive branch is not executed, so the state
        # after the branch depends on the condition.
        return True
    for match in settings:
        if match.group(1).lower() == 'unset':
            continue        # \unset ECHO behaves like \set ECHO none
        value = match.group(2).strip().strip("'\"").lower()
        if value not in ('all', 'none'):
            return True
    return False


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


# Only the plain "SUBDIRS =" assignment is read; "SUBDIRS += ..." lives inside
# configure conditionals (openssl, C++, injection points, LDAP) whose outcome a
# static reader cannot know.
_SUBDIRS_ASSIGNMENT = re.compile(r'^SUBDIRS\s*(\+=|:=|=)\s*(.*)$')


def _makefile_lines(makefile_text):
    """Logical makefile lines: comments removed, continuations joined."""
    lines = []
    pending = ''
    for raw_line in makefile_text.splitlines():
        line = raw_line.split('#', 1)[0].rstrip()
        if pending:
            line = pending + ' ' + line.lstrip()
        if line.endswith('\\'):
            pending = line[:-1].rstrip()
            continue
        pending = ''
        lines.append(line)
    if pending:
        lines.append(pending)
    return lines


def _module_subdirs(modules_dir):
    """Module directories that modules/Makefile always builds, or None.

    src/oracle_test/modules/Makefile is the authority for which module tests a
    normal run executes.  It lists the modules in a single SUBDIRS assignment
    spread over continuation lines, so the raw text is folded into logical
    lines before the assignment is read.  A directory that exists in the tree
    but is not listed (nbtree, for example) is never built, produces no
    results file, and checking it would only report noise.

    Conditional "SUBDIRS +=" additions depend on how the tree was configured,
    so they are not part of the strict set; --all still walks them and treats
    their drift as non-fatal, exactly like a test that no schedule runs.
    None means the list could not be determined, in which case the caller
    falls back to every directory in the tree so nothing is silently skipped.
    """
    try:
        makefile_text = _read(os.path.join(modules_dir, 'Makefile'))
    except OSError:
        return None
    names = set()
    found = False
    for line in _makefile_lines(makefile_text):
        match = _SUBDIRS_ASSIGNMENT.match(line.strip())
        if not match or match.group(1) != '=':
            continue
        found = True
        names.update(match.group(2).split())
    return names if found else None


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
    if not os.path.isdir(expected_dir):
        return variants
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
        built_modules = _module_subdirs(modules)
        for module in sorted(os.listdir(modules)):
            module_sql = os.path.join(modules, module, 'sql')
            module_expected = os.path.join(modules, module, 'expected')
            # A module that lost its expected/ directory is still collected:
            # check_target() reports the missing output instead of the module
            # disappearing from the check.
            if not os.path.isdir(module_sql):
                continue
            # A module that the Makefile does not descend into is not part of
            # a normal run; --all still looks at it, flagged unscheduled so
            # that drift there cannot fail the check.
            is_built = built_modules is None or module in built_modules
            if not is_built and not include_all:
                continue
            for name in sorted(os.listdir(module_sql)):
                if name.endswith('.sql'):
                    targets.append((os.path.join(module_sql, name),
                                    module_expected, name[:-len('.sql')],
                                    is_built))

    return targets


def check_target(sql_path, expected_dir, base):
    """Missing echoed lines for one test.

    None means the echo model cannot follow the script, and MISSING_EXPECTED
    means the test has no expected output at all.  The missing-file case is
    checked before the echo model because it is a failure no matter how psql
    behaves: pg_regress has nothing to compare the results with.
    """
    variants = _expected_variants(expected_dir, base)
    if not variants:
        return MISSING_EXPECTED
    sql_text = _read(sql_path)
    if is_unmodelled(sql_text):
        return None
    echoed = echoed_lines(sql_text)
    best = None
    for variant in variants:
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
    no_expected = 0
    for sql_path, expected_dir, base, scheduled in targets:
        missing = check_target(sql_path, expected_dir, base)
        if missing is None:
            skipped += 1
            continue
        if missing is MISSING_EXPECTED:
            no_expected += 1
            if scheduled:
                drift += 1
            else:
                unscheduled_drift += 1
            print('%s: no %s.out in %s' %
                  (os.path.relpath(sql_path, root), base,
                   os.path.relpath(expected_dir, root)))
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
    print('%d test(s) checked, %d unmodelled, %d without expected output, '
          '%d with drift' % (len(targets), skipped, no_expected, drift))
    return 1 if drift else 0


if __name__ == '__main__':
    sys.exit(main())
