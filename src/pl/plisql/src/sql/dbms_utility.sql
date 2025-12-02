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
