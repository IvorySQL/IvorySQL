--
-- NANVL (Oracle-compatible)
--
-- This test file uses Oracle syntax as much as possible,
-- so the same SQL can be run on an Oracle database for verification.
--
-- Oracle references:
--   https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/NANVL.html
--

--
-- normal values (BINARY_FLOAT / BINARY_DOUBLE)
--
SELECT NANVL(CAST(1.5 AS BINARY_FLOAT), CAST(2.5 AS BINARY_FLOAT)) FROM DUAL;
SELECT NANVL(CAST(1.5 AS BINARY_DOUBLE), CAST(2.5 AS BINARY_DOUBLE)) FROM DUAL;
SELECT NANVL(CAST(-1.5 AS BINARY_FLOAT), CAST(2.5 AS BINARY_FLOAT)) FROM DUAL;
SELECT NANVL(CAST(0 AS BINARY_DOUBLE), CAST(2.5 AS BINARY_DOUBLE)) FROM DUAL;

--
-- NaN path (core behavior)
--
SELECT NANVL(CAST('NAN' AS BINARY_FLOAT), CAST(2.5 AS BINARY_FLOAT)) FROM DUAL;
SELECT NANVL(CAST('NAN' AS BINARY_DOUBLE), CAST(2.5 AS BINARY_DOUBLE)) FROM DUAL;
-- expr2 is also NaN: only expr1 is checked
SELECT NANVL(CAST('NAN' AS BINARY_FLOAT), CAST('NAN' AS BINARY_FLOAT)) FROM DUAL;

--
-- Infinity is not NaN (INF / -INF: Oracle uppercase)
--
SELECT NANVL(CAST('INF' AS BINARY_FLOAT), CAST(2.5 AS BINARY_FLOAT)) FROM DUAL;
SELECT NANVL(CAST('-INF' AS BINARY_DOUBLE), CAST(2.5 AS BINARY_DOUBLE)) FROM DUAL;

--
-- NULL handling: SQL standard — any NULL argument yields NULL
--
SELECT NANVL(CAST(NULL AS BINARY_FLOAT), CAST(2.5 AS BINARY_FLOAT)) FROM DUAL;
SELECT NANVL(CAST(1.5 AS BINARY_FLOAT), CAST(NULL AS BINARY_FLOAT)) FROM DUAL;
SELECT NANVL(CAST(NULL AS BINARY_FLOAT), CAST(NULL AS BINARY_FLOAT)) FROM DUAL;

--
-- table column scenario (non-constant path)
-- Oracle reference: same table structure as Oracle NANVL documentation example
--
CREATE TABLE nanvl_test_tbl (f1 BINARY_FLOAT, d1 BINARY_DOUBLE);
INSERT INTO nanvl_test_tbl VALUES (CAST('NAN' AS BINARY_FLOAT), CAST('NAN' AS BINARY_DOUBLE));
INSERT INTO nanvl_test_tbl VALUES (CAST(1.1 AS BINARY_FLOAT), CAST(2.2 AS BINARY_DOUBLE));
INSERT INTO nanvl_test_tbl VALUES (CAST(NULL AS BINARY_FLOAT), CAST(NULL AS BINARY_DOUBLE));
INSERT INTO nanvl_test_tbl VALUES (CAST('INF' AS BINARY_FLOAT), CAST('-INF' AS BINARY_DOUBLE));

SELECT f1, NANVL(f1, 0) FROM nanvl_test_tbl ORDER BY f1;
SELECT d1, NANVL(d1, 0) FROM nanvl_test_tbl ORDER BY d1;

DROP TABLE nanvl_test_tbl;

--
-- NUMBER overload
-- Oracle doc: "This function takes as arguments any numeric data type"
--
SELECT NANVL(CAST(1.23 AS NUMBER), 100) FROM DUAL;
SELECT NANVL(CAST('NAN' AS NUMBER), 100) FROM DUAL;
SELECT NANVL(CAST(NULL AS NUMBER), 100) FROM DUAL;
SELECT NANVL(CAST(1.23 AS NUMBER), CAST(NULL AS NUMBER)) FROM DUAL;

--
-- bare literal / implicit conversion overload resolution
-- Oracle doc: "Oracle determines the argument with the highest numeric
-- precedence, implicitly converts the remaining arguments to that data
-- type, and returns that data type."
--
-- In IvorySQL, bare integer/numeric literals resolve to BINARY_DOUBLE
-- (IvorySQL-specific behavior; Oracle would also use numeric precedence)
--
SELECT NANVL(1, 2) FROM DUAL;
SELECT NANVL(1.5, 2.5) FROM DUAL;
SELECT NANVL('NAN', 100) FROM DUAL;

--
-- Oracle numeric precedence: BINARY_DOUBLE > BINARY_FLOAT > NUMBER
-- Mixing BINARY_FLOAT and BINARY_DOUBLE yields BINARY_DOUBLE
--
SELECT NANVL(CAST(1.5 AS BINARY_FLOAT), CAST(2.5 AS BINARY_DOUBLE)) FROM DUAL;

--
-- negative zero: -0.0 is NOT NaN, must be returned unchanged
-- Note: Oracle displays -0, IvorySQL displays 0 (output format difference)
--
SELECT NANVL(CAST(-0.0 AS BINARY_FLOAT), CAST(99.0 AS BINARY_FLOAT)) FROM DUAL;
SELECT NANVL(CAST(-0.0 AS BINARY_DOUBLE), CAST(99.0 AS BINARY_DOUBLE)) FROM DUAL;
SELECT NANVL(CAST(-0.0 AS NUMBER), CAST(99.0 AS NUMBER)) FROM DUAL;

--
-- replacement with computed expression (not just constants)
--
SELECT NANVL(CAST('NAN' AS BINARY_FLOAT), CAST(1.0 AS BINARY_FLOAT) + CAST(2.0 AS BINARY_FLOAT)) FROM DUAL;
SELECT NANVL(CAST('NAN' AS NUMBER), 10 * 10) FROM DUAL;

--
-- Oracle documentation example (reproduced for compatibility verification)
-- https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/NANVL.html
--
CREATE TABLE float_point_demo
  (dec_num NUMBER(10,2), bin_double BINARY_DOUBLE, bin_float BINARY_FLOAT);

INSERT INTO float_point_demo VALUES (1234.56,
  CAST(1.235e+003 AS BINARY_DOUBLE), CAST(1.235e+003 AS BINARY_FLOAT));
INSERT INTO float_point_demo VALUES (0, CAST('NAN' AS BINARY_DOUBLE), CAST('NAN' AS BINARY_FLOAT));

SELECT bin_float, NANVL(bin_float, 0) FROM float_point_demo;

DROP TABLE float_point_demo;

--
-- wrong number of arguments (error cases)
--
SELECT NANVL(CAST(1.5 AS BINARY_FLOAT));
SELECT NANVL(CAST(1.5 AS BINARY_FLOAT), CAST(2.5 AS BINARY_FLOAT), CAST(3.5 AS BINARY_FLOAT));
SELECT NANVL();
