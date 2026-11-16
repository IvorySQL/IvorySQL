# Copyright (c) 2026, IvorySQL Global Development Team

# Upgrade a cluster holding the Oracle-mode regression database, through the
# PostgreSQL port (--using-ora-pg) and through the Oracle port, and compare
# pg_dumpall output taken before and after.

use strict;
use warnings FATAL => 'all';

use Cwd qw(abs_path);
use File::Basename qw(dirname);

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $tempdir = PostgreSQL::Test::Utils::tempdir;
my $srcdir = abs_path('../../..');

my $old = PostgreSQL::Test::Cluster->new('old_regression');
$old->init;
$old->append_conf('postgresql.conf', 'log_statement = none');
$old->append_conf('postgresql.conf', 'max_prepared_transactions = 10');
$old->start;

command_ok(
	[
		$ENV{PG_REGRESS},
		"--dlpath=" . dirname($ENV{ORA_REGRESS_SHLIB}),
		'--bindir=',
		'--host=' . $old->host,
		'--port=' . $old->oraport,
		"--schedule=$srcdir/src/oracle_test/regress/parallel_schedule",
		'--max-concurrent-tests=20',
		"--inputdir=$srcdir/src/oracle_test/regress",
		"--outputdir=$PostgreSQL::Test::Utils::tmp_check"
	],
	'Oracle-mode regression tests in old instance');

# Dump every database, dropping the random \restrict keys.
sub dumpall
{
	my ($node, $port, $name) = @_;
	my $file = "$tempdir/$name.sql";

	command_ok(
		[
			'pg_dumpall', '--no-sync',
			'--host' => $node->host,
			'--port' => $port,
			'--file' => $file
		],
		"pg_dumpall $name");
	my $dump = slurp_file($file);
	$dump =~ s/^\\(?:un)?restrict .*$//mg;
	return $dump;
}

my $before_pg = dumpall($old, $old->port, 'before_pg_port');
my $before_ora = dumpall($old, $old->oraport, 'before_oracle_port');
$old->stop;

# pg_upgrade writes files into its working directory.
chdir ${PostgreSQL::Test::Utils::tmp_check};

for my $using_ora_pg (1, 0)
{
	my $label = $using_ora_pg ? 'through the PostgreSQL port'
	  : 'through the Oracle port';
	my $new = PostgreSQL::Test::Cluster->new(
		$using_ora_pg ? 'new_using_ora_pg' : 'new_default');
	$new->init;
	$new->append_conf('postgresql.conf', 'max_prepared_transactions = 10');

	command_ok(
		[
			'pg_upgrade', '--no-sync', '--copy',
			'--old-datadir' => $old->data_dir,
			'--new-datadir' => $new->data_dir,
			'--old-bindir' => $old->config_data('--bindir'),
			'--new-bindir' => $new->config_data('--bindir'),
			'--socketdir' => $new->host,
			'--old-port' => $old->port,
			'--new-port' => $new->port,
			'--old-oraport' => $old->oraport,
			'--new-oraport' => $new->oraport,
			$using_ora_pg ? ('--using-ora-pg') : ()
		],
		"pg_upgrade of the regression database $label");

	$new->start;
	if ($using_ora_pg)
	{
		is(dumpall($new, $new->port, 'after_pg_port'),
			$before_pg, "upgrade $label keeps every object unchanged");
	}
	else
	{
		my $after = dumpall($new, $new->oraport, 'after_oracle_port');

		# Issue #3269: a type without typmod that Oracle mode prints, such as
		# timestamptz or a varchar2 cast, reparses with a default typmod.
		# Print both forms alike, so that any other change still fails.
		my $default_typmod = sub {
			my ($dump) = @_;
			$dump =~ s/\btimestamp\(6\) with time zone\b/timestamp with time zone/g;
			$dump =~ s/::varchar2\(4000\)/::varchar2/g;
			return $dump;
		};
		is($default_typmod->($after), $default_typmod->($before_ora),
			"upgrade $label keeps every object unchanged, but for issue #3269");
		TODO:
		{
			local $TODO = 'types without typmod change their typmod (issue #3269)';
			is($after, $before_ora,
				"upgrade $label keeps every object unchanged");
		}
	}
	$new->stop;
}

done_testing();
