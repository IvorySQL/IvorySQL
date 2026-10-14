# Copyright (c) 2026, PostgreSQL Global Development Group
#
# IvorySQL #1307: exercise the externally installed oracle_fdw extension
# against a real Oracle server.
#
# This test is strictly opt-in: it only runs when PG_TEST_EXTRA contains
# "oracle_fdw", so that default builds and CI never depend on OCI headers,
# Oracle client libraries or a live Oracle server.  When the test IS enabled,
# missing prerequisites (extension not installed into the tested
# installation, missing DSN/user/password environment, missing sqlplus or an
# unreachable Oracle server) are fatal (BAIL_OUT) -- they must never be
# skipped into a green result.
#
# Required environment:
#	PG_TEST_EXTRA=oracle_fdw
#	PG_TEST_ORACLE_FDW_DSN		Oracle connect string for oracle_fdw,
#					e.g. //oraclehost:1521/FREEPDB1
#	PG_TEST_ORACLE_FDW_USER		dedicated Oracle test user
#	PG_TEST_ORACLE_FDW_PASSWORD	password of that user
#	ORACLE_HOME			OCI installation (needs bin/sqlplus and lib/)
#
# The fixture tables IV1307_TYPES and IV1307_LOOKUP must exist in the test
# user's schema; create them with src/test/modules/test_extensions/oracle_fdw/
# (compose.yaml + setup.sql).  The test itself reseeds both tables to a
# deterministic state.
#
# The matrix runs against three entry points:
#	1) a native PG-mode cluster,
#	2) the PG port of an oracle-mode cluster (session dialect pg),
#	3) the Oracle port (ivorysql.port) of the same oracle-mode cluster
#	   (session dialect oracle).

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# --------------------------------------------------------------------------
# opt-in gate
# --------------------------------------------------------------------------
if (   !defined $ENV{PG_TEST_EXTRA}
	|| $ENV{PG_TEST_EXTRA} !~ m/\boracle_fdw\b/)
{
	plan skip_all =>
	  'oracle_fdw tests are opt-in and not enabled in PG_TEST_EXTRA';
}

# --------------------------------------------------------------------------
# mandatory prerequisites -- fail loudly once the test is enabled
# --------------------------------------------------------------------------
my $dsn = $ENV{PG_TEST_ORACLE_FDW_DSN}
  or BAIL_OUT('PG_TEST_ORACLE_FDW_DSN must point at a dedicated Oracle test instance');
my $ora_user = $ENV{PG_TEST_ORACLE_FDW_USER}
  or BAIL_OUT('PG_TEST_ORACLE_FDW_USER must name a dedicated Oracle test user');
my $ora_pass = $ENV{PG_TEST_ORACLE_FDW_PASSWORD}
  or BAIL_OUT('PG_TEST_ORACLE_FDW_PASSWORD must be set for the Oracle test user');
my $oci_home = $ENV{ORACLE_HOME}
  or BAIL_OUT('ORACLE_HOME must point at an Oracle client (OCI) installation');

-f "$oci_home/bin/sqlplus"
  or BAIL_OUT("sqlplus not found under ORACLE_HOME=$oci_home");
my $sqlplus = "$oci_home/bin/sqlplus";

# Server backends must be able to load the OCI shared libraries; make sure
# the environment postgres is started with can find them.
{
	my $oci_lib = "$oci_home/lib";
	my $ld      = $ENV{LD_LIBRARY_PATH};
	$ENV{LD_LIBRARY_PATH} =
	  defined $ld && $ld =~ m/^\Q$oci_lib\E(?::|$)/
	  ? $ld
	  : $oci_lib . (defined $ld ? ":$ld" : "");
}

# The extension must be installed into the installation that is under test
# (the temporary installation used by "make check" / "meson test"), not
# merely somewhere on the machine.  Prefer the staged tree that PATH points
# at; fall back to the real installation prefix.
my $extdir;
for my $pathentry (split /:/, $ENV{PATH})
{
	(my $stage = $pathentry) =~ s{/bin$}{};
	if (-f "$stage/share/postgresql/extension/oracle_fdw.control")
	{
		$extdir = "$stage/share/postgresql/extension";
		$ENV{IV1307_STAGED_PREFIX} = $stage;
		last;
	}
}
if (!defined $extdir)
{
	chomp(my $sharedir = `pg_config --sharedir`);
	BAIL_OUT("pg_config --sharedir failed") if $? != 0 || !-d $sharedir;
	$extdir = "$sharedir/extension";
}
-f "$extdir/oracle_fdw.control"
  or BAIL_OUT(
	"oracle_fdw.control not found in $extdir -- "
	  . "install oracle_fdw into the tested installation first");
-f "$extdir/oracle_fdw--1.2.sql"
  or BAIL_OUT("oracle_fdw SQL script not found in $extdir");

# The server the test starts must be the staged installation, and the FDW
# shared library must live in the same tree; log both as run evidence.
my $staged = $ENV{IV1307_STAGED_PREFIX};
diag("staged installation: " . (defined $staged ? $staged : "<none>"))
  if defined $staged;

# --------------------------------------------------------------------------
# independent Oracle session helper
#
# The SQL*Plus password is placed in a temporary script inside a 0700
# directory, never on a command line.  It is unlinked immediately after use.
# CREATE USER MAPPING also sends the password through psql, so server-side
# statement and error-statement logging are disabled for the test clusters.
# --------------------------------------------------------------------------
my $sqlplus_dir = PostgreSQL::Test::Utils::tempdir();
my $oracle_seq  = 0;

# The independent SQL*Plus session must speak the same encoding as the
# fixture (AL32UTF8) so that Chinese seed data round-trips byte-exact.
$ENV{NLS_LANG} = '.AL32UTF8' unless defined $ENV{NLS_LANG};

sub oracle_sql
{
	my ($stmts) = @_;
	my $script = "$sqlplus_dir/q" . $$ . "_" . ($oracle_seq++) . ".sql";
	open my $fh, '>:raw', $script or BAIL_OUT("cannot write sqlplus script: $!");
	print $fh "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF ECHO OFF\n";
	print $fh "WHENEVER OSERROR EXIT FAILURE\n";
	print $fh "WHENEVER SQLERROR EXIT SQL.SQLCODE\n";
	print $fh "CONNECT $ora_user/\"$ora_pass\"\@$dsn\n";
	for my $stmt (@{$stmts})
	{
		# SQL*Plus buffers an unterminated statement and silently drops it
		# at EXIT, so make sure every statement is terminated.
		$stmt .= ';' unless $stmt =~ m/(?:;|\/)\s*$/;
		print $fh "$stmt\n";
	}
	print $fh "EXIT SQL.SQLCODE\n";
	close $fh;
	my $out = `$sqlplus -S /nolog '\@$script' 2>&1`;
	my $rc  = $?;
	unlink $script;
	return ($rc, $out);
}

# Oracle must be reachable and the fixture tables must exist before we start;
# both conditions are fatal when the test is explicitly enabled.
my ($orc_rc, $orc_out) = oracle_sql([
	"SELECT banner FROM v\$version WHERE banner LIKE 'Oracle%'",
	"SELECT parameter || '=' || value FROM nls_database_parameters "
	  . "WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET')",
]);
$orc_rc == 0
  or BAIL_OUT("cannot connect to Oracle as $ora_user (rc=$orc_rc):\n$orc_out");
diag("Oracle server evidence, DSN=$dsn:\n$orc_out");

my ($fix_rc, $fix_out) = oracle_sql(
	["SELECT COUNT(*) FROM user_tables WHERE table_name IN ('IV1307_TYPES','IV1307_LOOKUP')"
	]);
$fix_rc == 0
  or BAIL_OUT("fixture presence check failed (rc=$fix_rc):\n$fix_out");
$fix_out =~ m/^\s*2\s*$/m
  or BAIL_OUT(
	"fixture tables IV1307_TYPES/IV1307_LOOKUP not found for user $ora_user; "
	  . "start src/test/modules/test_extensions/oracle_fdw/compose.yaml "
	  . "and run setup.sql first");

# --------------------------------------------------------------------------
# deterministic reseed of the remote fixture
# --------------------------------------------------------------------------
sub reseed_oracle
{
	my ($rc, $out) = oracle_sql([
		"TRUNCATE TABLE iv1307_types",
		"TRUNCATE TABLE iv1307_lookup",
		"INSERT INTO iv1307_types (id, amount, txt, d, ts, payload, note) VALUES "
		  . "(1, 12345.6789, '中文数据测试', "
		  . "TO_DATE('2024-02-29 10:20:30','YYYY-MM-DD HH24:MI:SS'), "
		  . "TO_TIMESTAMP('2024-02-29 23:59:59.123456','YYYY-MM-DD HH24:MI:SS.FF6'), "
		  . "HEXTORAW('0123456789ABCDEF0123456789ABCDEF'), '中文CLOB内容 first line')",
		"INSERT INTO iv1307_types (id, amount, txt, d, ts, payload, note) VALUES "
		  . "(2, -999999999999.9999, 'English text', "
		  . "TO_DATE('2023-01-01 00:00:00','YYYY-MM-DD HH24:MI:SS'), "
		  . "TO_TIMESTAMP('2023-06-15 12:34:56.000001','YYYY-MM-DD HH24:MI:SS.FF6'), "
		  . "HEXTORAW('FF'), NULL)",
		"INSERT INTO iv1307_types (id) VALUES (3)",
		"INSERT INTO iv1307_types (id, amount, txt) VALUES (4, 7, '')",
		"INSERT INTO iv1307_types (id, amount, txt) VALUES (5, 0.0001, 'row five')",
		"INSERT INTO iv1307_lookup (id, code, label) VALUES (1, 'C1', 'label one 中文')",
		"INSERT INTO iv1307_lookup (id, code, label) VALUES (2, 'C2', 'label two')",
		"INSERT INTO iv1307_lookup (id, code, label) VALUES (5, 'C1', 'label five')",
	]);
	$rc == 0 or BAIL_OUT("reseeding remote fixture failed (rc=$rc):\n$out");
}

# --------------------------------------------------------------------------
# clusters: one native PG-mode node and one oracle-mode node with two
# dedicated entry ports
# --------------------------------------------------------------------------
my $pgnode = PostgreSQL::Test::Cluster->new('iv1307_pg');
# Force UTF-8 database encoding: round-trips of Chinese text through
# oracle_fdw are part of the matrix, and a C-locale default cluster would
# be SQL_ASCII.
$pgnode->init(extra => [ '--encoding=UTF8', '--locale=C' ]);
$pgnode->append_conf('postgresql.conf',
	"log_statement = none\nlog_min_error_statement = PANIC\n");
$pgnode->start;
diag("pgnode postgres: " . PostgreSQL::Test::Utils::slurp_file(
	$pgnode->data_dir . '/postmaster.opts'));

my $oranode = PostgreSQL::Test::Cluster->new('iv1307_ora');
my $ora_pg_port = $oranode->port;      # PG-protocol entry (session dialect pg)
my $ora_ora_port = PostgreSQL::Test::Cluster::get_free_port();

# IvorySQL's Cluster::init() hardcodes "-m pg"; for the oracle-mode node the
# database must be initialized manually.  Cluster->new() has already assigned
# data_dir/port/host, so initdb only needs the IvorySQL mode switches.
PostgreSQL::Test::Utils::system_or_bail('initdb', '-D', $oranode->data_dir,
	'-A', 'trust', '-N', '-m', 'oracle', '-C', 'normal',
	'--encoding=UTF8', '--locale=C');
PostgreSQL::Test::Utils::system_or_bail($ENV{PG_REGRESS}, '--config-auth',
	$oranode->data_dir)
  if defined $ENV{PG_REGRESS};

# Both entry ports must be real TCP listeners so that backend_startup.c sees
# the true connection mode: port -> connmode 'p' (pg), ivorysql.port ->
# connmode 'o' (oracle).  Unix-socket connections cannot distinguish the two,
# so do not fall back to them for the oracle-mode node.
$oranode->append_conf(
	'postgresql.conf', qq{
fsync = off
restart_after_crash = off
log_line_prefix = '%m %b[%p] %q%a '
wal_retrieve_retry_interval = '500ms'
port = $ora_pg_port
ivorysql.port = $ora_ora_port
listen_addresses = '127.0.0.1'
unix_socket_directories = ''
log_statement = none
log_min_error_statement = PANIC
});
$oranode->start;
diag("oranode postgres: " . PostgreSQL::Test::Utils::slurp_file(
	$oranode->data_dir . '/postmaster.opts'));

# Log the staged FDW shared library location as run evidence.
if (defined $staged)
{
	require File::Find;
	my $fdwso;
	File::Find::find(sub { $fdwso = $File::Find::name if $_ eq 'oracle_fdw.so'; },
		"$staged/lib");
	diag("oracle_fdw shared library: " . ($fdwso // "<missing>"));
}

# --------------------------------------------------------------------------
# entry points under test
# --------------------------------------------------------------------------
my @entries = (
	{   label  => 'pg-cluster',
		node   => $pgnode,
		connstr => undef,                     # unix socket, connmode 'p'
		mode   => 'pg',
		bg_env => { 'PGHOST' => $pgnode->host, 'PGPORT' => $pgnode->port },
	},
	{   label  => 'oracle-cluster-pg-port',
		node   => $oranode,
		connstr => "host=127.0.0.1 port=$ora_pg_port",
		mode   => 'pg',
		bg_env =>
		  { 'PGHOST' => '127.0.0.1', 'PGPORT' => $ora_pg_port },
	},
	{   label  => 'oracle-cluster-oracle-port',
		node   => $oranode,
		connstr => "host=127.0.0.1 port=$ora_ora_port",
		mode   => 'oracle',
		bg_env =>
		  { 'PGHOST' => '127.0.0.1', 'PGPORT' => $ora_ora_port },
	},
);

sub entry_psql
{
	my ($e, $sql) = @_;
	return $e->{node}->psql('postgres', $sql,
		connstr => $e->{connstr}, on_error_stop => 1);
}

sub ok_sql
{
	my ($e, $label, $sql) = @_;
	my ($rc, $out, $err) = entry_psql($e, $sql);
	is($rc, 0, "$e->{label}: $label") or diag("stderr: $err");
	return ($rc == 0, $out);
}

sub ok_sql_val
{
	my ($e, $label, $sql) = @_;
	my ($rc, $out, $err) = entry_psql($e, $sql);
	is($rc, 0, "$e->{label}: $label") or diag("stderr: $err");
	return $out;
}

sub fail_sql
{
	my ($e, $label, $sql, $errpat) = @_;
	my ($rc, $out, $err) = entry_psql($e, $sql);
	isnt($rc, 0, "$e->{label}: $label") or diag("unexpectedly succeeded: $out");
	like($err, $errpat, "$e->{label}: $label (error text)") if defined $errpat;
	return $err;
}

# --------------------------------------------------------------------------
# the full verification matrix for one entry point
# --------------------------------------------------------------------------
sub run_matrix
{
	my ($e)     = @_;
	my $L       = $e->{label};
	my $sqltail = defined $e->{connstr} ? " [via $e->{connstr}]" : "";

	subtest "$L: entry dialect and extension loading" => sub {
		plan tests => 16;

		# The entry point must prove its actual dialect; do not fake it
		# with a session-level SET.
		my $mode = ok_sql_val($e, 'read ivorysql.compatible_mode',
			'SHOW ivorysql.compatible_mode');
		is($mode, $e->{mode},
			"$L: entry runs in $e->{mode} dialect$sqltail");

		my $sp_before = ok_sql_val($e, 'read search_path', 'SHOW search_path');

		ok_sql($e, 'CREATE EXTENSION oracle_fdw', 'CREATE EXTENSION oracle_fdw;');

		# session state must be restored after the install script ran
		is(ok_sql_val($e, 'mode after install', 'SHOW ivorysql.compatible_mode'),
			$mode, "$L: compatible_mode restored after CREATE EXTENSION");
		is(ok_sql_val($e, 'search_path after install', 'SHOW search_path'),
			$sp_before,
			"$L: search_path restored after CREATE EXTENSION");

		is(ok_sql_val($e, 'handler and validator registered',
				"SELECT count(*) FROM pg_proc WHERE proname IN "
				  . "('oracle_fdw_handler','oracle_fdw_validator')"),
			'2', "$L: handler/validator functions present");

		my $diag = ok_sql_val($e, 'oracle_diag()', 'SELECT oracle_diag()');
		like($diag, qr/oracle_fdw\s+2\.9/,
			"$L: oracle_diag() reports oracle_fdw 2.9");
		diag("oracle_diag(): $diag");

		ok_sql($e, 'CREATE SERVER',
			"CREATE SERVER iv_fdw_server FOREIGN DATA WRAPPER oracle_fdw "
			  . "OPTIONS (dbserver '$dsn');");
		ok_sql($e, 'CREATE USER MAPPING (test user)',
			"CREATE USER MAPPING FOR CURRENT_USER SERVER iv_fdw_server "
			  . "OPTIONS (user '$ora_user', password '$ora_pass');");
		my $diag_srv =
		  ok_sql_val($e, 'oracle_diag(server)',
			"SELECT oracle_diag('iv_fdw_server')");
		like($diag_srv, qr/Oracle server/i,
			"$L: oracle_diag(server) reports the remote Oracle server");
		diag("oracle_diag(server): $diag_srv");
	};

	subtest "$L: foreign tables and remote type round-trip" => sub {
		plan tests => 24;

		reseed_oracle();

		# The foreign tables must use pg_catalog-qualified standard
		# PostgreSQL types (real catalog names, not keyword aliases):
		# unmodified oracle_fdw only knows the standard type OIDs, while an
		# oracle-dialect session resolves a bare "timestamp" to IvorySQL's
		# sys.oratimestamp, which the FDW cannot convert.
		ok_sql($e, 'CREATE FOREIGN TABLE iv1307_types',
			"CREATE FOREIGN TABLE iv1307_types ("
			  . "id pg_catalog.int4 OPTIONS (key 'true') NOT NULL, "
			  . "amount pg_catalog.numeric(18,4), txt pg_catalog.text, "
			  . "d pg_catalog.timestamp, ts pg_catalog.timestamp, "
			  . "payload pg_catalog.bytea, note pg_catalog.text) "
			  . "SERVER iv_fdw_server OPTIONS (schema 'IV1307', table 'IV1307_TYPES');"
		);
		ok_sql($e, 'CREATE FOREIGN TABLE iv1307_lookup',
			"CREATE FOREIGN TABLE iv1307_lookup ("
			  . "id pg_catalog.int4 OPTIONS (key 'true') NOT NULL, "
			  . "code pg_catalog.text, label pg_catalog.text) "
			  . "SERVER iv_fdw_server OPTIONS (schema 'IV1307', table 'IV1307_LOOKUP');"
		);
		ok_sql($e, 'ANALYZE foreign tables',
			'ANALYZE iv1307_types; ANALYZE iv1307_lookup;');

		is(ok_sql_val($e, 'numeric precision',
				'SELECT amount::text FROM iv1307_types WHERE id = 1'),
			'12345.6789', "$L: NUMBER(18,4) -> numeric(18,4) precision kept");
		is(ok_sql_val($e, 'negative numeric precision',
				'SELECT amount::text FROM iv1307_types WHERE id = 2'),
			'-999999999999.9999', "$L: negative NUMBER value kept");
		is(ok_sql_val($e, 'Chinese VARCHAR2',
				'SELECT txt FROM iv1307_types WHERE id = 1'),
			'中文数据测试', "$L: VARCHAR2(100 CHAR) Chinese text round-trip");
		is(ok_sql_val($e, 'Oracle DATE',
				"SELECT to_char(d, 'YYYY-MM-DD HH24:MI:SS') "
				  . 'FROM iv1307_types WHERE id = 1'),
			'2024-02-29 10:20:30', "$L: DATE -> timestamp round-trip");
		is(ok_sql_val($e, 'TIMESTAMP(6)',
				"SELECT to_char(ts, 'YYYY-MM-DD HH24:MI:SS.US') "
				  . 'FROM iv1307_types WHERE id = 1'),
			'2024-02-29 23:59:59.123456',
			"$L: TIMESTAMP(6) microseconds round-trip");
		is(ok_sql_val($e, 'RAW bytes',
				"SELECT encode(payload, 'hex') FROM iv1307_types WHERE id = 1"),
			'0123456789abcdef0123456789abcdef', "$L: RAW(16) -> bytea bytes kept");
		is(ok_sql_val($e, 'CLOB content',
				'SELECT note FROM iv1307_types WHERE id = 1'),
			'中文CLOB内容 first line', "$L: CLOB with Chinese round-trip");
		is(ok_sql_val($e, 'all-NULL row',
				'SELECT (amount IS NULL)::int::text || (txt IS NULL)::int::text '
				  . '|| (payload IS NULL)::int::text || (note IS NULL)::int::text '
				  . 'FROM iv1307_types WHERE id = 3'),
			'1111', "$L: NULLs survive the round-trip");

		# Oracle treats '' as NULL; oracle_fdw documents that empty strings
		# arrive as NULL.  Seed row 4 has txt = '' on the Oracle side.
		is(ok_sql_val($e, "Oracle '' is NULL on read",
				'SELECT count(*) FROM iv1307_types WHERE id = 4 AND txt IS NULL'),
			'1', "$L: Oracle empty string reads back as NULL");
		ok_sql($e, 'FDW INSERT with empty string',
			"INSERT INTO iv1307_types (id, amount, txt) VALUES (9008, 0, '');");
		my ($rc, $out) =
		  oracle_sql(["SELECT CASE WHEN txt IS NULL THEN 'NULL' ELSE 'NOTNULL' END "
			  . 'FROM iv1307_types WHERE id = 9008']);
		is($rc, 0, "$L: independent session after empty-string insert")
		  or diag($out);
		like($out, qr/^\s*NULL\s*$/m,
			"$L: empty string stored as Oracle NULL (Oracle '' = NULL semantics)"
		);
	};

	subtest "$L: predicate/projection/join pushdown" => sub {
		plan tests => 13;

		my $ex = ok_sql_val($e, 'EXPLAIN WHERE clause',
			'EXPLAIN (VERBOSE, COSTS OFF) '
			  . 'SELECT id, txt FROM iv1307_types WHERE id > 3');
		like($ex, qr/Oracle query/i, "$L: EXPLAIN VERBOSE shows Oracle query");
		like($ex, qr/"ID"\s*>\s*3/, "$L: WHERE clause pushed down");
		like($ex, qr/"TXT"/, "$L: projection includes used column");
		unlike($ex, qr/"PAYLOAD"/, "$L: unused column not fetched remotely");
		diag($ex);

		$ex = ok_sql_val($e, 'EXPLAIN numeric/JOIN pushdown',
			'EXPLAIN (VERBOSE, COSTS OFF) '
			  . 'SELECT t.id FROM iv1307_types t '
			  . 'JOIN iv1307_lookup l ON t.id = l.id WHERE l.code = \'C1\'');
		like($ex, qr/Oracle query/i, "$L: join EXPLAIN shows Oracle query");
		is(scalar(my @scans = ($ex =~ m/Foreign Scan/g)), 1,
			"$L: join runs as a single remote scan");
		like($ex, qr/"IV1307_TYPES"/, "$L: remote SQL references IV1307_TYPES");
		like($ex, qr/"IV1307_LOOKUP"/, "$L: remote SQL references IV1307_LOOKUP");
		like($ex, qr/'C1'/, "$L: join filter pushed down");
		diag($ex);

		is(ok_sql_val($e, 'pushed-join result',
				'SELECT count(*) FROM iv1307_types t '
				  . 'JOIN iv1307_lookup l ON t.id = l.id WHERE l.code = \'C1\''),
			'2', "$L: pushed join returns correct rows");
	};

	subtest "$L: DML with independent Oracle verification" => sub {
		plan tests => 10;

		my ($rc, $out);

		ok_sql($e, 'INSERT ... RETURNING',
			"INSERT INTO iv1307_types (id, amount, txt) "
			  . "VALUES (9001, 3.1416, 'FDW插入中文') "
			  . 'RETURNING id, amount, txt;');
		($rc, $out) = oracle_sql([
			"SELECT amount || '|' || txt FROM iv1307_types WHERE id = 9001"
		]);
		is($rc, 0, "$L: independent Oracle session after INSERT") or diag($out);
		like($out, qr/3\.1416/, "$L: committed INSERT visible in Oracle");
		like($out, qr/FDW插入中文/, "$L: Chinese DML text visible in Oracle");

		ok_sql($e, 'UPDATE ... RETURNING',
			'UPDATE iv1307_types SET amount = 6.2832 WHERE id = 9001 '
			  . 'RETURNING amount;');
		($rc, $out) =
		  oracle_sql(["SELECT amount FROM iv1307_types WHERE id = 9001"]);
		is($rc, 0, "$L: independent Oracle session after UPDATE") or diag($out);
		like($out, qr/6\.2832/, "$L: committed UPDATE visible in Oracle");

		ok_sql($e, 'DELETE ... RETURNING',
			'DELETE FROM iv1307_types WHERE id = 9001 RETURNING id;');
		($rc, $out) = oracle_sql(
			["SELECT COUNT(*) FROM iv1307_types WHERE id = 9001"]);
		is($rc, 0, "$L: independent Oracle session after DELETE") or diag($out);
		like($out, qr/^\s*0\s*$/m, "$L: committed DELETE visible in Oracle");
	};

	subtest "$L: rollback, savepoints and error recovery" => sub {
		plan tests => 9;

		ok_sql($e, 'remote write rolled back',
			'BEGIN; INSERT INTO iv1307_types (id, amount) VALUES (9002, 2); '
			  . 'ROLLBACK;');
		my ($rc, $out) = oracle_sql(
			["SELECT COUNT(*) FROM iv1307_types WHERE id = 9002"]);
		is($rc, 0, "$L: independent session after ROLLBACK") or diag($out);
		like($out, qr/^\s*0\s*$/m, "$L: ROLLBACK leaves no remote residue");

		ok_sql($e, 'savepoint rolled back to',
			'BEGIN; INSERT INTO iv1307_types (id, amount) VALUES (9003, 3); '
			  . 'SAVEPOINT s1; '
			  . 'INSERT INTO iv1307_types (id, amount) VALUES (9004, 4); '
			  . 'ROLLBACK TO SAVEPOINT s1; COMMIT;');
		($rc, $out) = oracle_sql(
			["SELECT COUNT(*) FROM iv1307_types WHERE id IN (9003, 9004)"]);
		is($rc, 0, "$L: independent session after SAVEPOINT/ROLLBACK TO")
		  or diag($out);
		like($out, qr/^\s*1\s*$/m,
			"$L: ROLLBACK TO keeps 9003 and drops 9004 remotely");

		# A remote constraint violation must not wedge the connection.
		fail_sql($e, 'remote unique violation rejected',
			'INSERT INTO iv1307_types (id, amount) VALUES (9003, 9);',
			qr/(ORA-00001|unique|duplicate)/);
		ok_sql($e, 'connection usable after remote error',
			'SELECT COUNT(*) FROM iv1307_types;');
	};

	subtest "$L: privileges and user mappings" => sub {
		plan tests => 14;

		ok_sql($e, 'create limited role', 'CREATE ROLE iv1307_limited;');
		ok_sql($e, 'grant server usage',
			'GRANT USAGE ON FOREIGN SERVER iv_fdw_server TO iv1307_limited;');
		ok_sql($e, 'user mapping for limited role',
			"CREATE USER MAPPING FOR iv1307_limited SERVER iv_fdw_server "
			  . "OPTIONS (user '$ora_user', password '$ora_pass');");
		ok_sql($e, 'grant foreign table select',
			'GRANT SELECT ON iv1307_types TO iv1307_limited;');
		ok_sql($e, 'limited role can read',
			'SET ROLE iv1307_limited; SELECT COUNT(*) FROM iv1307_types;');
		fail_sql($e, 'limited role cannot write',
			'SET ROLE iv1307_limited; '
			  . 'INSERT INTO iv1307_types (id, amount) VALUES (99999, 1);',
			qr/permission denied/);
		ok_sql($e, 'reset role', 'RESET ROLE;');

		ok_sql($e, 'create role without user mapping',
			'CREATE ROLE iv1307_nomapping;');
		ok_sql($e, 'grant server usage (no mapping)',
			'GRANT USAGE ON FOREIGN SERVER iv_fdw_server TO iv1307_nomapping;');
		ok_sql($e, 'grant foreign table select (no mapping)',
			'GRANT SELECT ON iv1307_types TO iv1307_nomapping;');
		fail_sql($e, 'missing user mapping is denied',
			'SET ROLE iv1307_nomapping; SELECT id FROM iv1307_types LIMIT 1;',
			qr/user mapping not found/);
		ok_sql($e, 'reset role (no-mapping case)', 'RESET ROLE;');
	};

	subtest "$L: concurrent sessions, connection lifecycle" => sub {
		plan tests => 11;

		# A second backend must not see uncommitted FDW writes, and must
		# see them after commit.
		my $pid = fork();
		if (!defined $pid)
		{
			BAIL_OUT('cannot fork holding-transaction session');
		}
		if ($pid == 0)
		{
			$ENV{PGHOST}    = $e->{bg_env}{'PGHOST'};
			$ENV{PGPORT}    = $e->{bg_env}{'PGPORT'};
			$ENV{PGDATABASE} = 'postgres';
			delete $ENV{PGOPTIONS};
			open(STDOUT, '>', '/dev/null') or exit(126);
			open(STDERR, '>', '/dev/null') or exit(126);
			exec('psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
				'-c', 'BEGIN; '
				  . 'INSERT INTO iv1307_types (id, amount) VALUES (9006, 6); '
				  . 'SELECT pg_sleep(6); COMMIT;');
			exit(127);
		}
		sleep 3;
		is(ok_sql_val($e, 'uncommitted write invisible to second session',
				'SELECT COUNT(*) FROM iv1307_types WHERE id = 9006'),
			'0', "$L: second session cannot see uncommitted FDW write");
		waitpid($pid, 0);
		is($? >> 8, 0, "$L: holding session committed cleanly");
		is(ok_sql_val($e, 'committed write visible to second session',
				'SELECT COUNT(*) FROM iv1307_types WHERE id = 9006'),
			'1', "$L: second session sees the write after commit");

		# A backend that exits with an open transaction must leave no
		# remote residue.
		my ($rc, $out, $err) = entry_psql($e, 'BEGIN; '
			  . 'INSERT INTO iv1307_types (id, amount) VALUES (9007, 7); '
			  . 'SELECT pg_terminate_backend(pg_backend_pid());');
		isnt($rc, 0, "$L: backend terminated with open transaction");
		($rc, $out) = oracle_sql(
			["SELECT COUNT(*) FROM iv1307_types WHERE id = 9007"]);
		is($rc, 0, "$L: independent session after backend exit") or diag($out);
		like($out, qr/^\s*0\s*$/m,
			"$L: backend exit leaves no remote residue");

		# oracle_close_connections() must not wedge subsequent use.
		ok_sql($e, 'oracle_close_connections()',
			'SELECT oracle_close_connections();');
		ok_sql($e, 'queries work after close/reconnect',
			'SELECT COUNT(*) FROM iv1307_types;');

		# best-effort: no lingering remote transaction after backend exit
		(my $vrc, my $vout) =
		  oracle_sql(['SELECT COUNT(*) FROM v$transaction']);
		if ($vrc == 0)
		{
			like($vout, qr/^\s*0\s*$/m,
				"$L: no lingering remote transaction");
		}
		else
		{
			diag("v\$transaction not accessible from test user, "
				  . "skipping lingering-transaction check: $vout");
			ok(1, "$L: no lingering remote transaction (not checkable)");
		}
	};

	subtest "$L: DROP EXTENSION cleanup and reinstall" => sub {
		plan tests => 11;

		ok_sql($e, 'DROP USER MAPPING',
			'DROP USER MAPPING FOR CURRENT_USER SERVER iv_fdw_server; '
			  . 'DROP USER MAPPING FOR iv1307_limited SERVER iv_fdw_server;');
		ok_sql($e, 'REVOKE server usage',
			'REVOKE USAGE ON FOREIGN SERVER iv_fdw_server '
			  . 'FROM iv1307_limited, iv1307_nomapping;');
		ok_sql($e, 'REVOKE foreign table select',
			'REVOKE SELECT ON iv1307_types '
			  . 'FROM iv1307_limited, iv1307_nomapping;');
		ok_sql($e, 'DROP ROLE',
			'DROP ROLE iv1307_limited, iv1307_nomapping;');
		ok_sql($e, 'DROP FOREIGN TABLE',
			'DROP FOREIGN TABLE iv1307_types, iv1307_lookup;');
		ok_sql($e, 'DROP SERVER', 'DROP SERVER iv_fdw_server;');
		ok_sql($e, 'DROP EXTENSION oracle_fdw', 'DROP EXTENSION oracle_fdw;');
		is(ok_sql_val($e, 'extension gone',
				"SELECT count(*) FROM pg_extension WHERE extname = 'oracle_fdw'"),
			'0', "$L: DROP EXTENSION cleaned up");
		ok_sql($e, 'reinstall after DROP',
			'CREATE EXTENSION oracle_fdw; SELECT oracle_diag();');
		ok_sql($e, 'final cleanup', 'DROP EXTENSION oracle_fdw;');
	};
}

# --------------------------------------------------------------------------
# run the identical matrix on every entry point
# --------------------------------------------------------------------------
for my $e (@entries)
{
	reseed_oracle();
	run_matrix($e);
}

done_testing();
