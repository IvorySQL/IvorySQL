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

use strict;
use warnings FATAL => 'all';

use File::Spec;
use PostgreSQL::Test::Cluster;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('utl_file_fcopy');
$node->init;
$node->start;

my $dir = File::Spec->catdir($node->data_dir, 'fcopy_files');
mkdir $dir or die "could not create $dir: $!";

my $source = File::Spec->catfile($dir, 'source.txt');
open my $source_file, '>', $source or die "could not open $source: $!";
print {$source_file} "abc\n";
close $source_file or die "could not close $source: $!";

(my $sql_dir = $dir) =~ s/'/''/g;
$node->safe_psql('ivorysql',
	"INSERT INTO sys.utl_file_directory(dirname, dir) VALUES ('fcopy_tap', '$sql_dir')");

$node->safe_psql('ivorysql',
	"CALL utl_file.fcopy('fcopy_tap', 'source.txt', 'fcopy_tap', 'normal.txt')",
	connect_to_oraport => 1);
my $normal = File::Spec->catfile($dir, 'normal.txt');
open my $normal_file, '<', $normal or die "could not open $normal: $!";
my $content = do { local $/; <$normal_file> };
close $normal_file or die "could not close $normal: $!";
is($content, "abc\n", 'FCOPY writes a normal destination');

SKIP:
{
	skip '/dev/full is unavailable', 2 unless $^O eq 'linux' && -w '/dev/full';
	my $full = File::Spec->catfile($dir, 'full');
	skip 'cannot create the /dev/full symlink', 2 unless symlink('/dev/full', $full);

	my ($stdout, $stderr);
	my $status = $node->psql('ivorysql',
		"CALL utl_file.fcopy('fcopy_tap', 'source.txt', 'fcopy_tap', 'full')",
		connect_to_oraport => 1,
		stdout => \$stdout,
		stderr => \$stderr);
	isnt($status, 0, 'FCOPY reports a write error deferred until destination close');
	like($stderr, qr/INVALID_OPERATION/,
		'FCOPY reports the deferred I/O error, not a SQL or routing failure');
}

$node->stop;
done_testing();
