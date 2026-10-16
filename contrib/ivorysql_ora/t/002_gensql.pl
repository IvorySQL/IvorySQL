# Copyright 2026 IvorySQL Global Development Team
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# SQL generation must find its inputs in the source tree, independently of
# the build directory.  No running server or configured build is required.

use strict;
use warnings FATAL => 'all';

use Cwd        qw(getcwd);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Run qw(run);
use Test::More;

my $original_dir = getcwd();
my $tempdir = tempdir(CLEANUP => 1);
my $srcdir = File::Spec->catdir($tempdir, 'source with spaces');
my $builddir = File::Spec->catdir($tempdir, 'external build', 'nested');
make_path($srcdir, $builddir);

my $script = File::Spec->catfile($srcdir, 'gensql.pl');
copy(File::Spec->catfile($FindBin::RealBin, '..', 'gensql.pl'), $script)
  or die "could not copy gensql.pl: $!";

my %inputs = (
	'ivorysql_ora_merge_sqls' => "first\nsecond\n",
	'first--1.0.sql' => "SELECT 1;\n",
	'second--1.0.sql' => "SELECT 2;\n",
	'second--1.0--1.1.sql' => "SELECT 3;\n");
for my $name (keys %inputs)
{
	open(my $fh, '>', File::Spec->catfile($srcdir, $name)) or die $!;
	print {$fh} $inputs{$name};
	close($fh) or die $!;
}

my %expected = (
	'1.0' =>
	  qq{\\echo Use "CREATE EXTENSION ivorysql_ora" to load this file. \\quit\n\nSELECT 1;\n\nSELECT 2;\n},
	'1.0--1.1' =>
	  qq{\\echo Use "ALTER EXTENSION ivorysql_ora UPDATE TO '1.1'" to load this file. \\quit\n\nSELECT 3;\n}
);

for my $dir ($srcdir, $builddir)
{
	chdir($dir) or die "could not change directory to $dir: $!";
	for my $version ('1.0', '1.0--1.1')
	{
		my ($sql, $stderr);
		ok( run([ $^X, $script, 'meson', $version ],
				'>', \$sql, '2>', \$stderr),
			"Meson generation succeeds in $dir ($version)") or diag($stderr);
		is($sql, $expected{$version}, 'Meson emits the complete SQL');
	}

	is(system($^X, $script, 'gcc_build', '1.0', '1.0--1.1'),
		0, "Make generation succeeds in $dir");
	for my $version ('1.0', '1.0--1.1')
	{
		my $output = "ivorysql_ora--$version.sql";
		ok(-f $output, "Make writes $output in the build directory");
		my $sql;
		if (open(my $fh, '<', $output))
		{
			$sql = do { local $/; <$fh> };
			close($fh) or die $!;
		}
		is($sql, $expected{$version}, 'Make emits the same complete SQL');
	}
}

chdir($original_dir) or die $!;
done_testing();
