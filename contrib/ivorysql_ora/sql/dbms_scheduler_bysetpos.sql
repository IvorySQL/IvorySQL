-- BYSETPOS selects from the complete frequency period, before start/after.
SET timezone TO 'UTC';
SET ivorysql.identifier_case_switch TO normal;
SET client_min_messages TO ERROR;
CREATE ROLE regress_scheduler_setpos SUPERUSER;
SET SESSION AUTHORIZATION regress_scheduler_setpos;

WITH cases(label, calendar, anchor, cutoff, expected) AS (VALUES
  ('last weekday', 'FREQ=MONTHLY;BYDAY=MON,TUE,WED,THU,FRI;BYSETPOS=-1',
   '2026-01-01 09:00:00+00:00', '2026-01-01 00:00:00+00:00', '2026-01-30 09:00:00+00:00'),
  ('next month', 'FREQ=MONTHLY;BYDAY=MON,TUE,WED,THU,FRI;BYSETPOS=-1',
   '2026-01-01 09:00:00+00:00', '2026-01-30 09:00:00+00:00', '2026-02-27 09:00:00+00:00'),
  ('positive positions', 'FREQ=MONTHLY;BYDAY=MON,TUE,FRI;BYSETPOS=1,3',
   '2004-01-01 00:00:00+00:00', '2004-01-02 00:00:00+00:00', '2004-01-06 00:00:00+00:00'),
  ('cutoff does not rerank', 'FREQ=MONTHLY;BYDAY=MON,TUE,FRI;BYSETPOS=1,3',
   '2004-01-01 00:00:00+00:00', '2004-01-15 00:00:00+00:00', '2004-02-02 00:00:00+00:00'),
  ('anchor does not rerank', 'FREQ=MONTHLY;BYDAY=MON,TUE,FRI;BYSETPOS=1,3',
   '2004-01-15 00:00:00+00:00', '2004-01-01 00:00:00+00:00', '2004-02-02 00:00:00+00:00'),
  ('interval skips months', 'FREQ=MONTHLY;INTERVAL=3;BYDAY=MON,TUE,WED,THU,FRI;BYSETPOS=-1',
   '2026-01-01 09:00:00+00:00', '2026-01-31 00:00:00+00:00', '2026-04-30 09:00:00+00:00'),
  ('time product', 'FREQ=MONTHLY;BYMONTHDAY=1,2;BYHOUR=9,17;BYMINUTE=0,30;BYSECOND=0,15;BYSETPOS=10',
   '2026-01-01 00:00:00+00:00', '2026-01-01 00:00:00+00:00', '2026-01-02 09:00:15+00:00'),
  ('last time not last date', 'FREQ=MONTHLY;BYDAY=FRI;BYHOUR=9,17;BYSETPOS=-1',
   '2026-01-01 00:00:00+00:00', '2026-01-01 00:00:00+00:00', '2026-01-30 17:00:00+00:00'),
  ('mixed positions are ordered', 'FREQ=MONTHLY;BYMONTHDAY=1,2,3;BYSETPOS=-1,2,1',
   '2026-01-01 00:00:00+00:00', '2026-01-01 00:00:00+00:00', '2026-01-02 00:00:00+00:00'),
  ('duplicates are a set', 'FREQ=MONTHLY;BYMONTHDAY=1,1,2;BYHOUR=9,9,17;BYSETPOS=2,2,-3',
   '2026-01-01 00:00:00+00:00', '2026-01-01 00:00:00+00:00', '2026-01-01 17:00:00+00:00'),
  ('year spans all selected months', 'FREQ=YEARLY;BYMONTH=1,3,6;BYDAY=MON,TUE,WED,THU,FRI;BYSETPOS=-1',
   '2026-01-01 09:00:00+00:00', '2026-01-01 00:00:00+00:00', '2026-06-30 09:00:00+00:00'),
  ('year positions cross months', 'FREQ=YEARLY;BYDATE=0101,0701;BYSETPOS=2',
   '2026-01-01 09:00:00+00:00', '2026-01-01 00:00:00+00:00', '2026-07-01 09:00:00+00:00'),
  ('year interval', 'FREQ=YEARLY;INTERVAL=2;BYDATE=0101,0701;BYSETPOS=2',
   '2026-01-01 09:00:00+00:00', '2026-12-31 00:00:00+00:00', '2028-07-01 09:00:00+00:00'),
  ('leap year', 'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=29;BYSETPOS=-1',
   '2026-01-01 09:00:00+00:00', '2026-01-01 00:00:00+00:00', '2028-02-29 09:00:00+00:00'),
  ('empty months skipped', 'FREQ=MONTHLY;BYMONTHDAY=31;BYSETPOS=1',
   '2026-01-01 09:00:00+00:00', '2026-02-01 00:00:00+00:00', '2026-03-31 09:00:00+00:00'),
  ('BYDATE intersection', 'FREQ=YEARLY;BYDATE=0101,0102,0702;BYMONTHDAY=2;BYSETPOS=2',
   '2026-01-01 09:00:00+00:00', '2026-01-01 00:00:00+00:00', '2026-07-02 09:00:00+00:00'),
  ('ordinal intersection', 'FREQ=MONTHLY;BYMONTHDAY=1,8,15,22,29;BYDAY=2MON;BYSETPOS=-1',
   '2026-01-01 09:00:00+00:00', '2026-06-01 00:00:00+00:00', '2026-06-08 09:00:00+00:00'),
  ('negative month days', 'FREQ=MONTHLY;BYMONTHDAY=-1,-2,-3;BYSETPOS=-2',
   '2026-01-01 09:00:00+00:00', '2026-02-01 00:00:00+00:00', '2026-02-27 09:00:00+00:00'),
  ('inherited components', 'FREQ=YEARLY;BYSETPOS=1',
   '2026-03-15 08:30:45+00:00', '2026-07-01 00:00:00+00:00', '2027-03-15 08:30:45+00:00'),
  ('exact anchor is allowed', 'FREQ=MONTHLY;BYMONTHDAY=15;BYSETPOS=1',
   '2026-01-15 09:00:00+00:00', '2026-01-15 08:59:59+00:00', '2026-01-15 09:00:00+00:00'),
  ('strict cutoff', 'FREQ=MONTHLY;BYMONTHDAY=15;BYSETPOS=1',
   '2026-01-15 09:00:00+00:00', '2026-01-15 09:00:00+00:00', '2026-02-15 09:00:00+00:00'),
  ('fractional anchor', 'FREQ=MONTHLY;BYMONTHDAY=15;BYSETPOS=1',
   '2026-01-15 09:00:00.5+00:00', '2026-01-01 00:00:00+00:00', '2026-02-15 09:00:00+00:00'),
  ('case whitespace and plus', ' bysetpos = +1 ; freq = monthly ; bymonthday = 2 ',
   '2026-01-01 09:00:00+00:00', '2026-01-01 00:00:00+00:00', '2026-01-02 09:00:00+00:00')
)
SELECT label, sys.ora_dbms_scheduler_evaluate_calendar_string(calendar,
  anchor::pg_catalog.timestamptz, cutoff::pg_catalog.timestamptz)
  IS NOT DISTINCT FROM expected::pg_catalog.timestamptz AS matches
FROM cases;

-- Independent enumeration oracle: 48 cutoffs spanning every month of a leap
-- year. Rank an explicitly generated timestamp set with SQL window functions.
WITH days AS (
  SELECT d + h * '1 hour'::pg_catalog.interval + m * '1 minute'::pg_catalog.interval AS candidate
  FROM generate_series('2028-01-01'::pg_catalog.timestamp,
    '2029-01-31'::pg_catalog.timestamp, '1 day'::pg_catalog.interval) d,
    (VALUES (9), (17)) hours(h), (VALUES (15), (45)) minutes(m)
  WHERE extract(isodow FROM d) <= 5
), ranked AS (
  SELECT candidate,
    row_number() OVER (PARTITION BY date_trunc('month', candidate) ORDER BY candidate) AS pos,
    count(*) OVER (PARTITION BY date_trunc('month', candidate)) AS n
  FROM days
), selected AS (
  SELECT candidate FROM ranked WHERE pos IN (1,3,67,n,n-6)
), probes AS (
  SELECT d + k * '1 day'::pg_catalog.interval AS cutoff
  FROM generate_series('2028-01-01'::pg_catalog.timestamp,
    '2028-12-01'::pg_catalog.timestamp, '1 month'::pg_catalog.interval) d,
    (VALUES (0), (10), (20), (29)) offsets(k)
)
SELECT count(*) AS checked, bool_and(
  sys.ora_dbms_scheduler_evaluate_calendar_string(
    'FREQ=MONTHLY;BYDAY=MON,TUE,WED,THU,FRI;BYHOUR=9,17;BYMINUTE=15,45;BYSECOND=0;BYSETPOS=1,3,67,-1,-7',
    '2028-01-01 00:00:00+00:00', cutoff::pg_catalog.timestamptz)
  = (SELECT min(candidate)::pg_catalog.timestamptz FROM selected WHERE candidate > cutoff)) AS matches
FROM probes;

-- Exhausted sets retain the evaluator's existing no-match error.
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYMONTHDAY=1;BYSETPOS=2,-2', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30;BYSETPOS=-1', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYDATE=20200101;BYSETPOS=1', '2026-01-01', '2026-01-01');

-- Large Cartesian product: 366 * 24 * 60 * 60 candidates in a leap year.
-- Both limits of BYSETPOS are legal; the evaluator need not build that set.
WITH rule AS (
  SELECT 'FREQ=YEARLY;BYMONTH=' || string_agg(n::text, ',') ||
    ';BYMONTHDAY=' || (SELECT string_agg(n::text, ',') FROM generate_series(1,31) n) ||
    ';BYHOUR=' || (SELECT string_agg(n::text, ',') FROM generate_series(0,23) n) ||
    ';BYMINUTE=' || (SELECT string_agg(n::text, ',') FROM generate_series(0,59) n) ||
    ';BYSECOND=' || (SELECT string_agg(n::text, ',') FROM generate_series(0,59) n) AS cal
  FROM generate_series(1,12) n
)
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(cal || ';BYSETPOS=9999',
    '2028-01-01 00:00:00+00:00', '2027-12-31 00:00:00+00:00') AS first_9999,
  sys.ora_dbms_scheduler_evaluate_calendar_string(cal || ';BYSETPOS=-9999',
    '2028-01-01 00:00:00+00:00', '2027-12-31 00:00:00+00:00') AS last_9999
FROM rule;

-- Transition periods sort and deduplicate actual timestamps.  This retains
-- the engine's existing session-timezone and gap/fold conversion policy.
SET timezone TO 'America/New_York';
WITH rule AS (
  SELECT 'FREQ=MONTHLY;BYDATE=20260308;BYHOUR=' ||
    (SELECT string_agg(n::text, ',') FROM generate_series(0,23) n) ||
    ';BYMINUTE=' || (SELECT string_agg(n::text, ',') FROM generate_series(0,59) n) ||
    ';BYSECOND=' || (SELECT string_agg(n::text, ',') FROM generate_series(0,59) n) AS cal
)
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(cal || ';BYSETPOS=9999',
    '2026-03-01 00:00:00-05:00', '2026-03-01 00:00:00-05:00') AS gap_first_9999,
  sys.ora_dbms_scheduler_evaluate_calendar_string(cal || ';BYSETPOS=-9999',
    '2026-03-01 00:00:00-05:00', '2026-03-01 00:00:00-05:00') AS gap_last_9999
FROM rule;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYMONTHDAY=8;BYHOUR=2,3;BYMINUTE=0,30;BYSETPOS=2',
  '2026-03-01 00:00:00-05:00', '2026-03-01 00:00:00-05:00') AS gap_duplicates;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYMONTHDAY=8;BYHOUR=2,3;BYMINUTE=0,30;BYSETPOS=-2',
  '2026-03-01 00:00:00-05:00', '2026-03-01 00:00:00-05:00') AS gap_negative;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYDATE=20260308;BYHOUR=1,2,3;BYMINUTE=30;BYSETPOS=3',
  '2026-03-01 00:00:00-05:00', '2026-03-01 00:00:00-05:00') AS gap_not_counted_twice;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=YEARLY;BYMONTH=3,11;BYMONTHDAY=1,8;BYHOUR=1,2,3;BYSETPOS=-2',
  '2026-01-01 00:00:00-05:00', '2026-01-01 00:00:00-05:00') AS fold_year;
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYMONTHDAY=1;BYHOUR=0,1,2;BYMINUTE=30;BYSETPOS=2',
  '2026-11-01 00:00:00-04:00', '2026-11-01 00:00:00-04:00') AS fold_selected;
SET timezone TO 'Australia/Lord_Howe';
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYMONTHDAY=4;BYHOUR=2;BYMINUTE=0,15,30,45;BYSETPOS=2',
  '2026-10-01 00:00:00+10:30', '2026-10-01 00:00:00+10:30') AS half_hour_gap;
SET timezone TO 'Pacific/Apia';
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string(
  'FREQ=MONTHLY;BYMONTHDAY=29,30,31;BYSETPOS=3',
  '2011-12-01 00:00:00-10:00', '2011-12-01 00:00:00-10:00') AS skipped_date;
SET timezone TO 'UTC';

-- Invalid positions, lists, duplicate clauses, and unsupported frequencies.
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=MONTHLY;BYSETPOS=0', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=MONTHLY;BYSETPOS=10000', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=MONTHLY;BYSETPOS=-10000', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=MONTHLY;BYSETPOS=21474836470', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=MONTHLY;BYSETPOS=one', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=MONTHLY;BYSETPOS=', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=MONTHLY;BYSETPOS=1,', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=MONTHLY;BYSETPOS=1,,2', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=MONTHLY;BYSETPOS=1;BYSETPOS=-1', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=DAILY;BYSETPOS=1', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=WEEKLY;BYSETPOS=1', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=HOURLY;BYSETPOS=1', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=MINUTELY;BYSETPOS=1', '2026-01-01', '2026-01-01');
SELECT sys.ora_dbms_scheduler_evaluate_calendar_string('FREQ=SECONDLY;BYSETPOS=1', '2026-01-01', '2026-01-01');

-- Both object-creation paths validate BYSETPOS. ENABLE computes the selected
-- timestamp, including jobs referencing a named schedule.
BEGIN
  dbms_scheduler.create_schedule('reg_setpos_schedule',
    start_date => TIMESTAMP '2199-01-01 09:00:00 +00:00',
    repeat_interval => 'FREQ=MONTHLY;BYDAY=MON,TUE,WED,THU,FRI;BYSETPOS=-1');
  dbms_scheduler.create_job('reg_setpos_job', job_type => 'PLSQL_BLOCK',
    job_action => 'BEGIN NULL; END;',
    start_date => TIMESTAMP '2199-01-01 09:00:00 +00:00',
    repeat_interval => 'FREQ=YEARLY;BYDATE=0101,0701;BYSETPOS=2', enabled => TRUE);
  dbms_scheduler.create_program('reg_setpos_program', 'PLSQL_BLOCK', 'BEGIN NULL; END;', enabled => TRUE);
  dbms_scheduler.create_job('reg_setpos_named', program_name => 'reg_setpos_program',
    schedule_name => 'reg_setpos_schedule', enabled => TRUE);
END;
/
SELECT job_name, enabled, next_run_date FROM sys.scheduler_jobs
WHERE job_name IN ('REG_SETPOS_JOB', 'REG_SETPOS_NAMED') ORDER BY job_name;
BEGIN
  dbms_scheduler.create_schedule('reg_setpos_invalid', repeat_interval => 'FREQ=MONTHLY;BYSETPOS=0');
END;
/
BEGIN
  dbms_scheduler.create_job('reg_setpos_invalid', job_type => 'PLSQL_BLOCK',
    job_action => 'BEGIN NULL; END;', repeat_interval => 'FREQ=DAILY;BYSETPOS=1');
END;
/
BEGIN
  dbms_scheduler.drop_job('reg_setpos_job');
  dbms_scheduler.drop_job('reg_setpos_named');
  dbms_scheduler.drop_program('reg_setpos_program');
  dbms_scheduler.drop_schedule('reg_setpos_schedule');
END;
/
RESET ivorysql.identifier_case_switch;
RESET timezone;
RESET SESSION AUTHORIZATION;
DROP ROLE regress_scheduler_setpos;
RESET client_min_messages;
