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
#
# Verify the versioned upgrade path of the catalog metadata corrections:
# the 1.0 installation scripts are frozen, so a cluster installed at 1.0
# (including one preserved through pg_upgrade) only reaches the corrected
# parallel-safety/volatility/strictness state after
# ALTER EXTENSION ... UPDATE.  A fresh install at the current default
# version must reach the same state through the same update chain, because
# only the 1.0 install script and the 1.0--1.1 update script exist.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# The check harness shares an initdb template built in native PG mode, but
# the extension scripts create packages and therefore need an oracle-mode
# cluster; build a dedicated node instead of copying that template.
delete $ENV{INITDB_TEMPLATE};

my $node = PostgreSQL::Test::Cluster->new('upgrade');
$node->init(
	extra => [ '--locale=C', '--encoding=UTF8', '-m', 'oracle', '-C', 'normal' ]);

$node->start;

# CREATE EXTENSION parses package definitions with the Oracle parser, which
# only the second (ivorysql.port) listener speaks; Cluster::init assigned a
# free port for it, so read it back from the node configuration.
my ($oracle_port) = slurp_file($node->data_dir . '/postgresql.conf')
  =~ /^ivorysql\.port\s*=\s*(\d+)/m;
ok($oracle_port, 'oracle port is configured') or BAIL_OUT('no ivorysql.port');

# A -p switch loses to the conninfo string safe_psql passes to --dbname, so
# hand psql a complete conninfo of our own as the last -d instead.
sub oracle_sql
{
	my ($db, $sql) = @_;
	return $node->safe_psql($db, $sql,
		extra_params =>
		  [ '-d', sprintf('host=%s port=%d dbname=%s', $node->host, $oracle_port, $db) ]);
}

# Reinstalling the extension from scratch in a database that inherits it
# from the template drops the sys."c" collation together with the
# extension, so put the pieces the scripts rely on back first.
my $reset = q{
	DROP EXTENSION IF EXISTS ivorysql_ora CASCADE;
	CREATE SCHEMA IF NOT EXISTS sys;
	CREATE COLLATION IF NOT EXISTS sys."c" FROM "C";
};

# Parallel/volatile/strict state of the functions corrected by 1.1.
my $probe = q{
	SELECT format('%%s/%%s/%%s', proparallel, provolatile, proisstrict)
	FROM pg_proc WHERE oid = %s::regprocedure
};

sub state
{
	my ($db, $func) = @_;
	return oracle_sql($db, sprintf($probe, "'" . $func . "'"));
}

my @probes = (
	# parallel safety corrected by the 1.1 update
	[ 'sys.bool_orachar(boolean)',            'u/i/t', 's/i/t' ],
	[ 'sys.generate_series(number,number)',   'u/i/f', 's/i/f' ],
	[ 'sys.oravarcharcat(sys.oravarcharchar,sys.oravarcharchar)',
	  'u/i/f', 's/i/f' ],
	# strictness and volatility corrected by the 1.1 update
	[ 'sys.lengthb(bytea)',                   's/v/f', 's/i/t' ]);

# An existing cluster installed at 1.0 keeps the old metadata ...
oracle_sql('postgres', 'CREATE DATABASE upgrade_test');
oracle_sql('upgrade_test',
	$reset . "CREATE EXTENSION ivorysql_ora VERSION '1.0';");

is( $node->safe_psql(
		'upgrade_test',
		"SELECT extversion FROM pg_extension WHERE extname = 'ivorysql_ora'"),
	'1.0',
	'extension is installed at 1.0');

for my $p (@probes)
{
	is(state('upgrade_test', $p->[0]),
		$p->[1], "$p->[0] keeps the 1.0 metadata");
}

# ... and reaches the corrected state after ALTER EXTENSION UPDATE.
oracle_sql('upgrade_test', 'ALTER EXTENSION ivorysql_ora UPDATE');

is( $node->safe_psql(
		'upgrade_test',
		"SELECT extversion FROM pg_extension WHERE extname = 'ivorysql_ora'"),
	'1.1',
	'ALTER EXTENSION UPDATE moves the extension to 1.1');

for my $p (@probes)
{
	is(state('upgrade_test', $p->[0]),
		$p->[2], "$p->[0] has the corrected metadata after the upgrade");
}

# A fresh install at the default version goes through the same update
# chain, so it must land in the same state.
oracle_sql('postgres', 'CREATE DATABASE fresh_test');
oracle_sql('fresh_test', $reset . 'CREATE EXTENSION ivorysql_ora;');

is( $node->safe_psql(
		'fresh_test',
		"SELECT extversion FROM pg_extension WHERE extname = 'ivorysql_ora'"),
	'1.1',
	'fresh install uses the default version 1.1');

for my $p (@probes)
{
	is(state('fresh_test', $p->[0]),
		$p->[2], "$p->[0] is corrected in a fresh install as well");
}

$node->stop;
done_testing();
