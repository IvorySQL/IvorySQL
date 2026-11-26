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

-- Numeric arguments (smallint/integer/bigint/numeric/number/float) are
-- implicitly converted to character data, and numeric position/length
-- arguments are accepted in both 2-argument and 3-argument forms.
SELECT substr(21212::int2, 2::int2, 2::int2) AS int2_three_args,
       substr(21212::int2, 2::int4, 2::int4) AS int2_int4_args,
       substr(21212::int2, 2::int2) AS int2_two_args,
       substr((-21212)::int2, 1::int2, 3::int2) AS int2_negative;

SELECT substr(21212, 2, 2) AS int4_three_args,
       substr(21212, -2) AS int4_two_args,
       substr(21212::int8, 2::int8, 2::int8) AS int8_three_args,
       substr(21212::int8, -2::int8) AS int8_two_args,
       substr(21212::numeric, 2::numeric, 2::numeric) AS numeric_three_args,
       substr(21212::number, 2::number, 2::number) AS number_three_args,
       substr(123.45::binary_double, 2, 3) AS bdouble_three_args;

-- String inputs with smallint/bigint/numeric/number position and length,
-- including mixed types and multibyte characters.
SELECT substr('hello', 2::int2, 2::int2) AS str_int2,
       substr('hello', 2::int8, 2::int8) AS str_int8,
       substr('hello', 2::numeric, 2::numeric) AS str_numeric,
       substr('hello'::varchar2, 2::int2, 2::int4) AS vc2_mixed_int,
       substr('hello'::varchar2, 2::int4, 2.9) AS vc2_mixed_num,
       substr('甲乙丙丁戊', -3::number, 2::number) AS mb_number;

-- Fractional positions and lengths truncate toward zero (Oracle semantics).
SELECT substr('hello', 2.9, 1.9) AS frac_pos,
       substr('hello', -2.9, 2.9) AS frac_neg_pos,
       substr('hello', -0.9, 2) AS frac_neg_zero_pos,
       substr('hello', 1, 0.9) IS NULL AS frac_zero_len,
       substr('hello', 1, -0.9) IS NULL AS frac_neg_len;

-- Finite numeric positions and lengths beyond int4 range do not overflow.
SELECT substr('hello', 3000000000) IS NULL AS big_pos,
       substr('hello', -3000000000) IS NULL AS big_neg_pos,
       substr('hello', 2147483647.9) IS NULL AS int32max_frac_pos,
       substr('hello', -2147483648.9) IS NULL AS int32min_frac_pos,
       substr('hello', 1e1000) IS NULL AS huge_pos,
       substr('hello', 2, 3000000000) AS big_len,
       substr('hello', 2, 1e1000) AS huge_len,
       substr('hello', 2, -3000000000) IS NULL AS big_neg_len;

-- NULL and empty inputs through the numeric overload.
SELECT substr(NULL::int2, 2::int2, 2::int2) IS NULL AS null_int2,
       substr(21212::int2, NULL::number, 2::number) IS NULL AS null_num_pos,
       substr(21212::int2, 2::number, NULL::number) IS NULL AS null_num_len,
       substr(pg_catalog.substr('hello', 1, 0)::varchar2, 1::number) IS NULL AS empty_vc2_num;

-- Special numeric values (NaN and Infinity) raise an error.
SELECT substr('hello', 'NaN'::numeric, 2);
SELECT substr('hello', 3000000000, 'NaN'::numeric);
SELECT substr('hello', 'Infinity'::numeric);
SELECT substr('hello', 1, '-Infinity'::numeric);

-- bytea and raw continue to resolve to pg_catalog.substr(bytea, ...).
SELECT substr('hello'::bytea, 2, 3) AS bytea_int4,
       substr('hello'::bytea, 2::int2, 3::int2) AS bytea_int2,
       substr(utl_raw.cast_to_raw('hello'), 2, 3) AS raw_int4;

-- Exercise the function with external TOAST values rather than only constants.
CREATE TABLE substr_toast(id integer, val text);
ALTER TABLE substr_toast ALTER COLUMN val SET STORAGE EXTERNAL;
INSERT INTO substr_toast VALUES (1, repeat('hello', 3000)),
                               (2, repeat('甲乙丙', 5000));
SELECT id, substr(val, -3) AS two_args, substr(val, -3, 2) AS three_args,
       substr(val, -3.9, 2.9) AS numeric_args
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
SELECT substr(21212::int2, 2::int2, 2::int2);
SELECT sys.substr('hello', -3) AS oracle_substr,
       sys.substr('hello', -3, 2) AS oracle_three_args,
       sys.substr(21212::int2, 2::int2, 2::int2) AS oracle_int2_args;
