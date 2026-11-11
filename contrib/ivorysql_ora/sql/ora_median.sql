--
-- ora_median.sql: test Oracle-compatible MEDIAN aggregate function
--

-- Basic usage: odd number of values
SELECT sys.median(x) FROM (VALUES (3), (1), (2)) t(x);

-- Even number of values: mean of the two middle values
SELECT sys.median(x) FROM (VALUES (4), (1), (3), (2)) t(x);

-- Float values
SELECT sys.median(x) FROM (VALUES (1.5), (2.5), (3.5)) t(x);

-- NULL values are ignored
SELECT sys.median(x) FROM (VALUES (NULL), (1), (NULL), (3), (2)) t(x);

-- All-NULL input returns NULL
SELECT sys.median(x) IS NULL FROM (SELECT NULL::float8 AS x UNION ALL SELECT NULL::float8) t;

-- Empty set returns NULL
SELECT sys.median(x) FROM (SELECT 1 x WHERE false) t;

-- Single value
SELECT sys.median(x) FROM (VALUES (7)) t(x);

-- Numeric input (implicit cast to float8)
SELECT sys.median(x) FROM (VALUES (10::numeric), (20::numeric), (30::numeric)) t(x);

-- Integer input (implicit cast to float8)
SELECT sys.median(x) FROM (VALUES (10::int8), (20::int8)) t(x);

-- GROUP BY usage
CREATE TABLE median_test (dept TEXT, val float8);
INSERT INTO median_test VALUES ('HR', 1), ('HR', 2), ('HR', 9), ('IT', 10), ('IT', 20), ('IT', 30), ('IT', 40);
SELECT dept, sys.median(val) FROM median_test GROUP BY dept ORDER BY dept;

-- Negative and mixed-sign values
SELECT sys.median(x) FROM (VALUES (-5), (-1), (3)) t(x);

-- Works in PG mode too
SET ivorysql.compatible_mode = pg;
SELECT sys.median(x) FROM (VALUES (1), (2), (3)) t(x);
RESET ivorysql.compatible_mode;

DROP TABLE median_test;
