# Copyright (c) 2026, PostgreSQL Global Development Group

# Test log_statement_max_length GUC: verifies that logged statement text is
# truncated at the specified byte limit, respecting multibyte boundaries, for
# both log_statement and log_min_duration_statement logging.

use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('primary');
$node->init();
$node->start;

# Verify ASCII truncation. With log_statement_max_length = 20,
# a 24-byte query should end at the 20th byte ('C').
note "ASCII truncation via log_statement";
my $log_offset = -s $node->logfile;
$node->psql(
	'postgres', "
	SET log_statement_max_length TO 20;
	SELECT '123456789ABCDEF';");
ok($node->log_contains(qr/statement: SELECT '123456789ABC$/m, $log_offset),
	"ASCII query truncated at 20 bytes");

# Verify -1 logs statement in full (closing quote must be present).
note "-1 logs statement in full";
$log_offset = -s $node->logfile;
$node->psql(
	'postgres', "
	SET log_statement_max_length TO -1;
	SELECT '123456789ABCDEF';");
ok( $node->log_contains(qr/statement: SELECT '123456789ABCDEF'/, $log_offset),
	"-1 logs full query");

# Verify multibyte character handling: truncation must not split a multibyte
# character when the byte limit falls in the middle of it.
SKIP:
{
	skip "UTF8 database encoding required for multibyte truncation test", 1
	  unless $node->safe_psql('postgres', 'SHOW server_encoding') eq 'UTF8';

	note "Multibyte truncation respects character boundaries";
	my $mbchar = pack("C*", 0xC4, 0x80);    # U+0100 in UTF-8
	my $mbquery = "SELECT 'AA${mbchar}Z';";
	$log_offset = -s $node->logfile;
	$node->psql(
		'postgres', "
		SET client_encoding TO 'UTF8';
		SET log_statement_max_length TO 11;
		$mbquery");
	ok($node->log_contains(qr/statement: SELECT 'AA$/m, $log_offset),
		"multibyte truncation at character boundary");
}

# Verify 0 logs an empty statement body.
note "Zero length truncation";
$log_offset = -s $node->logfile;
$node->psql(
	'postgres', "
	SET log_statement_max_length TO 0;
	SELECT '123456789ABCDEF';");
ok($node->log_contains(qr/statement:\s*$/m, $log_offset),
	"0 logs an empty statement body");

# Verify truncation via the extended query protocol (execute message).
# With log_statement_max_length = 20, a 24-byte query should end
# at the 20th byte ('C').
note "Extended query protocol (execute) truncation";
$log_offset = -s $node->logfile;
$node->psql(
	'postgres', "
	SET log_statement_max_length TO 20;
	SELECT '123456789ABCDEF' \\bind \\g");
ok( $node->log_contains(
		qr/execute <unnamed>: SELECT '123456789ABC$/m, $log_offset),
	"extended protocol execute truncated at 20 bytes");

# Verify extended protocol also respects -1 (no truncation; closing quote
# present).
note "Extended query protocol with -1 (no truncation)";
$log_offset = -s $node->logfile;
$node->psql(
	'postgres', "
	SET log_statement_max_length TO -1;
	SELECT '123456789ABCDEF' \\bind \\g");
ok( $node->log_contains(
		qr/execute <unnamed>: SELECT '123456789ABCDEF'/, $log_offset),
	"extended protocol -1 logs full query");

# Verify truncation applies to the parse/bind/execute duration log entries
# emitted by log_min_duration_statement.  log_statement must be 'none' to
# ensure the duration entries include the statement text.
note "Duration logging via log_min_duration_statement";
$log_offset = -s $node->logfile;
$node->psql(
	'postgres', "
	SET log_statement TO 'none';
	SET log_min_duration_statement TO 0;
	SET log_statement_max_length TO 20;
	SELECT '123456789ABCDEF' \\bind \\g");
ok( $node->log_contains(
		qr/parse <unnamed>: SELECT '123456789ABC$/m, $log_offset),
	"parse duration entry truncated");
ok( $node->log_contains(
		qr/bind <unnamed>: SELECT '123456789ABC$/m, $log_offset),
	"bind duration entry truncated");
ok( $node->log_contains(
		qr/execute <unnamed>: SELECT '123456789ABC$/m, $log_offset),
	"execute duration entry truncated");

$node->stop;
done_testing();
