--
-- UTL_CALL_STACK
--
-- Regression tests for Oracle-compatible UTL_CALL_STACK package:
--   - BACKTRACE_DEPTH
--   - BACKTRACE_LINE
--   - BACKTRACE_UNIT
--   - DYNAMIC_DEPTH
--   - CURRENT_EDITION
--   - OWNER
--   - SUBPROGRAM
--   - UNIT_LINE
--   - Error handling (index < 1 boundary checks)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- General call stack inspection
SELECT utl_call_stack.backtrace_depth();
SELECT utl_call_stack.backtrace_line(1);
SELECT utl_call_stack.backtrace_unit(1);
SELECT utl_call_stack.dynamic_depth();
SELECT utl_call_stack.current_edition();
SELECT utl_call_stack.owner(1) IS NOT NULL;
SELECT utl_call_stack.subprogram(1);
SELECT utl_call_stack.unit_line(1);

-- Inspection within an anonymous block
DO $$
DECLARE
    d INTEGER;
    ed VARCHAR2(128);
    u VARCHAR2(128);
BEGIN
    d := utl_call_stack.dynamic_depth();
    ed := utl_call_stack.current_edition();
    u := utl_call_stack.subprogram(1);
    RAISE NOTICE 'Call stack info: depth=%, edition=%, subprogram=%', d, ed, u;
END;
$$;

-- Error handling: index < 1 checks
SELECT sys.utl_call_stack_backtrace_line_internal(0);
SELECT sys.utl_call_stack_backtrace_unit_internal(-1);
SELECT sys.utl_call_stack_owner_internal(0);
SELECT sys.utl_call_stack_subprogram_internal(-5);
SELECT sys.utl_call_stack_unit_line_internal(0);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('utl_call_stack_backtrace_depth_internal',
                     'utl_call_stack_backtrace_line_internal',
                     'utl_call_stack_backtrace_unit_internal',
                     'utl_call_stack_dynamic_depth_internal',
                     'utl_call_stack_current_edition_internal',
                     'utl_call_stack_owner_internal',
                     'utl_call_stack_subprogram_internal',
                     'utl_call_stack_unit_line_internal')
 ORDER BY p.proname;
