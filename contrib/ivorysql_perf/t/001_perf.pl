# Copyright 2026 IvorySQL Global Development Team
# Licensed under the Apache License, Version 2.0. See LICENSE.
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;
use JSON::PP;
use Time::HiRes qw(time);

my $node = PostgreSQL::Test::Cluster->new('perf');
$node->init(extra => ['--dbmode=pg']);
$node->append_conf('postgresql.conf',
	"shared_preload_libraries='pg_stat_statements'\ncompute_query_id=on\n");
$node->start;
my $db = 'postgres';
sub sql { return $node->safe_psql($db, $_[0]); }

sub fails
{
	my ($query, $pattern, $name) = @_;
	my ($out, $err);
	isnt($node->psql($db, $query, stdout => \$out, stderr => \$err), 0,
		$name);
	like($err, $pattern, "$name reports the cause");
}
sql('CREATE EXTENSION ivorysql_perf');
my $a = sql('SELECT ivorysql_perf.take_snapshot()');
my $b = sql('SELECT ivorysql_perf.take_snapshot()');
is( decode_json(sql("SELECT ivorysql_perf.report($a,$b)"))->{sql_status},
	'unavailable',
	'database report works without pg_stat_statements extension');
sql('CREATE EXTENSION pg_stat_statements');
$a = sql('SELECT ivorysql_perf.take_snapshot()');
sql('SELECT sum(g) FROM generate_series(1,50000) g');
$b = sql('SELECT ivorysql_perf.take_snapshot()');
my $report = decode_json(sql("SELECT ivorysql_perf.report($a,$b)"));
is($report->{sql_status}, 'ok', 'captures optional statement counters');
ok( grep({ $_->{query_text} =~ /sum\(g\)/ && $_->{calls} > 0 }
		@{ $report->{top_sql} }),
	'interval report identifies executed workload');
fails(
	"SELECT ivorysql_perf.report($b,$a)",
	qr/must be increasing/,
	'reversed interval is rejected');
fails(
	'SELECT ivorysql_perf.report(-1,-2)',
	qr/snapshot does not exist/,
	'missing snapshots are rejected');
sql("SELECT pg_stat_statements_reset()");
my $reset = sql('SELECT ivorysql_perf.take_snapshot()');
is( decode_json(sql("SELECT ivorysql_perf.report($b,$reset)"))->{sql_status},
	'reset', 'statement reset never yields a negative SQL delta');
sql(q{CREATE ROLE perf_guest; CREATE ROLE perf_monitor; GRANT pg_monitor TO perf_monitor}
);
fails(
	'SET ROLE perf_guest; SELECT ivorysql_perf.take_snapshot()',
	qr/permission denied/,
	'ordinary role cannot collect privileged data');
like(
	sql('SET ROLE perf_monitor; SELECT ivorysql_perf.take_snapshot()'),
	qr/^\d+$/,
	'pg_monitor can use maintenance API without table write privileges');
fails(
	q{SET ROLE perf_monitor; DELETE FROM ivorysql_perf.samples},
	qr/permission denied/,
	'monitor cannot modify stored history directly');
fails(
	'SELECT ivorysql_perf.configure(sample_interval_ms=>1)',
	qr/check constraint/,
	'unsafe sampling interval is rejected');
sql('SELECT ivorysql_perf.configure(sample_interval_ms=>100,snapshot_interval_s=>1,sample_limit=>20,snapshot_limit=>100,sql_limit=>1000)'
);
sql('SET ROLE perf_monitor; SELECT ivorysql_perf.start_collector()');
ok( $node->poll_query_until(
		$db, 'SELECT count(*)=1 FROM ivorysql_perf.collector_status'),
	'collector starts without shared preloading its own library');
sql('SELECT ivorysql_perf.start_collector()');
is(sql('SELECT count(*) FROM ivorysql_perf.collector_status'),
	'1', 'starting again does not duplicate collection');
my $busy = $node->background_psql($db);
my $interval_a = sql('SELECT ivorysql_perf.take_snapshot()');
$busy->query_safe(
	"\\set ON_ERROR_STOP 0\nSET application_name='perf_sleep';");
$busy->query_until(qr/started/, "\\echo started\nSELECT pg_sleep(20);\n");
ok( $node->poll_query_until(
		$db, q{SELECT count(*)>0 FROM ivorysql_perf.samples
 WHERE application_name='perf_sleep' AND wait_event='PgSleep'}),
	'background sampling records a real waiting query');
my $sample_start = time();
sql('SELECT ivorysql_perf.collect_sample() FROM generate_series(1,30)');
diag(
	sprintf(
		'30 manual samples with one active sleeping client: %.3f seconds including psql connection',
		time() - $sample_start));
ok( sql('SELECT count(*)<=20 AND count(*)>0 FROM ivorysql_perf.samples') eq
	  't',
	'sample count remains bounded during active collection');
sql(q{SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE application_name='perf_sleep'}
);
$busy->quit;
sql('CREATE TABLE perf_lock(id int); INSERT INTO perf_lock VALUES (1)');
my $holder = $node->background_psql($db);
my $waiter = $node->background_psql($db);
$holder->query_safe('BEGIN; UPDATE perf_lock SET id=2');
$waiter->query_safe("SET application_name='perf_blocked'");
$waiter->query_until(qr/waiting/,
	"\\echo waiting\nUPDATE perf_lock SET id=3;\n");
ok( $node->poll_query_until(
		$db, q{SELECT count(*)>0 FROM ivorysql_perf.samples
 WHERE application_name='perf_blocked' AND cardinality(blocking_pids)>0}),
	'sampling records blocking backend identities');
$holder->query_safe('ROLLBACK');
$holder->quit;
$waiter->quit;
my $interval_b = sql('SELECT ivorysql_perf.take_snapshot()');
my $sample_report =
  decode_json(sql("SELECT ivorysql_perf.report($interval_a,$interval_b)"));
ok(grep({ $_->{wait_type} eq 'Lock' } @{ $sample_report->{wait_samples} }),
	'interval report aggregates lock waits');
ok( @{ $sample_report->{blocking_samples} } > 0,
	'interval report includes blocker identities');
my $survivor = $node->background_psql($db);
sql('SELECT ivorysql_perf.stop_collector()');
ok( $node->poll_query_until(
		$db, 'SELECT count(*)=0 FROM ivorysql_perf.collector_status'),
	'collector stops cleanly');
is($survivor->query_safe('SELECT 42'),
	'42', 'stopping a collector preserves unrelated client backends');
$survivor->quit;
sql('SELECT ivorysql_perf.configure(sample_limit=>20,snapshot_limit=>4)');
for (1 .. 6) { sql('SELECT ivorysql_perf.take_snapshot()'); }
is(sql('SELECT count(*) FROM ivorysql_perf.snapshots'),
	'4', 'snapshot storage is bounded');
is( sql(q{SELECT count(*) FROM ivorysql_perf.statement_snapshots s LEFT JOIN ivorysql_perf.snapshots p
 ON p.snapshot_id=s.snapshot_id WHERE p.snapshot_id IS NULL}),
	'0',
	'purge cascades to SQL history');
sql(q{UPDATE ivorysql_perf.samples SET sampled_at=clock_timestamp()-interval '2 days';
SELECT ivorysql_perf.purge()});
is(sql('SELECT count(*) FROM ivorysql_perf.samples'),
	'0', 'age retention removes old samples');
$a = sql('SELECT ivorysql_perf.take_snapshot()');
$node->restart;
$b = sql('SELECT ivorysql_perf.take_snapshot()');
fails(
	"SELECT ivorysql_perf.report($a,$b)",
	qr/crosses a restart/,
	'restart boundary cannot produce misleading deltas');
is(sql('SELECT count(*) FROM ivorysql_perf.collector_status'),
	'0', 'restart retains history but collector requires explicit start');
sql('SELECT ivorysql_perf.start_collector()');
ok( $node->poll_query_until(
		$db, 'SELECT count(*)=1 FROM ivorysql_perf.collector_status'),
	'collector can be restarted after server restart');
sql('SELECT ivorysql_perf.stop_collector()');
$node->poll_query_until($db,
	'SELECT count(*)=0 FROM ivorysql_perf.collector_status')
  or die 'collector did not stop';
my $settings_lock = $node->background_psql($db);
$settings_lock->query_safe(
	'BEGIN; LOCK TABLE ivorysql_perf.settings IN ACCESS EXCLUSIVE MODE');
sql('SELECT ivorysql_perf.start_collector()');
ok( $node->poll_query_until(
		$db, q{SELECT count(*)=1 FROM ivorysql_perf.collector_status}),
	'collector starts while its settings are locked');
ok( $node->poll_query_until(
		$db, q{SELECT count(*)=0 FROM ivorysql_perf.collector_status}),
	'tick statement timeout stops a blocked collector');
$settings_lock->query_safe('ROLLBACK');
$settings_lock->quit;
sql('SELECT ivorysql_perf.start_collector()');
ok( $node->poll_query_until(
		$db, q{SELECT count(*)=1 FROM ivorysql_perf.collector_status}),
	'collector can restart after a collection error');
sql('SELECT ivorysql_perf.stop_collector()');
$node->stop;
done_testing();
