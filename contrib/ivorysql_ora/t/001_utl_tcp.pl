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

sub start_server
{
	my ($name, @args) = @_;
	my $info = File::Spec->catfile($tmpdir, "$name.info");
	unlink $info;
	$SRV{$name} = IPC::Run::start(
		[ $^X, $server_pl, $name, @args, $info ],
		\my $in, \my $out, \my $err);
	PostgreSQL::Test::Utils::wait_for_file($info, qr/^\d+$/m);
	open my $fh, '<', $info or die "could not read $info: $!";
	$SRV_PORT{$name} = <$fh>;
	chomp $SRV_PORT{$name};
	close $fh;
	return $SRV_PORT{$name};
}

END
{
	foreach my $h (values %SRV)
	{
		eval { $h->kill_kill; };
	}
}

my $echo_port    = start_server('echo');
my $bin_port     = start_server('bin');
my $hold_port    = start_server('hold');
my $eof_port     = start_server('eof');
my $capture_port = start_server('capture',
	File::Spec->catfile($tmpdir, 'capture.bin'),
	File::Spec->catfile($tmpdir, 'capture.log'));
my $frag_port    = start_server('frag', 0.3);

# A port that refuses connections immediately: bind and close a listener.
my $refused_sock = IO::Socket::INET->new(
	LocalAddr => '127.0.0.1', LocalPort => 0, Listen => 1, Proto => 'tcp')
  or die "could not bind refused-port listener: $!";
my $refused_port = $refused_sock->sockport;
close $refused_sock;

my $prefix_reply = File::Spec->catfile($tmpdir, 'prefix.reply');
PostgreSQL::Test::Utils::append_to_file($prefix_reply, "done\n");
my $prefix_port = start_server('prefix', 8, $prefix_reply,
	File::Spec->catfile($tmpdir, 'prefix.info'));

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
is(read_bytes($capture_bin), "x\n",
	'capture shows data plus the registered LF newline');
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
is(unpack('H*', read_bytes($capture_bin) // ''), 'e941',
	'capture shows LATIN1-converted byte and the len-clipped text');
unlink $capture_bin;

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
{
	my ($pin, $pout, $perr) = ('', '', '');
	my $session = IPC::Run::start(
		[ 'psql', '-XAtq', '--dbname' => $ora_connstr ],
		\$pin, \$pout, \$perr,
		IPC::Run::timeout(120, exception => qq(session timed out)));

	$pin .= "SELECT pg_backend_pid();\n";
	PostgreSQL::Test::Utils::pump_until($session,
		IPC::Run::timeout(30), \$pout, qr/\d+/);
	my ($be_pid) = $pout =~ /(\d+)/g;
	$pout = '';
	ok($be_pid > 0, 'persistent session established');

	$pin .=
	  "SELECT sys.ora_utl_tcp_open_connection('127.0.0.1', $hold_port, " .
	  "NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);\n";
	PostgreSQL::Test::Utils::pump_until($session,
		IPC::Run::timeout(30), \$pout, qr/\d+/);
	$pout =~ /(\d+)\s*$/;
	my $handle = $1;
	ok($handle > 0, 'persistent session opened a connection');

	$pin .= "SELECT sys.ora_utl_tcp_get_text($handle, 1, NULL);\n";

	# wait until the read is parked in the socket wait
	my $waiting = 0;
	for (my $i = 0; $i < 100; $i++)
	{
		sleep 0.1;
		$session->pump_nb;    # actually transmit the queued statement
		(undef, my $qout) = ora_sql(
			"SELECT count(*) FROM pg_stat_activity " .
			"WHERE pid = $be_pid AND wait_event = 'UtlTcpIo'");
		if (defined $qout && $qout eq '1')
		{
			$waiting = 1;
			last;
		}
	}
	ok($waiting, 'GET_TEXT with NULL timeout waits in the socket wait');

	ora_sql("SELECT pg_cancel_backend($be_pid)");
	PostgreSQL::Test::Utils::pump_until($session,
		IPC::Run::timeout(30), \$perr, qr/canceling statement/);
	like($perr, qr/canceling statement due to user request/,
		'unbounded GET_TEXT is cancellable')
	  or diag($perr);

	# the connection survives the statement error and stays usable
	$pout = '';
	$pin .= "SELECT sys.ora_utl_tcp_flush($handle) IS NULL;\n";
	PostgreSQL::Test::Utils::pump_until($session,
		IPC::Run::timeout(30), \$pout, qr/^t$/m);
	like($pout, qr/^t$/m, 'connection survives statement errors')
	  or diag($pout);

	$pout = '';
	$pin .= "SELECT sys.ora_utl_tcp_close_connection($handle) IS NULL;\n";
	PostgreSQL::Test::Utils::pump_until($session,
		IPC::Run::timeout(30), \$pout, qr/^t$/m);
	$pin .= "\\q\n";
	my $quit_deadline = time() + 15;
	while (time() < $quit_deadline && $session->pumpable)
	{
		$session->pump_nb;
		sleep 0.05;
	}
	eval { $session->finish(15) };
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
like($err, qr/OPEN51 too many open connections \(54000\)/,
	'the 51st connection is rejected with 54000')
  or diag($err);
like($err, qr/REOPEN sd=\d+ fresh=t/,
	'after a close the slot is reusable and handles are never reused')
  or diag($err);
like($err, qr/AFTERALL sd_ok=t/, 'close_all_connections frees every slot')
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
	like($e, qr/$label .*not supported \(0A000\)/,
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
    c := utl_tcp.open_connection('127.0.0.1', $echo_port, newline => 'abc');
    RAISE NOTICE 'NL GOT (BAD)';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'NL % (%)', SQLERRM, SQLSTATE;
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
like($err, qr/NL .*22023/, '3-byte newline is rejected with 22023')
  or diag($err);
like($err, qr/TONEG .*22023/, 'negative tx_timeout is rejected with 22023')
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
like($err, qr/OWNER open=t/, 'the owner opens normally')
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
	my ($pin, $pout, $perr) = ('', '', '');
	my $session = IPC::Run::start(
		[ 'psql', '-XAtq', '--dbname' => $ora_connstr ],
		\$pin, \$pout, \$perr,
		IPC::Run::timeout(120, exception => qq(session timed out)));

	$pin .= "SELECT pg_backend_pid();\n";
	PostgreSQL::Test::Utils::pump_until($session,
		IPC::Run::timeout(30), \$pout, qr/\d+/);
	my ($be_pid) = $pout =~ /(\d+)/g;
	$pout = '';

	$pin .=
	  "SELECT sys.ora_utl_tcp_open_connection('127.0.0.1', $capture_port, " .
	  "NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);\n";
	PostgreSQL::Test::Utils::pump_until($session,
		IPC::Run::timeout(30), \$pout, qr/\d+/);
	$pout =~ /(\d+)\s*$/;
	my $handle = $1;

	$pout = '';
	$pin .= "SELECT sys.ora_utl_tcp_write_text($handle, 'x', NULL);\n";
	PostgreSQL::Test::Utils::pump_until($session,
		IPC::Run::timeout(30), \$pout, qr/^1$/m);

	ok(-s $capture_bin, 'capture peer received the bytes');

	ora_sql("SELECT pg_terminate_backend($be_pid)");

	# the capture server must see the connection end when the backend dies
	my $log_offset = -s $capture_log;
	$log_offset = 0 unless defined $log_offset;
	eval {
		PostgreSQL::Test::Utils::wait_for_file($capture_log, qr/EOF 1/,
			$log_offset);
	};
	ok(!$@, 'capture peer observed EOF when the backend was terminated')
	  or diag($@);

	eval { $session->finish(15) };
}

$node->stop('fast');
done_testing();
