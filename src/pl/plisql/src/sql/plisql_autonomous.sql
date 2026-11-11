--
-- Test PRAGMA AUTONOMOUS_TRANSACTION
--
-- This test verifies autonomous transaction functionality using dblink
--

-- Setup: Enable Oracle mode and install dblink
CREATE EXTENSION IF NOT EXISTS dblink;

-- Create test table
CREATE TABLE autonomous_test (
    id INT,
    msg TEXT,
    tx_state TEXT DEFAULT 'unknown'
);

--
-- Test 1: Basic autonomous transaction (no parameters)
--
CREATE OR REPLACE PROCEDURE test_basic AS $$
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (1, 'basic test', 'committed');
END;
$$ LANGUAGE plisql;
/

-- Must commit procedure before calling it
COMMIT;

CALL test_basic();
SELECT id, msg, tx_state FROM autonomous_test WHERE id = 1;

--
-- Test 2: Autonomous transaction with parameters
--
CREATE OR REPLACE PROCEDURE test_with_params(p_id INT, p_msg TEXT) AS $$
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_id, p_msg, 'committed');
END;
$$ LANGUAGE plisql;
/

COMMIT;

CALL test_with_params(2, 'with params');
SELECT id, msg, tx_state FROM autonomous_test WHERE id = 2;

--
-- Test 3: Transaction isolation - autonomous commit survives outer rollback
--
CREATE OR REPLACE PROCEDURE test_isolation(p_id INT) AS $$
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_id, 'autonomous', 'committed');
END;
$$ LANGUAGE plisql;
/

COMMIT;

-- Start a transaction and rollback
BEGIN;
    INSERT INTO autonomous_test VALUES (100, 'before autonomous', 'rolled back');
    CALL test_isolation(200);
    INSERT INTO autonomous_test VALUES (300, 'after autonomous', 'rolled back');
ROLLBACK;

-- Verify: Only id=200 should exist (100 and 300 rolled back)
SELECT id, msg, tx_state FROM autonomous_test WHERE id >= 100 ORDER BY id;

--
-- Test 4: Multiple parameters with different types
--
CREATE OR REPLACE PROCEDURE test_multi_types(
    p_int INT,
    p_text TEXT,
    p_bool BOOLEAN
) AS $$
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (
        p_int,
        p_text || ' (bool=' || p_bool::TEXT || ')',
        'committed'
    );
END;
$$ LANGUAGE plisql;
/

COMMIT;

CALL test_multi_types(4, 'multi-type', true);
SELECT id, msg FROM autonomous_test WHERE id = 4;

--
-- Test 5: NULL parameter handling
--
CREATE OR REPLACE PROCEDURE test_nulls(p_id INT, p_msg TEXT) AS $$
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_id, COALESCE(p_msg, 'NULL msg'), 'committed');
END;
$$ LANGUAGE plisql;
/

COMMIT;

CALL test_nulls(5, NULL);
SELECT id, msg FROM autonomous_test WHERE id = 5;

--
-- Test 6: Multiple sequential autonomous calls
--
CREATE OR REPLACE PROCEDURE test_sequential(p_id INT) AS $$
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_id, 'sequential', 'committed');
END;
$$ LANGUAGE plisql;
/

COMMIT;

CALL test_sequential(6);
CALL test_sequential(7);
CALL test_sequential(8);

SELECT id, msg FROM autonomous_test WHERE id IN (6, 7, 8) ORDER BY id;

--
-- Test 7: Error handling - missing dblink should give clear error
--
-- Note: We can't actually test this because dblink is already installed,
-- but the error message would be:
-- ERROR: dblink_exec function not found
-- HINT: Install dblink extension: CREATE EXTENSION dblink

--
-- Test 8: Verify transaction isolation - autonomous changes persist
--
TRUNCATE autonomous_test;

CREATE OR REPLACE PROCEDURE test_persist(p_id INT) AS $$
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_id, 'should persist', 'committed');
END;
$$ LANGUAGE plisql;
/

COMMIT;

-- Outer transaction that will rollback
BEGIN;
    INSERT INTO autonomous_test VALUES (1000, 'will rollback', 'rolled back');
    CALL test_persist(2000);
    INSERT INTO autonomous_test VALUES (3000, 'will rollback', 'rolled back');

    -- Check within transaction - both should be visible
    SELECT COUNT(*) AS count_in_tx FROM autonomous_test;
ROLLBACK;

-- After rollback - only autonomous insert should remain
SELECT id, msg, tx_state FROM autonomous_test ORDER BY id;

--
-- Test 9: Extension drop/recreate - verify OID invalidation works
--
CREATE OR REPLACE PROCEDURE test_oid_invalidation(p_id INT) AS $$
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_id, 'oid test', 'committed');
END;
$$ LANGUAGE plisql;
/

COMMIT;

-- Call once to cache the OID
CALL test_oid_invalidation(9);

-- Drop and recreate dblink extension (OID will change)
DROP EXTENSION dblink CASCADE;
CREATE EXTENSION dblink;

-- Call again - should work with new OID (tests invalidation callback)
CALL test_oid_invalidation(10);

-- Verify both calls succeeded
SELECT id, msg FROM autonomous_test WHERE id IN (9, 10) ORDER BY id;

--
-- Test 10: Autonomous function with return value
--
CREATE OR REPLACE FUNCTION test_function_return(p_input INT) RETURN INT AS $$
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_result INT;
BEGIN
    v_result := p_input * 2;
    INSERT INTO autonomous_test VALUES (p_input, 'function test', 'committed');
    RETURN v_result;
END;
$$ LANGUAGE plisql;
/

COMMIT;

-- Call function and verify return value
SELECT test_function_return(50) AS doubled_value;

-- Verify the function also did the insert
SELECT id, msg FROM autonomous_test WHERE id = 50;

--
-- Test 11: Autonomous function with NULL return
--
CREATE OR REPLACE FUNCTION test_function_null() RETURN TEXT AS $$
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (51, 'null return test', 'committed');
    RETURN NULL;
END;
$$ LANGUAGE plisql;
/

COMMIT;

SELECT test_function_null() AS null_result;
SELECT id, msg FROM autonomous_test WHERE id = 51;

--
-- Test 12: Explicit COMMIT in autonomous transaction (EXPECTED TO FAIL)
-- Reference: https://github.com/IvorySQL/IvorySQL/issues/985
-- PL/iSQL does not support COMMIT/ROLLBACK in procedures
--
/*
CREATE OR REPLACE PROCEDURE test_explicit_commit(p_id INT) AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_id, 'explicit commit', 'committed');
    COMMIT;  -- Would fail: ERROR: invalid transaction termination
END;
/

CALL test_explicit_commit(60);
*/

--
-- Test 13: Explicit ROLLBACK in autonomous transaction (EXPECTED TO FAIL)
-- Reference: https://github.com/IvorySQL/IvorySQL/issues/985
-- PL/iSQL does not support COMMIT/ROLLBACK in procedures
--
/*
CREATE OR REPLACE PROCEDURE test_explicit_rollback(p_id INT) AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_id, 'should rollback', 'rolled back');
    ROLLBACK;  -- Would fail: ERROR: invalid transaction termination
    INSERT INTO autonomous_test VALUES (p_id + 1, 'after rollback', 'committed');
END;
/

CALL test_explicit_rollback(70);
-- Expected: id=71 survives, id=70 rolled back (if it worked)
-- Actual: ERROR: invalid transaction termination
*/

--
-- Test 14: Conditional transaction control (EXPECTED TO FAIL)
-- Reference: https://github.com/IvorySQL/IvorySQL/issues/985
-- This pattern is common in Oracle but not supported in PL/iSQL
--
/*
CREATE OR REPLACE PROCEDURE test_conditional_tx(p_id INT, p_should_commit BOOLEAN) AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_id, 'conditional', 'unknown');

    IF p_should_commit THEN
        COMMIT;  -- Would fail: ERROR: invalid transaction termination
    ELSE
        ROLLBACK;  -- Would fail: ERROR: invalid transaction termination
    END IF;
END;
/

CALL test_conditional_tx(80, true);
CALL test_conditional_tx(81, false);
*/

--
-- Test 15: Error handling in autonomous function (triggers SPI error recovery)
--
CREATE OR REPLACE FUNCTION test_function_error() RETURN INT AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    -- This will fail because nonexistent_table doesn't exist
    -- Tests PG_CATCH cleanup (pfree and SPI_finish)
    INSERT INTO nonexistent_table VALUES (999);
    RETURN 1;
END;
/

COMMIT;

-- This should fail gracefully with proper error message
-- \set ON_ERROR_STOP off
SELECT test_function_error();
-- \set ON_ERROR_STOP on

--
-- Test 16: Function with pass-by-reference return type
-- Tests datumCopy() for complex types
--
CREATE OR REPLACE FUNCTION test_function_text(p_prefix TEXT) RETURN TEXT AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_result TEXT;
BEGIN
    v_result := p_prefix || ' - processed';
    INSERT INTO autonomous_test VALUES (52, v_result, 'committed');
    RETURN v_result;
END;
/

COMMIT;

SELECT test_function_text('test data') AS text_result;
SELECT id, msg FROM autonomous_test WHERE id = 52;

--
-- Test 17: Nested autonomous function calls
-- Tests multiple SPI contexts
--
CREATE OR REPLACE FUNCTION inner_function(p_value INT) RETURN INT AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_value, 'inner function', 'committed');
    RETURN p_value + 10;
END;
/

CREATE OR REPLACE FUNCTION outer_function(p_value INT) RETURN INT AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_inner_result INT;
BEGIN
    INSERT INTO autonomous_test VALUES (p_value, 'outer function', 'committed');
    v_inner_result := inner_function(p_value + 100);
    RETURN v_inner_result + 5;
END;
/

COMMIT;

-- Should insert at id=60 (outer) and id=160 (inner), return 175 (160+10+5)
SELECT outer_function(60) AS nested_result;
SELECT id, msg FROM autonomous_test WHERE id IN (60, 160) ORDER BY id;

--
-- Test 18: Function returning NUMERIC (pass-by-reference, variable length)
-- Tests datumCopy() with NUMERIC type
--
CREATE OR REPLACE FUNCTION test_function_numeric(p_amount NUMERIC) RETURN NUMERIC AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_result NUMERIC;
BEGIN
    v_result := p_amount * 1.15;  -- Add 15% tax
    INSERT INTO autonomous_test VALUES (53, 'numeric: ' || v_result::TEXT, 'committed');
    RETURN v_result;
END;
/

COMMIT;

SELECT test_function_numeric(100.50) AS numeric_result;
SELECT id, msg FROM autonomous_test WHERE id = 53;

--
-- Test 19: Function returning DATE (pass-by-value)
-- Tests date type handling
--
CREATE OR REPLACE FUNCTION test_function_date(p_base_date DATE, p_days_offset INT) RETURN DATE AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_result DATE;
BEGIN
    v_result := p_base_date + p_days_offset;
    INSERT INTO autonomous_test VALUES (54, 'date: ' || v_result::TEXT, 'committed');
    RETURN v_result;
END;
/

COMMIT;

-- Returns date 7 days from base date (using fixed date for deterministic test)
SELECT test_function_date('2025-01-01'::DATE, 7) AS date_result;
SELECT id, msg FROM autonomous_test WHERE id = 54;

--
-- Test 20: Function returning BOOLEAN (pass-by-value)
-- Tests boolean type handling
--
CREATE OR REPLACE FUNCTION test_function_boolean(p_value INT) RETURN BOOLEAN AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_result BOOLEAN;
BEGIN
    v_result := (p_value > 50);
    INSERT INTO autonomous_test VALUES (55, 'boolean: ' || v_result::TEXT, 'committed');
    RETURN v_result;
END;
/

COMMIT;

SELECT test_function_boolean(75) AS bool_true_result;
SELECT test_function_boolean(25) AS bool_false_result;
SELECT id, msg FROM autonomous_test WHERE id = 55 ORDER BY id;

--
-- Test 21: Autonomous transaction in package procedure
-- Tests that PRAGMA AUTONOMOUS_TRANSACTION works inside package bodies
--
CREATE OR REPLACE PACKAGE test_pkg AUTHID DEFINER AS
  PROCEDURE pkg_test_with_params(p_id INT, p_msg TEXT);
END;
/

CREATE OR REPLACE PACKAGE BODY test_pkg AS
  PROCEDURE pkg_test_with_params(p_id INT, p_msg TEXT) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO autonomous_test VALUES (p_id, p_msg, 'committed');
  END pkg_test_with_params;
END test_pkg;
/

COMMIT;

CALL test_pkg.pkg_test_with_params(76, 'package procedure test');
SELECT id, msg FROM autonomous_test WHERE id = 76;

--
-- Test 22: Package member isolation (write side)
-- The member's COMMIT must not commit the caller's transaction: the outer
-- rows are discarded by ROLLBACK while the member's row survives.
-- (PRAGMA AUTONOMOUS_TRANSACTION used to be silently ignored in package
-- members: they ran in the caller's transaction, and a COMMIT inside the
-- member terminated the caller's transaction instead.)
--
CREATE OR REPLACE PACKAGE test_pkg_iso AS
  PROCEDURE pkg_auto_insert(p_id INT);
END;
/

CREATE OR REPLACE PACKAGE BODY test_pkg_iso AS
  PROCEDURE pkg_auto_insert(p_id INT) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO autonomous_test VALUES (p_id, 'pkg-autonomous', 'committed');
  END pkg_auto_insert;
END test_pkg_iso;
/

COMMIT;

BEGIN;
    INSERT INTO autonomous_test VALUES (101, 'outer-before-pkg', 'rolled back');
    CALL test_pkg_iso.pkg_auto_insert(201);
    INSERT INTO autonomous_test VALUES (301, 'outer-after-pkg', 'rolled back');
ROLLBACK;

-- Verify: of this transaction's rows only id=201 survives the caller's
-- rollback (ids 160 and 2000 in the same range come from earlier tests).
SELECT id, msg, tx_state FROM autonomous_test WHERE id >= 100 ORDER BY id;

--
-- Test 23: Package member isolation (read side)
-- The member must not see the caller's uncommitted changes.
--
CREATE OR REPLACE PACKAGE test_pkg_isoread AS
  PROCEDURE pkg_auto_count(p_id INT);
END;
/

CREATE OR REPLACE PACKAGE BODY test_pkg_isoread AS
  PROCEDURE pkg_auto_count(p_id INT) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO autonomous_test
      VALUES (p_id, (SELECT count(*)::text FROM autonomous_test), 'committed');
  END pkg_auto_count;
END test_pkg_isoread;
/

COMMIT;

BEGIN;
    INSERT INTO autonomous_test VALUES (999, 'uncommitted-outer', 'rolled back');
    CALL test_pkg_isoread.pkg_auto_count(202);
ROLLBACK;

-- Verify: id=202 records the count of committed rows only — the member
-- does not see the caller's uncommitted id=999, and that row is rolled
-- back afterwards as well.
SELECT id, msg, tx_state FROM autonomous_test WHERE id >= 200 ORDER BY id;

--
-- Test 24: Autonomous package function returns its value
--
CREATE OR REPLACE PACKAGE test_pkg_func AS
  FUNCTION pkg_auto_func(p_id INT) RETURN INT;
  FUNCTION pkg_auto_func(p_id VARCHAR2) RETURN VARCHAR2;
END;
/

CREATE OR REPLACE PACKAGE BODY test_pkg_func AS
  FUNCTION pkg_auto_func(p_id INT) RETURN INT AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO autonomous_test VALUES (4242, 'pkg-function', 'committed');
    RETURN p_id * 2;
  END pkg_auto_func;
  FUNCTION pkg_auto_func(p_id VARCHAR2) RETURN VARCHAR2 AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    RETURN COALESCE(p_id, 'varchar2 overload');
  END pkg_auto_func;
END test_pkg_func;
/

COMMIT;

-- The function must run autonomously: its insert survives the caller's
-- rollback even though the call itself was made inside the transaction.
BEGIN;
SELECT test_pkg_func.pkg_auto_func(21) AS pkg_func_result;
ROLLBACK;
SELECT id, msg, tx_state FROM autonomous_test WHERE id = 4242;
-- A typed NULL must resolve to the INT overload through the autonomous
-- call builder (with the VARCHAR2 overload present, a bare NULL would be
-- ambiguous).
SELECT test_pkg_func.pkg_auto_func(NULL::INT) AS pkg_func_null_result;
-- Oracle-typed arguments must render with a type name the far session's
-- parser resolves (sys.oravarcharchar, not the "varchar2" display name).
SELECT test_pkg_func.pkg_auto_func(NULL::VARCHAR2) AS pkg_func_varchar2_null_result;
SELECT test_pkg_func.pkg_auto_func('autonomous') AS pkg_func_varchar2_result;

--
-- Test 25: A member that is only defined in the package body cannot be
-- re-invoked in an autonomous session: fail clearly instead of silently
-- running in the caller's transaction.
--
CREATE OR REPLACE PACKAGE test_pkg_bodyonly AS
  PROCEDURE spec_entry;
END;
/

CREATE OR REPLACE PACKAGE BODY test_pkg_bodyonly AS
  PROCEDURE body_only_auto AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO autonomous_test VALUES (500, 'must not run', 'no');
  END body_only_auto;

  PROCEDURE spec_entry AS
  BEGIN
    body_only_auto();
  END spec_entry;
END test_pkg_bodyonly;
/

COMMIT;

CALL test_pkg_bodyonly.spec_entry();
SELECT id, msg FROM autonomous_test WHERE id = 500;

--
-- Test 26: A polymorphic member (anyelement/anyarray parameters) must run
-- autonomously: the declared pseudotypes are resolved to the concrete types
-- of the actual arguments when the autonomous call is built, so the far
-- session never sees a cast to a pseudotype (which its parser rejects).
--
CREATE OR REPLACE PACKAGE test_pkg_poly AS
  FUNCTION poly_ident(x anyelement) RETURN anyelement;
  FUNCTION poly_pick(x anyarray) RETURN anyelement;
END;
/

CREATE OR REPLACE PACKAGE BODY test_pkg_poly AS
  FUNCTION poly_ident(x anyelement) RETURN anyelement AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    RETURN x;
  END poly_ident;

  FUNCTION poly_pick(x anyarray) RETURN anyelement AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    RETURN x[1];
  END poly_pick;
END test_pkg_poly;
/

COMMIT;

SELECT test_pkg_poly.poly_ident(42) AS poly_int_result;
SELECT test_pkg_poly.poly_ident('hello'::TEXT) AS poly_text_result;
SELECT test_pkg_poly.poly_ident(NULL::INT) AS poly_null_result;
SELECT test_pkg_poly.poly_pick(ARRAY[7,8,9]) AS poly_array_result;

--
-- Test 27: Numeric argument values whose unquoted rendering would not
-- survive the far parser: float special values (NaN, Infinity — an
-- unquoted NaN would be read as a column reference) and the negative
-- int2 minimum (-32768 — unquoted, the cast would bind before the unary
-- minus and overflow).  Every value is rendered quoted with its cast, so
-- the far call sees the exact local value.
--
CREATE OR REPLACE PACKAGE test_pkg_num AS
  FUNCTION num_echo(x FLOAT8) RETURN FLOAT8;
  FUNCTION int2_echo(x INT2) RETURN INT2;
END;
/

CREATE OR REPLACE PACKAGE BODY test_pkg_num AS
  FUNCTION num_echo(x FLOAT8) RETURN FLOAT8 AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    RETURN x;
  END num_echo;

  FUNCTION int2_echo(x INT2) RETURN INT2 AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    RETURN x;
  END int2_echo;
END test_pkg_num;
/

COMMIT;

SELECT test_pkg_num.num_echo('NaN'::FLOAT8) AS nan_result;
SELECT test_pkg_num.num_echo('Infinity'::FLOAT8) AS infinity_result;
SELECT test_pkg_num.num_echo('-Infinity'::FLOAT8) AS neg_infinity_result;
SELECT test_pkg_num.int2_echo((-32768)::INT2) AS int2_min_result;
SELECT test_pkg_num.int2_echo(32767::INT2) AS int2_max_result;

--
-- Summary: Show all test results
--
SELECT 'All autonomous transaction tests completed' AS status;

-- Cleanup
DROP PROCEDURE test_basic();
DROP PROCEDURE test_with_params(INT, TEXT);
DROP PROCEDURE test_isolation(INT);
DROP PROCEDURE test_multi_types(INT, TEXT, BOOLEAN);
DROP PROCEDURE test_nulls(INT, TEXT);
DROP PROCEDURE test_sequential(INT);
DROP PROCEDURE test_persist(INT);
DROP PROCEDURE test_oid_invalidation(INT);
DROP FUNCTION test_function_return(INT);
DROP FUNCTION test_function_null();
DROP FUNCTION test_function_error();
DROP FUNCTION test_function_text(TEXT);
DROP FUNCTION inner_function(INT);
DROP FUNCTION outer_function(INT);
DROP FUNCTION test_function_numeric(NUMERIC);
DROP FUNCTION test_function_date(DATE, INT);
DROP FUNCTION test_function_boolean(INT);
DROP PACKAGE BODY test_pkg;
DROP PACKAGE test_pkg;
DROP PACKAGE BODY test_pkg_iso;
DROP PACKAGE test_pkg_iso;
DROP PACKAGE BODY test_pkg_isoread;
DROP PACKAGE test_pkg_isoread;
DROP PACKAGE BODY test_pkg_func;
DROP PACKAGE test_pkg_func;
DROP PACKAGE BODY test_pkg_bodyonly;
DROP PACKAGE test_pkg_bodyonly;
DROP PACKAGE BODY test_pkg_poly;
DROP PACKAGE test_pkg_poly;
DROP PACKAGE BODY test_pkg_num;
DROP PACKAGE test_pkg_num;
DROP TABLE autonomous_test;
