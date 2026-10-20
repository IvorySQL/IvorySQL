# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';
use PostgreSQL::Version;
use PostgreSQL::Test::AdjustUpgrade;
use Test::More;

# pg_lsn gained a zero-padded low half in version 19.  Only normalize
# columns that exist in the old branch, and leave same-version upgrades alone.
my %introduced = (
	brintest => '9.5',
	tab_core_types => '12',
	brintest_multi => '14',
	brintest_bloom => '14');
for my $old ('9.4', '9.5', '11', '12', '13', '14', '18', '19', '19beta1')
{
	my $version = PostgreSQL::Version->new($old);
	my $major = PostgreSQL::Version->new($version->major);
	my $statements = adjust_database_contents($version, regression => 1);
	my @lsn_updates = grep { /set (?:lsncol|pg_lsn) = NULL/ }
	  @{ $statements->{regression} // [] };
	my @expected;
	for my $table (sort keys %introduced)
	{
		if ($major >= $introduced{$table} && $major < 19)
		{
			my $column = $table eq 'tab_core_types' ? 'pg_lsn' : 'lsncol';
			push @expected, "update $table set $column = NULL";
		}
	}
	is_deeply([sort @lsn_updates], [sort @expected],
		"LSN normalization for an upgrade from $old");
}

done_testing();
