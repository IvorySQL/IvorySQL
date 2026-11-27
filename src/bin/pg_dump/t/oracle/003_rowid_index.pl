# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('rowid_index');
$node->init;
$node->start;
my $tempdir = PostgreSQL::Test::Utils::tempdir;
my $port = $node->oraport;

$node->safe_psql('postgres', 'CREATE DATABASE rowid_source');
$node->safe_psql(
	'rowid_source',
	q{
CREATE SCHEMA rowid_schema;
CREATE TABLE rowid_schema.tb1_tioro019161645 (a int, b int) WITH ROWID;
CREATE TABLE rowid_schema.t2 (a int, b int) WITH ROWID;
INSERT INTO rowid_schema.tb1_tioro019161645 VALUES (11, 22), (33, 44);
INSERT INTO rowid_schema.t2 VALUES (21, 31), (41, 51);
},
	connect_to_oraport => 1);

# A renamed automatic index and a same-key user index must be distinguished.
my $source_t2_oid = $node->safe_psql('rowid_source',
	q{SELECT 'rowid_schema.t2'::regclass::oid});
my $user_index = "t2_${source_t2_oid}_rowid_idx";
$node->safe_psql(
	'rowid_source',
	"ALTER INDEX rowid_schema.$user_index RENAME TO t2_generated;
	 CREATE INDEX $user_index ON rowid_schema.t2 (rowid)",
	connect_to_oraport => 1);

my $data_query = q{
SELECT a, b, (rowid).rowno, (rowid).rowoid = tableoid
  FROM rowid_schema.tb1_tioro019161645
UNION ALL
SELECT a, b, (rowid).rowno, (rowid).rowoid = tableoid FROM rowid_schema.t2
ORDER BY a;
};
my $expected_data =
  $node->safe_psql('rowid_source', $data_query, connect_to_oraport => 1);
my $source_oid = $node->safe_psql('rowid_source',
	q{SELECT 'rowid_schema.tb1_tioro019161645'::regclass::oid});

my $index_query = q{
SELECT i.relname
  FROM pg_catalog.pg_index x
  JOIN pg_catalog.pg_class i ON i.oid = x.indexrelid
 WHERE x.indrelid IN ('rowid_schema.tb1_tioro019161645'::regclass,
                      'rowid_schema.t2'::regclass)
   AND x.indisvalid AND x.indisready
 ORDER BY i.relname COLLATE "C";
};

for my $scope ('database', 'schema')
{
	my @selection = $scope eq 'schema' ? ('-n', 'rowid_schema') : ();
	for my $format ('plain', 'custom')
	{
		my $label = "${scope}_${format}";
		my $dump = "$tempdir/$label";
		$node->command_ok(
			['pg_dump', '-p', $port, '-d', 'rowid_source', @selection,
			 "--format=$format", '-f', $dump],
			"$label dump");
		$node->safe_psql('postgres', "CREATE DATABASE $label");
		if ($format eq 'plain')
		{
			$node->command_ok(
				['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-p', $port, '-d',
				 $label, '-f', $dump],
				"$label restore");
		}
		else
		{
			$node->command_ok(
				['pg_restore', '--exit-on-error', '-p', $port, '-d', $label,
				 $dump],
				"$label restore");
		}

		my ($oid1, $oid2) = split /\|/,
		  $node->safe_psql($label, q{
SELECT 'rowid_schema.tb1_tioro019161645'::regclass::oid,
       'rowid_schema.t2'::regclass::oid;
});
		isnt($oid1, $source_oid, "$label assigned a new table OID");
		is($node->safe_psql($label, $index_query),
			join("\n", sort("tb1_tioro019161645_${oid1}_rowid_idx",
					"t2_${oid2}_rowid_idx", $user_index)),
			"$label uses the restored table OIDs and keeps the user index");
		is($node->safe_psql($label, $data_query, connect_to_oraport => 1),
			$expected_data, "$label restored the inserted rows");
	}
}

$node->stop;
done_testing();
