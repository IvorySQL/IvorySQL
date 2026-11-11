# Copyright (c) 2026, IvorySQL Global Development Team
#
# Oracle-compatible mode creates the "uuid-ossp" extension while it builds
# template1.  An installation without contrib/uuid-ossp used to fail only
# after the data directory had been created, and the error did not say what
# was missing; initdb now checks for the extension up front (see
# check_oracle_extensions() in initdb.c).  This test pins that behaviour down:
#
#   1. Oracle mode with uuid-ossp missing fails with the new message and exit
#      code 1, and leaves no data directory behind;
#   2. plain PostgreSQL mode still works in the very same installation;
#   3. a complete installation does not report the extension as missing.
#
# initdb resolves the installation through the running binary, so cases 1 and
# 2 run against a copy of the installation tree that has the uuid-ossp files
# filtered out.  The installation under test is never modified.

use strict;
use warnings FATAL => 'all';

use File::Basename qw(basename dirname);
use PostgreSQL::Test::RecursiveCopy;
use PostgreSQL::Test::Utils;
use Test::More;

my ($bindir) = run_command([ 'pg_config', '--bindir' ]);
my ($sharedir) = run_command([ 'pg_config', '--sharedir' ]);
my ($pkglibdir) = run_command([ 'pg_config', '--pkglibdir' ]);

# Without uuid support there is no uuid-ossp to be missing: Oracle-compatible
# mode cannot work in such a build at all, so there is no behaviour here that
# this test could distinguish.
plan skip_all =>
  "uuid-ossp is not installed (was this build configured with --with-uuid=no?)"
  unless -f "$sharedir/extension/uuid-ossp.control";

# initdb reads preload_ora_misc.sql before it reaches the check under test, and
# contrib/ivorysql_ora provides that file.  A bare "make check" installs no
# contrib module, hence the hint in the skip message.
plan skip_all =>
  "preload_ora_misc.sql is not installed (contrib/ivorysql_ora is missing); run with EXTRA_INSTALL='contrib/uuid-ossp contrib/ivorysql_ora'"
  unless -f "$sharedir/preload_ora_misc.sql";

# The copy must keep the layout of the installation prefix, so that the copied
# binaries resolve their share and pkglib directories inside the copy.
my $prefix = dirname($bindir);

plan skip_all =>
  "installation is not relocatable: bindir is $bindir but sharedir is $sharedir and pkglibdir is $pkglibdir"
  unless index($sharedir, "$prefix/") == 0
  and index($pkglibdir, "$prefix/") == 0;

sub make_parent_directories
{
	my ($path) = @_;
	my @parts = split(m{/}, $path);

	pop @parts;					# the last component is created by copypath()
	my $dir = shift @parts;		# empty for an absolute path

	foreach my $part (@parts)
	{
		$dir .= "/$part";
		next if -d $dir;
		mkdir $dir or die "could not create $dir: $!";
	}
	return;
}

my $tempdir = PostgreSQL::Test::Utils::tempdir();
my $copy = "$tempdir/inst";
my $copy_bindir = $copy . substr($bindir, length($prefix));
my $copy_sharedir = $copy . substr($sharedir, length($prefix));
my $copy_pkglibdir = $copy . substr($pkglibdir, length($prefix));

mkdir $copy or die "could not create $copy: $!";

# copypath() creates the target directory itself but not its parents, and the
# copy has to reproduce the directory layout of the installation.
make_parent_directories($copy_bindir);
make_parent_directories($copy_sharedir);
make_parent_directories($copy_pkglibdir);

# Filter out what an incomplete installation would be missing.  The control
# file, the install scripts and the shared library all match one pattern.
my $skip_uuid_ossp = sub
{
	my $entry = shift;

	return 0 if basename($entry) =~ /^uuid-ossp/;
	return 1;
};

PostgreSQL::Test::RecursiveCopy::copypath($bindir, $copy_bindir);

# copypath() does not preserve file modes, and the copied programs have to stay
# executable.
chmod_recursive($copy_bindir, 0755, 0755);

PostgreSQL::Test::RecursiveCopy::copypath(
	$sharedir, $copy_sharedir, filterfn => $skip_uuid_ossp);

# The modules of the installation have to come along: a cluster that is created
# by the copied initdb preloads modules from the pkglib directory of its own
# installation (gb18030_2022 is one of them).
PostgreSQL::Test::RecursiveCopy::copypath(
	$pkglibdir, $copy_pkglibdir, filterfn => $skip_uuid_ossp);

my $copy_control = "$copy_sharedir/extension/uuid-ossp.control";

# Guard against accidentally testing the real installation instead of the
# copy: the copied pg_config reports the paths the copied initdb will use.
my ($copy_reported_sharedir) =
  run_command([ "$copy_bindir/pg_config", '--sharedir' ]);

plan skip_all =>
  "the copied installation reports its share directory as $copy_reported_sharedir instead of $copy_sharedir"
  unless $copy_reported_sharedir eq $copy_sharedir;

ok(!-e $copy_control, 'the copy of the installation has no uuid-ossp.control');

# 1. Oracle-compatible mode must fail before anything is written to disk.
my $oracle_datadir = "$tempdir/data_oracle";

command_checks_all(
	[ "$copy_bindir/initdb", '-D', $oracle_datadir, '-m', 'oracle', '-N' ],
	1,
	[],
	[
		qr/Oracle-compatible mode requires the "uuid-ossp" extension, but this installation is incomplete:/,
		qr/missing file ".*uuid-ossp\.control"/,
	],
	'initdb -m oracle with uuid-ossp missing');

ok(!-e $oracle_datadir, 'initdb -m oracle left no data directory behind');

# 2. The new check must not change what plain PostgreSQL mode does.
my $pg_datadir = "$tempdir/data_pg";

command_ok(
	[ "$copy_bindir/initdb", '-D', $pg_datadir, '-m', 'pg', '-N', '--no-locale' ],
	'initdb -m pg succeeds without uuid-ossp');

ok(-f "$pg_datadir/PG_VERSION", 'initdb -m pg created the cluster');

# 3. A complete installation must not report the extension as missing.
my $complete_datadir = "$tempdir/data_complete";

my ($stdout, $stderr) = run_command(
	[
		"$bindir/initdb", '-D', $complete_datadir, '-m', 'oracle', '-N',
		'--no-locale'
	]);

unlike($stderr, qr/requires the "uuid-ossp" extension/,
	'no uuid-ossp complaint when the extension is installed');

done_testing();
