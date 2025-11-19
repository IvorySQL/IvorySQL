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

-- Cleanup
DROP PACKAGE test_implicit_pkg;
DROP TABLE test_loop_data;
