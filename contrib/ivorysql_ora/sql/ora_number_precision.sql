--
-- Verify that Oracle-mode NUMBER functions resolve to exact-precision numeric
-- implementations rather than falling back to float8.
--

SET ivorysql.compatible_mode = oracle;

SELECT to_char(1234567890123456789012345::number, '9999999999999999999999999') AS tc_int,
       to_char(1.234567890123456789::number, '9.999999999999999999') AS tc_frac,
       pg_typeof(to_char(123::number, '999')) AS tc_type
FROM dual;

SELECT round(123456789012345678901.5::number) AS r1,
       pg_typeof(round(123.5::number)) AS r1_type,
       trunc(123456789012345678901.5::number) AS t1,
       pg_typeof(trunc(123.5::number)) AS t1_type,
       trunc(12345678901234567890.12345::number, 2) AS t2,
       pg_typeof(trunc(123.45::number, 1)) AS t2_type
FROM dual;

SELECT ceil(123456789012345678901.1::number) AS c1,
       pg_typeof(ceil(123.5::number)) AS c1_type,
       ceiling(123456789012345678901.1::number) AS c2,
       pg_typeof(ceiling(123.5::number)) AS c2_type,
       floor(123456789012345678901.9::number) AS f1,
       pg_typeof(floor(123.5::number)) AS f1_type
FROM dual;

SELECT sign(-123.5::number) AS s1,
       pg_typeof(sign(-123.5::number)) AS s1_type,
       abs(-123456789012345678901.5::number) AS a1,
       pg_typeof(abs(-123.5::number)) AS a1_type
FROM dual;

SELECT width_bucket(100000000000000000001::number,
                    100000000000000000000::number,
                    100000000000000000002::number, 2) AS wb
FROM dual;

-- BINARY_DOUBLE and BINARY_FLOAT must still use floating-point semantics.
SELECT pg_typeof(abs((-1.5)::binary_double)) AS bd_abs,
       pg_typeof(ceil(1.5::binary_double)) AS bd_ceil,
       pg_typeof(floor(1.5::binary_double)) AS bd_floor,
       pg_typeof(round(1.5::binary_double)) AS bd_round,
       pg_typeof(trunc(1.5::binary_double)) AS bd_trunc,
       pg_typeof(sign(1.5::binary_double)) AS bd_sign,
       ceil('Infinity'::binary_double) AS bd_inf
FROM dual;
