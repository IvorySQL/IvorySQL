--
-- ROWNUM
-- Test Oracle ROWNUM pseudocolumn functionality
--

-- Setup test data
CREATE TABLE rownum_test (
    id int,
    name varchar(50),
    value int
);

INSERT INTO rownum_test VALUES
    (1, 'Alice', 100),
    (2, 'Bob', 200),
    (3, 'Charlie', 150),
    (4, 'David', 300),
    (5, 'Eve', 250),
    (6, 'Frank', 175),
    (7, 'Grace', 225),
    (8, 'Henry', 125),
    (9, 'Iris', 275),
    (10, 'Jack', 190);

--
-- Basic ROWNUM queries
--

-- ROWNUM <= N (should use LIMIT optimization)
SELECT id, name FROM rownum_test WHERE ROWNUM <= 5;

-- ROWNUM = 1 (should use LIMIT 1)
SELECT id, name FROM rownum_test WHERE ROWNUM = 1;

-- ROWNUM < N (should use LIMIT N-1)
SELECT id, name FROM rownum_test WHERE ROWNUM < 4;

-- ROWNUM in SELECT list
SELECT ROWNUM, id, name FROM rownum_test WHERE ROWNUM <= 3;

--
-- ROWNUM with ORDER BY
-- (requires subquery pattern to order first, then limit)
--

-- Top-N by value (descending)
SELECT * FROM (
    SELECT id, name, value
    FROM rownum_test
    ORDER BY value DESC
) WHERE ROWNUM <= 3;

-- Top-N by name (ascending)
SELECT * FROM (
    SELECT id, name
    FROM rownum_test
    ORDER BY name
) WHERE ROWNUM <= 5;

-- ROWNUM = 1 with ORDER BY (get minimum)
SELECT * FROM (
    SELECT id, name, value
    FROM rownum_test
    ORDER BY value
) WHERE ROWNUM = 1;

--
-- ROWNUM in nested subqueries
--

-- Subquery with ROWNUM in WHERE clause
SELECT name FROM (
    SELECT id, name FROM rownum_test WHERE ROWNUM <= 7
) sub WHERE id > 3;

-- Multiple levels of ROWNUM
SELECT * FROM (
    SELECT * FROM (
        SELECT id, name FROM rownum_test WHERE ROWNUM <= 8
    ) WHERE ROWNUM <= 5
) WHERE ROWNUM <= 3;

--
-- ROWNUM with JOINs
--

CREATE TABLE dept (
    dept_id int,
    dept_name varchar(50)
);

INSERT INTO dept VALUES
    (1, 'Engineering'),
    (2, 'Sales'),
    (3, 'Marketing');

-- Update test data to include dept_id
ALTER TABLE rownum_test ADD COLUMN dept_id int;
UPDATE rownum_test SET dept_id = (id % 3) + 1;

-- ROWNUM with JOIN
SELECT e.id, e.name, d.dept_name
FROM (SELECT * FROM rownum_test WHERE ROWNUM <= 5) e
JOIN dept d ON e.dept_id = d.dept_id
ORDER BY e.id;

-- JOIN with ORDER BY and ROWNUM
SELECT * FROM (
    SELECT e.id, e.name, e.value, d.dept_name
    FROM rownum_test e
    JOIN dept d ON e.dept_id = d.dept_id
    ORDER BY e.value DESC
) WHERE ROWNUM <= 4;

--
-- Edge cases and non-optimizable patterns
--

-- ROWNUM > 0 (tautology, returns all rows - Oracle semantics)
SELECT COUNT(*) FROM rownum_test WHERE ROWNUM > 0;

-- ROWNUM >= 1 (tautology, returns all rows - Oracle semantics)
SELECT COUNT(*) FROM rownum_test WHERE ROWNUM >= 1;

-- ROWNUM > N where N >= 1 (returns empty - Oracle semantics)
SELECT id, name FROM rownum_test WHERE ROWNUM > 5;
SELECT COUNT(*) FROM rownum_test WHERE ROWNUM > 1;

-- ROWNUM >= N where N > 1 (returns empty - Oracle semantics)
SELECT id, name FROM rownum_test WHERE ROWNUM >= 2;
SELECT COUNT(*) FROM rownum_test WHERE ROWNUM >= 2;

-- ROWNUM = 0 (always false)
SELECT id, name FROM rownum_test WHERE ROWNUM = 0;

-- ROWNUM = 2 (not optimizable, returns empty - Oracle semantics)
SELECT id, name FROM rownum_test WHERE ROWNUM = 2;

-- ROWNUM = 3 (not optimizable, returns empty - Oracle semantics)
SELECT id, name FROM rownum_test WHERE ROWNUM = 3;

-- ROWNUM with negative number
SELECT id, name FROM rownum_test WHERE ROWNUM <= -1;

-- ROWNUM in complex WHERE clause (AND)
SELECT id, name FROM rownum_test WHERE ROWNUM <= 5 AND id > 2;

-- ROWNUM in complex WHERE clause (OR - not optimizable)
SELECT id, name FROM rownum_test WHERE ROWNUM <= 3 OR id = 10;

--
-- ROWNUM with DISTINCT
--

SELECT DISTINCT dept_id FROM rownum_test WHERE ROWNUM <= 6;

--
-- ROWNUM with aggregate functions
--

-- ROWNUM with GROUP BY (applied before grouping)
SELECT dept_id, COUNT(*)
FROM (SELECT * FROM rownum_test WHERE ROWNUM <= 7)
GROUP BY dept_id
ORDER BY dept_id;

--
-- Issue #12: ROWNUM with same-level ORDER BY, DISTINCT, GROUP BY, aggregation
-- These should NOT be transformed to LIMIT because of semantic differences
--

-- Direct COUNT with ROWNUM (should count only first 5 rows, not all rows)
SELECT COUNT(*) FROM rownum_test WHERE ROWNUM <= 5;

-- Direct ORDER BY with ROWNUM (should pick first 5 rows, THEN sort them)
-- NOT the same as "ORDER BY value LIMIT 5" which sorts all rows first
SELECT id, name, value FROM rownum_test WHERE ROWNUM <= 5 ORDER BY value;

-- Direct DISTINCT with ROWNUM (should DISTINCT over first 3 rows only)
-- NOT the same as "SELECT DISTINCT ... LIMIT 3" which distincts all rows first
CREATE TABLE rownum_distinct_test (category varchar(10));
INSERT INTO rownum_distinct_test VALUES ('A'), ('A'), ('B'), ('B'), ('C'), ('C');
SELECT DISTINCT category FROM rownum_distinct_test WHERE ROWNUM <= 3;
DROP TABLE rownum_distinct_test;

-- Direct GROUP BY with ROWNUM (should group only first 4 rows)
-- NOT the same as "GROUP BY ... LIMIT N" which groups all rows first
CREATE TABLE rownum_group_test (category varchar(10), amount int);
INSERT INTO rownum_group_test VALUES
    ('A', 10), ('A', 20), ('B', 30), ('B', 40), ('C', 50), ('C', 60);
SELECT category, SUM(amount)
FROM rownum_group_test
WHERE ROWNUM <= 4
GROUP BY category
ORDER BY category;
DROP TABLE rownum_group_test;

--
-- Verify optimizer transformation with EXPLAIN
--

-- Should show Limit node for ROWNUM <= N
EXPLAIN (COSTS OFF) SELECT id, name FROM rownum_test WHERE ROWNUM <= 5;

-- Should show Limit node for ROWNUM = 1
EXPLAIN (COSTS OFF) SELECT id, name FROM rownum_test WHERE ROWNUM = 1;

-- Should show Limit node for ROWNUM < N
EXPLAIN (COSTS OFF) SELECT id, name FROM rownum_test WHERE ROWNUM < 4;

-- Subquery pattern should show Limit node
EXPLAIN (COSTS OFF)
SELECT * FROM (
    SELECT id, name, value
    FROM rownum_test
    ORDER BY value DESC
) WHERE ROWNUM <= 3;

-- ROWNUM > 0 (tautology, should remove qual entirely)
EXPLAIN (COSTS OFF) SELECT COUNT(*) FROM rownum_test WHERE ROWNUM > 0;

-- ROWNUM >= 1 (tautology, should remove qual entirely)
EXPLAIN (COSTS OFF) SELECT COUNT(*) FROM rownum_test WHERE ROWNUM >= 1;

-- ROWNUM > 5 (should show One-Time Filter: false)
EXPLAIN (COSTS OFF) SELECT id, name FROM rownum_test WHERE ROWNUM > 5;

-- ROWNUM > 1 with aggregation (should show One-Time Filter: false)
EXPLAIN (COSTS OFF) SELECT COUNT(*) FROM rownum_test WHERE ROWNUM > 1;

-- ROWNUM >= 2 (should show One-Time Filter: false)
EXPLAIN (COSTS OFF) SELECT id, name FROM rownum_test WHERE ROWNUM >= 2;

-- ROWNUM = 2 should NOT be optimized to LIMIT (should show One-Time Filter: false)
EXPLAIN (COSTS OFF) SELECT id, name FROM rownum_test WHERE ROWNUM = 2;

-- Issue #12: These should NOT show Limit because of same-level operations
-- Direct COUNT with ROWNUM (has aggregation, should not use LIMIT)
EXPLAIN (COSTS OFF) SELECT COUNT(*) FROM rownum_test WHERE ROWNUM <= 5;

-- Direct ORDER BY with ROWNUM (has ORDER BY, should not use LIMIT)
EXPLAIN (COSTS OFF) SELECT id, name FROM rownum_test WHERE ROWNUM <= 5 ORDER BY value;

-- Direct DISTINCT with ROWNUM (has DISTINCT, should not use LIMIT)
EXPLAIN (COSTS OFF) SELECT DISTINCT dept_id FROM rownum_test WHERE ROWNUM <= 5;

--
-- ROWNUM with other clauses
--

-- ROWNUM with OFFSET (not standard Oracle, but test interaction)
SELECT id, name FROM rownum_test WHERE ROWNUM <= 5 OFFSET 2;

-- ROWNUM with FETCH FIRST (should work together)
SELECT id, name FROM rownum_test WHERE ROWNUM <= 8 FETCH FIRST 3 ROWS ONLY;

--
-- ROWNUM in SELECT list with ORDER BY (Issue: ORDER BY bug fix)
-- These test the fix for ROWNUM being evaluated at wrong level when combined with ORDER BY
--

-- Basic case: ROWNUM in SELECT with ORDER BY
-- ROWNUM values should reflect row position BEFORE sort, not after
SELECT * FROM (
    SELECT ROWNUM as rn, id, name, value
    FROM rownum_test
    ORDER BY value DESC
) sub WHERE rn <= 3;

-- Verify ROWNUM values are assigned before ORDER BY (not sequential 1,2,3)
SELECT ROWNUM as rn, id, name, value
FROM rownum_test
ORDER BY value DESC;

-- ROWNUM in SELECT with ORDER BY and outer filter
SELECT * FROM (
    SELECT ROWNUM as rn, id, name, value
    FROM rownum_test
    ORDER BY value DESC
) sub WHERE rn > 2 AND rn <= 5;

-- Multiple ROWNUM columns at different nesting levels
SELECT ROWNUM as outer_rn, * FROM (
    SELECT ROWNUM as middle_rn, * FROM (
        SELECT ROWNUM as inner_rn, id, name, value
        FROM rownum_test
        ORDER BY value DESC
    ) sub1
    ORDER BY value ASC
) sub2
ORDER BY id
LIMIT 5;

-- ROWNUM in SELECT with ORDER BY and JOIN
SELECT * FROM (
    SELECT ROWNUM as rn, e.id, e.name, e.value, d.dept_name
    FROM rownum_test e
    JOIN dept d ON e.dept_id = d.dept_id
    ORDER BY e.value DESC
) sub WHERE rn <= 4;

-- Test that ROWNUM is materialized (not re-evaluated in outer query)
-- This tests the materialization fix
SELECT rn, id, name FROM (
    SELECT ROWNUM as rn, id, name, value
    FROM rownum_test
    ORDER BY value DESC
) sub
ORDER BY rn  -- Sorting by rn should not re-evaluate ROWNUM
LIMIT 5;

-- EXPLAIN: Verify ROWNUM is pushed to scan level before Sort
EXPLAIN (COSTS OFF, VERBOSE)
SELECT * FROM (
    SELECT ROWNUM as rn, id, name, value
    FROM rownum_test
    ORDER BY value DESC
) sub WHERE rn <= 3;

--
-- Issue #14: ROWNUM counter not reset in correlated subqueries (KNOWN BUG)
-- This test demonstrates a bug where es_rownum is not reset between
-- correlated subquery invocations. Expected: all values should be 1.
-- Actual: values increment across invocations (3, 6, 9, 12, 15).
-- Bug report: https://github.com/rophy/IvorySQL/issues/14
--
SELECT
    id,
    name,
    (SELECT ROWNUM FROM (
        SELECT * FROM rownum_test t2
        WHERE t2.id = t1.id
        ORDER BY value DESC
    ) sub) as correlated_rn
FROM rownum_test t1
ORDER BY id
LIMIT 5;

--
-- Cleanup
--

DROP TABLE rownum_test CASCADE;
DROP TABLE dept CASCADE;
