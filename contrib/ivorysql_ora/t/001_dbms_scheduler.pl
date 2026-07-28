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
# End-to-end test of DBMS_SCHEDULER background job execution: the launcher
# and per-database scheduler workers, repeating and one-shot jobs, failure
# logging, DISABLE, and recovery after a server restart.

use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('scheduler');
$node->init;
# background scheduling is off by default; this test is all about it
$node->append_conf(
	'postgresql.conf', qq{
ivorysql_ora.scheduler = on
ivorysql_ora.scheduler_databases = 'ivorysql'
ivorysql_ora.scheduler_poll_interval = 1
ivorysql_ora.scheduler_job_timeout = 2s
ivorysql_ora.scheduler_max_failures = 2
});
$node->start;

my $db = 'ivorysql';

# Oracle-syntax statements go through the oracle listener port.
sub ora_sql
{
	my ($sql) = @_;
	return $node->safe_psql($db, $sql, connect_to_oraport => 1);
}

# the launcher is registered at shared_preload time and starts one
# database scheduler for the configured database
$node->poll_query_until($db,
	"SELECT count(*) > 0 FROM pg_stat_activity WHERE backend_type = 'ivorysql scheduler worker'"
) or die "database scheduler worker did not start";
ok(1, 'scheduler launcher and database worker started');

ora_sql(q{CREATE TABLE sched_tap_t (id int, note varchar2(100))});

# ---------------------------------------------------------------------
# a repeating job runs on its calendar and sees BG_JOB_ID/SCHEDULER_JOB
# ---------------------------------------------------------------------
ora_sql(q{
BEGIN
  dbms_scheduler.create_job(job_name => 'tap_repeat', job_type => 'PLSQL_BLOCK',
    job_action => 'BEGIN INSERT INTO sched_tap_t VALUES (1, ''bg=''||CASE WHEN SYS_CONTEXT(''USERENV'',''BG_JOB_ID'') IS NULL THEN ''unset'' ELSE ''set'' END||'' job=''||SYS_CONTEXT(''USERENV'',''SCHEDULER_JOB'')); END;',
    repeat_interval => 'FREQ=SECONDLY;INTERVAL=2',
    enabled => TRUE);
END;});

$node->poll_query_until($db,
	"SELECT count(*) >= 2 FROM sys.scheduler_job_run_details WHERE job_name = 'TAP_REPEAT' AND status = 's'"
) or die "repeating job did not run twice";
ok(1, 'repeating job ran at least twice in the background');

is( $node->safe_psql(
		$db,
		"SELECT DISTINCT note FROM sched_tap_t WHERE id = 1"),
	'bg=set job=TAP_REPEAT',
	'BG_JOB_ID and SCHEDULER_JOB are set inside a background job');

# run counts and state are maintained
my $state = $node->safe_psql($db,
	"SELECT enabled, state, run_count >= 2 FROM sys.scheduler_jobs WHERE job_name = 'TAP_REPEAT'"
);
is($state, 't|SCHEDULED|t', 'repeating job stays enabled and scheduled');

# ---------------------------------------------------------------------
# DISABLE stops future runs
# ---------------------------------------------------------------------
ora_sql(q{BEGIN dbms_scheduler.disable('tap_repeat'); END;});
my $count_after_disable = $node->safe_psql($db,
	"SELECT count(*) FROM sys.scheduler_job_run_details WHERE job_name = 'TAP_REPEAT'");
sleep(4);
is( $node->safe_psql(
		$db,
		"SELECT count(*) FROM sys.scheduler_job_run_details WHERE job_name = 'TAP_REPEAT'"),
	$count_after_disable,
	'disabled job produces no further runs');

# ---------------------------------------------------------------------
# one-shot job: runs once, then is disabled with its outcome recorded
# ---------------------------------------------------------------------
ora_sql(q{
BEGIN
  dbms_scheduler.create_job(job_name => 'tap_oneshot', job_type => 'PLSQL_BLOCK',
    job_action => 'BEGIN INSERT INTO sched_tap_t VALUES (2, ''oneshot''); END;',
    enabled => TRUE);
END;});

$node->poll_query_until($db,
	"SELECT state = 'SUCCEEDED' AND NOT enabled AND run_count = 1 FROM sys.scheduler_jobs WHERE job_name = 'TAP_ONESHOT'"
) or die "one-shot job did not complete";
ok(1, 'one-shot job ran exactly once and was disabled');

# ---------------------------------------------------------------------
# a failing job records status 'f' with the error message
# ---------------------------------------------------------------------
ora_sql(q{
BEGIN
  dbms_scheduler.create_job(job_name => 'tap_fail', job_type => 'PLSQL_BLOCK',
    job_action => 'DECLARE v NUMBER; BEGIN v := 1/0; END;',
    enabled => TRUE);
END;});

$node->poll_query_until($db,
	"SELECT count(*) = 1 FROM sys.scheduler_job_run_details WHERE job_name = 'TAP_FAIL' AND status = 'f'"
) or die "failing job did not record a failure";
is( $node->safe_psql(
		$db,
		"SELECT state, failure_count, (SELECT error_message FROM sys.scheduler_job_run_details WHERE job_name = 'TAP_FAIL' AND status = 'f') FROM sys.scheduler_jobs WHERE job_name = 'TAP_FAIL'"),
	'FAILED|1|division by zero',
	'failed job records state, failure count and error message');

# ---------------------------------------------------------------------
# a job running past scheduler_job_timeout is cancelled
# ---------------------------------------------------------------------
ora_sql(q{
BEGIN
  dbms_scheduler.create_job(job_name => 'tap_timeout', job_type => 'PLSQL_BLOCK',
    job_action => 'SELECT pg_sleep(60)',
    enabled => TRUE);
END;});

$node->poll_query_until($db,
	"SELECT count(*) = 1 FROM sys.scheduler_job_run_details WHERE job_name = 'TAP_TIMEOUT' AND status = 'f' AND error_message LIKE '%statement timeout%'"
) or die "long-running job was not cancelled";
ok(1, 'a job running past scheduler_job_timeout is cancelled');

is( $node->safe_psql(
		$db,
		"SELECT state, failure_count, run_duration < '30 seconds'::pg_catalog.interval FROM sys.scheduler_jobs j JOIN sys.scheduler_job_run_details d USING (job_name) WHERE job_name = 'TAP_TIMEOUT'"),
	'FAILED|1|t',
	'cancelled job is recorded as failed and did not run to completion');

# ---------------------------------------------------------------------
# a repeating job is disabled once it hits scheduler_max_failures
# ---------------------------------------------------------------------
ora_sql(q{
BEGIN
  dbms_scheduler.create_job(job_name => 'tap_maxfail', job_type => 'PLSQL_BLOCK',
    job_action => 'DECLARE v NUMBER; BEGIN v := 1/0; END;',
    repeat_interval => 'FREQ=SECONDLY;INTERVAL=2',
    enabled => TRUE);
END;});

$node->poll_query_until($db,
	"SELECT NOT enabled AND state = 'FAILED' AND failure_count = 2 AND next_run_date IS NULL FROM sys.scheduler_jobs WHERE job_name = 'TAP_MAXFAIL'"
) or die "repeatedly failing job was not disabled";
ok(1, 'a repeating job is disabled after scheduler_max_failures failures');

# ENABLE clears the count.  Read it back in the same transaction as the ENABLE,
# so the scheduler cannot slip another failed run in between.
ora_sql(q{
BEGIN
  dbms_scheduler.enable('tap_maxfail');
  INSERT INTO sched_tap_t SELECT 5, 'fc=' || failure_count
    FROM sys.scheduler_jobs WHERE job_name = 'TAP_MAXFAIL';
  dbms_scheduler.disable('tap_maxfail');
END;});
is($node->safe_psql($db, "SELECT note FROM sched_tap_t WHERE id = 5"),
	'fc=0', 'ENABLE clears the failure count');

# ---------------------------------------------------------------------
# STOP_JOB cancels a running job, using the worker pid on its log row
# ---------------------------------------------------------------------
# raise the timeout first, so the job survives long enough to be stopped
$node->safe_psql($db,
	"ALTER SYSTEM SET ivorysql_ora.scheduler_job_timeout = '5min'");
$node->reload;
$node->poll_query_until($db,
	"SELECT setting = '300000' FROM pg_settings WHERE name = 'ivorysql_ora.scheduler_job_timeout'"
) or die "raised timeout did not take effect";

ora_sql(q{
BEGIN
  dbms_scheduler.create_job(job_name => 'tap_stop', job_type => 'PLSQL_BLOCK',
    job_action => 'SELECT pg_sleep(300)',
    enabled => TRUE);
END;});

$node->poll_query_until($db,
	"SELECT count(*) = 1 FROM sys.scheduler_job_run_details WHERE job_name = 'TAP_STOP' AND status = 'r' AND worker_pid IS NOT NULL"
) or die "running job did not publish its worker pid";
ok(1, 'a running job publishes its worker pid on the log row');

ora_sql(q{BEGIN dbms_scheduler.stop_job('tap_stop'); END;});

$node->poll_query_until($db,
	"SELECT count(*) = 1 FROM sys.scheduler_job_run_details WHERE job_name = 'TAP_STOP' AND status = 'f'"
) or die "STOP_JOB did not stop the job";
ok(1, 'STOP_JOB cancels the running job');

is( $node->safe_psql(
		$db,
		"SELECT state, failure_count FROM sys.scheduler_jobs WHERE job_name = 'TAP_STOP'"),
	'FAILED|1',
	'a stopped job is recorded as a failed run');

# ---------------------------------------------------------------------
# STORED_PROCEDURE job with program arguments runs in the background
# ---------------------------------------------------------------------
ora_sql(q{
CREATE OR REPLACE PROCEDURE sched_tap_proc(x NUMBER, y VARCHAR2) IS
BEGIN
  INSERT INTO sched_tap_t VALUES (x, y);
END;});
ora_sql(q{
BEGIN
  dbms_scheduler.create_program('tap_prog', 'STORED_PROCEDURE', 'sched_tap_proc', 2);
  dbms_scheduler.define_program_argument(program_name => 'tap_prog',
      argument_position => 1, argument_name => 'x', argument_type => 'NUMBER');
  dbms_scheduler.define_program_argument(program_name => 'tap_prog',
      argument_position => 2, argument_name => 'y', argument_type => 'VARCHAR2',
      default_value => 'prog-default');
  dbms_scheduler.enable('tap_prog');
  dbms_scheduler.create_schedule('tap_sched', repeat_interval => 'FREQ=SECONDLY;INTERVAL=2');
  dbms_scheduler.create_job(job_name => 'tap_named', program_name => 'tap_prog',
      schedule_name => 'tap_sched');
  dbms_scheduler.set_job_argument_value('tap_named', 1, '3');
  dbms_scheduler.enable('tap_named');
END;});

$node->poll_query_until($db,
	"SELECT count(*) > 0 FROM sched_tap_t WHERE id = 3 AND note = 'prog-default'"
) or die "named-program job did not run";
ok(1, 'named-program job runs with job arguments and program defaults');
ora_sql(q{BEGIN dbms_scheduler.disable('tap_named'); END;});

# ---------------------------------------------------------------------
# scheduling survives a server restart; interrupted 'r' rows are closed
# ---------------------------------------------------------------------
ora_sql(q{
BEGIN
  dbms_scheduler.create_job(job_name => 'tap_restart', job_type => 'PLSQL_BLOCK',
    job_action => 'BEGIN INSERT INTO sched_tap_t VALUES (4, ''after-restart''); END;',
    repeat_interval => 'FREQ=SECONDLY;INTERVAL=2',
    enabled => TRUE);
END;});
$node->restart;

$node->poll_query_until($db,
	"SELECT count(*) >= 1 FROM sched_tap_t WHERE id = 4"
) or die "job did not run after restart";
ok(1, 'background scheduling resumes after a restart');

is( $node->safe_psql(
		$db,
		"SELECT count(*) FROM sys.scheduler_job_run_details WHERE status = 'r' AND log_date < (SELECT pg_postmaster_start_time())"),
	'0',
	'no interrupted running-state log rows survive a restart');

ora_sql(q{BEGIN dbms_scheduler.disable('tap_restart'); END;});

# ---------------------------------------------------------------------
# a job whose stored calendar cannot be parsed is taken out on its own,
# without killing the database scheduler or the jobs queued behind it
# ---------------------------------------------------------------------
ora_sql(q{
BEGIN
  dbms_scheduler.create_job(job_name => 'tap_badcal', job_type => 'PLSQL_BLOCK',
    job_action => 'BEGIN NULL; END;',
    repeat_interval => 'FREQ=SECONDLY;INTERVAL=2',
    enabled => TRUE);
  dbms_scheduler.create_job(job_name => 'tap_survivor', job_type => 'PLSQL_BLOCK',
    job_action => 'BEGIN NULL; END;',
    repeat_interval => 'FREQ=SECONDLY;INTERVAL=2',
    enabled => TRUE);
END;});

# CREATE_JOB validates the calendar, so a bad one can only be stored by writing
# it directly.  The back-dated next_run_date also puts this job at the head of
# the claim query's ORDER BY, ahead of tap_survivor.
$node->safe_psql(
	$db, q{
UPDATE sys.scheduler_jobs
   SET repeat_interval = 'FREQ=NOSUCHTHING',
       next_run_date = now() - interval '1 hour'
 WHERE job_name = 'TAP_BADCAL'});

$node->poll_query_until($db,
	"SELECT NOT enabled AND state = 'DISABLED' AND next_run_date IS NULL FROM sys.scheduler_jobs WHERE job_name = 'TAP_BADCAL'"
) or die "job with an unparsable calendar was not disabled";
ok(1, 'a job whose calendar cannot be parsed is disabled');

# The scheduler has to still be alive, and the job that sorted behind the
# broken one has to still be claimed rather than rolled back along with it.
my $survived = $node->safe_psql($db,
	"SELECT count(*) FROM sys.scheduler_job_run_details WHERE job_name = 'TAP_SURVIVOR' AND status = 's'"
);
$node->poll_query_until($db,
	"SELECT count(*) > $survived FROM sys.scheduler_job_run_details WHERE job_name = 'TAP_SURVIVOR' AND status = 's'"
) or die "database scheduler stopped claiming other jobs";
ok(1, 'the database scheduler keeps running the remaining jobs');

ora_sql(q{BEGIN dbms_scheduler.disable('tap_survivor'); END;});

# ---------------------------------------------------------------------
# a database scheduler that stops on its own is reported once and left
# stopped; reloading the configuration retries it
# ---------------------------------------------------------------------
my $logpos = -s $node->logfile;

# a database that does not exist yet: the worker starts, fails to connect and
# is gone, which is what the launcher has to notice
$node->safe_psql($db,
	"ALTER SYSTEM SET ivorysql_ora.scheduler_databases = 'ivorysql,sched_late'"
);
$node->reload;

$node->wait_for_log(qr/scheduler for database "sched_late" stopped; not restarting it/,
	$logpos)
  or die "launcher did not report the stopped scheduler";
ok(1, 'a database scheduler that stops on its own is reported');

# The launcher cycles every 10s, so this covers several cycles.  Any retry
# would log the same line again.
sleep 25;
my $reports = () = (PostgreSQL::Test::Utils::slurp_file($node->logfile, $logpos) =~
	  /scheduler for database "sched_late" stopped; not restarting it/g);
is($reports, 1, 'the stopped scheduler is not restarted, and reported only once');

# creating the database is not enough on its own - the retry needs a reload
$node->safe_psql($db, 'CREATE DATABASE sched_late');
$logpos = -s $node->logfile;
$node->reload;

$node->wait_for_log(qr/ivorysql scheduler started for database "sched_late"/, $logpos)
  or die "reload did not retry the database given up on";
ok(1, 'reloading the configuration retries a database given up on');

done_testing();
