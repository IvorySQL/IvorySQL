--
-- REMAINDER (Oracle-compatible)
--
-- This test file uses Oracle syntax as much as possible,
-- so the same SQL can be run on an Oracle database for verification.
--
-- Oracle references:
--   https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/REMAINDER.html
--
-- Oracle defines REMAINDER over three overloads (NUMBER, BINARY_FLOAT,
-- BINARY_DOUBLE) and "determines the argument with the highest numeric
-- precedence, implicitly converts the remaining arguments to that data
-- type, and returns that data type."  Numeric precedence is
-- BINARY_DOUBLE > BINARY_FLOAT > NUMBER.
--
-- The NUMBER path uses a round-half-to-EVEN quotient and raises
-- ORA-01476 on a zero divisor; the floating-point paths follow IEEE 754,
-- returning NaN for a zero divisor or an infinite dividend and keeping
-- the sign of a zero result.
--
-- IvorySQL exposes the same three overloads as the already-merged
-- sys.nanvl: (number, number), (binary_float, binary_float) and
-- (binary_double, binary_double).  In Oracle mode the function argument
-- precedence hook (oracle_funcarg_precedence_hook) resolves the call the
-- way Oracle numeric precedence dictates:
--
--   * ordinary numeric literals (integer, decimal, or an unknown string
--     literal in this numeric context) behave as NUMBER values, so the
--     all-literal form reaches the NUMBER body;
--   * a common target type is chosen with the Oracle numeric precedence
--     BINARY_DOUBLE > BINARY_FLOAT > NUMBER, which resolves the mixed
--     NUMBER/BINARY_FLOAT spellings to BINARY_FLOAT;
--   * a typed argument keeps its own family when the other operand is a
--     bare literal of lower precedence.
--
-- The assertions below pin those rules with pg_typeof() and assert the
-- Oracle results for the all-literal calls (ORA-01476 on a zero divisor,
-- full precision on a 20-digit literal, exact decimals).
--

set ivorysql.compatible_mode to oracle;

--
-- basic integer cases (NUMBER path)
--
SELECT REMAINDER(CAST(11 AS NUMBER), CAST(4 AS NUMBER)) FROM DUAL;
SELECT REMAINDER(CAST(-11 AS NUMBER), CAST(4 AS NUMBER)) FROM DUAL;
SELECT REMAINDER(CAST(5 AS NUMBER), CAST(3 AS NUMBER)) FROM DUAL;
SELECT REMAINDER(CAST(6 AS NUMBER), CAST(3 AS NUMBER)) FROM DUAL;
SELECT REMAINDER(CAST(1 AS NUMBER), CAST(3 AS NUMBER)) FROM DUAL;
SELECT REMAINDER(CAST(0 AS NUMBER), CAST(5 AS NUMBER)) FROM DUAL;

--
-- exact ties: quotient x.5 rounds to the EVEN integer (core behavior)
--
SELECT REMAINDER(CAST(0.5 AS NUMBER), 1) FROM DUAL;
SELECT REMAINDER(CAST(-0.5 AS NUMBER), 1) FROM DUAL;
SELECT REMAINDER(CAST(1.5 AS NUMBER), 1) FROM DUAL;
SELECT REMAINDER(CAST(-1.5 AS NUMBER), 1) FROM DUAL;
SELECT REMAINDER(CAST(2.5 AS NUMBER), 1) FROM DUAL;
SELECT REMAINDER(CAST(-2.5 AS NUMBER), 1) FROM DUAL;
SELECT REMAINDER(CAST(3.5 AS NUMBER), 1) FROM DUAL;
SELECT REMAINDER(CAST(-3.5 AS NUMBER), 1) FROM DUAL;
SELECT REMAINDER(CAST(25 AS NUMBER), 10) FROM DUAL;
SELECT REMAINDER(CAST(35 AS NUMBER), 10) FROM DUAL;
SELECT REMAINDER(CAST(-25 AS NUMBER), 10) FROM DUAL;
-- wide quotient: the tie digit survives the scale-38 multiplication of
-- the dividend (multiplying by 1.000...0, value 1, scale 38)
SELECT REMAINDER(CAST(10000000000000000001 AS NUMBER), 2) FROM DUAL;

--
-- non-integer quotients (no tie: nearest integer)
--
SELECT REMAINDER(CAST(4.5 AS NUMBER), 2) FROM DUAL;
SELECT REMAINDER(CAST(-4.5 AS NUMBER), 2) FROM DUAL;
SELECT REMAINDER(CAST(5.5 AS NUMBER), 2) FROM DUAL;
SELECT REMAINDER(CAST(15.3 AS NUMBER), 5) FROM DUAL;
SELECT REMAINDER(CAST(-15.3 AS NUMBER), 5) FROM DUAL;
SELECT REMAINDER(CAST(7 AS NUMBER), CAST(4.2 AS NUMBER)) FROM DUAL;
SELECT REMAINDER(CAST(1.05 AS NUMBER), CAST(0.3 AS NUMBER)) FROM DUAL;

--
-- NULL propagation on every family
--
SELECT REMAINDER(CAST(NULL AS NUMBER), 1) FROM DUAL;
SELECT REMAINDER(CAST(1 AS NUMBER), CAST(NULL AS NUMBER)) FROM DUAL;
SELECT REMAINDER(CAST(NULL AS BINARY_FLOAT), CAST(1 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST(1 AS BINARY_DOUBLE), CAST(NULL AS BINARY_DOUBLE)) FROM DUAL;

--
-- return type: the explicit NUMBER / BINARY_FLOAT / BINARY_DOUBLE pair
-- returns its own type (Oracle precedence base cases)
--
SELECT pg_typeof(REMAINDER(CAST(1 AS NUMBER), CAST(2 AS NUMBER))) FROM DUAL;
SELECT pg_typeof(REMAINDER(CAST(1 AS BINARY_FLOAT), CAST(2 AS BINARY_FLOAT))) FROM DUAL;
SELECT pg_typeof(REMAINDER(CAST(1 AS BINARY_DOUBLE), CAST(2 AS BINARY_DOUBLE))) FROM DUAL;
-- BINARY_DOUBLE outranks NUMBER and BINARY_FLOAT
SELECT pg_typeof(REMAINDER(CAST(1 AS NUMBER), CAST(2 AS BINARY_DOUBLE))) FROM DUAL;
SELECT pg_typeof(REMAINDER(CAST(1 AS BINARY_DOUBLE), CAST(2 AS NUMBER))) FROM DUAL;
SELECT pg_typeof(REMAINDER(CAST(1 AS BINARY_FLOAT), CAST(2 AS BINARY_DOUBLE))) FROM DUAL;
SELECT pg_typeof(REMAINDER(CAST(1 AS BINARY_DOUBLE), CAST(2 AS BINARY_FLOAT))) FROM DUAL;
-- Oracle numeric precedence: BINARY_FLOAT outranks NUMBER; both arguments
-- of a mixed NUMBER/BINARY_FLOAT call are converted to BINARY_FLOAT and
-- binary_float is returned (before the precedence hook these failed with
-- "function remainder(number, binary_float) is not unique")
SELECT pg_typeof(REMAINDER(CAST(1 AS NUMBER), CAST(2 AS BINARY_FLOAT))) FROM DUAL;
SELECT pg_typeof(REMAINDER(CAST(1 AS BINARY_FLOAT), CAST(2 AS NUMBER))) FROM DUAL;
-- an explicit cast keeps working and lands on the same family
SELECT pg_typeof(REMAINDER(CAST(1 AS NUMBER), CAST(2 AS BINARY_FLOAT)::NUMBER)) FROM DUAL;
SELECT pg_typeof(REMAINDER(CAST(1 AS NUMBER)::BINARY_FLOAT, CAST(2 AS BINARY_FLOAT))) FROM DUAL;
-- a bare literal next to a typed argument stays on that argument's family
SELECT pg_typeof(REMAINDER(CAST(1 AS NUMBER), 2)) FROM DUAL;
SELECT pg_typeof(REMAINDER(CAST(1 AS BINARY_FLOAT), 2)) FROM DUAL;
SELECT pg_typeof(REMAINDER(CAST(1 AS BINARY_DOUBLE), 2)) FROM DUAL;
-- all-literal calls follow Oracle numeric precedence: literals are NUMBER
-- values; the float4/float8 spellings map to BINARY_FLOAT/BINARY_DOUBLE
SELECT pg_typeof(REMAINDER(11, 4)) FROM DUAL;
SELECT pg_typeof(REMAINDER(1.05, 0.3)) FROM DUAL;
SELECT pg_typeof(REMAINDER(11::smallint, 4)) FROM DUAL;
SELECT pg_typeof(REMAINDER(1.5::float4, 2.5::float4)) FROM DUAL;
SELECT pg_typeof(REMAINDER(1.5::float8, 2.5::float8)) FROM DUAL;
SELECT pg_typeof(REMAINDER(1.5::numeric, 2.5::numeric)) FROM DUAL;
-- a quoted numeric literal is unknown at parse time and joins as NUMBER
SELECT pg_typeof(REMAINDER('7', 2)) FROM DUAL;
SELECT REMAINDER('7', 2) FROM DUAL;

--
-- all-literal calls behave like Oracle (the literals are NUMBER values,
-- so the call reaches the NUMBER body through the precedence hook)
--
-- A zero divisor raises ORA-01476 (division by zero), not NaN.
SELECT REMAINDER(7, 0) FROM DUAL;
-- A literal wider than a double keeps all 20 digits and returns 1.
SELECT REMAINDER(10000000000000000001, 2) FROM DUAL;
SELECT pg_typeof(REMAINDER(10000000000000000001, 2)) FROM DUAL;
-- The NUMBER path is exact (no binary-double rounding noise).
SELECT REMAINDER(15.3, 5) FROM DUAL;
SELECT REMAINDER(7, 4.2) FROM DUAL;
SELECT REMAINDER(1.05, 0.3) FROM DUAL;
-- The typed spellings agree with the bare-literal spellings.
SELECT REMAINDER(CAST(7 AS NUMBER), 0) FROM DUAL;
SELECT REMAINDER(CAST(10000000000000000001 AS NUMBER), 2) FROM DUAL;
SELECT REMAINDER(CAST(15.3 AS NUMBER), 5) FROM DUAL;
SELECT REMAINDER(CAST(7 AS NUMBER), CAST(4.2 AS NUMBER)) FROM DUAL;
SELECT REMAINDER(CAST(1.05 AS NUMBER), CAST(0.3 AS NUMBER)) FROM DUAL;

--
-- parameterized calls take the same precedence path: untyped bind
-- parameters arrive as unknown and join as NUMBER
--
SELECT REMAINDER($1, $2) FROM DUAL \bind 11 4 \g
SELECT REMAINDER($1, $2) FROM DUAL \bind 7 0 \g

--
-- BINARY_FLOAT path
--
SELECT REMAINDER(CAST(11 AS BINARY_FLOAT), CAST(4 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST(-11 AS BINARY_FLOAT), CAST(4 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST(2.5 AS BINARY_FLOAT), CAST(1 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST(1.5 AS BINARY_FLOAT), CAST(1 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST(-2.5 AS BINARY_FLOAT), CAST(1 AS BINARY_FLOAT)) FROM DUAL;

--
-- BINARY_DOUBLE path
--
SELECT REMAINDER(CAST(11 AS BINARY_DOUBLE), CAST(4 AS BINARY_DOUBLE)) FROM DUAL;
SELECT REMAINDER(CAST(-11 AS BINARY_DOUBLE), CAST(4 AS BINARY_DOUBLE)) FROM DUAL;
SELECT REMAINDER(CAST(2.5 AS BINARY_DOUBLE), CAST(1 AS BINARY_DOUBLE)) FROM DUAL;
SELECT REMAINDER(CAST(1.5 AS BINARY_DOUBLE), CAST(1 AS BINARY_DOUBLE)) FROM DUAL;
SELECT REMAINDER(CAST(-2.5 AS BINARY_DOUBLE), CAST(1 AS BINARY_DOUBLE)) FROM DUAL;

--
-- zero divisor: a typed NUMBER operand raises ORA-01476
-- (division_by_zero), the floating-point paths return NaN (no error)
-- Oracle doc: "If n1 = 0 ... Oracle returns An error if the arguments
-- are of type NUMBER / NaN if the arguments are BINARY_FLOAT or
-- BINARY_DOUBLE."
-- The all-literal spelling REMAINDER(7, 0) raises the same error: bare
-- literals are NUMBER values under the precedence hook; see the
-- "all-literal calls" section.
--
SELECT REMAINDER(CAST(7 AS NUMBER), CAST(0 AS NUMBER)) FROM DUAL;
SELECT REMAINDER(CAST(7 AS NUMBER), 0) FROM DUAL;
SELECT REMAINDER(CAST(7 AS BINARY_FLOAT), CAST(0 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST(7 AS BINARY_DOUBLE), CAST(0 AS BINARY_DOUBLE)) FROM DUAL;
SELECT REMAINDER(CAST(7 AS BINARY_FLOAT), CAST(-0 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST(0 AS BINARY_DOUBLE), CAST(0 AS BINARY_DOUBLE)) FROM DUAL;

--
-- infinite dividend yields NaN
-- Oracle doc: "If n1 = 0 or n2 = infinity, then Oracle returns ...
-- NaN if the arguments are BINARY_FLOAT or BINARY_DOUBLE."
-- (n2 is the dividend, the first argument)
--
SELECT REMAINDER(CAST('INF' AS BINARY_FLOAT), CAST(4 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST('-INF' AS BINARY_FLOAT), CAST(4 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST('INF' AS BINARY_DOUBLE), CAST(4 AS BINARY_DOUBLE)) FROM DUAL;
SELECT REMAINDER(CAST('-INF' AS BINARY_DOUBLE), CAST(4 AS BINARY_DOUBLE)) FROM DUAL;

--
-- an infinite divisor is not the documented NaN case; IEEE 754 leaves the
-- dividend unchanged
--
SELECT REMAINDER(CAST(7 AS BINARY_FLOAT), CAST('INF' AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST(7 AS BINARY_DOUBLE), CAST('INF' AS BINARY_DOUBLE)) FROM DUAL;

--
-- NaN propagates through both arguments
--
SELECT REMAINDER(CAST('NAN' AS BINARY_FLOAT), CAST(4 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST(7 AS BINARY_DOUBLE), CAST('NAN' AS BINARY_DOUBLE)) FROM DUAL;

--
-- sign of a floating-point zero result is preserved
-- Oracle doc: "If n2 is a floating-point number, and if the remainder is
-- 0, then the sign of the remainder is the sign of n2."
-- (n2 is the dividend, the first argument)
--
SELECT REMAINDER(CAST(-6 AS BINARY_FLOAT), CAST(3 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST(6 AS BINARY_FLOAT), CAST(3 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST(-6 AS BINARY_DOUBLE), CAST(3 AS BINARY_DOUBLE)) FROM DUAL;
SELECT REMAINDER(CAST(6 AS BINARY_DOUBLE), CAST(3 AS BINARY_DOUBLE)) FROM DUAL;
-- negative zero dividend keeps its sign
-- (a numeric literal -0.0 is normalised to +0 on input, so the sign has
-- to be introduced through the binary_double / binary_float input routine)
SELECT REMAINDER(CAST('-0' AS BINARY_FLOAT), CAST(3 AS BINARY_FLOAT)) FROM DUAL;
SELECT REMAINDER(CAST('-0' AS BINARY_DOUBLE), CAST(3 AS BINARY_DOUBLE)) FROM DUAL;
-- NUMBER remainders of 0 are unsigned
SELECT REMAINDER(CAST(-6 AS NUMBER), CAST(3 AS NUMBER)) FROM DUAL;
SELECT REMAINDER(CAST(6 AS NUMBER), CAST(3 AS NUMBER)) FROM DUAL;

--
-- table column scenario (non-constant path)
--
-- Every call below goes through a real column, so it exercises the
-- resolution path that migrated code actually uses.  The result type is
-- asserted explicitly: a NUMBER column must stay on the NUMBER path
-- (REMAINDER(n, 4) returns NUMBER, not BINARY_DOUBLE), a BINARY_FLOAT
-- column must return BINARY_FLOAT and a BINARY_DOUBLE column
-- BINARY_DOUBLE.  A literal (integer or decimal) next to a typed column
-- must not pull the call onto the BINARY_DOUBLE path.
--
CREATE TABLE remainder_test_tbl (n NUMBER, f BINARY_FLOAT, d BINARY_DOUBLE);
INSERT INTO remainder_test_tbl VALUES (11, CAST(11 AS BINARY_FLOAT), CAST(11 AS BINARY_DOUBLE));
INSERT INTO remainder_test_tbl VALUES (-11, CAST(-11 AS BINARY_FLOAT), CAST(-11 AS BINARY_DOUBLE));
INSERT INTO remainder_test_tbl VALUES (0, CAST('-0' AS BINARY_FLOAT), CAST('-0' AS BINARY_DOUBLE));
INSERT INTO remainder_test_tbl VALUES (10000000000000000001, CAST(1 AS BINARY_FLOAT), CAST(1 AS BINARY_DOUBLE));
INSERT INTO remainder_test_tbl VALUES (NULL, CAST(NULL AS BINARY_FLOAT), CAST(NULL AS BINARY_DOUBLE));

-- NUMBER column + integer literal -> NUMBER (was BINARY_DOUBLE before)
SELECT n, pg_typeof(REMAINDER(n, 4)) AS type, REMAINDER(n, 4) AS r
FROM remainder_test_tbl ORDER BY n;
-- NUMBER column + decimal literal -> NUMBER, no "is not unique" error
SELECT n, pg_typeof(REMAINDER(n, 1.5)) AS type, REMAINDER(n, 1.5) AS r
FROM remainder_test_tbl ORDER BY n;
-- wide NUMBER column value keeps its precision on the NUMBER path
SELECT n, pg_typeof(REMAINDER(n, 2)) AS type, REMAINDER(n, 2) AS r
FROM remainder_test_tbl WHERE n = 10000000000000000001;
-- BINARY_FLOAT column + integer literal -> BINARY_FLOAT (was BINARY_DOUBLE before)
SELECT f, pg_typeof(REMAINDER(f, 4)) AS type, REMAINDER(f, 4) AS r
FROM remainder_test_tbl ORDER BY f;
-- BINARY_DOUBLE column + integer literal -> BINARY_DOUBLE
SELECT d, pg_typeof(REMAINDER(d, 4)) AS type, REMAINDER(d, 4) AS r
FROM remainder_test_tbl ORDER BY d;

-- a NUMBER column with a zero divisor must raise, not return NaN
SELECT n, REMAINDER(n, 0) FROM remainder_test_tbl WHERE n = 11;

DROP TABLE remainder_test_tbl;

--
-- Oracle documentation example
-- https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/REMAINDER.html
-- The documented output is 5.859E-005. The value matches; the rendering
-- differs in precision only: Oracle shows 4 significant digits, while
-- IvorySQL prints the shortest round-trip decimal for the double, which
-- happens to carry more digits (both are scientific notation).
-- The two operands differ because BINARY_FLOAT cannot represent 1234.56
-- exactly.
--
CREATE TABLE float_point_demo
  (bin_float BINARY_FLOAT, bin_double BINARY_DOUBLE);
INSERT INTO float_point_demo VALUES (CAST(1234.56 AS BINARY_FLOAT),
                                    CAST(1234.56 AS BINARY_DOUBLE));

SELECT bin_float, bin_double, REMAINDER(bin_float, bin_double)
FROM float_point_demo;

DROP TABLE float_point_demo;

--
-- wrong number of arguments (error cases)
--
SELECT REMAINDER(1);
SELECT REMAINDER(1, 2, 3);

--
-- The precedence rewrite is a preference, not a mandate.  It applies only
-- to unqualified calls or to calls qualified with "sys": a user-defined
-- remainder in another schema keeps resolving with its own signature even
-- when the call passes numeric-looking literals, and a rewritten lookup
-- that finds no unique overload falls back to the actual argument types.
--
CREATE SCHEMA remainder_shadow;
CREATE FUNCTION remainder_shadow.remainder(a varchar2, b varchar2)
RETURN varchar2
IS
BEGIN
  RETURN a || b;
END;
/

-- the non-"sys" qualified call must reach the user-defined function
SELECT remainder_shadow.remainder('7', '0') FROM DUAL;

-- the sys-qualified builtin still follows Oracle numeric precedence
SELECT SYS.REMAINDER(7, 0) FROM DUAL;

DROP FUNCTION remainder_shadow.remainder(a varchar2, b varchar2);
DROP SCHEMA remainder_shadow;
