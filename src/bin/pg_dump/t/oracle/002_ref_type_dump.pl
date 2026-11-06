# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $tempdir = PostgreSQL::Test::Utils::tempdir;
my $node = PostgreSQL::Test::Cluster->new('ref_dump');
$node->init;
$node->start;

$node->safe_psql('postgres', 'CREATE DATABASE ref_source',
	connect_to_oraport => 1);
$node->safe_psql('postgres', 'CREATE DATABASE ref_restored',
	connect_to_oraport => 1);
$node->safe_psql('ref_source', q{
	CREATE TYPE ref_person AS OBJECT (name varchar2(10), parent REF ref_person);
	CREATE TABLE ref_people OF ref_person;
	CREATE TABLE ref_holder (person REF ref_person);
	INSERT INTO ref_people (name) VALUES ('root'), ('child');
	UPDATE ref_people p SET parent =
		(SELECT REF(r) FROM ref_people r WHERE r.name = 'root')
		WHERE p.name = 'child';
	INSERT INTO ref_holder SELECT REF(p) FROM ref_people p WHERE p.name = 'child';
	DELETE FROM ref_people WHERE name = 'root';
	SELECT setval('ref_people_rowid_seq', 2147483648, false);
	INSERT INTO ref_people (name) VALUES ('high');
	INSERT INTO ref_holder SELECT REF(p) FROM ref_people p WHERE p.name = 'high';
	CREATE TABLE ref_max OF ref_person;
	SELECT setval('ref_max_rowid_seq', 9223372036854775807, false);
	INSERT INTO ref_max (name) VALUES ('maximum');
	INSERT INTO ref_holder SELECT REF(p) FROM ref_max p;
	CREATE TABLE ref_empty () WITH ROWID;
	INSERT INTO ref_empty DEFAULT VALUES;
	CREATE TABLE ref_generated (n integer GENERATED ALWAYS AS (1) STORED) WITH ROWID;
	INSERT INTO ref_generated DEFAULT VALUES;
}, connect_to_oraport => 1);

my $dump = "$tempdir/ref.dump";
$node->command_ok(['pg_dump', '-Fc', '-f', $dump, '-d', 'ref_source'],
	'custom archive of recursive REF type');
$node->command_ok(
	['pg_restore', '--exit-on-error', '--no-owner', '-p', $node->oraport,
	 '-d', 'ref_restored', $dump],
	'custom archive restores object references');

is($node->safe_psql('ref_restored', q{
	SELECT name, (rowid).rowno, DEREF(parent) IS NULL
	FROM ref_people ORDER BY name
}, connect_to_oraport => 1),
	"child|2|t\nhigh|2147483648|t", 'dangling REF and 64-bit ROWIDs survive restore');
is($node->safe_psql('ref_restored', q{
	SELECT (DEREF(person)).name FROM ref_holder ORDER BY 1
}, connect_to_oraport => 1),
	"child\nhigh\nmaximum", 'REF columns still point to restored objects');
is($node->safe_psql('ref_restored',
	q{SELECT (rowid).rowno FROM ref_max}, connect_to_oraport => 1),
	'9223372036854775807', 'INT64_MAX object identity survives restore');
is($node->safe_psql('ref_restored',
	q{SELECT (rowid).rowno FROM ref_empty}, connect_to_oraport => 1),
	'1', 'zero-column ROWID table restores');
is($node->safe_psql('ref_restored',
	q{SELECT n, (rowid).rowno FROM ref_generated}, connect_to_oraport => 1),
	'1|1', 'generated-only ROWID table restores');

my $plain = "$tempdir/ref.sql";
$node->safe_psql('postgres', 'CREATE DATABASE ref_plain', connect_to_oraport => 1);
$node->command_ok(['pg_dump', '-f', $plain, '-d', 'ref_source'],
	'plain dump with statement-scoped ROWID restoration');
$node->command_ok(['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-p', $node->oraport,
	'-d', 'ref_plain', '-f', $plain], 'plain dump restores in autocommit mode');
is($node->safe_psql('ref_plain', q{
	SELECT name, (rowid).rowno FROM ref_people ORDER BY name
}, connect_to_oraport => 1), 'child|2' . "\nhigh|2147483648",
	'plain restore preserves 64-bit object identity');

$node->stop('fast');
done_testing();
