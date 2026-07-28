--
-- dbms_scheduler.sql
--
-- tests for the DBMS_SCHEDULER package (EDB-parity subset):
--   CREATE_JOB (2 overloads), CREATE_PROGRAM, CREATE_SCHEDULE,
--   DEFINE_PROGRAM_ARGUMENT (2), DISABLE, DROP_JOB, DROP_PROGRAM,
--   DROP_PROGRAM_ARGUMENT (2), DROP_SCHEDULE, ENABLE,
--   EVALUATE_CALENDAR_STRING, RUN_JOB, SET_JOB_ARGUMENT_VALUE (2)
-- plus the USER_/DBA_SCHEDULER_* dictionary views.
--
-- Background execution is exercised by the TAP test (t/001_dbms_scheduler.pl);
-- everything here is synchronous and deterministic.  Jobs that get enabled
-- use start dates far in the future so the background scheduler (if one is
-- attached to this database) never picks them up.
--

SET timezone TO 'UTC';

-- Run under a fixed role so that object owners embedded in error messages
-- are stable regardless of the OS/bootstrap user running the test.  A
-- superuser role is needed because the test later creates sub-users and
-- switches session authorization between them.
CREATE ROLE regress_dbms_scheduler SUPERUSER;
SET SESSION AUTHORIZATION regress_dbms_scheduler;

--
-- calendar syntax: EVALUATE_CALENDAR_STRING
-- (fixed anchor and probe dates make the results deterministic)
--
-- 2026-01-01 is a Thursday; 2026-07-01 is a Wednesday.
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=DAILY;BYHOUR=9;BYMINUTE=30',
  '2026-01-01 00:00:00+00', '2026-07-01 12:00:00+00') AS daily_930;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=DAILY;INTERVAL=3',
  '2026-01-01 08:30:45+00', '2026-07-01 00:00:00+00') AS every3days_inherits_time;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=WEEKLY;BYDAY=MON,WED,FRI;BYHOUR=6;BYMINUTE=0;BYSECOND=0',
  '2026-01-05 00:00:00+00', '2026-07-01 12:00:00+00') AS weekly_mwf;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYMONTHDAY=31;BYHOUR=12;BYMINUTE=0;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-01-31 13:00:00+00') AS monthly_31st_skips_feb;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYMONTHDAY=-1;BYHOUR=23;BYMINUTE=0;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-02-01 00:00:00+00') AS monthly_last_day;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYDAY=2FRI;BYHOUR=10;BYMINUTE=0;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00') AS second_friday;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYDAY=-1SUN;BYHOUR=10;BYMINUTE=0;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00') AS last_sunday;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYMONTH=FEB;BYMONTHDAY=29;BYHOUR=0;BYMINUTE=0;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00') AS next_feb29_leap;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=HOURLY;INTERVAL=6',
  '2026-01-01 01:15:00+00', '2026-07-01 03:00:00+00') AS hourly6;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MINUTELY;INTERVAL=30',
  '2026-01-01 00:05:00+00', '2026-07-01 00:20:00+00') AS minutely30;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=SECONDLY;INTERVAL=15',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:05+00') AS secondly15;
-- lower case and embedded blanks are accepted
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  ' freq = daily ; byhour = 7 ; byminute = 0 ; bysecond = 0 ',
  '2026-01-01 00:00:00+00', '2026-07-01 12:00:00+00') AS case_blank_insensitive;

-- BYDATE: MMDD repeats every year, YYYYMMDD pins one absolute date
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYDATE=0101;BYHOUR=0;BYMINUTE=0;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00') AS bydate_mmdd;
-- a second date in another month must be reached even without BYMONTH
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYDATE=0101,0701;BYHOUR=2;BYMINUTE=0;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-03-01 00:00:00+00') AS bydate_two_months;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYDATE=20270315;BYHOUR=9;BYMINUTE=30;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00') AS bydate_absolute;
-- 0229 is accepted and simply skips non-leap years
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=DAILY;BYDATE=0229;BYHOUR=0;BYMINUTE=0;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00') AS bydate_leap_day;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYDATE=0115;BYHOUR=8;BYMINUTE=0;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00') AS bydate_monthly;
-- BY clauses intersect: only 0102 also satisfies BYMONTHDAY=2
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYDATE=0101,0102;BYMONTHDAY=2;BYHOUR=0;BYMINUTE=0;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00') AS bydate_intersects;

-- BYMONTH also accepts the numeric form
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;BYHOUR=0;BYMINUTE=0;BYSECOND=0',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00') AS bymonth_numeric;

-- BYDAY also accepts the numeric form, 1 = Monday .. 7 = Sunday
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=WEEKLY;BYDAY=1;BYHOUR=6;BYMINUTE=0;BYSECOND=0',
  '2026-01-05 00:00:00+00', '2026-07-01 00:00:00+00') AS byday_numeric_monday;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=WEEKLY;BYDAY=7;BYHOUR=6;BYMINUTE=0;BYSECOND=0',
  '2026-01-05 00:00:00+00', '2026-07-01 00:00:00+00') AS byday_numeric_sunday;

-- calendar errors
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'BYHOUR=9', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=FORTNIGHTLY', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=DAILY;INTERVAL=0', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=DAILY;INTERVAL=100', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=DAILY;BYHOUR=24', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=WEEKLY;BYDAY=XYZ', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=DAILY;BYHOUR=1;BYHOUR=2', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=DAILY;BYSETPOS=1', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=WEEKLY;BYDAY=2FRI', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=WEEKLY;BYDAY=8', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
-- BYDATE errors
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYDATE=123', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYDATE=1301', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYDATE=0132', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYDATE=20260230', '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYDATE=0101;BYDATE=0202',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
-- pattern that never yields a date
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYMONTH=FEB;BYMONTHDAY=30',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');
-- an absolute BYDATE entirely in the past yields nothing either
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYDATE=20200101',
  '2026-01-01 00:00:00+00', '2026-07-01 00:00:00+00');

-- package-level OUT parameter form
DECLARE
  next_d TIMESTAMP WITH TIME ZONE;
BEGIN
  dbms_scheduler.evaluate_calendar_string('FREQ=DAILY;BYHOUR=9;BYMINUTE=30;BYSECOND=0',
     TIMESTAMP '2026-01-01 00:00:00 +00:00', TIMESTAMP '2026-07-01 12:00:00 +00:00', next_d);
  RAISE NOTICE 'next: %', next_d;
END;
/

--
-- test fixtures
--
CREATE TABLE sched_reg_t (id int, note varchar2(200));
CREATE OR REPLACE PROCEDURE sched_reg_proc(x NUMBER, y VARCHAR2) IS
BEGIN
  INSERT INTO sched_reg_t VALUES (x, y);
END;
/

--
-- CREATE_PROGRAM / DEFINE_PROGRAM_ARGUMENT / DROP_PROGRAM_ARGUMENT
--
BEGIN
  dbms_scheduler.create_program('reg_prog', 'STORED_PROCEDURE', 'sched_reg_proc',
                                2, FALSE, 'regression test program');
END;
/
-- duplicate name
BEGIN
  dbms_scheduler.create_program('reg_prog', 'PLSQL_BLOCK', 'BEGIN NULL; END;');
END;
/
-- unsupported program type
BEGIN
  dbms_scheduler.create_program('reg_prog2', 'EXECUTABLE', '/bin/true');
END;
/
-- PLSQL_BLOCK program cannot take arguments
BEGIN
  dbms_scheduler.create_program('reg_prog2', 'PLSQL_BLOCK', 'BEGIN NULL; END;',
                                number_of_arguments => 1);
END;
/
-- cannot enable while arguments are undefined
BEGIN
  dbms_scheduler.enable('reg_prog');
END;
/
-- argument definitions (overload without and with default_value)
BEGIN
  dbms_scheduler.define_program_argument(program_name => 'reg_prog',
      argument_position => 1, argument_name => 'x', argument_type => 'NUMBER');
  dbms_scheduler.define_program_argument(program_name => 'reg_prog',
      argument_position => 2, argument_name => 'y', argument_type => 'VARCHAR2',
      default_value => 'y-default');
END;
/
-- argument position out of range
BEGIN
  dbms_scheduler.define_program_argument(program_name => 'reg_prog',
      argument_position => 3, argument_type => 'NUMBER');
END;
/
-- OUT arguments are not supported
BEGIN
  dbms_scheduler.define_program_argument(program_name => 'reg_prog',
      argument_position => 1, argument_type => 'NUMBER', out_argument => TRUE);
END;
/
BEGIN
  dbms_scheduler.enable('reg_prog');
END;
/
SELECT program_name, program_type, program_action, number_of_arguments, enabled
  FROM user_scheduler_programs ORDER BY program_name;
SELECT program_name, argument_position, argument_name, argument_type, default_value
  FROM user_scheduler_program_args ORDER BY argument_position;

-- drop argument by position and by name; errors on unknown ones
BEGIN
  dbms_scheduler.drop_program_argument('reg_prog', 1);
END;
/
BEGIN
  dbms_scheduler.drop_program_argument('reg_prog', 1);
END;
/
BEGIN
  dbms_scheduler.drop_program_argument('reg_prog', 'y');
END;
/
BEGIN
  dbms_scheduler.drop_program_argument('reg_prog', 'nosucharg');
END;
/
SELECT count(*) AS remaining_args FROM user_scheduler_program_args;
-- put them back for later job tests
BEGIN
  dbms_scheduler.define_program_argument(program_name => 'reg_prog',
      argument_position => 1, argument_name => 'x', argument_type => 'NUMBER');
  dbms_scheduler.define_program_argument(program_name => 'reg_prog',
      argument_position => 2, argument_name => 'y', argument_type => 'VARCHAR2',
      default_value => 'y-default');
END;
/

--
-- CREATE_SCHEDULE / DROP_SCHEDULE
--
BEGIN
  dbms_scheduler.create_schedule('reg_sched',
      start_date => TIMESTAMP '2199-01-01 00:00:00 +00:00',
      repeat_interval => 'FREQ=DAILY;BYHOUR=3;BYMINUTE=0;BYSECOND=0');
END;
/
-- at least one of start_date / repeat_interval is required
BEGIN
  dbms_scheduler.create_schedule('reg_sched2');
END;
/
-- calendar syntax is validated at creation
BEGIN
  dbms_scheduler.create_schedule('reg_sched2', repeat_interval => 'FREQ=BROKEN');
END;
/
-- end_date must be after start_date
BEGIN
  dbms_scheduler.create_schedule('reg_sched2',
      start_date => TIMESTAMP '2199-01-02 00:00:00 +00:00',
      end_date   => TIMESTAMP '2199-01-01 00:00:00 +00:00');
END;
/
-- BYDATE is accepted on the CREATE_SCHEDULE path too
BEGIN
  dbms_scheduler.create_schedule('reg_sched_bydate',
      start_date => TIMESTAMP '2199-01-01 00:00:00 +00:00',
      repeat_interval => 'FREQ=YEARLY;BYDATE=0101,0701;BYHOUR=4;BYMINUTE=0;BYSECOND=0');
END;
/
SELECT schedule_name, repeat_interval FROM user_scheduler_schedules ORDER BY schedule_name;
BEGIN
  dbms_scheduler.drop_schedule('reg_sched_bydate');
END;
/

--
-- CREATE_JOB (both overloads)
--
BEGIN
  dbms_scheduler.create_job(job_name => 'reg_job_inline', job_type => 'PLSQL_BLOCK',
      job_action => 'BEGIN INSERT INTO sched_reg_t VALUES (1, ''inline''); END;');
END;
/
-- jobs, programs and schedules share a namespace
BEGIN
  dbms_scheduler.create_job(job_name => 'reg_prog', job_type => 'PLSQL_BLOCK',
      job_action => 'BEGIN NULL; END;');
END;
/
-- PLSQL_BLOCK job cannot take arguments
BEGIN
  dbms_scheduler.create_job(job_name => 'reg_job_bad', job_type => 'PLSQL_BLOCK',
      job_action => 'BEGIN NULL; END;', number_of_arguments => 2);
END;
/
-- unsupported job type
BEGIN
  dbms_scheduler.create_job(job_name => 'reg_job_bad', job_type => 'CHAIN',
      job_action => 'c1');
END;
/
-- named-program job; job_class/auto_drop/comments are accepted
BEGIN
  dbms_scheduler.create_job(job_name => 'reg_job_named', program_name => 'reg_prog',
      schedule_name => 'reg_sched', job_class => 'SOME_CLASS',
      auto_drop => FALSE, comments => 'named job');
END;
/
-- referencing a missing program
BEGIN
  dbms_scheduler.create_job(job_name => 'reg_job_bad', program_name => 'no_prog',
      schedule_name => 'reg_sched');
END;
/
SELECT job_name, job_type, program_name, schedule_name, enabled, state
  FROM user_scheduler_jobs ORDER BY job_name;

--
-- SET_JOB_ARGUMENT_VALUE (by position and by name)
--
BEGIN
  dbms_scheduler.set_job_argument_value('reg_job_named', 1, '11');
END;
/
BEGIN
  dbms_scheduler.set_job_argument_value('reg_job_named', 'y', 'y-set');
END;
/
-- out of range / unknown name / job without named arguments
BEGIN
  dbms_scheduler.set_job_argument_value('reg_job_named', 3, 'x');
END;
/
BEGIN
  dbms_scheduler.set_job_argument_value('reg_job_named', 'nosucharg', 'x');
END;
/
BEGIN
  dbms_scheduler.set_job_argument_value('reg_job_inline', 'y', 'x');
END;
/
SELECT job_name, argument_position, value FROM user_scheduler_job_args
  ORDER BY argument_position;

--
-- ENABLE / DISABLE
--
-- schedules cannot be enabled or disabled
BEGIN
  dbms_scheduler.enable('reg_sched');
END;
/
BEGIN
  dbms_scheduler.disable('reg_sched');
END;
/
-- unknown object
BEGIN
  dbms_scheduler.enable('no_such_object');
END;
/
-- commit_semantics values are validated (and otherwise ignored)
BEGIN
  dbms_scheduler.enable('reg_job_named', commit_semantics => 'WHENEVER');
END;
/
-- Enabling a job warns when it will not run automatically, which depends on
-- ivorysql_ora.scheduler and ivorysql_ora.scheduler_databases in the instance
-- under test.  Silence it so the expected output is stable either way.
SET client_min_messages TO error;
BEGIN
  dbms_scheduler.enable('reg_job_named', commit_semantics => 'TRANSACTIONAL');
END;
/
RESET client_min_messages;
SELECT job_name, enabled, state FROM user_scheduler_jobs
  WHERE job_name = 'REG_JOB_NAMED';
BEGIN
  dbms_scheduler.disable('reg_job_named', force => TRUE,
                         commit_semantics => 'ABSORB_ERRORS');
END;
/
SELECT job_name, enabled, state FROM user_scheduler_jobs
  WHERE job_name = 'REG_JOB_NAMED';
-- enabling an inline job whose argument has neither value nor default
BEGIN
  dbms_scheduler.create_job(job_name => 'reg_job_args', job_type => 'STORED_PROCEDURE',
      job_action => 'sched_reg_proc', number_of_arguments => 2,
      start_date => TIMESTAMP '2199-01-01 00:00:00 +00:00');
END;
/
BEGIN
  dbms_scheduler.enable('reg_job_args');
END;
/

--
-- RUN_JOB (current session)
--
BEGIN
  dbms_scheduler.run_job('reg_job_inline');
END;
/
-- program defaults vs job argument overrides
BEGIN
  dbms_scheduler.set_job_argument_value('reg_job_named', 1, '21');
  dbms_scheduler.run_job('reg_job_named');
END;
/
SELECT id, note FROM sched_reg_t ORDER BY id;
-- FG_JOB_ID and SCHEDULER_JOB are visible inside the running job
BEGIN
  dbms_scheduler.create_job(job_name => 'reg_job_ctx', job_type => 'PLSQL_BLOCK',
      job_action => 'BEGIN INSERT INTO sched_reg_t VALUES (90, ''fg=''||CASE WHEN SYS_CONTEXT(''USERENV'',''FG_JOB_ID'') IS NULL THEN ''unset'' ELSE ''set'' END||'' job=''||SYS_CONTEXT(''USERENV'',''SCHEDULER_JOB'')); END;');
  dbms_scheduler.run_job('reg_job_ctx');
END;
/
SELECT note FROM sched_reg_t WHERE id = 90;
-- outside of a job both are NULL
SELECT SYS_CONTEXT('USERENV','FG_JOB_ID') IS NULL AS fg_null,
       SYS_CONTEXT('USERENV','BG_JOB_ID') IS NULL AS bg_null,
       SYS_CONTEXT('USERENV','SCHEDULER_JOB') IS NULL AS job_null;
-- a failing job surfaces its error to the caller
BEGIN
  dbms_scheduler.create_job(job_name => 'reg_job_fail', job_type => 'PLSQL_BLOCK',
      job_action => 'DECLARE v NUMBER; BEGIN v := 1/0; END;');
END;
/
BEGIN
  dbms_scheduler.run_job('reg_job_fail');
END;
/
-- only the current session mode is supported
BEGIN
  dbms_scheduler.run_job('reg_job_inline', use_current_session => FALSE);
END;
/
SELECT job_name, state, run_count FROM user_scheduler_jobs
  WHERE job_name IN ('REG_JOB_INLINE', 'REG_JOB_NAMED') ORDER BY job_name;
SELECT job_name, status FROM user_scheduler_job_run_details
  WHERE job_name IN ('REG_JOB_INLINE', 'REG_JOB_NAMED', 'REG_JOB_CTX')
  ORDER BY log_id;

--
-- quoted identifiers keep their case; unquoted ones are upper-cased
--
BEGIN
  dbms_scheduler.create_job(job_name => '"lower_job"', job_type => 'PLSQL_BLOCK',
      job_action => 'BEGIN NULL; END;');
END;
/
SELECT job_name FROM user_scheduler_jobs WHERE job_name = 'lower_job';
BEGIN
  dbms_scheduler.drop_job('"lower_job"');
END;
/

--
-- ownership and dictionary views
--
CREATE USER sched_regress_u1;
CREATE USER sched_regress_u2;
SET SESSION AUTHORIZATION sched_regress_u1;
BEGIN
  dbms_scheduler.create_job(job_name => 'u1_job', job_type => 'PLSQL_BLOCK',
      job_action => 'BEGIN NULL; END;');
END;
/
SELECT job_name, state FROM user_scheduler_jobs;
SET SESSION AUTHORIZATION sched_regress_u2;
-- u2 sees nothing and cannot touch u1's job or the base tables
SELECT count(*) AS visible FROM user_scheduler_jobs;
BEGIN
  dbms_scheduler.drop_job('sched_regress_u1.u1_job');
END;
/
SELECT count(*) FROM sys.scheduler_jobs;
SELECT count(*) FROM sys.dba_scheduler_jobs;
-- back to the fixed test owner (not RESET, which would revert to the
-- environment-dependent authenticated user)
SET SESSION AUTHORIZATION regress_dbms_scheduler;
-- the superuser sees and can drop everything
SELECT owner, job_name FROM dba_scheduler_jobs WHERE job_name = 'U1_JOB';
BEGIN
  dbms_scheduler.drop_job('sched_regress_u1.u1_job');
END;
/

--
-- DROP_PROGRAM / DROP_SCHEDULE (force semantics) and DROP_JOB
--
BEGIN
  dbms_scheduler.drop_program('reg_prog');
END;
/
BEGIN
  dbms_scheduler.drop_program('reg_prog', force => TRUE);
END;
/
-- force-dropping disabled the referencing job
SELECT job_name, enabled, state FROM user_scheduler_jobs
  WHERE job_name = 'REG_JOB_NAMED';
BEGIN
  dbms_scheduler.drop_schedule('reg_sched', force => TRUE);
END;
/
BEGIN
  dbms_scheduler.drop_job('no_such_job');
END;
/
BEGIN
  dbms_scheduler.drop_job('reg_job_named', force => TRUE, defer => TRUE);
END;
/
BEGIN
  dbms_scheduler.drop_job('reg_job_inline');
  dbms_scheduler.drop_job('reg_job_args');
  dbms_scheduler.drop_job('reg_job_ctx');
  dbms_scheduler.drop_job('reg_job_fail');
END;
/
-- job argument rows went with their jobs; run log rows are retained
SELECT count(*) AS jobs, (SELECT count(*) FROM user_scheduler_job_args) AS args
  FROM user_scheduler_jobs;
SELECT count(*) > 0 AS log_retained FROM user_scheduler_job_run_details;

-- cleanup
RESET SESSION AUTHORIZATION;
DROP USER sched_regress_u1;
DROP USER sched_regress_u2;
DROP TABLE sched_reg_t;
DROP PROCEDURE sched_reg_proc;
DELETE FROM sys.scheduler_job_run_details;
DROP ROLE regress_dbms_scheduler;
