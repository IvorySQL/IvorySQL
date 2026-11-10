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
# Test the finite range and infinity sentinels of Oracle datetime binary input.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('datetime_binary');
$node->init;
$node->append_conf('postgresql.conf', "timezone = 'UTC'\n");
$node->start;

# Timestamp wire values are signed, big-endian microseconds since 2000-01-01.
# Hex avoids relying on Perl's native integer width.  Bounds are defined in
# datatype/timestamp.h; the two int64 extrema are the infinity sentinels.
my @cases = (
	['epoch', '0000000000000000', 1],
	['before epoch', 'fffffffffff0bdc0', 1],
	['minimum finite', 'fd0f7cc1411fa000', 1],
	['last whole second', '7fffff5bb3a35dc0', 1],
	['last microsecond', '7fffff5bb3b29fff', 1],
	['negative infinity', '8000000000000000', 1],
	['positive infinity', '7fffffffffffffff', 1],
	['below minimum', 'fd0f7cc1411f9fff', 0],
	['exclusive upper bound', '7fffff5bb3b2a000', 0],
	['above upper bound', '7fffff5bb3b2a001', 0],
	['largest finite int64', '7ffffffffffffffe', 0],
);

foreach my $type (qw(oradate oratimestamp oratimestamptz oratimestampltz))
{
	$node->safe_psql('postgres', "CREATE TABLE binary_input (v sys.$type)");
	foreach my $case (@cases)
	{
		my ($name, $hex, $valid) = @$case;
		# DATE has whole-second precision; exercise the exact microsecond
		# upper boundary only for the three TIMESTAMP types.
		next if $type eq 'oradate' && $name eq 'last microsecond';
		my $file = $node->basedir . '/datetime.bin';
		open(my $fh, '>:raw', $file) or die "could not open $file: $!";
		print $fh "PGCOPY\n\377\r\n\0", pack('NN', 0, 0),
		  pack('nN', 1, 8), pack('H*', $hex), pack('n', 0xffff);
		close($fh) or die "could not close $file: $!";

		my ($stdout, $stderr);
		my $ret = $node->psql('postgres',
			"\\copy binary_input FROM '$file' (FORMAT binary)",
			stdout => \$stdout, stderr => \$stderr);
		if ($valid)
		{
			is($ret, 0, "$type accepts $name") or diag($stderr);
			is($node->safe_psql('postgres',
				"SELECT encode(sys.${type}_send(v), 'hex') FROM binary_input"),
				$hex, "$type preserves $name");
		}
		else
		{
			isnt($ret, 0, "$type rejects $name");
			like($stderr, qr/(?:date|timestamp) out of range/,
				"$type reports range error for $name");
			is($node->safe_psql('postgres', 'SELECT count(*) FROM binary_input'),
				0, "$type stores no row for $name");
		}
		$node->safe_psql('postgres', 'TRUNCATE binary_input');
	}
	$node->safe_psql('postgres', 'DROP TABLE binary_input');
}

$node->stop;
done_testing();
