# Copyright (c) 2026, IvorySQL Global Development Team

# Exercise an Oracle row filter during both initial synchronization and logical
# decoding, with the function allocated in the normal user-object OID range.
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $publisher = PostgreSQL::Test::Cluster->new('publisher');
$publisher->init(allows_streaming => 'logical');
$publisher->start;
my $subscriber = PostgreSQL::Test::Cluster->new('subscriber');
$subscriber->init;
$subscriber->start;

$publisher->safe_psql(
	'postgres',
	q{
	ALTER FUNCTION sys.length(text) RENAME TO length_before_oid_test;
	CREATE FUNCTION sys.length(text) RETURNS integer
	AS '$libdir/ivorysql_ora', 'oracharlen'
	LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
	ALTER EXTENSION ivorysql_ora ADD FUNCTION sys.length(text);
	CREATE TABLE builtin_oid_data
	  (g text, n integer GENERATED ALWAYS AS (length(g)) VIRTUAL);
	INSERT INTO builtin_oid_data(g) VALUES ('hello'), ('longer'), (NULL);
	CREATE PUBLICATION builtin_oid_pub FOR TABLE builtin_oid_data
	  WHERE (length(g) < 6) WITH (publish = 'insert');
	},
	connect_to_oraport => 1);
is( $publisher->safe_psql('postgres',
		q{SELECT 'sys.length(text)'::regprocedure::oid >= 16384}),
	't', 'Oracle function has a high OID');

$subscriber->safe_psql('postgres',
	q{CREATE TABLE builtin_oid_data
	  (g text, n integer GENERATED ALWAYS AS (pg_catalog.length(g)) VIRTUAL)});
my $connstr = $publisher->connstr . ' dbname=postgres';
$subscriber->safe_psql('postgres',
	"CREATE SUBSCRIPTION builtin_oid_sub CONNECTION '$connstr'
	 PUBLICATION builtin_oid_pub");
$subscriber->wait_for_subscription_sync($publisher, 'builtin_oid_sub');
is( $subscriber->safe_psql('postgres',
		'SELECT g, n FROM builtin_oid_data ORDER BY g'),
	'hello|5', 'initial copy applies the high-OID Oracle row filter');

$publisher->safe_psql('postgres',
	q{INSERT INTO builtin_oid_data(g) VALUES ('hi'), ('another'), (NULL)});
$publisher->wait_for_catchup('builtin_oid_sub');
is( $subscriber->safe_psql('postgres',
		'SELECT g, n FROM builtin_oid_data ORDER BY g'),
	"hello|5\nhi|2", 'logical decoding applies the high-OID Oracle row filter');

$publisher->safe_psql(
	'postgres',
	q{ALTER PUBLICATION builtin_oid_pub SET TABLE builtin_oid_data
	    WHERE (length(g) < 3);
	  INSERT INTO builtin_oid_data(g) VALUES ('a'), ('four');},
	connect_to_oraport => 1);
$publisher->wait_for_catchup('builtin_oid_sub');
is( $subscriber->safe_psql('postgres',
		'SELECT g, n FROM builtin_oid_data ORDER BY g'),
	"a|1\nhello|5\nhi|2", 'ALTER PUBLICATION refreshes the Oracle row filter');

# A dump stores object names, not their instance-specific OIDs.  Restore the
# generation expression into a database with the original extension objects.
my $dumpfile = $publisher->basedir . '/builtin_oid.sql';
$publisher->command_ok(
	[ 'pg_dump', '--schema-only', '--no-publications',
	  '--table=public.builtin_oid_data', '--file=' . $dumpfile,
	  '--dbname=' . $publisher->connstr('postgres', 1) ],
	'dump a virtual generated column using the high-OID Oracle function');
$subscriber->safe_psql('postgres', 'CREATE DATABASE builtin_oid_restore');
$subscriber->safe_psql('builtin_oid_restore', slurp_file($dumpfile),
	connect_to_oraport => 1);
is( $subscriber->safe_psql(
		'builtin_oid_restore',
		q{INSERT INTO builtin_oid_data(g) VALUES ('hello');
		  SELECT n FROM builtin_oid_data},
		connect_to_oraport => 1),
	'5', 'restored generation expression resolves the target function OID');

$subscriber->safe_psql('postgres', 'DROP SUBSCRIPTION builtin_oid_sub');
$subscriber->stop;
$publisher->stop;
done_testing();
