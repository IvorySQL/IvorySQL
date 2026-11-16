# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('typmod_restore');
$node->init;
$node->start;

my $tempdir = PostgreSQL::Test::Utils::tempdir;
my $port = $node->oraport;
my $source = 'typmod_source';
$node->safe_psql('postgres', "CREATE DATABASE $source", connect_to_oraport => 1);

$node->safe_psql($source, q{
	CREATE TABLE restore_typmods (
		tz timestamptz,
		ts sys.oratimestamp,
		ltz sys.oratimestampltz,
		byte_string sys.oravarcharbyte,
		char_string sys.oravarcharchar,
		precise_tz timestamp(3) with time zone,
		address varchar2(10)
	);
	CREATE VIEW restore_view AS
		SELECT address FROM restore_typmods WHERE address = 'US';
}, connect_to_oraport => 1);

my $column_types = q{
	SELECT a.attname, t.typname, a.atttypmod
	FROM pg_attribute a JOIN pg_type t ON t.oid = a.atttypid
	WHERE a.attrelid = 'restore_typmods'::regclass AND a.attnum > 0
	ORDER BY a.attnum
};
my $view_definition = q{SELECT pg_get_viewdef('restore_view'::regclass)};
my $expected_types = $node->safe_psql($source, $column_types,
	connect_to_oraport => 1);
my $expected_view = $node->safe_psql($source, $view_definition,
	connect_to_oraport => 1);

like($expected_types, qr/^tz\|oratimestamptz\|-1$/m,
	'source timestamp with time zone has no type modifier');
like($expected_types, qr/^precise_tz\|oratimestamptz\|3$/m,
	'source timestamp with explicit precision has a type modifier');

foreach my $format ('custom', 'plain')
{
	my $target = "typmod_$format";
	my $dump = "$tempdir/$format.dump";
	$node->safe_psql('postgres', "CREATE DATABASE $target",
		connect_to_oraport => 1);

	$node->command_ok(
		['pg_dump', '-p', $port, "--format=$format", '-f', $dump, $source],
		"dump through the Oracle port ($format)");

	my $restore = $format eq 'custom'
	  ? ['pg_restore', '--exit-on-error', '-p', $port, '-d', $target, $dump]
	  : ['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-p', $port, '-d', $target,
		'-f', $dump];
	$node->command_ok($restore, "restore through the Oracle port ($format)");

	is($node->safe_psql($target, $column_types, connect_to_oraport => 1),
		$expected_types, "column types and modifiers survive $format restore");
	is($node->safe_psql($target, $view_definition, connect_to_oraport => 1),
		$expected_view, "view expression casts survive $format restore");
}

$node->stop('fast');
done_testing();
