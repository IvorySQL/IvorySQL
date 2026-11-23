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
# Tests for the Oracle-compatible UTL_TCP package (plain outbound TCP).
#
# The cluster is initialized in Oracle mode so that the PL/iSQL package
# machinery and the ivorysql_ora extension are available; package calls
# are issued through the Oracle-mode listener (SHOW ivorysql.port).  A
# set of test-owned loopback servers (t/utl_tcp_server.pl) provides
# deterministic echo, fragment, hold, EOF, capture and close-after-prefix
# peers; nothing here touches the public network, and every wait is
# bounded by a transfer timeout, a poll deadline or the watchdog alarm.

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec;
use IO::Socket::INET;
use IPC::Run;
use Time::HiRes qw(time sleep);

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

# Watchdog: never let CI hang on a stuck socket wait.
$SIG{ALRM} = sub {
	BAIL_OUT("001_utl_tcp.pl watchdog: test ran longer than 600s");
};
alarm 600;

my $node = PostgreSQL::Test::Cluster->new('utl_tcp_test');

# Oracle mode is required for the PL/iSQL package; UTF8 for the multibyte
# conversion tests.  The later -m overrides the harness default.
$node->init(extra => [ '-m', 'oracle', '-E', 'UTF8', '--locale', 'C' ]);
$node->start;

my $tmpdir    = PostgreSQL::Test::Utils::tempdir();
my $server_pl = File::Spec->catfile(dirname(__FILE__), 'utl_tcp_server.pl');

# The PL/iSQL package calls must go through the Oracle-mode listener.
my $oraport = $node->safe_psql('postgres', 'SHOW ivorysql.port');
like($oraport, qr/^\d+$/, "Oracle-mode listener port is numeric ($oraport)");
my $ora_connstr = "host=127.0.0.1 port=$oraport dbname=postgres";

my (%SRV, %SRV_PORT);

# Start one utl_tcp_server.pl instance.  $key identifies the instance in
# %SRV / %SRV_PORT and names the info file; $mode is the server's mode
# argument.  They are separate because several instances can share one
# mode (the six push peers), while every instance must keep its own
# IPC::Run handle so that END can stop and reap all of them; overwriting
# a key would strand the earlier handle until the server's own watchdog
# fires, so fail loudly instead.
sub start_server
{
	my ($key, $mode, @args) = @_;
	die "start_server: instance '$key' already started" if $SRV{$key};
	my $info = File::Spec->catfile($tmpdir, "$key.info");
	unlink $info;
	$SRV{$key} = IPC::Run::start(
		[ $^X, $server_pl, $mode, @args, $info ],
		\my $in, \my $out, \my $err);
	PostgreSQL::Test::Utils::wait_for_file($info, qr/^\d+$/m);
	open my $fh, '<', $info or die "could not read $info: $!";
	$SRV_PORT{$key} = <$fh>;
	chomp $SRV_PORT{$key};
	close $fh;
	return $SRV_PORT{$key};
}

# Stop and reap every server this test started.  kill_kill sends TERM
# (KILL on Windows), escalates to KILL after its grace period and reaps
# the child, croaking if it cannot, so a surviving server is an error
# reported here rather than something left to the server's watchdog.
END
{
	my @cleanup_failures;
	foreach my $key (sort keys %SRV)
	{
		my $h = $SRV{$key} or next;
		eval { $h->kill_kill; 1 }
			or push @cleanup_failures, "$key: $@";
	}
	die "END failed to stop and reap test servers:\n  ",
		join("\n  ", @cleanup_failures), "\n"
		if @cleanup_failures;
}

my $echo_port    = start_server('echo', 'echo');
my $bin_port     = start_server('bin', 'bin');
my $hold_port    = start_server('hold', 'hold');
my $eof_port     = start_server('eof', 'eof');
my $capture_port = start_server('capture', 'capture',
	File::Spec->catfile($tmpdir, 'capture.bin'),
	File::Spec->catfile($tmpdir, 'capture.log'));
my $frag_port    = start_server('frag', 'frag', 0.3);

# A port that refuses connections immediately: bind and close a listener.
my $refused_sock = IO::Socket::INET->new(
	LocalAddr => '127.0.0.1', LocalPort => 0, Listen => 1, Proto => 'tcp')
  or die "could not bind refused-port listener: $!";
my $refused_port = $refused_sock->sockport;
close $refused_sock;

my $prefix_reply = File::Spec->catfile($tmpdir, 'prefix.reply');
PostgreSQL::Test::Utils::append_to_file($prefix_reply, "done\n");
my $prefix_port = start_server('prefix', 'prefix', 8, $prefix_reply,
	File::Spec->catfile($tmpdir, 'prefix.info'));

# Push peers: every connection receives the file's bytes immediately on
# accept; afterwards the peer echoes everything received, except for the
# pushclose variant, which closes right after the push (clean EOF).
my $push_abclf_file = File::Spec->catfile($tmpdir, 'push_abclf.bin');
my $push_cr_file    = File::Spec->catfile($tmpdir, 'push_cr.bin');
my $push_abc_file   = File::Spec->catfile($tmpdir, 'push_abc.bin');
my $push_mb_file    = File::Spec->catfile($tmpdir, 'push_mb.bin');
my $push_mb2_file   = File::Spec->catfile($tmpdir, 'push_mb2.bin');
my $push_amb_file   = File::Spec->catfile($tmpdir, 'push_amb.bin');
PostgreSQL::Test::Utils::append_to_file($push_abclf_file, "ABC\r\n");
PostgreSQL::Test::Utils::append_to_file($push_cr_file,    "abc\r");
PostgreSQL::Test::Utils::append_to_file($push_abc_file,   "abc");
PostgreSQL::Test::Utils::append_to_file($push_mb_file,    "\xe4");
PostgreSQL::Test::Utils::append_to_file($push_mb2_file,   "\xe4\xbd\xa0\xe5");
PostgreSQL::Test::Utils::append_to_file($push_amb_file,   "A\xe4");
my $push_abclf_port    = start_server('push_abclf', 'push', $push_abclf_file);
my $push_cr_port       = start_server('push_cr', 'push', $push_cr_file);
my $push_abc_port      = start_server('push_abc', 'push', $push_abc_file);
my $push_mb_port       = start_server('push_mb', 'push', $push_mb_file);
my $push_mb2_port      = start_server('push_mb2', 'push', $push_mb2_file);
my $pushclose_amb_port = start_server('pushclose_amb', 'push', $push_amb_file,
	'close');

my $capture_bin = File::Spec->catfile($tmpdir, 'capture.bin');
my $capture_log = File::Spec->catfile($tmpdir, 'capture.log');

sub read_bytes
{
	my ($file) = @_;
	open my $fh, '<', $file or return undef;
	binmode $fh;
	local $/;
	my $data = <$fh>;
	close $fh;
	return $data;
}

# Wait (bounded) until the capture peer's file holds at least $len bytes
# and return the contents.  The capture server writes asynchronously from
# its select loop, so the TAP side must poll instead of reading right
# after the SQL statement returns.  On timeout this dies with the bytes
# seen so far and the capture log, which makes the harness failure a
# visible TAP failure instead of a flaky byte comparison.
sub wait_capture_bytes
{
	my ($file, $len, $label) = @_;
	my $deadline = time() + 10;
	my $data;

	while (1)
	{
		$data = read_bytes($file);
		last if defined $data && length($data) >= $len;

		if (time() >= $deadline)
		{
			die "$label: capture file never reached $len bytes within 10s\n"
			  . 'bytes now: ' . unpack('H*', $data // '') . "\n"
			  . 'capture log: ' . (read_bytes($capture_log) // '<missing>')
			  . "\n";
		}

		sleep 0.05;
	}

	return $data;
}

# Run SQL through the Oracle-mode listener; returns (exit, stdout, stderr).
sub ora_sql
{
	my ($sql) = @_;
	my ($out, $err) = ('', '');
	my $ret = $node->psql('postgres', $sql,
		connstr       => $ora_connstr,
		stdout        => \$out,
		stderr        => \$err,
		on_error_stop => 0,
		timeout       => 90);
	return ($ret, $out, $err);
}

# Byte constants for the multibyte tests (raw bytes, never perl-unicode).
my $nihao     = "\xe4\xbd\xa0\xe5\xa5\xbd";    # U+4F60 U+595D in UTF8
my $nihao_1ch = "\xe4\xbd\xa0";                # first character in UTF8
my $e_utf8    = "\xc3\xa9";                    # U+00E9 in UTF8

# ---------------------------------------------------------------------
# Installation and privilege model
# ---------------------------------------------------------------------

my ($ret, $out, $err);

(undef, $out) = ora_sql(
	"SELECT count(*) FROM pg_extension WHERE extname = 'ivorysql_ora'");
is($out, '1', 'ivorysql_ora extension is installed');

(undef, $out) = ora_sql(
	"SELECT count(*) FROM pg_package WHERE pkgname = 'utl_tcp'");
is($out, '1', 'UTL_TCP package is installed');

(undef, $out) = ora_sql(
	"SELECT define_invok FROM pg_package WHERE pkgname = 'utl_tcp'");
is($out, 'f', 'UTL_TCP is AUTHID CURRENT_USER');

(undef, $out) = ora_sql(
	"SELECT has_function_privilege('public'," .
	" 'sys.ora_utl_tcp_open_connection(text,integer,text,integer,integer," .
	"integer,text,text,integer,text,text)', 'EXECUTE')");
is($out, 'f', 'PUBLIC has no EXECUTE on the open C function');

(undef, $out) = ora_sql(
	"SELECT has_function_privilege('public'," .
	" 'sys.ora_utl_tcp_close_connection(integer)', 'EXECUTE')");
is($out, 'f', 'PUBLIC has no EXECUTE on the close C function');

# ---------------------------------------------------------------------
# CONNECTION record, defaults, CRLF, close semantics
# ---------------------------------------------------------------------

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port);
  RAISE NOTICE 'DEF host=% port=% lh=% lp=% cs=% nl=%,% to=% sd_ok=%',
    c.remote_host, c.remote_port, c.local_host, c.local_port,
    c.charset, ascii(substr(c.newline, 1, 1)),
    ascii(substr(c.newline, 2, 1)), c.tx_timeout, c.private_sd > 0;
  utl_tcp.close_connection(c);
END;
});
like($err,
	qr/DEF host=127\.0\.0\.1 port=$echo_port lh=<NULL> lp=<NULL> cs=<NULL> nl=13,10 to=<NULL> sd_ok=t\b/,
	'open_connection defaults: CRLF newline, NULL charset/timeout/local, private_sd set')
  or diag($err);

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
BEGIN
  c := utl_tcp.open_connection(remote_host => '127.0.0.1',
                               remote_port => $echo_port,
                               charset => 'UTF8',
                               newline => CHR(10),
                               tx_timeout => 3);
  RAISE NOTICE 'NAMED cs=% nl=% to=%',
    c.charset, ascii(c.newline), c.tx_timeout;
  utl_tcp.close_connection(c);
  RAISE NOTICE 'CLOSED sd=% host=%', c.private_sd, c.remote_host;
END;
});
like($err, qr/NAMED cs=UTF8 nl=10 to=3/,
	'named notation overrides: charset, LF newline, timeout')
  or diag($err);
like($err, qr/CLOSED sd=<NULL> host=<NULL>/,
	'close_connection clears the record fields')
  or diag($err);

(undef, undef, $err) = ora_sql(qq{
BEGIN
  RAISE NOTICE 'CRLF len=% c1=% c2=%',
    length(utl_tcp.CRLF),
    ascii(substr(utl_tcp.CRLF, 1, 1)),
    ascii(substr(utl_tcp.CRLF, 2, 1));
END;
});
like($err, qr/CRLF len=2 c1=13 c2=10/,
	'UTL_TCP.CRLF is CHR(13) || CHR(10)')
  or diag($err);

# The record is descriptive only: editing c.newline must not change the
# newline WRITE_LINE actually sends (the registered LF, one character).
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $capture_port,
                               newline => CHR(10), tx_timeout => 5);
  c.newline := 'ZZ';
  n := utl_tcp.write_line(c, 'x');
  RAISE NOTICE 'RECLINE n=%', n;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/RECLINE n=2/,
	'WRITE_LINE uses the registered newline, not an edited record field')
  or diag($err);
is(wait_capture_bytes($capture_bin, 2, 'registered LF newline capture'),
	"x\n", 'capture shows data plus the registered LF newline');
unlink $capture_bin;

# ---------------------------------------------------------------------
# Text and line I/O over echo
# ---------------------------------------------------------------------

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port, tx_timeout => 5);
  n := utl_tcp.write_line(c, 'hello world');
  RAISE NOTICE 'WL n=%', n;
  s := utl_tcp.get_line(c);
  RAISE NOTICE 'GL len=% last2=%,%',
    length(s), ascii(substr(s, length(s) - 1, 1)),
    ascii(substr(s, length(s), 1));
  n := utl_tcp.write_line(c, 'second');
  s := utl_tcp.get_line(c, remove_crlf => TRUE);
  RAISE NOTICE 'GLSTRIP=%', s;
  n := utl_tcp.write_text(c, 'abcdefgh');
  RAISE NOTICE 'WT n=%', n;
  s := utl_tcp.get_text(c, 5);
  RAISE NOTICE 'GT=%', s;
  n := utl_tcp.write_text(c, NULL);
  RAISE NOTICE 'WTNULL n=%', n;
  s := utl_tcp.get_text(c);
  RAISE NOTICE 'GTDEF=%', s;
  n := utl_tcp.write_text(c, 'XYZ', 2);
  RAISE NOTICE 'WT2 n=%', n;
  s := utl_tcp.get_text(c, 2);
  RAISE NOTICE 'GT2=%', s;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/WL n=13/, 'WRITE_LINE returns characters including the newline')
  or diag($err);
like($err, qr/GL len=13 last2=13,10/,
	'GET_LINE preserves the CRLF terminator by default')
  or diag($err);
like($err, qr/GLSTRIP=second/, 'GET_LINE remove_crlf strips the terminator')
  or diag($err);
like($err, qr/WT n=8/, 'WRITE_TEXT without len sends all characters')
  or diag($err);
like($err, qr/GT=abcde/, 'GET_TEXT reads the requested characters')
  or diag($err);
like($err, qr/WTNULL n=0/, 'WRITE_TEXT with NULL data transmits nothing')
  or diag($err);
like($err, qr/GTDEF=f/, 'GET_TEXT default len is 1')
  or diag($err);
like($err, qr/WT2 n=2/, 'WRITE_TEXT honors the len parameter (characters)')
  or diag($err);
like($err, qr/GT2=gh/,
	'GET_TEXT drains buffered bytes before newly written data')
  or diag($err);

# CR alone terminates a line; CR followed by non-LF is a plain CR.
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port, tx_timeout => 5);
  n := utl_tcp.write_text(c, 'a' || CHR(13) || 'b' || CHR(10) || 'c');
  s := utl_tcp.get_line(c);
  RAISE NOTICE 'CR1 len=% last=%', length(s), ascii(substr(s, length(s), 1));
  s := utl_tcp.get_line(c);
  RAISE NOTICE 'CR2 len=% last=%', length(s), ascii(substr(s, length(s), 1));
  utl_tcp.close_connection(c);
END;
});
like($err, qr/CR1 len=2 last=13/, 'lone CR terminates a line and is kept')
  or diag($err);
like($err, qr/CR2 len=2 last=10/, 'LF terminates the next line')
  or diag($err);

# Two independent connections.
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c1 utl_tcp.connection;
  c2 utl_tcp.connection;
  s VARCHAR2(100);
  n INTEGER;
BEGIN
  c1 := utl_tcp.open_connection('127.0.0.1', $echo_port, tx_timeout => 5);
  c2 := utl_tcp.open_connection('127.0.0.1', $echo_port, tx_timeout => 5);
  n := utl_tcp.write_line(c1, 'one');
  n := utl_tcp.write_line(c2, 'two');
  s := utl_tcp.get_line(c2, TRUE);
  RAISE NOTICE 'TWO c2=%', s;
  s := utl_tcp.get_line(c1, TRUE);
  RAISE NOTICE 'TWO c1=%', s;
  utl_tcp.close_connection(c1);
  utl_tcp.close_connection(c2);
END;
});
like($err, qr/TWO c2=two/, 'two connections: second stream independent')
  or diag($err);
like($err, qr/TWO c1=one/, 'two connections: first stream independent')
  or diag($err);

# ---------------------------------------------------------------------
# Raw I/O: NUL and high bytes move unchanged
# ---------------------------------------------------------------------

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  r RAW(64);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port, tx_timeout => 5);
  n := utl_tcp.write_raw(c, HEXTORAW('00FF41FE'));
  RAISE NOTICE 'WR n=%', n;
  r := utl_tcp.get_raw(c, 4);
  RAISE NOTICE 'GR=%', r;
  n := utl_tcp.write_raw(c, HEXTORAW('DEADBEEF'), 2);
  RAISE NOTICE 'WR2 n=%', n;
  r := utl_tcp.get_raw(c, 2);
  RAISE NOTICE 'GR2=%', r;
  n := utl_tcp.write_raw(c, HEXTORAW('BEEF'));
  r := utl_tcp.get_raw(c);
  RAISE NOTICE 'GRDEF=%', r;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/WR n=4/, 'WRITE_RAW returns the byte count')
  or diag($err);
like($err, qr/GR=\\x00ff41fe/i,
	'GET_RAW returns NUL and high bytes unchanged')
  or diag($err);
like($err, qr/WR2 n=2/, 'WRITE_RAW honors the len parameter (bytes)')
  or diag($err);
like($err, qr/GR2=\\xdead/i, 'GET_RAW reads the requested bytes')
  or diag($err);
like($err, qr/GRDEF=\\xbe/i, 'GET_RAW default len is 1')
  or diag($err);

# binary echo with a prefix proves exact framing over raw bytes
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  r RAW(64);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $bin_port, tx_timeout => 5);
  n := utl_tcp.write_raw(c, HEXTORAW('00FF'));
  r := utl_tcp.get_raw(c, 4);
  RAISE NOTICE 'BIN r=%', r;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/BIN r=\\x525800ff/i,
	'binary echo: RX prefix plus raw bytes come back exactly')
  or diag($err);

# ---------------------------------------------------------------------
# Multibyte conversion and charsets
# ---------------------------------------------------------------------

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port,
                               charset => 'UTF8', tx_timeout => 5);
  n := utl_tcp.write_text(c, '$nihao');
  RAISE NOTICE 'MB n=%', n;
  s := utl_tcp.get_text(c, 2);
  IF s = '$nihao' THEN
    RAISE NOTICE 'MBRT OK';
  ELSE
    RAISE NOTICE 'MBRT BAD %', s;
  END IF;
  n := utl_tcp.write_text(c, '$nihao', 1);
  RAISE NOTICE 'MB1 n=%', n;
  s := utl_tcp.get_text(c, 1);
  IF s = '$nihao_1ch' THEN
    RAISE NOTICE 'MB1CH OK';
  ELSE
    RAISE NOTICE 'MB1CH BAD %', s;
  END IF;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/MB n=2/, 'WRITE_TEXT counts characters, not bytes (2 CJK chars)')
  or diag($err);
like($err, qr/MBRT OK/, 'GET_TEXT round-trips multibyte text')
  or diag($err);
like($err, qr/MB1 n=1/, 'len never splits a multibyte character')
  or diag($err);
like($err, qr/MB1CH OK/, 'partial multibyte write round-trips as one character')
  or diag($err);

# LATIN1 on the wire: one UTF8 character converts to a single byte and
# back.  This exercises real conversion in both directions.
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port,
                               charset => 'LATIN1', tx_timeout => 5);
  n := utl_tcp.write_text(c, '$e_utf8');
  RAISE NOTICE 'LAT1 n=%', n;
  s := utl_tcp.get_text(c, 1);
  IF s = '$e_utf8' THEN
    RAISE NOTICE 'LAT1RT OK';
  ELSE
    RAISE NOTICE 'LAT1RT BAD %', s;
  END IF;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/LAT1 n=1/, 'WRITE_TEXT with LATIN1 charset returns char count')
  or diag($err);
like($err, qr/LAT1RT OK/,
	'GET_TEXT converts the LATIN1 wire byte back to UTF8')
  or diag($err);

# the capture peer shows the actual converted wire bytes
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $capture_port,
                               charset => 'LATIN1', tx_timeout => 5);
  n := utl_tcp.write_text(c, '$e_utf8');
  RAISE NOTICE 'CAP n=%', n;
  n := utl_tcp.write_text(c, 'AB', 1);
  RAISE NOTICE 'CAPPART n=%', n;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/CAP n=1/, 'capture write returns 1 character')
  or diag($err);
like($err, qr/CAPPART n=1/, 'partial capture write returns 1 character')
  or diag($err);
is(unpack('H*', wait_capture_bytes($capture_bin, 2, 'LATIN1 capture')),
	'e941', 'capture shows LATIN1-converted byte and the len-clipped text');
unlink $capture_bin;

# the newline is converted to the wire encoding at open time: CHR(233)
# in a UTF8 database must reach a LATIN1 connection as the single byte
# E9, not as the UTF8 bytes C3 A9
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $capture_port,
                               charset => 'LATIN1',
                               newline => CHR(233), tx_timeout => 5);
  n := utl_tcp.write_line(c, 'A');
  RAISE NOTICE 'NLWIRE n=%', n;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/NLWIRE n=2/,
	'WRITE_LINE counts the converted newline as one wire character')
  or diag($err);
is(unpack('H*', wait_capture_bytes($capture_bin, 2, 'LATIN1 newline capture')),
	'41e9', 'newline CHR(233) is sent as LATIN1 E9, not UTF8 C3 A9');
unlink $capture_bin;

# a newline character that does not exist in the wire encoding is
# rejected before the connection is opened, leaving no slot behind
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  ok INTEGER := 0;
BEGIN
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', $echo_port,
                                 charset => 'LATIN1',
                                 newline => CHR(338));
    RAISE NOTICE 'NLCONV GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'NLCONV % (%)', SQLERRM, SQLSTATE;
  END;
  FOR i IN 1 .. 50 LOOP
    c := utl_tcp.open_connection('127.0.0.1', $hold_port);
    ok := ok + 1;
  END LOOP;
  RAISE NOTICE 'NLSLOTS ok=%', ok;
  utl_tcp.close_all_connections();
END;
});
like($err, qr/NLCONV .*22P05/,
	'untranslatable newline character is rejected with 22P05')
  or diag($err);
like($err, qr/NLSLOTS ok=50/,
	'a rejected newline consumes no connection slots')
  or diag($err);

# called directly, a newline that is too long is rejected by the C
# function with 22023
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
BEGIN
  BEGIN
    c.private_sd := sys.ora_utl_tcp_open_connection('127.0.0.1',
      $echo_port, NULL, NULL, NULL, NULL, 'UTF8', 'abc', NULL, NULL, NULL);
    RAISE NOTICE 'NLLEN GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'NLLEN % (%)', SQLERRM, SQLSTATE;
  END;
END;
});
like($err, qr/NLLEN .*22023/, 'overlong newline is rejected with 22023')
  or diag($err);

# ---------------------------------------------------------------------
# GET_TEXT at the 32767-byte value limit must not lose buffered data
# ---------------------------------------------------------------------

# 8192 four-byte characters (32768 wire bytes): the first call returns
# the largest complete prefix, 8191 characters, and the second call
# returns the last character untouched
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  four VARCHAR2(4);
  s VARCHAR2(32767);
  expected VARCHAR2(32767);
  n INTEGER;
BEGIN
  four := convert_from(HEXTORAW('F0908D88'), 'UTF8');
  c := utl_tcp.open_connection('127.0.0.1', $echo_port, tx_timeout => 5);
  n := utl_tcp.write_text(c, repeat(four, 4096));
  n := utl_tcp.write_text(c, repeat(four, 4096));
  s := utl_tcp.get_text(c, 8192);
  expected := repeat(four, 8191);
  IF s = expected THEN
    RAISE NOTICE 'GT1 OK bytes=%', octet_length(s);
  ELSE
    RAISE NOTICE 'GT1 BAD bytes=% chars=%', octet_length(s), length(s);
  END IF;
  s := utl_tcp.get_text(c, 1);
  IF s = four THEN
    RAISE NOTICE 'GT2 OK';
  ELSE
    RAISE NOTICE 'GT2 BAD bytes=%', octet_length(s);
  END IF;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/GT1 OK bytes=32764/,
	'GET_TEXT(8192) returns 8191 four-byte characters at the limit')
  or diag($err);
like($err, qr/GT2 OK/, 'the 8192nd four-byte character is returned next')
  or diag($err);

# LATIN1 wire bytes expand when converted to UTF8: 20000 E9 bytes would
# become 40000 bytes, so the first read returns the 16383 characters
# that fit (32766 bytes) and the rest is returned by the next read
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(32767);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port,
                               charset => 'LATIN1', tx_timeout => 5);
  n := utl_tcp.write_text(c, repeat(CHR(233), 10000));
  n := utl_tcp.write_text(c, repeat(CHR(233), 10000));
  s := utl_tcp.get_text(c, 20000);
  IF s = repeat(CHR(233), 16383) THEN
    RAISE NOTICE 'EXP1 OK bytes=%', octet_length(s);
  ELSE
    RAISE NOTICE 'EXP1 BAD bytes=% chars=%', octet_length(s), length(s);
  END IF;
  s := utl_tcp.get_text(c, 3617);
  IF s = repeat(CHR(233), 3617) THEN
    RAISE NOTICE 'EXP2 OK bytes=%', octet_length(s);
  ELSE
    RAISE NOTICE 'EXP2 BAD bytes=% chars=%', octet_length(s), length(s);
  END IF;
  utl_tcp.close_connection(c);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'EXPERR % (%)', SQLERRM, SQLSTATE;
END;
});
like($err, qr/EXP1 OK bytes=32766/,
	'GET_TEXT returns the fitting prefix when conversion expands')
  or diag($err);
like($err, qr/EXP2 OK bytes=7234/,
	'the expansion remainder is returned by the next read')
  or diag($err);

# an invalid byte sequence raises without consuming, so the same bytes
# can be retrieved as RAW afterwards
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  r RAW(64);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port, tx_timeout => 5);
  n := utl_tcp.write_raw(c, HEXTORAW('41FF42'));
  s := utl_tcp.get_text(c, 1);
  RAISE NOTICE 'CVA s=%', s;
  BEGIN
    s := utl_tcp.get_text(c, 1);
    RAISE NOTICE 'CVBAD GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'CVERR % (%)', SQLERRM, SQLSTATE;
  END;
  r := utl_tcp.get_raw(c, 2);
  RAISE NOTICE 'CVRAW=%', r;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/CVA s=A/, 'GET_TEXT returns the valid character before the bad byte')
  or diag($err);
like($err, qr/CVERR .*22021/, 'GET_TEXT raises 22021 on an invalid byte sequence')
  or diag($err);
like($err, qr/CVRAW=\\xff42/i,
	'the bytes behind a conversion error are retrievable as RAW')
  or diag($err);

# unknown charset is rejected at open time
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port,
                               charset => 'NOT_A_CHARSET');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'BADCS % (%)', SQLERRM, SQLSTATE;
END;
});
like($err, qr/BADCS .*22023/, 'unknown charset is rejected with 22023')
  or diag($err);

# ---------------------------------------------------------------------
# Fragmented delivery (CRLF split across two writes)
# ---------------------------------------------------------------------

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $frag_port, tx_timeout => 5);
  s := utl_tcp.get_line(c, TRUE);
  RAISE NOTICE 'FRAG1=%', s;
  s := utl_tcp.get_line(c, TRUE);
  RAISE NOTICE 'FRAG2=%', s;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/FRAG1=abcd/,
	'GET_LINE assembles fragments and a CRLF split across writes')
  or diag($err);
like($err, qr/FRAG2=ef/, 'second line after the fragmented CRLF is intact')
  or diag($err);

# ---------------------------------------------------------------------
# Ready data at tx_timeout = 0 and line rules at timeouts
# ---------------------------------------------------------------------

# bytes that have already arrived are readable without waiting.  The
# push peer sends on accept, so give that write a moment to land in the
# kernel buffer before reading with tx_timeout => 0.
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  r RAW(64);
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $push_abclf_port,
                               tx_timeout => 0);
  PERFORM pg_sleep(0.2);
  s := utl_tcp.get_text(c, 1);
  RAISE NOTICE 'ZT_T s=%', s;
  s := utl_tcp.get_line(c);
  RAISE NOTICE 'ZT_L len=%', length(s);
  utl_tcp.close_connection(c);
  c := utl_tcp.open_connection('127.0.0.1', $push_abclf_port,
                               tx_timeout => 0);
  PERFORM pg_sleep(0.2);
  r := utl_tcp.get_raw(c, 1);
  RAISE NOTICE 'ZT_R r=%', r;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/ZT_T s=A/,
	'GET_TEXT reads pre-delivered data with tx_timeout 0')
  or diag($err);
like($err, qr/ZT_L len=4/,
	'GET_LINE reads a pre-delivered line with tx_timeout 0')
  or diag($err);
like($err, qr/ZT_R r=\\x41/i,
	'GET_RAW reads pre-delivered data with tx_timeout 0')
  or diag($err);

# with no data at all the three read entry points raise immediately
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  r RAW(64);
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $hold_port, tx_timeout => 0);
  BEGIN
    s := utl_tcp.get_text(c, 1);
    RAISE NOTICE 'ZTE GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ZTE % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    r := utl_tcp.get_raw(c, 1);
    RAISE NOTICE 'ZRE GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ZRE % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    s := utl_tcp.get_line(c);
    RAISE NOTICE 'ZLE GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ZLE % (%)', SQLERRM, SQLSTATE;
  END;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/ZTE .*timed out.*\(08006\)/,
	'GET_TEXT with no data and tx_timeout 0 raises 08006')
  or diag($err);
like($err, qr/ZRE .*timed out.*\(08006\)/,
	'GET_RAW with no data and tx_timeout 0 raises 08006')
  or diag($err);
like($err, qr/ZLE .*timed out.*\(08006\)/,
	'GET_LINE with no data and tx_timeout 0 raises 08006')
  or diag($err);

# a lone CR terminates a line immediately; an LF arriving afterwards is
# swallowed as part of the same terminator and produces no empty line
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $push_cr_port, tx_timeout => 5);
  s := utl_tcp.get_line(c, remove_crlf => FALSE);
  RAISE NOTICE 'CRL1 len=% last=%',
    length(s), ascii(substr(s, length(s), 1));
  n := utl_tcp.write_raw(c, HEXTORAW('0A65660A'));
  s := utl_tcp.get_line(c, remove_crlf => TRUE);
  RAISE NOTICE 'CRL2 s=% len=%', s, length(s);
  utl_tcp.close_connection(c);
END;
});
like($err, qr/CRL1 len=4 last=13/,
	'a lone CR completes a line without waiting for more bytes')
  or diag($err);
like($err, qr/CRL2 s=ef len=2/,
	'the LF after a lone CR line produces no empty line')
  or diag($err);

# a line without a terminator is returned in full when the transfer
# times out, and the next line continues cleanly afterwards
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $push_abc_port, tx_timeout => 1);
  s := utl_tcp.get_line(c, remove_crlf => TRUE);
  RAISE NOTICE 'PART1 s=% len=%', s, length(s);
  n := utl_tcp.write_raw(c, HEXTORAW('6465660A'));
  s := utl_tcp.get_line(c, remove_crlf => TRUE);
  RAISE NOTICE 'PART2 s=% len=%', s, length(s);
  utl_tcp.close_connection(c);
END;
});
like($err, qr/PART1 s=abc len=3/,
	'an unterminated line is returned when the transfer times out')
  or diag($err);
like($err, qr/PART2 s=def len=3/,
	'the line after a timeout partial return is intact')
  or diag($err);

# a timeout with no complete character raises and keeps the buffer; the
# completed character is read in order afterwards
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $push_mb_port, tx_timeout => 1);
  BEGIN
    s := utl_tcp.get_line(c, remove_crlf => TRUE);
    RAISE NOTICE 'MBL GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'MBL % (%)', SQLERRM, SQLSTATE;
  END;
  n := utl_tcp.write_raw(c, HEXTORAW('BDA0E5A5BD0A'));
  s := utl_tcp.get_line(c, remove_crlf => TRUE);
  RAISE NOTICE 'MBL2 s=% len=%', s, length(s);
  utl_tcp.close_connection(c);
END;
});
like($err, qr/MBL .*timed out.*\(08006\)/,
	'a timeout on an incomplete character raises without losing it')
  or diag($err);
like($err, qr/MBL2 s=$nihao len=2/,
	'the completed character is read in order after the retry')
  or diag($err);

# a timeout while a multibyte character is incomplete raises
# TRANSFER_TIMEOUT and keeps the characters read so far; after the
# remaining bytes arrive they are read in the original order
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $push_mb2_port, tx_timeout => 1);
  BEGIN
    s := utl_tcp.get_text(c, 10);
    RAISE NOTICE 'PT1 len=%', length(s);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PT1 % (%)', SQLERRM, SQLSTATE;
  END;
  n := utl_tcp.write_raw(c, HEXTORAW('A5BD'));
  s := utl_tcp.get_text(c, 2);
  IF s = '$nihao' THEN
    RAISE NOTICE 'PT2 OK';
  ELSE
    RAISE NOTICE 'PT2 BAD bytes=%', octet_length(s);
  END IF;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/PT1 .*timed out.*\(08006\)/,
	'GET_TEXT raises TRANSFER_TIMEOUT with an incomplete trailing character')
  or diag($err);
like($err, qr/PT2 OK/,
	'the buffered characters and the completed one come back in order')
  or diag($err);

# at a clean EOF the complete characters are returned and the partial
# trailing character is left for RAW
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  r RAW(64);
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $pushclose_amb_port,
                               tx_timeout => 2);
  s := utl_tcp.get_text(c, 10);
  RAISE NOTICE 'CEOF1 len=%', length(s);
  r := utl_tcp.get_raw(c, 1);
  RAISE NOTICE 'CEOF2 r=%', r;
  BEGIN
    r := utl_tcp.get_raw(c, 1);
    RAISE NOTICE 'CEOF3 GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'CEOF3 % (%)', SQLERRM, SQLSTATE;
  END;
END;
});
like($err, qr/CEOF1 len=1/,
	'clean EOF returns the complete characters read')
  or diag($err);
like($err, qr/CEOF2 r=\\xe4/i,
	'the partial trailing character is left for GET_RAW')
  or diag($err);
like($err, qr/CEOF3 .*\(P0002\)/,
	'input is at an end after the partial byte')
  or diag($err);

# ---------------------------------------------------------------------
# Transfer timeout, unbounded wait and cancellation
# ---------------------------------------------------------------------

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $hold_port, tx_timeout => 1);
  s := utl_tcp.get_text(c, 1);
  RAISE NOTICE 'TMO GOT (BAD)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'TMO % (%)', SQLERRM, SQLSTATE;
END;
});
like($err, qr/TMO .*transfer timed out after 1 seconds \(08006\)/,
	'GET_TEXT raises TRANSFER_TIMEOUT as 08006 after tx_timeout')
  or diag($err);

# A write to a peer that never reads must time out instead of hanging.
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  big RAW(32767);
  n INTEGER;
  i INTEGER;
BEGIN
  big := HEXTORAW(repeat('AB', 16383));
  c := utl_tcp.open_connection('127.0.0.1', $hold_port, tx_timeout => 1);
  FOR i IN 1 .. 20000 LOOP
    n := utl_tcp.write_raw(c, big);
  END LOOP;
  RAISE NOTICE 'WTMO GOT (BAD)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'WTMO % (%)', SQLERRM, SQLSTATE;
END;
});
like($err, qr/WTMO .*transfer timed out after 1 seconds \(08006\)/,
	'a write that cannot drain raises TRANSFER_TIMEOUT')
  or diag($err);

# An unbounded wait must still be cancellable.
#
# The persistent sessions use background_psql, whose IPC::Run timer is
# part of the harness: a pump that never sees its expected output dies
# after the bound instead of blocking until a process-level timer and
# then being swallowed.  Every wait below is therefore either observed or
# a visible failure.
{
	my $session = $node->background_psql(
		'postgres',
		connstr => $ora_connstr,
		on_error_stop => 0,
		timeout => 60);
	$session->set_query_timer_restart;

	my $be_pid = $session->query('SELECT pg_backend_pid();');
	$be_pid =~ s/\s+//g;
	like($be_pid, qr/^\d+$/, 'persistent session established');

	my $handle = $session->query(
		"SELECT sys.ora_utl_tcp_open_connection('127.0.0.1', $hold_port, "
		  . "NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);");
	$handle =~ s/\s+//g;
	like($handle, qr/^\d+$/, 'persistent session opened a connection');

	# Queue the unbounded read without waiting for it to return.
	$session->{stdin} .= "SELECT sys.ora_utl_tcp_get_text($handle, 1, NULL);\n";

	# wait until the read is parked in the socket wait
	my $waiting = 0;
	for (my $i = 0; $i < 100; $i++)
	{
		sleep 0.1;
		$session->{run}->pump_nb;    # actually transmit the queued statement
		(undef, my $qout) = ora_sql(
			"SELECT count(*) FROM pg_stat_activity "
			  . "WHERE pid = $be_pid AND wait_event = 'UtlTcpIo'");
		if (defined $qout && $qout eq '1')
		{
			$waiting = 1;
			last;
		}
	}
	ok($waiting, 'GET_TEXT with NULL timeout waits in the socket wait');

	ora_sql("SELECT pg_cancel_backend($be_pid)");

	# psql reports the cancellation on stderr; wait for it, bounded
	$session->{timeout}->start(30);
	$session->{run}->pump()
	  until $session->{stderr} =~ /canceling statement/
	  || $session->{timeout}->is_expired;
	die "cancellation of the unbounded GET_TEXT was not reported within 30s\n"
	  . "stderr: $session->{stderr}\n"
	  if $session->{timeout}->is_expired;
	like($session->{stderr}, qr/canceling statement due to user request/,
		'unbounded GET_TEXT is cancellable');

	# the connection survives the statement error and stays usable
	like($session->query("SELECT sys.ora_utl_tcp_write_text($handle, 'y', NULL);"),
		qr/^1$/m, 'connection survives statement errors');

	# close the connection; a void function returns nothing observable, so
	# verify the close through the stale handle afterwards
	$session->query("SELECT sys.ora_utl_tcp_close_connection($handle);");
	$session->query("SELECT sys.ora_utl_tcp_write_text($handle, 'x', NULL);");
	like($session->{stderr}, qr/invalid UTL_TCP connection handle/,
		'persistent session closes its connection');

	# quit sends \q, closes stdin and reaps psql; a session that does not
	# exit within the bound dies here instead of passing silently
	$session->{timeout}->start(30);
	is($session->quit, 1, 'persistent session exits cleanly');
}

# ---------------------------------------------------------------------
# End of input
# ---------------------------------------------------------------------

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  r RAW(64);
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $eof_port, tx_timeout => 5);
  BEGIN
    s := utl_tcp.get_text(c, 1);
    RAISE NOTICE 'EOF1 GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'EOF1 % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    r := utl_tcp.get_raw(c, 1);
    RAISE NOTICE 'EOF2 GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'EOF2 % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    s := utl_tcp.get_line(c);
    RAISE NOTICE 'EOF3 GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'EOF3 % (%)', SQLERRM, SQLSTATE;
  END;
END;
});
like($err, qr/EOF1 .* \(P0002\)/,
	'GET_TEXT at clean EOF raises END_OF_INPUT P0002')
  or diag($err);
like($err, qr/EOF2 .* \(P0002\)/,
	'GET_RAW at clean EOF raises END_OF_INPUT P0002')
  or diag($err);
like($err, qr/EOF3 .* \(P0002\)/,
	'GET_LINE at clean EOF raises END_OF_INPUT P0002')
  or diag($err);

# ---------------------------------------------------------------------
# Close-after-prefix peer: reply then EOF
# ---------------------------------------------------------------------

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $prefix_port, tx_timeout => 5);
  n := utl_tcp.write_text(c, '12345678');
  RAISE NOTICE 'PF n=%', n;
  s := utl_tcp.get_line(c);
  RAISE NOTICE 'PF len=% first=%', length(s), substr(s, 1, 4);
  BEGIN
    s := utl_tcp.get_line(c);
    RAISE NOTICE 'PFEOF GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PFEOF % (%)', SQLERRM, SQLSTATE;
  END;
END;
});
like($err, qr/PF n=8/, 'write to the prefix peer is accepted')
  or diag($err);
like($err, qr/PF len=5 first=done/,
	'reply after the prefix is read with terminator')
  or diag($err);
like($err, qr/PFEOF .* \(P0002\)/,
	'peer close after the reply is END_OF_INPUT')
  or diag($err);

# ---------------------------------------------------------------------
# Slot limit, handle non-reuse, failed opens
# ---------------------------------------------------------------------

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  max_id INTEGER := 0;
BEGIN
  FOR i IN 1 .. 50 LOOP
    c := utl_tcp.open_connection('127.0.0.1', $hold_port);
    IF c.private_sd > max_id THEN
      max_id := c.private_sd;
    END IF;
  END LOOP;
  RAISE NOTICE 'OPEN50 max=%', max_id;
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', $hold_port);
    RAISE NOTICE 'OPEN51 GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'OPEN51 % (%)', SQLERRM, SQLSTATE;
  END;
  utl_tcp.close_connection(c);
  c := utl_tcp.open_connection('127.0.0.1', $hold_port);
  RAISE NOTICE 'REOPEN sd=% fresh=%', c.private_sd, c.private_sd > max_id;
  utl_tcp.close_all_connections();
  c := utl_tcp.open_connection('127.0.0.1', $hold_port);
  RAISE NOTICE 'AFTERALL sd_ok=%', c.private_sd > 0;
  utl_tcp.close_all_connections();
END;
});
like($err, qr/OPEN50 max=\d+/, '50 connections open successfully')
  or diag($err);
like($err, qr/OPEN51 .*too many open connections \(54000\)/,
	'the 51st connection is rejected with 54000')
  or diag($err);
like($err, qr/REOPEN sd=\d+ fresh=t\b/,
	'after a close the slot is reusable and handles are never reused')
  or diag($err);
like($err, qr/AFTERALL sd_ok=t\b/, 'close_all_connections frees every slot')
  or diag($err);

# failed opens must not consume slots
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  ok INTEGER := 0;
BEGIN
  FOR i IN 1 .. 3 LOOP
    BEGIN
      c := utl_tcp.open_connection('127.0.0.1', $refused_port);
      RAISE NOTICE 'REFUSED GOT (BAD)';
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
  BEGIN
    c := utl_tcp.open_connection('no-such-host.invalid', 80);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  FOR i IN 1 .. 50 LOOP
    c := utl_tcp.open_connection('127.0.0.1', $hold_port);
    ok := ok + 1;
  END LOOP;
  RAISE NOTICE 'AFTERFAIL ok=%', ok;
  utl_tcp.close_all_connections();
END;
});
like($err, qr/AFTERFAIL ok=50/,
	'failed opens (refused, unresolvable) consume no slots')
  or diag($err);

# ---------------------------------------------------------------------
# Invalid handles, invalid arguments, unsupported options
# ---------------------------------------------------------------------

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  fake utl_tcp.connection;
  nullrec utl_tcp.connection;
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port, tx_timeout => 5);
  utl_tcp.flush(c);
  RAISE NOTICE 'FLUSH OK';
  fake.private_sd := 999999;
  BEGIN
    n := utl_tcp.write_text(fake, 'x');
    RAISE NOTICE 'FAKE GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'FAKE % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    utl_tcp.flush(nullrec);
    RAISE NOTICE 'NULLH GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'NULLH % (%)', SQLERRM, SQLSTATE;
  END;
  utl_tcp.close_connection(c);
  BEGIN
    n := utl_tcp.write_text(c, 'x');
    RAISE NOTICE 'STALE GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'STALE % (%)', SQLERRM, SQLSTATE;
  END;
END;
});
like($err, qr/FLUSH OK/, 'FLUSH on a live unbuffered connection is a no-op')
  or diag($err);
like($err, qr/FAKE invalid UTL_TCP connection handle \(08003\)/,
	'forged handle is rejected with 08003')
  or diag($err);
like($err, qr/NULLH invalid UTL_TCP connection handle \(08003\)/,
	'NULL handle is rejected with 08003')
  or diag($err);
like($err, qr/STALE invalid UTL_TCP connection handle \(08003\)/,
	'closed handle is rejected with 08003')
  or diag($err);

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  n INTEGER;
  s VARCHAR2(100);
  r RAW(64);
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port, tx_timeout => 5);

  BEGIN
    n := utl_tcp.write_text(c, 'abc', -1);
    RAISE NOTICE 'NEG GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'NEG % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    n := utl_tcp.write_text(c, 'abc', 4);
    RAISE NOTICE 'OVER GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'OVER % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    s := utl_tcp.get_text(c, 0);
    RAISE NOTICE 'ZERO GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ZERO % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    r := utl_tcp.get_raw(c, 32768);
    RAISE NOTICE 'BIGLEN GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'BIGLEN % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    s := utl_tcp.get_text(c, 1, TRUE);
    RAISE NOTICE 'PEEKT GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PEEKT % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    s := utl_tcp.get_line(c, remove_crlf => FALSE, peek => TRUE);
    RAISE NOTICE 'PEEKL GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PEEKL % (%)', SQLERRM, SQLSTATE;
  END;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/NEG .*22023/, 'negative len is rejected with 22023')
  or diag($err);
like($err, qr/OVER .*22023/, 'overlong len is rejected with 22023')
  or diag($err);
like($err, qr/ZERO .*22023/, 'get_text len 0 is rejected with 22023')
  or diag($err);
like($err, qr/BIGLEN .*22023/, 'get_raw len above 32767 is rejected with 22023')
  or diag($err);
like($err, qr/PEEKT .*0A000/, 'get_text peek => TRUE is rejected with 0A000')
  or diag($err);
like($err, qr/PEEKL .*0A000/, 'get_line peek => TRUE is rejected with 0A000')
  or diag($err);

# unsupported non-default open options are rejected one by one
sub try_open_expect_fail
{
	my ($label, $extra) = @_;
	my (undef, undef, $e) = ora_sql(qq{
DECLARE
  cc utl_tcp.connection;
BEGIN
  cc := utl_tcp.open_connection('127.0.0.1', $echo_port, $extra);
  RAISE NOTICE '$label GOT (BAD)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '$label % (%)', SQLERRM, SQLSTATE;
END;
});
	like($e, qr/$label .*not supported.*\(0A000\)/,
		"$extra is rejected with 0A000")
	  or diag($e);
	return;
}

try_open_expect_fail('LH', "local_host => '127.0.0.1'");
try_open_expect_fail('LP', "local_port => 12345");
try_open_expect_fail('IB', "in_buffer_size => 8192");
try_open_expect_fail('OB', "out_buffer_size => 8192");
try_open_expect_fail('WP', "wallet_path => 'file:/tmp/wallet'");
try_open_expect_fail('WPW', "wallet_password => 'secret'");

# NULL/zero buffer sizes select unbuffered I/O and are accepted
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  s VARCHAR2(100);
  n INTEGER;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port,
                               in_buffer_size => 0,
                               out_buffer_size => 0,
                               tx_timeout => 5);
  n := utl_tcp.write_line(c, 'zb');
  s := utl_tcp.get_line(c, TRUE);
  RAISE NOTICE 'ZBUF=%', s;
  utl_tcp.close_connection(c);
END;
});
like($err, qr/ZBUF=zb/, 'zero buffer sizes are accepted (unbuffered)')
  or diag($err);

# negative buffer sizes are bad arguments (22023), and local_port 0 is
# as unsupported as any other non-NULL local port
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  ok INTEGER := 0;
BEGIN
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', $echo_port,
                                 in_buffer_size => -1);
    RAISE NOTICE 'IBNEG GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'IBNEG % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', $echo_port,
                                 out_buffer_size => -5);
    RAISE NOTICE 'OBNEG GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'OBNEG % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', $echo_port,
                                 local_port => 0);
    RAISE NOTICE 'LP0 GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'LP0 % (%)', SQLERRM, SQLSTATE;
  END;
  FOR i IN 1 .. 50 LOOP
    c := utl_tcp.open_connection('127.0.0.1', $hold_port);
    ok := ok + 1;
  END LOOP;
  RAISE NOTICE 'AFTERBAD ok=%', ok;
  utl_tcp.close_all_connections();
END;
});
like($err, qr/IBNEG .*22023/,
	'negative in_buffer_size is rejected with 22023')
  or diag($err);
like($err, qr/OBNEG .*22023/,
	'negative out_buffer_size is rejected with 22023')
  or diag($err);
like($err, qr/LP0 .*not supported \(0A000\)/,
	'local_port 0 is rejected with 0A000')
  or diag($err);
like($err, qr/AFTERBAD ok=50/,
	'rejected open options consume no connection slots')
  or diag($err);

# invalid ports, newline and timeout
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
BEGIN
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', 0);
    RAISE NOTICE 'P0 GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'P0 % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', -1);
    RAISE NOTICE 'PNEG GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PNEG % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', 65536);
    RAISE NOTICE 'PBIG GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PBIG % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', $echo_port, tx_timeout => -5);
    RAISE NOTICE 'TONEG GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TONEG % (%)', SQLERRM, SQLSTATE;
  END;
END;
});
like($err, qr/P0 .*22023/, 'port 0 is rejected with 22023')
  or diag($err);
like($err, qr/PNEG .*22023/, 'negative port is rejected with 22023')
  or diag($err);
like($err, qr/PBIG .*22023/, 'port 65536 is rejected with 22023')
  or diag($err);
like($err, qr/TONEG .*22023/, 'negative tx_timeout is rejected with 22023')
  or diag($err);

# a 3-byte newline never reaches the C function through the package (the
# connection record's VARCHAR2(2) newline field rejects it at bind time
# with 22001); called directly, the C function rejects it with 22023
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
BEGIN
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', $echo_port, newline => 'abc');
    RAISE NOTICE 'NLREC GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'NLREC % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    c.private_sd := sys.ora_utl_tcp_open_connection('127.0.0.1',
      $echo_port, NULL, NULL, NULL, NULL, NULL, 'abc', NULL, NULL, NULL);
    RAISE NOTICE 'NLC GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'NLC % (%)', SQLERRM, SQLSTATE;
  END;
END;
});
like($err, qr/NLREC .*22001/,
	'3-byte newline fails the record bind with 22001')
  or diag($err);
like($err, qr/NLC .*22023/,
	'3-byte newline is rejected with 22023 by the C open function')
  or diag($err);

# connection failures
(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $refused_port);
  RAISE NOTICE 'REF GOT (BAD)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'REF % (%)', SQLERRM, SQLSTATE;
END;
});
like($err, qr/REF .*08001/, 'connection refused reports 08001')
  or diag($err);

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
BEGIN
  c := utl_tcp.open_connection('no-such-host.invalid', 80);
  RAISE NOTICE 'BADHOST GOT (BAD)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'BADHOST % (%)', SQLERRM, SQLSTATE;
END;
});
like($err, qr/BADHOST .*08001/, 'unresolvable host reports 08001')
  or diag($err);

# ---------------------------------------------------------------------
# Security: ownership across SET ROLE, C-level guard
# ---------------------------------------------------------------------

ora_sql("DROP ROLE IF EXISTS utl_low");
ora_sql("CREATE ROLE utl_low NOLOGIN");

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
BEGIN
  SET ROLE utl_low;
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', $echo_port);
    RAISE NOTICE 'NOPRIV GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'NOPRIV % (%)', SQLERRM, SQLSTATE;
  END;
END;
});
like($err, qr/NOPRIV permission denied for package utl_tcp \(42501\)/,
	'a role without EXECUTE cannot call the package at all')
  or diag($err);

ora_sql("GRANT EXECUTE ON PACKAGE utl_tcp TO utl_low");
ora_sql("GRANT EXECUTE ON FUNCTION " .
	"sys.ora_utl_tcp_open_connection(text,integer,text,integer,integer," .
	"integer,text,text,integer,text,text) TO utl_low");

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
BEGIN
  SET ROLE utl_low;
  BEGIN
    c := utl_tcp.open_connection('127.0.0.1', $echo_port);
    RAISE NOTICE 'GUARD GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'GUARD % (%)', SQLERRM, SQLSTATE;
  END;
END;
});
like($err,
	qr/GUARD permission denied to open a UTL_TCP connection \(42501\)/,
	'the C guard denies open even with a direct EXECUTE grant')
  or diag($err);

# a superuser's handle cannot be used after SET ROLE; grants first, since
# PL/iSQL blocks do not run utility DDL inline
ora_sql(
	"GRANT EXECUTE ON FUNCTION " .
	"sys.ora_utl_tcp_write_text(integer, text, integer) TO utl_low");
ora_sql(
	"GRANT EXECUTE ON FUNCTION " .
	"sys.ora_utl_tcp_get_text(integer, integer, boolean) TO utl_low");
ora_sql(
	"GRANT EXECUTE ON FUNCTION " .
	"sys.ora_utl_tcp_close_connection(integer) TO utl_low");

(undef, undef, $err) = ora_sql(qq{
DECLARE
  c utl_tcp.connection;
  n INTEGER;
  s VARCHAR2(100);
BEGIN
  c := utl_tcp.open_connection('127.0.0.1', $echo_port, tx_timeout => 5);
  RAISE NOTICE 'OWNER open=%', c.private_sd > 0;
  SET ROLE utl_low;
  BEGIN
    n := utl_tcp.write_text(c, 'x');
    RAISE NOTICE 'ROLEWR GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ROLEWR % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    s := utl_tcp.get_text(c, 1);
    RAISE NOTICE 'ROLERD GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ROLERD % (%)', SQLERRM, SQLSTATE;
  END;
  BEGIN
    utl_tcp.close_connection(c);
    RAISE NOTICE 'ROLECL GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ROLECL % (%)', SQLERRM, SQLSTATE;
  END;
  RESET ROLE;
  utl_tcp.close_connection(c);
  RAISE NOTICE 'OWNER close OK';
END;
});
like($err, qr/OWNER open=t\b/, 'the owner opens normally')
  or diag($err);
like($err, qr/ROLEWR invalid UTL_TCP connection handle \(08003\)/,
	'SET ROLE cannot write through a foreign handle')
  or diag($err);
like($err, qr/ROLERD invalid UTL_TCP connection handle \(08003\)/,
	'SET ROLE cannot read through a foreign handle')
  or diag($err);
like($err, qr/ROLECL invalid UTL_TCP connection handle \(08003\)/,
	'SET ROLE cannot close a foreign handle')
  or diag($err);
like($err, qr/OWNER close OK/,
	'the owner can still close after RESET ROLE')
  or diag($err);

ora_sql("REVOKE EXECUTE ON PACKAGE utl_tcp FROM utl_low");
ora_sql("DROP ROLE utl_low");

# ---------------------------------------------------------------------
# Backend exit closes sockets (capture peer observes EOF)
# ---------------------------------------------------------------------

{
	my $session = $node->background_psql(
		'postgres',
		connstr => $ora_connstr,
		on_error_stop => 0,
		timeout => 60);
	$session->set_query_timer_restart;

	my $be_pid = $session->query('SELECT pg_backend_pid();');
	$be_pid =~ s/\s+//g;
	like($be_pid, qr/^\d+$/, 'backend-exit session established');

	my $handle = $session->query(
		"SELECT sys.ora_utl_tcp_open_connection('127.0.0.1', $capture_port, "
		  . "NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);");
	$handle =~ s/\s+//g;
	like($handle, qr/^\d+$/, 'backend-exit session opened a connection');

	like(
		$session->query(
			"SELECT sys.ora_utl_tcp_write_text($handle, 'x', NULL);"),
		qr/^1$/m,
		'backend-exit session wrote one character');

	# the capture peer writes asynchronously; wait for the byte to land
	wait_capture_bytes($capture_bin, 1, 'backend-exit capture');
	ok(-s $capture_bin, 'capture peer received the bytes');

	# snapshot the capture log before terminating: the server appends the
	# EOF line as soon as the backend dies, which may beat the next read
	my $log_offset = -s $capture_log;
	$log_offset = 0 unless defined $log_offset;

	ora_sql("SELECT pg_terminate_backend($be_pid)");

	# the capture server must see the connection end when the backend
	# dies; poll its log for a new EOF line, bounded
	my $eof_seen = 0;
	my $eof_deadline = time() + 10;
	while (time() < $eof_deadline)
	{
		my $log = read_bytes($capture_log) // '';
		if (length($log) > $log_offset
			&& substr($log, $log_offset) =~ /EOF 1/)
		{
			$eof_seen = 1;
			last;
		}
		sleep 0.05;
	}
	ok($eof_seen, 'capture peer observed EOF when the backend was terminated')
	  or diag('capture log: ' . (read_bytes($capture_log) // '<missing>'));

	# psql has not noticed the dead backend yet (it is waiting on stdin);
	# \q plus a closed stdin must still end the process within the bound
	$session->{timeout}->start(30);
	is($session->quit, 1, 'backend-exit session exits cleanly');
}

$node->stop('fast');
done_testing();
