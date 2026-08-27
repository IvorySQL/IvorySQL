
# Copyright (c) 2021-2024, PostgreSQL Global Development Group

# Test for timeline switch
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# Ensure that a cascading standby is able to follow a newly-promoted standby
# on a new timeline.

# Initialize primary node
my $node_primary = PostgreSQL::Test::Cluster->new('primary');
$node_primary->init(allows_streaming => 1);
$node_primary->start;

# Take backup
my $backup_name = 'my_backup';
$node_primary->backup($backup_name);

# Create two standbys linking to it
my $node_standby_1 = PostgreSQL::Test::Cluster->new('standby_1');
$node_standby_1->init_from_backup($node_primary, $backup_name,
	has_streaming => 1);
$node_standby_1->start;
my $node_standby_2 = PostgreSQL::Test::Cluster->new('standby_2');
$node_standby_2->init_from_backup($node_primary, $backup_name,
	has_streaming => 1);
$node_standby_2->start;

# Wait for standby_1 and standby_2 connection to the primary.
$node_primary->poll_query_until('postgres',
	"SELECT count(1) = 2 FROM pg_stat_replication");

# Create some content on primary
$node_primary->safe_psql('postgres',
	"CREATE TABLE tab_int AS SELECT generate_series(1,1000) AS a");

# Cleanly stop and remove primary.  A clean stop is required so as all
# the records generated on the primary are received and flushed by the two
# standbys.
$node_primary->stop;

# promote standby 1 using "pg_promote", switching it to a new timeline
my $psql_out = '';
$node_standby_1->psql(
	'postgres',
	"SELECT pg_promote(wait_seconds => 300)",
	stdout => \$psql_out);
is($psql_out, 't', "promotion of standby with pg_promote");

# Switch standby 2 to replay from standby 1.  During the timeline switch,
# the WAL receiver process on standby 2 should not be stopped, and the
# new primary connection string should not be visible
# in pg_stat_wal_receiver.
my $secret = 'dont_show_me';
my $connstr_1 = $node_standby_1->connstr;
$node_standby_2->append_conf(
	'postgresql.conf', qq(
primary_conninfo='$connstr_1 password=$secret'
));
$node_standby_2->restart;

# Insert some data in standby 1 and check its presence in standby 2
# to ensure that the timeline switch has been done.
$node_standby_1->safe_psql('postgres',
	"INSERT INTO tab_int VALUES (generate_series(1001,2000))");
$node_standby_1->wait_for_catchup($node_standby_2);

my $result =
  $node_standby_2->safe_psql('postgres', "SELECT count(*) FROM tab_int");
is($result, qq(2000), 'check content of standby 2');


my $raw_conninfo_count = $node_standby_2->safe_psql('postgres',
	"SELECT count(*) FROM pg_stat_wal_receiver WHERE conninfo LIKE '%$secret%'"
);

is($raw_conninfo_count, '0',
	'pg_stat_wal_receiver.conninfo not updated across timeline jumps');

# Ensure that a standby is able to follow a primary on a newer timeline
# when WAL archiving is enabled.

# Initialize primary node
my $node_primary_2 = PostgreSQL::Test::Cluster->new('primary_2');
$node_primary_2->init(allows_streaming => 1, has_archiving => 1);
$node_primary_2->append_conf(
	'postgresql.conf', qq(
wal_keep_size = 512MB
));
$node_primary_2->start;

# Take backup
$node_primary_2->backup($backup_name);

# Create standby node
my $node_standby_3 = PostgreSQL::Test::Cluster->new('standby_3');
$node_standby_3->init_from_backup($node_primary_2, $backup_name,
	has_streaming => 1);

# Restart primary node in standby mode and promote it, switching it
# to a new timeline.
$node_primary_2->set_standby_mode;
$node_primary_2->restart;
$node_primary_2->promote;

# Start standby node, create some content on primary and check its presence
# in standby, to ensure that the timeline switch has been done.
$node_standby_3->start;
$node_primary_2->safe_psql('postgres',
	"CREATE TABLE tab_int AS SELECT 1 AS a");
$node_primary_2->wait_for_catchup($node_standby_3);

my $result_2 =
  $node_standby_3->safe_psql('postgres', "SELECT count(*) FROM tab_int");
is($result_2, qq(1), 'check content of standby 3');

done_testing();
