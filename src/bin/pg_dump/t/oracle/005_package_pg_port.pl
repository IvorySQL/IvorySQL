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

	for my $target_port ($node->port, $node->oraport)
	{
		my $dbname = "restore_${format}_${target_port}";
		my $label = "$format restore through port $target_port";
		$node->safe_psql('postgres', "CREATE DATABASE $dbname");

		if ($format eq 'plain')
		{
			# The session must go back to its own port's grammar afterwards.
			my $mode = $target_port == $node->oraport ? 'oracle' : 'pg';
			$node->command_ok(
				[
					'psql', '-X', "--port=$target_port", "--dbname=$dbname",
					'--set=ON_ERROR_STOP=1', '--single-transaction',
					"--file=$dump", '--command',
					"SELECT 1 / (current_setting('ivorysql.compatible_mode') = '$mode')::int"
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
