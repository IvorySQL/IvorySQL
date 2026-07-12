
# Copyright (c) 2026, PostgreSQL Global Development Group

# Test psql's %o prompt escape.  The escape prints "[ORA]" when the connected
# IvorySQL server reports the session's compatibility mode
# (ivorysql.compatible_mode) as "oracle", and expands to nothing otherwise.
#
# The default regression cluster is initialized in "pg" database mode, so
# compatible_mode is "pg" here and %o must expand to nothing.  The full
# "[ORA]" path is exercised against Oracle-mode clusters by the oracle
# regression suite; this test guards the client-side escape handling in the
# standard (pg-mode) test environment.

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

# start a new server
my $node = PostgreSQL::Test::Cluster->new('main');
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

# done
$node->stop;
done_testing();
