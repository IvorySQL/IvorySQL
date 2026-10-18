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

# Monthly inline and yearly named schedules execute a selected timestamp,
# survive restart, then advance to the next period rather than reranking the
# remaining timestamps in the current period.
use strict;
use warnings FATAL => 'all';

use PostgreSQL::Test::Cluster;
use PostgreSQL::Test::Utils;
use Test::More;

my $node = PostgreSQL::Test::Cluster->new('setpos');
$node->init;
$node->append_conf(
	'postgresql.conf', qq{
timezone = 'UTC'
ivorysql.scheduler = on
ivorysql.scheduler_databases = 'ivorysql'
ivorysql.scheduler_poll_interval = 1
});
$node->start;
my $db = 'ivorysql';

sub ora_sql
{
	my ($sql) = @_;
	return $node->safe_psql($db, $sql, connect_to_oraport => 1);
}

ora_sql('CREATE TABLE setpos_runs (kind varchar2(20))');

# The bounded-memory transition path may still enumerate a dense year. It
# must respond to cancellation instead of monopolizing a backend.
my ($stdout, $stderr);
my $rc = $node->psql(
	$db, q{
SET timezone = 'America/New_York';
SET statement_timeout = '100ms';
WITH rule AS (
  SELECT 'FREQ=YEARLY;BYMONTH=' || (SELECT string_agg(n::text, ',') FROM generate_series(1,12) n) ||
    ';BYMONTHDAY=' || (SELECT string_agg(n::text, ',') FROM generate_series(1,31) n) ||
    ';BYHOUR=' || (SELECT string_agg(n::text, ',') FROM generate_series(0,23) n) ||
    ';BYMINUTE=' || (SELECT string_agg(n::text, ',') FROM generate_series(0,59) n) ||
    ';BYSECOND=' || (SELECT string_agg(n::text, ',') FROM generate_series(0,59) n) AS cal
)
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(cal || ';BYSETPOS=-9999',
  '2028-01-01 00:00:00-05:00'::timestamptz, '2028-01-01 00:00:00-05:00'::timestamptz)
FROM rule;
},
	stdout => \$stdout,
	stderr => \$stderr);
is($rc, 3, 'dense transition evaluation can be cancelled');
like(
	$stderr,
	qr/canceling statement due to statement timeout/,
	'transition enumeration checks interrupts');
is($node->safe_psql($db, 'SELECT 1'),
	'1', 'server remains available after cancellation');

# Derive both time choices from a single future instant, including across
# minute/day boundaries. The second choice must not run in this period.
my $when = $node->safe_psql($db,
	q{SELECT to_char(clock_timestamp() + interval '15 seconds', 'YYYY-MM-DD HH24:MI:SS')}
);
my ($year, $month, $day, $hour, $minute, $second) =
  $when =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)$/;
die "unexpected timestamp: $when" unless defined $second;
my $other = ($second + 1) % 60;
my $position = $other < $second ? 2 : 1;
my $times =
  "BYHOUR=$hour;BYMINUTE=$minute;BYSECOND=$second,$other;BYSETPOS=$position";
my $monthly = "FREQ=MONTHLY;BYMONTHDAY=$day;$times";
my $yearly = "FREQ=YEARLY;BYDATE=$month$day;$times";

ora_sql(
	qq{
BEGIN
  dbms_scheduler.create_job('tap_setpos_month', job_type => 'PLSQL_BLOCK',
    job_action => 'BEGIN INSERT INTO setpos_runs VALUES (''monthly''); END;',
    start_date => TIMESTAMP '$when +00:00', repeat_interval => '$monthly', enabled => TRUE);
  dbms_scheduler.create_program('tap_setpos_program', 'PLSQL_BLOCK',
    'BEGIN INSERT INTO setpos_runs VALUES (''yearly''); END;', enabled => TRUE);
  dbms_scheduler.create_schedule('tap_setpos_schedule',
    start_date => TIMESTAMP '$when +00:00', repeat_interval => '$yearly');
  dbms_scheduler.create_job('tap_setpos_year', program_name => 'tap_setpos_program',
    schedule_name => 'tap_setpos_schedule', enabled => TRUE);
END;});

my $initial = $node->safe_psql(
	$db,
	qq{SELECT count(*) FROM sys.scheduler_jobs
       WHERE job_name IN ('TAP_SETPOS_MONTH', 'TAP_SETPOS_YEAR')
         AND next_run_date = '$when+00'::timestamptz AND enabled});
is($initial, '2', 'inline and named schedules select the requested instant');

$node->restart;
is( $node->safe_psql(
		$db,
		qq{SELECT count(*) FROM sys.scheduler_jobs
       WHERE job_name IN ('TAP_SETPOS_MONTH', 'TAP_SETPOS_YEAR')
         AND next_run_date = '$when+00'::timestamptz AND enabled}),
	'2',
	'selected run dates survive a server restart');

$node->poll_query_until(
	$db,
	q{SELECT count(*) = 2 FROM sys.scheduler_job_run_details
      WHERE job_name IN ('TAP_SETPOS_MONTH', 'TAP_SETPOS_YEAR') AND status = 's'}
) or die 'BYSETPOS jobs did not complete';
is( $node->safe_psql(
		$db, 'SELECT string_agg(kind, \',\' ORDER BY kind) FROM setpos_runs'),
	'monthly,yearly',
	'both selected jobs execute their actions in background workers');

is( $node->safe_psql(
		$db,
		q{SELECT count(*) FROM sys.scheduler_jobs
      WHERE job_name IN ('TAP_SETPOS_MONTH', 'TAP_SETPOS_YEAR')
        AND enabled AND run_count = 1 AND failure_count = 0
        AND next_run_date > clock_timestamp() + interval '20 days'}),
	'2',
	'after execution each job advances to a later frequency period');

is( $node->safe_psql(
		$db,
		q{SELECT count(*) FROM sys.scheduler_jobs j JOIN sys.scheduler_schedules s
        ON j.schedule_name = s.schedule_name AND j.job_owner = s.schedule_owner
      WHERE j.job_name = 'TAP_SETPOS_YEAR' AND s.repeat_interval LIKE '%BYSETPOS=%'}
	),
	'1',
	'the yearly job retains its named schedule with BYSETPOS');

$node->stop;
done_testing();
