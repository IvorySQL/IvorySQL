# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('view_binding');
$node->init;
$node->start;

my $tempdir = PostgreSQL::Test::Utils::tempdir;
my $source = 'view_binding_source';
$node->safe_psql('postgres', "CREATE DATABASE $source");
$node->safe_psql(
	$source,
	q{
SET ivorysql.identifier_case_switch = interchange;
CREATE FUNCTION public."replay"(integer) RETURNS integer LANGUAGE sql AS 'SELECT 11';
CREATE FUNCTION public."REPLAY"(integer) RETURNS integer LANGUAGE sql AS 'SELECT 22';
CREATE TABLE public.binding_base(a integer);
INSERT INTO public.binding_base VALUES (1);
CREATE VIEW public.fv_binding AS SELECT public."replay"(a) AS a FROM public.binding_base;
},
	connect_to_oraport => 1);
is($node->safe_psql($source, 'SELECT a FROM public.fv_binding'),
	'11', 'source view calls the uppercase function');

$node->safe_psql(
	$source,
	q{SET ivorysql.identifier_case_switch = interchange;
DROP TABLE public.binding_base;},
	connect_to_oraport => 1);
is($node->safe_psql(
		$source, q{
SELECT ident_case FROM pg_catalog.pg_force_view
WHERE fvoid = 'public.fv_binding'::regclass}),
	'u', 'dropping the base table stores a deparsed force view');

for my $source_port ($node->port, $node->oraport)
{
	for my $format ('plain', 'custom')
	{
		my $dump = "$tempdir/binding_${source_port}_$format";
		$node->command_ok(
			[
				'pg_dump', "--port=$source_port", "--dbname=$source",
				"--format=$format", "--file=$dump", '--no-sync'
			],
			"$format dump of the invalidated view through port $source_port");

		my @targets = ([$node->oraport, 0]);
		# Oracle plain dumps use slash terminators understood by Oracle psql.
		push @targets, [$node->port, 0]
		  if $format ne 'plain' || $source_port == $node->port;
		push @targets, [$node->port, 2]
		  if $format eq 'custom' && $source_port == $node->oraport;
		for my $target (@targets)
		{
			my ($target_port, $jobs) = @$target;
			my $dbname = "restore_${source_port}_${target_port}_${format}_$jobs";
			my $label = "$format restore from $source_port to $target_port";
			$label .= " with $jobs jobs" if $jobs;
			$node->safe_psql('postgres', "CREATE DATABASE $dbname");
			if ($format eq 'plain')
			{
				$node->command_ok(
					[
						'psql', '-X', "--port=$target_port", "--dbname=$dbname",
						'--set=ON_ERROR_STOP=1', "--file=$dump"
					],
					$label);
			}
			else
			{
				$node->command_ok(
					[
						'pg_restore', "--port=$target_port", "--dbname=$dbname",
						'--exit-on-error', ($jobs ? "--jobs=$jobs" : ()), $dump
					],
					$label);
			}

			$node->safe_psql($dbname, q{
CREATE TABLE public.binding_base(a integer);
INSERT INTO public.binding_base VALUES (1);
});

			# Recompile in a fresh Oracle session after the restore.
			is($node->safe_psql($dbname, q{
SET ivorysql.identifier_case_switch = interchange;
ALTER VIEW public.fv_binding COMPILE;
SHOW ivorysql.identifier_case_switch;
SELECT a FROM public.fv_binding;
}, connect_to_oraport => 1),
				"interchange\n11",
				"$label retains the original function after interchange recompilation");
			is($node->safe_psql(
					$dbname, q{
SELECT n.nspname, p.proname
FROM pg_catalog.pg_rewrite AS r
JOIN pg_catalog.pg_depend AS d
  ON d.classid = 'pg_rewrite'::regclass AND d.objid = r.oid
JOIN pg_catalog.pg_proc AS p
  ON d.refclassid = 'pg_proc'::regclass AND d.refobjid = p.oid
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE r.ev_class = 'public.fv_binding'::regclass AND r.rulename = '_RETURN'}),
				'public|REPLAY', "$label records a dependency on the uppercase function");
		}
	}
}

$node->stop;
done_testing();
