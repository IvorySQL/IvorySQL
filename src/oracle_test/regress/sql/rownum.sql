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
-- Issue #14: ROWNUM counter reset in correlated subqueries
-- ROWNUM counter must reset to 0 for each correlated subquery invocation.
-- This matches Oracle behavior where each subquery execution starts fresh.
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

-- Additional test: max ROWNUM in correlated subquery
-- Each group should have max_rn = 3 (not incrementing values)
SELECT
    id,
    (SELECT MAX(ROWNUM) FROM rownum_test t2 WHERE t2.id = t1.id) as max_rn
FROM rownum_test t1
WHERE id <= 5
GROUP BY id
ORDER BY id;

-- Test multiple correlated subqueries in same query
-- Both should reset independently
SELECT
    id,
    (SELECT COUNT(*) FROM rownum_test t2 WHERE t2.id = t1.id AND ROWNUM <= 2) as cnt_first_2,
    (SELECT MIN(ROWNUM) FROM rownum_test t2 WHERE t2.id = t1.id) as min_rn
FROM rownum_test t1
WHERE id <= 3
GROUP BY id
ORDER BY id;

-- Nested correlated subqueries
-- Inner and outer subqueries should both reset ROWNUM
SELECT
    id,
    (SELECT
        (SELECT ROWNUM FROM rownum_test t3 WHERE t3.id = t2.id ORDER BY value LIMIT 1)
     FROM rownum_test t2 WHERE t2.id = t1.id LIMIT 1) as nested_rn
FROM rownum_test t1
WHERE id <= 3
ORDER BY id;

-- Correlated subquery with ROWNUM in JOIN condition
SELECT
    t1.id,
    (SELECT COUNT(*)
     FROM rownum_test t2
     JOIN rownum_test t3 ON t2.id = t3.id
     WHERE t2.id = t1.id AND ROWNUM <= 1) as join_count
FROM rownum_test t1
WHERE id <= 3
GROUP BY id
ORDER BY id;

--
-- Nested ROWNUM expression tests (CodeRabbit improvements)
--

-- ROWNUM in arithmetic expressions with ORDER BY
SELECT
    id,
    value,
    ROWNUM * 10 as rownum_x10,
    ROWNUM + value as rownum_plus_value
FROM rownum_test
WHERE id <= 5
ORDER BY value DESC;

-- ROWNUM in CASE expression with ORDER BY
SELECT
    id,
    value,
    CASE
        WHEN ROWNUM <= 2 THEN 'Top 2'
        WHEN ROWNUM <= 5 THEN 'Top 5'
        ELSE 'Other'
    END as tier
FROM rownum_test
ORDER BY value DESC
LIMIT 7;

-- ROWNUM in function calls with ORDER BY
SELECT
    id,
    value,
    COALESCE(ROWNUM, 0) as coalesced_rn,
    GREATEST(ROWNUM, 1) as greatest_rn
FROM rownum_test
WHERE id <= 5
ORDER BY value;

-- Multiple nested ROWNUM expressions in same SELECT
SELECT
    id,
    ROWNUM as rn1,
    ROWNUM * 2 as rn2,
    CASE WHEN ROWNUM <= 3 THEN ROWNUM * 100 ELSE 0 END as rn3
FROM rownum_test
WHERE id <= 5
ORDER BY value DESC;

-- ROWNUM in subquery expression with ORDER BY
SELECT
    id,
    value,
    (SELECT ROWNUM) as subquery_rn,
    ROWNUM + (SELECT 10) as expr_rn
FROM rownum_test
WHERE id <= 5
ORDER BY value;

-- ROWNUM in aggregate function with ORDER BY
SELECT
    dept_id,
    MAX(ROWNUM) as max_rownum,
    MIN(ROWNUM) as min_rownum,
    COUNT(ROWNUM) as count_rownum
FROM (
    SELECT dept_id, ROWNUM
    FROM rownum_test
    ORDER BY value DESC
) sub
GROUP BY dept_id
ORDER BY dept_id;

--
-- Projection capability tests (change_plan_targetlist usage)
--

-- Test ROWNUM with Material node (non-projection-capable)
SELECT DISTINCT ON (dept_id)
    dept_id,
    ROWNUM as rn,
    value
FROM rownum_test
ORDER BY dept_id, value DESC;

-- Test ROWNUM with Sort -> Unique pipeline
SELECT DISTINCT
    ROWNUM as rn,
    dept_id
FROM (
    SELECT dept_id, ROWNUM
    FROM rownum_test
    ORDER BY value DESC
) sub
WHERE ROWNUM <= 5;

-- Test ROWNUM with SetOp (non-projection-capable)
-- With UNION ROWNUM fix, each branch has independent ROWNUM (Oracle behavior)
SELECT ROWNUM as rn, id FROM rownum_test WHERE id <= 3
UNION
SELECT ROWNUM as rn, id FROM rownum_test WHERE id > 7
ORDER BY rn, id;

--
-- Edge cases for ROWNUM reset
--

-- ROWNUM in EXISTS correlated subquery
SELECT
    id,
    EXISTS(SELECT 1 FROM rownum_test t2 WHERE t2.id = t1.id AND ROWNUM = 1) as has_first
FROM rownum_test t1
WHERE id <= 5
ORDER BY id;

-- ROWNUM in NOT EXISTS correlated subquery
SELECT
    id,
    NOT EXISTS(SELECT 1 FROM rownum_test t2 WHERE t2.id = t1.id AND ROWNUM > 5) as all_within_5
FROM rownum_test t1
WHERE id <= 3
ORDER BY id;

-- ROWNUM in IN correlated subquery
SELECT
    id,
    1 IN (SELECT ROWNUM FROM rownum_test t2 WHERE t2.id = t1.id) as has_rownum_1
FROM rownum_test t1
WHERE id <= 3
ORDER BY id;

--
-- UNION ALL with ROWNUM
-- In Oracle, each UNION branch has independent ROWNUM counter.
-- The counter resets when switching between UNION branches.
--

-- Basic UNION ALL with ROWNUM
SELECT ROWNUM, id FROM (SELECT 1 AS id FROM DUAL UNION ALL SELECT 2 FROM DUAL UNION ALL SELECT 3 FROM DUAL)
UNION ALL
SELECT ROWNUM, id FROM (SELECT 4 AS id FROM DUAL UNION ALL SELECT 5 FROM DUAL UNION ALL SELECT 6 FROM DUAL);

-- UNION ALL with tables
SELECT ROWNUM, id FROM (SELECT id FROM rownum_test WHERE id <= 3 ORDER BY id)
UNION ALL
SELECT ROWNUM, id FROM (SELECT id FROM rownum_test WHERE id BETWEEN 4 AND 6 ORDER BY id);

-- Multiple UNION ALL branches
SELECT ROWNUM, 'a' as src FROM (SELECT 1 FROM DUAL UNION ALL SELECT 2 FROM DUAL)
UNION ALL
SELECT ROWNUM, 'b' as src FROM (SELECT 1 FROM DUAL UNION ALL SELECT 2 FROM DUAL)
UNION ALL
SELECT ROWNUM, 'c' as src FROM (SELECT 1 FROM DUAL UNION ALL SELECT 2 FROM DUAL);

--
-- UNION (not UNION ALL) with ROWNUM
-- UNION uses MergeAppend + Unique nodes, so needs different ROWNUM reset handling.
-- Each UNION branch should have independent ROWNUM counting.
--

-- Test 1: Simple UNION with ROWNUM
-- Creates two tables to avoid relying on ordering within branches
CREATE TABLE test1 (id int);
CREATE TABLE test2 (id int);
INSERT INTO test1 VALUES (1), (2), (3);
INSERT INTO test2 VALUES (4), (5), (6);

-- Each branch should have ROWNUM 1,2,3 independently
-- Result is sorted by the UNION's deduplication process
SELECT ROWNUM as rn, id FROM test1
UNION
SELECT ROWNUM as rn, id FROM test2
ORDER BY rn, id;

-- Test 2: UNION with ORDER BY in subqueries
SELECT ROWNUM as rn, id FROM (SELECT id FROM test1 ORDER BY id)
UNION
SELECT ROWNUM as rn, id FROM (SELECT id FROM test2 ORDER BY id)
ORDER BY rn, id;

-- Test 3: Multiple UNION branches
SELECT ROWNUM, 'a' as src FROM (SELECT 1 FROM DUAL UNION ALL SELECT 2 FROM DUAL)
UNION
SELECT ROWNUM, 'b' as src FROM (SELECT 1 FROM DUAL UNION ALL SELECT 2 FROM DUAL)
UNION
SELECT ROWNUM, 'c' as src FROM (SELECT 1 FROM DUAL UNION ALL SELECT 2 FROM DUAL)
ORDER BY src, rownum;

DROP TABLE test1;
DROP TABLE test2;

--
-- INTERSECT and EXCEPT with ROWNUM
-- NOTE: Oracle resets ROWNUM for each side of INTERSECT/EXCEPT independently.
-- Current IvorySQL implementation shares ROWNUM counter across both sides,
-- which produces different results than Oracle.
--

-- INTERSECT with ROWNUM
-- Oracle: Each side produces (1,1), (2,2), (3,3) independently, intersection = 3 rows
-- IvorySQL: Left side produces (1,1), (2,2), (3,3), right side produces (4,1), (5,2), (6,3)
--           No intersection because ROWNUM values differ
SELECT ROWNUM as rn, id FROM (SELECT 1 as id FROM dual UNION ALL SELECT 2 FROM dual UNION ALL SELECT 3 FROM dual)
INTERSECT
SELECT ROWNUM as rn, id FROM (SELECT 1 as id FROM dual UNION ALL SELECT 2 FROM dual UNION ALL SELECT 3 FROM dual)
ORDER BY rn;

-- EXCEPT with ROWNUM
-- Oracle: Left (1,1),(2,2),(3,3) EXCEPT Right (1,2) = (1,1),(2,2),(3,3) (no match on rn)
-- IvorySQL: Left (1,1),(2,2),(3,3) EXCEPT Right (4,2) = (1,1),(2,2),(3,3)
SELECT ROWNUM as rn, id FROM (SELECT 1 as id FROM dual UNION ALL SELECT 2 FROM dual UNION ALL SELECT 3 FROM dual)
EXCEPT
SELECT ROWNUM as rn, id FROM (SELECT 2 as id FROM dual)
ORDER BY rn;

--
-- LATERAL join with ROWNUM
-- NOTE: Oracle resets ROWNUM for each outer row in LATERAL/CROSS APPLY.
-- Current IvorySQL implementation does not reset, counter continues across outer rows.
--

CREATE TABLE lat_test (id int);
INSERT INTO lat_test VALUES (1), (2), (3);

-- LATERAL subquery with ROWNUM
-- Oracle produces: (1,1), (2,1), (2,2), (3,1), (3,2), (3,3) - resets for each outer row
-- IvorySQL produces: (1,1), (2,2), (2,3), (3,4), (3,5), (3,6) - counter continues
SELECT t.id as outer_id, sub.rn
FROM lat_test t,
LATERAL (SELECT ROWNUM as rn FROM lat_test lt WHERE lt.id <= t.id) sub
ORDER BY t.id, sub.rn;

DROP TABLE lat_test;

--
-- DELETE with ROWNUM
-- Oracle supports DELETE WHERE ROWNUM <= N to delete first N rows
--

CREATE TABLE del_test (id int, val varchar(10));
INSERT INTO del_test VALUES (1, 'a'), (2, 'b'), (3, 'c'), (4, 'd'), (5, 'e');

-- Delete first 2 rows
DELETE FROM del_test WHERE ROWNUM <= 2;
SELECT * FROM del_test ORDER BY id;

DROP TABLE del_test;

--
-- UPDATE with ROWNUM
-- Oracle supports UPDATE ... WHERE ROWNUM <= N to update first N rows
--

CREATE TABLE upd_test (id int, val varchar(10));
INSERT INTO upd_test VALUES (1, 'a'), (2, 'b'), (3, 'c'), (4, 'd'), (5, 'e');

-- Update first 2 rows
UPDATE upd_test SET val = 'updated' WHERE ROWNUM <= 2;
SELECT * FROM upd_test ORDER BY id;

DROP TABLE upd_test;

--
-- ROWNUM with empty table
--

CREATE TABLE empty_test (id int);

-- ROWNUM on empty table should return no rows
SELECT ROWNUM, id FROM empty_test;
SELECT COUNT(*) FROM empty_test WHERE ROWNUM <= 5;

DROP TABLE empty_test;

--
-- ROWNUM pagination with nested subqueries
-- Common Oracle pagination pattern: SELECT FROM (SELECT ... ROWNUM) WHERE rnum >= N
--

CREATE TABLE eemp(
    empno NUMBER(4) NOT NULL CONSTRAINT emp_pk PRIMARY KEY,
    ename VARCHAR2(10),
    sal NUMBER(7,2)
);

INSERT INTO eemp VALUES (7369,'SMITH',800);
INSERT INTO eemp VALUES (7499,'ALLEN',1600);
INSERT INTO eemp VALUES (7521,'WARD',1250);
INSERT INTO eemp VALUES (7566,'JONES',2975);
INSERT INTO eemp VALUES (7654,'MARTIN',1250);
INSERT INTO eemp VALUES (7698,'BLAKE',2850);
INSERT INTO eemp VALUES (7782,'CLARK',2450);
INSERT INTO eemp VALUES (7788,'SCOTT',3000);
INSERT INTO eemp VALUES (7839,'KING',5000);
INSERT INTO eemp VALUES (7844,'TURNER',1500);
INSERT INTO eemp VALUES (7876,'ADAMS',1100);
INSERT INTO eemp VALUES (7900,'JAMES',950);
INSERT INTO eemp VALUES (7902,'FORD',3000);
INSERT INTO eemp VALUES (7934,'MILLER',1300);

-- Pagination query: get rows 8-12 (sorted by sal)
-- This is the standard Oracle pagination pattern
SELECT *
FROM (
    SELECT a.*, rownum rnum
    FROM (
        SELECT empno, sal
        FROM eemp
        ORDER BY sal
    ) a
    WHERE rownum <= 12
)
WHERE rnum >= 8;

-- Expected result:
--  empno |   sal   | rnum
-- -------+---------+------
--  7499  | 1600.00 |    8
--  7782  | 2450.00 |    9
--  7698  | 2850.00 |   10
--  7566  | 2975.00 |   11
--  7902  | 3000.00 |   12
-- (5 rows)

-- Verify ROWNUM values are consecutive in inner query
SELECT empno, sal, rownum as rnum
FROM (
    SELECT empno, sal
    FROM eemp
    ORDER BY sal
) a
WHERE rownum <= 12;

DROP TABLE eemp;

--
-- ROWNUM with GROUP BY validation
-- ROWNUM must appear in GROUP BY clause or be used in aggregate function
--

CREATE TABLE grp_test (id int, category varchar(10));
INSERT INTO grp_test VALUES (1, 'A'), (2, 'A'), (3, 'B'), (4, 'B'), (5, 'C');

-- Error: ROWNUM not in GROUP BY and not in aggregate
SELECT rownum FROM grp_test GROUP BY category;

-- OK: ROWNUM in GROUP BY clause
SELECT rownum FROM grp_test GROUP BY rownum ORDER BY rownum;

DROP TABLE grp_test;

--
-- ROWNUM with aggregate functions
-- Aggregate functions should evaluate ROWNUM for each row during scan
--

CREATE TABLE agg_test (id int, val int);
INSERT INTO agg_test VALUES (1, 10), (2, 20), (3, 30), (4, 40), (5, 50), (6, 60);

-- MIN/MAX/SUM/AVG with ROWNUM
-- For 6 rows: MIN=1, MAX=6, SUM=21, AVG=3.5
SELECT MIN(rownum), MAX(rownum), SUM(rownum), AVG(rownum) FROM agg_test;

-- COUNT with ROWNUM
SELECT COUNT(*), COUNT(rownum) FROM agg_test;

-- Aggregate with ROWNUM expression
SELECT SUM(rownum * 2), SUM(rownum) * 2 FROM agg_test;

-- Aggregate with ROWNUM and GROUP BY
SELECT val / 20 as grp, MIN(rownum), MAX(rownum)
FROM agg_test
GROUP BY val / 20
ORDER BY grp;

DROP TABLE agg_test;

--
-- ROWNUM with nested aggregate functions
-- Test that ROWNUM works correctly in nested subqueries with aggregates
--

CREATE TABLE agg_nest_test (id int, val int);
INSERT INTO agg_nest_test VALUES (1, 10), (2, 20), (3, 30), (4, 40), (5, 50), (6, 60);

-- Subquery with aggregate containing ROWNUM
SELECT * FROM (
    SELECT MIN(rownum) as min_rn, MAX(rownum) as max_rn, SUM(rownum) as sum_rn
    FROM agg_nest_test
) sub;

-- Aggregate of subquery with ROWNUM
SELECT SUM(rn) FROM (SELECT rownum as rn FROM agg_nest_test) sub;

-- Nested subquery aggregates (use float division for Oracle compatibility)
SELECT MAX(sum_rn) FROM (
    SELECT val/20.0 as grp, SUM(rownum) as sum_rn
    FROM agg_nest_test
    GROUP BY val/20.0
) sub;

-- Multiple levels of aggregation
SELECT AVG(max_rn) FROM (
    SELECT val/30.0 as grp, MAX(rownum) as max_rn
    FROM agg_nest_test
    GROUP BY val/30.0
) sub;

DROP TABLE agg_nest_test;

--
-- Cleanup
--

DROP TABLE rownum_test CASCADE;
DROP TABLE dept CASCADE;
