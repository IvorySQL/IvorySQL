# Copyright (c) 2026, IvorySQL Global Development Team

# Verify that pg_upgrade --using-ora-pg refuses a source cluster that
# contains a user-defined package, rather than failing later in pg_restore
# when CREATE PACKAGE reaches the PostgreSQL port.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $oldnode = PostgreSQL::Test::Cluster->new('old');
$oldnode->init(extra => [ '-m', 'oracle' ]);
$oldnode->start;

# CREATE PACKAGE needs a single command string because psql's normal
# file/statement splitting would break the package body at its internal
# semicolons.  Switch the session to Oracle mode first.
$oldnode->safe_psql('postgres', 'CREATE SCHEMA "MixSch"');
$oldnode->safe_psql(
	'postgres', '',
	extra_params =>
	  [ '-c', 'SET ivorysql.compatible_mode=oracle',
		'-c', 'CREATE PACKAGE "MixSch"."MixPkg" AS PROCEDURE p; END;' ]);
$oldnode->safe_psql(
	'postgres', '',
	extra_params =>
	  [ '-c', 'SET ivorysql.compatible_mode=oracle',
		'-c',
		'CREATE PACKAGE BODY "MixSch"."MixPkg" AS PROCEDURE p IS BEGIN NULL; END; END;'
	  ]);

$oldnode->stop;

my $newnode = PostgreSQL::Test::Cluster->new('new');
$newnode->init(extra => [ '-m', 'oracle' ]);

my $oldbindir = $oldnode->config_data('--bindir');
my $newbindir = $newnode->config_data('--bindir');

# The standard TAP harness has no oraport accessor; the port is recorded in
# postgresql.conf by PostgreSQL::Test::Cluster.
sub node_oraport
{
	my ($node) = @_;
	my $conf = PostgreSQL::Test::Utils::slurp_file(
		$node->data_dir . '/postgresql.conf');
	$conf =~ /^ivorysql\.port\s*=\s*(\d+)/m
	  or die "could not find ivorysql.port in " . $node->data_dir;
	return $1;
}

my $oldoraport = node_oraport($oldnode);
my $neworaport = node_oraport($newnode);

command_checks_all(
	[
		'pg_upgrade', '--no-sync', '-g',
		'-d', $oldnode->data_dir,
		'-D', $newnode->data_dir,
		'-b', $oldbindir,
		'-B', $newbindir,
		'-s', $newnode->host,
		'-p', $oldnode->port,
		'-P', $newnode->port,
		'-q', $oldoraport,
		'-Q', $neworaport,
		'--check'
	],
	1,
	[qr/user-defined package/],
	[qr/^$/],
	'pg_upgrade refuses user-defined packages with --using-ora-pg');

done_testing();
