# Copyright 2026 IvorySQL Global Development Team
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('dbms_sql');
$node->init;
$node->start;
my $db = 'ivorysql';
$node->safe_psql($db,
	'CREATE TABLE dbms_sql_modes (mode text, result numeric)');
for my $mode ('normal', 'interchange', 'lowercase')
{
	my ($out, $err);
	my $status = $node->psql(
		$db, qq{
SET ivorysql.identifier_case_switch = '$mode';
DECLARE
  c INTEGER := dbms_sql.open_cursor();
  n NUMBER;
  ignored INTEGER;
BEGIN
  dbms_sql.parse(c, 'SELECT :v FROM dual', dbms_sql.native);
  dbms_sql.bind_variable(c, 'v', 12);
  dbms_sql.define_column(c, 1, n);
  ignored := dbms_sql.execute(c);
  ignored := dbms_sql.fetch_rows(c);
  dbms_sql.column_value(c, 1, n);
  INSERT INTO dbms_sql_modes VALUES ('$mode', n);
  dbms_sql.close_cursor(c);
END;
},
		connect_to_oraport => 1,
		stdout => \$out,
		stderr => \$err);
	is($status, 0, "public package workflow works in $mode identifier mode")
	  or diag($err);
	is( $node->safe_psql(
			$db, "SELECT result FROM dbms_sql_modes WHERE mode = '$mode'"),
		'12',
		"public execute and integer binding return the correct value in $mode mode"
	);
}
my $a = $node->background_psql($db);
my $b = $node->background_psql($db);
for my $session ($a, $b)
{
	$session->query_safe('SET ivorysql.compatible_mode = oracle');
	$session->query_safe('SET ivorysql.identifier_case_switch = normal');
}
is($a->query_safe('SELECT sys.ora_dbms_sql_open_cursor(1)'),
	'1', 'first session opens handle 1');
is($b->query_safe('SELECT sys.ora_dbms_sql_open_cursor(1)'),
	'1', 'second session has an independent handle namespace');
for my $pair ([ $a, 111 ], [ $b, 222 ])
{
	my ($session, $value) = @$pair;
	$session->query_safe(
		"SELECT sys.ora_dbms_sql_parse(1, 'SELECT :v FROM dual', 1)");
	$session->query_safe(
		"SELECT sys.ora_dbms_sql_bind_variable(1, 'v', $value\::numeric)");
	$session->query_safe(
		'SELECT sys.ora_dbms_sql_define_column(1, 1, 0::numeric, NULL)');
	$session->query_safe('BEGIN');
	is($session->query_safe('SELECT sys.ora_dbms_sql_execute(1)'),
		'0', "session executes SELECT $value");
}
# Rebind one session after EXECUTE. The live portal must retain its own values.
$a->query_safe("SELECT sys.ora_dbms_sql_bind_variable(1, 'v', 999::numeric)");
for my $pair ([ $a, 111 ], [ $b, 222 ])
{
	my ($session, $value) = @$pair;
	is($session->query_safe('SELECT sys.ora_dbms_sql_fetch_rows(1)'),
		'1', 'fetch returns one row');
	is( $session->query_safe(
			'SELECT sys.ora_dbms_sql_column_value(1, 1, 0::numeric)'),
		"$value",
		'result parameters are copied and isolated');
	$session->query_safe('COMMIT');
}

# Releasing a handle also drops its portal. No session result survives in
# pg_cursors, and a new handle is not confused with the previously closed one.
$a->query_safe('SELECT sys.ora_dbms_sql_close_cursor(1)');
is($a->query_safe('SELECT sys.ora_dbms_sql_is_open(1)'),
	'f', 'closed handle is no longer open');
is($a->query_safe('SELECT sys.ora_dbms_sql_open_cursor(1)'),
	'2', 'handle IDs are not reused');
$a->query_safe(
	"SELECT sys.ora_dbms_sql_parse(2, 'SELECT 1 AS n UNION ALL SELECT 2 FROM pg_sleep(60)', 1)"
);
$a->query_safe(
	'SELECT sys.ora_dbms_sql_define_column(2, 1, 0::numeric, NULL)');
$a->query_safe("SET statement_timeout = '2s'");
$a->query_safe('BEGIN');
is($a->query_safe('SELECT sys.ora_dbms_sql_execute(2)'),
	'0', 'EXECUTE does not materialize an entire SELECT');
is($a->query_safe('SELECT sys.ora_dbms_sql_fetch_rows(2)'),
	'1', 'first row is available without executing a later sleeping branch');
is( $a->query_safe('SELECT sys.ora_dbms_sql_column_value(2, 1, 0::numeric)'),
	'1', 'streamed first value is correct');
$a->query_safe('SELECT sys.ora_dbms_sql_close_cursor(2)');
is( $a->query_safe(
		q{SELECT count(*) FROM pg_cursors WHERE name LIKE '<unnamed portal%'}
	),
	'0',
	'close releases result portals');
$a->query_safe('COMMIT');
$a->quit;
$b->quit;

$node->safe_psql(
	$db, q{
CREATE TABLE dbms_sql_toast AS
SELECT string_agg(md5(g::text), '') AS payload FROM generate_series(1,1000) g;
});
my $toast = $node->background_psql($db);
$toast->query_safe('SET ivorysql.compatible_mode = oracle');
$toast->query_safe('SELECT sys.ora_dbms_sql_open_cursor(1)');
$toast->query_safe(
	"SELECT sys.ora_dbms_sql_parse(1, 'SELECT payload FROM dbms_sql_toast', 1)"
);
$toast->query_safe(
	"SELECT sys.ora_dbms_sql_define_column(1, 1, ''::text, 32000)");
$toast->query_safe('BEGIN');
$toast->query_safe('SELECT sys.ora_dbms_sql_execute(1)');
$toast->query_safe('SELECT sys.ora_dbms_sql_fetch_rows(1)');
is( $toast->query_safe(
		"SELECT length(sys.ora_dbms_sql_column_value(1, 1, ''::text))"),
	'32000',
	'a TOASTed row survives SPI cleanup between fetch and column access');
$toast->query_safe('SELECT sys.ora_dbms_sql_close_cursor(1)');
$toast->query_safe('COMMIT');
$toast->quit;

# Package code is not SECURITY DEFINER: an unprivileged user cannot use the
# helpers to bypass table ACLs, even when opening/parsing succeeds.
$node->safe_psql(
	$db, q{
CREATE TABLE dbms_sql_secret (n int);
INSERT INTO dbms_sql_secret VALUES (42);
CREATE ROLE dbms_sql_reader;
});
my ($stdout, $stderr);
my $rc = $node->psql(
	$db, q{
SET ivorysql.compatible_mode = oracle;
SET ROLE dbms_sql_reader;
SELECT sys.ora_dbms_sql_open_cursor(1);
SELECT sys.ora_dbms_sql_parse(1, 'SELECT n FROM dbms_sql_secret', 1);
SELECT sys.ora_dbms_sql_execute(1);
},
	stdout => \$stdout,
	stderr => \$stderr);
is($rc, 3, 'unprivileged execution is rejected');
like(
	$stderr,
	qr/permission denied for table dbms_sql_secret/,
	'underlying relation ACL is enforced');
is($node->safe_psql($db, 'SELECT count(*) FROM dbms_sql_secret'),
	'1', 'failed execution leaves the server and data intact');

my $churn = $node->background_psql($db);
is( $churn->query_safe(
		q{SELECT count(sys.ora_dbms_sql_close_cursor(sys.ora_dbms_sql_open_cursor(1))) FROM generate_series(1,2000)}
	),
	'2000',
	'repeated open/close releases handles instead of reaching the limit');
is( $churn->query_safe(
		q{SELECT count(*) FROM pg_backend_memory_contexts WHERE name = 'DBMS_SQL cursor'}
	),
	'0',
	'closing all handles releases their session memory contexts');
$churn->quit;
$rc = $node->psql(
	$db, q{
CREATE TEMP TABLE held AS SELECT sys.ora_dbms_sql_open_cursor(1) c FROM generate_series(1,1024);
SELECT count(*) FROM held;
SELECT sys.ora_dbms_sql_open_cursor(1);
},
	stdout => \$stdout,
	stderr => \$stderr);
is($rc, 3, 'unclosed cursors reach a bounded session limit');
like(
	$stderr,
	qr/DBMS_SQL: cursor limit exceeded/,
	'cursor limit reports a controlled error');

# Terminating a session with an active cursor must clean up its executor.
my $orphan = $node->background_psql($db);
$orphan->query_safe('SET ivorysql.compatible_mode = oracle');
$orphan->query_safe('SELECT sys.ora_dbms_sql_open_cursor(1)');
$orphan->query_safe(
	"SELECT sys.ora_dbms_sql_parse(1, 'SELECT 1 FROM dual', 1)");
$orphan->query_safe('BEGIN');
$orphan->query_safe('SELECT sys.ora_dbms_sql_execute(1)');
$orphan->quit;
is($node->safe_psql($db, 'SELECT 1'),
	'1', 'session exit with an active cursor cleans up without crashing');
$node->stop;
done_testing();
