# Copyright (c) 2026, IvorySQL Global Development Team

# Verify that pg_upgrade --using-ora-pg refuses a source cluster that
# contains a user-defined Oracle object type, rather than failing later in
# pg_restore when CREATE TYPE ... AS OBJECT reaches the PostgreSQL port.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $oldnode = PostgreSQL::Test::Cluster->new('old');
$oldnode->init(extra => [ '-m', 'oracle' ]);
$oldnode->start;

$oldnode->safe_psql(
	'postgres', '',
	extra_params =>
	  [ '-c', 'SET ivorysql.compatible_mode=oracle',
		'-c', 'CREATE TYPE obj_upg AS OBJECT (a NUMBER)' ]);

$oldnode->stop;

my $newnode = PostgreSQL::Test::Cluster->new('new');
$newnode->init(extra => [ '-m', 'oracle' ]);

my $oldbindir = $oldnode->config_data('--bindir');
my $newbindir = $newnode->config_data('--bindir');

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
	[qr/user-defined object type/],
	[qr/^$/],
	'pg_upgrade refuses user-defined object types with --using-ora-pg');

done_testing();
