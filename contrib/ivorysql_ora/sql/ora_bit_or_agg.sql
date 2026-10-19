--
-- ora_bit_or_agg.sql: test Oracle-compatible BIT_OR_AGG aggregate function
--
-- This test file uses Oracle syntax as much as possible,
-- so the same SQL can be run on an Oracle database for verification.
--
-- Oracle references:
--   https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/BIT_OR_AGG.html
--

--
-- Basic usage
--
SELECT bit_or_agg(bits)
FROM (SELECT 3 bits FROM dual
      UNION ALL SELECT 5 FROM dual);

SELECT bit_or_agg(x) FROM (SELECT 12 x FROM dual
                           UNION ALL SELECT 10 FROM dual
                           UNION ALL SELECT 4 FROM dual) t;

--
-- GROUP BY usage
--
CREATE TABLE bit_or_agg_test (grp text, val bigint);
INSERT INTO bit_or_agg_test VALUES ('a', 12);
INSERT INTO bit_or_agg_test VALUES ('a', 10);
INSERT INTO bit_or_agg_test VALUES ('a', 6);
INSERT INTO bit_or_agg_test VALUES ('b', 7);
INSERT INTO bit_or_agg_test VALUES ('b', 5);
SELECT grp, bit_or_agg(val) FROM bit_or_agg_test GROUP BY grp ORDER BY grp;

--
-- NULL handling: NULLs are ignored
--
INSERT INTO bit_or_agg_test VALUES ('a', NULL);
SELECT grp, bit_or_agg(val) FROM bit_or_agg_test GROUP BY grp ORDER BY grp;

-- All-NULL group returns NULL
CREATE TABLE bit_or_agg_nulls (grp text, val bigint);
INSERT INTO bit_or_agg_nulls VALUES ('a', NULL);
INSERT INTO bit_or_agg_nulls VALUES ('a', NULL);
SELECT bit_or_agg(val) IS NULL FROM bit_or_agg_nulls;

-- Empty set returns NULL
SELECT bit_or_agg(val) IS NULL FROM bit_or_agg_test WHERE grp = 'NONE';

--
-- Negative values use two's complement
--
SELECT bit_or_agg(x) FROM (SELECT -1 x FROM dual
                           UNION ALL SELECT 6 FROM dual) t;
SELECT bit_or_agg(x) FROM (SELECT -8 x FROM dual
                           UNION ALL SELECT 12 FROM dual) t;

--
-- Fractional values are truncated toward zero before aggregating
--
SELECT bit_or_agg(x) FROM (SELECT 4.64 x FROM dual
                           UNION ALL SELECT 9.9 FROM dual) t;
SELECT bit_or_agg(x) FROM (SELECT 12.9 x FROM dual
                           UNION ALL SELECT 10.2 FROM dual) t;

--
-- NUMBER columns
--
CREATE TABLE bit_or_agg_number (grp text, val number);
INSERT INTO bit_or_agg_number VALUES ('a', 12);
INSERT INTO bit_or_agg_number VALUES ('a', 10);
INSERT INTO bit_or_agg_number VALUES ('a', NULL);
INSERT INTO bit_or_agg_number VALUES ('b', 15);
SELECT grp, bit_or_agg(val) FROM bit_or_agg_number GROUP BY grp ORDER BY grp;

--
-- The result type is NUMBER, as in Oracle
--
SELECT pg_typeof(bit_or_agg(val)) FROM bit_or_agg_test;

--
-- DISTINCT keyword
-- Bitwise OR is idempotent, so DISTINCT cannot change the result; the
-- query proves the keyword is accepted and no error is raised.
--
SELECT bit_or_agg(DISTINCT val) FROM bit_or_agg_test WHERE grp = 'a';

--
-- Window function usage (Oracle lists BIT_OR_AGG as an analytic
-- function too); the default RANGE frame keeps peer rows together.
--
SELECT grp, val, bit_or_agg(val) OVER (PARTITION BY grp ORDER BY val)
FROM bit_or_agg_test ORDER BY grp, val;

--
-- Values beyond the bigint domain raise an error
--
SELECT bit_or_agg(x) FROM (SELECT 99999999999999999999999 x FROM dual) t;

DROP TABLE bit_or_agg_test;
DROP TABLE bit_or_agg_nulls;
DROP TABLE bit_or_agg_number;

--
-- Works in PG mode too
--
SET ivorysql.compatible_mode = pg;
SELECT sys.bit_or_agg(x) FROM (VALUES (12), (10)) AS t(x);
RESET ivorysql.compatible_mode;
