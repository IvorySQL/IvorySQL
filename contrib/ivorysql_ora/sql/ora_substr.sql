SET ivorysql.compatible_mode = oracle;

-- Negative positions count from the end, in both forms of SUBSTR.
SELECT substr('hello', -3) AS two_args,
       substr('hello', -3, 2) AS three_args;

-- Zero, positions at either end, out-of-range positions, and int4 limits.
SELECT pos, coalesce(substr('hello', pos), '<NULL>') AS result
FROM (VALUES (-2147483648), (-6), (-5), (-3), (-1), (0), (1),
             (3), (5), (6), (2147483647)) AS v(pos)
ORDER BY pos;

-- Nonpositive lengths return NULL; large lengths stop at the string's end.
SELECT pos, len, coalesce(substr('hello', pos, len), '<NULL>') AS result
FROM (VALUES (-6, 2), (-5, 2), (-3, 2), (-1, 20), (0, 2),
             (1, -2147483648), (1, -1), (1, 0), (1, 2147483647),
             (3, 2147483647), (6, 2), (2147483647, 2)) AS v(pos, len)
ORDER BY pos, len;

-- NULL input and empty strings, including an empty text produced at runtime.
SELECT substr(NULL::text, -3) IS NULL AS null_string,
       substr('hello', NULL::pg_catalog.int4) IS NULL AS null_position,
       substr('hello', 1, NULL::pg_catalog.int4) IS NULL AS null_length,
       substr('', 1) IS NULL AS empty_string,
       substr(pg_catalog.substr('hello', 1, 0), 1) IS NULL AS empty_text;

-- Character positions must not be interpreted as byte offsets.
SELECT substr('甲乙丙丁戊', -3) AS two_args,
       substr('甲乙丙丁戊', -3, 2) AS three_args,
       substr('A你中好Z', -4, 2) AS mixed_chars;

-- Resolve Oracle character types through the new overloads too.
SELECT substr('hello'::varchar2, -3) AS varchar2_value,
       substr('hello'::clob, -3, 2) AS clob_value,
       substr('hello'::nclob, -3) AS nclob_value;

-- Numeric input becomes text, and fractional positions and lengths truncate.
\pset format unaligned
SELECT substr(12345.6789::double precision, 2.9::float8, 3.9::float8) AS float_value,
       substr(12345.6789::pg_catalog.numeric, 2.9::float8, 3.9::float8) AS numeric_value,
       pg_typeof(substr(12345::double precision, 2::float8, 3::float8)) AS result_type;
SELECT substr(12345::double precision, -3.9::float8, 2.9::float8) AS from_end,
       substr(12345::pg_catalog.numeric, 0.9::float8, 2.9::float8) AS from_start,
       substr(12345::pg_catalog.numeric, 2::float8, 0.9::float8) IS NULL AS short_length,
       substr(NULL::double precision, 2::float8, 3::float8) IS NULL AS null_value,
       substr(12345::pg_catalog.numeric, NULL::float8, 3::float8) IS NULL AS null_position,
       substr(12345::double precision, 2::float8, NULL::float8) IS NULL AS null_length;
SELECT substr('hello', 2.9::float8, 3.9::float8) AS word,
       substr('00012', 2.9::float8, 3.9::float8) AS leading_zeroes,
       substr('hello', 2, 3) AS integer_arguments;
SELECT substr(9007199254740993::pg_catalog.numeric, 16::float8, 1::float8) AS numeric_digit,
       substr(9007199254740993::number, 16::float8, 1::float8) AS number_digit;
\pset format aligned

-- Exercise the function with external TOAST values rather than only constants.
CREATE TABLE substr_toast(id integer, val text);
ALTER TABLE substr_toast ALTER COLUMN val SET STORAGE EXTERNAL;
INSERT INTO substr_toast VALUES (1, repeat('hello', 3000)),
                               (2, repeat('甲乙丙', 5000));
SELECT id, substr(val, -3) AS two_args, substr(val, -3, 2) AS three_args
FROM substr_toast ORDER BY id;
DROP TABLE substr_toast;

-- Explicit PostgreSQL functions retain their original behavior in Oracle mode.
SELECT pg_catalog.substr('hello', -3) AS pg_substr,
       substring('hello' FROM -3) AS pg_substring;

SET ivorysql.compatible_mode = pg;

-- Only Oracle name resolution selects sys.substr; the implementation itself
-- is independent of the current mode, as required for an immutable function.
SELECT substr('hello', -3) AS pg_substr,
       substr('hello', -3, 2) AS pg_three_args,
       substring('hello' FROM -3) AS pg_substring;
SELECT sys.substr('hello', -3) AS oracle_substr,
       sys.substr('hello', -3, 2) AS oracle_three_args;
