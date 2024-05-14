# Copyright (c) 2021-2023, PostgreSQL Global Development Group
#
# This test aims to validate that an incremental backup can be combined
# with a valid prior backup and that it cannot be combined with an invalid
# prior backup.

use strict;
use warnings;
use File::Compare;
use File::Path qw(rmtree);
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# Set up a new database instance.
my $node1 = PostgreSQL::Test::Cluster->new('node1');
$node1->init(has_archiving => 1, allows_streaming => 1);
$node1->append_conf('postgresql.conf', 'summarize_wal = on');
$node1->start;

# Set up another new database instance. We don't want to use the cached
# INITDB_TEMPLATE for this, because we want it to be a separate cluster
# with a different system ID.
my $node2;
{
	local $ENV{'INITDB_TEMPLATE'} = undef;

	$node2 = PostgreSQL::Test::Cluster->new('node2');
	$node2->init(has_archiving => 1, allows_streaming => 1);
	$node2->append_conf('postgresql.conf', 'summarize_wal = on');
	$node2->start;
}

# Take a full backup from node1.
my $backup1path = $node1->backup_dir . '/backup1';
$node1->command_ok(
	[ 'pg_basebackup', '-D', $backup1path, '--no-sync', '-cfast' ],
	"full backup from node1");

# Now take an incremental backup.
my $backup2path = $node1->backup_dir . '/backup2';
$node1->command_ok(
	[ 'pg_basebackup', '-D', $backup2path, '--no-sync', '-cfast',
	  '--incremental', $backup1path . '/backup_manifest' ],
	"incremental backup from node1");

# Now take another incremental backup.
my $backup3path = $node1->backup_dir . '/backup3';
$node1->command_ok(
	[ 'pg_basebackup', '-D', $backup3path, '--no-sync', '-cfast',
	  '--incremental', $backup2path . '/backup_manifest' ],
	"another incremental backup from node1");

# Take a full backup from node2.
my $backupother1path = $node1->backup_dir . '/backupother1';
$node2->command_ok(
	[ 'pg_basebackup', '-D', $backupother1path, '--no-sync', '-cfast' ],
	"full backup from node2");

# Take an incremental backup from node2.
my $backupother2path = $node1->backup_dir . '/backupother2';
$node2->command_ok(
	[ 'pg_basebackup', '-D', $backupother2path, '--no-sync', '-cfast',
	  '--incremental', $backupother1path . '/backup_manifest' ],
	"incremental backup from node2");

# Result directory.
my $resultpath = $node1->backup_dir . '/result';

# Can't combine 2 full backups.
$node1->command_fails_like(
	[ 'pg_combinebackup', $backup1path, $backup1path, '-o', $resultpath ],
	qr/is a full backup, but only the first backup should be a full backup/,
	"can't combine full backups");

# Can't combine 2 incremental backups.
$node1->command_fails_like(
	[ 'pg_combinebackup', $backup2path, $backup2path, '-o', $resultpath ],
	qr/is an incremental backup, but the first backup should be a full backup/,
	"can't combine full backups");

# Can't combine full backup with an incremental backup from a different system.
$node1->command_fails_like(
	[ 'pg_combinebackup', $backup1path, $backupother2path, '-o', $resultpath ],
	qr/expected system identifier.*but found/,
	"can't combine backups from different nodes");

# Can't omit a required backup.
$node1->command_fails_like(
	[ 'pg_combinebackup', $backup1path, $backup3path, '-o', $resultpath ],
	qr/starts at LSN.*but expected/,
	"can't omit a required backup");

# Can't combine backups in the wrong order.
$node1->command_fails_like(
	[ 'pg_combinebackup', $backup1path, $backup3path, $backup2path, '-o', $resultpath ],
	qr/starts at LSN.*but expected/,
	"can't combine backups in the wrong order");

# Can combine 3 backups that match up properly.
$node1->command_ok(
	[ 'pg_combinebackup', $backup1path, $backup2path, $backup3path, '-o', $resultpath ],
	"can combine 3 matching backups");
rmtree($resultpath);

# Can combine full backup with first incremental.
my $synthetic12path = $node1->backup_dir . '/synthetic12';
$node1->command_ok(
	[ 'pg_combinebackup', $backup1path, $backup2path, '-o', $synthetic12path ],
	"can combine 2 matching backups");

# Can combine result of previous step with second incremental.
$node1->command_ok(
	[ 'pg_combinebackup', $synthetic12path, $backup3path, '-o', $resultpath ],
	"can combine synthetic backup with later incremental");
rmtree($resultpath);

# Can't combine result of 1+2 with 2.
$node1->command_fails_like(
	[ 'pg_combinebackup', $synthetic12path, $backup2path, '-o', $resultpath ],
	qr/starts at LSN.*but expected/,
	"can't combine synthetic backup with included incremental");

# OK, that's all.
done_testing();
