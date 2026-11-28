# Copyright (c) 2021-2026, PostgreSQL Global Development Group

# Test the aggregate physical WAL sender rate limit and SIGHUP reload.
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use Test::More;
use Time::HiRes qw(time sleep);

my $primary = PostgreSQL::Test::Cluster->new('primary');
$primary->init(allows_streaming => 1);
$primary->start;

$primary->safe_psql('postgres',
	'CREATE TABLE rate_probe (id integer, payload text)');
$primary->backup('backup');

my @standbys;
for my $name ('standby_1', 'standby_2')
{
	my $standby = PostgreSQL::Test::Cluster->new($name);
	$standby->init_from_backup($primary, 'backup', has_streaming => 1);
	$standby->start;
	push @standbys, $standby;
}

ok($primary->poll_query_until('postgres',
		'SELECT count(*) = 2 FROM pg_stat_replication'),
	'two physical WAL senders connected');
$primary->wait_for_replay_catchup($_) for @standbys;

my $base_lsn = $primary->lsn('flush');
my $sender_pids = $primary->safe_psql('postgres',
	"SELECT string_agg(pid::text, ',' ORDER BY pid) FROM pg_stat_replication");

$primary->safe_psql('postgres',
	"ALTER SYSTEM SET wal_sender_max_rate_total = '32kB'");
$primary->safe_psql('postgres', 'SELECT pg_reload_conf()');
ok($primary->poll_query_until('postgres',
		"SELECT setting = '32' FROM pg_settings "
		. "WHERE name = 'wal_sender_max_rate_total'"),
	'aggregate rate setting reloaded');
sleep 1; # Allow the already-running WAL senders to process SIGHUP.

my $start = time();
$primary->safe_psql('postgres',
	"INSERT INTO rate_probe SELECT g, md5(g::text) || md5((g * 7)::text) "
		. "FROM generate_series(1, 4000) g");
my $target_lsn = $primary->lsn('flush');
my $wal_bytes = $primary->safe_psql('postgres',
	"SELECT pg_wal_lsn_diff('$target_lsn', '$base_lsn')::bigint");
cmp_ok($wal_bytes, '>', 32768 * 4,
	'generated enough WAL to distinguish one shared budget from two');

sleep 3;
my $elapsed = time() - $start;
my $sent_bytes = $primary->safe_psql('postgres',
	"SELECT coalesce(sum(greatest(0, "
		. "pg_wal_lsn_diff(sent_lsn, '$base_lsn')::bigint)), 0) "
		. "FROM pg_stat_replication");
cmp_ok($sent_bytes, '<=', int(32768 * $elapsed + 65536),
	'aggregate WAL payload stays within one budget plus burst margin');
my $behind = $primary->safe_psql('postgres',
	"SELECT count(*) FROM pg_stat_replication "
		. "WHERE replay_lsn < '$target_lsn'::pg_lsn");
is($behind, '2', 'both standbys have a backlog under the limit');

$primary->safe_psql('postgres',
	"ALTER SYSTEM SET wal_sender_max_rate_total = '0kB'");
$primary->safe_psql('postgres', 'SELECT pg_reload_conf()');
$primary->wait_for_catchup($_, 'replay', $target_lsn) for @standbys;
my $sender_pids_after = $primary->safe_psql('postgres',
	"SELECT string_agg(pid::text, ',' ORDER BY pid) FROM pg_stat_replication");
is($sender_pids_after, $sender_pids,
	'disabling the limit releases backlog without reconnecting senders');

done_testing();
