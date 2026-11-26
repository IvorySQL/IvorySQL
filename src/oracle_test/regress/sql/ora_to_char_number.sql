--
-- ORA_TO_CHAR_NUMBER
-- Test Oracle-compatible TO_CHAR(number, format) overflow handling (#3349)
--
-- When a value does not fit the format model, Oracle replaces the whole field
-- with '#', including the positions of the sign and of the decimal character.
-- The width of that field is the width of the format model with fill mode
-- (FM) disabled: FM only suppresses the padding.
--

-- Basic overflow: digits, sign and decimal point are all replaced
SELECT TO_CHAR(12345, '999') AS pos,
       TO_CHAR(-12345, '999') AS neg,
       TO_CHAR(12.5, '9.9') AS dec,
       TO_CHAR(1000, '99') AS small;

-- Sign elements do not widen the field
SELECT TO_CHAR(12345, 'S9999') AS s_pre,
       TO_CHAR(12345, '9999S') AS s_post,
       TO_CHAR(12345, '9999MI') AS mi,
       TO_CHAR(12345, '9999PR') AS pr,
       TO_CHAR(12345, 'B9999') AS b;

-- Fill mode still reserves the sign position when a value overflows
SELECT TO_CHAR(12345, 'FM9999') AS fm,
       TO_CHAR(12345, 'FM9999MI') AS fm_mi,
       TO_CHAR(12345, 'FM9999PR') AS fm_pr,
       TO_CHAR(12345, 'FM9,999') AS fm_group;

-- Group separators and decimal characters count towards the width
SELECT TO_CHAR(12345, '9,999') AS grp,
       TO_CHAR(12345, '9,999.99') AS grp_dec,
       TO_CHAR(12345, '999.99') AS dec;

-- Values that fit the format model are not affected
SELECT TO_CHAR(1234, '99999') AS fits,
       TO_CHAR(1234, '9,999.99') AS fits_dec;

-- The field width does not depend on the input type: int8, float4 and float8
-- use the same format model, and a value that fits is still rendered normally
SELECT TO_CHAR(12345::int8, '999') AS int8_over,
       TO_CHAR(12.5::float8, '9.9') AS float8_over,
       TO_CHAR(12345::float4, '999') AS float4_over,
       TO_CHAR(123::int8, '999') AS int8_fits,
       TO_CHAR(12.5::float8, '99.9') AS float8_fits;

-- Negative values use the same width
SELECT TO_CHAR(-12345, '9999PR') AS neg_pr,
       TO_CHAR(-12345, '9999MI') AS neg_mi,
       TO_CHAR(-12345, 'S9999') AS neg_s;

-- The width follows the format model even where the fractional precision is
-- clamped for float4 and float8 input
SELECT TO_CHAR('12345678901'::float8,
               'FM9999999999D9999900000000000000000') AS float8_long,
       TO_CHAR('12345678901'::float4,
               'FM9999999999D9999900000000000000000') AS float4_long;

-- A '#' that comes from a quoted literal is not an overflow marker.  Quoted
-- literals are a PostgreSQL extension; Oracle rejects them in number format
-- models (ORA-01481), so only the IvorySQL behaviour is pinned here.
SELECT TO_CHAR(12, 'FM99"#"') AS literal_fits,
       TO_CHAR(123, 'FM99"#"') AS literal_overflow;

-- A format model with no digit position before the decimal character still
-- overflows; the overflow marker is not lost even though the decimal
-- character overwrites the only '#' placeholder
SELECT TO_CHAR('1e20'::float8, '.99') AS no_int_position,
       TO_CHAR('1e20'::float8, '.0') AS one_decimal,
       TO_CHAR('-1e20'::float8, '.99') AS no_int_position_neg,
       TO_CHAR('1e20'::float4, '.99') AS no_int_position_f4,
       TO_CHAR('1e20'::float4, '.0') AS one_decimal_f4;
