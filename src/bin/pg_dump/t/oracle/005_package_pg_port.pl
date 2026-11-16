# Copyright (c) 2026, IvorySQL Global Development Team

# Packages and object types exist only in the Oracle grammar.  A dump taken
# through the PostgreSQL port, as pg_upgrade --using-ora-pg does, must still
# restore them through either port.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('package_pg_port');
$node->init;
$node->start;
my $tempdir = PostgreSQL::Test::Utils::tempdir;

$node->safe_psql('postgres',
	'CREATE ROLE pkg_owner; CREATE ROLE pkg_user; CREATE DATABASE pkg_source');
$node->safe_psql(
	'pkg_source',
	q{
CREATE SCHEMA "MixSch";
CREATE OR REPLACE PACKAGE "MixSch"."MixPkg" AS
  FUNCTION hello RETURN varchar2;
END;
/
CREATE OR REPLACE PACKAGE BODY "MixSch"."MixPkg" AS
  FUNCTION hello RETURN varchar2 IS
  BEGIN
    RETURN 'hello from MixPkg';
  END;
END;
/
ALTER PACKAGE "MixSch"."MixPkg" OWNER TO pkg_owner;
COMMENT ON PACKAGE "MixSch"."MixPkg" IS 'mixed-case package';
GRANT EXECUTE ON PACKAGE "MixSch"."MixPkg" TO pkg_user;
REVOKE ALL ON PACKAGE sys.dbms_random FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA "MixSch" GRANT EXECUTE ON PACKAGES TO pkg_user;
CREATE OR REPLACE PACKAGE spec_only AS
  answer CONSTANT integer := 42;
END;
/
CREATE TYPE obj_t AS OBJECT (
  id integer,
  MEMBER FUNCTION doubled RETURN integer,
  MEMBER FUNCTION tripled RETURN integer);
/
CREATE TYPE attr_t AS OBJECT (
  a_ora_date date,
  a_pg_date pg_catalog.date,
  a_ts timestamp,
  a_pg_ts pg_catalog.timestamp,
  a_varchar2 varchar2(10),
  a_pg_varchar pg_catalog.varchar(10),
  a_number number(5,2),
  a_pg_numeric pg_catalog.numeric(5,2));
/
CREATE TYPE BODY obj_t AS
  MEMBER FUNCTION doubled RETURN integer IS
  BEGIN
    RETURN self.id * 2;
  END;
  MEMBER FUNCTION tripled RETURN integer IS
  BEGIN
    RETURN self.id * 3;
  END;
END;
/
CREATE TABLE plain_rowid (id int) WITH ROWID;
INSERT INTO plain_rowid VALUES (1), (2);
CREATE INDEX user_rowid_idx ON plain_rowid (rowid);
CREATE TABLE rowid_opts (id int) WITH (rowid = true, fillfactor = 70);
CREATE TYPE other_t AS OBJECT (name varchar2(10));
/
CREATE TABLE others OF other_t;
INSERT INTO others VALUES (other_t('a')), (other_t('b'));
CREATE TABLE holder (p REF other_t);
INSERT INTO holder SELECT REF(o) FROM others o;
CREATE TYPE has_ref AS OBJECT (p REF other_t);
/
CREATE TABLE ref_holder (v has_ref);
INSERT INTO ref_holder SELECT has_ref(h.p) FROM holder h;
},
	connect_to_oraport => 1);

my $catalog_query = q{
SELECT n.nspname, p.pkgname, pg_catalog.pg_get_userbyid(p.pkgowner),
       p.pkgacl, md5(p.pkgsrc), md5(coalesce(b.bodysrc, '')),
       coalesce(obj_description(p.oid, 'pg_package'), '')
FROM pg_catalog.pg_package p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pkgnamespace
LEFT JOIN pg_catalog.pg_package_body b ON b.pkgoid = p.oid
WHERE n.nspname NOT IN ('pg_catalog', 'sys')
ORDER BY 1, 2;
SELECT pkgname, pkgacl FROM pg_catalog.pg_package
WHERE pkgnamespace = 'sys'::regnamespace ORDER BY 1;
SELECT c.relname, c.relhasrowid, c.reloptions,
       (SELECT count(*) FROM pg_catalog.pg_index i WHERE i.indrelid = c.oid)
FROM pg_catalog.pg_class c
WHERE c.relname IN ('plain_rowid', 'rowid_opts', 'others', 'holder', 'ref_holder')
ORDER BY 1;
SELECT a.attrelid::regclass::text, a.attname, a.atttypid::regtype
FROM pg_catalog.pg_attribute a
WHERE a.attrelid IN ('holder'::regclass, 'ref_holder'::regclass) AND a.attnum > 0
ORDER BY 1, 2;
SELECT 'plain_rowid', (rowid).rowno, id FROM plain_rowid ORDER BY 3;
SELECT 'others', (o.rowid).rowno, o.name FROM others o ORDER BY 3;
SELECT 'holder', (h.p).rowno FROM holder h ORDER BY 2;
SELECT 'ref_holder', ((x.v).p).rowno FROM ref_holder x ORDER BY 2;
SELECT a.attrelid::regclass, a.attname, a.atttypid::regtype, a.atttypmod
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_type t ON t.typrelid = a.attrelid
WHERE t.typisobject AND a.attnum > 0
ORDER BY a.attrelid::regclass::text, a.attnum;
SELECT pg_catalog.pg_get_userbyid(d.defaclrole), n.nspname, d.defaclobjtype,
       d.defaclacl
FROM pg_catalog.pg_default_acl d
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = d.defaclnamespace
ORDER BY 1, 2, 3;
};
my $expected_catalog = $node->safe_psql('pkg_source', $catalog_query);

# Check that a restored database works, not just that its catalogs match.
sub check_restored
{
	my ($dbname, $label) = @_;

	is($node->safe_psql($dbname, $catalog_query), $expected_catalog,
		"$label preserves packages, their privileges and comments, and object type attributes");
	is( $node->safe_psql(
			$dbname, 'SELECT "MixSch"."MixPkg".hello() FROM dual',
			connect_to_oraport => 1),
		'hello from MixPkg',
		"$label restores a callable package body");
	is( $node->safe_psql(
			$dbname,
			q{SELECT string_agg((DEREF(h.p)).name::text, ',' ORDER BY (h.p).rowno) FROM holder h},
			connect_to_oraport => 1),
		'(a),(b)',
		"$label restores REFs that point at their rows");
	my $notice;
	$node->psql(
		$dbname,
		q{DECLARE o obj_t := obj_t(21);
BEGIN
  RAISE NOTICE '% % %', spec_only.answer, o.doubled(), o.tripled();
END;},
		stderr => \$notice,
		on_error_die => 1,
		connect_to_oraport => 1);
	like($notice, qr/42 42 63/,
		"$label restores a specification-only package and an object type");
}

for my $format ('plain', 'custom')
{
	my $dump = "$tempdir/pkg_$format";
	$node->command_ok(
		[
			'pg_dump', '--port=' . $node->port, '--dbname=pkg_source',
			"--format=$format", "--file=$dump", '--no-sync'
		],
		"$format dump of packages through the PostgreSQL port");

	# psql in Oracle mode reads CREATE PACKAGE and CREATE TYPE BODY up to a
	# "/" line, which only a dump through the Oracle port writes, so a plain
	# dump through the PostgreSQL port is loaded through that port.
	my @target_ports =
	  $format eq 'plain' ? ($node->port) : ($node->port, $node->oraport);

	for my $target_port (@target_ports)
	{
		my $dbname = "restore_${format}_${target_port}";
		my $label = "$format restore through port $target_port";
		$node->safe_psql('postgres', "CREATE DATABASE $dbname");

		if ($format eq 'plain')
		{
			# The session must go back to its own port's grammar afterwards.
			$node->command_ok(
				[
					'psql', '-X', "--port=$target_port", "--dbname=$dbname",
					'--set=ON_ERROR_STOP=1', '--single-transaction',
					"--file=$dump", '--command',
					"SELECT 1 / (current_setting('ivorysql.compatible_mode') = 'pg')::int"
				],
				$label);
		}
		else
		{
			$node->command_ok(
				[
					'pg_restore', "--port=$target_port", "--dbname=$dbname",
					'--exit-on-error', '--single-transaction', $dump
				],
				$label);
		}

		check_restored($dbname, $label);
	}
}

# Each parallel worker switches the grammar on its own connection, and
# --clean must drop packages through the Oracle grammar too.
my $custom_dump = "$tempdir/pkg_custom";
$node->safe_psql('postgres', 'CREATE DATABASE parallel_restore');
$node->command_ok(
	[
		'pg_restore', '--port=' . $node->port, '--dbname=parallel_restore',
		'--exit-on-error', '--jobs=2', $custom_dump
	],
	'parallel restore of packages through the PostgreSQL port');
check_restored('parallel_restore', 'parallel restore');

$node->command_ok(
	[
		'pg_restore', '--port=' . $node->port, '--dbname=parallel_restore',
		'--exit-on-error', '--clean', '--if-exists', $custom_dump
	],
	'clean restore replaces existing packages through the PostgreSQL port');
check_restored('parallel_restore', 'clean restore');

$node->stop;
done_testing();
