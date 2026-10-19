--
-- ora_bit_xor_agg.sql: test Oracle-compatible BIT_XOR_AGG aggregate function
--
-- This test file uses Oracle syntax as much as possible,
-- so the same SQL can be run on an Oracle database for verification.
--
-- Oracle references:
--   https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/BIT_XOR_AGG.html
--

--
-- Basic usage
--
SELECT bit_xor_agg(bits)
FROM (SELECT 3 bits FROM dual
      UNION ALL SELECT 5 FROM dual);

SELECT bit_xor_agg(x) FROM (SELECT 12 x FROM dual
                            UNION ALL SELECT 10 FROM dual
                            UNION ALL SELECT 4 FROM dual) t;

--
-- GROUP BY usage
--
CREATE TABLE bit_xor_agg_test (grp text, val bigint);
INSERT INTO bit_xor_agg_test VALUES ('a', 12);
INSERT INTO bit_xor_agg_test VALUES ('a', 10);
INSERT INTO bit_xor_agg_test VALUES ('a', 6);
INSERT INTO bit_xor_agg_test VALUES ('b', 7);
INSERT INTO bit_xor_agg_test VALUES ('b', 5);
SELECT grp, bit_xor_agg(val) FROM bit_xor_agg_test GROUP BY grp ORDER BY grp;

--
-- NULL handling: NULLs are ignored
--
INSERT INTO bit_xor_agg_test VALUES ('a', NULL);
SELECT grp, bit_xor_agg(val) FROM bit_xor_agg_test GROUP BY grp ORDER BY grp;

-- All-NULL group returns NULL
CREATE TABLE bit_xor_agg_nulls (grp text, val bigint);
INSERT INTO bit_xor_agg_nulls VALUES ('a', NULL);
INSERT INTO bit_xor_agg_nulls VALUES ('a', NULL);
SELECT bit_xor_agg(val) IS NULL FROM bit_xor_agg_nulls;

-- Empty set returns NULL
SELECT bit_xor_agg(val) IS NULL FROM bit_xor_agg_test WHERE grp = 'NONE';

--
-- Negative values use two's complement
--
SELECT bit_xor_agg(x) FROM (SELECT -1 x FROM dual
                            UNION ALL SELECT 6 FROM dual) t;
SELECT bit_xor_agg(x) FROM (SELECT -8 x FROM dual
                            UNION ALL SELECT 12 FROM dual) t;

--
-- Fractional values are truncated toward zero before aggregating
--
SELECT bit_xor_agg(x) FROM (SELECT 4.64 x FROM dual
                            UNION ALL SELECT 4.4 FROM dual) t;
SELECT bit_xor_agg(x) FROM (SELECT 12.9 x FROM dual
                            UNION ALL SELECT 10.2 FROM dual) t;

--
-- NUMBER columns
--
CREATE TABLE bit_xor_agg_number (grp text, val number);
INSERT INTO bit_xor_agg_number VALUES ('a', 12);
INSERT INTO bit_xor_agg_number VALUES ('a', 10);
INSERT INTO bit_xor_agg_number VALUES ('a', NULL);
INSERT INTO bit_xor_agg_number VALUES ('b', 15);
SELECT grp, bit_xor_agg(val) FROM bit_xor_agg_number GROUP BY grp ORDER BY grp;

--
-- DISTINCT keyword
--
SELECT bit_xor_agg(DISTINCT val) FROM bit_xor_agg_test WHERE grp = 'a';

--
-- Values beyond the bigint domain raise an error
--
SELECT bit_xor_agg(x) FROM (SELECT 99999999999999999999999 x FROM dual) t;

DROP TABLE bit_xor_agg_test;
DROP TABLE bit_xor_agg_nulls;
DROP TABLE bit_xor_agg_number;

--
-- Works in PG mode too
--
SET ivorysql.compatible_mode = pg;
SELECT sys.bit_xor_agg(x) FROM (SELECT 12 x FROM dual
                                UNION ALL SELECT 10 FROM dual) t;
RESET ivorysql.compatible_mode;
