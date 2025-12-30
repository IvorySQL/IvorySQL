--
-- Tests for DBMS_UTILITY package
--

-- Test 1: FORMAT_ERROR_BACKTRACE - Basic exception in procedure
CREATE OR REPLACE PROCEDURE test_basic_error AS
  v_backtrace VARCHAR2(4000);
BEGIN
  RAISE EXCEPTION 'Test error';
EXCEPTION
  WHEN OTHERS THEN
    v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    RAISE INFO 'Backtrace: %', v_backtrace;
END;
/

CALL test_basic_error();

DROP PROCEDURE test_basic_error;

-- Test 2: FORMAT_ERROR_BACKTRACE - Nested procedure calls
CREATE OR REPLACE PROCEDURE test_level3 AS
BEGIN
  RAISE EXCEPTION 'Error at level 3';
END;
/

CREATE OR REPLACE PROCEDURE test_level2 AS
BEGIN
  test_level3();
END;
/

CREATE OR REPLACE PROCEDURE test_level1 AS
  v_backtrace VARCHAR2(4000);
BEGIN
  test_level2();
EXCEPTION
  WHEN OTHERS THEN
    v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    RAISE INFO 'Backtrace: %', v_backtrace;
END;
/

CALL test_level1();

DROP PROCEDURE test_level1;
DROP PROCEDURE test_level2;
DROP PROCEDURE test_level3;

-- Test 3: FORMAT_ERROR_BACKTRACE - Deeply nested calls
CREATE OR REPLACE PROCEDURE test_deep5 AS
BEGIN
  RAISE EXCEPTION 'Error at deepest level';
END;
/

CREATE OR REPLACE PROCEDURE test_deep4 AS
BEGIN
  test_deep5();
END;
/

CREATE OR REPLACE PROCEDURE test_deep3 AS
BEGIN
  test_deep4();
END;
/

CREATE OR REPLACE PROCEDURE test_deep2 AS
BEGIN
  test_deep3();
END;
/

CREATE OR REPLACE PROCEDURE test_deep1 AS
  v_backtrace VARCHAR2(4000);
BEGIN
  test_deep2();
EXCEPTION
  WHEN OTHERS THEN
    v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    RAISE INFO 'Deep backtrace: %', v_backtrace;
END;
/

CALL test_deep1();

DROP PROCEDURE test_deep1;
DROP PROCEDURE test_deep2;
DROP PROCEDURE test_deep3;
DROP PROCEDURE test_deep4;
DROP PROCEDURE test_deep5;

-- Test 4: FORMAT_ERROR_BACKTRACE - Function calls
CREATE OR REPLACE FUNCTION test_func_error RETURN NUMBER AS
BEGIN
  RAISE EXCEPTION 'Error in function';
  RETURN 1;
END;
/

CREATE OR REPLACE PROCEDURE test_func_caller AS
  v_result NUMBER;
  v_backtrace VARCHAR2(4000);
BEGIN
  v_result := test_func_error();
EXCEPTION
  WHEN OTHERS THEN
    v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    RAISE INFO 'Function backtrace: %', v_backtrace;
END;
/

CALL test_func_caller();

DROP PROCEDURE test_func_caller;
DROP FUNCTION test_func_error;

-- Test 5: FORMAT_ERROR_BACKTRACE - Anonymous block
DO $$
DECLARE
  v_backtrace VARCHAR2(4000);
BEGIN
  RAISE EXCEPTION 'Error in anonymous block';
EXCEPTION
  WHEN OTHERS THEN
    v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    RAISE INFO 'Anonymous block backtrace: %', v_backtrace;
END;
$$;

-- Test 6: FORMAT_ERROR_BACKTRACE - No exception (should return empty)
CREATE OR REPLACE PROCEDURE test_no_error AS
  v_backtrace VARCHAR2(4000);
BEGIN
  v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
  RAISE INFO 'No error - backtrace: [%]', v_backtrace;
END;
/

CALL test_no_error();

DROP PROCEDURE test_no_error;

-- Test 7: FORMAT_ERROR_BACKTRACE - Multiple exception levels
CREATE OR REPLACE PROCEDURE test_multi_inner AS
BEGIN
  RAISE EXCEPTION 'Inner error';
END;
/

CREATE OR REPLACE PROCEDURE test_multi_middle AS
BEGIN
  BEGIN
    test_multi_inner();
  EXCEPTION
    WHEN OTHERS THEN
      RAISE INFO 'Caught at middle level';
      RAISE;
  END;
END;
/

CREATE OR REPLACE PROCEDURE test_multi_outer AS
  v_backtrace VARCHAR2(4000);
BEGIN
  test_multi_middle();
EXCEPTION
  WHEN OTHERS THEN
    v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    RAISE INFO 'Outer backtrace: %', v_backtrace;
END;
/

CALL test_multi_outer();

DROP PROCEDURE test_multi_outer;
DROP PROCEDURE test_multi_middle;
DROP PROCEDURE test_multi_inner;

-- Test 8: FORMAT_ERROR_BACKTRACE - Package procedure
CREATE OR REPLACE PACKAGE test_pkg IS
  PROCEDURE pkg_error;
  PROCEDURE pkg_caller;
END test_pkg;
/

CREATE OR REPLACE PACKAGE BODY test_pkg IS
  PROCEDURE pkg_error IS
  BEGIN
    RAISE EXCEPTION 'Error in package procedure';
  END pkg_error;

  PROCEDURE pkg_caller IS
    v_backtrace VARCHAR2(4000);
  BEGIN
    pkg_error();
  EXCEPTION
    WHEN OTHERS THEN
      v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
      RAISE INFO 'Package backtrace: %', v_backtrace;
  END pkg_caller;
END test_pkg;
/

CALL test_pkg.pkg_caller();

DROP PACKAGE test_pkg;

-- Test 9: FORMAT_ERROR_BACKTRACE - Schema-qualified calls
CREATE SCHEMA test_schema;

CREATE OR REPLACE PROCEDURE test_schema.schema_error AS
BEGIN
  RAISE EXCEPTION 'Error in schema procedure';
END;
/

CREATE OR REPLACE PROCEDURE test_schema.schema_caller AS
  v_backtrace VARCHAR2(4000);
BEGIN
  test_schema.schema_error();
EXCEPTION
  WHEN OTHERS THEN
    v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    RAISE INFO 'Schema-qualified backtrace: %', v_backtrace;
END;
/

CALL test_schema.schema_caller();

DROP SCHEMA test_schema CASCADE;

-- Test 10: Nested exception handlers - outer context preserved after inner handler
-- This tests that when an exception handler calls a procedure that has its own
-- exception handler, the outer handler's backtrace is preserved.
CREATE OR REPLACE PROCEDURE test_nested_inner AS
BEGIN
  RAISE EXCEPTION 'Inner error';
EXCEPTION
  WHEN OTHERS THEN
    RAISE INFO 'Inner handler caught error';
END;
/

CREATE OR REPLACE PROCEDURE test_nested_outer AS
  v_bt_before VARCHAR2(4000);
  v_bt_after VARCHAR2(4000);
BEGIN
  RAISE EXCEPTION 'Outer error';
EXCEPTION
  WHEN OTHERS THEN
    v_bt_before := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    RAISE INFO 'Outer backtrace before: %', v_bt_before;
    test_nested_inner();
    v_bt_after := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    RAISE INFO 'Outer backtrace after: %', v_bt_after;
    IF v_bt_before = v_bt_after THEN
      RAISE INFO 'SUCCESS: Outer backtrace preserved';
    ELSE
      RAISE INFO 'FAILURE: Outer backtrace changed';
    END IF;
END;
/

CALL test_nested_outer();

DROP PROCEDURE test_nested_outer;
DROP PROCEDURE test_nested_inner;

-- ============================================================
-- Tests for FORMAT_ERROR_STACK
-- ============================================================

-- Test 11: FORMAT_ERROR_STACK - Basic exception
CREATE OR REPLACE PROCEDURE test_error_stack_basic AS
  v_stack VARCHAR2(4000);
BEGIN
  RAISE EXCEPTION 'Test error message';
EXCEPTION
  WHEN OTHERS THEN
    v_stack := DBMS_UTILITY.FORMAT_ERROR_STACK;
    RAISE INFO 'Error stack: %', v_stack;
END;
/

CALL test_error_stack_basic();

DROP PROCEDURE test_error_stack_basic;

-- Test 12: FORMAT_ERROR_STACK - Division by zero
CREATE OR REPLACE PROCEDURE test_error_stack_divzero AS
  v_stack VARCHAR2(4000);
  v_num NUMBER;
BEGIN
  v_num := 1 / 0;
EXCEPTION
  WHEN OTHERS THEN
    v_stack := DBMS_UTILITY.FORMAT_ERROR_STACK;
    RAISE INFO 'Division error stack: %', v_stack;
END;
/

CALL test_error_stack_divzero();

DROP PROCEDURE test_error_stack_divzero;

-- Test 13: FORMAT_ERROR_STACK - No exception (should return NULL)
CREATE OR REPLACE PROCEDURE test_error_stack_no_error AS
  v_stack VARCHAR2(4000);
BEGIN
  v_stack := DBMS_UTILITY.FORMAT_ERROR_STACK;
  RAISE INFO 'No error - stack: [%]', v_stack;
END;
/

CALL test_error_stack_no_error();

DROP PROCEDURE test_error_stack_no_error;

-- ============================================================
-- Tests for FORMAT_CALL_STACK
-- ============================================================

-- Test 14: FORMAT_CALL_STACK - Basic single procedure (verify structure)
-- Note: Addresses vary between runs, so we just verify the stack is not null
-- and contains the expected function name pattern
CREATE OR REPLACE PROCEDURE test_call_stack_basic AS
  v_stack VARCHAR2(4000);
BEGIN
  v_stack := DBMS_UTILITY.FORMAT_CALL_STACK;
  IF v_stack IS NOT NULL AND v_stack LIKE '%----- PL/SQL Call Stack -----%' THEN
    -- Extract just the function name part for verification
    IF v_stack LIKE '%TEST_CALL_STACK_BASIC%' THEN
      RAISE INFO 'Call stack contains expected function';
    END IF;
  END IF;
END;
/

CALL test_call_stack_basic();

DROP PROCEDURE test_call_stack_basic;

-- Test 15: FORMAT_CALL_STACK - Nested procedure calls (verify count)
CREATE OR REPLACE PROCEDURE test_call_stack_level3 AS
  v_stack VARCHAR2(4000);
  v_count INTEGER;
BEGIN
  v_stack := DBMS_UTILITY.FORMAT_CALL_STACK;
  -- Count the number of function entries (look for 'function ' pattern)
  v_count := (LENGTH(v_stack) - LENGTH(REPLACE(v_stack, 'function ', ''))) / 9;
  RAISE INFO 'Call stack has % function entries', v_count;
END;
/

CREATE OR REPLACE PROCEDURE test_call_stack_level2 AS
BEGIN
  test_call_stack_level3();
END;
/

CREATE OR REPLACE PROCEDURE test_call_stack_level1 AS
BEGIN
  test_call_stack_level2();
END;
/

CALL test_call_stack_level1();

DROP PROCEDURE test_call_stack_level1;
DROP PROCEDURE test_call_stack_level2;
DROP PROCEDURE test_call_stack_level3;

-- Test 16: FORMAT_CALL_STACK - In exception handler
CREATE OR REPLACE PROCEDURE test_call_stack_exception AS
  v_stack VARCHAR2(4000);
BEGIN
  RAISE EXCEPTION 'Test error';
EXCEPTION
  WHEN OTHERS THEN
    v_stack := DBMS_UTILITY.FORMAT_CALL_STACK;
    IF v_stack IS NOT NULL AND v_stack LIKE '%TEST_CALL_STACK_EXCEPTION%' THEN
      RAISE INFO 'Call stack in exception handler: OK';
    END IF;
END;
/

CALL test_call_stack_exception();

DROP PROCEDURE test_call_stack_exception;

-- Test 17: All three functions together (verify they return expected content)
CREATE OR REPLACE PROCEDURE test_all_functions_inner AS
BEGIN
  RAISE EXCEPTION 'Inner error for all functions test';
END;
/

CREATE OR REPLACE PROCEDURE test_all_functions_outer AS
  v_backtrace VARCHAR2(4000);
  v_error_stack VARCHAR2(4000);
  v_call_stack VARCHAR2(4000);
  v_all_ok BOOLEAN := TRUE;
BEGIN
  test_all_functions_inner();
EXCEPTION
  WHEN OTHERS THEN
    v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    v_error_stack := DBMS_UTILITY.FORMAT_ERROR_STACK;
    v_call_stack := DBMS_UTILITY.FORMAT_CALL_STACK;

    -- Verify FORMAT_ERROR_BACKTRACE
    IF v_backtrace IS NULL OR v_backtrace NOT LIKE '%ORA-06512%' THEN
      v_all_ok := FALSE;
      RAISE INFO 'FORMAT_ERROR_BACKTRACE: FAILED';
    END IF;

    -- Verify FORMAT_ERROR_STACK
    IF v_error_stack IS NULL OR v_error_stack NOT LIKE '%ORA-%' THEN
      v_all_ok := FALSE;
      RAISE INFO 'FORMAT_ERROR_STACK: FAILED';
    END IF;

    -- Verify FORMAT_CALL_STACK
    IF v_call_stack IS NULL OR v_call_stack NOT LIKE '%----- PL/SQL Call Stack -----%' THEN
      v_all_ok := FALSE;
      RAISE INFO 'FORMAT_CALL_STACK: FAILED';
    END IF;

    IF v_all_ok THEN
      RAISE INFO 'All three DBMS_UTILITY functions: OK';
    END IF;
END;
/

CALL test_all_functions_outer();

DROP PROCEDURE test_all_functions_outer;
DROP PROCEDURE test_all_functions_inner;
