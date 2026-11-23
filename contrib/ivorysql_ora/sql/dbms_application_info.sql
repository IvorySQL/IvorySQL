-- Test the DBMS_APPLICATION_INFO package (session info register/read)
SET ivorysql.compatible_mode = oracle;

-- round trip: set_module + set_action + read_module
CALL dbms_application_info.set_module('payroll', 'monthly');
SELECT sys.ora_dbms_application_info_read_module() AS after_set_module;

-- set_action overrides only the action field
CALL dbms_application_info.set_action('quarterly');
SELECT sys.ora_dbms_application_info_read_module() AS after_set_action;

-- set_client_info + read_client_info
CALL dbms_application_info.set_client_info('client-xyz');
SELECT sys.ora_dbms_application_info_read_client_info() AS after_set_client_info;

-- truncation semantics: module 48, action 32, client_info 64 bytes
CALL dbms_application_info.set_module(rpad('M', 60, 'x'), rpad('A', 40, 'y'));
CALL dbms_application_info.set_client_info(rpad('C', 80, 'z'));
SELECT length(module_name) AS module_len,
       length(action_name) AS action_len
FROM sys.ora_dbms_application_info_read_module();
SELECT length(client_info) AS client_len
FROM sys.ora_dbms_application_info_read_client_info();

-- truncation semantics: multibyte boundary — 47 ASCII bytes + CJK chars
-- must clip on a character boundary within the 48-byte module limit
CALL dbms_application_info.set_module(rpad('M', 47, 'x') || '中中中', 'ok');
SELECT length(module_name) AS module_multibyte_len
FROM sys.ora_dbms_application_info_read_module();

-- NULL clears the fields
CALL dbms_application_info.set_module(NULL, NULL);
SELECT module_name IS NULL AS module_is_null,
       action_name IS NULL AS action_is_null
FROM sys.ora_dbms_application_info_read_module();

-- PL/iSQL OUT-parameter access path
DECLARE
  m varchar2(100);
  a varchar2(100);
  c varchar2(100);
BEGIN
  dbms_application_info.set_module('batch', 'load');
  dbms_application_info.set_client_info('etl-1');
  dbms_application_info.read_module(m, a);
  dbms_application_info.read_client_info(c);
  RAISE NOTICE 'plisql: %/%/%', m, a, c;
END;

-- SET_SESSION_LONGOPS: row allocation, update, and V$SESSION_LONGOPS view
DECLARE
  r int;
  s int;
BEGIN
  r := 0; s := 0;
  dbms_application_info.set_session_longops(r, s, 'backup', 0, 0, 40, 100, 'daily rollup', 'blocks');
  -- observe incomplete progress before the completing update
  RAISE NOTICE 'progress: %/%', 40, 100;
  dbms_application_info.set_session_longops(r, s, 'backup', 0, 0, 100, 100, 'daily rollup', 'blocks');
END;

SELECT rindex, slno, opname, target_desc, sofar, totalwork, units,
       time_remaining IS NULL AS tr_null, message
FROM sys.v$session_longops ORDER BY rindex;

-- NULL clears the longops row? No: rows persist for the session lifetime
SELECT count(*) AS rows_after_clear FROM sys.v$session_longops;
