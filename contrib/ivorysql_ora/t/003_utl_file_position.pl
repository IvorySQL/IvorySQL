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
# Check FGETPOS at the int32 boundary without allocating a large disk file.

use strict;
use warnings FATAL => 'all';
use Config;
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# ftell() itself cannot represent the overflowing offsets with a 32-bit long.
plan skip_all => 'requires a 64-bit long for large file positions'
  if $Config{longsize} < 8;

my $node = PostgreSQL::Test::Cluster->new('file_position');
$node->init;
my $file = $node->basedir . '/offset.dat';
open(my $fh, '>', $file) or die "could not open $file: $!";

# Check sparse-file support with a small probe before creating the large hole.
truncate($fh, 1048576) or die "could not truncate $file: $!";
my @stat = stat($fh);
if (!defined($stat[12]) || $stat[12] * 512 > 8192)
{
	close($fh) or die "could not close $file: $!";
	unlink($file) or die "could not remove $file: $!";
	plan skip_all => 'requires sparse-file support';
}
truncate($fh, 2147483649) or die "could not extend sparse file $file: $!";
close($fh) or die "could not close $file: $!";
$node->start;

my $directory = $node->basedir;
$directory =~ s/'/''/g;
$node->safe_psql('postgres',
	"INSERT INTO sys.utl_file_directory(dirname, dir) VALUES ('position_fixture', '$directory')");
$node->safe_psql('postgres', q{
CREATE FUNCTION tap_file_position(abs_pos integer, rel_pos integer)
RETURN integer AS
  f UTL_FILE.FILE_TYPE;
  result integer;
BEGIN
  f := utl_file.fopen('position_fixture', 'offset.dat', 'r');
  utl_file.fseek(f, abs_pos, NULL);
  utl_file.fseek(f, NULL, rel_pos);
  result := utl_file.fgetpos(f);
  utl_file.fclose(f);
  RETURN result;
EXCEPTION
  WHEN OTHERS THEN
    utl_file.fclose_all();
    RAISE;
END;
/}, connect_to_oraport => 1);

foreach my $offset (0, 1, 2147483646, 2147483647)
{
	is($node->safe_psql('postgres',
		"SELECT tap_file_position($offset, 0) FROM dual",
		connect_to_oraport => 1),
		$offset, "FGETPOS preserves valid offset $offset");
}
foreach my $relative (1, 2)
{
	my ($stdout, $stderr);
	my $ret = $node->psql('postgres',
		"SELECT tap_file_position(2147483647, $relative) FROM dual",
		connect_to_oraport => 1, stdout => \$stdout, stderr => \$stderr,
		extra_params => ['--set=VERBOSITY=verbose']);
	isnt($ret, 0, "FGETPOS rejects INT_MAX + $relative");
	like($stderr, qr/22003: file position out of range/,
		'out-of-range file position reports numeric overflow');
	is($stdout, '', 'no wrapped negative offset is returned');
}
is($node->safe_psql('postgres', 'SELECT tap_file_position(0, 0) FROM dual',
	connect_to_oraport => 1), 0, 'file operations still work after overflow');

$node->stop;
unlink($file) or die "could not remove $file: $!";
done_testing();
