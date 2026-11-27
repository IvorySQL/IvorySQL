# Copyright 2026 IvorySQL Global Development Team
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('extension_upgrade');
$node->init;
$node->start;

my $upgrade_db = 'ivorysql_ora_upgrade';
my $fresh_db = 'ivorysql_ora_fresh';

$node->safe_psql('postgres', "CREATE DATABASE $upgrade_db");
$node->safe_psql('postgres', "CREATE DATABASE $fresh_db");

$node->safe_psql(
	$upgrade_db,
	q{
		DROP EXTENSION IF EXISTS ivorysql_ora;
		SET ivorysql.compatible_mode = oracle;
		CREATE EXTENSION ivorysql_ora VERSION '1.0';
	});
is( $node->safe_psql(
		$upgrade_db,
		"SELECT extversion FROM pg_extension WHERE extname = 'ivorysql_ora'"),
	'1.0',
	'1.0 extension installs');

# Simulate an existing 1.0 installation that predates sys.nchar_cs.
$node->safe_psql(
	$upgrade_db,
	q{
		ALTER EXTENSION ivorysql_ora DROP COLLATION sys.nchar_cs;
		DROP COLLATION sys.nchar_cs;
	});

$node->safe_psql(
	$upgrade_db,
	"ALTER EXTENSION ivorysql_ora UPDATE TO '1.1'");
is( $node->safe_psql(
		$upgrade_db,
		"SELECT extversion FROM pg_extension WHERE extname = 'ivorysql_ora'"),
	'1.1',
	'1.0 extension upgrades to 1.1');
is( $node->safe_psql(
		$upgrade_db,
		q{SELECT count(*) FROM pg_collation
		  WHERE collnamespace = 'sys'::regnamespace
		    AND collname = 'nchar_cs'}),
	'1',
	'upgrade creates the NCHAR collation');

$node->safe_psql(
	$fresh_db,
	q{
		DROP EXTENSION IF EXISTS ivorysql_ora;
		SET ivorysql.compatible_mode = oracle;
		CREATE EXTENSION ivorysql_ora;
	});
is( $node->safe_psql(
		$fresh_db,
		"SELECT extversion FROM pg_extension WHERE extname = 'ivorysql_ora'"),
	'1.1',
	'a fresh installation uses version 1.1');
is( $node->safe_psql(
		$fresh_db,
		q{SELECT count(*) FROM pg_collation
		  WHERE collnamespace = 'sys'::regnamespace
		    AND collname = 'nchar_cs'}),
	'1',
	'a fresh installation creates the NCHAR collation');

done_testing();
