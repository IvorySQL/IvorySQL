# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('force_view');
$node->init;
$node->start;
my $tempdir = PostgreSQL::Test::Utils::tempdir;

$node->safe_psql('postgres', 'CREATE DATABASE force_source');
$node->safe_psql(
	'force_source',
	q{
CREATE SCHEMA force_schema;
CREATE SCHEMA "force schema";
CREATE TABLE public.base_table(a int);
INSERT INTO public.base_table VALUES (7);
CREATE FORCE VIEW public.valid_force AS SELECT a FROM public.base_table;
CREATE VIEW public."ZZ_AFTER_FORCE" AS SELECT a FROM public.base_table;
CREATE FORCE VIEW fv_absent AS SELECT * FROM missing_table;
COMMENT ON VIEW fv_absent IS 'invalid force view';
SET search_path = force_schema;
CREATE FORCE VIEW fv_local AS SELECT a FROM missing_table;
SET search_path = public;
CREATE FORCE VIEW "force schema"."MixedView" ("Alias") AS
  SELECT 'it''s $force_view$; \ path' FROM missing_table;
SET ivorysql.identifier_case_switch = interchange;
CREATE FORCE VIEW "fv_interchange" AS SELECT * FROM missing_table;
SET ivorysql.identifier_case_switch = lowercase;
CREATE FORCE VIEW "FV_LOWER" AS SELECT * FROM missing_table;
SET ivorysql.identifier_case_switch = normal;
CREATE FORCE VIEW public.fv_cycle1 AS SELECT * FROM public.fv_cycle2;
CREATE FORCE VIEW public.fv_cycle2 AS SELECT * FROM public.fv_cycle1;
},
	connect_to_oraport => 1);

# Compare the actual catalog identity, original source, and parsing mode, not
# just whether the dump command succeeds or contains a CREATE statement.
my $catalog_query = q{
SELECT n.nspname, c.relname, f.ident_case, md5(f.source)
FROM pg_catalog.pg_force_view f
JOIN pg_catalog.pg_class c ON c.oid = f.fvoid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C";
};
my $expected_catalog = $node->safe_psql('force_source', $catalog_query);
is($node->safe_psql('force_source',
		'SELECT count(*) FROM pg_catalog.pg_force_view'),
	'7', 'source contains seven invalid FORCE VIEWs');

for my $source_port ($node->port, $node->oraport)
{
	for my $format ('plain', 'custom')
	{
		my $dump = "$tempdir/force_${source_port}_${format}";
		$node->command_ok(
			[
				'pg_dump', "--port=$source_port", '--dbname=force_source',
				"--format=$format", "--file=$dump", '--no-sync'
			],
			"$format dump of FORCE VIEWs through port $source_port");

		if ($format eq 'plain')
		{
			unlike(slurp_file($dump),
				qr/CREATE VIEW[^;]*\bAS\s+CREATE\b/s,
				'FORCE VIEW definition is not wrapped in CREATE VIEW AS');
		}

		for my $target_port ($node->port, $node->oraport)
		{
			my $dbname = "restore_${source_port}_${target_port}_${format}";
			$node->safe_psql('postgres', "CREATE DATABASE $dbname");
			my $label = "$format restore from $source_port to $target_port";

			if ($format eq 'plain')
			{
				my $mode = $target_port == $node->oraport ? 'oracle' : 'pg';
				my ($restore_path) = slurp_file($dump) =~
				  /^SELECT pg_catalog.set_config\('search_path', '([^']*)', false\);/m;
				die 'dump has no search_path setting' unless defined $restore_path;
				# An empty literal becomes NULL on the Oracle port, so obtain
				# the effective value of the archive's initial setting there.
				my %psql_opts = $target_port == $node->oraport
				  ? (connect_to_oraport => 1) : ();
				$restore_path = $node->safe_psql($dbname,
					"SELECT pg_catalog.set_config('search_path', '$restore_path', false)",
					%psql_opts);
				$restore_path =~ s/'/''/g;
				# Check before COMMIT, so SET LOCAL alone cannot hide a leaked
				# parsing mode or search_path in a single-transaction restore.
				my $settings_check =
				  "SELECT 1 / ((current_setting('ivorysql.compatible_mode') = '$mode' "
				  . "AND current_setting('ivorysql.identifier_case_switch') = 'normal' "
				  . "AND current_setting('search_path') = '$restore_path')::int)";
				$node->command_ok(
					[
						'psql', '-X', "--port=$target_port", "--dbname=$dbname",
						'--set=ON_ERROR_STOP=1', '--single-transaction',
						"--file=$dump", '--command', $settings_check
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

			is($node->safe_psql($dbname, $catalog_query), $expected_catalog,
				"$label preserves invalid views, schemas, source, and identifier case");
			is($node->safe_psql($dbname,
					'SELECT a FROM public.valid_force'),
				'7', "$label preserves a valid FORCE VIEW and its data");
			is($node->safe_psql($dbname,
					'SELECT a FROM public."ZZ_AFTER_FORCE"'),
				'7', "$label preserves an ordinary view with a quoted name");
			is($node->safe_psql($dbname,
					q{SELECT obj_description('public.fv_absent'::regclass, 'pg_class')}),
				'invalid force view', "$label preserves view comments");

			$node->safe_psql($dbname,
				q{SET search_path = force_schema, public;
CREATE TABLE force_schema.missing_table(a int);
INSERT INTO force_schema.missing_table VALUES (42);
ALTER VIEW force_schema.fv_local COMPILE;},
				connect_to_oraport => 1);
			is($node->safe_psql($dbname,
					'SELECT a FROM force_schema.fv_local'),
				'42', "$label restores a definition that can subsequently compile");
		}
	}
}

# Each parallel restore worker must handle its own parser and namespace state.
my $parallel_dump = "$tempdir/force_" . $node->oraport . '_custom';
$node->safe_psql('postgres', 'CREATE DATABASE parallel_restore');
$node->command_ok(
	[
		'pg_restore', '--port=' . $node->port, '--dbname=parallel_restore',
		'--exit-on-error', '--jobs=2', $parallel_dump
	],
	'parallel restore of FORCE VIEWs');
is($node->safe_psql('parallel_restore', $catalog_query), $expected_catalog,
	'parallel restore preserves invalid FORCE VIEW definitions');
$node->command_ok(
	[
		'pg_restore', '--port=' . $node->port, '--dbname=parallel_restore',
		'--exit-on-error', '--clean', '--if-exists', $parallel_dump
	],
	'clean restore replaces existing FORCE VIEWs');
is($node->safe_psql('parallel_restore', $catalog_query), $expected_catalog,
	'clean restore preserves invalid FORCE VIEW definitions');

$node->stop;
done_testing();
