--
-- DBMS_WARNING
--
-- Regression tests for Oracle-compatible DBMS_WARNING package:
--   - GET_CATEGORY for severe, informational, performance codes
--   - ADD_WARNING_SETTING_NUM building composite setting strings
--   - SET_WARNING_SETTING_STRING and GET_WARNING_SETTING_STRING
--   - GET_WARNING_SETTING_NUM
--   - Error handling (NULL parameter checks)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Category resolution
SELECT dbms_warning.get_category(5001);
SELECT dbms_warning.get_category(6002);
SELECT dbms_warning.get_category(7204);

-- Building warning setting strings
SELECT dbms_warning.add_warning_setting_num(5001, 'ERROR', '');
SELECT dbms_warning.add_warning_setting_num(6002, 'DISABLE', 'ENABLE:ALL, ERROR:5001');

-- Set and get warning settings
CALL dbms_warning.set_warning_setting_string('ENABLE:ALL, ERROR:5001, DISABLE:6002');
SELECT dbms_warning.get_warning_setting_string();

SELECT dbms_warning.get_warning_setting_num(5001);
SELECT dbms_warning.get_warning_setting_num(6002);
SELECT dbms_warning.get_warning_setting_num(7000);

-- Error handling: NULL parameter checks
SELECT sys.dbms_warning_add_warning_setting_num_internal(5001, NULL, 'ENABLE:ALL');
SELECT sys.dbms_warning_set_warning_setting_string_internal(NULL);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_warning_get_category_internal',
                     'dbms_warning_add_warning_setting_num_internal',
                     'dbms_warning_get_warning_setting_num_internal',
                     'dbms_warning_set_warning_setting_string_internal',
                     'dbms_warning_get_warning_setting_string_internal')
 ORDER BY p.proname;

-- Reset warning setting string
CALL dbms_warning.set_warning_setting_string('ENABLE:ALL');
