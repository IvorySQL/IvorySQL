--
-- Test user-defined EXCEPTION type declarations
--
-- Note: This test verifies EXCEPTION type declarations compile correctly.
-- RAISE and WHEN handler support for user-defined exceptions is not yet
-- implemented and is commented out below.
--

-- Test 1: Basic EXCEPTION declaration in package body
CREATE OR REPLACE PACKAGE test_exc_pkg1 IS
  PROCEDURE test_proc;
END test_exc_pkg1;
/

CREATE OR REPLACE PACKAGE BODY test_exc_pkg1 IS
  bad_interval EXCEPTION;  -- User-defined exception

  PROCEDURE test_proc IS
  BEGIN
    RAISE INFO 'Package with EXCEPTION compiled successfully';
  END test_proc;
END test_exc_pkg1;
/

-- Verify the package body was created
SELECT 'Package test_exc_pkg1 created' AS result;

-- Test 2: Multiple EXCEPTION declarations
CREATE OR REPLACE PACKAGE test_exc_pkg2 IS
  PROCEDURE multi_exc_test;
END test_exc_pkg2;
/

CREATE OR REPLACE PACKAGE BODY test_exc_pkg2 IS
  exc_invalid_data EXCEPTION;
  exc_timeout EXCEPTION;
  exc_not_found EXCEPTION;

  PROCEDURE multi_exc_test IS
  BEGIN
    RAISE INFO 'Multiple exceptions declared successfully';
  END multi_exc_test;
END test_exc_pkg2;
/

SELECT 'Package test_exc_pkg2 with multiple exceptions created' AS result;

-- Test 3: EXCEPTION in standalone procedure (should work in declaration block)
CREATE OR REPLACE PROCEDURE test_standalone_exc IS
  my_exception EXCEPTION;
BEGIN
  RAISE INFO 'Standalone procedure with EXCEPTION compiled';
END;
/

SELECT 'Standalone procedure with EXCEPTION created' AS result;

-- Test 4: EXCEPTION mixed with other variable types
CREATE OR REPLACE PACKAGE test_exc_pkg3 IS
  PROCEDURE mixed_decl_test;
END test_exc_pkg3;
/

CREATE OR REPLACE PACKAGE BODY test_exc_pkg3 IS
  v_counter NUMBER := 0;
  exc_custom EXCEPTION;
  v_name VARCHAR2(100) := 'Test';
  exc_another EXCEPTION;
  v_date DATE;

  PROCEDURE mixed_decl_test IS
  BEGIN
    RAISE INFO 'Mixed declarations compiled successfully';
  END mixed_decl_test;
END test_exc_pkg3;
/

SELECT 'Package test_exc_pkg3 with mixed declarations created' AS result;

--
-- Test 5: RAISE and exception handling
--
CREATE OR REPLACE PACKAGE test_exc_raise IS
  PROCEDURE test_raise_catch;
END test_exc_raise;
/

CREATE OR REPLACE PACKAGE BODY test_exc_raise IS
  custom_error EXCEPTION;

  PROCEDURE test_raise_catch IS
  BEGIN
    RAISE custom_error;  -- Raise user-defined exception
  EXCEPTION
    WHEN custom_error THEN  -- Catch user-defined exception
      RAISE INFO 'Successfully caught custom_error';
  END test_raise_catch;
END test_exc_raise;
/

-- Test execution
BEGIN
  test_exc_raise.test_raise_catch();
END;
/

DROP PACKAGE test_exc_raise;

--
-- Test 6: PRAGMA EXCEPTION_INIT basic usage
--
CREATE OR REPLACE PACKAGE test_pragma_init IS
  PROCEDURE test_basic_pragma;
END test_pragma_init;
/

CREATE OR REPLACE PACKAGE BODY test_pragma_init IS
  my_exception EXCEPTION;
  PRAGMA EXCEPTION_INIT(my_exception, -20001);

  PROCEDURE test_basic_pragma IS
  BEGIN
    RAISE INFO 'PRAGMA EXCEPTION_INIT compiled successfully';
  END test_basic_pragma;
END test_pragma_init;
/

-- Test execution
BEGIN
  test_pragma_init.test_basic_pragma();
END;
/

SELECT 'PRAGMA EXCEPTION_INIT basic test passed' AS result;

--
-- Test 7: PRAGMA EXCEPTION_INIT with RAISE and WHEN
--
CREATE OR REPLACE PACKAGE test_pragma_raise IS
  PROCEDURE test_pragma_exception;
END test_pragma_raise;
/

CREATE OR REPLACE PACKAGE BODY test_pragma_raise IS
  custom_exc EXCEPTION;
  PRAGMA EXCEPTION_INIT(custom_exc, -20002);

  PROCEDURE test_pragma_exception IS
  BEGIN
    RAISE custom_exc;
  EXCEPTION
    WHEN custom_exc THEN
      RAISE INFO 'Caught exception with PRAGMA EXCEPTION_INIT';
  END test_pragma_exception;
END test_pragma_raise;
/

-- Test execution
BEGIN
  test_pragma_raise.test_pragma_exception();
END;
/

--
-- Test 8: PRAGMA EXCEPTION_INIT in procedure
--
CREATE OR REPLACE PROCEDURE test_pragma_proc IS
  my_exc EXCEPTION;
  PRAGMA EXCEPTION_INIT(my_exc, -20003);
BEGIN
  RAISE INFO 'PRAGMA EXCEPTION_INIT in procedure works';
  RAISE my_exc;
EXCEPTION
  WHEN my_exc THEN
    RAISE INFO 'Exception caught in procedure';
END;
/

-- Test execution
BEGIN
  test_pragma_proc();
END;
/

SELECT 'PRAGMA EXCEPTION_INIT in procedure test passed' AS result;

--
-- Test 9: Multiple PRAGMA EXCEPTION_INIT declarations
--
CREATE OR REPLACE PACKAGE test_multi_pragma IS
  PROCEDURE test_multiple;
END test_multi_pragma;
/

CREATE OR REPLACE PACKAGE BODY test_multi_pragma IS
  exc1 EXCEPTION;
  PRAGMA EXCEPTION_INIT(exc1, -20011);

  exc2 EXCEPTION;
  PRAGMA EXCEPTION_INIT(exc2, -20012);

  exc3 EXCEPTION;
  PRAGMA EXCEPTION_INIT(exc3, -20013);

  PROCEDURE test_multiple IS
  BEGIN
    RAISE INFO 'Multiple PRAGMA EXCEPTION_INIT declarations work';
  END test_multiple;
END test_multi_pragma;
/

BEGIN
  test_multi_pragma.test_multiple();
END;
/

SELECT 'Multiple PRAGMA EXCEPTION_INIT test passed' AS result;

--
-- Test 10: PRAGMA EXCEPTION_INIT with positive error codes
-- Oracle documentation: Valid codes are 100 or any negative integer >= -1000000 (except -1403)
-- This test verifies positive error codes: only 100 is accepted, all others are rejected.
--

-- Test 10a: Valid positive error code 100 (should succeed)
CREATE OR REPLACE PACKAGE test_pragma_positive_100 IS
  PROCEDURE test_positive;
END test_pragma_positive_100;
/

CREATE OR REPLACE PACKAGE BODY test_pragma_positive_100 IS
  exc_100 EXCEPTION;
  PRAGMA EXCEPTION_INIT(exc_100, 100);  -- Oracle accepts: ANSI NO_DATA_FOUND

  PROCEDURE test_positive IS
  BEGIN
    RAISE INFO 'Error code 100 accepted (ANSI NO_DATA_FOUND)';
  END test_positive;
END test_pragma_positive_100;
/

BEGIN
  test_pragma_positive_100.test_positive();
END;
/

DROP PACKAGE test_pragma_positive_100;

-- Test 10b: Invalid positive error code 1 (should fail with PLS-00701)
CREATE OR REPLACE PACKAGE test_pragma_positive_1 IS
  exc_1 EXCEPTION;
  PRAGMA EXCEPTION_INIT(exc_1, 1);  -- Oracle rejects: positive except 100
END test_pragma_positive_1;
/

-- Test 10c: Invalid positive error code 1000000 (should fail with PLS-00701)
CREATE OR REPLACE PACKAGE test_pragma_positive_1000000 IS
  exc_1000000 EXCEPTION;
  PRAGMA EXCEPTION_INIT(exc_1000000, 1000000);  -- Oracle rejects: positive except 100
END test_pragma_positive_1000000;
/

SELECT 'PRAGMA EXCEPTION_INIT positive error code tests completed' AS result;

--
-- Test 11: PRAGMA EXCEPTION_INIT with negative error codes and boundary
-- Oracle documentation: Valid codes are 100 or any negative integer >= -1000000 (except -1403)
-- This test verifies the -1000000 boundary and specifically rejected negative codes.
--

-- Test 11a: Valid error code -1000000 (should succeed - at boundary)
CREATE OR REPLACE PACKAGE test_pragma_minus_1000000 IS
  PROCEDURE test_boundary;
END test_pragma_minus_1000000;
/

CREATE OR REPLACE PACKAGE BODY test_pragma_minus_1000000 IS
  exc_boundary EXCEPTION;
  PRAGMA EXCEPTION_INIT(exc_boundary, -1000000);  -- At the boundary

  PROCEDURE test_boundary IS
  BEGIN
    RAISE INFO 'Error code -1000000 accepted (at boundary)';
  END test_boundary;
END test_pragma_minus_1000000;
/

BEGIN
  test_pragma_minus_1000000.test_boundary();
END;
/

DROP PACKAGE test_pragma_minus_1000000;

-- Test 11b: Invalid error code -1000001 (should fail with PLS-00701 - beyond boundary)
CREATE OR REPLACE PACKAGE test_pragma_minus_1000001 IS
  exc_beyond EXCEPTION;
  PRAGMA EXCEPTION_INIT(exc_beyond, -1000001);  -- Beyond boundary
END test_pragma_minus_1000001;
/

-- Test 11c: Invalid error code -1403 (should fail with PLS-00701)
CREATE OR REPLACE PACKAGE test_pragma_minus_1403 IS
  exc_1403 EXCEPTION;
  PRAGMA EXCEPTION_INIT(exc_1403, -1403);  -- Oracle-specific NO_DATA_FOUND, must use 100
END test_pragma_minus_1403;
/

-- Test 11d: Invalid error code 0 (should fail with PLS-00701)
CREATE OR REPLACE PACKAGE test_pragma_zero IS
  exc_zero EXCEPTION;
  PRAGMA EXCEPTION_INIT(exc_zero, 0);  -- Zero is rejected by Oracle
END test_pragma_zero;
/

SELECT 'PRAGMA EXCEPTION_INIT negative error code tests completed' AS result;

--
-- Test 12: SQLERRM in procedures when package has EXCEPTION variables (issue #1151)
-- When a package declares user-defined EXCEPTION variables at package scope,
-- passing SQLERRM to procedures from exception handlers should work.
--
CREATE OR REPLACE PACKAGE test_sqlerrm_with_exc IS
  my_exception EXCEPTION;  -- User-defined exception at package scope
  PROCEDURE log_error(p_msg VARCHAR2);
  PROCEDURE test_sqlerrm;
END test_sqlerrm_with_exc;
/

CREATE OR REPLACE PACKAGE BODY test_sqlerrm_with_exc IS
  PROCEDURE log_error(p_msg VARCHAR2) IS
  BEGIN
    RAISE INFO 'Logged: %', p_msg;
  END log_error;

  PROCEDURE test_sqlerrm IS
  BEGIN
    RAISE my_exception;
  EXCEPTION
    WHEN my_exception THEN
      -- This should work: passing SQLERRM to procedure
      log_error(SQLERRM);
  END test_sqlerrm;
END test_sqlerrm_with_exc;
/

-- Test execution - this used to fail with "exception variables cannot be used in this context"
BEGIN
  test_sqlerrm_with_exc.test_sqlerrm();
END;
/

SELECT 'SQLERRM with package EXCEPTION test passed (issue #1151)' AS result;

DROP PACKAGE test_sqlerrm_with_exc;

--
-- Test 13: Oracle predefined exception names (issue #3098)
--
CREATE TABLE test_predef_t (id int PRIMARY KEY);
INSERT INTO test_predef_t VALUES (1);

DECLARE
  n NUMBER;
BEGIN
  n := 1 / 0;
EXCEPTION
  WHEN ZERO_DIVIDE THEN
    RAISE INFO 'ZERO_DIVIDE caught %', SQLSTATE;
END;
/

BEGIN
  INSERT INTO test_predef_t VALUES (1);
EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    RAISE INFO 'DUP_VAL_ON_INDEX caught %', SQLSTATE;
END;
/

DECLARE
  v VARCHAR2(3);
  n NUMBER(2);
  m NUMBER;
BEGIN
  BEGIN
    v := 'abcdef';
  EXCEPTION
    WHEN VALUE_ERROR THEN
      RAISE INFO 'VALUE_ERROR caught string overflow %', SQLSTATE;
  END;
  BEGIN
    n := 100;
  EXCEPTION
    WHEN VALUE_ERROR THEN
      RAISE INFO 'VALUE_ERROR caught number overflow %', SQLSTATE;
  END;
  BEGIN
    m := 'abc';
  EXCEPTION
    WHEN VALUE_ERROR THEN
      RAISE INFO 'VALUE_ERROR caught conversion error %', SQLSTATE;
  END;
END;
/

DECLARE
  m NUMBER;
BEGIN
  m := '12a';
EXCEPTION
  WHEN INVALID_NUMBER THEN
    RAISE INFO 'INVALID_NUMBER caught %', SQLSTATE;
END;
/

CREATE OR REPLACE PROCEDURE test_predef_cursor_open IS
  c CURSOR FOR SELECT 1 AS x FROM dual;
BEGIN
  OPEN c;
  OPEN c;
EXCEPTION
  WHEN CURSOR_ALREADY_OPEN THEN
    RAISE INFO 'CURSOR_ALREADY_OPEN caught %', SQLSTATE;
END;
/
CALL test_predef_cursor_open();
DROP PROCEDURE test_predef_cursor_open;

CREATE OR REPLACE PROCEDURE test_predef_invalid_cursor IS
  c CURSOR FOR SELECT 1 AS x FROM dual;
  rc refcursor;
  v int;
BEGIN
  BEGIN
    FETCH c INTO v;
  EXCEPTION
    WHEN INVALID_CURSOR THEN
      RAISE INFO 'INVALID_CURSOR caught FETCH before OPEN %', SQLSTATE;
  END;
  BEGIN
    CLOSE c;
  EXCEPTION
    WHEN INVALID_CURSOR THEN
      RAISE INFO 'INVALID_CURSOR caught CLOSE before OPEN %', SQLSTATE;
  END;
  BEGIN
    OPEN c;
    CLOSE c;
    FETCH c INTO v;
  EXCEPTION
    WHEN INVALID_CURSOR THEN
      RAISE INFO 'INVALID_CURSOR caught FETCH after CLOSE %', SQLSTATE;
  END;
  BEGIN
    FETCH rc INTO v;
  EXCEPTION
    WHEN INVALID_CURSOR THEN
      RAISE INFO 'INVALID_CURSOR caught FETCH from unopened cursor variable %', SQLSTATE;
  END;
END;
/
CALL test_predef_invalid_cursor();
DROP PROCEDURE test_predef_invalid_cursor;

-- RAISE of a predefined name, caught by the Oracle and the PostgreSQL name
BEGIN
  RAISE ZERO_DIVIDE;
EXCEPTION
  WHEN ZERO_DIVIDE THEN
    RAISE INFO 'RAISE ZERO_DIVIDE: % %', SQLSTATE, SQLERRM;
END;
/

BEGIN
  RAISE ZERO_DIVIDE;
EXCEPTION
  WHEN division_by_zero THEN
    RAISE INFO 'division_by_zero caught RAISE ZERO_DIVIDE';
END;
/

BEGIN
  BEGIN
    RAISE VALUE_ERROR;
  EXCEPTION WHEN VALUE_ERROR THEN
    RAISE INFO 'RAISE VALUE_ERROR: %', SQLSTATE;
  END;
  BEGIN
    RAISE INVALID_CURSOR;
  EXCEPTION WHEN INVALID_CURSOR THEN
    RAISE INFO 'RAISE INVALID_CURSOR: %', SQLSTATE;
  END;
  BEGIN
    RAISE STORAGE_ERROR;
  EXCEPTION WHEN STORAGE_ERROR THEN
    RAISE INFO 'RAISE STORAGE_ERROR: %', SQLSTATE;
  END;
  BEGIN
    RAISE PROGRAM_ERROR;
  EXCEPTION WHEN PROGRAM_ERROR THEN
    RAISE INFO 'RAISE PROGRAM_ERROR: %', SQLSTATE;
  END;
END;
/

-- A predefined name only catches its own errors
BEGIN
  INSERT INTO test_predef_t VALUES (1);
EXCEPTION
  WHEN ZERO_DIVIDE OR VALUE_ERROR THEN
    RAISE INFO 'wrong handler';
  WHEN OTHERS THEN
    RAISE INFO 'OTHERS caught %', SQLSTATE;
END;
/

-- Unhandled predefined exception
BEGIN
  RAISE DUP_VAL_ON_INDEX;
END;
/

DROP TABLE test_predef_t;

-- Cleanup
DROP PACKAGE test_pragma_init;
DROP PACKAGE test_pragma_raise;
DROP PROCEDURE test_pragma_proc;
DROP PACKAGE test_multi_pragma;
DROP PACKAGE test_exc_pkg1;
DROP PACKAGE test_exc_pkg2;
DROP PACKAGE test_exc_pkg3;
DROP PROCEDURE test_standalone_exc;
