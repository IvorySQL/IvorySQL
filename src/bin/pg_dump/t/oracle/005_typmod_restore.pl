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
# The default display prints both VARCHAR2 flavours as plain varchar2, so
# compare view definitions with the qualified names turned on as well.
my $preserve = "SET ivorysql.preserve_absent_typmod = on;\n";
my $preserved_view_definition = $preserve . $view_definition;
my $expected_types = $node->safe_psql($source, $column_types,
	connect_to_oraport => 1);
my $expected_view = $node->safe_psql($source, $view_definition,
	connect_to_oraport => 1);
my $expected_preserved_view = $node->safe_psql($source,
	$preserved_view_definition, connect_to_oraport => 1);

like($expected_types, qr/^tz\|oratimestamptz\|-1$/m,
	'source timestamp with time zone has no type modifier');
like($expected_types, qr/^precise_tz\|oratimestamptz\|3$/m,
	'source timestamp with explicit precision has a type modifier');

# Interactive output (\d, view definitions, plans) keeps the familiar Oracle
# names; only a session that turns on ivorysql.preserve_absent_typmod, as
# pg_dump does, gets the schema-qualified names.
my $formatted_types = q{
	SELECT a.attname || '|' || format_type(a.atttypid, a.atttypmod)
	FROM pg_attribute a
	WHERE a.attrelid = 'restore_typmods'::regclass AND a.attnum > 0
	ORDER BY a.attnum
};
is( $node->safe_psql($source, $formatted_types, connect_to_oraport => 1),
	join("\n",
		'tz|timestamp with time zone',
		'ts|timestamp',
		'ltz|timestamp with local time zone',
		'byte_string|varchar2',
		'char_string|varchar2',
		'precise_tz|timestamp(3) with time zone',
		'address|varchar2(10)'),
	'Oracle session prints familiar type names by default');
is( $node->safe_psql(
		$source,
		"$preserve$formatted_types",
		connect_to_oraport => 1),
	join("\n",
		'tz|sys.oratimestamptz',
		'ts|sys.oratimestamp',
		'ltz|sys.oratimestampltz',
		'byte_string|sys.oravarcharbyte',
		'char_string|sys.oravarcharchar',
		'precise_tz|timestamp(3) with time zone',
		'address|varchar2(10)'),
	'preserve_absent_typmod qualifies only types without a type modifier');

unlike($expected_view, qr/sys\./,
	'view definition keeps familiar names by default');
like($expected_preserved_view, qr/'US'::sys\.oravarchar(byte|char)/,
	'preserve_absent_typmod qualifies the view cast');

foreach my $format ('custom', 'plain')
{
	my $target = "typmod_$format";
	my $dump = "$tempdir/$format.dump";
	$node->safe_psql('postgres', "CREATE DATABASE $target",
		connect_to_oraport => 1);

	$node->command_ok(
		['pg_dump', '-p', $port, "--format=$format", '-f', $dump, $source],
		"dump through the Oracle port ($format)");

	if ($format eq 'plain')
	{
		my $sql = slurp_file($dump);
		like($sql, qr/\btz sys\.oratimestamptz\b/,
			'plain dump qualifies a timestamp without precision');
		like($sql, qr/\bprecise_tz timestamp\(3\) with time zone\b/,
			'plain dump keeps an explicit precision');
	}

	my $restore = $format eq 'custom'
	  ? ['pg_restore', '--exit-on-error', '-p', $port, '-d', $target, $dump]
	  : ['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-p', $port, '-d', $target,
		'-f', $dump];
	$node->command_ok($restore, "restore through the Oracle port ($format)");

	is($node->safe_psql($target, $column_types, connect_to_oraport => 1),
		$expected_types, "column types and modifiers survive $format restore");
	is($node->safe_psql($target, $view_definition, connect_to_oraport => 1),
		$expected_view, "view expression casts survive $format restore");
	is( $node->safe_psql($target, $preserved_view_definition,
			connect_to_oraport => 1),
		$expected_preserved_view,
		"qualified view casts survive $format restore");
}

# The probe for ivorysql.preserve_absent_typmod must not need any privilege:
# a role that may not call current_setting() still gets the qualified names,
# and its dump restores without adding type modifiers.
$node->safe_psql($source, q{
	CREATE ROLE typmod_dumper LOGIN;
	GRANT SELECT ON restore_typmods, restore_view TO typmod_dumper;
	REVOKE EXECUTE ON FUNCTION pg_catalog.current_setting(text, boolean)
		FROM PUBLIC;
});
my $noexec_dump = "$tempdir/noexec.sql";
$node->command_ok(
	[
		'pg_dump', '-p', $port, '-U', 'typmod_dumper', '--schema-only',
		'-f', $noexec_dump, $source
	],
	'dump succeeds without EXECUTE on current_setting');
like(slurp_file($noexec_dump), qr/\btz sys\.oratimestamptz\b/,
	'dump without EXECUTE on current_setting qualifies the type');
$node->safe_psql('postgres', 'CREATE DATABASE typmod_noexec',
	connect_to_oraport => 1);
$node->command_ok(
	[
		'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-p', $port,
		'-d', 'typmod_noexec', '-f', $noexec_dump
	],
	'restore the dump made without EXECUTE on current_setting');
is($node->safe_psql('typmod_noexec', $column_types, connect_to_oraport => 1),
	$expected_types,
	'column types and modifiers survive a dump without EXECUTE on current_setting');
$node->safe_psql($source, q{
	GRANT EXECUTE ON FUNCTION pg_catalog.current_setting(text, boolean)
		TO PUBLIC;
});

$node->stop('fast');
done_testing();
