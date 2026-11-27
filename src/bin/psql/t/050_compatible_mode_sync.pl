
# Copyright (c) 2021-2026, IvorySQL Global Development Group

# Test that psql's internal parser mode tracks ivorysql.compatible_mode as the
# server reports it, so that "SET ivorysql.compatible_mode" switches the parser
# immediately, without first running "\parser" (issue #1403).
#
# The observable is the SQL*Plus client command "variable": psql only intercepts
# it (in interactive use it prints "No bind variables declared.") when its
# internal mode is oracle.  In pg mode the bare word is shipped to the server as
# SQL and raises a syntax error.  This therefore reflects psql's own cached
# parser state rather than the server's, since "\parser" (which would re-query
# the server) is never run here.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# A DB_ORACLE cluster is required: check_compatible_mode refuses to switch
# compatible_mode to oracle on a native-PG (DB_PG) cluster.  Cluster.pm
# initializes clusters with "initdb -m pg"; appending "-m oracle" yields a
# DB_ORACLE cluster.  (The session still starts in pg compatible mode.)
local $ENV{PG_TEST_INITDB_EXTRA_OPTS} = '-m oracle';

my $node = PostgreSQL::Test::Cluster->new('parser_sync');
$node->init;
$node->start;

# At session start compatible_mode is pg, so "variable" is unknown SQL.
my ($ret, $stdout, $stderr) = $node->psql('postgres', 'variable');
isnt($ret, 0, "pg mode: 'variable' is rejected");
like(
	$stderr,
	qr/syntax error at or near "variable"/i,
	"pg mode: 'variable' is sent to the server and errors");

# Switch the session to oracle WITHOUT a manual "\parser".  psql's parser mode
# must follow the reported change, so "variable" is now intercepted by psqlplus
# instead of being shipped to the server (which would reject it).
($ret, $stdout, $stderr) = $node->psql('postgres',
	"SET ivorysql.compatible_mode = oracle;\nvariable");
is($ret, 0, "oracle mode: SET then 'variable' succeed without \\parser");
unlike(
	$stderr,
	qr/syntax error/i,
	"oracle mode: 'variable' is intercepted client-side, not sent to server");

# Switching back to pg within the same session must restore pg parsing.
($ret, $stdout, $stderr) = $node->psql('postgres',
	"SET ivorysql.compatible_mode = oracle;\n"
	  . "SET ivorysql.compatible_mode = pg;\nvariable");
isnt($ret, 0, "back to pg: 'variable' is rejected again");
like(
	$stderr,
	qr/syntax error at or near "variable"/i,
	"back to pg: 'variable' errors again after SET pg");

$node->stop;

done_testing();
