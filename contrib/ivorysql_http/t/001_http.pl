# Copyright 2026 IvorySQL Global Development Team
# Licensed under the Apache License, Version 2.0. See LICENSE.
use strict;
use warnings FATAL => 'all';
use FindBin;
use lib "$FindBin::RealBin/../../../src/oracle_test/perl";
use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;
use Time::HiRes qw(usleep time);

my @servers;
my $test_pid = $$;

END
{
	my $saved_status = $?;
	if (defined($test_pid) && $$ == $test_pid)
	{
		for my $pid (@servers) { kill 'TERM', $pid; waitpid($pid, 0); }
	}
	$? = $saved_status;
}
my $node = PostgreSQL::Test::Cluster->new('http');
$node->init;
$node->start;
my $db = 'ivorysql';
sub sql { return $node->safe_psql($db, $_[0]); }
sub ora { return $node->safe_psql($db, $_[0], connect_to_oraport => 1); }

sub fails
{
	my ($query, $pattern, $name, $oracle) = @_;
	my ($out, $err);
	isnt(
		$node->psql(
			$db, $query,
			stdout => \$out,
			stderr => \$err,
			connect_to_oraport => ($oracle || 0)),
		0, $name);
	like($err, $pattern, "$name reports the cause");
}

sub server
{
	my ($suffix, @extra) = @_;
	my $ready = $node->basedir . "/http_ready_$suffix";
	my $pid = fork();
	die 'fork failed' unless defined $pid;
	if (!$pid)
	{
		exec($ENV{PYTHON} || 'python3',
			"$FindBin::RealBin/http_server.py",
			$ready, @extra);
		die 'exec failed';
	}
	push @servers, $pid;
	for (1 .. 1000) { last if -e $ready; usleep(10000); }
	die 'HTTP fixture did not start' unless -e $ready;
	return slurp_file($ready);
}
my $port = server('plain');
my $url = "http://127.0.0.1:$port";
ora('CREATE EXTENSION ivorysql_http');
fails(
	"SELECT sys.ora_utl_http_begin('$url/hello','GET','HTTP/1.1')",
	qr/is not granted/,
	'network access is denied by default');
sql("INSERT INTO sys.utl_http_host_acl VALUES(current_user::regrole,'127.0.0.1',$port,NULL)"
);
my $session = $node->background_psql($db);
my $id = $session->query_safe(
	"SELECT sys.ora_utl_http_begin('$url/chunk','GET','HTTP/1.1')");
$session->query_safe("SELECT sys.ora_utl_http_response($id)");
is($session->query_safe("SELECT (sys.ora_utl_http_info($id))[1]"),
	'200', 'gets HTTP status');
is($session->query_safe("SELECT (sys.ora_utl_http_info($id))[3]"),
	'HTTP/1.1', 'reports actual HTTP version');
is( $session->query_safe(
		"SELECT encode(convert_to(sys.ora_utl_http_read($id,2),'UTF8'),'hex')"
	),
	'e4bda0e5a5bd',
	'character reads preserve UTF-8 split between network chunks');
is( $session->query_safe(
		"SELECT encode(convert_to(sys.ora_utl_http_read($id,32767),'UTF8'),'hex')"
	),
	'efbc8c49766f727953514cf09f8c8d',
	'next read resumes at a complete character');
is($session->query_safe("SELECT sys.ora_utl_http_read($id,1) IS NULL"),
	't', 'helper signals EOF without manufacturing text');
$session->query_safe("SELECT sys.ora_utl_http_close($id)");
$session->quit;
sql('CREATE TABLE http_package_results(mode text, status integer, body text, eof boolean, header_found boolean)'
);

for my $mode ('normal', 'interchange', 'lowercase')
{
	my ($out, $err);
	my $status = $node->psql(
		$db, qq{
SET ivorysql.identifier_case_switch='$mode';
DECLARE rq utl_http.req; rs utl_http.resp; data VARCHAR2; name VARCHAR2; value VARCHAR2;
  done BOOLEAN:=FALSE; found_header BOOLEAN:=FALSE;
  http_eof EXCEPTION;
  PRAGMA EXCEPTION_INIT(http_eof,-29266);
BEGIN
  rq:=utl_http.begin_request('$url/echo','POST');
  utl_http.set_header(rq,'Content-Type','application/json; charset=UTF-8');
  utl_http.set_header(rq,'X-Test','old');
  utl_http.set_header(rq,'X-Test','new');
  utl_http.write_text(rq,'{"message":"IvorySQL"}');
  rs:=utl_http.get_response(rq);
  FOR i IN 1..utl_http.get_header_count(rs) LOOP
    utl_http.get_header(rs,i,name,value);
    IF name='X-Echo' AND value='new' THEN found_header:=TRUE; END IF;
  END LOOP;
  utl_http.read_text(rs,data);
  BEGIN
    DECLARE ignored VARCHAR2;
    BEGIN utl_http.read_text(rs,ignored); END;
  EXCEPTION WHEN http_eof THEN done:=TRUE;
  END;
  INSERT INTO http_package_results VALUES('$mode',rs.status_code,data,done,found_header);
  utl_http.end_response(rs);
END;
},
		connect_to_oraport => 1,
		stdout => \$out,
		stderr => \$err);
	is($status, 0, "public lifecycle works in $mode mode") or diag($err);
	is( sql("SELECT status||'|'||body||'|'||eof||'|'||header_found FROM http_package_results WHERE mode='$mode'"
		),
		'201|{"message":"IvorySQL"}|true|true',
		"public POST, header replacement and EOF work in $mode mode");
}
is( ora("SELECT encode(convert_to(utl_http.request('$url/hello'),'UTF8'),'hex')"
	),
	'e4bda0e5a5bdefbc8c49766f727953514cf09f8c8d',
	'simple REQUEST retrieves text');
is( ora("SELECT CASE WHEN utl_http.request('$url/empty') IS NULL THEN 1 ELSE 0 END"
	),
	'1',
	'simple REQUEST handles an empty body');
ora(qq{
SET ivorysql.identifier_case_switch=normal;
DECLARE rq utl_http.req; timeout_value INTEGER;
BEGIN
  utl_http.set_transfer_timeout(2); timeout_value:=utl_http.get_transfer_timeout();
  rq:=utl_http.begin_request('$url/hello'); utl_http.end_request(rq);
  INSERT INTO http_package_results VALUES('timeout',timeout_value,NULL,rq.private_id IS NULL,FALSE);
END;
});
is( sql("SELECT status||'|'||eof FROM http_package_results WHERE mode='timeout'"
	),
	'2|true',
	'public timeout accessors and END_REQUEST work');
my $s = $node->background_psql($db);
for my $path ('redirect', 'missing')
{
	my $h = $s->query_safe(
		"SELECT sys.ora_utl_http_begin('$url/$path','GET','HTTP/1.1')");
	$s->query_safe("SELECT sys.ora_utl_http_response($h)");
	is( $s->query_safe("SELECT (sys.ora_utl_http_info($h))[1]"),
		$path eq 'redirect' ? '302' : '404',
		"$path status remains visible without redirect following");
	$s->query_safe("SELECT sys.ora_utl_http_close($h)");
}
$s->quit;
fails(
	"SELECT sys.ora_utl_http_begin('file:///etc/passwd','GET','HTTP/1.1')",
	qr/expected an HTTP/,
	'non-HTTP schemes are rejected');
fails(
	"SELECT sys.ora_utl_http_begin('http://user:pass\@127.0.0.1:$port/','GET','HTTP/1.1')",
	qr/without user credentials/,
	'URL credentials are rejected');
fails(
	"SELECT sys.ora_utl_http_begin('http://127.0.0.1:1/','GET','HTTP/1.1')",
	qr/is not granted/,
	'ACL is specific to port');
fails(
	"DO \$\$DECLARE h integer:=sys.ora_utl_http_begin('$url/hello','GET','HTTP/1.1'); BEGIN PERFORM sys.ora_utl_http_set_header(h,'X-Test',E'bad\\r\\nInjected: yes'); END\$\$",
	qr/control characters/,
	'header injection is rejected');
fails(
	"DO \$\$DECLARE h integer:=sys.ora_utl_http_begin('$url/hello','GET','HTTP/1.1'); BEGIN PERFORM sys.ora_utl_http_set_header(h,'Content-Length','2'); END\$\$",
	qr/framing headers/,
	'caller cannot override HTTP framing');
fails(
	"DO \$\$DECLARE h integer:=sys.ora_utl_http_begin('$url/large','GET','HTTP/1.1'); BEGIN PERFORM sys.ora_utl_http_response(h); END\$\$",
	qr/exceeds body\/header limits/,
	'oversized response is bounded');
fails(
	"DO \$\$DECLARE h integer:=sys.ora_utl_http_begin('$url/latin','GET','HTTP/1.1'); BEGIN PERFORM sys.ora_utl_http_response(h); PERFORM sys.ora_utl_http_read(h,10); END\$\$",
	qr/charset is not UTF-8/,
	'unsupported charset is rejected instead of misdecoded');
fails(
	"DO \$\$DECLARE h integer:=sys.ora_utl_http_begin('$url/latin-spaced','GET','HTTP/1.1'); BEGIN PERFORM sys.ora_utl_http_response(h); PERFORM sys.ora_utl_http_read(h,10); END\$\$",
	qr/charset is not UTF-8/,
	'quoted charset with optional whitespace is checked');
is( ora("SELECT encode(convert_to(utl_http.request('$url/utf8-spaced'),'UTF8'),'hex')"
	),
	'e4bda0e5a5bdefbc8c49766f727953514cf09f8c8d',
	'quoted parameters do not hide the actual UTF-8 charset');
my $started = time();
fails(
	"DO \$\$DECLARE h integer; BEGIN PERFORM sys.ora_utl_http_timeout(1); h:=sys.ora_utl_http_begin('$url/slow','GET','HTTP/1.1'); PERFORM sys.ora_utl_http_response(h); END\$\$",
	qr/HTTP transfer failed/,
	'transfer timeout cancels a slow response');
ok(time() - $started < 5, 'transfer timeout is bounded');
fails(
	"SET statement_timeout='500ms'; DO \$\$DECLARE h integer:=sys.ora_utl_http_begin('$url/slow','GET','HTTP/1.1'); BEGIN PERFORM sys.ora_utl_http_response(h); END\$\$",
	qr/statement timeout/,
	'query cancellation exits libcurl cleanly');
sql('CREATE ROLE http_app; CREATE ROLE http_other; GRANT http_app TO http_other'
);
fails(
	"SET ROLE http_app; SELECT sys.ora_utl_http_begin('$url/hello','GET','HTTP/1.1')",
	qr/is not granted/,
	'ungranted application role has no network access');
sql("INSERT INTO sys.utl_http_host_acl VALUES('http_app'::regrole,'127.0.0.1',$port,NULL)"
);
my $owner = $node->background_psql($db);
$owner->query_safe('SET ROLE http_other');
my $owned = $owner->query_safe(
	"SELECT sys.ora_utl_http_begin('$url/hello','GET','HTTP/1.1')");
like($owned, qr/^\d+$/, 'inherited ACL grants permit requests');
$owner->query_safe('SET ROLE http_app');
is( $owner->query_safe(
		"DO \$\$BEGIN PERFORM sys.ora_utl_http_write($owned,'x'); RAISE EXCEPTION 'unexpected success'; EXCEPTION WHEN insufficient_privilege THEN NULL; END\$\$; SELECT 1"
	),
	'1',
	'role change cannot use another role handle');
$owner->query_safe('SET ROLE http_other');
$owner->query_safe("SELECT sys.ora_utl_http_close($owned)");
my $pending = $owner->query_safe(
	"SELECT sys.ora_utl_http_begin('$url/hello','GET','HTTP/1.1')");
sql("DELETE FROM sys.utl_http_host_acl WHERE role_oid='http_app'::regrole");
is( $owner->query_safe(
		"DO \$\$BEGIN PERFORM sys.ora_utl_http_response($pending); RAISE EXCEPTION 'unexpected success'; EXCEPTION WHEN insufficient_privilege THEN NULL; END\$\$; SELECT 1"
	),
	'1',
	'revoked ACL is checked again before network transfer');
$owner->query_safe("SELECT sys.ora_utl_http_close($pending)");
sql("INSERT INTO sys.utl_http_host_acl VALUES('http_app'::regrole,'127.0.0.1',$port,NULL)"
);
my @handles;

for (1 .. 16)
{
	push @handles,
	  $owner->query_safe(
		"SELECT sys.ora_utl_http_begin('$url/hello','GET','HTTP/1.1')");
}
is( $owner->query_safe(
		"DO \$\$BEGIN PERFORM sys.ora_utl_http_begin('$url/hello','GET','HTTP/1.1'); RAISE EXCEPTION 'unexpected success'; EXCEPTION WHEN program_limit_exceeded THEN NULL; END\$\$; SELECT 1"
	),
	'1',
	'session handle count has a hard limit');
for my $h (@handles)
{
	$owner->query_safe("SELECT sys.ora_utl_http_close($h)");
}
$owner->query_safe(
	"BEGIN; SELECT sys.ora_utl_http_begin('$url/hello','GET','HTTP/1.1'); ROLLBACK"
);
$owner->query_safe('RESET ROLE');
is( $owner->query_safe(
		q{SELECT count(*) FROM pg_backend_memory_contexts WHERE name='UTL_HTTP request'}
	),
	'0',
	'transaction abort releases outstanding handles');
$owner->query_safe('SET ROLE http_other');
for (1 .. 200)
{
	my $h = $owner->query_safe(
		"SELECT sys.ora_utl_http_begin('$url/hello','GET','HTTP/1.1')");
	$owner->query_safe("SELECT sys.ora_utl_http_close($h)");
}
$owner->query_safe('RESET ROLE');
is( $owner->query_safe(
		q{SELECT count(*) FROM pg_backend_memory_contexts WHERE name='UTL_HTTP request'}
	),
	'0',
	'repeated close releases request contexts');
$owner->quit;

my $cert = $node->basedir . '/server.crt';
my $key = $node->basedir . '/server.key';
$node->command_ok(
	[
		'openssl', 'req',
		'-x509', '-newkey',
		'rsa:2048', '-nodes',
		'-days', '1',
		'-subj', '/CN=localhost',
		'-addext', 'subjectAltName=DNS:localhost',
		'-keyout', $key,
		'-out', $cert
	],
	'creates local TLS fixture certificate');
my $tls = server('tls', $cert, $key);
sql("INSERT INTO sys.utl_http_host_acl VALUES(current_user::regrole,'localhost',$tls,NULL)"
);
fails(
	"SELECT utl_http.request('https://localhost:$tls/hello')",
	qr/HTTP transfer failed/,
	'HTTPS rejects an untrusted certificate', 1);
sql("UPDATE sys.utl_http_host_acl SET ca_file='$cert' WHERE host='localhost' AND port=$tls"
);
is( ora("SELECT encode(convert_to(utl_http.request('https://localhost:$tls/hello'),'UTF8'),'hex')"
	),
	'e4bda0e5a5bdefbc8c49766f727953514cf09f8c8d',
	'HTTPS succeeds with explicit trusted CA');
sql("INSERT INTO sys.utl_http_host_acl VALUES(current_user::regrole,'127.0.0.1',$tls,'$cert')"
);
fails(
	"SELECT utl_http.request('https://127.0.0.1:$tls/hello')",
	qr/HTTP transfer failed/,
	'HTTPS still checks the hostname with a trusted CA', 1);
$node->stop;
done_testing();
