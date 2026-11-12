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
# End-to-end test of the two listening sockets of one IvorySQL cluster.
#
# An IvorySQL postmaster binds the PostgreSQL-compatible socket ("port") and the
# Oracle-compatible socket ("ivorysql.port") for the same data directory.
# backend_startup.c derives port->connmode from the *local* port number of the
# accepted connection, and InitIvorysql() in src/backend/tcop/postgres.c turns
# that into ivorysql.compatible_mode = pg | oracle before the first statement is
# parsed.  So which socket a client connects to decides the dialect of the
# session, not the database mode the cluster was initialized with.
#
# Nothing else in the tree opens both sockets of one cluster, so a change that
# collapsed the two compatibility modes into one, or that dropped/renamed the
# second listener, would not be caught by any existing test.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('dual_listener');

# Oracle database mode is the interesting case: an Oracle-mode cluster still
# answers in PostgreSQL compatibility mode on the "port" socket.  Cluster.pm
# hardcodes "-m pg" and appends %params{extra} after it, so the later -m wins.
$node->init( extra => [ '-m', 'oracle' ] );
$node->start;

# A server without the Oracle listening socket would not know this parameter.
# Current builds always have it (configure only has --with-oraport), so this
# guard is a safety net rather than a path that is normally taken.
my ($ora_ret, $ora_port) = $node->psql('postgres', 'SHOW ivorysql.port');
if ($ora_ret != 0 || $ora_port !~ /^\d+$/)
{
	plan skip_all => 'this server has no ivorysql.port listening socket';
}

my $pg_port = $node->port;
my $pg_connstr = $node->connstr('postgres');
my $ora_connstr =
  sprintf( "port=%s host=%s dbname='postgres'", $ora_port, $node->host );

is( $node->safe_psql('postgres', 'SHOW ivorysql.database_mode'),
	'oracle', 'cluster was initialized in Oracle database mode');
isnt( $ora_port, $pg_port,
	"ivorysql.port ($ora_port) is a separate listening port");

# 1) both sockets of the same postmaster accept connections
my ($ret, $out, $err) = $node->psql('postgres', 'SELECT 1', connstr => $pg_connstr);
is( $ret, 0, "connected on the PostgreSQL socket (port $pg_port)" )
  or diag "stderr: $err";

($ret, $out, $err) = $node->psql('postgres', 'SELECT 1', connstr => $ora_connstr);
is( $ret, 0, "connected on the Oracle socket (port $ora_port)" )
  or diag "stderr: $err";

# 2) the same instance reports a different compatibility mode per socket
is( $node->safe_psql('postgres', 'SHOW ivorysql.compatible_mode'),
	'pg', 'the PostgreSQL socket runs in pg compatibility mode');

($ret, $out, $err) =
  $node->psql('postgres', 'SHOW ivorysql.compatible_mode',
	connstr => $ora_connstr);
is( $ret, 0, 'read compatible_mode over the Oracle socket' )
  or diag "stderr: $err";
is( $out, 'oracle', 'the Oracle socket runs in oracle compatibility mode');

# 3) Oracle-only syntax is accepted on the Oracle socket and rejected on the
#    PostgreSQL socket.  "dual" is the canonical example: it is resolved
#    through the Oracle-style search path, so on the PostgreSQL socket the
#    parser cannot find the relation at all.
($ret, $out, $err) =
  $node->psql('postgres', 'SELECT 1 FROM dual', connstr => $pg_connstr);
isnt( $ret, 0, 'SELECT 1 FROM dual is rejected on the PostgreSQL socket' );
like( $err, qr/relation "dual" does not exist/,
	'... with a relation-does-not-exist error' );

($ret, $out, $err) =
  $node->psql('postgres', 'SELECT 1 FROM dual', connstr => $ora_connstr);
is( $ret, 0, 'SELECT 1 FROM dual runs on the Oracle socket' )
  or diag "stderr: $err";
is( $out, '1', '... and returns 1' );

# The Oracle type mapping is installed for Oracle-mode sessions only.
($ret, $out, $err) = $node->psql('postgres',
	'CREATE TABLE dual_listener_v2 (c varchar2(10))', connstr => $pg_connstr);
isnt( $ret, 0, 'varchar2 is rejected on the PostgreSQL socket' );
like( $err, qr/type "varchar2" does not exist/,
	'... with a type-does-not-exist error' );

($ret, $out, $err) = $node->psql('postgres',
	'CREATE TABLE dual_listener_v2 (c varchar2(10))', connstr => $ora_connstr);
is( $ret, 0, 'varchar2 is accepted on the Oracle socket' )
  or diag "stderr: $err";

# Both sockets reach the same database, so what the Oracle socket created is
# visible from the PostgreSQL socket.
is( $node->safe_psql('postgres', 'SELECT count(*) FROM dual_listener_v2'),
	'0',
	'a table created through the Oracle socket is visible on the PostgreSQL socket'
);

$node->stop;

done_testing();