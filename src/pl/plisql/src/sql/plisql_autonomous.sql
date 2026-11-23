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
-- Test 22: Special numeric values (NaN / Infinity) as arguments
-- Tests that values whose text output is not a valid bare SQL literal
-- (NaN, Infinity, -Infinity) survive the round trip through the
-- autonomous session.
--
CREATE OR REPLACE PROCEDURE test_special_numbers(p_id INT, p_n NUMERIC, p_f FLOAT8) AS $$
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_id,
        'numeric: ' || p_n::TEXT || ' float: ' || p_f::TEXT,
        'committed');
END;
$$ LANGUAGE plisql;
/

COMMIT;

CALL test_special_numbers(90, 'NaN'::NUMERIC, 'Infinity'::FLOAT8);
CALL test_special_numbers(91, 1.5, '-Infinity'::FLOAT8);
CALL test_special_numbers(92, 'NaN'::NUMERIC, 'NaN'::FLOAT8);
SELECT id, msg FROM autonomous_test WHERE id IN (90, 91, 92) ORDER BY id;

--
-- Test 23: Procedure with OUT parameter
-- Tests that OUT parameters of an autonomous procedure are dispatched
-- via CALL and the output value is returned to the caller.
--
CREATE OR REPLACE PROCEDURE test_out_param(IN p_id INT, OUT p_result INT) AS $$
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_id, 'out param', 'committed');
    p_result := p_id * 2;
END;
$$ LANGUAGE plisql;
/

COMMIT;

CALL test_out_param(77, NULL);
SELECT id, msg FROM autonomous_test WHERE id = 77;

--
-- Test 24: Procedure with INOUT parameter
-- Tests that INOUT values are passed in and the modified value is
-- returned through the autonomous CALL.
--
CREATE OR REPLACE PROCEDURE test_inout_param(INOUT p_value INT) AS $$
PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (p_value, 'inout param', 'committed');
    p_value := p_value + 100;
END;
$$ LANGUAGE plisql;
/

COMMIT;

CALL test_inout_param(7);
SELECT id, msg FROM autonomous_test WHERE id = 7;

--
-- Test 25: Polymorphic (ANYELEMENT) function argument
-- Tests that polymorphic parameter types are resolved against the
-- actual call argument types instead of the declared pseudo-type.
--
CREATE OR REPLACE FUNCTION test_polymorphic(p_any ANYELEMENT) RETURN TEXT AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO autonomous_test VALUES (93, 'poly: ' || p_any::TEXT, 'committed');
    RETURN p_any::TEXT;
END;
/

COMMIT;

SELECT test_polymorphic(5) AS poly_int;
SELECT test_polymorphic('poly text'::TEXT) AS poly_text;
SELECT id, msg FROM autonomous_test WHERE id = 93 ORDER BY id;

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
DROP PROCEDURE test_special_numbers(INT, NUMERIC, FLOAT8);
DROP PROCEDURE test_out_param(INT, INT);
DROP PROCEDURE test_inout_param(INT);
DROP FUNCTION test_polymorphic(ANYELEMENT);
DROP PACKAGE BODY test_pkg;
DROP PACKAGE test_pkg;
DROP TABLE autonomous_test;
