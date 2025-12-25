--
-- Tests for DBMS_OUTPUT package
--
-- Design: Every PUT operation is verified by corresponding GET operation
-- to ensure content is properly buffered and retrieved.
--

-- =============================================================================
-- Section 1: Basic PUT_LINE and GET_LINE
-- =============================================================================

-- Test 1.1: Simple PUT_LINE verified by GET_LINE
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('Hello, World!');
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 1.1 - Line: [%], Status: %', line, status;
END;
/

-- Test 1.2: Multiple PUT_LINE calls verified by GET_LINES
DECLARE
    lines TEXT[];
    numlines INTEGER := 10;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('First line');
    dbms_output.put_line('Second line');
    dbms_output.put_line('Third line');
    dbms_output.get_lines(lines, numlines);
    RAISE NOTICE 'Test 1.2 - Retrieved % lines', numlines;
    FOR i IN 1..numlines LOOP
        RAISE NOTICE '  Line %: [%]', i, lines[i];
    END LOOP;
END;
/

-- Test 1.3: Empty string handling
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('');
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 1.3 - Empty string: [%], Status: %', line, status;
END;
/

-- Test 1.4: NULL handling (should output empty line)
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put_line(NULL);
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 1.4 - NULL input: [%], Status: %', line, status;
END;
/

-- Test 1.5: GET_LINE when buffer is empty (status should be 1)
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    -- Don't put anything
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 1.5 - Empty buffer: Line=[%], Status=%', line, status;
END;
/

-- =============================================================================
-- Section 2: PUT and NEW_LINE
-- =============================================================================

-- Test 2.1: PUT followed by NEW_LINE
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put('First part');
    dbms_output.put(' second part');
    dbms_output.new_line();
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 2.1 - Combined: [%], Status: %', line, status;
END;
/

-- Test 2.2: PUT with NULL (should append nothing)
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put('Before');
    dbms_output.put(NULL);
    dbms_output.put('After');
    dbms_output.new_line();
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 2.2 - PUT with NULL: [%], Status: %', line, status;
END;
/

-- Test 2.3: Multiple PUT calls building one line
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put('A');
    dbms_output.put('B');
    dbms_output.put('C');
    dbms_output.put('D');
    dbms_output.new_line();
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 2.3 - Multiple PUTs: [%], Status: %', line, status;
END;
/

-- Test 2.4: PUT_LINE after PUT (should create two lines)
DECLARE
    lines TEXT[];
    numlines INTEGER := 10;
BEGIN
    dbms_output.enable();
    dbms_output.put('Partial');
    dbms_output.new_line();
    dbms_output.put_line('Complete');
    dbms_output.get_lines(lines, numlines);
    RAISE NOTICE 'Test 2.4 - Retrieved % lines', numlines;
    FOR i IN 1..numlines LOOP
        RAISE NOTICE '  Line %: [%]', i, lines[i];
    END LOOP;
END;
/

-- =============================================================================
-- Section 3: ENABLE and DISABLE behavior
-- =============================================================================

-- Test 3.1: DISABLE prevents output from being buffered
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('Before disable');
    dbms_output.disable();
    dbms_output.put_line('During disable - should not appear');
    dbms_output.enable();
    -- Try to get - should only see what was put after re-enable
    dbms_output.put_line('After re-enable');
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 3.1 - After disable/enable cycle: [%], Status: %', line, status;
END;
/

-- Test 3.2: DISABLE clears existing buffer
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('This will be cleared');
    dbms_output.disable();
    dbms_output.enable();
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 3.2 - Buffer after disable: [%], Status: %', line, status;
END;
/

-- Test 3.3: Re-ENABLE clears buffer
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('First enable content');
    dbms_output.enable();  -- Re-enable should clear
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 3.3 - After re-enable: [%], Status: %', line, status;
END;
/

-- Test 3.4: Output while disabled is silently ignored
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.disable();
    dbms_output.put_line('Ignored 1');
    dbms_output.put('Ignored 2');
    dbms_output.new_line();
    dbms_output.enable();
    dbms_output.put_line('Visible');
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 3.4 - Only visible after enable: [%], Status: %', line, status;
END;
/

-- =============================================================================
-- Section 4: Buffer size limits
-- =============================================================================

-- Test 4.1: Buffer size below minimum (should fail)
CALL dbms_output.enable(1000);

-- Test 4.2: Buffer size at minimum (should succeed)
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable(2000);
    dbms_output.put_line('Min buffer works');
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 4.2 - Min buffer: [%]', line;
END;
/

-- Test 4.3: Buffer size at maximum (should succeed)
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable(1000000);
    dbms_output.put_line('Max buffer works');
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 4.3 - Max buffer: [%]', line;
END;
/

-- Test 4.4: Buffer size above maximum (should fail)
CALL dbms_output.enable(1000001);

-- Test 4.5: NULL buffer size uses maximum (1000000)
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable(NULL);
    dbms_output.put_line('NULL buffer uses max');
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 4.5 - NULL buffer: [%]', line;
END;
/

-- =============================================================================
-- Section 5: Buffer overflow
-- =============================================================================

-- Test 5.1: Buffer overflow produces error
DECLARE
    overflow_occurred BOOLEAN := FALSE;
    line_count INTEGER := 0;
BEGIN
    dbms_output.enable(2000);  -- Small buffer
    FOR i IN 1..100 LOOP
        BEGIN
            dbms_output.put_line('Buffer test line ' || i || ' with extra padding text');
            line_count := i;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Test 5.1 - Overflow at line %: %', i, SQLERRM;
            overflow_occurred := TRUE;
            EXIT;
        END;
    END LOOP;
    IF NOT overflow_occurred THEN
        RAISE NOTICE 'Test 5.1 - No overflow occurred (unexpected)';
    END IF;
END;
/

-- =============================================================================
-- Section 6: GET_LINE and GET_LINES behavior
-- =============================================================================

-- Test 6.1: GET_LINE returns lines in order
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('Line A');
    dbms_output.put_line('Line B');
    dbms_output.put_line('Line C');
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 6.1a - First: [%]', line;
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 6.1b - Second: [%]', line;
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 6.1c - Third: [%]', line;
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 6.1d - Fourth (empty): [%], Status: %', line, status;
END;
/

-- Test 6.2: GET_LINES with numlines larger than available
DECLARE
    lines TEXT[];
    numlines INTEGER := 100;  -- Request more than available
BEGIN
    dbms_output.enable();
    dbms_output.put_line('Only');
    dbms_output.put_line('Three');
    dbms_output.put_line('Lines');
    dbms_output.get_lines(lines, numlines);
    RAISE NOTICE 'Test 6.2 - Requested 100, got %', numlines;
    FOR i IN 1..numlines LOOP
        RAISE NOTICE '  Line %: [%]', i, lines[i];
    END LOOP;
END;
/

-- Test 6.3: GET_LINES with numlines smaller than available
DECLARE
    lines TEXT[];
    numlines INTEGER := 2;  -- Request fewer than available
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('One');
    dbms_output.put_line('Two');
    dbms_output.put_line('Three');
    dbms_output.put_line('Four');
    dbms_output.get_lines(lines, numlines);
    RAISE NOTICE 'Test 6.3a - Got % lines with GET_LINES', numlines;
    FOR i IN 1..numlines LOOP
        RAISE NOTICE '  Line %: [%]', i, lines[i];
    END LOOP;
    -- Remaining lines should still be available
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 6.3b - Remaining: [%], Status: %', line, status;
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 6.3c - Remaining: [%], Status: %', line, status;
END;
/

-- =============================================================================
-- Section 7: Usage in procedures and functions
-- =============================================================================

-- Test 7.1: Output from procedure
CREATE OR REPLACE PROCEDURE test_output_proc(p_msg TEXT)
AS $$
BEGIN
    dbms_output.put_line('Proc says: ' || p_msg);
END;
$$ LANGUAGE plisql;
/

DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    test_output_proc('Hello from procedure');
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 7.1 - From procedure: [%]', line;
END;
/

-- Test 7.2: Output from function (output preserved across call)
CREATE OR REPLACE FUNCTION test_output_func(p_val INTEGER) RETURNS INTEGER
AS $$
BEGIN
    dbms_output.put_line('Func input: ' || p_val);
    dbms_output.put_line('Func output: ' || (p_val * 2));
    RETURN p_val * 2;
END;
$$ LANGUAGE plisql;
/

DECLARE
    result INTEGER;
    lines TEXT[];
    numlines INTEGER := 10;
BEGIN
    dbms_output.enable();
    result := test_output_func(5);
    dbms_output.get_lines(lines, numlines);
    RAISE NOTICE 'Test 7.2 - Function returned: %', result;
    FOR i IN 1..numlines LOOP
        RAISE NOTICE '  Output %: [%]', i, lines[i];
    END LOOP;
END;
/

-- =============================================================================
-- Section 8: Special cases
-- =============================================================================

-- Test 8.1: Special characters
DECLARE
    lines TEXT[];
    numlines INTEGER := 10;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('Tab:	here');
    dbms_output.put_line('Quote: ''single'' "double"');
    dbms_output.put_line('Backslash: \ forward: /');
    dbms_output.get_lines(lines, numlines);
    RAISE NOTICE 'Test 8.1 - Special chars: % lines', numlines;
    FOR i IN 1..numlines LOOP
        RAISE NOTICE '  [%]', lines[i];
    END LOOP;
END;
/

-- Test 8.2: Numeric values via concatenation
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('Number: ' || 42);
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 8.2 - Numeric: [%]', line;
END;
/

-- Test 8.3: Very long line
DECLARE
    very_long TEXT := repeat('X', 1000);
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable(10000);
    dbms_output.put_line(very_long);
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 8.3 - Long line length: %', length(line);
END;
/

-- Test 8.4: Exception handling preserves buffer
DECLARE
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('Before exception');
    BEGIN
        RAISE EXCEPTION 'Test error';
    EXCEPTION WHEN OTHERS THEN
        dbms_output.put_line('Caught: ' || SQLERRM);
    END;
    dbms_output.put_line('After exception');
    -- Verify all three lines are in buffer
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 8.4a - [%]', line;
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 8.4b - [%]', line;
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 8.4c - [%]', line;
END;
/

-- Test 8.5: Nested blocks
DECLARE
    lines TEXT[];
    numlines INTEGER := 10;
BEGIN
    dbms_output.enable();
    dbms_output.put_line('Outer');
    BEGIN
        dbms_output.put_line('Inner 1');
        BEGIN
            dbms_output.put_line('Inner 2');
        END;
    END;
    dbms_output.put_line('Back to outer');
    dbms_output.get_lines(lines, numlines);
    RAISE NOTICE 'Test 8.5 - Nested blocks: % lines', numlines;
    FOR i IN 1..numlines LOOP
        RAISE NOTICE '  [%]', lines[i];
    END LOOP;
END;
/

-- Test 8.6: Loop output
DECLARE
    lines TEXT[];
    numlines INTEGER := 10;
BEGIN
    dbms_output.enable();
    FOR i IN 1..3 LOOP
        dbms_output.put_line('Iteration ' || i);
    END LOOP;
    dbms_output.get_lines(lines, numlines);
    RAISE NOTICE 'Test 8.6 - Loop: % lines', numlines;
    FOR i IN 1..numlines LOOP
        RAISE NOTICE '  [%]', lines[i];
    END LOOP;
END;
/

-- =============================================================================
-- Section 9: Line Length Limit (32767 bytes)
-- =============================================================================
-- Test 9.1: PUT_LINE at exactly 32767 bytes (should succeed)
DECLARE
    long_line TEXT := repeat('X', 32767);
    line TEXT;
    status INTEGER;
BEGIN
    dbms_output.enable(100000);
    dbms_output.put_line(long_line);
    dbms_output.get_line(line, status);
    RAISE NOTICE 'Test 9.1 - Max line (32767 bytes): length=%, Status=%', length(line), status;
END;
/

-- Test 9.2: PUT_LINE exceeding 32767 bytes (should fail with ORU-10028)
DECLARE
    long_line TEXT := repeat('X', 32768);
BEGIN
    dbms_output.enable(100000);
    dbms_output.put_line(long_line);
    RAISE NOTICE 'Test 9.2 - Should not reach here';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Test 9.2 - Line overflow error: %', SQLERRM;
END;
/

-- Test 9.3: PUT accumulating to exceed 32767 bytes (should fail with ORU-10028)
DECLARE
    chunk TEXT := repeat('X', 32767);
BEGIN
    dbms_output.enable(100000);
    dbms_output.put(chunk);
    dbms_output.put('Y');  -- This triggers the overflow
    dbms_output.new_line();
    RAISE NOTICE 'Test 9.3 - Should not reach here';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Test 9.3 - PUT overflow error: %', SQLERRM;
END;
/

-- =============================================================================
-- Section 10: Session Scope (buffer persists across transactions)
-- =============================================================================

-- Test 10.1: Buffer persists after block ends (implicit commit)
-- Write in first block
DO $$
BEGIN
    dbms_output.enable(1000000);
    dbms_output.put_line('Written in block 1');
END;
$$;

-- Read in second block (different transaction)
DO $$
DECLARE
    v_line TEXT;
    v_status INTEGER;
BEGIN
    dbms_output.get_line(v_line, v_status);
    IF v_status = 0 THEN
        RAISE NOTICE 'Test 10.1 - Read after commit: [%]', v_line;
    ELSE
        RAISE NOTICE 'Test 10.1 FAILED - Buffer was cleared (status=%)', v_status;
    END IF;
END;
$$;

-- Test 10.2: Multiple blocks accumulate in buffer
DO $$
BEGIN
    dbms_output.enable(1000000);
    dbms_output.put_line('Line from block A');
END;
$$;

DO $$
BEGIN
    dbms_output.put_line('Line from block B');
END;
$$;

DO $$
BEGIN
    dbms_output.put_line('Line from block C');
END;
$$;

DO $$
DECLARE
    v_line TEXT;
    v_status INTEGER;
    v_count INTEGER := 0;
BEGIN
    LOOP
        dbms_output.get_line(v_line, v_status);
        EXIT WHEN v_status != 0;
        v_count := v_count + 1;
        RAISE NOTICE 'Test 10.2 - Line %: [%]', v_count, v_line;
    END LOOP;
    RAISE NOTICE 'Test 10.2 - Total lines read: %', v_count;
END;
$$;

-- =============================================================================
-- Cleanup
-- =============================================================================
DROP PROCEDURE test_output_proc;
DROP FUNCTION test_output_func;
