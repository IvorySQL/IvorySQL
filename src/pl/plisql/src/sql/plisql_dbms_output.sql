--
-- Tests for DBMS_OUTPUT package
--

-- Test 1: PUT_LINE basic functionality
BEGIN
  DBMS_OUTPUT.PUT_LINE('Test message 1');
END;
/

-- Test 2: PUT_LINE with variable
DECLARE
  v_number NUMBER := 42;
  v_text VARCHAR2(100) := 'Hello World';
BEGIN
  DBMS_OUTPUT.PUT_LINE('Number: ' || v_number);
  DBMS_OUTPUT.PUT_LINE('Text: ' || v_text);
END;
/

-- Test 3: Multiple PUT_LINE calls
BEGIN
  DBMS_OUTPUT.PUT_LINE('Line 1');
  DBMS_OUTPUT.PUT_LINE('Line 2');
  DBMS_OUTPUT.PUT_LINE('Line 3');
END;
/

-- Test 4a: PUT procedure
BEGIN
  DBMS_OUTPUT.PUT('Part 1');
END;
/

-- Test 4b: Multiple PUT calls
BEGIN
  DBMS_OUTPUT.PUT('Part 1');
  DBMS_OUTPUT.PUT(' Part 2');
END;
/

-- Test 4c: NEW_LINE procedure
BEGIN
  DBMS_OUTPUT.NEW_LINE;
END;
/

-- Test 5a: ENABLE procedure
BEGIN
  DBMS_OUTPUT.ENABLE(20000);
END;
/

-- Test 5b: ENABLE with PUT_LINE
BEGIN
  DBMS_OUTPUT.ENABLE(20000);
  DBMS_OUTPUT.PUT_LINE('After enable');
END;
/

-- Test 5c: DISABLE procedure
BEGIN
  DBMS_OUTPUT.DISABLE;
END;
/

-- Test 5d: DISABLE with PUT_LINE
BEGIN
  DBMS_OUTPUT.DISABLE;
  DBMS_OUTPUT.PUT_LINE('After disable');
END;
/

-- Test 6: DBMS_OUTPUT in function
CREATE OR REPLACE FUNCTION test_dbms_output_func(p_msg VARCHAR2) RETURN NUMBER IS
BEGIN
  DBMS_OUTPUT.PUT_LINE('Function says: ' || p_msg);
  RETURN 1;
END;
/

DECLARE
  v_result NUMBER;
BEGIN
  v_result := test_dbms_output_func('Hello from function');
  DBMS_OUTPUT.PUT_LINE('Result: ' || v_result);
END;
/

DROP FUNCTION test_dbms_output_func;

-- Test 7: DBMS_OUTPUT in procedure
CREATE OR REPLACE PROCEDURE test_dbms_output_proc(p_msg VARCHAR2) IS
BEGIN
  DBMS_OUTPUT.PUT_LINE('Procedure says: ' || p_msg);
END;
/

BEGIN
  test_dbms_output_proc('Hello from procedure');
END;
/

DROP PROCEDURE test_dbms_output_proc;

-- Test 8: DBMS_OUTPUT in package
CREATE OR REPLACE PACKAGE test_output_pkg IS
  PROCEDURE show_message(p_msg VARCHAR2);
END test_output_pkg;
/

CREATE OR REPLACE PACKAGE BODY test_output_pkg IS
  PROCEDURE show_message(p_msg VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('Package says: ' || p_msg);
  END show_message;
BEGIN
  -- Package initialization block
  DBMS_OUTPUT.PUT_LINE('Package initialized');
END test_output_pkg;
/

BEGIN
  test_output_pkg.show_message('Hello from package');
END;
/

DROP PACKAGE test_output_pkg;

-- Test 9: NULL handling
BEGIN
  DBMS_OUTPUT.PUT_LINE(NULL);
  DBMS_OUTPUT.PUT_LINE('After NULL');
END;
/

-- Test 10: Empty string
BEGIN
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('After empty string');
END;
/

-- Test 11: Long string
DECLARE
  v_long VARCHAR2(1000) := RPAD('A', 500, 'B');
BEGIN
  DBMS_OUTPUT.PUT_LINE(v_long);
END;
/

--
-- Oracle DBMS_OUTPUT Package Methods (per Oracle 12c documentation):
-- 1. ENABLE(buffer_size)        - Enable output with buffer size
-- 2. DISABLE                     - Disable output and purge buffer
-- 3. PUT(text)                   - Place partial line in buffer
-- 4. PUT_LINE(text)              - Place complete line in buffer
-- 5. NEW_LINE                    - Put end-of-line marker in buffer
-- 6. GET_LINE(line, status)      - Retrieve single line from buffer
-- 7. GET_LINES(lines, numlines)  - Retrieve multiple lines from buffer
--
-- IvorySQL Current Implementation Status:
-- ✓ PUT_LINE(text)               - Works (outputs via RAISE INFO)
-- ✓ PUT(text)                    - Works (outputs via RAISE INFO)
-- ✗ NEW_LINE                     - Syntax error (no-arg procedure call)
-- ✓ ENABLE(buffer_size)          - Works (no-op)
-- ✗ DISABLE                      - Syntax error (no-arg procedure call)
-- ✗ GET_LINE(line, status)       - Not implemented
-- ✗ GET_LINES(lines, numlines)   - Not implemented
--
-- Note:
-- - Output is immediate (no buffering)
-- - NEW_LINE and DISABLE fail due to PL/iSQL parser limitation with no-arg procedures
