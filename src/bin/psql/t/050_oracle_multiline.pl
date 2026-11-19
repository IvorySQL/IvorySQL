# Copyright (c) 2026, IvorySQL Global Development Team

# Readline can return a whole multiline paste as one input buffer.  A slash
# on a line of its own must still submit an Oracle anonymous block.
use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

if (!defined($ENV{with_readline}) || $ENV{with_readline} ne 'yes')
{
	plan skip_all => 'readline is not supported by this build';
}
if (defined($ENV{SKIP_READLINE_TESTS}))
{
	plan skip_all => 'SKIP_READLINE_TESTS is set';
}
eval { require IO::Pty; };
if ($@)
{
	plan skip_all => 'IO::Pty is needed to run this test';
}

my $node = PostgreSQL::Test::Cluster->new('oracle_multiline');
$node->init(extra => [ '-m', 'oracle' ]);
$node->start;

my $ora_port = $node->safe_psql('postgres', 'SHOW ivorysql.port');
my $ora_connstr = $node->connstr('postgres') . " port=$ora_port";
my $h = $node->interactive_psql('postgres',
	extra_params => [ '--dbname', $ora_connstr ]);
$h->set_query_timer_restart();
$h->query_safe('SET ivorysql.compatible_mode = oracle;');
$h->query_safe('SET client_min_messages = notice;');

my $block = <<'SQL';
DECLARE
    i INTEGER := 10;
BEGIN
    RAISE NOTICE '%', i;
END;
/
SQL

# Sending normal newlines without terminal paste markers exercises the
# traditional line-at-a-time interactive input path.
$h->query($block, verbose => 0);
like(
	$h->{stderr},
	qr/NOTICE:  10/,
	'line-at-a-time interactive input still executes the block');
unlike($h->{stderr}, qr/(?:ERROR|FATAL):/,
	'line-at-a-time input does not send the slash to the server');
$h->{stderr} = '';

# The terminal paste markers make Readline return the embedded newlines in a
# single call.  The newline after the end marker accepts that input buffer.
sub paste
{
	my ($sql) = @_;
	$h->{stderr} = '';
	return $h->query("\e[200~$sql\e[201~\n", verbose => 0);
}

sub check_paste
{
	my ($sql, $expected, $description, $count) = @_;
	$count = 1 unless defined $count;
	local $Test::Builder::Level = $Test::Builder::Level + 1;

	paste($sql);
	like($h->{stderr} . "\n", $expected, $description);
	my @notices = ($h->{stderr} =~ /NOTICE:/g);
	is(scalar @notices, $count, 'each block executes exactly once');
	unlike($h->{stderr}, qr/(?:ERROR|FATAL):/,
		'the paste does not send a terminator as SQL');
	$h->{stderr} = '';
	$h->query_safe("\\r");
}

subtest 'Readline multiline paste' => sub {
	# interactive_psql ignores the user's inputrc.  Explicitly enable paste
	# handling, including on terminals for which Readline disables it by default.
	my $inputrc = $node->basedir . '/inputrc';
	append_to_file($inputrc, "set enable-bracketed-paste on\n");
	$h->query_safe("\\setenv INPUTRC '$inputrc'");
	$h->query_until(qr/^readline_ready\r?$/m,
		"\030\022\\echo readline_ready\n");
	# libedit and older Readline versions may not implement bracketed paste.
	my $probe = paste("SELECT 12345;\n");
	my $supported = $h->{stderr} eq '' && $probe =~ /^12345\r?$/m;
	$h->{stderr} = '';
	$h->query_safe("\\r");
	plan skip_all => 'the readline library does not support bracketed paste'
	  unless $supported;

	check_paste(
		$block,
		qr/NOTICE:  10\r?\n/,
		'a pasted anonymous block executes without another slash');

	check_paste(
		"BEGIN\n RAISE NOTICE 'begin paste';\nEND;\n \t/ \t\n",
		qr/NOTICE:  begin paste\r?\n/,
		'a BEGIN block accepts whitespace around its slash');

	check_paste(
		<<'SQL', qr/NOTICE:  nested 20\r?\n/, 'a labeled nested block executes');
<<outer_block>>
DECLARE
    i INTEGER := 20;
BEGIN
    BEGIN
        RAISE NOTICE 'nested %', i;
    END;
END;
/
SQL

	check_paste(
		<<'SQL', qr/NOTICE:  first\r?\n.*NOTICE:  second\r?\n/s, 'two blocks in one paste execute in order', 2);
BEGIN
    RAISE NOTICE 'first';
END;
/
BEGIN
    RAISE NOTICE 'second';
END;
/
SQL

	check_paste(
		<<'SQL', qr/NOTICE:  divided 5\r?\n/, 'division and comment slashes remain SQL');
DECLARE
    i INTEGER;
BEGIN
    /* A comment containing a line with just a slash:
    /
    */
    -- Another / in a comment
    i := 20
    / 4;
    RAISE NOTICE 'divided %', i;
END;
/
SQL

	check_paste(
		<<'SQL', qr/NOTICE:  text first\r?\n\/\r?\nlast\r?\n/, 'a slash on a line inside a string does not submit the block');
DECLARE
    s TEXT := 'first
/
last';
BEGIN
    RAISE NOTICE 'text %', s;
END;
/
SQL

	check_paste(
		<<'SQL', qr/NOTICE:  quoted first\r?\n\/\r?\nlast 3\r?\n/, 'Oracle quoted strings and quoted identifiers retain their slashes');
DECLARE
    s TEXT := q'[first
/
last]';
    "a/b" INTEGER := 3;
BEGIN
    RAISE NOTICE 'quoted % %', s, "a/b";
END;
/
SQL

	my $crlf = $block;
	$crlf =~ s/\n/\r\n/g;
	check_paste(
		$crlf,
		qr/NOTICE:  10\r?\n/,
		'a paste with CRLF line endings executes');

	# A new input buffer can begin inside a quote, then close it before the
	# terminating slash.  Use the lexer's current state, not its initial state.
	$h->query_safe("\\set PROMPT2 'CONT> '");
	$h->query_until(qr/CONT> /, "\e[200~DECLARE\n s TEXT := 'first\e[201~\n");
	check_paste(
		"last';\nBEGIN\n RAISE NOTICE 'continued %', s;\nEND;\n/\n",
		qr/NOTICE:  continued first\r?\nlast\r?\n/,
		'a pasted tail closes a string and submits the block');

	$h->query_safe("\\set expression '                    20 / 4'");
	my $expanded = paste("SELECT :expression AS result;\n");
	like($expanded, qr/^5\r?$/m,
		'a slash from variable expansion remains a division operator');
	is($h->{stderr}, '', 'a substituted slash emits no error');

	$h->query_safe("SET ivorysql.compatible_mode = pg;");
	my $out = paste("SELECT 20 / 4 AS result;\n");
	like($out, qr/^5\r?$/m, 'PostgreSQL mode still handles multiline input');
	is($h->{stderr}, '', 'PostgreSQL division emits no error');
	done_testing();
};

$h->{stderr} = '';
ok($h->quit, 'interactive psql exits successfully');

# The same anonymous block must continue to work with noninteractive input,
# where psql reads separate lines instead of one Readline buffer.
my ($stdout, $stderr);
is( $node->psql(
		'postgres', "SET ivorysql.compatible_mode = oracle;\n$block",
		stdout => \$stdout,
		stderr => \$stderr,
		extra_params => [ '--dbname', $ora_connstr ]),
	0,
	'noninteractive anonymous block executes');
like(
	$stderr,
	qr/NOTICE:  10(?:\n|$)/,
	'noninteractive input emits its notice');

$node->stop;
done_testing();
