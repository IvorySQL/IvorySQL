
# Copyright (c) 2026, IvorySQL Global Development Group

# initdb -C stores the identifier case mode in pg_control, and the
# postmaster sets ivorysql.identifier_case_switch from it.  Every backend
# must run with that mode.  Under EXEC_BACKEND a backend does not inherit
# the postmaster's memory: it gets the value only from the postmaster's
# non-default variables file, which leaves out a value whose source is
# PGC_S_DEFAULT, and the backend would then run with the compiled default,
# interchange.
#
# The mode is checked with SHOW over both ports, and in use: quoted names
# created over the Oracle port, where the mode applies, come out as each
# mode spells them.

use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# the names "q_low" and "Q_UP" become, sorted by relname (C collation)
my %relnames = (
	normal => 'Q_UP q_low',
	interchange => 'Q_LOW q_up',
	lowercase => 'q_low q_up');

foreach my $mode (qw(normal interchange lowercase))
{
	my $node = PostgreSQL::Test::Cluster->new("case_$mode");
	# init passes -C normal itself; the last -C given wins
	$node->init(extra => [ '-C', $mode ]);
	$node->start;

	is($node->safe_psql('postgres', 'SHOW ivorysql.identifier_case_switch'),
		$mode, "$mode: SHOW over the PostgreSQL port");
	is( $node->safe_psql(
			'postgres', 'SHOW ivorysql.identifier_case_switch',
			connect_to_oraport => 1),
		$mode,
		"$mode: SHOW over the Oracle port");

	$node->safe_psql(
		'postgres',
		'CREATE TABLE "q_low" (a int); CREATE TABLE "Q_UP" (a int);',
		connect_to_oraport => 1);
	is( $node->safe_psql(
			'postgres',
			q{SELECT string_agg(relname, ' ' ORDER BY relname) FROM pg_class
			  WHERE relname IN ('q_low', 'Q_LOW', 'Q_UP', 'q_up')}),
		$relnames{$mode},
		"$mode: quoted names created over the Oracle port");

	$node->stop;
}

done_testing();
