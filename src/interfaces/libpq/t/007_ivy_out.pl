# Copyright (c) 2026, IvorySQL Global Development Team
use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('ivy_out');
$node->init;
$node->start;

foreach my $api ('legacy', 'typed')
{
	foreach my $case (
		['empty', 'rows=0 indicator=-1 value=empty'],
		['null', 'rows=1 indicator=-1 value=null'],
		['value', 'rows=1 indicator=0 value=returned'])
	{
		my ($stdout, $stderr) = run_command(
			['libpq_testclient', '--ivy-out', $node->connstr('postgres'),
				$api, $case->[0]]);
		is($?, 0, "$api $case->[0] exits normally");
		is($stdout, $case->[1], "$api $case->[0] OUT value and indicator");
		is($stderr, '', "$api $case->[0] has no diagnostics");
	}
}

# An empty result must not null an input binding with no matching OUT column.
$node->command_checks_all(
	['libpq_testclient', '--ivy-out', $node->connstr('postgres'),
		'typed', 'unbound'],
	0, [qr/^rows=0 indicator=0 value=unbound$/m], [],
	'input-only binding is unchanged by an empty result');

done_testing();
