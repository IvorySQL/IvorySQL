SET ivorysql.compatible_mode = oracle;

-- Oracle reference strings, including full precision and ties-to-even cases.
CREATE TABLE ora_binary_float_format
    (id integer, f BINARY_FLOAT, d BINARY_DOUBLE, expected_f text, expected_d text);
INSERT INTO ora_binary_float_format VALUES
    (1, 39.5f, 39.5d, '3.95E+001', '3.95E+001'),
    (2, 0.1f, 0.1d, '1.00000001E-001', '1.0000000000000001E-001'),
    (3, 1.2345678f, 1.234567890123456d, '1.23456776E+000', '1.234567890123456E+000'),
    (4, 1f, 1d, '1.0E+000', '1.0E+000'),
    (5, 10f, 10d, '1.0E+001', '1.0E+001'),
    (6, 0f, 0d, '0', '0'),
    (7, -0f, -0d, '0', '0'),
    (8, -39.5f, -39.5d, '-3.95E+001', '-3.95E+001'),
    (9, 1.17549435e-38f, 2.2250738585072014e-308d,
     '1.17549435E-038', '2.2250738585072014E-308'),
    (10, 1.40129846e-45f, 4.9406564584124654e-324d,
     '1.40129846E-045', '4.9406564584124654E-324'),
    (11, 3.40282347e38f, 1.7976931348623157e308d,
     '3.40282347E+038', '1.7976931348623157E+308'),
    (12, 1.001953125f, 1.00000762939453125d,
     '1.00195312E+000', '1.0000076293945312E+000'),
    (13, binary_float_infinity, binary_double_infinity, 'Inf', 'Inf'),
    (14, -binary_float_infinity, -binary_double_infinity, '-Inf', '-Inf'),
    (15, binary_float_nan, binary_double_nan, 'Nan', 'Nan'),
    (16, NULL, NULL, NULL, NULL);

SELECT id, f, d FROM ora_binary_float_format ORDER BY id;
SELECT id, f::text IS NOT DISTINCT FROM expected_f AS float_text,
       d::text IS NOT DISTINCT FROM expected_d AS double_text,
       TO_CHAR(f)::text IS NOT DISTINCT FROM expected_f AS float_to_char,
       TO_CHAR(d)::text IS NOT DISTINCT FROM expected_d AS double_to_char
FROM ora_binary_float_format ORDER BY id;

-- Original report: the finite value matches uppercase E; Infinity does not.
SELECT f FROM ora_binary_float_format WHERE id IN (1, 13) AND f LIKE '%E%';
SELECT f FROM ora_binary_float_format WHERE id IN (1, 13) AND f NOT LIKE '%E%';
SELECT d FROM ora_binary_float_format WHERE id IN (1, 13) AND d LIKE '%E%';
SELECT d FROM ora_binary_float_format WHERE id IN (1, 13) AND d NOT LIKE '%E%';

-- Runtime patterns exercise the same implicit conversion as literal patterns.
WITH patterns(id, pattern) AS
    (VALUES (1, '%E%'), (2, '%e%'), (3, '%+%'), (4, '%Inf%'),
            (5, '1.0E+00_'), (6, '%Nan%'))
SELECT p.id, pattern,
       count(*) FILTER (WHERE f LIKE pattern) AS float_like,
       count(*) FILTER (WHERE f NOT LIKE pattern) AS float_not_like,
       count(*) FILTER (WHERE d LIKE pattern) AS double_like,
       count(*) FILTER (WHERE d NOT LIKE pattern) AS double_not_like
FROM patterns p CROSS JOIN ora_binary_float_format t
GROUP BY p.id, pattern ORDER BY p.id;
SELECT id FROM ora_binary_float_format
WHERE f LIKE '1.0E++00_' ESCAPE '+' ORDER BY id;
SELECT id FROM ora_binary_float_format
WHERE d LIKE '1.0E++00_' ESCAPE '+' ORDER BY id;

-- Output must round-trip without changing the value, including NaN and NULL.
SELECT bool_and(f IS NOT DISTINCT FROM (f::text)::BINARY_FLOAT) AS float_roundtrip,
       bool_and(d IS NOT DISTINCT FROM (d::text)::BINARY_DOUBLE) AS double_roundtrip
FROM ora_binary_float_format;
SELECT ARRAY[39.5f, 0f, binary_float_infinity] AS float_array,
       ARRAY[39.5d, 0d, binary_double_infinity] AS double_array;

-- Oracle's default precision does not depend on PostgreSQL's output setting.
SET extra_float_digits = -3;
SELECT id, f, d, TO_CHAR(f), TO_CHAR(d)
FROM ora_binary_float_format WHERE id IN (1, 2, 3) ORDER BY id;
SET extra_float_digits = 3;
SELECT id, f, d, TO_CHAR(f), TO_CHAR(d)
FROM ora_binary_float_format WHERE id IN (1, 2, 3) ORDER BY id;
RESET extra_float_digits;

-- Explicit format models and non-floating-point overloads remain available.
SELECT TO_CHAR(39.5f, 'FM9990.00') AS formatted_float,
       TO_CHAR(39.5d, 'FM9990.00') AS formatted_double,
       TO_CHAR(39.5::number) AS number_value;
SELECT TO_CHAR(22::integer) AS integer_value,
       TO_CHAR(99::smallint) AS smallint_value,
       TO_CHAR(1234567890123456::bigint) AS bigint_value,
       TO_CHAR(123.456::real) AS real_value,
       TO_CHAR(1234.5678::double precision) AS double_value,
       TO_CHAR('4.0010'::pg_catalog.numeric) AS numeric_value;
SELECT LENGTH(192::smallint) AS smallint_length,
       LENGTH(192::bigint) AS bigint_length,
       LENGTH('-9223372036854775808'::bigint) AS min_bigint_length;
SELECT TO_CHAR(NULL::BINARY_FLOAT) IS NULL AS null_float,
       TO_CHAR(NULL::BINARY_DOUBLE) IS NULL AS null_double,
       (NULL::BINARY_FLOAT LIKE '%E%') IS NULL AS null_like,
       (NULL::BINARY_DOUBLE NOT LIKE '%E%') IS NULL AS null_not_like;

-- Keep the PG output path, including extra_float_digits, unchanged.
SET ivorysql.compatible_mode = pg;
SELECT '39.5'::sys.binary_float AS pg_binary_float,
       '39.5'::sys.binary_double AS pg_binary_double,
       39.5::real AS pg_real, 39.5::double precision AS pg_double;
SET extra_float_digits = 0;
SELECT '1.2345678'::sys.binary_float AS pg_binary_float,
       '1.234567890123456'::sys.binary_double AS pg_binary_double,
       'Infinity'::sys.binary_float AS pg_infinity,
       'NaN'::sys.binary_double AS pg_nan;
-- Explicit SYS calls still request Oracle's formatting in PG mode.
SELECT sys.TO_CHAR('39.5'::sys.binary_float) AS oracle_float,
       sys.TO_CHAR('39.5'::sys.binary_double) AS oracle_double;
RESET extra_float_digits;
SET ivorysql.compatible_mode = oracle;
DROP TABLE ora_binary_float_format;
