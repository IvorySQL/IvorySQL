# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $tempdir = PostgreSQL::Test::Utils::tempdir;
my $node = PostgreSQL::Test::Cluster->new('varchar2_restore');
$node->init;
$node->start;

for my $db (qw(source_db plain_db custom_db parallel_db))
{
	$node->safe_psql('postgres', "CREATE DATABASE $db",
		connect_to_oraport => 1);
}

$node->safe_psql('source_db', q{
	SET nls_length_semantics = byte;
	CREATE TABLE lengths (
		id integer PRIMARY KEY,
		explicit_char varchar2(10 char),
		explicit_byte varchar2(10 byte),
		implicit_byte varchar2(10)
	);
	INSERT INTO lengths VALUES (1, 'char', 'byte', 'implicit');
	CREATE TABLE restore_data_probe (seen text);
	INSERT INTO restore_data_probe VALUES ('source');
	CREATE INDEX lengths_byte_cast ON lengths ((CAST(explicit_byte AS varchar2(8))));
	SET nls_length_semantics = char;
	ALTER TABLE lengths ADD COLUMN implicit_char varchar2(10);
	UPDATE lengths SET implicit_char = 'char';
	CREATE FUNCTION restore_char_pg_date(v sys.oravarcharchar,
		d pg_catalog.date DEFAULT CAST('2026-01-02' AS pg_catalog.date),
		"label, text" pg_catalog.text DEFAULT 'date, varchar2')
		RETURNS pg_catalog.date LANGUAGE sql AS 'SELECT d';
	CREATE FUNCTION restore_fixed_char(v sys.oravarcharchar, c sys.oracharchar,
		b sys.oracharbyte, d pg_catalog.date) RETURNS integer LANGUAGE sql AS 'SELECT 1';
	CREATE FUNCTION restore_varchar_arrays(v sys.oravarcharchar, a sys.oravarcharchar[],
		b sys.oravarcharbyte[]) RETURNS integer LANGUAGE sql AS 'SELECT 1';
	CREATE FUNCTION restore_only_char_array(a sys.oravarcharchar[])
		RETURNS integer LANGUAGE sql AS 'SELECT 1';
	CREATE FUNCTION restore_fixed_result() RETURNS sys.oracharchar
		LANGUAGE sql AS 'SELECT CAST(NULL AS sys.oracharchar)';
	CREATE FUNCTION restore_varchar_array_result() RETURNS sys.oravarcharchar[]
		LANGUAGE sql AS 'SELECT CAST(NULL AS sys.oravarcharchar[])';
	CREATE FUNCTION restore_char_array_result() RETURNS sys.oracharchar[]
		LANGUAGE sql AS 'SELECT CAST(NULL AS sys.oracharchar[])';
	CREATE FUNCTION restore_char_set_result() RETURNS SETOF sys.oracharchar
		LANGUAGE sql AS 'SELECT CAST(NULL AS sys.oracharchar)';
	CREATE FUNCTION restore_char_input(v varchar2) RETURNS integer
		LANGUAGE sql AS 'SELECT 1';
	CREATE FUNCTION restore_char_input_with_byte_out(v varchar2,
		OUT answer sys.oravarcharbyte) RETURNS sys.oravarcharbyte
		LANGUAGE sql AS 'SELECT CAST(''kept'' AS sys.oravarcharbyte)';
	CREATE FUNCTION restore_char_result() RETURNS varchar2
		LANGUAGE sql AS 'SELECT CAST(''kept'' AS sys.oravarcharchar)';
	CREATE FUNCTION restore_char_out(OUT answer varchar2) RETURNS varchar2
		LANGUAGE sql AS 'SELECT CAST(''kept'' AS sys.oravarcharchar)';
	CREATE FUNCTION restore_mixed_out(v sys.oravarcharbyte,
		OUT a varchar2, OUT b sys.oravarcharbyte)
		LANGUAGE sql AS 'SELECT CAST(''kept'' AS sys.oravarcharchar), v';
}, connect_to_oraport => 1);

sub snapshot
{
	my ($db) = @_;
	return $node->safe_psql($db, q{
		SELECT a.attname, t.typname, a.atttypmod
		FROM pg_attribute a JOIN pg_type t ON t.oid = a.atttypid
		WHERE a.attrelid = 'lengths'::regclass AND a.attnum > 0
		ORDER BY a.attnum;
		SELECT p.proname, t.typname, p.proargtypes, p.proallargtypes
		FROM pg_proc p JOIN pg_type t ON t.oid = p.prorettype
		WHERE p.proname IN ('restore_char_result', 'restore_char_out',
							'restore_char_input', 'restore_char_input_with_byte_out',
							'restore_char_pg_date', 'restore_fixed_char',
							'restore_varchar_arrays', 'restore_only_char_array',
							'restore_fixed_result', 'restore_varchar_array_result',
							'restore_char_array_result', 'restore_char_set_result',
							'restore_mixed_out')
		ORDER BY p.proname;
		SELECT a.attname, t.typname, a.atttypmod
		FROM pg_attribute a JOIN pg_type t ON t.oid = a.atttypid
		WHERE a.attrelid = 'lengths_byte_cast'::regclass AND a.attnum = 1;
		SELECT pg_get_function_arguments(p.oid) FROM pg_proc p
		WHERE p.proname = 'restore_char_pg_date';
		SELECT proretset FROM pg_proc WHERE proname = 'restore_char_set_result';
		SELECT * FROM lengths ORDER BY id;
	}, connect_to_oraport => 1);
}

my $expected = snapshot('source_db');
like($expected, qr/^explicit_byte\|oravarcharbyte\|/m,
	'source contains a BYTE-semantic column');
like($expected, qr/^restore_char_result\|oravarcharchar\|\|$/m,
	'source function returns a CHAR-semantic type');
like($expected, qr/^restore_char_out\|oravarcharchar\|\|\{9502\}$/m,
	'source OUT parameter and return type both use CHAR semantics');
like($expected, qr/^restore_char_input\|int4\|9502\|$/m,
	'source input-only function has a CHAR argument');
like($expected, qr/^restore_char_input_with_byte_out\|oravarcharbyte\|9502\|\{9502,9503\}$/m,
	'source mixed function has CHAR input and BYTE output');
like($expected, qr/^restore_char_pg_date\|date\|9502 1082 25\|$/m,
	'source function has CHAR input and PostgreSQL DATE input and result');
like($expected, qr/^restore_fixed_char\|int4\|9502 9500 9501 1082\|$/m,
	'source function has CHAR and BYTE fixed-length arguments');
like($expected, qr/^restore_varchar_arrays\|int4\|9502 9506 9507\|$/m,
	'source mixed function has CHAR and BYTE VARCHAR2 arrays');
like($expected, qr/^restore_only_char_array\|int4\|9506\|$/m,
	'source array-only function has a CHAR VARCHAR2 array');
like($expected, qr/^restore_fixed_result\|oracharchar\|\|$/m,
	'source function returns fixed-length CHAR');
like($expected, qr/^restore_varchar_array_result\|_oravarcharchar\|\|$/m,
	'source function returns a CHAR VARCHAR2 array');
like($expected, qr/^restore_char_array_result\|_oracharchar\|\|$/m,
	'source function returns a fixed-length CHAR array');
like($expected, qr/^restore_char_set_result\|oracharchar\|\|$/m,
	'source set-returning function has a fixed-length CHAR result');
like($expected, qr/^explicit_byte\|oravarcharbyte\|12$/m,
	'source expression index key has an 8-byte typmod');

my $plain = "$tempdir/lengths.sql";
my $custom = "$tempdir/lengths.dump";
my $port = $node->oraport;
{
	local $ENV{PGOPTIONS} = '-c nls_length_semantics=char';
	$node->command_ok(
		['pg_dump', '-p', $port, '-Fp', '-f', $plain, 'source_db'],
		'create plain dump with CHAR source default');
	$node->command_ok(
		['pg_dump', '-p', $port, '-Fc', '-f', $custom, 'source_db'],
		'create custom dump with CHAR source default');
}

{
	local $ENV{PGOPTIONS} = '-c nls_length_semantics=char';
	$node->command_ok(
		['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-p', $port,
		 '-d', 'plain_db', '-f', $plain],
		'restore plain dump with CHAR default');
	$node->command_ok(
		['pg_restore', '--exit-on-error', '-p', $port,
		 '-d', 'custom_db', $custom],
		'restore custom dump with CHAR default');
	$node->command_ok(
		['pg_restore', '--exit-on-error', '-j', '2', '-p', $port,
		 '-d', 'parallel_db', $custom],
		'restore custom dump in parallel with CHAR default');
}

for my $db (qw(plain_db custom_db parallel_db))
{
	is(snapshot($db), $expected, "$db preserves types, lengths and rows");
}

# Existing destination triggers must use the destination's length semantics
# when the restore does not recreate any schema objects.
for my $db (qw(data_plain data_custom data_parallel))
{
	$node->safe_psql('postgres', "CREATE DATABASE $db",
		connect_to_oraport => 1);
	$node->safe_psql($db, q{
		CREATE TABLE restore_data_probe (seen text);
		CREATE FUNCTION record_restore_semantics() RETURNS trigger
			LANGUAGE plpgsql AS $$
		BEGIN
			NEW.seen := current_setting('nls_length_semantics');
			RETURN NEW;
		END
		$$;
		CREATE TRIGGER capture_semantics BEFORE INSERT ON restore_data_probe
			FOR EACH ROW EXECUTE FUNCTION record_restore_semantics();
	}, connect_to_oraport => 1);
}
my $data_sql = "$tempdir/data_only.sql";
{
	local $ENV{PGOPTIONS} = '-c nls_length_semantics=char';
	$node->command_ok(
		['pg_dump', '-p', $port, '--data-only', '-t', 'restore_data_probe',
		 '-f', $data_sql, 'source_db'],
		'create plain data-only dump');
	$node->command_ok(
		['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-p', $port,
		 '-d', 'data_plain', '-f', $data_sql],
		'restore plain data-only dump');
	$node->command_ok(
		['pg_restore', '--exit-on-error', '--data-only', '-t', 'restore_data_probe',
		 '-p', $port, '-d', 'data_custom', $custom],
		'restore only data from a full custom dump');
	$node->command_ok(
		['pg_restore', '--exit-on-error', '--data-only', '-t', 'restore_data_probe',
		 '-j', '2', '-p', $port, '-d', 'data_parallel', $custom],
		'restore only data from a full custom dump in parallel');
}
for my $db (qw(data_plain data_custom data_parallel))
{
	is($node->safe_psql($db, 'SELECT seen FROM restore_data_probe',
			connect_to_oraport => 1),
		'char', "$db preserves the destination trigger's length semantics");
}

done_testing();
