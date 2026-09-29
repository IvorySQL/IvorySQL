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
	FROM ref_people
}, connect_to_oraport => 1),
	'child|2|t', 'dangling REF and original ROWID survive restore');
is($node->safe_psql('ref_restored', q{
	SELECT (DEREF(person)).name FROM ref_holder
}, connect_to_oraport => 1),
	'child', 'REF column still points to restored object');

$node->stop('fast');
done_testing();
