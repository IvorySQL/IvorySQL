--
-- Test implicit RECORD declaration in FOR loops (Oracle compatibility)
--

-- Setup test table
CREATE TABLE test_loop_data (
  id NUMBER,
  name VARCHAR2(50),
  amount NUMBER
);

INSERT INTO test_loop_data VALUES (1, 'Item A', 100);
INSERT INTO test_loop_data VALUES (2, 'Item B', 200);
INSERT INTO test_loop_data VALUES (3, 'Item C', 300);

-- Test 1: Simple FOR loop with implicit cursor variable
-- Oracle: cr is implicitly declared as RECORD
-- Expected: Should work (currently fails)
DECLARE
  total NUMBER := 0;
BEGIN
  FOR cr IN (SELECT id, name, amount FROM test_loop_data ORDER BY id) LOOP
    RAISE INFO 'Processing: id=%, name=%, amount=%', cr.id, cr.name, cr.amount;
    total := total + cr.amount;
  END LOOP;
  RAISE INFO 'Total amount: %', total;
END;
/

-- Test 2: FOR loop with different cursor variable name
DECLARE
  count_val NUMBER := 0;
BEGIN
  FOR rec IN (SELECT name FROM test_loop_data ORDER BY id) LOOP
    count_val := count_val + 1;
    RAISE INFO 'Row %: %', count_val, rec.name;
  END LOOP;
END;
/

-- Test 3: Nested FOR loops with implicit variables
BEGIN
  FOR outer_rec IN (SELECT id, name FROM test_loop_data WHERE id <= 2 ORDER BY id) LOOP
    RAISE INFO 'Outer: id=%, name=%', outer_rec.id, outer_rec.name;
    FOR inner_rec IN (SELECT amount FROM test_loop_data WHERE id = outer_rec.id) LOOP
      RAISE INFO '  Inner: amount=%', inner_rec.amount;
    END LOOP;
  END LOOP;
END;
/

-- Test 4: Implicit cursor in package procedure
CREATE OR REPLACE PACKAGE test_implicit_pkg IS
  PROCEDURE process_data;
END test_implicit_pkg;
/

CREATE OR REPLACE PACKAGE BODY test_implicit_pkg IS
  PROCEDURE process_data IS
    counter NUMBER := 0;
  BEGIN
    FOR item IN (SELECT id, name, amount FROM test_loop_data ORDER BY id) LOOP
      counter := counter + 1;
      RAISE INFO 'Item %: id=%, name=%, amount=%', counter, item.id, item.name, item.amount;
    END LOOP;
    RAISE INFO 'Processed % items', counter;
  END process_data;
END test_implicit_pkg;
/

-- Execute the package procedure
BEGIN
  test_implicit_pkg.process_data();
END;
/

-- Test 5: Multiple FOR loops reusing same variable name (different scope)
DECLARE
  sum1 NUMBER := 0;
  sum2 NUMBER := 0;
BEGIN
  FOR cr IN (SELECT amount FROM test_loop_data WHERE id <= 2) LOOP
    sum1 := sum1 + cr.amount;
  END LOOP;
  RAISE INFO 'First loop sum: %', sum1;

  -- cr should be implicitly declared again in this scope
  FOR cr IN (SELECT amount FROM test_loop_data WHERE id > 2) LOOP
    sum2 := sum2 + cr.amount;
  END LOOP;
  RAISE INFO 'Second loop sum: %', sum2;
END;
/

-- Test 6: Verify cursor variable doesn't leak outside loop
DECLARE
  x NUMBER;
BEGIN
  FOR loop_var IN (SELECT id FROM test_loop_data WHERE id = 1) LOOP
    x := loop_var.id;
  END LOOP;
  -- This should fail: loop_var not visible here
  RAISE INFO 'Value: %', loop_var.id;
END;
/

-- Test 7: FOR loop variable colliding with a package scalar variable.
-- Oracle semantics: the loop variable is implicitly local to the loop, so
-- the package variable must keep its value.  (Before the fix, the loop
-- silently overwrote the package variable with column data on each
-- iteration, and every other member then read the corrupted value.)
CREATE OR REPLACE PACKAGE test_loop_shadow_pkg AS
  g_config NUMBER := 50;
  PROCEDURE run_loop;
  FUNCTION get_config RETURN NUMBER;
END;
/
CREATE OR REPLACE PACKAGE BODY test_loop_shadow_pkg AS
  PROCEDURE run_loop IS
  BEGIN
    FOR g_config IN (SELECT amount FROM test_loop_data ORDER BY id) LOOP
      RAISE INFO 'loop sees amount=%', g_config.amount;
    END LOOP;
  END;
  FUNCTION get_config RETURN NUMBER IS
  BEGIN
    RETURN g_config;
  END;
END;
/
BEGIN
  test_loop_shadow_pkg.run_loop();
END;
/
SELECT 'T7 package scalar after loop', test_loop_shadow_pkg.get_config() FROM dual;

-- Test 8: FOR loop variable colliding with a package RECORD variable.
-- Before the fix, the loop restructured the package's declared record to
-- the shape of the query's row, so other members failed at runtime with
-- "record ... has no field ..." when the query selected fewer columns.
CREATE OR REPLACE PACKAGE test_loop_shadow_rec AS
  TYPE t_rec IS RECORD (a NUMBER, b VARCHAR2(50));
  g_rec t_rec;
  PROCEDURE run_loop;
  FUNCTION get_a RETURN NUMBER;
  FUNCTION get_b RETURN VARCHAR2;
END;
/
CREATE OR REPLACE PACKAGE BODY test_loop_shadow_rec AS
  PROCEDURE run_loop IS
  BEGIN
    FOR g_rec IN (SELECT id FROM test_loop_data ORDER BY id) LOOP
      RAISE INFO 'loop sees id=%', g_rec.id;
    END LOOP;
  END;
  FUNCTION get_a RETURN NUMBER IS
  BEGIN
    RETURN g_rec.a;
  END;
  FUNCTION get_b RETURN VARCHAR2 IS
  BEGIN
    RETURN g_rec.b;
  END;
BEGIN
  g_rec.a := 1;
  g_rec.b := 'untouched';
END;
/
BEGIN
  test_loop_shadow_rec.run_loop();
END;
/
SELECT 'T8 package record after loop', test_loop_shadow_rec.get_a(), test_loop_shadow_rec.get_b() FROM dual;

-- Test 9: the same collision from the package init block, from a nested
-- subprogram, and with an explicitly declared local record as the loop
-- target (which must keep binding to the local, as before).
CREATE OR REPLACE PACKAGE test_loop_shadow_more AS
  g_init NUMBER := 9;
  g_nested NUMBER := 5;
  TYPE t_ctrl IS RECORD (amount NUMBER);
  PROCEDURE run_nested;
  PROCEDURE run_local;
  FUNCTION get_init RETURN NUMBER;
  FUNCTION get_nested RETURN NUMBER;
END;
/
CREATE OR REPLACE PACKAGE BODY test_loop_shadow_more AS
  PROCEDURE run_nested IS
    PROCEDURE inner IS
    BEGIN
      FOR g_nested IN (SELECT amount FROM test_loop_data ORDER BY id) LOOP
        RAISE INFO 'nested loop sees amount=%', g_nested.amount;
      END LOOP;
    END;
  BEGIN
    inner();
  END;
  PROCEDURE run_local IS
    loc t_ctrl;
  BEGIN
    FOR loc IN (SELECT amount FROM test_loop_data ORDER BY id) LOOP
      RAISE INFO 'local loop sees amount=%', loc.amount;
    END LOOP;
  END;
  FUNCTION get_init RETURN NUMBER IS
  BEGIN
    RETURN g_init;
  END;
  FUNCTION get_nested RETURN NUMBER IS
  BEGIN
    RETURN g_nested;
  END;
BEGIN
  FOR g_init IN (SELECT amount FROM test_loop_data ORDER BY id) LOOP
    RAISE INFO 'init loop sees amount=%', g_init.amount;
  END LOOP;
END;
/
BEGIN
  test_loop_shadow_more.run_nested();
  test_loop_shadow_more.run_local();
END;
/
SELECT 'T9 init block', test_loop_shadow_more.get_init() FROM dual;
SELECT 'T9 nested subprogram', test_loop_shadow_more.get_nested() FROM dual;

-- Test 10: FOREACH over an array with the package variable as the element
-- target.  Unlike the query/cursor/dynamic FOR loops above, FOREACH binds
-- the declared datum (that is how the loop body reads each element), so the
-- package variable keeps receiving the elements.
CREATE OR REPLACE PACKAGE test_loop_foreach_pkg AS
  g_el NUMBER := 0;
  PROCEDURE run_foreach;
  FUNCTION get_el RETURN NUMBER;
END;
/
CREATE OR REPLACE PACKAGE BODY test_loop_foreach_pkg AS
  PROCEDURE run_foreach IS
    a INT[] := ARRAY[10, 20, 30];
  BEGIN
    FOREACH g_el IN ARRAY a LOOP
      RAISE INFO 'foreach sees %', g_el;
    END LOOP;
  END;
  FUNCTION get_el RETURN NUMBER IS
  BEGIN
    RETURN g_el;
  END;
END;
/
BEGIN
  test_loop_foreach_pkg.run_foreach();
END;
/
SELECT 'T10 foreach bound target', test_loop_foreach_pkg.get_el() FROM dual;

-- Test 11: a local declared in a block nested inside the package init
-- block keeps binding as the loop target (only datums declared before the
-- init block's BEGIN are package state).
CREATE OR REPLACE PACKAGE test_loop_init_local AS
  g_seen NUMBER := 0;
  PROCEDURE run;
  FUNCTION get_seen RETURN NUMBER;
END;
/
CREATE OR REPLACE PACKAGE BODY test_loop_init_local AS
  PROCEDURE run IS
  BEGIN
    NULL;
  END;
  FUNCTION get_seen RETURN NUMBER IS
  BEGIN
    RETURN g_seen;
  END;
BEGIN
  DECLARE
    loc test_loop_shadow_more.t_ctrl;
  BEGIN
    FOR loc IN (SELECT amount FROM test_loop_data ORDER BY id) LOOP
      RAISE INFO 'init nested-local loop sees amount=%', loc.amount;
    END LOOP;
    RAISE INFO 'init nested-local after loop amount=%', loc.amount;
  END;
  g_seen := 1;
END;
/
BEGIN
  test_loop_init_local.run();
END;
/
SELECT 'T11 init nested-local', test_loop_init_local.get_seen() FROM dual;

-- Test 12: comma-separated query FOR list whose first target collides with
-- a package variable.  A multi-target loop needs locally declared scalars;
-- the error must name the loop variable instead of silently binding the
-- shared package datum.  (The error is raised while the package body is
-- compiled.)
CREATE OR REPLACE PACKAGE test_loop_comma_pkg AS
  g_config NUMBER := 50;
  PROCEDURE run_comma;
END;
/
CREATE OR REPLACE PACKAGE BODY test_loop_comma_pkg AS
  PROCEDURE run_comma IS
    x NUMBER;
  BEGIN
    FOR g_config, x IN (SELECT amount, id FROM test_loop_data ORDER BY id) LOOP
      RAISE INFO 'comma loop sees amount=%, id=%', g_config, x;
    END LOOP;
  END;
END;
/
DROP PACKAGE test_loop_comma_pkg;

-- Test 13: cursor FOR loop whose record target collides with a package
-- variable: same Oracle shadowing contract as Test 7, through the cursor
-- branch of for_control.
CREATE OR REPLACE PACKAGE test_loop_cursor_pkg AS
  g_config NUMBER := 50;
  PROCEDURE run_cursor;
  FUNCTION get_config RETURN NUMBER;
END;
/
CREATE OR REPLACE PACKAGE BODY test_loop_cursor_pkg AS
  PROCEDURE run_cursor IS
    c CURSOR FOR SELECT amount FROM test_loop_data ORDER BY id;
  BEGIN
    FOR g_config IN c LOOP
      RAISE INFO 'cursor loop sees amount=%', g_config.amount;
    END LOOP;
  END;
  FUNCTION get_config RETURN NUMBER IS
  BEGIN
    RETURN g_config;
  END;
END;
/
BEGIN
  test_loop_cursor_pkg.run_cursor();
END;
/
SELECT 'T13 package scalar after cursor loop', test_loop_cursor_pkg.get_config() FROM dual;

-- Test 14: dynamic FOR (IN EXECUTE) whose record target collides with a
-- package variable: same Oracle shadowing contract, through the dynamic
-- branch of for_control.
CREATE OR REPLACE PACKAGE test_loop_dyn_pkg AS
  g_config NUMBER := 50;
  PROCEDURE run_dyn;
  FUNCTION get_config RETURN NUMBER;
END;
/
CREATE OR REPLACE PACKAGE BODY test_loop_dyn_pkg AS
  PROCEDURE run_dyn IS
  BEGIN
    FOR g_config IN EXECUTE 'SELECT amount FROM test_loop_data ORDER BY id' LOOP
      RAISE INFO 'dynamic loop sees amount=%', g_config.amount;
    END LOOP;
  END;
  FUNCTION get_config RETURN NUMBER IS
  BEGIN
    RETURN g_config;
  END;
END;
/
BEGIN
  test_loop_dyn_pkg.run_dyn();
END;
/
SELECT 'T14 package scalar after dynamic loop', test_loop_dyn_pkg.get_config() FROM dual;

-- Test 15: a nested subprogram's query FOR loop whose target collides with
-- a LOCAL of the enclosing member.  The enclosing frame's locals are outer
-- datums for the nested subprogram: the loop must bind an implicit
-- loop-local record and leave the member's local untouched (both a scalar
-- and a record target).
CREATE OR REPLACE PACKAGE test_loop_nested_pkg AS
  PROCEDURE run_scalar;
  PROCEDURE run_record;
END;
/
CREATE OR REPLACE PACKAGE BODY test_loop_nested_pkg AS
  PROCEDURE run_scalar IS
    x NUMBER := 7;
    PROCEDURE inner IS
    BEGIN
      FOR x IN (SELECT amount FROM test_loop_data ORDER BY id) LOOP
        RAISE INFO 'nested loop sees amount=%', x.amount;
      END LOOP;
    END;
  BEGIN
    inner();
    RAISE INFO 'T15 member scalar after nested loop: %', x;
  END;
  PROCEDURE run_record IS
    TYPE t_rec IS RECORD (a NUMBER);
    r t_rec;
    PROCEDURE inner IS
    BEGIN
      FOR r IN (SELECT amount FROM test_loop_data ORDER BY id) LOOP
        RAISE INFO 'nested loop sees amount=%', r.amount;
      END LOOP;
    END;
  BEGIN
    r.a := 5;
    inner();
    RAISE INFO 'T15 member record after nested loop: %', r.a;
  END;
END;
/
BEGIN
  test_loop_nested_pkg.run_scalar();
  test_loop_nested_pkg.run_record();
END;
/

-- Cleanup
DROP PACKAGE test_loop_shadow_pkg;
DROP PACKAGE test_loop_shadow_rec;
DROP PACKAGE test_loop_shadow_more;
DROP PACKAGE test_loop_foreach_pkg;
DROP PACKAGE test_loop_init_local;
DROP PACKAGE test_loop_comma_pkg;
DROP PACKAGE test_loop_cursor_pkg;
DROP PACKAGE test_loop_dyn_pkg;
DROP PACKAGE test_loop_nested_pkg;
DROP PACKAGE test_implicit_pkg;
DROP TABLE test_loop_data;
