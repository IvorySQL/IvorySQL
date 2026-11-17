# Copyright (c) 2026, PostgreSQL Global Development Group

# Tests for PostgreSQL::Version.
#
# The module documents that its constructor accepts the output of a Postgres
# command line tool such as "psql --version" or "pg_config --version", so the
# cases below cover those forms in addition to the plain numeric input that
# existing callers pass.
#
# The same parser is shipped twice (src/test/perl and src/oracle_test/perl),
# so the second half of this file re-runs the cases against the other copy in
# a child process and requires identical results.

use strict;
use warnings FATAL => 'all';

use Test::More;
use FindBin;

use PostgreSQL::Version;

# (input, expected stringification, expected major version)
my @cases = (
	[ '18.3',                                   '18.3',      '18' ],
	[ 'psql (PostgreSQL) 18.3',                 '18.3',      '18' ],
	[ 'psql (PostgreSQL) 18.3 (Ubuntu 18.3-1)', '18.3',      '18' ],
	[ 'pg_config (PostgreSQL) 18.3',            '18.3',      '18' ],
	[ 'PostgreSQL 18.3',                        '18.3',      '18' ],
	[ '(PostgreSQL) 18.3',                      '18.3',      '18' ],
	[ '16.2devel',                              '16.2devel', '16' ],
	[ 'psql (PostgreSQL) 9.6.24',               '9.6.24',    '9.6' ],
);

for my $case (@cases)
{
	my ($input, $want_str, $want_major) = @$case;

	my $version = eval { PostgreSQL::Version->new($input) };
	is($@, '', "construct from \"$input\"");
	next if $@;

	is("$version", $want_str, "stringify \"$input\"");

	my $major = eval { $version->major };
	is($@, '', "major() on \"$input\"");
	is($major, $want_major, "major of \"$input\"");
}

# Comparison operators must work on the parsed value, not on the raw string.
my $v = eval { PostgreSQL::Version->new('psql (PostgreSQL) 18.3') };
BAIL_OUT("could not parse psql --version output: $@") if $@;

ok($v == 18.3,  'compares equal to 18.3');
ok($v >= 18,    'compares greater than or equal to 18');
ok($v < 19,     'compares less than 19');
ok($v > '18.2', 'compares greater than 18.2');

# A numeric argument must keep working.
my $numeric = PostgreSQL::Version->new(18);
is("$numeric",       '18', 'numeric input stringifies as 18');
is($numeric->major,  18,   'numeric input major() is 18');

# The second copy of the module must return the same results.  Run the same
# cases in a child process with src/oracle_test/perl first in @INC.
my $oracle_perl = "$FindBin::Bin/../../../oracle_test/perl";

SKIP:
{
	skip 'src/oracle_test/perl is not present in this tree', 1
	  unless -d $oracle_perl;

	my $code = 'use PostgreSQL::Version;'
	  . ' for my $in (@ARGV) {'
	  . ' my $v = PostgreSQL::Version->new($in);'
	  . ' print "$v|", $v->major, "\n";'
	  . ' }';

	my @inputs = map { $_->[0] } @cases;
	my @want   = map { "$_->[1]|$_->[2]" } @cases;

	open(my $fh, '-|', $^X, '-I', $oracle_perl, '-e', $code, @inputs)
	  or die "could not run $^X: $!";
	my @got = <$fh>;
	close($fh);
	chomp @got;

	is_deeply(\@got, \@want,
		'src/oracle_test/perl copy parses the same inputs identically');
}

done_testing();
