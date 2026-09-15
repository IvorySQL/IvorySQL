# Copyright 2026 IvorySQL Global Development Team
# SPDX-License-Identifier: Apache-2.0

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# Preserve user ACL configuration even though initdb extensions do not dump their definitions.
my $node = PostgreSQL::Test::Cluster->new('network_acl');
$node->init(extra => ['-m', 'oracle', '-C', 'normal']);
$node->start;
my $tempdir = PostgreSQL::Test::Utils::tempdir;

$node->safe_psql('postgres', 'CREATE ROLE acl_dump_user');
$node->safe_psql('postgres', 'CREATE DATABASE acl_source TEMPLATE template0');
$node->safe_psql('postgres', 'CREATE DATABASE acl_target TEMPLATE template0');
$node->safe_psql('acl_source', q{
  SELECT sys.network_acl_admin('create', 'dump.xml', 'acl_dump_user', true, 'resolve');
  SELECT sys.network_acl_admin('assign', 'dump.xml', host_name => '127.0.0.1');
});
my $lookup = q{SET ROLE acl_dump_user;
  SELECT sys.utl_inaddr_get_host_address('127.0.0.1')};
is($node->safe_psql('acl_source', $lookup), '127.0.0.1',
   'source ACL permits invoking user');

$node->command_ok(
  ['pg_dump', '--dbname=' . $node->connstr('acl_source'),
   '-Fc', '--file=' . "$tempdir/acl.dump"],
  'dump built-in extension configuration');

# Change the role OID to verify that regrole values restore by name.
my $old_oid = $node->safe_psql('postgres', q{SELECT 'acl_dump_user'::regrole::oid});
$node->safe_psql('postgres', 'DROP ROLE acl_dump_user; CREATE ROLE acl_dump_user');
isnt($node->safe_psql('postgres', q{SELECT 'acl_dump_user'::regrole::oid}),
     $old_oid, 'recreated role has a different OID');
is($node->safe_psql('acl_source', q{
  SELECT sys.network_acl_check('127.0.0.1', 'acl_dump_user'::regrole::oid)
}), 'f', 'old ACL does not authorize recreated role');

$node->command_ok(
  ['pg_restore', '--dbname=' . $node->connstr('acl_target'),
   '--exit-on-error', "$tempdir/acl.dump"],
  'restore configuration into initialized database');
is($node->safe_psql('acl_target', $lookup), '127.0.0.1',
   'restored ACL resolves role by name');
is($node->safe_psql('acl_target', 'SELECT count(*) FROM sys.network_acl_host'),
   '1', 'host assignment restored');

# Honor dump filters that exclude the extension or the sys schema.
for my $filter ('--exclude-extension=ivorysql_ora', '--exclude-schema=sys')
{
  $node->command_ok(
    ['pg_dump', '--dbname=' . $node->connstr('acl_target'),
     $filter, '--file=' . "$tempdir/excluded.sql"],
    "dump with $filter");
  unlike(slurp_file("$tempdir/excluded.sql"), qr/COPY sys\.network_acl/,
         'excluded ACL configuration is not dumped');
}

$node->stop;
done_testing();
