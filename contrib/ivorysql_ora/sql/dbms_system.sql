--
-- DBMS_SYSTEM
--
-- Regression tests for Oracle-compatible DBMS_SYSTEM package:
--   - Package constants (dest_trace, dest_alert, dest_both)
--   - KSDWRT procedure calls to trace, alert log, and both
--   - SET_SQL_TRACE_IN_SESSION procedure
--   - SET_EV procedure
--   - READ_EV procedure
--   - GET_ENV procedure
--   - Error handling (invalid dest, NULL parameter, invalid sid)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Package constants
SELECT dbms_system.dest_trace;
SELECT dbms_system.dest_alert;
SELECT dbms_system.dest_both;

-- KSDWRT calls
CALL dbms_system.ksdwrt(dbms_system.dest_trace, 'Diagnostic trace message test');
CALL dbms_system.ksdwrt(dbms_system.dest_alert, 'Diagnostic alert log message test');
CALL dbms_system.ksdwrt(dbms_system.dest_both, 'Dual destination log message test');

-- SET_SQL_TRACE_IN_SESSION
CALL dbms_system.set_sql_trace_in_session(1, 101, TRUE);
CALL dbms_system.set_sql_trace_in_session(1, 101, FALSE);

-- SET_EV
CALL dbms_system.set_ev(1, 101, 10046, 12, '');

-- READ_EV
DO $$
DECLARE
    lvl INTEGER;
BEGIN
    dbms_system.read_ev(10046, lvl);
    RAISE NOTICE 'READ_EV level: %', lvl;
END;
$$;

-- GET_ENV
DO $$
DECLARE
    val VARCHAR2(256);
BEGIN
    dbms_system.get_env('PATH', val);
    RAISE NOTICE 'GET_ENV PATH is not null: %', (val IS NOT NULL);
END;
$$;

-- Error handling: invalid destination
SELECT sys.dbms_system_ksdwrt_internal(99, 'Invalid dest test');

-- Error handling: NULL message
SELECT sys.dbms_system_ksdwrt_internal(1, NULL);

-- Error handling: invalid sid
SELECT sys.dbms_system_set_sql_trace_in_session_internal(0, 1, true);
SELECT sys.dbms_system_set_ev_internal(-1, 1, 10046, 1, '');
SELECT sys.dbms_system_get_env_internal(NULL);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_system_ksdwrt_internal',
                     'dbms_system_set_sql_trace_in_session_internal',
                     'dbms_system_set_ev_internal',
                     'dbms_system_read_ev_internal',
                     'dbms_system_get_env_internal')
 ORDER BY p.proname;
