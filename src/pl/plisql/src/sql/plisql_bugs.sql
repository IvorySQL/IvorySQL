--
-- Test for GitHub Issue #1124: Variable Reset Bug in Nested Functions
--
-- Bug: When evaluating expressions like "v_sum := v_sum + nested_func()",
-- variables show original values instead of modified ones.
--

-- Test 1: Variable modification + nested function call in expression
-- This was the core bug - v_sum's modified value (109) was being lost
-- during expression evaluation, causing v_sum + get_30(10) to be 0 + 30 = 30
-- instead of 109 + 30 = 139
CREATE OR REPLACE FUNCTION test_bug1124_basic() RETURN NUMBER AS
    v_sum NUMBER := 99;
    v_result NUMBER;

    FUNCTION get_30(p_val NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN p_val * 3;
    END get_30;
BEGIN
    -- Modify v_sum
    v_sum := v_sum + 10;  -- v_sum = 109

    -- Expression with nested function - this was buggy
    v_result := v_sum + get_30(10);  -- Should be 109 + 30 = 139

    RETURN v_result;
END;
/

SELECT test_bug1124_basic() AS result FROM dual;
DROP FUNCTION test_bug1124_basic;

-- Test 2: Multiple expressions to ensure consistent behavior
CREATE OR REPLACE FUNCTION test_bug1124_multiple() RETURN NUMBER AS
    v_sum NUMBER := 99;
    v_temp NUMBER;

    FUNCTION get_30(p_val NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN p_val * 3;
    END get_30;
BEGIN
    v_sum := v_sum + 10;  -- v_sum = 109

    -- First expression
    v_temp := v_sum + get_30(10);  -- Should be 139

    -- Second expression (same) - should also be 139
    v_temp := v_sum + get_30(10);

    -- Third expression
    v_temp := v_sum + get_30(10);

    RETURN v_temp;
END;
/

SELECT test_bug1124_multiple() AS result FROM dual;
DROP FUNCTION test_bug1124_multiple;

-- Test 3: Nested procedure modifying parent variable + nested function in expression
CREATE OR REPLACE FUNCTION test_bug1124_proc_and_func() RETURN NUMBER AS
    v_sum NUMBER := 99;
    v_temp NUMBER;

    PROCEDURE add_val(p_val NUMBER) IS
    BEGIN
        v_sum := v_sum + p_val;
    END add_val;

    FUNCTION get_30(p_val NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN p_val * 3;
    END get_30;
BEGIN
    -- Call nested procedure to modify v_sum
    add_val(10);  -- v_sum = 109

    -- Expression with nested function
    v_temp := v_sum + get_30(10);  -- Should be 109 + 30 = 139

    RETURN v_temp;
END;
/

SELECT test_bug1124_proc_and_func() AS result FROM dual;
DROP FUNCTION test_bug1124_proc_and_func;

-- Test 4: Test with integer type (not just NUMBER)
CREATE OR REPLACE FUNCTION test_bug1124_integer() RETURN integer AS
    v_sum integer := 99;
    v_result integer;

    FUNCTION get_30(p_val integer) RETURN integer IS
    BEGIN
        RETURN p_val * 3;
    END get_30;
BEGIN
    v_sum := v_sum + 10;  -- v_sum = 109

    v_result := v_sum + get_30(10);  -- Should be 109 + 30 = 139

    RETURN v_result;
END;
/

SELECT test_bug1124_integer() AS result FROM dual;
DROP FUNCTION test_bug1124_integer;

-- Test 5: Nested function on left side of expression
CREATE OR REPLACE FUNCTION test_bug1124_order() RETURN NUMBER AS
    v_sum NUMBER := 99;
    v_temp NUMBER;

    FUNCTION get_30(p_val NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN p_val * 3;
    END get_30;
BEGIN
    v_sum := v_sum + 10;  -- v_sum = 109

    -- Nested function result on left side
    v_temp := get_30(10) + v_sum;  -- Should be 30 + 109 = 139

    RETURN v_temp;
END;
/

SELECT test_bug1124_order() AS result FROM dual;
DROP FUNCTION test_bug1124_order;

--
-- Subprograms without a pg_proc entry and track_functions
--
-- Package members and nested subprograms are called through an id that is
-- not a pg_proc OID.  With track_functions = pl or all, function usage
-- tracking looked that id up in pg_proc and failed the call with "function
-- call to dropped function".
--
SET track_functions = 'all';

CREATE OR REPLACE PACKAGE test_trackfunc_pkg IS
    FUNCTION f(p_val NUMBER) RETURN NUMBER;
    PROCEDURE p;
END;
/

CREATE OR REPLACE PACKAGE BODY test_trackfunc_pkg IS
    FUNCTION f(p_val NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN p_val + 1;
    END;
    PROCEDURE p IS
    BEGIN
        RAISE NOTICE 'test_trackfunc_pkg.p called';
    END;
END;
/

SELECT test_trackfunc_pkg.f(1) AS result FROM dual;
CALL test_trackfunc_pkg.p();

BEGIN
    test_trackfunc_pkg.p();
END;
/

DECLARE
    FUNCTION nested_f(p_val NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN p_val * 2;
    END;
BEGIN
    RAISE NOTICE 'nested_f(21) = %', nested_f(21);
END;
/

-- functions with a pg_proc entry are still tracked
CREATE OR REPLACE FUNCTION test_trackfunc_plain RETURN NUMBER IS
BEGIN
    RETURN 1;
END;
/

BEGIN;
SELECT test_trackfunc_plain() AS result FROM dual;
SELECT pg_stat_get_xact_function_calls('test_trackfunc_plain'::regproc) AS calls FROM dual;
COMMIT;

RESET track_functions;
DROP FUNCTION test_trackfunc_plain;
DROP PACKAGE test_trackfunc_pkg;
