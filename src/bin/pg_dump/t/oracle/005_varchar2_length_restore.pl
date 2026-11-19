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
	SET nls_length_semantics = char;
	ALTER TABLE lengths ADD COLUMN implicit_char varchar2(10);
	UPDATE lengths SET implicit_char = 'char';
}, connect_to_oraport => 1);

sub snapshot
{
	my ($db) = @_;
	return $node->safe_psql($db, q{
		SELECT a.attname, t.typname, a.atttypmod
		FROM pg_attribute a JOIN pg_type t ON t.oid = a.atttypid
		WHERE a.attrelid = 'lengths'::regclass AND a.attnum > 0
		ORDER BY a.attnum;
		SELECT * FROM lengths ORDER BY id;
	}, connect_to_oraport => 1);
}

my $expected = snapshot('source_db');
like($expected, qr/^explicit_byte\|oravarcharbyte\|/m,
	'source contains a BYTE-semantic column');

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
