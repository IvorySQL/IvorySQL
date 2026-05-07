\set SHOW_CONTEXT never

-- T01: Basic WITH FUNCTION returning a number
WITH FUNCTION double_it(n NUMBER) RETURN NUMBER IS
BEGIN RETURN n * 2; END;
SELECT double_it(5) FROM dual;

-- T02: WITH PROCEDURE (void — verified via side-effect SELECT)
WITH PROCEDURE do_nothing IS
BEGIN
  NULL;
END;
SELECT 'procedure ok' AS result FROM dual;

-- T03: WITH FUNCTION mixed with a regular CTE
WITH
  FUNCTION tax(amt NUMBER) RETURN NUMBER IS
  BEGIN RETURN amt * 0.1; END;
  orders AS (SELECT 100 AS amount FROM dual)
SELECT amount, tax(amount) FROM orders;

-- T04: Multiple WITH FUNCTION definitions composed
WITH
  FUNCTION add1(n NUMBER) RETURN NUMBER IS
  BEGIN RETURN n + 1; END;
  FUNCTION mul2(n NUMBER) RETURN NUMBER IS
  BEGIN RETURN n * 2; END;
SELECT mul2(add1(3)) FROM dual;

-- T05: IN OUT parameter (value is modified inside the body)
WITH FUNCTION bump(x IN OUT NUMBER) RETURN NUMBER IS
BEGIN
  x := x * 3;
  RETURN x;
END;
SELECT bump(5) FROM dual;

-- T06: Default parameter value — call with one arg (uses default) and two args
WITH FUNCTION greet(name VARCHAR2, greeting VARCHAR2 DEFAULT 'Hello') RETURN VARCHAR2 IS
BEGIN RETURN greeting || ', ' || name || '!'; END;
SELECT greet('World'), greet('World', 'Hi') FROM dual;

-- T07: Multiple parameters
WITH FUNCTION add_nums(a NUMBER, b NUMBER) RETURN NUMBER IS
BEGIN
  RETURN a + b;
END;
SELECT add_nums(3, 4) FROM dual;

-- T08: IF/ELSE control flow
WITH FUNCTION abs_val(n NUMBER) RETURN NUMBER IS
BEGIN
  IF n < 0 THEN RETURN -n; ELSE RETURN n; END IF;
END;
SELECT abs_val(-5), abs_val(3) FROM dual;

-- T09: LOOP construct (iterative factorial)
WITH FUNCTION loop_fact(n NUMBER) RETURN NUMBER IS
  result NUMBER := 1;
  i NUMBER;
BEGIN
  FOR i IN 1..n LOOP
    result := result * i;
  END LOOP;
  RETURN result;
END;
SELECT loop_fact(5) FROM dual;

-- T10: Recursive function call (factorial via recursion)
WITH FUNCTION factorial(n NUMBER) RETURN NUMBER IS
BEGIN
  IF n <= 1 THEN RETURN 1; END IF;
  RETURN n * factorial(n-1);
END;
SELECT factorial(5) FROM dual;

-- T11: EXCEPTION WHEN handler
WITH FUNCTION safe_div(a NUMBER, b NUMBER) RETURN NUMBER IS
BEGIN
  RETURN a / b;
EXCEPTION
  WHEN OTHERS THEN RETURN NULL;
END;
SELECT safe_div(10, 2), safe_div(10, 0) FROM dual;

-- T12: Runtime error propagation (unhandled exception reaches caller)
WITH FUNCTION bad_div(a NUMBER, b NUMBER) RETURN NUMBER IS
BEGIN
  RETURN a / b;
END;
SELECT bad_div(1, 0) FROM dual;

-- T13: WITH FUNCTION inside INSERT...SELECT
CREATE TABLE _wf_dml_test (val NUMBER);
WITH FUNCTION triple(n NUMBER) RETURN NUMBER IS
BEGIN
  RETURN n * 3;
END;
INSERT INTO _wf_dml_test SELECT triple(x) FROM generate_series(1,4) AS x;
SELECT * FROM _wf_dml_test ORDER BY val;
DROP TABLE _wf_dml_test;

-- T14: WITH FUNCTION inside UPDATE...SET
CREATE TABLE _wf_upd_test (id INT, val NUMBER);
INSERT INTO _wf_upd_test VALUES (1, 10), (2, 20), (3, 30);
WITH FUNCTION halve(n NUMBER) RETURN NUMBER IS
BEGIN RETURN n / 2; END;
UPDATE _wf_upd_test SET val = halve(val);
SELECT id, val FROM _wf_upd_test ORDER BY id;
DROP TABLE _wf_upd_test;

-- T15: WITH FUNCTION inside DELETE...WHERE
CREATE TABLE _wf_del_test (id INT, val NUMBER);
INSERT INTO _wf_del_test VALUES (1, 5), (2, 15), (3, 25);
WITH FUNCTION is_big(n NUMBER) RETURN NUMBER IS
BEGIN IF n > 10 THEN RETURN 1; ELSE RETURN 0; END IF; END;
DELETE FROM _wf_del_test WHERE is_big(val) = 1;
SELECT id, val FROM _wf_del_test ORDER BY id;
DROP TABLE _wf_del_test;

-- T16: WITH FUNCTION inside MERGE WHEN MATCHED THEN UPDATE
CREATE TABLE _wf_merge_test (id INT, val NUMBER);
INSERT INTO _wf_merge_test VALUES (1, 10), (2, 20), (3, 30);
WITH FUNCTION triple(n NUMBER) RETURN NUMBER IS
BEGIN RETURN n * 3; END;
MERGE INTO _wf_merge_test t USING dual ON (1=1)
WHEN MATCHED THEN UPDATE SET val = triple(t.val);
SELECT id, val FROM _wf_merge_test ORDER BY id;
DROP TABLE _wf_merge_test;

-- T17: WITH FUNCTION scope — function works inside its statement,
-- and is no longer visible in a separate statement afterward.
WITH FUNCTION _wf_scope_test(n NUMBER) RETURN NUMBER IS
BEGIN RETURN n + 42; END;
SELECT _wf_scope_test(1) FROM dual;
-- Separate statement: same name should now fail because the WITH-clause
-- definition went out of scope when the previous statement completed.
SELECT _wf_scope_test(1) FROM dual;

-- T18: WITH FUNCTION shadows a catalog function of the same name
WITH FUNCTION abs(n NUMBER) RETURN NUMBER IS
BEGIN RETURN 999; END;
SELECT abs(-5) FROM dual;

-- T19: WITH FUNCTION visible inside a subquery
WITH FUNCTION add2(n NUMBER) RETURN NUMBER IS
BEGIN RETURN n + 2; END;
SELECT add2(v) FROM (SELECT 10 AS v FROM dual) sub;

-- E01: Duplicate WITH FUNCTION definition (same name and types) — expect error
WITH
  FUNCTION dup(n NUMBER) RETURN NUMBER IS BEGIN RETURN n; END;
  FUNCTION dup(n NUMBER) RETURN NUMBER IS BEGIN RETURN n * 2; END;
SELECT dup(1) FROM dual;

-- E02: Return type mismatch — function returns NUMBER but body returns text — expect error
WITH FUNCTION bad_ret(n NUMBER) RETURN NUMBER IS
BEGIN RETURN 'hello'; END;
SELECT bad_ret(1) FROM dual;

-- E03: Wrong argument type at call site — expect error
WITH FUNCTION only_nums(n NUMBER) RETURN NUMBER IS
BEGIN RETURN n; END;
SELECT only_nums('not a number') FROM dual;

-- E04: WITH FUNCTION syntax in PG_PARSER mode — expect error
SET ivorysql.compatible_mode = pg;
WITH FUNCTION pg_mode_test(n INT) RETURN INT IS
BEGIN RETURN n; END;
SELECT pg_mode_test(1);
SET ivorysql.compatible_mode = oracle;

-- E05: Syntax error in function body — expect error
WITH FUNCTION broken_body(n NUMBER) RETURN NUMBER IS
BEGIN RETRUN n; END;
SELECT broken_body(1) FROM dual;

-- E06: WITH function used as a table function — expect clear error
WITH FUNCTION as_table(n NUMBER) RETURN NUMBER IS
BEGIN RETURN n; END;
SELECT * FROM as_table(5);

-- T20: Nested BEGIN…END inside WITH FUNCTION body
-- (inner END; must not dismantle WITH-clause tracking on the client side)
WITH FUNCTION nested_begin(n NUMBER) RETURN NUMBER IS
BEGIN
  BEGIN
    RETURN n * 2;
  END;
END;
SELECT nested_begin(5) FROM dual;

-- E07: Qualified name in WITH FUNCTION declaration — expect clear error
WITH FUNCTION public.qual_func(n NUMBER) RETURN NUMBER IS
BEGIN RETURN n; END;
SELECT public.qual_func(5) FROM dual;

-- E08: Qualified name in WITH PROCEDURE declaration — expect clear error
WITH PROCEDURE public.qual_proc IS
BEGIN NULL; END;
SELECT 'unused' FROM dual;

-- E09: WITH-clause names must NOT leak into catalog functions called from
-- within the WITH execution frame.  catalog_caller is a regular PL/iSQL
-- function whose body references _wf_leak_target.  When invoked from inside
-- a WITH FUNCTION body, the WITH-clause name must remain invisible to the
-- catalog function's lexical scope.
CREATE OR REPLACE FUNCTION catalog_caller(n NUMBER) RETURN NUMBER IS
  result NUMBER;
BEGIN
  result := _wf_leak_target(n);
  RETURN result;
END;
/
WITH
  FUNCTION _wf_leak_target(x NUMBER) RETURN NUMBER IS
  BEGIN RETURN x + 1000; END;
  FUNCTION calls_catalog(n NUMBER) RETURN NUMBER IS
  BEGIN RETURN catalog_caller(n); END;
SELECT calls_catalog(5) FROM dual;
DROP FUNCTION catalog_caller;

-- X01: EXPLAIN shows WITH Function/Procedure signatures
EXPLAIN (COSTS OFF)
WITH FUNCTION double_it(n NUMBER) RETURN NUMBER IS
BEGIN RETURN n * 2; END;
SELECT double_it(5) FROM dual;

-- X02: EXPLAIN shows multiple WITH definitions
EXPLAIN (COSTS OFF)
WITH
  FUNCTION add1(n NUMBER) RETURN NUMBER IS
  BEGIN RETURN n + 1; END;
  PROCEDURE do_nothing IS
  BEGIN NULL; END;
SELECT add1(1) FROM dual;

-- X03: EXPLAIN VERBOSE shows function body in TEXT mode
EXPLAIN (COSTS OFF, VERBOSE)
WITH FUNCTION shows_body(n NUMBER) RETURN NUMBER IS
BEGIN RETURN n + 100; END;
SELECT shows_body(5) FROM dual;
