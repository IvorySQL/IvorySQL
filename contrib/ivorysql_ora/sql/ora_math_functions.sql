--
-- SQRT, EXP, LN, LOG and POWER with integer and string arguments
-- (Oracle-compatible)
--
-- Oracle computes these functions on NUMBER and returns NUMBER.  An integer
-- argument used to bind the float8 versions and keep about 16 digits.
--
-- Oracle references:
--   https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SQRT.html
--   https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/POWER.html
--   https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html
--

--
-- values returned by Oracle 23ai, from issue #2020
--
SELECT POWER(3, 50) FROM DUAL;
SELECT TO_CHAR(POWER(3, 50)) FROM DUAL;
SELECT POWER(2, 64) FROM DUAL;
SELECT TO_CHAR(SQRT(2)) FROM DUAL;

--
-- every integer type gets a numeric result
--
SELECT pg_typeof(SQRT(2)) AS sqrt, pg_typeof(EXP(1)) AS exp,
       pg_typeof(LN(2)) AS ln, pg_typeof(LOG(100)) AS log1,
       pg_typeof(LOG(2, 8)) AS log2, pg_typeof(POWER(2, 3)) AS power
FROM DUAL;
SELECT SQRT(CAST(2 AS SMALLINT)) AS int2, SQRT(CAST(2 AS INTEGER)) AS int4,
       SQRT(CAST(2 AS BIGINT)) AS int8 FROM DUAL;
SELECT EXP(CAST(1 AS SMALLINT)) AS int2, EXP(CAST(1 AS BIGINT)) AS int8 FROM DUAL;
SELECT LN(CAST(2 AS SMALLINT)) AS int2, LN(CAST(2 AS BIGINT)) AS int8 FROM DUAL;
SELECT LOG(CAST(2 AS SMALLINT)) AS int2, LOG(CAST(2 AS BIGINT)) AS int8 FROM DUAL;
SELECT LOG(CAST(2 AS SMALLINT), CAST(3 AS SMALLINT)) AS int2,
       LOG(CAST(2 AS BIGINT), CAST(3 AS BIGINT)) AS int8 FROM DUAL;
SELECT POWER(CAST(3 AS SMALLINT), CAST(-1 AS SMALLINT)) AS int2,
       POWER(CAST(3 AS BIGINT), CAST(40 AS BIGINT)) AS int8 FROM DUAL;
-- mixed integer types use the wider one
SELECT POWER(CAST(2 AS SMALLINT), CAST(70 AS BIGINT)) AS power,
       pg_typeof(POWER(CAST(2 AS SMALLINT), CAST(70 AS BIGINT))) AS type,
       LOG(CAST(2 AS INTEGER), CAST(3 AS BIGINT)) AS log FROM DUAL;

--
-- NUMBER precision: 20 base-100 digits from the first nonzero one,
-- so a result keeps 39 or 40 significant digits
--
SELECT SQRT(2) AS sqrt_2, SQRT(200) AS sqrt_200, SQRT(3) AS sqrt_3 FROM DUAL;
SELECT EXP(1) AS e, EXP(-1) AS inv_e, EXP(10) AS e_10, EXP(-10) AS inv_e_10 FROM DUAL;
SELECT LN(2) AS ln_2, LN(10) AS ln_10, LN(1000000) AS ln_1e6 FROM DUAL;
SELECT LOG(2) AS log_2, LOG(2, 3) AS log_2_3, LOG(3, 2) AS log_3_2 FROM DUAL;
SELECT POWER(3, -1) AS third, POWER(7, -3) AS seventh_cubed,
       POWER(2, -100) AS two_to_minus_100 FROM DUAL;
-- longer results are rounded the way a NUMBER stores them
SELECT POWER(7, 50) AS power_7_50, POWER(2, 200) AS power_2_200 FROM DUAL;
-- exact results stay exact
SELECT LOG(2, 8) AS log_2_8, LOG(10, 1000) AS log_10_1000, LOG(100) AS log_100,
       SQRT(144) AS sqrt_144, POWER(10, 30) AS power_10_30,
       POWER(2, -2) AS quarter, POWER(-3, 3) AS minus_27, POWER(-2, -1) AS minus_half
FROM DUAL;

--
-- zero and one
--
SELECT SQRT(0) AS sqrt_0, EXP(0) AS exp_0, LN(1) AS ln_1, LOG(1) AS log_1,
       LOG(5, 1) AS log_5_1, POWER(0, 0) AS power_0_0, POWER(0, 3) AS power_0_3,
       POWER(1, -5) AS power_1_minus_5 FROM DUAL;

--
-- NULL
--
SELECT SQRT(CAST(NULL AS INTEGER)) AS sqrt, POWER(2, NULL) AS power,
       LOG(NULL, 8) AS log FROM DUAL;

--
-- errors
--
SELECT SQRT(-1) FROM DUAL;
SELECT LN(0) FROM DUAL;
SELECT LN(-1) FROM DUAL;
SELECT LOG(0) FROM DUAL;
SELECT LOG(1, 8) FROM DUAL;
SELECT POWER(0, -1) FROM DUAL;

--
-- string arguments convert to NUMBER
--
SELECT SQRT('2.25') AS sqrt_lit, EXP('1') AS exp_lit, LN('2') AS ln_lit,
       LOG('100') AS log_lit FROM DUAL;
SELECT LOG('2', '8') AS log_lits, POWER('2', '10') AS power_lits,
       POWER('2.5', 3) AS power_lit_int, POWER(2, '0.5') AS power_int_lit FROM DUAL;
CREATE TABLE ora_math_str (v VARCHAR2(10), c CHAR(5), s SMALLINT);
INSERT INTO ora_math_str VALUES ('2.5', '2', 3);
SELECT SQRT(v) AS sqrt_v, SQRT(c) AS sqrt_c, POWER(v, 2) AS power_v_2,
       POWER(v, s) AS power_v_s FROM ora_math_str;
SELECT POWER(2, v) AS power_2_v, LOG(c, v) AS log_c_v,
       pg_typeof(SQRT(v)) AS sqrt_type, pg_typeof(POWER(v, 2)) AS power_type
FROM ora_math_str;
DROP TABLE ora_math_str;
SELECT SQRT('abc') FROM DUAL;

--
-- other argument types keep the existing functions
--
SELECT pg_typeof(SQRT(2.0)) AS numeric_arg, pg_typeof(POWER(2, 0.5)) AS numeric_exp,
       pg_typeof(SQRT(CAST(2 AS BINARY_DOUBLE))) AS binary_double_arg,
       pg_typeof(SQRT(CAST(2 AS DOUBLE PRECISION))) AS float8_arg FROM DUAL;
SELECT SQRT(2.0) AS sqrt_2_0, POWER(2, 0.5) AS power_2_half FROM DUAL;

--
-- integer columns and PL/iSQL parameters
--
CREATE TABLE ora_math_tab (i INTEGER, b BIGINT);
INSERT INTO ora_math_tab VALUES (2, 3);
INSERT INTO ora_math_tab VALUES (10, -2);
SELECT i, b, SQRT(i) AS sqrt, POWER(i, b) AS power, LOG(i, b * b) AS log
FROM ora_math_tab ORDER BY i;
DROP TABLE ora_math_tab;

CREATE OR REPLACE FUNCTION ora_math_power(n INTEGER) RETURN NUMBER IS
BEGIN
    RETURN POWER(n, 30);
END;
/
SELECT ora_math_power(3) FROM DUAL;
DROP FUNCTION ora_math_power;
