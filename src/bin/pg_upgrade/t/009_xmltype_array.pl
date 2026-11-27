# Copyright (c) 2026, IvorySQL Global Development Team

# Test pg_upgrade handling of sys.xmltype arrays across matching and
# mismatched sys.xmltype OIDs (Issue #3273).

use strict;
use warnings FATAL => 'all';

use File::Find qw(find);
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $mode = $ENV{PG_TEST_PG_UPGRADE_MODE} || '--copy';
my $has_libxml = check_pg_config("#define USE_LIBXML 1");

sub get_oraport
{
	my ($node) = @_;
	return $node->oraport if $node->can('oraport');
	my $conf = slurp_file($node->data_dir . '/postgresql.conf');
	$conf =~ /^ivorysql\.port\s*=\s*(\d+)/m
	  or die "could not find ivorysql.port in postgresql.conf";
	return $1;
}

sub find_report_file
{
	my ($datadir, $filename) = @_;
	my @matches;
	find(
		sub {
			push @matches, $File::Find::name if $_ eq $filename;
		},
		"$datadir/pg_upgrade_output.d");
	@matches = sort @matches;
	return $matches[-1];
}

my $old = PostgreSQL::Test::Cluster->new('old_ora');
my $new_mismatch = PostgreSQL::Test::Cluster->new('new_ora_mismatch');

$old->init(extra => [ '-m', 'oracle' ]);
$new_mismatch->init(extra => [ '-m', 'oracle' ]);

my $old_oraport = get_oraport($old);
my $new_mismatch_oraport = get_oraport($new_mismatch);

my $xml_lit_1 = $has_libxml ? "'<a/>'::sys.xmltype" : "NULL::sys.xmltype";
my $xml_lit_2 = $has_libxml ? "'<b/>'::sys.xmltype" : "NULL::sys.xmltype";

$old->start;

$old->safe_psql(
	'postgres', qq{
	CREATE DOMAIN dom_xml AS sys.xmltype;
	CREATE DOMAIN dom_xml_arr AS sys.xmltype[];
	CREATE TYPE comp_xml_arr AS (id int, arr sys.xmltype[]);

	CREATE TABLE keep_ok (
		id int,
		c_scalar sys.xmltype,
		c_dom_scalar dom_xml,
		c_dom_elem_arr dom_xml[]
	);
	INSERT INTO keep_ok VALUES (
		1,
		$xml_lit_1,
		$xml_lit_1,
		ARRAY[$xml_lit_1]::dom_xml[]
	);

	CREATE TABLE bad_direct (id int, c_arr sys.xmltype[]);
	INSERT INTO bad_direct VALUES (1, ARRAY[$xml_lit_1, $xml_lit_2]);

	CREATE TABLE bad_nested (
		c_dom_arr dom_xml_arr,
		c_comp comp_xml_arr,
		c_dom_arr_arr dom_xml_arr[],
		c_comp_arr comp_xml_arr[]
	);
	INSERT INTO bad_nested VALUES (
		ARRAY[$xml_lit_1]::dom_xml_arr,
		ROW(1, ARRAY[$xml_lit_2]),
		ARRAY[ARRAY[$xml_lit_1]::dom_xml_arr],
		ARRAY[ROW(1, ARRAY[$xml_lit_2])::comp_xml_arr]
	);

	CREATE MATERIALIZED VIEW bad_mv AS SELECT c_arr AS mv_arr FROM bad_direct;
	CREATE INDEX bad_expr_idx ON keep_ok ((ARRAY[c_scalar]));

	CREATE DATABASE db2;
});

$old->safe_psql(
	'db2', qq{
	CREATE TABLE db2_bad (x sys.xmltype[]);
	INSERT INTO db2_bad VALUES (ARRAY[$xml_lit_1]);
});

$old->stop;

# Simulate a new IvorySQL version whose initdb assigned a different OID to
# sys.xmltype in template1/postgres.
my $conf_path = $new_mismatch->data_dir . '/postgresql.conf';
my $orig_conf = slurp_file($conf_path);
$new_mismatch->append_conf('postgresql.conf', 'allow_system_table_mods = on');
$new_mismatch->start;

my $shifted_oid = $new_mismatch->safe_psql(
	'template1', q{
	SELECT s
	FROM generate_series(15000, 16383) s
	WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_type WHERE oid = s)
	LIMIT 1;
});

for my $dbname ('template1', 'postgres')
{
	$new_mismatch->safe_psql(
		$dbname, qq{
		UPDATE pg_catalog.pg_type
		   SET oid = $shifted_oid
		 WHERE oid = 'sys.xmltype'::pg_catalog.regtype;
		UPDATE pg_catalog.pg_type
		   SET typelem = $shifted_oid
		 WHERE oid = 'sys._xmltype'::pg_catalog.regtype;
	});
}

$new_mismatch->stop;
open my $fh, '>', $conf_path or die "could not rewrite $conf_path: $!";
print $fh $orig_conf;
close $fh;

chdir ${PostgreSQL::Test::Utils::tmp_check};

# 1. With mismatched sys.xmltype OID, pg_upgrade --check must fail and report
#    only the columns/relations that store sys._xmltype arrays.
command_checks_all(
	[
		'pg_upgrade', '--no-sync', '--check',
		'--old-datadir' => $old->data_dir,
		'--new-datadir' => $new_mismatch->data_dir,
		'--old-bindir' => $old->config_data('--bindir'),
		'--new-bindir' => $new_mismatch->config_data('--bindir'),
		'--socketdir' => $new_mismatch->host,
		'--old-port' => $old->port,
		'--new-port' => $new_mismatch->port,
		'--old-oraport' => $old_oraport,
		'--new-oraport' => $new_mismatch_oraport,
		$mode
	],
	1,
	[
		qr/Checking for incompatible "sys\.xmltype" arrays in user tables\s*fatal/,
		qr/Your installation contains arrays of "sys\.xmltype" in user tables/,
		qr/tables_using_xmltype_array\.txt/
	],
	[],
	'pg_upgrade --check fails when sys.xmltype OID differs and xmltype[] columns exist'
);

my $report_file =
  find_report_file($new_mismatch->data_dir, 'tables_using_xmltype_array.txt');
ok(defined $report_file && -f $report_file,
	'tables_using_xmltype_array.txt was created');

my $report = slurp_file($report_file);
like($report, qr/In database: db2\n  public\.db2_bad\.x\n/,
	'report lists xmltype[] column in secondary database db2');
like($report, qr/  public\.bad_direct\.c_arr\n/,
	'report lists direct sys.xmltype[] column');
like($report, qr/  public\.bad_expr_idx\.array\n/,
	'report lists expression index over sys.xmltype[]');
like($report, qr/  public\.bad_mv\.mv_arr\n/,
	'report lists materialized view column over sys.xmltype[]');
like($report, qr/  public\.bad_nested\.c_dom_arr\n/,
	'report lists domain over sys.xmltype[]');
like($report, qr/  public\.bad_nested\.c_comp\n/,
	'report lists composite type containing sys.xmltype[]');
like($report, qr/  public\.bad_nested\.c_dom_arr_arr\n/,
	'report lists array of domain over sys.xmltype[]');
like($report, qr/  public\.bad_nested\.c_comp_arr\n/,
	'report lists array of composite containing sys.xmltype[]');
unlike($report, qr/keep_ok/,
	'report excludes scalar sys.xmltype and domain-element array dom_xml[]');

# 2. Dropping the problematic relations/index/column allows --check to pass even
#    when sys.xmltype OID differs, while preserving scalar sys.xmltype and dom_xml[].
$old->start;
$old->safe_psql(
	'postgres', q{
	DROP MATERIALIZED VIEW bad_mv;
	ALTER TABLE bad_direct DROP COLUMN c_arr;
	DROP TABLE bad_nested;
	DROP INDEX bad_expr_idx;
});
$old->safe_psql('db2', 'DROP TABLE db2_bad;');
$old->stop;

command_ok(
	[
		'pg_upgrade', '--no-sync', '--check',
		'--old-datadir' => $old->data_dir,
		'--new-datadir' => $new_mismatch->data_dir,
		'--old-bindir' => $old->config_data('--bindir'),
		'--new-bindir' => $new_mismatch->config_data('--bindir'),
		'--socketdir' => $new_mismatch->host,
		'--old-port' => $old->port,
		'--new-port' => $new_mismatch->port,
		'--old-oraport' => $old_oraport,
		'--new-oraport' => $new_mismatch_oraport,
		$mode
	],
	'pg_upgrade --check succeeds after dropping xmltype[] columns despite OID shift'
);

# 3. When old and new clusters have the same sys.xmltype OID, full pg_upgrade
#    succeeds with stored sys.xmltype[] columns and preserves array values.
$old->start;
$old->safe_psql(
	'postgres', qq{
	CREATE TABLE preserved_xml_arr (
		id int,
		c_arr sys.xmltype[],
		c_dom_arr dom_xml_arr,
		c_comp comp_xml_arr,
		c_dom_arr_arr dom_xml_arr[],
		c_comp_arr comp_xml_arr[]
	);
	INSERT INTO preserved_xml_arr VALUES (
		1,
		ARRAY[$xml_lit_1, $xml_lit_2],
		ARRAY[$xml_lit_1]::dom_xml_arr,
		ROW(1, ARRAY[$xml_lit_2]),
		ARRAY[ARRAY[$xml_lit_1]::dom_xml_arr],
		ARRAY[ROW(1, ARRAY[$xml_lit_2])::comp_xml_arr]
	);
});
my $expected_vals = $old->safe_psql(
	'postgres',
	'SELECT c_arr::text, c_dom_arr::text, c_comp::text, c_dom_arr_arr::text, c_comp_arr::text FROM preserved_xml_arr;'
);
my $expected_keep = $old->safe_psql(
	'postgres',
	'SELECT c_scalar::text, c_dom_scalar::text, c_dom_elem_arr::text FROM keep_ok;'
);
$old->stop;

my $new_same = PostgreSQL::Test::Cluster->new('new_ora_same');
$new_same->init(extra => [ '-m', 'oracle' ]);
my $new_same_oraport = get_oraport($new_same);

command_ok(
	[
		'pg_upgrade', '--no-sync',
		'--old-datadir' => $old->data_dir,
		'--new-datadir' => $new_same->data_dir,
		'--old-bindir' => $old->config_data('--bindir'),
		'--new-bindir' => $new_same->config_data('--bindir'),
		'--socketdir' => $new_same->host,
		'--old-port' => $old->port,
		'--new-port' => $new_same->port,
		'--old-oraport' => $old_oraport,
		'--new-oraport' => $new_same_oraport,
		$mode
	],
	'full pg_upgrade succeeds when old and new clusters share the same sys.xmltype OID'
);

$new_same->start;
my $upgraded_vals = $new_same->safe_psql(
	'postgres',
	'SELECT c_arr::text, c_dom_arr::text, c_comp::text, c_dom_arr_arr::text, c_comp_arr::text FROM preserved_xml_arr;'
);
my $upgraded_keep = $new_same->safe_psql(
	'postgres',
	'SELECT c_scalar::text, c_dom_scalar::text, c_dom_elem_arr::text FROM keep_ok;'
);
is($upgraded_vals, $expected_vals,
	'sys.xmltype[] values are readable and identical after upgrade when OID matches'
);
is($upgraded_keep, $expected_keep,
	'scalar sys.xmltype and dom_xml[] values remain intact after upgrade');
is($new_same->safe_psql('postgres', 'SELECT id FROM bad_direct;'),
	'1',
	'table with dropped sys.xmltype[] column upgrades intact');
$new_same->stop;

done_testing();
