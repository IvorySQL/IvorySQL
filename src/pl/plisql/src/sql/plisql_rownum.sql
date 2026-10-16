--
-- Tests for PL/iSQL with Oracle ROWNUM pseudocolumn
--

-- Setup test table
CREATE TABLE rownum_test (
    id INT,
    name TEXT,
    value NUMERIC
);

INSERT INTO rownum_test VALUES
    (1, 'Alice', 100),
    (2, 'Bob', 200),
    (3, 'Charlie', 150),
    (4, 'David', 300),
    (5, 'Eve', 250),
    (6, 'Frank', 175),
    (7, 'Grace', 225),
    (8, 'Henry', 125);

-- Test 1: ROWNUM in FOR loop with query
CREATE FUNCTION test_rownum_for_loop() RETURNS void AS $$
DECLARE
    r RECORD;
BEGIN
    RAISE NOTICE 'Test 1: FOR loop with ROWNUM';
    FOR r IN SELECT ROWNUM as rn, id, name FROM rownum_test WHERE ROWNUM <= 3 LOOP
        RAISE NOTICE 'ROWNUM=%, id=%, name=%', r.rn, r.id, r.name;
    END LOOP;
END;
$$ LANGUAGE plisql;
/

SELECT test_rownum_for_loop();

-- Test 2: ROWNUM in explicit cursor
CREATE FUNCTION test_rownum_cursor() RETURNS TEXT AS $$
DECLARE
    cur CURSOR FOR SELECT ROWNUM as rn, id, name FROM rownum_test WHERE ROWNUM <= 4;
    rec RECORD;
    result TEXT := '';
BEGIN
    RAISE NOTICE 'Test 2: Explicit cursor with ROWNUM';
    OPEN cur;
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        result := result || rec.rn || ':' || rec.name || ' ';
        RAISE NOTICE 'Fetched: ROWNUM=%, name=%', rec.rn, rec.name;
    END LOOP;
    CLOSE cur;
    RETURN trim(result);
END;
$$ LANGUAGE plisql;
/

SELECT test_rownum_cursor();

-- Test 3: ROWNUM with dynamic SQL (EXECUTE IMMEDIATE)
CREATE FUNCTION test_rownum_dynamic_sql(p_limit INT) RETURNS void AS $$
DECLARE
    r RECORD;
    sql_stmt TEXT;
BEGIN
    RAISE NOTICE 'Test 3: Dynamic SQL with ROWNUM limit=%', p_limit;
    sql_stmt := 'SELECT ROWNUM as rn, id, name FROM rownum_test WHERE ROWNUM <= ' || p_limit;

    FOR r IN EXECUTE sql_stmt LOOP
        RAISE NOTICE 'ROWNUM=%, id=%, name=%', r.rn, r.id, r.name;
    END LOOP;
END;
$$ LANGUAGE plisql;
/

SELECT test_rownum_dynamic_sql(3);

-- Test 4: ROWNUM in nested BEGIN...END blocks
DO $$
DECLARE
    v_count INT;
    r RECORD;
BEGIN
    RAISE NOTICE 'Test 4: Nested blocks with ROWNUM';

    -- Outer block
    BEGIN
        SELECT COUNT(*) INTO v_count FROM rownum_test WHERE ROWNUM <= 5;
        RAISE NOTICE 'Outer block: count=%', v_count;

        -- Inner block
        BEGIN
            FOR r IN SELECT ROWNUM as rn, name FROM rownum_test WHERE ROWNUM <= 2 LOOP
                RAISE NOTICE 'Inner block: ROWNUM=%, name=%', r.rn, r.name;
            END LOOP;
        END;
    END;
END$$;

-- Test 5: ROWNUM with OUT parameter
CREATE FUNCTION test_rownum_out_param(OUT p_first_name TEXT, OUT p_second_name TEXT) AS $$
DECLARE
    r RECORD;
    counter INT := 0;
BEGIN
    RAISE NOTICE 'Test 5: OUT parameters with ROWNUM';

    FOR r IN SELECT ROWNUM as rn, name FROM rownum_test WHERE ROWNUM <= 2 LOOP
        counter := counter + 1;
        IF counter = 1 THEN
            p_first_name := r.name;
        ELSIF counter = 2 THEN
            p_second_name := r.name;
        END IF;
    END LOOP;

    RAISE NOTICE 'First: %, Second: %', p_first_name, p_second_name;
    RETURN;
END;
$$ LANGUAGE plisql;
/

DO $$
DECLARE
    v_first TEXT;
    v_second TEXT;
BEGIN
    SELECT * INTO v_first, v_second FROM test_rownum_out_param(v_first, v_second);
    RAISE NOTICE 'Result: first=%, second=%', v_first, v_second;
END$$;

-- Test 6: ROWNUM with WHILE loop
CREATE FUNCTION test_rownum_while() RETURNS void AS $$
DECLARE
    r RECORD;
    cur CURSOR FOR SELECT ROWNUM as rn, id, name FROM rownum_test WHERE ROWNUM <= 5;
    i INT := 0;
BEGIN
    RAISE NOTICE 'Test 6: WHILE loop with ROWNUM cursor';
    OPEN cur;

    WHILE i < 3 LOOP
        FETCH cur INTO r;
        EXIT WHEN NOT FOUND;
        i := i + 1;
        RAISE NOTICE 'Iteration %: ROWNUM=%, name=%', i, r.rn, r.name;
    END LOOP;

    CLOSE cur;
END;
$$ LANGUAGE plisql;
/

SELECT test_rownum_while();

-- Test 7: ROWNUM with exception handling
CREATE FUNCTION test_rownum_exception() RETURNS void AS $$
DECLARE
    r RECORD;
    v_name TEXT;
BEGIN
    RAISE NOTICE 'Test 7: Exception handling with ROWNUM';

    BEGIN
        -- This will work
        FOR r IN SELECT ROWNUM as rn, name FROM rownum_test WHERE ROWNUM <= 2 LOOP
            RAISE NOTICE 'ROWNUM=%, name=%', r.rn, r.name;
        END LOOP;

        -- Force an error
        SELECT name INTO STRICT v_name FROM rownum_test WHERE ROWNUM <= 10;

    EXCEPTION
        WHEN TOO_MANY_ROWS THEN
            RAISE NOTICE 'Caught TOO_MANY_ROWS exception';
        WHEN NO_DATA_FOUND THEN
            RAISE NOTICE 'Caught NO_DATA_FOUND exception';
    END;
END;
$$ LANGUAGE plisql;
/

SELECT test_rownum_exception();

-- Test 8: ROWNUM with multiple cursors
CREATE FUNCTION test_rownum_multi_cursor() RETURNS void AS $$
DECLARE
    cur1 CURSOR FOR SELECT ROWNUM as rn, name FROM rownum_test WHERE ROWNUM <= 2;
    cur2 CURSOR FOR SELECT ROWNUM as rn, value FROM rownum_test WHERE ROWNUM <= 3;
    rec1 RECORD;
    rec2 RECORD;
BEGIN
    RAISE NOTICE 'Test 8: Multiple cursors with ROWNUM';

    OPEN cur1;
    FETCH cur1 INTO rec1;
    RAISE NOTICE 'Cursor1: ROWNUM=%, name=%', rec1.rn, rec1.name;

    OPEN cur2;
    FETCH cur2 INTO rec2;
    RAISE NOTICE 'Cursor2: ROWNUM=%, value=%', rec2.rn, rec2.value;

    FETCH cur1 INTO rec1;
    RAISE NOTICE 'Cursor1: ROWNUM=%, name=%', rec1.rn, rec1.name;

    FETCH cur2 INTO rec2;
    RAISE NOTICE 'Cursor2: ROWNUM=%, value=%', rec2.rn, rec2.value;

    CLOSE cur1;
    CLOSE cur2;
END;
$$ LANGUAGE plisql;
/

SELECT test_rownum_multi_cursor();

-- Test 9: ROWNUM with RETURN NEXT (set-returning function)
CREATE FUNCTION test_rownum_return_next() RETURNS SETOF TEXT AS $$
DECLARE
    r RECORD;
BEGIN
    RAISE NOTICE 'Test 9: RETURN NEXT with ROWNUM';

    FOR r IN SELECT ROWNUM as rn, name FROM rownum_test WHERE ROWNUM <= 4 LOOP
        RETURN NEXT r.rn || ':' || r.name;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plisql;
/

SELECT * FROM test_rownum_return_next();

-- Test 10: ROWNUM with RECORD type variable
DO $$
DECLARE
    rec RECORD;
    v_total NUMERIC := 0;
BEGIN
    RAISE NOTICE 'Test 10: RECORD type with ROWNUM';

    FOR rec IN SELECT ROWNUM as rn, id, value FROM rownum_test WHERE ROWNUM <= 3 LOOP
        RAISE NOTICE 'ROWNUM=%, id=%, value=%', rec.rn, rec.id, rec.value;
        v_total := v_total + rec.value;
    END LOOP;

    RAISE NOTICE 'Total value: %', v_total;
END$$;

-- Test 11: ROWNUM in subquery within PL/iSQL
-- Note: ROWNUM inside subquery is assigned during scan BEFORE ORDER BY,
-- so rn values reflect original row order, not sorted order.
-- This matches Oracle behavior.
CREATE FUNCTION test_rownum_subquery() RETURNS void AS $$
DECLARE
    r RECORD;
BEGIN
    RAISE NOTICE 'Test 11: Subquery with ROWNUM';

    -- ROWNUM assigned before ORDER BY, so rn values are from original scan order
    FOR r IN
        SELECT * FROM (
            SELECT ROWNUM as rn, id, name, value
            FROM rownum_test
            ORDER BY value DESC
        ) WHERE ROWNUM <= 3
    LOOP
        RAISE NOTICE 'ROWNUM=%, name=%, value=%', r.rn, r.name, r.value;
    END LOOP;
END;
$$ LANGUAGE plisql;
/

SELECT test_rownum_subquery();

-- Test 12: ROWNUM with EXIT WHEN inside loop
CREATE FUNCTION test_rownum_exit_when() RETURNS void AS $$
DECLARE
    r RECORD;
    counter INT := 0;
BEGIN
    RAISE NOTICE 'Test 12: EXIT WHEN with ROWNUM';

    FOR r IN SELECT ROWNUM as rn, name, value FROM rownum_test WHERE ROWNUM <= 10 LOOP
        counter := counter + 1;
        RAISE NOTICE 'ROWNUM=%, name=%', r.rn, r.name;

        EXIT WHEN counter >= 3;
    END LOOP;

    RAISE NOTICE 'Exited after % iterations', counter;
END;
$$ LANGUAGE plisql;
/

SELECT test_rownum_exit_when();

-- Test 13: ROWNUM with CONTINUE statement
CREATE FUNCTION test_rownum_continue() RETURNS void AS $$
DECLARE
    r RECORD;
BEGIN
    RAISE NOTICE 'Test 13: CONTINUE with ROWNUM';

    FOR r IN SELECT ROWNUM as rn, name, value FROM rownum_test WHERE ROWNUM <= 5 LOOP
        CONTINUE WHEN r.value < 200;
        RAISE NOTICE 'ROWNUM=%, name=%, value=%', r.rn, r.name, r.value;
    END LOOP;
END;
$$ LANGUAGE plisql;
/

SELECT test_rownum_continue();

-- Test 14: ROWNUM with conditional logic
CREATE FUNCTION test_rownum_conditional(p_limit INT) RETURNS void AS $$
DECLARE
    r RECORD;
    v_sql TEXT;
BEGIN
    RAISE NOTICE 'Test 14: Conditional with ROWNUM, limit=%', p_limit;

    IF p_limit > 0 THEN
        FOR r IN SELECT ROWNUM as rn, name FROM rownum_test WHERE ROWNUM <= p_limit LOOP
            IF r.rn = 1 THEN
                RAISE NOTICE 'First row: %', r.name;
            ELSIF r.rn = p_limit THEN
                RAISE NOTICE 'Last row: %', r.name;
            ELSE
                RAISE NOTICE 'Middle row %: %', r.rn, r.name;
            END IF;
        END LOOP;
    ELSE
        RAISE NOTICE 'Invalid limit: %', p_limit;
    END IF;
END;
$$ LANGUAGE plisql;
/

SELECT test_rownum_conditional(4);
SELECT test_rownum_conditional(0);

-- Test 15: ROWNUM with aggregate in PL/iSQL
CREATE FUNCTION test_rownum_aggregate() RETURNS void AS $$
DECLARE
    v_count INT;
    v_sum NUMERIC;
    v_avg NUMERIC;
BEGIN
    RAISE NOTICE 'Test 15: Aggregates with ROWNUM';

    SELECT COUNT(*), SUM(value), AVG(value)
    INTO v_count, v_sum, v_avg
    FROM (SELECT * FROM rownum_test WHERE ROWNUM <= 5);

    RAISE NOTICE 'Count: %, Sum: %, Avg: %', v_count, v_sum, v_avg;
END;
$$ LANGUAGE plisql;
/

SELECT test_rownum_aggregate();

-- Cleanup
DROP FUNCTION test_rownum_for_loop();
DROP FUNCTION test_rownum_cursor();
DROP FUNCTION test_rownum_dynamic_sql(INT);
DROP FUNCTION test_rownum_out_param(TEXT, TEXT);
DROP FUNCTION test_rownum_while();
DROP FUNCTION test_rownum_exception();
DROP FUNCTION test_rownum_multi_cursor();
DROP FUNCTION test_rownum_return_next();
DROP FUNCTION test_rownum_subquery();
DROP FUNCTION test_rownum_exit_when();
DROP FUNCTION test_rownum_continue();
DROP FUNCTION test_rownum_conditional(INT);
DROP FUNCTION test_rownum_aggregate();
DROP TABLE rownum_test;
