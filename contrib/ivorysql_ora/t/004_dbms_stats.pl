# Copyright 2026 IvorySQL Global Development Team
# Licensed under the Apache License, Version 2.0. See LICENSE.
use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;
use JSON::PP;

my $node = PostgreSQL::Test::Cluster->new('dbms_stats');
$node->init;
$node->start;
my $db = 'ivorysql';
sub sql { return $node->safe_psql($db, $_[0]); }

sub fails
{
	my ($query, $pattern, $name) = @_;
	my ($out, $err);
	my $status = $node->psql($db, $query, stdout => \$out, stderr => \$err);
	isnt($status, 0, $name);
	like($err, $pattern, "$name reports the cause");
}

sql(q{
CREATE SCHEMA stats_test;
CREATE TABLE stats_test.t AS SELECT g AS id, 'value ' || g%7 AS label,
  ARRAY[g%3,g%5] AS elems, int4range(g,g+3) AS span,
  CASE WHEN g%10=0 THEN NULL ELSE g%13 END AS nullable FROM generate_series(1,1000) g;
CREATE INDEX t_expr ON stats_test.t (lower(label));
CREATE INDEX t_id ON stats_test.t (id);
CREATE TABLE stats_test.package_results(mode text, n numeric);
});
for my $mode ('normal', 'interchange', 'lowercase')
{
	my ($out, $err);
	my $status = $node->psql(
		$db, qq{
SET ivorysql.identifier_case_switch = '$mode';
DECLARE n NUMBER; b NUMBER; a NUMBER;
BEGIN
  dbms_stats.gather_table_stats('stats_test','t');
  dbms_stats.get_table_stats(ownname=>'stats_test',tabname=>'t',numrows=>n,numblks=>b,avgrlen=>a);
  INSERT INTO stats_test.package_results VALUES ('$mode', n);
END;
},
		connect_to_oraport => 1,
		stdout => \$out,
		stderr => \$err);
	is($status, 0, "public package works in $mode identifier mode")
	  or diag($err);
	is(sql("SELECT n FROM stats_test.package_results WHERE mode='$mode'"),
		'1000', "public getter returns collected row count in $mode mode");
}
my ($public_out, $public_err);
is( $node->psql(
		$db, q{
SET ivorysql.identifier_case_switch = normal;
DECLARE n NUMBER; b NUMBER; a NUMBER;
BEGIN
  dbms_stats.create_stat_table('stats_test','public_snap');
  dbms_stats.export_table_stats(ownname=>'stats_test',tabname=>'t',stattab=>'public_snap',statid=>'public');
  dbms_stats.set_table_stats(ownname=>'stats_test',tabname=>'t',numrows=>2000);
  dbms_stats.get_table_stats(ownname=>'stats_test',tabname=>'t',numrows=>n,numblks=>b,avgrlen=>a);
  INSERT INTO stats_test.package_results VALUES ('public_set', n);
  dbms_stats.import_table_stats(ownname=>'stats_test',tabname=>'t',stattab=>'public_snap',statid=>'public');
  dbms_stats.get_table_stats(ownname=>'stats_test',tabname=>'t',numrows=>n,numblks=>b,avgrlen=>a);
  INSERT INTO stats_test.package_results VALUES ('public_restore', n);
  dbms_stats.delete_column_stats('stats_test','t','label');
  dbms_stats.delete_table_stats('stats_test','t');
  dbms_stats.gather_schema_stats('stats_test');
  dbms_stats.drop_stat_table('stats_test','public_snap');
END;
},
		connect_to_oraport => 1,
		stdout => \$public_out,
		stderr => \$public_err),
	0,
	'all ten public procedures form a working lifecycle'
) or diag($public_err);
is( sql(q{SELECT n FROM stats_test.package_results WHERE mode='public_set'}),
	'2000', 'public setter changes estimates');
is( sql(q{SELECT n FROM stats_test.package_results WHERE mode='public_restore'}
	),
	'1000',
	'public importer restores estimates');
sql(q{SELECT sys.ora_stats_stattab('stats_test','snap',true);
SELECT sys.ora_stats_export('stats_test','t','snap','original',NULL);
CREATE TABLE stats_test.expected AS SELECT to_jsonb(s) AS value FROM pg_stats s
 WHERE schemaname='stats_test' AND tablename IN ('t','t_expr','t_id');
CREATE TABLE stats_test.expected_relation AS SELECT oid, reltuples, relpages FROM pg_class
 WHERE oid IN ('stats_test.t'::regclass,'stats_test.t_expr'::regclass,'stats_test.t_id'::regclass);
});
is(sql(q{SELECT count(*) FROM stats_test.snap}),
	'1', 'exports one complete snapshot');
sql(q{SELECT sys.ora_stats_set('stats_test','t',99999,NULL)});
is( sql(q{SELECT reltuples FROM pg_class WHERE oid='stats_test.t'::regclass}),
	'99999', 'SET changes planner-visible row statistics');
is( decode_json(sql(q{EXPLAIN (FORMAT JSON) SELECT * FROM stats_test.t}))
	  ->[0]->{Plan}->{'Plan Rows'},
	99999, 'EXPLAIN uses artificial row count');
sql(q{SELECT sys.ora_stats_export('stats_test','t','snap','artificial',NULL);
SELECT sys.ora_stats_delete('stats_test','t')});
is( sql(q{SELECT count(*) FROM pg_stats WHERE schemaname='stats_test'
 AND tablename IN ('t','t_expr','t_id')}),
	'0',
	'DELETE removes table and expression-index column statistics');
sql(q{SELECT sys.ora_stats_import('stats_test','t','snap','original',NULL)});
is( sql(q{SELECT count(*) FROM ((SELECT value FROM stats_test.expected EXCEPT
 SELECT to_jsonb(s) FROM pg_stats s WHERE schemaname='stats_test'
 AND tablename IN ('t','t_expr','t_id')) UNION ALL
 (SELECT to_jsonb(s) FROM pg_stats s WHERE schemaname='stats_test'
 AND tablename IN ('t','t_expr','t_id') EXCEPT SELECT value FROM stats_test.expected)) d}
	),
	'0',
	'round trip preserves every pg_stats field including array, range, NULL and expression statistics'
);
is( sql(q{SELECT count(*) FROM stats_test.expected_relation e JOIN pg_class c USING(oid)
 WHERE e.reltuples IS DISTINCT FROM c.reltuples OR e.relpages IS DISTINCT FROM c.relpages}
	),
	'0',
	'round trip restores table and index row/page estimates');
is( decode_json(sql(q{EXPLAIN (FORMAT JSON) SELECT * FROM stats_test.t}))
	  ->[0]->{Plan}->{'Plan Rows'},
	1000, 'EXPLAIN uses restored row count');
sql(q{SELECT sys.ora_stats_import('stats_test','t','snap','artificial',NULL)}
);
is( sql(q{SELECT reltuples FROM pg_class WHERE oid='stats_test.t'::regclass}),
	'99999', 'statid selects an independent snapshot');
sql(q{BEGIN; SELECT sys.ora_stats_set('stats_test','t',777,NULL); ROLLBACK});
is( sql(q{SELECT reltuples FROM pg_class WHERE oid='stats_test.t'::regclass}),
	'99999', 'statistics changes roll back with caller transaction');
fails(
	q{SELECT sys.ora_stats_import('stats_test','t','snap','missing',NULL)},
	qr/snapshot does not exist/,
	'missing snapshot is rejected');
sql(q{ALTER TABLE stats_test.t ALTER COLUMN label TYPE varchar(50);
SELECT sys.ora_stats_set('stats_test','t',99999,NULL)});
fails(
	q{SELECT sys.ora_stats_import('stats_test','t','snap','original',NULL)},
	qr/no longer matches/,
	'changed column/index definition is rejected');
is( sql(q{SELECT reltuples FROM pg_class WHERE oid='stats_test.t'::regclass}),
	'99999', 'failed import preserves existing statistics');
fails(
	q{SELECT sys.ora_stats_gather('stats_test','t',10,'FOR ALL COLUMNS SIZE AUTO',NULL,NULL)},
	qr/only automatic sampling/,
	'unsupported explicit sampling is rejected');
fails(
	q{SELECT sys.ora_stats_set('stats_test','t',-1,NULL)},
	qr/invalid table statistics/,
	'negative row count is rejected');
fails(
	q{SELECT sys.ora_stats_set('stats_test','t',NULL,1.5)},
	qr/invalid table statistics/,
	'fractional page count is rejected');
fails(
	q{SELECT sys.ora_stats_ident('a.b')},
	qr/single identifier/,
	'qualified strings cannot bypass component validation');
sql(q{CREATE ROLE stats_reader; GRANT USAGE ON SCHEMA stats_test TO stats_reader;
GRANT SELECT ON stats_test.t TO stats_reader});
fails(
	q{SET ROLE stats_reader; SELECT sys.ora_stats_delete('stats_test','t')},
	qr/permission denied/,
	'SELECT-only role cannot change statistics');
sql(q{CREATE ROLE stats_maintainer; GRANT USAGE ON SCHEMA stats_test TO stats_maintainer;
GRANT MAINTAIN ON stats_test.t TO stats_maintainer});
like(
	sql(q{SET ROLE stats_maintainer; SELECT sys.ora_stats_set('stats_test','t',123,NULL);
 SELECT reltuples FROM pg_class WHERE oid='stats_test.t'::regclass}),
	qr/^\s*123$/,
	'MAINTAIN permits table statistics updates');
fails(
	q{SET ROLE stats_maintainer; SELECT sys.ora_stats_export('stats_test','t','snap','x',NULL)},
	qr/export requires SELECT/,
	'export requires row visibility in addition to MAINTAIN');
sql(q{CREATE TABLE stats_test."Mixed Table" ("Mixed Column" int);
INSERT INTO stats_test."Mixed Table" VALUES (1),(2);
SELECT sys.ora_stats_gather('stats_test','"Mixed Table"',0,'FOR ALL COLUMNS SIZE AUTO',NULL,NULL)}
);
is( sql(q{SELECT numrows FROM sys.ora_stats_get('stats_test','"Mixed Table"')}
	),
	'2',
	'quoted identifiers survive resolution');
sql(q{SELECT sys.ora_stats_delete('stats_test','"Mixed Table"','"Mixed Column"')}
);
is( sql(q{SELECT count(*) FROM pg_stats WHERE schemaname='stats_test' AND tablename='Mixed Table'}
	),
	'0',
	'deletes a single quoted column');
sql(q{SELECT sys.ora_stats_gather_schema('stats_test',0,'FOR ALL COLUMNS SIZE AUTO',NULL,NULL)}
);
is( sql(q{SELECT count(*) > 0 FROM pg_stats WHERE schemaname='stats_test' AND tablename='Mixed Table'}
	),
	't',
	'schema collection visits tables');
sql(q{SELECT sys.ora_stats_stattab('stats_test','snap',false)});
is(sql(q{SELECT to_regclass('stats_test.snap') IS NULL}),
	't', 'drops the snapshot table');
$node->stop;
done_testing();
