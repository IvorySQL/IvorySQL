
# Copyright (c) 2021-2026, PostgreSQL Global Development Group

# Test psql's %o prompt escape.  The escape prints "[ORA]" when the connected
# IvorySQL server reports the session's compatibility mode
# (ivorysql.compatible_mode) as "oracle", and expands to nothing otherwise.
#
# Both paths are exercised here against real IvorySQL clusters started by the
# TAP harness:
#   * a default pg-mode cluster, where %o must expand to nothing;
#   * an Oracle-mode cluster where compatible_mode is switched to oracle
#     in-session, where %o must expand to "[ORA]".

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# A pty is required for psql to print prompts at all.
eval { require IO::Pty; };
if ($@)
{
	plan skip_all => 'IO::Pty is needed to run this test';
}

# ---------------------------------------------------------------------------
# pg-mode cluster: %o expands to nothing.
# ---------------------------------------------------------------------------
{
my $node = PostgreSQL::Test::Cluster->new('pgmode');
$node->init;
$node->start;

my $h = $node->interactive_psql('postgres');

# interactive_psql drains the startup banner, so a prompt is only observed in
# the output captured for a *later* command.  To reliably capture the prompt
# that is printed between two commands, send a primer command followed by a
# real command, and match the real command's result on its own line (so the
# pump reads well past the primer and its trailing prompt).  Note that pty
# output uses CR/LF line endings.

# Default prompt ('%o%/%R%x%# '): %o must be recognized and expand to nothing,
# so the prompt still reads "postgres=# " with no literal "%o".
my $out = $h->query_until(
	qr/^res1\r?$/m,
	"select 'primer' as p;\nselect 'res1' as r;\n");
like(
	$out,
	qr/postgres/,
	"default prompt is shown in interactive mode");
unlike(
	$out,
	qr/%o/,
	"default prompt expands %o to nothing in pg mode");

# Isolate %o with recognizable markers.  In pg mode it must expand to nothing,
# so the rendered prompt becomes "BEFORE[]AFTER".
$h->query_until(
	qr/^ok1\r?$/m,
	"\\set PROMPT1 'BEFORE[%o]AFTER'\nselect 'p2' as p;\nselect 'ok1' as r;\n");
$out = $h->query_until(
	qr/^res2\r?$/m,
	"select 'p3' as p;\nselect 'res2' as r;\n");
like(
	$out,
	qr/BEFORE\[\]AFTER/,
	"%o expands to nothing when compatible_mode is pg");

# Confirm the value %o keys off of.
my $mode = $h->query_until(qr/^pg\r?$/m, "show ivorysql.compatible_mode;\n");
like($mode, qr/^pg\r?$/m, "compatible_mode is pg in a pg-mode cluster");

# send psql an explicit \q to shut it down, else pty won't close properly
$h->quit or die "psql returned $?";

$node->stop;
}

# ---------------------------------------------------------------------------
# Oracle-mode cluster: %o expands to "[ORA]".
# ---------------------------------------------------------------------------
{
# Cluster.pm initializes clusters with `initdb -m pg`; appending `-m oracle`
# creates an Oracle-mode (database_mode = DB_ORACLE) cluster, the only mode in
# which compatible_mode may be switched to oracle.
local $ENV{PG_TEST_INITDB_EXTRA_OPTS} = '-m oracle';

my $node = PostgreSQL::Test::Cluster->new('oraclemode');
$node->init;
$node->start;

my $h = $node->interactive_psql('postgres');

# Switch the session to oracle compatibility, then isolate %o with markers.
# After the SET, the server reports compatible_mode = oracle, so the rendered
# prompt must become "BEFORE[ORA]AFTER".
$h->query_until(
	qr/^ok2\r?$/m,
	"SET ivorysql.compatible_mode = oracle;\n"
	  . "\\set PROMPT1 'BEFORE%oAFTER'\n"
	  . "select 'p4' as p;\nselect 'ok2' as r;\n");
my $out = $h->query_until(
	qr/^res3\r?$/m,
	"select 'p5' as p;\nselect 'res3' as r;\n");
like(
	$out,
	qr/BEFORE\[ORA\]AFTER/,
	"%o expands to [ORA] when compatible_mode is oracle");

# Confirm the value %o keys off of.
my $mode = $h->query_until(qr/^oracle\r?$/m, "show ivorysql.compatible_mode;\n");
like($mode, qr/^oracle\r?$/m,
	"compatible_mode is oracle in an oracle-mode session");

$h->quit or die "psql returned $?";

$node->stop;
}

done_testing();
