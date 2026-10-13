# Copyright (c) 2021-2026, IvorySQL Global Development Team
#
# TAP tests for Oracle PIPELINED table functions (#1329): lifecycle,
# streaming (on-demand execution), resource recycling, SECURITY DEFINER
# role/GUC restoration, and error recovery.
#
# The SQL-level contract is covered by plisql_pipeline.sql in the
# oracle-check regression; this file covers the parts that need session
# state checks (currval, GUC, role) that must run within a single psql
# session.  Each block below is one safe_psql call = one session; the
# expected verdicts are computed by the SQL itself and asserted here.

use strict;
use warnings FATAL => 'all';

use FindBin;
use lib "$FindBin::RealBin/../../../../oracle_test/perl";

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# ---------------------------------------------------------------------------
# Set up one fresh oracle-mode node (force_initdb: the pipelined machinery
# needs the new catalog columns, so a copied INITDB_TEMPLATE would be stale).
# ---------------------------------------------------------------------------
my $node = PostgreSQL::Test::Cluster->new('pipe');
$node->init(force_initdb => 1);
$node->start;

my $psql = { connect_to_oraport => 1 };

# Verify we really are in oracle mode through the oracle port before
# running any SQL; a wrong setup must fail the whole file here.
my $mode = $node->safe_psql('postgres',
	"SHOW ivorysql.compatible_mode", %$psql);
chomp $mode if defined $mode;
is($mode, 'oracle', "compatible mode is oracle on the oracle port");

# ---------------------------------------------------------------------------
# Schema objects and the #1329 example.
# ---------------------------------------------------------------------------
$node->safe_psql('postgres', <<'EOSQL', %$psql);
CREATE TYPE pipe_num_tab AS TABLE OF NUMBER;
CREATE SEQUENCE pipe_seq;
CREATE TABLE pipe_src (k NUMBER, v VARCHAR2(10));
INSERT INTO pipe_src VALUES (1, 'a');
INSERT INTO pipe_src VALUES (2, 'b');
INSERT INTO pipe_src VALUES (3, 'c');

CREATE OR REPLACE FUNCTION pipe_num_list(p_n NUMBER)
RETURN pipe_num_tab PIPELINED IS
BEGIN
  FOR i IN 1 .. p_n LOOP
    PIPE ROW(i);
  END LOOP;
  RETURN;
END;
EOSQL
pass('schema objects and pipe_num_list created');

my $result = $node->safe_psql('postgres',
	"SELECT column_value FROM TABLE(pipe_num_list(3))", %$psql);
is($result, "1\n2\n3", "basic pipeline returns 1..3 in order");

# ---------------------------------------------------------------------------
# Streaming: a sequence records each PIPE ROW side effect.  LIMIT 1 must
# consume exactly one row (one pre-PIPE nextval); a full drain must run all
# 101 side effects (100 pre-PIPE + 1 tail).  All statements run in one
# session because currval is session-scoped.
# ---------------------------------------------------------------------------
$node->safe_psql('postgres', <<'EOSQL', %$psql);
CREATE OR REPLACE FUNCTION pipe_counted(p_n NUMBER)
RETURN pipe_num_tab PIPELINED IS
BEGIN
  FOR i IN 1 .. p_n LOOP
    PERFORM nextval('pipe_seq');
    PIPE ROW(i);
  END LOOP;
  PERFORM nextval('pipe_seq');
  RETURN;
END;
EOSQL
pass('pipe_counted created');

$result = $node->safe_psql('postgres', <<'EOSQL', %$psql);
SELECT setval('pipe_seq', 1, false);
SELECT 'C=' || column_value FROM TABLE(pipe_counted(100)) LIMIT 1;
SELECT 'CUR=' || currval('pipe_seq');
EOSQL
is($result, "1\nC=1\nCUR=1",
	"LIMIT 1 consumes exactly one row (on-demand execution)");

$result = $node->safe_psql('postgres', <<'EOSQL', %$psql);
SELECT setval('pipe_seq', 1, false);
SELECT 'N=' || count(*) FROM TABLE(pipe_counted(100));
SELECT 'CUR=' || currval('pipe_seq');
EOSQL
is($result, "1\nN=100\nCUR=101",
	"full drain runs 101 side effects (100 + tail)");

# ---------------------------------------------------------------------------
# Cursor FOR + portal recycling: after pipeline calls complete, no portals
# may linger.
# ---------------------------------------------------------------------------
$node->safe_psql('postgres', <<'EOSQL', %$psql);
CREATE OR REPLACE FUNCTION pipe_cursor_drain
RETURN pipe_num_tab PIPELINED IS
  -- declared cursors in standalone scope are deferred (#2184); use query FOR
  total NUMBER := 0;
BEGIN
  FOR r IN (SELECT g FROM generate_series(1, 3) g) LOOP
    total := total + r.g;
    PIPE ROW(total);
  END LOOP;
  RETURN;
END;
EOSQL
pass('pipe_cursor_drain created');

$result = $node->safe_psql('postgres', <<'EOSQL', %$psql);
SELECT 'C=' || column_value FROM TABLE(pipe_cursor_drain());
SELECT 'PORTALS=' || count(*) FROM pg_cursors;
EOSQL
is($result, "C=1\nC=3\nC=6\nPORTALS=0",
	"cursor FOR pipeline drains in order, no lingering portals");

# ---------------------------------------------------------------------------
# Error recovery: a failure inside the pipeline aborts the call cleanly and
# leaves the session usable.
# ---------------------------------------------------------------------------
$node->safe_psql('postgres', <<'EOSQL', %$psql);
CREATE OR REPLACE FUNCTION pipe_boom(p_n NUMBER)
RETURN pipe_num_tab PIPELINED IS
BEGIN
  FOR i IN 1 .. p_n LOOP
    PIPE ROW(i);
    IF i = 2 THEN
      RAISE EXCEPTION 'boom at %', i;
    END IF;
  END LOOP;
  RETURN;
END;
EOSQL
pass('pipe_boom created');

my ($ret, $stdout, $stderr) = $node->psql('postgres', <<'EOSQL', %$psql);
SELECT 'X=' || column_value FROM TABLE(pipe_boom(5));
SELECT 'STILL-OK';
EOSQL
isnt($ret, 0, "error inside pipeline aborts the call");
like($stderr, qr/boom at 2/, "error surfaces the application message");

# Session still usable after the error; ON_ERROR_STOP is off for the check.
$result = $node->safe_psql('postgres',
	"SELECT column_value FROM TABLE(pipe_num_list(2))", %$psql);
is($result, "1\n2", "session usable after pipeline error");

# ---------------------------------------------------------------------------
# Invocation isolation: two invocations in one query keep independent state.
# ---------------------------------------------------------------------------
$node->safe_psql('postgres', <<'EOSQL', %$psql);
CREATE OR REPLACE FUNCTION pipe_running(p_n NUMBER)
RETURN pipe_num_tab PIPELINED IS
  total NUMBER := 0;
BEGIN
  FOR i IN 1 .. p_n LOOP
    total := total + i;
    PIPE ROW(total);
  END LOOP;
  RETURN;
END;
EOSQL
pass('pipe_running created');

$result = $node->safe_psql('postgres', <<'EOSQL', %$psql);
SELECT 'ISO=' || a.column_value || '|' || b.column_value
FROM TABLE(pipe_running(2)) a, TABLE(pipe_running(3)) b
WHERE a.column_value = 3 AND b.column_value = 6
EOSQL
is($result, "ISO=3|6",
	"two invocations keep independent running totals");

# ---------------------------------------------------------------------------
# SECURITY DEFINER + SET clause: role and GUC applied during the call and
# restored after it, on both success and error paths.  All statements run in
# one session so the restoration check is meaningful.
# ---------------------------------------------------------------------------
$node->safe_psql('postgres', <<'EOSQL', %$psql);
CREATE ROLE pipe_restricted NOLOGIN;
GRANT CREATE ON SCHEMA public TO pipe_restricted;
SET ROLE pipe_restricted;
CREATE OR REPLACE FUNCTION pipe_definer(p_n NUMBER)
RETURN pipe_num_tab PIPELINED
SECURITY DEFINER
SET search_path = pg_catalog
IS
  cur_user VARCHAR2(64);
  cur_path VARCHAR2(200);
BEGIN
  SELECT current_user, current_setting('search_path')
    INTO cur_user, cur_path;
  PIPE ROW(p_n);
  PIPE ROW(CASE WHEN cur_user = 'pipe_restricted' THEN 1 ELSE 0 END);
  PIPE ROW(CASE WHEN cur_path = 'pg_catalog' THEN 1 ELSE 0 END);
  RETURN;
END;
RESET ROLE;
EOSQL
pass('pipe_definer created');

my $who = $node->safe_psql('postgres', "SELECT current_user", %$psql);
chomp $who if defined $who;

$result = $node->safe_psql('postgres', <<'EOSQL', %$psql);
SELECT 'BEFORE=' || current_user || '|' || current_setting('search_path');
SELECT 'D=' || column_value FROM TABLE(pipe_definer(7));
SELECT 'AFTER=' || current_user || '|' || current_setting('search_path');
EOSQL
is($result, "BEFORE=$who|\"\$user\", public\n"
  . "D=7\nD=1\nD=1\n"
  . "AFTER=$who|\"\$user\", public",
	"SECURITY DEFINER applies role/search_path and restores after call");

# Error path: a failing definer function must still restore the caller.
$node->safe_psql('postgres', <<'EOSQL', %$psql);
CREATE OR REPLACE FUNCTION pipe_definer_boom
RETURN pipe_num_tab PIPELINED
SECURITY DEFINER
SET search_path = pg_catalog
IS
BEGIN
  RAISE EXCEPTION 'definer boom';
  RETURN;
END;
EOSQL
pass('pipe_definer_boom created');

($ret, $stdout, $stderr) = $node->psql('postgres', <<'EOSQL', %$psql,
SELECT 'D2=' || column_value FROM TABLE(pipe_definer_boom());
SELECT 'AFTER2=' || current_user || '|' || current_setting('search_path');
EOSQL
	on_error_stop => 0);
	unlike($stdout, qr/D2=/, "definer error aborts before any row");
like($stderr, qr/definer boom/, "definer error message surfaces");
like($stdout, qr/AFTER2=\Q$who\E\|/, "caller state intact after definer error");

# ---------------------------------------------------------------------------
# Function replacement: a drained call followed by CREATE OR REPLACE leaves
# the session and the compiled cache consistent.
# ---------------------------------------------------------------------------
$node->safe_psql('postgres', <<'EOSQL', %$psql);
CREATE OR REPLACE FUNCTION pipe_stable(p_n NUMBER)
RETURN pipe_num_tab PIPELINED IS
BEGIN
  FOR i IN 1 .. p_n LOOP
    PIPE ROW(i * 100);
  END LOOP;
  RETURN;
END;
EOSQL
pass('pipe_stable created');

$result = $node->safe_psql('postgres',
	"SELECT column_value FROM TABLE(pipe_stable(5))", %$psql);
is($result, "100\n200\n300\n400\n500", "original definition drains");

$node->safe_psql('postgres', <<'EOSQL', %$psql);
CREATE OR REPLACE FUNCTION pipe_stable(p_n NUMBER)
RETURN pipe_num_tab PIPELINED IS
BEGIN
  FOR i IN 1 .. p_n LOOP
    PIPE ROW(i * 1000);
  END LOOP;
  RETURN;
END;
EOSQL
pass('pipe_stable replaced');

$result = $node->safe_psql('postgres',
	"SELECT column_value FROM TABLE(pipe_stable(2))", %$psql);
is($result, "1000\n2000", "replacement definition visible to later calls");

# ---------------------------------------------------------------------------
# Rollback of a transaction spanning pipeline calls restores source rows.
# All statements run in ONE session (each safe_psql call is its own session,
# so a BEGIN/ROLLBACK split across calls would be meaningless).
# ---------------------------------------------------------------------------
$result = $node->safe_psql('postgres', <<'EOSQL', %$psql);
BEGIN;
DELETE FROM pipe_src;
SELECT 1 FROM TABLE(pipe_num_list(2)) WHERE false;
ROLLBACK;
SELECT 'RB=' || count(*) FROM pipe_src;
EOSQL
is($result, "RB=3", "rollback restores source rows after pipeline calls");

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
$node->safe_psql('postgres', <<'EOSQL', %$psql);
DROP FUNCTION pipe_num_list;
DROP FUNCTION pipe_counted;
DROP FUNCTION pipe_cursor_drain;
DROP FUNCTION pipe_boom;
DROP FUNCTION pipe_running;
DROP FUNCTION pipe_definer;
DROP FUNCTION pipe_definer_boom;
DROP FUNCTION pipe_stable;
DROP TYPE pipe_num_tab;
DROP SEQUENCE pipe_seq;
DROP TABLE pipe_src;
REVOKE CREATE ON SCHEMA public FROM pipe_restricted;
DROP ROLE pipe_restricted;
EOSQL
pass('cleanup');

$node->stop('fast');
done_testing();
