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
-- Test 11e: PRAGMA EXCEPTION_INIT maps the error number to an SQLSTATE (issue #3097)
-- A number with a PostgreSQL counterpart catches that error, and RAISE uses
-- its SQLSTATE.  Any other number gets an SQLSTATE of its own in class O.
--
CREATE TABLE test_pragma_map_t (id int PRIMARY KEY);

CREATE OR REPLACE PROCEDURE test_pragma_map IS
  e_zero EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_zero, -1476);
  e_dup EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_dup, -1);
  e_value EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_value, -6502);
  e_nodata EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_nodata, 100);
  e_app EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_app, -20001);
  e_app2 EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_app2, -20002);
  n NUMBER;
  v VARCHAR2(3);
BEGIN
  BEGIN
    n := 1 / 0;
  EXCEPTION
    WHEN e_zero THEN
      RAISE INFO 'e_zero caught division by zero: %', SQLSTATE;
  END;

  BEGIN
    RAISE e_zero;
  EXCEPTION
    WHEN division_by_zero THEN
      RAISE INFO 'RAISE e_zero is division_by_zero: %', SQLSTATE;
  END;

  BEGIN
    INSERT INTO test_pragma_map_t VALUES (1);
    INSERT INTO test_pragma_map_t VALUES (1);
  EXCEPTION
    WHEN e_dup THEN
      RAISE INFO 'e_dup caught unique violation: %', SQLSTATE;
  END;

  -- -1 must not turn into a catch-all handler
  BEGIN
    BEGIN
      n := 1 / 0;
    EXCEPTION
      WHEN e_dup THEN
        RAISE INFO 'wrong: e_dup caught division by zero';
    END;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE INFO 'e_dup let division by zero through: %', SQLSTATE;
  END;

  BEGIN
    v := 'abcd';
  EXCEPTION
    WHEN e_value THEN
      RAISE INFO 'e_value caught string truncation: %', SQLSTATE;
  END;

  BEGIN
    n := 'abc';
  EXCEPTION
    WHEN e_value THEN
      RAISE INFO 'e_value caught invalid number text: %', SQLSTATE;
  END;

  BEGIN
    RAISE no_data_found;
  EXCEPTION
    WHEN e_nodata THEN
      RAISE INFO 'e_nodata caught no_data_found: %', SQLSTATE;
  END;

  BEGIN
    RAISE e_app;
  EXCEPTION
    WHEN e_app2 THEN
      RAISE INFO 'wrong: e_app2 caught e_app';
    WHEN e_app THEN
      RAISE INFO 'e_app caught: %', SQLSTATE;
  END;
END;
/

CALL test_pragma_map();

DROP PROCEDURE test_pragma_map;
DROP TABLE test_pragma_map_t;

--
-- Test 11f: SQLCODE in exception handlers (issue #3099)
--
CREATE OR REPLACE PROCEDURE test_sqlcode IS
  e_user EXCEPTION;
  e_app EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_app, -20001);
  e_far EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_far, -1000000);
  n NUMBER;
BEGIN
  BEGIN
    n := 1 / 0;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE INFO 'division by zero: SQLCODE %', SQLCODE;
  END;

  BEGIN
    RAISE no_data_found;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE INFO 'no_data_found: SQLCODE %', SQLCODE;
  END;

  BEGIN
    EXECUTE 'SELECT * FROM test_sqlcode_no_such_table';
  EXCEPTION
    WHEN OTHERS THEN
      RAISE INFO 'undefined table: SQLCODE %', SQLCODE;
  END;

  BEGIN
    RAISE e_user;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE INFO 'user-defined exception: SQLCODE %', SQLCODE;
  END;

  BEGIN
    RAISE e_app;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE INFO 'EXCEPTION_INIT -20001: SQLCODE % SQLSTATE %', SQLCODE, SQLSTATE;
  END;

  BEGIN
    RAISE e_far;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE INFO 'EXCEPTION_INIT -1000000: SQLCODE % SQLSTATE %', SQLCODE, SQLSTATE;
  END;

  -- no Oracle number: positive, like Oracle's non-Oracle exceptions
  BEGIN
    RAISE invalid_parameter_value;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE INFO 'invalid_parameter_value: SQLCODE % SQLSTATE %', SQLCODE, SQLSTATE;
  END;

  BEGIN
    BEGIN
      n := 1 / 0;
    EXCEPTION
      WHEN OTHERS THEN
        RAISE e_app;
    END;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE INFO 'outer handler: SQLCODE % (%)', SQLCODE, SQLERRM;
  END;
END;
/

CALL test_sqlcode();

DROP PROCEDURE test_sqlcode;

-- SQLCODE in a package initialization block
CREATE OR REPLACE PACKAGE test_sqlcode_pkg IS
  last_code NUMBER;
  PROCEDURE show_code;
END test_sqlcode_pkg;
/

CREATE OR REPLACE PACKAGE BODY test_sqlcode_pkg IS
  PROCEDURE show_code IS
  BEGIN
    RAISE INFO 'package init block saw SQLCODE %', last_code;
  END show_code;
BEGIN
  last_code := 1 / 0;
EXCEPTION
  WHEN OTHERS THEN
    last_code := SQLCODE;
END test_sqlcode_pkg;
/

BEGIN
  test_sqlcode_pkg.show_code();
END;
/

DROP PACKAGE test_sqlcode_pkg;

--
-- Test 11g: package exceptions named as pkg.exc in WHEN and RAISE (issue #3100)
--
CREATE OR REPLACE PACKAGE test_pkg_exc IS
  e_plain EXCEPTION;
  e_init EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_init, -20010);
  counter NUMBER := 0;
  PROCEDURE raise_plain;
  PROCEDURE raise_init;
END test_pkg_exc;
/

CREATE OR REPLACE PACKAGE BODY test_pkg_exc IS
  PROCEDURE raise_plain IS
  BEGIN
    RAISE e_plain;
  END raise_plain;

  PROCEDURE raise_init IS
  BEGIN
    RAISE test_pkg_exc.e_init;
  EXCEPTION
    WHEN test_pkg_exc.e_plain THEN
      RAISE INFO 'raise_init: wrong handler';
  END raise_init;
END test_pkg_exc;
/

CREATE OR REPLACE PROCEDURE test_pkg_exc_caller IS
BEGIN
  BEGIN
    test_pkg_exc.raise_plain;
  EXCEPTION
    WHEN test_pkg_exc.e_init THEN
      RAISE INFO 'raise_plain: wrong handler';
    WHEN test_pkg_exc.e_plain THEN
      RAISE INFO 'raise_plain: caught by WHEN test_pkg_exc.e_plain, SQLCODE %', SQLCODE;
  END;

  BEGIN
    test_pkg_exc.raise_init;
  EXCEPTION
    WHEN test_pkg_exc.e_init THEN
      RAISE INFO 'raise_init: caught by WHEN test_pkg_exc.e_init, SQLCODE %', SQLCODE;
  END;

  BEGIN
    RAISE test_pkg_exc.e_init;
  EXCEPTION
    WHEN public.test_pkg_exc.e_plain OR public.test_pkg_exc.e_init THEN
      RAISE INFO 'RAISE test_pkg_exc.e_init: caught by WHEN public.test_pkg_exc.e_init, SQLSTATE %', SQLSTATE;
  END;
END;
/

CALL test_pkg_exc_caller();

-- a package exception that is not handled
BEGIN
  RAISE test_pkg_exc.e_plain;
END;
/

-- a package variable or a missing name is not an exception
BEGIN
  NULL;
EXCEPTION
  WHEN test_pkg_exc.counter THEN
    NULL;
END;
/

BEGIN
  NULL;
EXCEPTION
  WHEN test_pkg_exc.no_such_exc THEN
    NULL;
END;
/

DROP PROCEDURE test_pkg_exc_caller;
DROP PACKAGE test_pkg_exc;

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

-- Cleanup
DROP PACKAGE test_pragma_init;
DROP PACKAGE test_pragma_raise;
DROP PROCEDURE test_pragma_proc;
DROP PACKAGE test_multi_pragma;
DROP PACKAGE test_exc_pkg1;
DROP PACKAGE test_exc_pkg2;
DROP PACKAGE test_exc_pkg3;
DROP PROCEDURE test_standalone_exc;
