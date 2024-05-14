# Copyright (c) 2021-2023, PostgreSQL Global Development Group

use strict;
use warnings;
use File::Compare;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# Set up a new database instance.
my $primary = PostgreSQL::Test::Cluster->new('primary');
$primary->init(has_archiving => 1, allows_streaming => 1);
$primary->append_conf('postgresql.conf', 'summarize_wal = on');
$primary->start;

# Create some test tables, each containing one row of data, plus a whole
# extra database.
$primary->safe_psql('postgres', <<EOM);
CREATE TABLE will_change (a int, b text);
INSERT INTO will_change VALUES (1, 'initial test row');
CREATE TABLE will_grow (a int, b text);
INSERT INTO will_grow VALUES (1, 'initial test row');
CREATE TABLE will_shrink (a int, b text);
INSERT INTO will_shrink VALUES (1, 'initial test row');
CREATE TABLE will_get_vacuumed (a int, b text);
INSERT INTO will_get_vacuumed VALUES (1, 'initial test row');
CREATE TABLE will_get_dropped (a int, b text);
INSERT INTO will_get_dropped VALUES (1, 'initial test row');
CREATE TABLE will_get_rewritten (a int, b text);
INSERT INTO will_get_rewritten VALUES (1, 'initial test row');
CREATE DATABASE db_will_get_dropped;
EOM

# Take a full backup.
my $backup1path = $primary->backup_dir . '/backup1';
$primary->command_ok(
	[ 'pg_basebackup', '-D', $backup1path, '--no-sync', '-cfast' ],
	"full backup");

# Now make some database changes.
$primary->safe_psql('postgres', <<EOM);
UPDATE will_change SET b = 'modified value' WHERE a = 1;
INSERT INTO will_grow
	SELECT g, 'additional row' FROM generate_series(2, 5000) g;
TRUNCATE will_shrink;
VACUUM will_get_vacuumed;
DROP TABLE will_get_dropped;
CREATE TABLE newly_created (a int, b text);
INSERT INTO newly_created VALUES (1, 'row for new table');
VACUUM FULL will_get_rewritten;
DROP DATABASE db_will_get_dropped;
CREATE DATABASE db_newly_created;
EOM

# Take an incremental backup.
my $backup2path = $primary->backup_dir . '/backup2';
$primary->command_ok(
	[ 'pg_basebackup', '-D', $backup2path, '--no-sync', '-cfast',
	  '--incremental', $backup1path . '/backup_manifest' ],
	"incremental backup");

# Find an LSN to which either backup can be recovered.
my $lsn = $primary->safe_psql('postgres', "SELECT pg_current_wal_lsn();");

# Make sure that the WAL segment containing that LSN has been archived.
# PostgreSQL won't issue two consecutive XLOG_SWITCH records, and the backup
# just issued one, so call txid_current() to generate some WAL activity
# before calling pg_switch_wal().
$primary->safe_psql('postgres', 'SELECT txid_current();');
$primary->safe_psql('postgres', 'SELECT pg_switch_wal()');

# Now wait for the LSN we chose above to be archived.
my $archive_wait_query =
  "SELECT pg_walfile_name('$lsn') <= last_archived_wal FROM pg_stat_archiver;";
$primary->poll_query_until('postgres', $archive_wait_query)
  or die "Timed out while waiting for WAL segment to be archived";

# Perform PITR from the full backup. Disable archive_mode so that the archive
# doesn't find out about the new timeline; that way, the later PITR below will
# choose the same timeline.
my $pitr1 = PostgreSQL::Test::Cluster->new('pitr1');
$pitr1->init_from_backup($primary, 'backup1',
						 standby => 1, has_restoring => 1);
$pitr1->append_conf('postgresql.conf', qq{
recovery_target_lsn = '$lsn'
recovery_target_action = 'promote'
archive_mode = 'off'
});
$pitr1->start();

# Perform PITR to the same LSN from the incremental backup. Use the same
# basic configuration as before.
my $pitr2 = PostgreSQL::Test::Cluster->new('pitr2');
$pitr2->init_from_backup($primary, 'backup2',
						 standby => 1, has_restoring => 1,
						 combine_with_prior => [ 'backup1' ]);
$pitr2->append_conf('postgresql.conf', qq{
recovery_target_lsn = '$lsn'
recovery_target_action = 'promote'
archive_mode = 'off'
});
$pitr2->start();

# Wait until both servers exit recovery.
$pitr1->poll_query_until('postgres',
						 "SELECT NOT pg_is_in_recovery();")
  or die "Timed out while waiting apply to reach LSN $lsn";
$pitr2->poll_query_until('postgres',
						 "SELECT NOT pg_is_in_recovery();")
  or die "Timed out while waiting apply to reach LSN $lsn";

# Perform a logical dump of each server, and check that they match.
# It would be much nicer if we could physically compare the data files, but
# that doesn't really work. The contents of the page hole aren't guaranteed to
# be identical, and there can be other discrepancies as well. To make this work
# we'd need the equivalent of each AM's rm_mask function written or at least
# callable from Perl, and that doesn't seem practical.
#
# NB: We're just using the primary's backup directory for scratch space here.
# This could equally well be any other directory we wanted to pick.
my $backupdir = $primary->backup_dir;
my $dump1 = $backupdir . '/pitr1.dump';
my $dump2 = $backupdir . '/pitr2.dump';
$pitr1->command_ok([
	'pg_dumpall', '-f', $dump1, '--no-sync', '--no-unlogged-table-data',
		'-d', $pitr1->connstr('postgres'),
	],
	'dump from PITR 1');
$pitr1->command_ok([
	'pg_dumpall', '-f', $dump2, '--no-sync', '--no-unlogged-table-data',
		'-d', $pitr1->connstr('postgres'),
	],
	'dump from PITR 2');

# Compare the two dumps, there should be no differences.
my $compare_res = compare($dump1, $dump2);
note($dump1);
note($dump2);
is($compare_res, 0, "dumps are identical");

# Provide more context if the dumps do not match.
if ($compare_res != 0)
{
	my ($stdout, $stderr) =
		run_command([ 'diff', '-u', $dump1, $dump2 ]);
	print "=== diff of $dump1 and $dump2\n";
	print "=== stdout ===\n";
	print $stdout;
	print "=== stderr ===\n";
	print $stderr;
	print "=== EOF ===\n";
}

done_testing();
