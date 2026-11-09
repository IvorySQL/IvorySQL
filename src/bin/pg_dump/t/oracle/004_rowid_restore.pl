# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $tempdir = PostgreSQL::Test::Utils::tempdir;
my $node = PostgreSQL::Test::Cluster->new('rowid_restore');
$node->init;
$node->start;

my $owner = 'rowid_owner';
$node->safe_psql('postgres', "CREATE ROLE $owner LOGIN");
foreach my $db (
	qw(rowid_source rowid_custom rowid_plain rowid_auth rowid_data rowid_triggers))
{
	$node->safe_psql('postgres', "CREATE DATABASE $db OWNER $owner",
		connect_to_oraport => 1);
}
$node->safe_psql('rowid_source', q{
	CREATE TYPE owner_t AS OBJECT (id integer);
	CREATE TABLE owner_objects OF owner_t;
	CREATE TABLE owner_refs (id integer, r REF owner_t);
	INSERT INTO owner_objects VALUES (10), (20);
	INSERT INTO owner_refs SELECT o.id, REF(o) FROM owner_objects o;
	DELETE FROM owner_objects WHERE id = 10;
	CREATE TABLE owner_plain (id integer) WITH ROWID;
	INSERT INTO owner_plain VALUES (1), (2);
	DELETE FROM owner_plain WHERE id = 1;
	SELECT setval('owner_plain_rowid_seq', 2147483648, false);
	INSERT INTO owner_plain VALUES (3);
}, connect_to_oraport => 1, extra_params => ['-U', $owner]);

sub check_data
{
	my ($db, $label) = @_;
	is($node->safe_psql($db, q{
		SELECT id, (rowid).rowno FROM owner_objects ORDER BY id
	}, connect_to_oraport => 1, extra_params => ['-U', $owner]),
		'20|2', "$label: object identity survives");
	is($node->safe_psql($db, q{
		SELECT id, (rowid).rowno FROM owner_plain ORDER BY id
	}, connect_to_oraport => 1, extra_params => ['-U', $owner]),
		"2|2\n3|2147483648", "$label: ordinary 64-bit ROWIDs survive");
	is($node->safe_psql($db, q{
		SELECT id, (DEREF(r)).id FROM owner_refs ORDER BY 1
	}, connect_to_oraport => 1, extra_params => ['-U', $owner]),
		"10|\n20|20", "$label: dangling and live REFs survive");
}

my $dump = "$tempdir/owner.dump";
$node->command_ok(
	['pg_dump', '-U', $owner, '-Fc', '-f', $dump, '-d', 'rowid_source'],
	'non-superuser owner can dump ROWID tables');
$node->command_ok(
	['pg_restore', '--exit-on-error', '--no-owner', '-U', $owner,
	 '-p', $node->oraport, '-d', 'rowid_custom', $dump],
	'non-superuser owner can restore a custom archive with --no-owner');
check_data('rowid_custom', 'owner custom restore');

my $plain = "$tempdir/owner.sql";
$node->command_ok(
	['pg_dump', '-U', $owner, '-f', $plain, '-d', 'rowid_source'],
	'non-superuser owner can create a plain dump');
$node->command_ok(
	['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', $owner,
	 '-p', $node->oraport, '-d', 'rowid_plain', '-f', $plain],
	'original non-superuser owner can restore a plain dump');
check_data('rowid_plain', 'owner plain restore');

$node->command_ok(
	['pg_restore', '--exit-on-error', '--use-set-session-authorization',
	 '-p', $node->oraport, '-d', 'rowid_auth', $dump],
	'ROWID restore works under archived session authorization');
check_data('rowid_auth', 'session authorization restore');

$node->command_ok(
	['pg_restore', '--exit-on-error', '--schema-only', '--no-owner', '-U', $owner,
	 '-p', $node->oraport, '-d', 'rowid_data', $dump],
	'non-superuser owner can prepare an existing ROWID schema');
$node->command_ok(
	['pg_restore', '--exit-on-error', '--data-only', '--no-owner', '-U', $owner,
	 '-p', $node->oraport, '-d', 'rowid_data', $dump],
	'non-superuser owner can perform a data-only restore');
check_data('rowid_data', 'owner data-only restore');

# Use an existing schema, as in a data-only restore into an application DB.
$node->command_ok(
	['pg_restore', '--exit-on-error', '--schema-only', '-p', $node->oraport,
	 '-d', 'rowid_triggers', $dump],
	'prepare existing ROWID tables for data-only restore');
is($node->safe_psql('rowid_triggers', q{
	SELECT bool_and(t.relowner = s.relowner)
	FROM pg_class t JOIN pg_class s
	  ON s.relname = t.relname || '_rowid_seq'
	 AND s.relnamespace = t.relnamespace
	WHERE t.oid IN ('owner_objects'::regclass, 'owner_plain'::regclass)
}), 't', 'schema restore transfers implicit ROWID sequence ownership');
$node->safe_psql('rowid_triggers', q{
	CREATE FUNCTION skip_restore_row() RETURNS trigger LANGUAGE plpgsql AS
	$$ BEGIN RETURN NULL; END $$;
	CREATE TRIGGER skip_restore_row BEFORE INSERT ON owner_objects
	FOR EACH ROW EXECUTE FUNCTION skip_restore_row();
	CREATE TRIGGER skip_restore_row BEFORE INSERT ON owner_plain
	FOR EACH ROW EXECUTE FUNCTION skip_restore_row();
	CREATE RULE unrelated_update AS ON UPDATE TO owner_plain DO INSTEAD NOTHING;
	CREATE RULE disabled_insert AS ON INSERT TO owner_plain
	DO ALSO NOTIFY rowid_restore;
	ALTER TABLE owner_plain DISABLE RULE disabled_insert;
});
$node->command_ok(
	['pg_restore', '--exit-on-error', '--data-only', '--disable-triggers',
	 '-p', $node->oraport, '-d', 'rowid_triggers', $dump],
	'data-only restore ignores disabled BEFORE triggers and irrelevant rules');
check_data('rowid_triggers', 'disabled-trigger restore');
is($node->safe_psql('rowid_triggers', q{
	SELECT count(*) FROM pg_trigger
	WHERE tgname = 'skip_restore_row' AND tgenabled = 'O'
}), '2', 'pg_restore re-enables both BEFORE INSERT triggers');
$node->safe_psql('rowid_triggers', 'INSERT INTO owner_plain VALUES (99)');
is($node->safe_psql('rowid_triggers', 'SELECT count(*) FROM owner_plain'),
	'2', 're-enabled trigger still suppresses ordinary inserts');

$node->stop('fast');
done_testing();
