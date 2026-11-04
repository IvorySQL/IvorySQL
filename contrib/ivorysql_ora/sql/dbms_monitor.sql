--
-- DBMS_MONITOR
--
-- Regression tests for Oracle-compatible DBMS_MONITOR package:
--   - CLIENT_ID_STAT_ENABLE / CLIENT_ID_STAT_DISABLE
--   - CLIENT_ID_TRACE_ENABLE / CLIENT_ID_TRACE_DISABLE
--   - SESSION_TRACE_ENABLE / SESSION_TRACE_DISABLE
--   - DATABASE_TRACE_ENABLE / DATABASE_TRACE_DISABLE
--   - Catalog tables verification (sys.monitored_client_ids, sys.monitored_sessions)
--   - Error handling (NULL parameter checks)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Enable and disable statistics by client_id
CALL dbms_monitor.client_id_stat_enable('app_user_101');
SELECT client_id, stat_enabled, trace_enabled FROM sys.monitored_client_ids WHERE client_id = 'app_user_101';

CALL dbms_monitor.client_id_stat_disable('app_user_101');
SELECT client_id, stat_enabled FROM sys.monitored_client_ids WHERE client_id = 'app_user_101';

-- Enable and disable tracing by client_id
CALL dbms_monitor.client_id_trace_enable('app_user_101', TRUE, FALSE, 'ALL_EXECUTIONS');
SELECT client_id, trace_enabled FROM sys.monitored_client_ids WHERE client_id = 'app_user_101';

CALL dbms_monitor.client_id_trace_disable('app_user_101');
SELECT client_id, trace_enabled FROM sys.monitored_client_ids WHERE client_id = 'app_user_101';

-- Enable and disable session tracing
CALL dbms_monitor.session_trace_enable(12, 105, TRUE, FALSE, 'ALL_EXECUTIONS');
SELECT session_id, serial_num, trace_enabled, waits, binds, plan_stat
  FROM sys.monitored_sessions
 WHERE session_id = 12 AND serial_num = 105;

CALL dbms_monitor.session_trace_disable(12, 105);
SELECT session_id, serial_num, trace_enabled
  FROM sys.monitored_sessions
 WHERE session_id = 12 AND serial_num = 105;

-- Database-wide trace
CALL dbms_monitor.database_trace_enable(TRUE, FALSE, 'FIRST_EXECUTION');
CALL dbms_monitor.database_trace_disable();

-- Error handling: NULL parameter checks
SELECT sys.dbms_monitor_client_id_stat_enable_internal(NULL);
SELECT sys.dbms_monitor_client_id_stat_disable_internal(NULL);
SELECT sys.dbms_monitor_client_id_trace_enable_internal(NULL, true, false, 'FIRST_EXECUTION');
SELECT sys.dbms_monitor_client_id_trace_disable_internal(NULL);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_monitor_client_id_stat_disable_internal',
                     'dbms_monitor_client_id_stat_enable_internal',
                     'dbms_monitor_client_id_trace_disable_internal',
                     'dbms_monitor_client_id_trace_enable_internal',
                     'dbms_monitor_session_trace_disable_internal',
                     'dbms_monitor_session_trace_enable_internal',
                     'dbms_monitor_database_trace_enable_internal',
                     'dbms_monitor_database_trace_disable_internal')
 ORDER BY p.proname;

-- Clean up
DELETE FROM sys.monitored_client_ids WHERE client_id = 'app_user_101';
DELETE FROM sys.monitored_sessions WHERE session_id = 12 AND serial_num = 105;
