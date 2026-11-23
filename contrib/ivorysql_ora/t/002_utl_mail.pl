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
# End-to-end test of the UTL_MAIL package against a mock SMTP server that
# speaks just enough RFC 5321 (greeting, EHLO, MAIL FROM, RCPT TO, DATA
# with dot-unstuffing, QUIT) to act as a trustworthy oracle for what the
# C client actually transmits.  Everything the client sends - envelope
# commands and the fully assembled MIME message - is captured verbatim
# and asserted below.
#
# Covered scenarios:
#   * unconfigured UTL_MAIL, SMTP whitelist denial, superuser-only GUCs
#   * SEND with ASCII body, multiple recipients, CC/BCC, reply-to,
#     priority, EHLO identity (smtp_out_domain / client_id)
#   * RFC 2047 encoded-word Chinese subject + base64 UTF-8 body
#   * dot-stuffing round-trip (body line starting with '.')
#   * SEND_ATTACH_RAW binary round-trip, inline disposition, ASCII name
#   * SEND_ATTACH_VARCHAR2 text attachment with a non-ASCII name
#     (RFC 2231 filename*=), plus a large (512 KB) attachment
#   * 550 recipient rejection, connect timeout, priority validation
#
# Windows lacks fork(), which the in-test SMTP mock relies on.

use strict;
use warnings FATAL => 'all';
use POSIX qw(_exit);

# the test file embeds UTF-8 literals (中文 subject, 报告.txt attachment name)
use utf8;

use Encode qw(encode_utf8);
use MIME::Base64 qw(encode_base64 decode_base64);
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

if ($windows_os)
{
	plan skip_all => 'UTL_MAIL mock SMTP test requires fork()';
	exit 0;
}

my $node = PostgreSQL::Test::Cluster->new('utl_mail');
$node->init;

my $db = 'ivorysql';

# Oracle-syntax statements go through the oracle listener port.
sub ora_sql
{
	my ($sql) = @_;
	return $node->safe_psql($db, $sql, connect_to_oraport => 1);
}

# Run a statement and return ($ret, $stdout, $stderr) even when it errors.
sub ora_sql_err
{
	my ($sql) = @_;
	return $node->psql($db, $sql,
		connect_to_oraport => 1,
		on_error_stop     => 0);
}

# ---------------------------------------------------------------------
# Minimal in-test SMTP server.  Runs as a forked child and writes every
# received SMTP command to $logfile and every raw DATA message (after
# dot-unstuffing) to $msgfile.  With silent => 1 the server never greets
# the client (used to provoke the read-timeout path).
#
# The child must stay silent towards the TAP harness even at exit: the
# harness installs TERM/INT handlers that die() and the node object would
# run its DESTROY (which stops the real server) on plain exit(), so the
# child resets its handlers and leaves via POSIX::_exit().
# ---------------------------------------------------------------------
sub mock_smtp_child
{
	my ($port, $msgfile, $logfile, $reject, $silent) = @_;

	$SIG{TERM} = 'DEFAULT';
	$SIG{INT}  = 'DEFAULT';
	$SIG{CHLD} = 'DEFAULT';
	undef $node;				# never touch the cluster from the child

	open STDERR, '>', "$logfile.err" or do { _exit(1) };
	open STDOUT, '>', "$logfile.out" or do { _exit(1) };

	my $sock = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Proto     => 'tcp',
		ReuseAddr => 1,
		Listen    => 5) or do { print STDERR "bind: $!\n"; _exit(1) };

	open my $plog, '>>', $logfile or do { _exit(1) };
	open my $pmsg, '>>', $msgfile or do { _exit(1) };
	my $old = select($plog); $| = 1; select($pmsg); $| = 1; select($old);

	while (my $conn = $sock->accept())
	{
		$conn->autoflush(1);
		if ($silent)
		{
			# never greet: the client must time out waiting for the greeting
			sleep 30;
			next;
		}
		print $conn "220 mock.smtp.local ESMTP ready\r\n";
		my $in_data = 0;
		my $body    = '';
		while (defined(my $line = <$conn>))
		{
			chomp $line;
			$line =~ s/\r$//;
			if ($in_data)
			{
				if ($line eq '.')
				{
					$in_data = 0;
					print $conn "250 2.0.0 OK queued\r\n";
					print $pmsg "$body\n---ENDOFMESSAGE---\n";
					$body = '';
				}
				else
				{
					$line =~ s/^\.//;	# RFC 5321 dot-unstuffing
					$body .= "$line\n";
				}
				next;
			}
			print $plog "C: $line\n";
			if ($line =~ /^EHLO/i)
			{
				print $conn
				  "250-mock.smtp.local\r\n250-8BITMIME\r\n250 SIZE 10485760\r\n";
			}
			elsif ($line =~ /^HELO/i)
			{
				print $conn "250 mock.smtp.local\r\n";
			}
			elsif ($line =~ /^MAIL FROM/i)
			{
				print $conn "250 2.1.0 OK\r\n";
			}
			elsif ($line =~ /^RCPT TO:<([^>]+)>/i)
			{
				my $rcpt = $1;
				if (defined $reject && lc($rcpt) eq lc($reject))
				{
					print $conn "550 5.1.1 no such user\r\n";
				}
				else
				{
					print $conn "250 2.1.5 OK\r\n";
				}
			}
			elsif ($line =~ /^DATA/i)
			{
				$in_data = 1;
				print $conn "354 End data with <CR><LF>.<CR><LF>\r\n";
			}
			elsif ($line =~ /^QUIT/i)
			{
				print $conn "221 2.0.0 bye\r\n";
				last;
			}
			elsif ($line =~ /^(NOOP|RSET)/i)
			{
				print $conn "250 2.0.0 OK\r\n";
			}
			else
			{
				print $conn "500 5.5.2 unrecognized command\r\n";
			}
		}
		close $conn;
	}
	_exit(0);
}

# Start a fresh mock SMTP server for one scenario; returns
# ($pid, $port, $logfile, $msgfile).
sub start_mock_smtp
{
	my (%opts) = @_;
	my $port = PostgreSQL::Test::Cluster::get_free_port();
	my $tag  = $$ . "_" . int(rand(1000000));
	my $dir  = $node->basedir . "/utl_mail_mock_$tag";
	mkdir $dir or die "mkdir $dir: $!";
	my $msgfile = "$dir/message.txt";
	my $logfile = "$dir/smtp.log";

	my $pid = fork();
	die "fork failed: $!" unless defined $pid;
	if ($pid == 0)
	{
		mock_smtp_child($port, $msgfile, $logfile, $opts{reject},
			$opts{silent});
	}
	# give the child a moment to bind its listener
	sleep 1;
	return ($pid, $port, $logfile, $msgfile);
}

sub stop_mock_smtp
{
	my ($pid) = @_;
	return unless defined $pid;
	kill 'TERM', $pid;
	waitpid($pid, 0);
}

# Read the messages captured by the mock (split on its separator).
sub read_messages
{
	my ($msgfile) = @_;
	open my $fh, '<', $msgfile or return ();
	my $raw = do { local $/; <$fh> };
	close $fh;
	my @msgs = split /^---ENDOFMESSAGE---$/m, $raw;
	# the separator is followed by a final newline, which yields a trailing
	# empty element; drop it so $msgs[-1] is the real last message
	pop @msgs if @msgs && $msgs[-1] =~ /^\s*$/;
	return @msgs;
}

sub last_message
{
	my ($msgfile) = @_;
	my @msgs = read_messages($msgfile);
	return $msgs[-1];
}

# Compare ignoring base64 line wrapping (we wrap at 76 like RFC 2045).
sub squash
{
	my ($s) = @_;
	$s =~ s/\s+//g;
	return $s;
}

# Decode the (first) base64 blob found after a Content-Transfer-Encoding:
# base64 header line.  Returns undef when there is none.
sub b64_blob
{
	my ($txt) = @_;
	if ($txt =~ /^Content-Transfer-Encoding: base64\r?\n\r?\n(.*)/ms)
	{
		my $blob = $1;
		$blob =~ s/\r?\n--.*\z//s;	# trim a trailing closing boundary
		return decode_base64(squash($blob));
	}
	return undef;
}

# ---------------------------------------------------------------------
# 0. bring up the node with a mock SMTP preconfigured in
#    postgresql.conf.  smtp_out_server/smtp_out_whitelist are
#    superuser-only, and the TAP sessions are the cluster superuser, so
#    scenarios that need a different server simply override them with a
#    session-level SET on the oracle port.
# ---------------------------------------------------------------------
my ($mock_pid, $mock_port, $mock_log, $mock_msgs) = start_mock_smtp();

$node->append_conf(
	'postgresql.conf', qq{
utl_mail.smtp_out_server = '127.0.0.1:$mock_port'
utl_mail.smtp_out_whitelist = '127.0.0.1'
utl_mail.smtp_out_domain = 'ivorysql.example.org'
utl_mail.timeout = 5000
});
$node->start;

# ---------------------------------------------------------------------
# 1. baseline: UTL_MAIL refuses to run before it is configured
# ---------------------------------------------------------------------
my ($ret, $out, $err) = ora_sql_err(q{
SET utl_mail.smtp_out_server = '';
SELECT sys.ora_utl_mail_send('i@example.com','a@example.com',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);});
like($err, qr/UTL_MAIL is not configured/,
	'UTL_MAIL reports "not configured" when smtp_out_server is unset');

# ---------------------------------------------------------------------
# 2. superuser-only GUCs
# ---------------------------------------------------------------------
ora_sql("CREATE ROLE mail_user LOGIN");
my $connstr_user = $node->connstr($db) . " user=mail_user";
($ret, $out, $err) = $node->psql(
	$db,
	"SET utl_mail.smtp_out_server = '1.2.3.4:25';",
	connstr       => $connstr_user,
	on_error_stop => 0);
like(
	$err,
	qr/permission denied to set parameter "utl_mail\.smtp_out_server"/,
	'non-superuser cannot set utl_mail.smtp_out_server');
($ret, $out, $err) = $node->psql(
	$db,
	"SET utl_mail.smtp_out_whitelist = '*';",
	connstr       => $connstr_user,
	on_error_stop => 0);
like(
	$err,
	qr/permission denied to set parameter "utl_mail\.smtp_out_whitelist"/,
	'non-superuser cannot set utl_mail.smtp_out_whitelist');

# ---------------------------------------------------------------------
# 3. outbound whitelist: a server host outside the whitelist is blocked
#    before any socket is opened
# ---------------------------------------------------------------------
($ret, $out, $err) = ora_sql_err(q{
SET utl_mail.smtp_out_whitelist='example.com';
SELECT sys.ora_utl_mail_send('i@example.com','a@example.com',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);});
like(
	$err,
	qr/outbound mail blocked by the SMTP whitelist.*"127\.0\.0\.1"/s,
	'SMTP server outside the whitelist is blocked');
ora_sql("SET utl_mail.smtp_out_whitelist = '127.0.0.1'");
ora_sql("SET utl_mail.smtp_out_server = '127.0.0.1:$mock_port'");

# ---------------------------------------------------------------------
# 4. SEND: ASCII body, multiple recipients, CC/BCC, priority, reply-to
#    (multi-line bodies are assembled with chr(10): the oracle parser
#    collapses whitespace inside string literals)
# ---------------------------------------------------------------------
my $body_ascii =
  "'line one' || chr(10) || 'line two' || chr(10) || '.leading-dot line' || chr(10) || 'last line'";
ora_sql(qq{
BEGIN
  utl_mail.send(sender => 'ivory\@example.com',
    recipients => 'alice\@example.com, bob\@example.com',
    cc => 'carol\@example.com',
    bcc => 'dave\@example.com',
    subject => 'Plain ASCII subject',
    message => $body_ascii,
    priority => 5,
    replyto => 'noreply\@example.com');
END;});

my $msg = last_message($mock_msgs);
ok(defined $msg && length($msg) > 0, 'mock SMTP captured a message');
unlike($msg, qr/^Bcc:/mi, 'no Bcc header is emitted (bcc stays in the envelope)');
like($msg, qr/^From: ivory\@example\.com$/mi, 'From header');
like($msg, qr/^To: alice\@example\.com, bob\@example\.com$/mi, 'To header');
like($msg, qr/^Cc: carol\@example\.com$/mi, 'Cc header');
like($msg, qr/^Reply-To: noreply\@example\.com$/mi, 'Reply-To header');
like($msg, qr/^Subject: Plain ASCII subject$/mi, 'ASCII subject is not encoded');
like($msg, qr/^X-Priority: 5$/mi, 'X-Priority header');
like($msg, qr/^Content-Transfer-Encoding: 7bit$/mi, 'ASCII body uses 7bit CTE');
like($msg, qr/^\.leading-dot line$/m,
	'dot-stuffing round-trip: a body line starting with "." survives');
like($msg, qr/line one\r?\nline two\r?\n\.leading-dot line\r?\nlast line/,
	'body lines are delivered with CRLF and in order');

my $raw_log = slurp_file($mock_log);
like($raw_log, qr/^C: EHLO ivorysql\.example\.org$/mi,
	'EHLO advertises utl_mail.smtp_out_domain');
like($raw_log, qr/^C: MAIL FROM:<ivory\@example\.com>$/mi,
	'MAIL FROM envelope sender');
like(
	$raw_log,
	qr/^C: RCPT TO:<alice\@example\.com>.*^C: RCPT TO:<bob\@example\.com>.*^C: RCPT TO:<carol\@example\.com>.*^C: RCPT TO:<dave\@example\.com>/ms,
	'envelope lists recipients, cc and bcc');
like($raw_log, qr/^C: DATA$/m, 'DATA command issued');
like($raw_log, qr/^C: QUIT$/m, 'QUIT issued');

# utl_mail.client_id overrides the HELO identity (session-scoped: SET and
# the send must happen in the same psql session, i.e. the same string)
ora_sql(q{
SET utl_mail.client_id = 'mail-01';
BEGIN
  utl_mail.send('ivory@example.com', 'alice@example.com',
                subject => 'x', message => 'y');
END;});
like(slurp_file($mock_log), qr/^C: EHLO mail-01$/mi,
	'utl_mail.client_id is used as the EHLO identity');

# ---------------------------------------------------------------------
# 5. Chinese subject (RFC 2047 encoded-word) + UTF-8 body (base64 CTE)
# ---------------------------------------------------------------------
my $utf8_subject = '中文主题 ✓';
my $utf8_body    =
  "'第一行中文' || chr(10) || '.点开头行' || chr(10) || '第三行'";
ora_sql(qq{
BEGIN
  utl_mail.send('ivory\@example.com', 'alice\@example.com',
    subject => '$utf8_subject', message => $utf8_body);
END;});
$msg = last_message($mock_msgs);

my $expected_word = '=?utf-8?B?' . encode_base64(encode_utf8($utf8_subject), '') . '?=';
my $subj_line = ($msg =~ /^Subject: (.*)$/mi)[0];
ok(defined $subj_line && unpack('H*', $subj_line) eq unpack('H*', $expected_word),
	'Chinese subject uses RFC 2047 B-encoding');
like($msg, qr/^Content-Transfer-Encoding: base64$/mi,
	'non-ASCII body uses base64 transport encoding');
like($msg, qr/charset=UTF-8/i, 'non-ASCII body claims charset=UTF-8');

if (defined(my $decoded = b64_blob($msg)))
{
	# decode_base64 yields plain bytes; decode to a character string so
	# the pattern literals (compiled with use utf8) line up
	utf8::decode($decoded);
	my $expected_body = "第一行中文\n.点开头行\n第三行";
	ok($decoded eq $expected_body,
		'base64 body decodes back to the exact UTF-8 bytes');
	ok($decoded =~ /\n\.\Q点开头行\E/m,
		'dot-stuffed line round-trips in the base64 body too');
}
else
{
	fail('could not locate the base64 body blob');
}

# ---------------------------------------------------------------------
# 6. SEND_ATTACH_RAW: binary round-trip, inline disposition, ASCII name
# ---------------------------------------------------------------------
my $att_hex = '00112233445566778899aabbccddeeff' . 'deadbeef' . '0123456789abcdef';
ora_sql(qq{
BEGIN
  utl_mail.send_attach_raw('ivory\@example.com', 'alice\@example.com',
    subject => 'binary attachment', message => 'see the file',
    attachment => decode('$att_hex', 'hex'),
    att_inline => TRUE,
    att_mime_type => 'application/x-test',
    att_filename => 'data.bin');
END;});
$msg = last_message($mock_msgs);
like($msg, qr/^Content-Type: multipart\/mixed; boundary="----=_ivorysql_\d+"$/mi,
	'attachment produces a multipart/mixed message');
like($msg, qr/^Content-Type: application\/x-test; name="data\.bin"$/mi,
	'attachment part carries the MIME type and name');
like($msg, qr/^Content-Disposition: inline; filename="data\.bin"$/mi,
	'att_inline => TRUE yields an inline disposition');
if (defined(my $decoded = b64_blob($msg)))
{
	is(unpack('H*', $decoded), $att_hex,
		'raw attachment round-trips byte-for-byte');
}
else
{
	fail('could not locate the attachment base64 blob');
}

# ---------------------------------------------------------------------
# 7. SEND_ATTACH_VARCHAR2 with a non-ASCII (RFC 2231) filename
# ---------------------------------------------------------------------
my $txt_attach = "'line 1' || chr(10) || 'line 2'";
ora_sql(qq{
BEGIN
  utl_mail.send_attach_varchar2('ivory\@example.com', 'alice\@example.com',
    subject => 'text attachment', message => 'see the file',
    attachment => $txt_attach, att_filename => '报告.txt');
END;});
$msg = last_message($mock_msgs);
like(
	$msg,
	qr/^Content-Disposition: attachment; filename\*=UTF-8''%E6%8A%A5%E5%91%8A\.txt$/mi,
	'non-ASCII attachment name is RFC 2231 encoded');
like(
	$msg,
	qr/^Content-Type: application\/octet; name\*=UTF-8''%E6%8A%A5%E5%91%8A\.txt$/mi,
	'non-ASCII attachment name encoded in Content-Type name= too');

# ---------------------------------------------------------------------
# 8. large attachment (512 KB)
# ---------------------------------------------------------------------
my $big_hex = 'ab' x (512 * 1024);	# 512 KB, 2 hex chars per byte
ora_sql(qq{
BEGIN
  utl_mail.send_attach_raw('ivory\@example.com', 'alice\@example.com',
    subject => 'big', attachment => decode('$big_hex', 'hex'),
    att_filename => 'big.bin');
END;});
$msg = last_message($mock_msgs);
ok(defined $msg && length($msg) > 680 * 1024,
	'large (512 KB) attachment is transmitted (message > 680 KB)');

# ---------------------------------------------------------------------
# 9. priority validation (before any network I/O)
# ---------------------------------------------------------------------
($ret, $out, $err) = ora_sql_err(q{
BEGIN
  utl_mail.send('i@example.com','a@example.com', priority => 0);
END;});
like($err, qr/priority must be between 1 and 5/, 'priority 0 rejected');
($ret, $out, $err) = ora_sql_err(q{
BEGIN
  utl_mail.send('i@example.com','a@example.com', priority => 6);
END;});
like($err, qr/priority must be between 1 and 5/, 'priority 6 rejected');

# ---------------------------------------------------------------------
# 10. 550 recipient rejection -> EMAIL_SEND_FAILED naming the address
# ---------------------------------------------------------------------
stop_mock_smtp($mock_pid);
my ($reject_pid, $reject_port, $reject_log, $reject_msgs) =
  start_mock_smtp(reject => 'bob@example.com');

($ret, $out, $err) = ora_sql_err(qq{
SET utl_mail.smtp_out_server = '127.0.0.1:$reject_port';
BEGIN
  utl_mail.send('ivory\@example.com',
    'alice\@example.com, bob\@example.com',
    subject => 'rejected', message => 'x');
END;});
like(
	$err,
	qr/UTL_MAIL\.EMAIL_SEND_FAILED.*RCPT TO:<bob\@example\.com> rejected/s,
	'SMTP 550 for one recipient yields EMAIL_SEND_FAILED naming the address');
stop_mock_smtp($reject_pid);

# ---------------------------------------------------------------------
# 11. read timeout against a silent (never-greeting) listener
# ---------------------------------------------------------------------
my ($black_pid, $black_port, $black_log, $black_msgs) =
  start_mock_smtp(silent => 1);

($ret, $out, $err) = ora_sql_err(qq{
SET utl_mail.smtp_out_server = '127.0.0.1:$black_port';
SET utl_mail.timeout = 500;
BEGIN
  utl_mail.send('i\@example.com','a\@example.com', subject => 'timeout');
END;});
like(
	$err,
	qr/UTL_MAIL\.EMAIL_SEND_FAILED.*Timed out waiting for the SMTP server while server greeting/s,
	'silent SMTP server provokes EMAIL_SEND_FAILED (greeting timeout)');
stop_mock_smtp($black_pid);

done_testing();