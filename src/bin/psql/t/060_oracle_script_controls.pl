# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('oracle_script_controls');
$node->init(extra => [ '-m', 'oracle' ]);
my $ora_port = PostgreSQL::Test::Cluster::get_free_port();
$node->append_conf('postgresql.conf', "ivorysql.port = $ora_port");
$node->start;

my $connstr = $node->connstr('postgres') . " port=$ora_port";
my $marker = "\\echo after_command\n";
my @failures = (
	[ 'VARIABLE n NUMBER = invalid', qr/is not a valid NUMBER/ ],
	[ "VARIABLE n NUMBER = 7\nVARIABLE n = invalid",
		qr/is not a valid NUMBER/ ],
	[ 'VARIABLE missing', qr/Bind variable "missing" not declared/i ],
	[ 'PRINT missing', qr/Bind variable "missing" not declared/i ],
	[ 'PRINT 1bad', qr/invalid host\/bind variable name/i ],
	[ 'VARIABLE n unknown_type', qr/Usage: VAR\[IABLE\]/ ],
);

for my $case (@failures)
{
	my ($command, $error) = @$case;
	my ($ret, $stdout, $stderr) =
	  $node->psql('postgres', "$command\n$marker", connstr => $connstr);
	is($ret, 3, "$command exits with the script error status");
	like($stderr, $error, "$command reports its error");
	unlike($stdout, qr/^after_command$/m, "$command stops the script");
}

my ($ret, $stdout, $stderr) = $node->psql('postgres',
	"PRINT missing\n$marker", connstr => $connstr, on_error_stop => 0);
is($ret, 0, 'psql continues after a command error with ON_ERROR_STOP off');
like($stderr, qr/not declared/i, 'continuing still reports the error');
like($stdout, qr/^after_command$/m, 'the following command runs');

my $conditional_script = <<'PSQL';
VARIABLE n NUMBER = 7
\if false
VARIABLE n = 17
PRINT missing
VARIABLE n unknown_type
\endif
PRINT n
PSQL
($ret, $stdout, $stderr) =
  $node->psql('postgres', $conditional_script, connstr => $connstr);
is($ret, 0, 'Oracle client commands in an inactive branch are skipped');
is($stderr, '', 'the inactive commands emit no errors');
is($stdout, '7', 'the inactive assignment leaves the value unchanged');

my $failed_transaction = <<'PSQL';
BEGIN;
SELECT 1 / 0;
\if false
VARIABLE n CHAR(10) = 'unterminated
VARIABLE v VARCHAR2(10)
\endif
ROLLBACK;
\echo after_command
PSQL
($ret, $stdout, $stderr) = $node->psql('postgres',
	$failed_transaction, connstr => $connstr, on_error_stop => 0);
is($ret, 0, 'inactive declarations are skipped in a failed transaction');
like($stderr, qr/division by zero/i, 'the transaction fails as intended');
unlike($stderr, qr/current transaction is aborted|missing terminating quote/i,
	'inactive declarations do not query the server or report errors');
like($stdout, qr/^after_command$/m, 'the script continues after rollback');

my $active_declaration = <<'PSQL';
BEGIN;
SELECT 1 / 0;
VARIABLE n CHAR(10)
ROLLBACK;
\echo after_command
PSQL
($ret, $stdout, $stderr) = $node->psql('postgres',
	$active_declaration, connstr => $connstr, on_error_stop => 0);
is($ret, 0, 'a failed length semantics lookup does not crash psql');
like($stderr, qr/current transaction is aborted/i,
	'the active declaration reports the lookup error');
like($stdout, qr/^after_command$/m, 'the active script continues after rollback');

my $failed_type_lookup = <<'PSQL';
VARIABLE n NUMBER = 7
\set ON_ERROR_STOP off
BEGIN;
SELECT 1 / 0;
\set ON_ERROR_STOP on
VARIABLE n
\echo after_command
PSQL
($ret, $stdout, $stderr) =
  $node->psql('postgres', $failed_type_lookup, connstr => $connstr);
is($ret, 3, 'a failed bind variable type lookup stops the script');
like($stderr, qr/current transaction is aborted/i, 'the lookup reports its error');
is($stdout, '', 'the failed lookup leaves no output and stops further commands');

my $pending_query = <<'PSQL';
SELECT (40
\if false
VARIABLE n NUMBER
VARIABLE n unknown_type
\endif
+ 2);
PSQL
($ret, $stdout, $stderr) =
  $node->psql('postgres', $pending_query, connstr => $connstr);
is($ret, 0, 'psql completes a pending query after an inactive branch');
is($stderr, '', 'skipping client commands emits no errors');
is($stdout, '42', 'skipping client commands preserves the pending SQL');

$node->stop;
done_testing();
