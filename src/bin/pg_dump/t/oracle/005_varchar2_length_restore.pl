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
	CREATE INDEX lengths_byte_cast ON lengths ((CAST(explicit_byte AS varchar2(8))));
	SET nls_length_semantics = char;
	ALTER TABLE lengths ADD COLUMN implicit_char varchar2(10);
	UPDATE lengths SET implicit_char = 'char';
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
							'restore_mixed_out')
		ORDER BY p.proname;
		SELECT a.attname, t.typname, a.atttypmod
		FROM pg_attribute a JOIN pg_type t ON t.oid = a.atttypid
		WHERE a.attrelid = 'lengths_byte_cast'::regclass AND a.attnum = 1;
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
like($expected, qr/^explicit_byte\|oravarcharbyte\|12$/m,
	'source expression index key has an 8-byte typmod');

my $plain = "$tempdir/lengths.sql";
my $custom = "$tempdir/lengths.dump";
my $port = $node->oraport;
$node->command_ok(
	['pg_dump', '-p', $port, '-Fp', '-f', $plain, 'source_db'],
	'create plain dump');
$node->command_ok(
	['pg_dump', '-p', $port, '-Fc', '-f', $custom, 'source_db'],
	'create custom dump');

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

done_testing();
