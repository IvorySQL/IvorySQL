SET ivorysql.compatible_mode = oracle;

-- Basic hexadecimal formatting for integer, bigint, numeric, number, binary_float, binary_double.
SELECT to_char(255, 'XX') AS upper_hex,
       to_char(255, 'xx') AS lower_hex,
       to_char(255, 'Xx') AS mixed_first_upper,
       to_char(255, 'xX') AS mixed_first_lower,
       to_char(255::bigint, 'XX') AS bigint_hex,
       to_char(255::numeric, 'XX') AS numeric_hex,
       to_char(255::number, 'XX') AS number_hex,
       to_char(255::binary_float, 'XX') AS bfloat_hex,
       to_char(255::binary_double, 'XX') AS bdouble_hex
FROM dual;

-- Padding, zero-fill and FM fill mode.
SELECT '|' || to_char(15, 'XX') || '|' AS space_pad,
       '|' || to_char(15, 'FMXX') || '|' AS fm_only,
       '|' || to_char(15, '0X') || '|' AS zero_pad,
       '|' || to_char(15, '0XXX') || '|' AS zero_pad_4,
       '|' || to_char(15, 'FM0XXX') || '|' AS fm_zero_pad,
       '|' || to_char(0, 'XX') || '|' AS zero_space,
       '|' || to_char(0, 'FMXX') || '|' AS zero_fm,
       '|' || to_char(0, '0X') || '|' AS zero_zero_pad,
       '|' || to_char(0, 'FM0X') || '|' AS zero_fm_zero_pad
FROM dual;

-- Rounding: half away from zero to integer, matching Oracle.
SELECT '|' || to_char(15.4::numeric, 'XX') || '|' AS round_down,
       '|' || to_char(15.5::numeric, 'XX') || '|' AS round_up,
       '|' || to_char(-0.4::numeric, 'XX') || '|' AS neg_to_zero,
       '|' || to_char(-0.5::numeric, 'XX') || '|' AS neg_overflow,
       '|' || to_char(15.5::binary_double, 'XX') || '|' AS bdouble_round_up,
       '|' || to_char(-0.4::binary_float, 'XX') || '|' AS bfloat_neg_zero
FROM dual;

-- Overflow, negative inputs, NaN and Infinity return width + 1 '#' characters.
SELECT to_char(256, 'XX') AS over_int,
       to_char(256, 'FMXX') AS over_fm,
       to_char(256, '0X') AS over_zero_pad,
       to_char(-1, 'XX') AS neg_int,
       to_char(-1::bigint, 'XXXX') AS neg_bigint,
       to_char(-1::numeric, 'XX') AS neg_numeric,
       to_char('NaN'::binary_double, 'XX') AS nan_val,
       to_char('Infinity'::binary_double, 'XX') AS inf_val,
       to_char('NaN'::numeric, 'XX') AS nan_num,
       to_char('Infinity'::numeric, 'XX') AS inf_num
FROM dual;

-- Arbitrary-precision values beyond signed/unsigned int64.
SELECT to_char(power(2::numeric, 64), 'XXXXXXXXXXXXXXXXX') AS two_pow_64,
       to_char(power(2::numeric, 64) - 1, 'FMXXXXXXXXXXXXXXXX') AS uint64_max
FROM dual;

-- Quoted literal "X" and mixed format models are not treated as hex.
SELECT to_char(12, '"X"99') AS quoted_x,
       to_char(12, 'FM"X"09') AS quoted_x_fm
FROM dual;

-- Runtime/non-constant format models and NULLs.
CREATE TABLE ora_to_char_hex_t(id int, n numeric, fmt varchar2(32));
INSERT INTO ora_to_char_hex_t VALUES
    (1, 255, 'XX'),
    (2, 15, 'fm0xxx'),
    (3, 256, 'XX'),
    (4, NULL, 'XX'),
    (5, 10, NULL);
SELECT id, '|' || to_char(n, fmt) || '|' AS res FROM ora_to_char_hex_t ORDER BY id;
DROP TABLE ora_to_char_hex_t;

-- PostgreSQL compatibility mode keeps existing behavior unchanged.
SET ivorysql.compatible_mode = pg;
SELECT to_char(255, 'XX') AS pg_unchanged;
RESET ivorysql.compatible_mode;
