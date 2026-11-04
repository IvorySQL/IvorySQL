--
-- DBMS_ALERT
--
-- Regression tests for Oracle-compatible DBMS_ALERT package:
--   - REGISTER procedure
--   - SIGNAL procedure
--   - WAITONE procedure (successful signal receipt & timeout)
--   - REMOVE procedure
--   - REMOVEALL procedure
--   - Catalog tables verification (sys.alert_registrations, sys.alert_signals)
--   - Error handling (NULL parameter checks)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- REGISTER alert
CALL dbms_alert.register('inventory_update');
CALL dbms_alert.register('price_change');

-- Verify registrations
SELECT alert_name FROM sys.alert_registrations ORDER BY alert_name;

-- SIGNAL alert
CALL dbms_alert.signal('inventory_update', 'item_1001_restocked');

-- Verify signal in catalog
SELECT alert_name, message FROM sys.alert_signals WHERE alert_name = 'inventory_update';

-- WAITONE on signaled alert
DO $$
DECLARE
    msg VARCHAR2(2047);
    st INTEGER;
BEGIN
    dbms_alert.waitone('inventory_update', msg, st, 1);
    RAISE NOTICE 'WAITONE inventory_update: status=%, message=%', st, msg;
END;
$$;

-- WAITONE on unsignaled alert (returns status=1 timeout)
DO $$
DECLARE
    msg VARCHAR2(2047);
    st INTEGER;
BEGIN
    dbms_alert.waitone('unsignaled_alert', msg, st, 0);
    RAISE NOTICE 'WAITONE unsignaled_alert: status=%', st;
END;
$$;

-- REMOVE specific alert
CALL dbms_alert.remove('price_change');
SELECT alert_name FROM sys.alert_registrations ORDER BY alert_name;

-- REMOVEALL alerts
CALL dbms_alert.removeall();
SELECT COUNT(*) FROM sys.alert_registrations;

-- Error handling: NULL parameter checks
SELECT sys.dbms_alert_register_internal(NULL);
SELECT sys.dbms_alert_remove_internal(NULL);
SELECT sys.dbms_alert_signal_internal(NULL, 'test');
SELECT sys.dbms_alert_waitone_internal(NULL, 1.0);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_alert_register_internal',
                     'dbms_alert_remove_internal',
                     'dbms_alert_removeall_internal',
                     'dbms_alert_signal_internal',
                     'dbms_alert_waitone_internal')
 ORDER BY p.proname;

-- Clean up signals
DELETE FROM sys.alert_signals;
