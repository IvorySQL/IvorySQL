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

done_testing();
