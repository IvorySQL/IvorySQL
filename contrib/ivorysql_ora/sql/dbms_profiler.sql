--
-- DBMS_PROFILER
--
-- Regression tests for Oracle-compatible DBMS_PROFILER package:
--   - Package constants
--   - GET_VERSION
--   - START_PROFILER / STOP_PROFILER / PAUSE_PROFILER / RESUME_PROFILER
--   - FLUSH_DATA
--   - Repository table entries verification
--   - State error transitions (double start, stop while stopped, pause while stopped)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Package constants
SELECT dbms_profiler.success;
SELECT dbms_profiler.error_param;
SELECT dbms_profiler.error_io;
SELECT dbms_profiler.error_version;
SELECT dbms_profiler.major_version;
SELECT dbms_profiler.minor_version;

-- GET_VERSION test
DO $$
DECLARE
    maj NUMBER;
    min NUMBER;
BEGIN
    dbms_profiler.get_version(maj, min);
    RAISE NOTICE 'DBMS_PROFILER version: %.%', maj, min;
END;
$$;

-- Normal profiler lifecycle
SELECT dbms_profiler.start_profiler('test_run_1', 'unit test comment');

-- Pause and resume
SELECT dbms_profiler.pause_profiler();
SELECT dbms_profiler.resume_profiler();

-- Flush data
SELECT dbms_profiler.flush_data();

-- Stop profiler
SELECT dbms_profiler.stop_profiler();

-- Verify repository tables contain the run record
SELECT run_comment, run_comment1, run_system_info, run_total_time >= 0 AS valid_time
  FROM sys.plsql_profiler_runs
 WHERE run_comment = 'test_run_1';

-- State machine error handling:
-- 1. Stop when already stopped returns error_param (1)
SELECT dbms_profiler.stop_profiler();

-- 2. Pause when stopped returns error_param (1)
SELECT dbms_profiler.pause_profiler();

-- 3. Resume when stopped returns error_param (1)
SELECT dbms_profiler.resume_profiler();

-- 4. Double start returns error_param (1)
SELECT dbms_profiler.start_profiler('test_run_2');
SELECT dbms_profiler.start_profiler('test_run_conflict');
SELECT dbms_profiler.stop_profiler();

-- Procedure overload test with OUT run_number
DO $$
DECLARE
    rnum NUMBER;
BEGIN
    dbms_profiler.start_profiler('procedure_test', 'comment', rnum);
    RAISE NOTICE 'Run number assigned: %', (rnum > 0);
    dbms_profiler.stop_profiler();
END;
$$;

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_profiler_start_profiler_internal',
                     'dbms_profiler_get_run_number_internal',
                     'dbms_profiler_stop_profiler_internal',
                     'dbms_profiler_pause_profiler_internal',
                     'dbms_profiler_resume_profiler_internal',
                     'dbms_profiler_flush_data_internal',
                     'dbms_profiler_get_version_internal')
 ORDER BY p.proname;

-- Clean up test records
DELETE FROM sys.plsql_profiler_runs WHERE run_comment IN ('test_run_1', 'test_run_2', 'procedure_test');
