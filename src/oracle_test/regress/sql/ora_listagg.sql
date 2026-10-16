--
-- ORA_LISTAGG
-- Test Oracle-compatible LISTAGG aggregate function
-- Syntax: LISTAGG(measure_expr [, 'delimiter']) WITHIN GROUP (ORDER BY sort_expr)
--

-- Setup
CREATE TABLE listagg_test (
    deptno  INTEGER,
    ename   varchar2(20),
    sal     NUMERIC
);

INSERT INTO listagg_test VALUES
    (10, 'CLARK',  2450),
    (10, 'KING',   5000),
    (10, 'MILLER', 1300),
    (20, 'ADAMS',  1100),
    (20, 'FORD',   3000),
    (20, 'JONES',  2975),
    (30, 'ALLEN',  1600),
    (30, 'BLAKE',  2850),
    (30, 'MARTIN', 1250);

-- Test 1: basic ordered concatenation (measure == sort key)
SELECT LISTAGG(ename, ',') WITHIN GROUP (ORDER BY ename)
FROM listagg_test WHERE deptno = 10;

-- Test 2: sort column differs from measure column (sort by salary DESC)
SELECT LISTAGG(ename, ', ') WITHIN GROUP (ORDER BY sal DESC)
FROM listagg_test WHERE deptno = 10;

-- Test 3: grouped aggregation
SELECT deptno, LISTAGG(ename, '|') WITHIN GROUP (ORDER BY ename)
FROM listagg_test GROUP BY deptno ORDER BY deptno;

-- Test 4: no delimiter (single-argument form, defaults to empty string)
SELECT LISTAGG(ename) WITHIN GROUP (ORDER BY ename)
FROM listagg_test WHERE deptno = 10;

-- Test 5: NULL measure values are ignored (string_agg skips NULLs)
INSERT INTO listagg_test VALUES (10, NULL, 999);
SELECT LISTAGG(ename, ',') WITHIN GROUP (ORDER BY ename)
FROM listagg_test WHERE deptno = 10;

-- Test 6: multi-column ORDER BY
SELECT LISTAGG(ename, ',') WITHIN GROUP (ORDER BY deptno, ename)
FROM listagg_test;

-- Test 7: empty result set returns NULL
SELECT LISTAGG(ename, ',') WITHIN GROUP (ORDER BY ename)
FROM listagg_test WHERE deptno = 99;

-- Test 8: schema-qualified call
SELECT sys.ora_listagg_check(string_agg(ename, ',' ORDER BY ename))
FROM listagg_test WHERE deptno = 10;

-- Test 9: aggregate with FILTER clause
SELECT LISTAGG(ename, ',') WITHIN GROUP (ORDER BY ename)
    FILTER (WHERE sal > 1500)
FROM listagg_test WHERE deptno IS NOT NULL;

-- Test 10: 4000-byte overflow raises an error
DO $$
BEGIN
    PERFORM sys.ora_listagg_check(repeat('x', 4001));
    RAISE EXCEPTION 'Expected error was not raised';
EXCEPTION
    WHEN string_data_right_truncation THEN
        RAISE NOTICE 'ORA-01489: result of string concatenation is too long (expected)';
END;
$$;

-- Test 11: exactly 4000 bytes is allowed
SELECT length(sys.ora_listagg_check(repeat('x', 4000)));

-- Test 12: LISTAGG with GROUP BY and multi-column ORDER BY
SELECT deptno,
       LISTAGG(ename ORDER by ename ) WITHIN GROUP(ORDER BY ename) AS employees
FROM listagg_test
GROUP BY deptno
ORDER BY deptno;

-- Test 13: LISTAGG with GROUP BY and multi-column ORDER BY, with delimiter
SELECT deptno,
       LISTAGG(ename, ',' ORDER BY ename) WITHIN GROUP(ORDER BY ename) AS employees
FROM listagg_test
GROUP BY deptno
ORDER BY deptno;

-- Cleanup
DROP TABLE listagg_test;

