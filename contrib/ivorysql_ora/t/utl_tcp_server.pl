#!/usr/bin/perl
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
# Test-only loopback TCP server used by t/001_utl_tcp.pl to exercise the
# UTL_TCP package deterministically.  Never installed.
#
# usage: perl utl_tcp_server.pl <mode> [<arg> ...] <infofile>
#
# The server binds 127.0.0.1:0, writes the assigned port as the first line
# of <infofile>, then serves connections in one of these modes:
#
#   echo            echo every received byte back unchanged (binary safe)
#   bin             echo with an "RX" prefix (binary round trips)
#   hold            accept and hold connections without ever sending;
#                   received bytes are discarded (transfer timeout tests
#                   and the 50-connection slot limit)
#   eof             close every connection immediately after accept
#   capture FILE LOG
#                   append everything received to FILE; when a connection
#                   ends, append one "EOF <bytes>\n" line per connection
#                   to LOG so the test can observe a closed backend
#   frag PAUSE      fragmented delivery: on accept send "abc", sleep PAUSE,
#                   send "d\r", sleep PAUSE, send "\nef\r\n"; input is
#                   discarded (splits a CRLF across two writes)
#   prefix LEN REPLYFILE
#                   read exactly LEN bytes, send the contents of
#                   REPLYFILE and close ("close-after-prefix")
#   push FILE [close]
#                   send the contents of FILE immediately on accept,
#                   then echo everything received (or close right away
#                   with the "close" argument; "push with clean EOF")
#
# The server installs an alarm watchdog and a TERM handler so the TAP
# harness always owns and reaps the child.

use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use Time::HiRes qw(sleep time);

my $mode = shift @ARGV or die "usage: utl_tcp_server.pl <mode> [args...] <infofile>";
my $infofile = pop @ARGV or die "usage: utl_tcp_server.pl <mode> [args...] <infofile>";

$SIG{ALRM} = sub { exit 2 };    # watchdog: CI must never hang on us
alarm 600;
$SIG{TERM} = sub { exit 0 };
$SIG{PIPE} = 'IGNORE';

my $srv = IO::Socket::INET->new(
	LocalAddr => '127.0.0.1',
	LocalPort => 0,
	Listen    => 128,
	ReuseAddr => 1,
	Proto     => 'tcp')
  or die "could not bind loopback listener: $!";
my $port = $srv->sockport;

open my $info, '>', $infofile or die "could not write $infofile: $!";
print $info "$port\n";
close $info;

my $capture_file;
my $capture_log;
if ($mode eq 'capture')
{
	$capture_file = shift @ARGV or die "capture mode needs a data file";
	$capture_log  = shift @ARGV or die "capture mode needs a log file";
}

my $frag_pause;
if ($mode eq 'frag')
{
	$frag_pause = shift @ARGV;
	$frag_pause = 0.3 unless defined $frag_pause;
}

my $prefix;
if ($mode eq 'prefix')
{
	$prefix->{len} = shift @ARGV or die "prefix mode needs a length";
	my $replyfile = shift @ARGV or die "prefix mode needs a reply file";
	open my $rf, '<', $replyfile or die "could not read $replyfile: $!";
	binmode $rf;
	$prefix->{reply} = do { local $/; <$rf> };
}

my $push_reply;
my $push_close = 0;
if ($mode eq 'push')
{
	my $replyfile = shift @ARGV or die "push mode needs a data file";
	open my $rf, '<', $replyfile or die "could not read $replyfile: $!";
	binmode $rf;
	$push_reply = do { local $/; <$rf> };
	$push_close = 1 if (@ARGV && $ARGV[0] eq 'close');
}

my $sel      = IO::Select->new($srv);
my %conns;    # fileno => per-connection state

sub close_conn
{
	my ($st) = @_;
	my $fn   = fileno( $st->{sock} );
	$sel->remove($st->{sock});
	if ($mode eq 'capture')
	{
		open my $log, '>>', $capture_log or die "could not append $capture_log: $!";
		print $log "EOF $st->{received}\n";
		close $log;
	}
	close $st->{sock};
	delete $conns{$fn};
	return;
}

# Queue the fragment script for a frag-mode connection: the pieces go out
# at increasing absolute times so a CRLF lands in two separate writes.
sub start_fragments
{
	my ($st) = @_;
	my @pieces = ( "abc", "d\r", "\nef\r\n" );
	my $at     = time();
	$st->{pending} = [];
	foreach my $piece (@pieces)
	{
		$at += $frag_pause;
		push @{ $st->{pending} }, [ $at, $piece ];
	}
	return;
}

sub push_fragments
{
	foreach my $st (values %conns)
	{
		next unless defined $st->{pending};
		while (@{ $st->{pending} }
			&& $st->{pending}[0][0] <= time())
		{
			my $chunk = $st->{pending}[0][1];
			shift @{ $st->{pending} };
			syswrite($st->{sock}, $chunk);
		}
	}
	return;
}

while (1)
{
	my @ready = $sel->can_read(0.05);

	foreach my $h (@ready)
	{
		if ($h == $srv)
		{
			my $c = $srv->accept or next;
			binmode $c;
			my $st = {
				sock     => $c,
				received => 0,
				read     => 0,
			};
			$conns{ fileno($c) } = $st;
			$sel->add($c);

			if ($mode eq 'eof')
			{
				close_conn($st);
			}
			elsif ($mode eq 'hold')
			{
				# hold the connection open but never read from it, so that
				# a peer writing enough data eventually blocks
				$sel->remove($c);
			}
			elsif ($mode eq 'frag')
			{
				start_fragments($st);
			}
			elsif ($mode eq 'push')
			{
				# deliver the pushed bytes right away; echo or close,
				# depending on the variant
				syswrite($st->{sock}, $push_reply)
					if length($push_reply) > 0;
				if ($push_close)
				{
					close_conn($st);
					next;
				}
			}
			next;
		}

		my $st = $conns{ fileno($h) } or next;

		if ($mode eq 'hold')
		{
			next;    # never read; the connection is only held
		}

		if ($mode eq 'prefix')
		{
			my $data;
			my $n = sysread($h, $data, $prefix->{len} - $st->{read});
			if (!defined $n) { next }
			if ($n == 0)
			{
				close_conn($st);
				next;
			}
			$st->{read} += $n;
			if ($st->{read} >= $prefix->{len})
			{
				syswrite($st->{sock}, $prefix->{reply});
				close_conn($st);
			}
			next;
		}

		my $data;
		my $n = sysread($h, $data, 65536);
		if (!defined $n) { next }    # interrupted read
		if ($n == 0)
		{
			close_conn($st);
			next;
		}

		$st->{received} += $n;

		if ($mode eq 'echo' or $mode eq 'bin' or $mode eq 'push')
		{
			my $out = $mode eq 'bin' ? "RX$data" : $data;
			syswrite($st->{sock}, $out);
		}
		elsif ($mode eq 'capture')
		{
			open my $cf, '>>', $capture_file or die "could not append $capture_file: $!";
			binmode $cf;
			print $cf $data;
			close $cf;
		}

		# 'hold' swallows everything and never answers
	}

	push_fragments();
}
