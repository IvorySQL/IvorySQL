--
-- UTL_LMS
--
-- Regression tests for Oracle-compatible UTL_LMS package:
--   - FORMAT_MESSAGE with strings and numeric substitutions
--   - FORMAT_MESSAGE with extended 8 parameters
--   - FORMAT_MESSAGE with escaped percent signs ('%%')
--   - FORMAT_MESSAGE with partial and NULL arguments
--   - GET_MESSAGE procedure call
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Basic string format substitution
SELECT utl_lms.format_message('User %s performed %s on table %s', 'SCOTT', 'INSERT', 'EMP');

-- Mixed format with %s and %d
SELECT utl_lms.format_message('Processed %d records in %s mode', '150', 'BATCH');

-- Extended 8-parameter format substitution
SELECT utl_lms.format_message('Col1: %s, Col2: %s, Col3: %s, Col4: %s, Col5: %s, Col6: %s',
                              'A', 'B', 'C', 'D', 'E', 'F');

-- Escaped percent signs ('%%')
SELECT utl_lms.format_message('Disk usage at %s%% capacity', '85');

-- Fewer arguments provided than format specifiers
SELECT utl_lms.format_message('Param1: %s, Param2: %s', 'first_value');

-- Format with NULL arguments
SELECT utl_lms.format_message('Value: %s', NULL);

-- GET_MESSAGE procedure call
DO $$
DECLARE
    msg VARCHAR2(500);
BEGIN
    utl_lms.get_message(1403, 'rdbms', 'ora', 'american', msg);
    RAISE NOTICE 'GET_MESSAGE result: %', msg;
END;
$$;

-- Direct internal function tests
SELECT sys.utl_lms_get_message_extended_internal(1403, 'rdbms', 'ora', 'american');

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('utl_lms_format_message_internal',
                     'utl_lms_format_message_extended_internal',
                     'utl_lms_get_message_internal',
                     'utl_lms_get_message_extended_internal')
 ORDER BY p.proname;
