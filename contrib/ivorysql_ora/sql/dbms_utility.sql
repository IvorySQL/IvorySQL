--
-- Tests for DBMS_UTILITY package
--

-- Backtrace/call-stack frames are qualified per ivorysql.identifier_case_switch
SET ivorysql.enable_case_switch = true;
SET ivorysql.identifier_case_switch = interchange;

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

-- Test 18: FORMAT_CALL_STACK - Package procedure. The frame for a package
-- member must carry the exact owning-schema/package/routine triple.  The
-- package lives in a dedicated non-public schema so the assertion can pin
-- the schema name; a wildcard-only prefix would let a wrong or missing
-- schema qualifier pass silently.
CREATE SCHEMA callstack_ns;

CREATE OR REPLACE PACKAGE callstack_ns.test_call_stack_pkg IS
  PROCEDURE stack_caller;
END test_call_stack_pkg;
/

CREATE OR REPLACE PACKAGE BODY callstack_ns.test_call_stack_pkg IS
  PROCEDURE stack_caller IS
    v_stack VARCHAR2(4000);
  BEGIN
    v_stack := DBMS_UTILITY.FORMAT_CALL_STACK;
    IF v_stack LIKE '%CALLSTACK_NS.TEST_CALL_STACK_PKG.STACK_CALLER%'
       AND v_stack NOT LIKE '%PUBLIC.CALLSTACK_NS%' THEN
      RAISE INFO 'Call stack is package-qualified: OK';
    ELSE
      RAISE INFO 'Call stack is package-qualified: FAILED (got: %)', v_stack;
    END IF;
  END stack_caller;
END test_call_stack_pkg;
/

CALL callstack_ns.test_call_stack_pkg.stack_caller();

DROP PACKAGE callstack_ns.test_call_stack_pkg;
DROP SCHEMA callstack_ns;

-- Test 19: FORMAT_ERROR_BACKTRACE - Schema-qualified routine must not acquire a
-- spurious PUBLIC prefix.  Regression: before fix, schema_error() appeared as
-- PUBLIC.SCHEMA_ERROR instead of BUG_SCHEMA.SCHEMA_ERROR.
CREATE SCHEMA bug_schema;

CREATE OR REPLACE PROCEDURE bug_schema.schema_error IS
BEGIN
  RAISE EXCEPTION 'boom';
END;
/

CREATE OR REPLACE PROCEDURE bug_schema.schema_caller IS
  v_backtrace VARCHAR2(4000);
BEGIN
  bug_schema.schema_error();
EXCEPTION
  WHEN OTHERS THEN
    v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
    IF v_backtrace LIKE '%ORA-06512: at "BUG_SCHEMA.SCHEMA_ERROR"%' THEN
      RAISE INFO 'Backtrace has correct schema qualifier: OK';
    ELSE
      RAISE INFO 'Backtrace has correct schema qualifier: FAILED (got: %)', v_backtrace;
    END IF;
END;
/

CALL bug_schema.schema_caller();
DROP SCHEMA bug_schema CASCADE;

-- ============================================================
-- GET_TIME 与 GET_CPU_TIME 测试
-- ============================================================

-- 测试 20：内部计时函数必须保持无参数、返回 Oracle NUMBER 且为
-- VOLATILE 的包契约。
DO $$
DECLARE
  v_total INTEGER;
  v_number_results INTEGER;
  v_volatile INTEGER;
BEGIN
  SELECT count(*)
    INTO v_total
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'sys'
     AND p.proname IN ('ora_get_time', 'ora_get_cpu_time')
     AND p.pronargs = 0;

  SELECT count(*)
    INTO v_number_results
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'sys'
     AND p.proname IN ('ora_get_time', 'ora_get_cpu_time')
     AND p.pronargs = 0
     AND p.prorettype = 'sys.number'::pg_catalog.regtype;

  SELECT count(*)
    INTO v_volatile
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'sys'
     AND p.proname IN ('ora_get_time', 'ora_get_cpu_time')
     AND p.pronargs = 0
     AND p.provolatile = 'v';

  IF v_total != 2 OR v_number_results != 2 OR v_volatile != 2 THEN
    RAISE EXCEPTION 'timer helper catalog contract mismatch: %, %, %',
      v_total, v_number_results, v_volatile;
  END IF;

  RAISE INFO 'Timer helper catalog contract: OK';
END;
$$;

-- 测试 21：两个公开包函数均返回 Oracle NUMBER，且结果处于文档规定的
-- 有符号 32 位计时器范围内。
DO $$
DECLARE
  v_wall NUMBER;
  v_cpu NUMBER;
  v_wall_type TEXT;
  v_cpu_type TEXT;
BEGIN
  v_wall := DBMS_UTILITY.GET_TIME;
  v_cpu := DBMS_UTILITY.GET_CPU_TIME;

  SELECT pg_catalog.pg_typeof(sys.ora_get_time())::TEXT
    INTO v_wall_type;
  SELECT pg_catalog.pg_typeof(sys.ora_get_cpu_time())::TEXT
    INTO v_cpu_type;

  IF v_wall_type != 'sys.number' OR v_cpu_type != 'sys.number' THEN
    RAISE EXCEPTION 'timer package result type mismatch: %, %',
      v_wall_type, v_cpu_type;
  END IF;

  IF v_wall < -2147483648 OR v_wall > 2147483647 OR
     v_cpu < -2147483648 OR v_cpu > 2147483647 THEN
    RAISE EXCEPTION 'timer result outside Oracle signed range';
  END IF;

  RAISE INFO 'Timer package result type and range: OK';
END;
$$;

-- 测试 22：GET_TIME 测量实际流逝时间，而不是事务或语句时间。使用宽松
-- 下限，避免依赖调度器的精确唤醒时刻。
DO $$
DECLARE
  v_start NUMBER;
  v_finish NUMBER;
  v_elapsed NUMBER;
BEGIN
  v_start := DBMS_UTILITY.GET_TIME;
  PERFORM pg_catalog.pg_sleep(0.08);
  v_finish := DBMS_UTILITY.GET_TIME;

  IF v_finish >= v_start THEN
    v_elapsed := v_finish - v_start;
  ELSE
    v_elapsed := (2147483647 - v_start) +
                 (v_finish - (-2147483648)) + 1;
  END IF;

  IF v_elapsed < 5 THEN
    RAISE EXCEPTION 'GET_TIME did not measure elapsed wall time: %', v_elapsed;
  END IF;

  RAISE INFO 'GET_TIME elapsed wall-time contract: OK';
END;
$$;

-- 测试 23：GET_CPU_TIME 包含用户态与系统态 CPU 时间，且不会把休眠
-- 区间等同为 CPU 工作时间。
DO $$
DECLARE
  v_wall_start NUMBER;
  v_wall_finish NUMBER;
  v_cpu_start NUMBER;
  v_cpu_finish NUMBER;
  v_wall_elapsed NUMBER;
  v_cpu_elapsed NUMBER;
BEGIN
  v_wall_start := DBMS_UTILITY.GET_TIME;
  v_cpu_start := DBMS_UTILITY.GET_CPU_TIME;
  PERFORM pg_catalog.pg_sleep(0.08);
  v_cpu_finish := DBMS_UTILITY.GET_CPU_TIME;
  v_wall_finish := DBMS_UTILITY.GET_TIME;

  IF v_wall_finish >= v_wall_start THEN
    v_wall_elapsed := v_wall_finish - v_wall_start;
  ELSE
    v_wall_elapsed := (2147483647 - v_wall_start) +
                     (v_wall_finish - (-2147483648)) + 1;
  END IF;

  IF v_cpu_finish >= v_cpu_start THEN
    v_cpu_elapsed := v_cpu_finish - v_cpu_start;
  ELSE
    v_cpu_elapsed := (2147483647 - v_cpu_start) +
                    (v_cpu_finish - (-2147483648)) + 1;
  END IF;

  IF v_cpu_elapsed > v_wall_elapsed THEN
    RAISE EXCEPTION 'sleep consumed more CPU than wall time: CPU %, wall %',
      v_cpu_elapsed, v_wall_elapsed;
  END IF;

  RAISE INFO 'GET_CPU_TIME excludes sleeping wall time: OK';
END;
$$;

-- 测试 24：CPU 密集型工作必须最终使 GET_CPU_TIME 按百分之一秒精度推进。
-- 即使实现退化为常量，采样上限也能保证循环终止。
DO $$
DECLARE
  v_start NUMBER;
  v_finish NUMBER;
  v_elapsed NUMBER;
  v_checksum NUMBER := 0;
  v_iterations INTEGER := 0;
BEGIN
  v_start := DBMS_UTILITY.GET_CPU_TIME;
  v_finish := v_start;

  FOR i IN 1..2000000 LOOP
    v_checksum := MOD(v_checksum + i, 1000003);
    v_iterations := i;

    IF MOD(i, 1000) = 0 THEN
      v_finish := DBMS_UTILITY.GET_CPU_TIME;
      EXIT WHEN v_finish != v_start;
    END IF;
  END LOOP;

  IF v_finish >= v_start THEN
    v_elapsed := v_finish - v_start;
  ELSE
    v_elapsed := (2147483647 - v_start) +
                 (v_finish - (-2147483648)) + 1;
  END IF;

  IF v_elapsed < 1 OR v_iterations <= 0 OR v_checksum < 0 THEN
    RAISE EXCEPTION 'GET_CPU_TIME did not advance during CPU work';
  END IF;

  RAISE INFO 'GET_CPU_TIME CPU-work contract: OK';
END;
$$;

-- 测试 25：计时函数可在存储函数内使用，覆盖 Oracle 应用中通过两次
-- 采样统计代码耗时的常见模式。
CREATE OR REPLACE FUNCTION test_dbms_utility_timers RETURN BOOLEAN AS
  v_wall_start NUMBER;
  v_wall_finish NUMBER;
  v_cpu_start NUMBER;
  v_cpu_finish NUMBER;
BEGIN
  v_wall_start := DBMS_UTILITY.GET_TIME;
  v_cpu_start := DBMS_UTILITY.GET_CPU_TIME;
  v_wall_finish := DBMS_UTILITY.GET_TIME;
  v_cpu_finish := DBMS_UTILITY.GET_CPU_TIME;

  RETURN v_wall_start IS NOT NULL AND
         v_wall_finish IS NOT NULL AND
         v_cpu_start IS NOT NULL AND
         v_cpu_finish IS NOT NULL;
END;
/

DO $$
BEGIN
  IF NOT test_dbms_utility_timers() THEN
    RAISE EXCEPTION 'timer function returned NULL in stored function';
  END IF;

  RAISE INFO 'Timers in stored function: OK';
END;
$$;

DROP FUNCTION test_dbms_utility_timers;

RESET ivorysql.identifier_case_switch;
RESET ivorysql.enable_case_switch;
