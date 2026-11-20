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
#
# Run with: prove src/tools/t/001_ivy_copyright.pl
# No configured build tree or database server is required.

use strict;
use warnings FATAL => 'all';

use Cwd qw(getcwd);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

my $script = File::Spec->catfile($FindBin::RealBin, '..', 'ivy_copyright.pl');
my $year = 1900 + (localtime)[5];
my $old_year = $year - 1;
my $first_year = $year - 3;
my $owner = 'IvorySQL Global Development Team';
my @cases;

for my $marker ('Copyright', 'Copyright (c)')
{
	for my $separator (' ', ', ')
	{
		push @cases,
		  [
			"$marker $old_year$separator$owner",
			"$marker $old_year-$year$separator$owner"
		  ],
		  [
			"Portions $marker $first_year-$old_year$separator$owner",
			"Portions $marker $first_year-$year$separator$owner"
		  ],
		  [ "$marker $year$separator$owner",
			"$marker $year$separator$owner" ],
		  [
			"$marker $first_year-$year$separator$owner",
			"$marker $first_year-$year$separator$owner"
		  ];
	}
}

push @cases,
  [
	"Copyright (c) $old_year, PostgreSQL Global Development Group",
	"Copyright (c) $old_year, PostgreSQL Global Development Group"
  ];

my $original_dir = getcwd;
my $test_dir = tempdir(CLEANUP => 1);
chdir $test_dir or die "chdir $test_dir: $!";

for my $i (0 .. $#cases)
{
	write_file("notice_$i.txt", "$cases[$i][0]\n");
}
mkdir '.git' or die "mkdir .git: $!";
my $excluded_notice = "Copyright $old_year $owner\n";
write_file('.git/index', $excluded_notice);
write_file('excluded.key', $excluded_notice);

for my $run (1 .. 2)
{
	my $stderr = gensym;
	my $pid = open3(undef, my $stdout, $stderr, $^X, $script);
	my $output = do { local $/; <$stdout> };
	my $errors = do { local $/; <$stderr> };
	waitpid($pid, 0);
	is($?, 0, "copyright updater succeeds on run $run") or diag($output);
	is($errors, '', "copyright updater has no errors on run $run");
	for my $i (0 .. $#cases)
	{
		is(read_file("notice_$i.txt"),
			"$cases[$i][1]\n", "run $run: $cases[$i][0]");
	}
	is(read_file('.git/index'), $excluded_notice, "run $run: skip .git");
	is(read_file('excluded.key'),
		$excluded_notice, "run $run: skip key files");
}

chdir $original_dir or die "chdir $original_dir: $!";
done_testing();

sub write_file
{
	my ($path, $contents) = @_;
	open(my $fh, '>', $path) or die "open $path: $!";
	print $fh $contents;
	close $fh or die "close $path: $!";
}

sub read_file
{
	my ($path) = @_;
	open(my $fh, '<', $path) or die "open $path: $!";
	local $/;
	return <$fh>;
}
