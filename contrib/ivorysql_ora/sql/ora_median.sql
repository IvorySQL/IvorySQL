--
-- ora_median.sql: test Oracle-compatible MEDIAN aggregate function
--
-- MEDIAN is Oracle's continuous-distribution median: the middle value of
-- the ordered set (odd count) or the mean of the two middle values (even
-- count).  NULLs are ignored; an empty set yields NULL.
--

-- Odd number of values: middle value of the ordered set
SELECT sys.median(x) FROM (VALUES (1), (2), (3)) t(x);

-- Even number of values: mean of the two middle values
SELECT sys.median(x) FROM (VALUES (1), (2), (3), (4)) t(x);

-- Unordered input gives the same result as ordered input
SELECT sys.median(x) FROM (VALUES (3), (1), (2)) t(x);

-- NULLs are ignored
SELECT sys.median(x) FROM (VALUES (1), (NULL), (2), (3)) t(x);

-- All-NULL input returns NULL
SELECT sys.median(x) FROM (VALUES (NULL::numeric), (NULL)) t(x);

-- Empty set returns NULL
SELECT sys.median(x) FROM (VALUES (1::numeric)) t(x) WHERE false;

-- Values of other numeric types resolve to the numeric aggregate
SELECT sys.median(x) FROM (VALUES (10::int), (20), (30)) t(x);

-- float8 input (implicit cast to numeric)
SELECT sys.median(x) FROM (VALUES (1.5::float8), (2.5), (3.5)) t(x);

-- Duplicate values
SELECT sys.median(x) FROM (VALUES (2), (2), (1)) t(x);

-- Negative values
SELECT sys.median(x) FROM (VALUES (-3), (-1), (-2)) t(x);

-- GROUP BY
SELECT g, sys.median(v) FROM (VALUES (1, 10), (1, 20), (2, 100), (2, 200), (2, 300)) t(g, v) GROUP BY g ORDER BY g;

-- Window frame: running median
SELECT x, sys.median(x) OVER (ORDER BY x) FROM (VALUES (1), (2), (3), (4)) t(x) ORDER BY x;

-- Works in PostgreSQL mode too
SET ivorysql.compatible_mode = pg;
SELECT sys.median(x) FROM (VALUES (1), (2), (3)) t(x);
RESET ivorysql.compatible_mode;
