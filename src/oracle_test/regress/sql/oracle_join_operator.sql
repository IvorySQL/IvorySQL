--
-- Oracle join (+) operator test queries
--

-- Create test tables
CREATE TABLE t1 (
    c1 NUMBER PRIMARY KEY,
    c2 VARCHAR2(50)
);

CREATE TABLE t2 (
    c1 NUMBER PRIMARY KEY,
    c2 VARCHAR2(50),
    c3 NUMBER
);

CREATE TABLE t3 (
    c1 NUMBER,
    c2 NUMBER,
    c3 VARCHAR2(50)
);

-- Insert sample data
INSERT INTO t1 VALUES (10, 't1_a');
INSERT INTO t1 VALUES (20, 't1_b');
INSERT INTO t1 VALUES (30, 't1_c');
INSERT INTO t1 VALUES (40, 't1_d');

INSERT INTO t2 VALUES (1, 't2_a', 10);
INSERT INTO t2 VALUES (2, 't2_b', 10);
INSERT INTO t2 VALUES (3, 't2_c', 20);
INSERT INTO t2 VALUES (4, 't2_d', NULL);
INSERT INTO t2 VALUES (5, 't2_e', 50);

INSERT INTO t3 VALUES (1, 1, 't3_a');
INSERT INTO t3 VALUES (2, 2, 't3_b');
INSERT INTO t3 VALUES (3, 99, 't3_c');

-- Test: Basic left outer join (+ on right side)
SELECT t2.c2 AS t2_c2, t1.c2 AS t1_c2
FROM t2, t1
WHERE t2.c3 = t1.c1(+)
ORDER BY t2.c2;

-- Test: Basic left outer join (+ on right side) with spaces and comments between the operator
SELECT t2.c2 AS t2_c2, t1.c2 AS t1_c2
FROM t2, t1
WHERE t2.c3 = t1.c1(  + -- comment
)
ORDER BY t2.c2;

-- Test: Filtered left outer join
SELECT t2.c2 AS t2_c2, t1.c2 AS t1_c2
FROM t2, t1
WHERE t2.c3 = t1.c1(+)
AND t2.c2 LIKE 't2_a%'
ORDER BY t2.c2;

-- Test: Multiple conditions with left outer join
SELECT t2.c2 AS t2_c2, t1.c2 AS t1_c2
FROM t2, t1
WHERE t2.c3 = t1.c1(+)
AND (t2.c2 IN ('t2_a', 't2_c', 't2_d') OR t1.c2 = 't1_a')
ORDER BY t2.c2;

-- Test: Basic right outer join (+ on left side)
SELECT t1.c2 AS t1_c2, t2.c2 AS t2_c2
FROM t2, t1
WHERE t2.c3(+) = t1.c1;

-- Test: Filtered right outer join
SELECT t1.c2 AS t1_c2, t2.c2 AS t2_c2
FROM t2, t1
WHERE t2.c3(+) = t1.c1
AND t1.c2 = 't1_c';

-- Test: Complex WHERE clause with right outer join
SELECT t1.c2 AS t1_c2, t2.c2 AS t2_c2
FROM t2, t1
WHERE t2.c3(+) = t1.c1
AND (t1.c2 IN ('t1_a', 't1_b') OR t2.c2 IS NULL)
ORDER BY t1.c2;

-- AGGREGATION TESTS WITH OUTER JOINS
-- Test: Row count per t1 row using right outer join
SELECT t1.c2 AS t1_c2, COUNT(t2.c1) AS t2_count
FROM t2, t1
WHERE t2.c3(+) = t1.c1
GROUP BY t1.c2
ORDER BY t1.c2;

-- Test: Complex filtering with outer join
SELECT t2.c2 AS t2_c2, t1.c2 AS t1_c2
FROM t2, t1
WHERE t2.c3 = t1.c1(+)
AND (t1.c2 = 't1_a' OR t2.c3 IS NULL)
ORDER BY t2.c2;

-- EDGE CASE TESTS
-- Test: Multiple outer joins

SELECT t2.c2 AS t2_c2, t1.c2 AS t1_c2, t3.c3 AS t3_c3
FROM t2, t1, t3
WHERE t2.c3 = t1.c1(+)
AND t2.c1 = t3.c2(+)
ORDER BY t2.c2;

-- NON-RELATION FROM ITEM TESTS
-- These exercise get_orajoin_fromclause_node(): the (+) join operand is
-- a CTE / VALUES list / subquery / set-returning function, none of which
-- have a usable pg_class relid, so the original FROM node must be
-- preserved rather than rebuilt from relid.

-- Test: Oracle join operator with a CTE as the (+) operand (RTE_CTE)
WITH t1_cte AS (
    SELECT c1, c2 FROM t1
)
SELECT t2.c2 AS t2_c2, t1_cte.c2 AS t1_cte_c2
FROM t2, t1_cte
WHERE t2.c3 = t1_cte.c1(+)
ORDER BY t2.c2;

-- Test: Oracle join operator with the CTE on the (+) side itself
WITH t2_cte AS (
    SELECT c1, c2, c3 FROM t2
)
SELECT t1.c2 AS t1_c2, t2_cte.c2 AS t2_cte_c2
FROM t2_cte, t1
WHERE t2_cte.c3(+) = t1.c1
ORDER BY t1.c2;

-- Test: Oracle join operator with a VALUES list as the (+) operand (RTE_VALUES)
SELECT t2.c2 AS t2_c2, v.v_c2 AS v_c2
FROM t2, (VALUES (10, 't1_a'), (20, 't1_b'), (30, 't1_c'), (40, 't1_d')) AS v(v_c1, v_c2)
WHERE t2.c3 = v.v_c1(+)
ORDER BY t2.c2;

-- Test: Oracle join operator with a subquery as the (+) operand (RTE_SUBQUERY)
SELECT t2.c2 AS t2_c2, s.c2 AS s_c2
FROM t2, (SELECT c1, c2 FROM t1) s
WHERE t2.c3 = s.c1(+)
ORDER BY t2.c2;

-- Test: Oracle join operator with a set-returning function as the (+) operand (RTE_FUNCTION)
CREATE OR REPLACE FUNCTION t1_rows() RETURNS TABLE(c1 NUMBER, c2 VARCHAR2(50)) AS
$$
BEGIN
    RETURN QUERY SELECT t1.c1, t1.c2 FROM t1;
END;
$$ LANGUAGE plpgsql;
/

SELECT t2.c2 AS t2_c2, f.c2 AS f_c2
FROM t2, t1_rows() AS f
WHERE t2.c3 = f.c1(+)
ORDER BY t2.c2;

-- Test: Multiple non-relation operands combined in one query (CTE + subquery)
WITH t3_cte AS (
    SELECT c1, c2, c3 FROM t3
)
SELECT t2.c2 AS t2_c2, s.c2 AS t1_c2, t3_cte.c3 AS t3_c3
FROM t2, (SELECT c1, c2 FROM t1) s, t3_cte
WHERE t2.c3 = s.c1(+)
AND t2.c1 = t3_cte.c2(+)
ORDER BY t2.c2;

-- JOIN GRAPH IDENTITY TESTS
-- These exercise extractOraJoins()'s graph-by-rtindex construction:
-- multiple predicates for the same relation pair, independent join pairs
-- in a single query, and repeated aliases of the same relation.

CREATE TABLE t4 (
    id NUMBER,
    code NUMBER,
    label VARCHAR2(50)
);

CREATE TABLE t5 (
    id NUMBER,
    code NUMBER,
    label VARCHAR2(50)
);

INSERT INTO t4 VALUES (1, 100, 't4_a');
INSERT INTO t4 VALUES (2, 200, 't4_b');
INSERT INTO t4 VALUES (3, 300, 't4_c');

INSERT INTO t5 VALUES (1, 100, 't5_a');   -- id AND code both match t4 row 1
INSERT INTO t5 VALUES (2, 999, 't5_b');   -- id matches t4 row 2, code does not
INSERT INTO t5 VALUES (4, 400, 't5_d');   -- matches nothing in t4

-- Test: Two (+) predicates for the SAME relation pair must fold into one
-- JoinExpr ON clause (id AND code both required), not create a second
-- JoinExpr that reintroduces t5 as a duplicate operand.
-- Expected: t4_a -> t5_a (both columns match); t4_b -> NULL (code 200 !=
-- 999, so despite id matching this must NOT be treated as a match);
-- t4_c -> NULL (no id match at all).
SELECT t4.label AS t4_label, t5.label AS t5_label
FROM t4, t5
WHERE t4.id = t5.id(+)
AND t4.code = t5.code(+)
ORDER BY t4.label;

-- Test: Two INDEPENDENT (+) join pairs in the same query must not be
-- chained onto each other. (t4 outer-joined to t5) and (t1 preserved,
-- t2 outer-joined) are unrelated pairs; since nothing connects the two
-- groups, they combine as an implicit cross join between the two
-- outer-join results -- exactly like an ordinary comma-separated FROM
-- list would, just with each pair independently outer-joined.
-- Expected: 3 rows from the t4/t5 outer join (t4_a/t5_a, t4_b/NULL,
-- t4_c/NULL) crossed with 5 rows from the t1/t2 outer join (t1_a paired
-- with both t2 rows whose c3=10, t1_b/t2_c, t1_c/NULL, t1_d/NULL) = 15
-- rows total. What matters here is that the query parses and executes
-- without error and without either pair leaking rows/aliases into the
-- other -- not any specific row ordering within the 15.
SELECT t4.label AS t4_label, t5.label AS t5_label,
       t1.c2 AS t1_c2, t2.c2 AS t2_c2
FROM t4, t5, t1, t2
WHERE t4.id = t5.id(+)
AND t1.c1 = t2.c3(+)
ORDER BY t4.label, t1.c2, t2.c2;

-- Test: Self join using two aliases of the same relation. Alias identity
-- (rtindex), not relation name, must distinguish "a" from "b" -- both
-- have relname 't1', which the old relname-based logic would confuse.
-- Expected: t1_a has no predecessor row (c1-10 = 0, no match) -> NULL;
-- t1_b's predecessor is t1_a; t1_c's predecessor is t1_b; t1_d's
-- predecessor is t1_c.
SELECT a.c2 AS a_c2, b.c2 AS prev_c2
FROM t1 a, t1 b
WHERE b.c1(+) = a.c1 - 10
ORDER BY a.c1;

-- SCHEMA-QUALIFIED COLUMN REFERENCE TESTS
-- These exercise the parse_expr.c fix: OraJoinState must be populated in
-- the three-part (schema.table.col) and four-part (db.schema.table.col)
-- ColumnRef resolution branches too, not just the one-part/two-part
-- cases, or a predicate like "t2.c3 = public.t1.c1(+)" silently falls
-- through to an ordinary WHERE condition instead of becoming a join.

-- Test: three-part reference (schema.table.col) as the (+) operand.
-- Expected: identical to the very first basic-left-outer-join test,
-- since public.t1 is the same table as t1.
-- t2_a -> t1_a, t2_b -> t1_a, t2_c -> t1_b, t2_d -> NULL, t2_e -> NULL
SELECT t2.c2 AS t2_c2, t1.c2 AS t1_c2
FROM t2, t1
WHERE t2.c3 = public.t1.c1(+)
ORDER BY t2.c2;

-- Test: three-part reference marked with (+) on the LEFT side (right
-- outer join), and the other operand also three-part qualified.
-- Expected: t1_a matches two t2 rows (c3=10 twice) so it appears twice;
-- t1_b -> t2_c; t1_c and t1_d have no matching t2 row -> NULL.
SELECT t1.c2 AS t1_c2, t2.c2 AS t2_c2
FROM t2, t1
WHERE public.t2.c3(+) = public.t1.c1
ORDER BY t1.c2;

-- Test: four-part reference (database.schema.table.col) as the (+)
-- operand. The database name isn't known ahead of time, so this builds
-- the query dynamically with current_database() and captures the result
-- in a temp table for display, rather than hardcoding a database name.
-- Expected result set: same as the three-part test above.
DO $$
DECLARE
    dbname text := current_database();
BEGIN
    EXECUTE format($f$
        CREATE TEMP TABLE fourpart_orajoin_result AS
        SELECT t2.c2 AS t2_c2, t1.c2 AS t1_c2
        FROM t2, t1
        WHERE t2.c3 = %I.public.t1.c1(+)
        ORDER BY t2.c2
    $f$, dbname);
END $$;

SELECT * FROM fourpart_orajoin_result;
DROP TABLE fourpart_orajoin_result;

--OR/NOT rejection, pair-direction conflict detection, and the multi-table chain refold
-- Test: (+) inside OR must throw error
SELECT t2.c2, t1.c2
FROM t2, t1
WHERE t2.c3 = t1.c1(+) OR t2.c2 = 't2_a';

-- Test: (+) inside NOT must throw error
SELECT t1.c2, t2.c2
FROM t1, t2
WHERE NOT (t2.c3 = t1.c1(+))
ORDER BY t1.c2;

-- Test: A top-level OR with no (+) at all must still filter correctly
SELECT t2.c2, t2.c3
FROM t2
WHERE t2.c1 = 1 OR t2.c1 = 2
ORDER BY t2.c2;

-- Test:Conflicting outer-join direction for the same pair must throw error
SELECT t4.label, t5.label
FROM t4, t5
WHERE t4.id = t5.id(+)
AND t4.code(+) = t5.code
ORDER BY t4.label;

-- Test:Three-table chain where a later predicate must refold into the first pair, not the second
-- Needs fresh data to make it unambiguous:
CREATE TABLE ta (id NUMBER, code NUMBER, label VARCHAR2(50));
CREATE TABLE tb (id NUMBER, code NUMBER, ta_id NUMBER, label VARCHAR2(50));
CREATE TABLE tc (id NUMBER, tb_id NUMBER, label VARCHAR2(50));

INSERT INTO ta VALUES (1, 10, 'ta_1');
INSERT INTO ta VALUES (2, 20, 'ta_2');
INSERT INTO tb VALUES (1, 10, 1, 'tb_1');   -- matches ta_1 on id AND code
INSERT INTO tb VALUES (2, 99, 2, 'tb_2');   -- matches ta_2 on id only, not code
INSERT INTO tc VALUES (1, 1, 'tc_1');       -- matches tb_1

SELECT ta.label AS ta_label, tb.label AS tb_label, tc.label AS tc_label
FROM ta, tb, tc
WHERE ta.id = tb.ta_id(+)
AND tb.id = tc.tb_id(+)
AND ta.code = tb.code(+)
ORDER BY ta.label;

-- Clean up
DROP FUNCTION t1_rows();

DROP TABLE tc;
DROP TABLE tb;
DROP TABLE ta;
DROP TABLE t5;
DROP TABLE t4;
DROP TABLE t3;
DROP TABLE t2;
DROP TABLE t1;
