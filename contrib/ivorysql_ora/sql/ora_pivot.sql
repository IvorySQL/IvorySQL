--
-- ora_pivot.sql: test Oracle-compatible PIVOT / UNPIVOT clauses
--

-- =============================================
-- PIVOT tests
-- =============================================

CREATE TABLE pivot_sales (dept TEXT, quarter TEXT, amount NUMERIC);
INSERT INTO pivot_sales VALUES
    ('HR', 'Q1', 100), ('HR', 'Q2', 150), ('HR', 'Q3', 180),
    ('IT', 'Q1', 200), ('IT', 'Q2', 250), ('IT', 'Q3', 300),
    ('SALES', 'Q1', 50), ('SALES', 'Q2', 75), ('SALES', 'Q3', 90);

-- Basic PIVOT with explicit aliases
SELECT * FROM pivot_sales
    PIVOT (SUM(amount) FOR quarter IN ('Q1' AS q1, 'Q2' AS q2, 'Q3' AS q3))
    ORDER BY dept;

-- Default column names derived from item literals
SELECT * FROM pivot_sales
    PIVOT (SUM(amount) FOR quarter IN ('Q1', 'Q2', 'Q3'))
    ORDER BY dept;

-- Multiple aggregate functions
SELECT * FROM pivot_sales
    PIVOT (SUM(amount) AS total, COUNT(*) AS cnt FOR quarter IN ('Q1' AS q1, 'Q2' AS q2))
    ORDER BY dept;

-- COUNT(*) as the aggregate
SELECT * FROM pivot_sales
    PIVOT (COUNT(*) FOR quarter IN ('Q1' AS q1, 'Q2' AS q2))
    ORDER BY dept;

-- PIVOT over a subquery
SELECT * FROM (SELECT dept, quarter, amount FROM pivot_sales WHERE amount > 100)
    PIVOT (COUNT(*) FOR dept IN ('HR' AS hr, 'IT' AS it))
    ORDER BY hr, it;

-- PIVOT with numeric IN items
SELECT * FROM pivot_sales
    PIVOT (SUM(amount) AS amt FOR amount IN (100, 200))
    ORDER BY dept;

-- PIVOT with multiple FOR columns
SELECT * FROM pivot_sales
    PIVOT (COUNT(*) FOR dept, quarter IN (('HR', 'Q1') AS hr_q1, ('IT', 'Q1') AS it_q1))
    ORDER BY hr_q1, it_q1;

-- Implicit grouping: dept is the only non-aggregate, non-FOR column
SELECT dept, q1, q2 FROM pivot_sales
    PIVOT (SUM(amount) AS amt FOR quarter IN ('Q1' AS q1, 'Q2' AS q2))
    ORDER BY dept;

-- PIVOT with WHERE clause
SELECT * FROM pivot_sales
    WHERE dept != 'SALES'
    PIVOT (SUM(amount) FOR quarter IN ('Q1' AS q1, 'Q2' AS q2))
    ORDER BY dept;

-- Empty result set: aggregates are NULL
SELECT * FROM pivot_sales
    PIVOT (SUM(amount) AS s FOR quarter IN ('Q9' AS q9))
    ORDER BY dept;

-- Aliased pivot result
SELECT p.q1, p.q2, p.dept FROM pivot_sales
    PIVOT (SUM(amount) FOR quarter IN ('Q1' AS q1, 'Q2' AS q2)) p
    ORDER BY p.dept;

-- PIVOT with MAX and MIN
SELECT * FROM pivot_sales
    PIVOT (MAX(amount) AS mx, MIN(amount) AS mn FOR quarter IN ('Q1' AS q1))
    ORDER BY dept;

-- PIVOT with AVG (returns numeric)
SELECT * FROM pivot_sales
    PIVOT (AVG(amount) AS av FOR quarter IN ('Q1' AS q1, 'Q2' AS q2))
    ORDER BY dept;

-- =============================================
-- UNPIVOT tests
-- =============================================

CREATE TABLE unpivot_sales (id INT, dept TEXT, q1 INT, q2 INT, q3 INT);
INSERT INTO unpivot_sales VALUES
    (1, 'HR', 10, 20, NULL),
    (2, 'IT', NULL, NULL, 30),
    (3, 'SALES', 40, 50, 60);

-- UNPIVOT with default EXCLUDE NULLS
SELECT * FROM unpivot_sales
    UNPIVOT (val FOR quarter IN (q1 AS 'Q1', q2 AS 'Q2', q3 AS 'Q3'))
    ORDER BY id, quarter;

-- UNPIVOT with INCLUDE NULLS
SELECT * FROM unpivot_sales
    UNPIVOT INCLUDE NULLS (val FOR quarter IN (q1 AS 'Q1', q2 AS 'Q2', q3 AS 'Q3'))
    ORDER BY id, quarter;

-- UNPIVOT with explicit EXCLUDE NULLS
SELECT * FROM unpivot_sales
    UNPIVOT EXCLUDE NULLS (val FOR quarter IN (q1 AS 'Q1', q2 AS 'Q2', q3 AS 'Q3'))
    ORDER BY id, quarter;

-- UNPIVOT with default naming from source columns
SELECT * FROM unpivot_sales
    UNPIVOT (val FOR quarter IN (q1, q2, q3))
    ORDER BY id, quarter;

-- UNPIVOT with WHERE clause on the outer query
SELECT * FROM unpivot_sales
    UNPIVOT (val FOR quarter IN (q1 AS 'Q1', q2 AS 'Q2', q3 AS 'Q3'))
    WHERE val > 15
    ORDER BY id, quarter;

-- UNPIVOT with alias on the result
SELECT u.id, u.quarter, u.val FROM unpivot_sales
    UNPIVOT (val FOR quarter IN (q1 AS 'Q1', q2 AS 'Q2', q3 AS 'Q3')) u
    WHERE u.val IS NOT NULL
    ORDER BY u.id, u.quarter;

-- =============================================
-- Round-trip: PIVOT then UNPIVOT
-- =============================================

CREATE TABLE roundtrip_source (dept TEXT, quarter TEXT, amount NUMERIC);
INSERT INTO roundtrip_source VALUES
    ('A', 'Q1', 1), ('A', 'Q2', 2),
    ('B', 'Q1', 3), ('B', 'Q2', 4);

SELECT dept, quarter, amount FROM roundtrip_source
    PIVOT (SUM(amount) FOR quarter IN ('Q1' AS q1, 'Q2' AS q2))
    UNPIVOT (amount FOR quarter IN (q1 AS 'Q1', q2 AS 'Q2'))
    ORDER BY dept, quarter;

DROP TABLE pivot_sales;
DROP TABLE unpivot_sales;
DROP TABLE roundtrip_source;
