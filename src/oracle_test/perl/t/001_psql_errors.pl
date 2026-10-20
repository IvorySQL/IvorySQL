# Copyright (c) 2026, IvorySQL Global Development Team

use strict;
use warnings FATAL => 'all';
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# Exercise the real psql wrapper and IPC::Run without starting a server.
# Perl stands in for psql so exit status and timeout behavior are deterministic.
{
	package PsqlErrorTestNode;
	our @ISA = ('PostgreSQL::Test::Cluster');
	sub installed_command { return $^X; }
	sub connstr { return ''; }
}

# Replace only the psql argv with a controlled Perl child; keep the real
# IPC::Run implementation, including process exit and timeout handling.
{
	no warnings 'redefine';
	my $run = \&IPC::Run::run;
	*IPC::Run::run = sub {
		my @args = @_;
		my $argv = $args[0];
		my $program = pop @$argv;
		$args[0] = [$^X, '-e', $program];
		return $run->(@args);
	};
}

my $node = bless {_host => 'localhost', _port => 1, _oraport => 2},
  'PsqlErrorTestNode';

my %diagnostics = (
	1 => 'psql error',
	2 => 'connection error',
	3 => 'error running SQL',
	4 => 'psql returns 4');
for my $exit (1, 2, 3, 4)
{
	my $error = '';
	eval {
		$node->psql('postgres', '', on_error_die => 1,
			extra_params => ["exit $exit"]);
	};
	$error = $@;
	like($error, qr/\Q$diagnostics{$exit}\E/,
		"exit $exit retains its psql diagnostic without stderr capture");
	like($error, qr/<not collected>/, "exit $exit explains uncaptured stderr");
}

my $error = '';
eval {
	$node->psql('postgres', '', timeout => 0.1,
		extra_params => ['sleep 10']);
};
$error = $@;
like($error, qr/psql timed out: stderr: '<not collected>'/,
	'timeout retains its diagnostic without stderr capture');

my $stderr;
eval {
	$node->psql('postgres', '', on_error_die => 1, stderr => \$stderr,
		extra_params => ['print STDERR "detail"; exit 3']);
};
like($@, qr/error running SQL: 'detail'/, 'captured stderr is preserved');
is($stderr, 'detail', 'caller receives captured stderr');

my ($ret, $out, $err) = $node->psql('postgres', '',
	extra_params => ['print "result"; print STDERR "warning"; exit 0']);
is($ret, 0, 'list context success status');
is($out, 'result', 'list context stdout');
is($err, 'warning', 'list context stderr');

done_testing();
