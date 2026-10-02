--
-- MOD (Oracle-compatible)
--
-- This test file uses Oracle syntax as much as possible,
-- so the same SQL can be run on an Oracle database for verification.
--
-- Oracle references:
--   https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/MOD.html
--
-- Oracle: "MOD returns the remainder of n2 divided by n1. Returns n2 if n1 is 0."
-- PostgreSQL's mod(n2, 0) raises division-by-zero; sys.mod returns n2.

--
-- official example (SQLRF MOD): MOD(11,4) = 3
--
SELECT MOD(11,4) FROM DUAL;
SELECT PG_TYPEOF(MOD(11,4)) FROM DUAL;

--
-- official sign-convention table (SQLRF MOD):
--   n2=11,  n1=4  ->  3
--   n2=11,  n1=-4 ->  3
--   n2=-11, n1=4  -> -3
--   n2=-11, n1=-4 -> -3
--
SELECT MOD(11,4), MOD(11,-4), MOD(-11,4), MOD(-11,-4) FROM DUAL;

--
-- zero divisor: Oracle returns n2 (PostgreSQL raises division-by-zero)
--
SELECT MOD(7,0) FROM DUAL;
SELECT MOD(-7,0) FROM DUAL;
SELECT MOD(0,0) FROM DUAL;
SELECT MOD(CAST(9223372036854775807 AS BIGINT), 0) FROM DUAL;
SELECT MOD(CAST(7 AS SMALLINT), 0) FROM DUAL;
SELECT MOD(CAST(7 AS NUMBER), 0) FROM DUAL;
SELECT MOD(CAST(7 AS NUMERIC), 0) FROM DUAL;
SELECT MOD(-11.5, 0) FROM DUAL;

--
-- zero divisor keeps the type of the remainder: NUMBER
--
SELECT PG_TYPEOF(MOD(7,0)) FROM DUAL;

--
-- remainder sign follows n2 for column values too
--
CREATE TABLE mod_t (n2_val NUMBER, n1_val NUMBER);
INSERT INTO mod_t VALUES (-11, 4);
INSERT INTO mod_t VALUES (11, -4);
INSERT INTO mod_t VALUES (7, 0);
SELECT MOD(n2_val, n1_val) FROM mod_t;

--
-- NULL propagation (STRICT)
--
SELECT MOD(NULL, 4) IS NULL FROM DUAL;
SELECT MOD(11, NULL) IS NULL FROM DUAL;
SELECT MOD(NULL, NULL) IS NULL FROM DUAL;

--
-- mixed literal types
--
SELECT MOD(7, 2.5) FROM DUAL;
SELECT MOD(2.5, 7) FROM DUAL;
SELECT PG_TYPEOF(MOD(7, 2.5)) FROM DUAL;

--
-- large mixed-type operands keep working (no ambiguity regression):
-- n2 NUMBER, n1 NUMERIC
--
SELECT MOD(999999999999999999999::number, 1000000000000000000000) FROM DUAL;

--
-- qualified and unqualified calls agree
--
SELECT MOD(11,4) = SYS.MOD(11,4) FROM DUAL;

--
-- unchanged PostgreSQL behavior for pg_catalog-qualified calls
--
SELECT PG_CATALOG.MOD(11,4) FROM DUAL;
SELECT PG_CATALOG.MOD(7,0) FROM DUAL;
