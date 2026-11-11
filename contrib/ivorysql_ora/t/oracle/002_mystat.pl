# Copyright (c) 2026, IvorySQL Global Development Team
#
# Tests for the SYS.V$MYSTAT / SYS.V$STATNAME current-session statistics
# views (GitHub issue #1003).  The views must report live backend-local
# counters: a session must observe the effect of its own DML immediately,
# even inside the same transaction, and must never observe another
# session's activity.  Oracle's STATISTIC# is not stable across versions,
# so callers join V$MYSTAT to V$STATNAME by NAME; these tests use that
# same unquoted STATISTIC# join.
use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('mystat');
$node->init;
$node->start;

# Two persistent sessions, A and B, both kept alive for the whole test so
# that cross-session isolation can be checked.  query_safe() dies on any
# failed query; the END block makes sure the sessions are reaped even when
# an assertion dies before done_testing() is reached.
my ($sa, $sb);

END
{
	$sa->quit() if defined $sa;
	$sb->quit() if defined $sb;
}

my $connstr = $node->connstr('ivorysql', 1);
$sa = $node->background_psql('ivorysql', connstr => $connstr, timeout => 30);
$sb = $node->background_psql('ivorysql', connstr => $connstr, timeout => 30);
$sa->set_query_timer_restart();
$sb->set_query_timer_restart();

sub setup_session
{
	my ($sess) = @_;
	$sess->query_safe("SET IVORYSQL.COMPATIBLE_MODE = ORACLE;");
	$sess->query_safe("SET IVORYSQL.IDENTIFIER_CASE_SWITCH = INTERCHANGE;");
	# keep every scan non-parallel so buffer counters stay deterministic
	$sess->query_safe("SET max_parallel_workers_per_gather = 0;");
	return;
}

setup_session($sa);
setup_session($sb);

# One row per statistic, joined on the unquoted STATISTIC# exactly like the
# Oracle migration queries from issue #1003.
my $stat_sql = <<'SQL';
SELECT a.VALUE
FROM SYS.V$MYSTAT a, SYS.V$STATNAME b
WHERE a.STATISTIC# = b.STATISTIC# AND b.NAME = '%s';
SQL

sub read_stat
{
	my ($sess, $statname) = @_;
	my $out = $sess->query_safe(sprintf($stat_sql, $statname));
	$out =~ s/\s+\z//;
	return $out + 0;
}

sub read_sid
{
	my ($sess) = @_;
	my $out = $sess->query_safe(
		"SELECT SID FROM SYS.V\$MYSTAT WHERE STATISTIC# = 0;");
	$out =~ s/\s+\z//;
	return $out + 0;
}

# ---- fixtures ------------------------------------------------------------
$sa->query_safe("CREATE TABLE mystat_persist (g INT);");
$sa->query_safe(
	"CREATE TABLE mystat_scan AS SELECT generate_series(1, 200000) g;");
$sa->query_safe("CREATE ROLE regress_mystat_reader;");

# ---- baseline readings for session-lifetime monotonicity -----------------
my %base;
for my $s (['a', $sa], ['b', $sb])
{
	my ($tag, $sess) = @$s;
	$base{$tag}{redo}   = read_stat($sess, 'redo size');
	$base{$tag}{cpu}    = read_stat($sess, 'CPU used by this session');
	$base{$tag}{lreads} = read_stat($sess, 'session logical reads');
	$base{$tag}{preads} = read_stat($sess, 'physical reads');
}

# ---- scenario 1: own DML is visible inside the open transaction ----------
$sa->query_safe("BEGIN;");
my $redo_before = read_stat($sa, 'redo size');
$sa->query_safe("INSERT INTO mystat_persist SELECT generate_series(1, 1000);");
my $redo_after = read_stat($sa, 'redo size');
ok($redo_after > $redo_before,
	'redo size grows after own uncommitted INSERT')
  or diag("redo before=$redo_before after=$redo_after");

# ---- scenario 2: stats_fetch_consistency=snapshot must not freeze us -----
$sa->query_safe("SET stats_fetch_consistency = snapshot;");
$redo_before = read_stat($sa, 'redo size');
$sa->query_safe(
	"INSERT INTO mystat_persist SELECT generate_series(1001, 2000);");
$redo_after = read_stat($sa, 'redo size');
ok($redo_after > $redo_before,
	'redo size still grows with stats_fetch_consistency=snapshot')
  or diag("redo before=$redo_before after=$redo_after");
$sa->query_safe("COMMIT;");

# ---- scenario 3: another session's writes do not change A's redo ---------
my $redo_a_stable = read_stat($sa, 'redo size');
$sb->query_safe(
	"INSERT INTO mystat_persist SELECT generate_series(2001, 3000);");
my $redo_a_after_b = read_stat($sa, 'redo size');
is($redo_a_after_b, $redo_a_stable,
	"session B's writes do not change session A's redo size")
  or diag("A redo before B=$redo_a_stable after B=$redo_a_after_b");

# ---- scenario 4: SIDs are the backend's own PID and distinct per session -
my $pid_a = read_sid($sa);
my $pid_b = read_sid($sb);
my $raw_pid_a = $sa->query_safe("SELECT pg_backend_pid();");
$raw_pid_a =~ s/\s+\z//;
is($pid_a, $raw_pid_a + 0,
	'V$MYSTAT.SID equals pg_backend_pid() in session A');
isnt($pid_a, $pid_b, 'concurrent sessions report distinct SIDs');

# ---- scenario 5: cross-transaction values never regress ------------------
ok(read_stat($sa, 'redo size') >= $redo_after,
	'redo size does not regress across transactions')
  or diag("redo after scenario 2=$redo_after, now="
		  . read_stat($sa, 'redo size'));

# ---- scenario 6: logical reads grow after a plain (non-parallel) scan ----
my $lr_before = read_stat($sa, 'session logical reads');
$sa->query_safe("SELECT COUNT(*) FROM mystat_scan;");
my $lr_after = read_stat($sa, 'session logical reads');
ok($lr_after > $lr_before, 'logical reads grow after a plain table scan')
  or diag("logical reads before=$lr_before after=$lr_after");

# ---- scenario 7: CPU grows after server-side compute (never pg_sleep) ----
my $cpu_before = read_stat($sa, 'CPU used by this session');
my $cpu_after  = $cpu_before;
for my $attempt (1 .. 5)
{
	$sa->query_safe(
		"SELECT sum(sin(x)) FROM generate_series(1, 20000000) x;");
	$cpu_after = read_stat($sa, 'CPU used by this session');
	last if $cpu_after > $cpu_before;
}
ok($cpu_after > $cpu_before,
	'CPU used by this session grows after server-side compute')
  or diag("cpu before=$cpu_before after=$cpu_after (10ms units)");

# ---- scenario 8: physical reads are non-negative and non-decreasing ------
my $pr_before = read_stat($sa, 'physical reads');
$sa->query_safe("SELECT COUNT(*) FROM mystat_scan;");
my $pr_after = read_stat($sa, 'physical reads');
ok($pr_before >= 0 && $pr_after >= $pr_before,
	'physical reads are non-negative and non-decreasing')
  or diag("physical reads before=$pr_before after=$pr_after");

# ---- scenario 9: resetting shared stats leaves local counters alone ------
my $redo_pre_reset = read_stat($sa, 'redo size');
$sa->query_safe("SELECT pg_stat_reset_backend_stats(pg_backend_pid());");
my $redo_post_reset = read_stat($sa, 'redo size');
ok($redo_post_reset >= $redo_pre_reset,
	'pg_stat_reset_backend_stats leaves session-local counters alone')
  or diag("redo before reset=$redo_pre_reset after reset=$redo_post_reset");

# ---- scenario 10: ordinary role can read the views, only its own SID -----
$sb->query_safe("SET ROLE regress_mystat_reader;");
my $mystat_rows = $sb->query_safe("SELECT COUNT(*) FROM SYS.V\$MYSTAT;");
$mystat_rows =~ s/\s+\z//;
is($mystat_rows + 0, 4, 'ordinary role sees the four statistics rows');
my $own_rows = $sb->query_safe(
	"SELECT COUNT(*) FROM SYS.V\$MYSTAT WHERE SID = pg_backend_pid()::NUMBER;");
$own_rows =~ s/\s+\z//;
is($own_rows + 0, 4, 'ordinary role sees only its own session rows');
my $statname_rows = $sb->query_safe("SELECT COUNT(*) FROM SYS.V\$STATNAME;");
$statname_rows =~ s/\s+\z//;
is($statname_rows + 0, 4, 'ordinary role can read V$STATNAME');
$sb->query_safe("RESET ROLE;");

# ---- session-lifetime monotonicity of every counter ----------------------
for my $s (['a', $sa], ['b', $sb])
{
	my ($tag, $sess) = @$s;
	for my $m (['redo',   'redo size'],
			   ['cpu',    'CPU used by this session'],
			   ['lreads', 'session logical reads'],
			   ['preads', 'physical reads'])
	{
		my ($key, $name) = @$m;
		my $now = read_stat($sess, $name);
		ok($now >= $base{$tag}{$key},
			"$name does not regress over the session lifetime")
		  or diag("session $tag $name baseline=$base{$tag}{$key} now=$now");
	}
}

# ---- cleanup ---------------------------------------------------------------
$sa->query_safe("DROP TABLE mystat_persist;");
$sa->query_safe("DROP TABLE mystat_scan;");
$sa->query_safe("DROP ROLE regress_mystat_reader;");

done_testing();
