SET ivorysql.compatible_mode = oracle;

-- Reported case, and the same input explicitly typed as CHAR or VARCHAR2.
SELECT to_number('f', 'xx') FROM dual;
SELECT to_number(CAST('f' AS char(1)), 'xx') AS char_value,
       to_number(CAST('f' AS varchar2(10)), 'xx') AS varchar2_value,
       pg_typeof(to_number('f', 'xx')) AS result_type;

-- Both input digits and format elements accept either letter case.
SELECT to_number('F', 'xx') AS upper_digit,
       to_number('f', 'XX') AS upper_format,
       to_number('aB', 'xX') AS mixed_case,
       to_number('0', 'X') AS zero_value,
       to_number('10', 'XX') AS hex_ten,
       to_number('000f', 'XXXX') AS leading_zeroes;

-- Supported hexadecimal prefixes and inputs shorter than the format width.
SELECT to_number('ff', 'FMXXXX') AS fill_mode,
       to_number('0f', '0X') AS zero_prefix,
       to_number('ff', 'fm0xx') AS both_prefixes,
       to_number('f', 'XXXXXXXX') AS short_input;

-- Padded CHAR values and column-based format models must work at runtime.
CREATE TABLE ora_number_hex(id int, c char(4), v varchar2(40), fmt varchar2(40));
INSERT INTO ora_number_hex VALUES (1, 'f', 'f', 'xx'),
                                 (2, 'aB', 'Ab', 'XXXX'),
                                 (3, '0', '0', 'X');
SELECT id, to_number(c, fmt) AS char_value,
       to_number(v, fmt) AS varchar2_value
FROM ora_number_hex ORDER BY id;
DROP TABLE ora_number_hex;
SELECT to_number('  f  ', 'XX') AS surrounding_blanks;

-- Preserve precision for numbers larger than signed or unsigned int64.
SELECT to_number('7fffffffffffffff', 'XXXXXXXXXXXXXXXX') AS signed_max,
       to_number('ffffffffffffffff', 'XXXXXXXXXXXXXXXX') AS unsigned_max,
       to_number('10000000000000000', 'XXXXXXXXXXXXXXXXX') AS beyond_int64;

-- NULL and empty strings keep the existing strict-function behavior.
SELECT to_number(NULL, 'XX') IS NULL AS null_value,
       to_number('f', NULL) IS NULL AS null_format,
       to_number('', 'XX') IS NULL AS empty_value,
       to_number('f', '') IS NULL AS empty_format;

-- Invalid data must not be accepted by numeric_in's more permissive syntax.
SELECT to_number('g', 'XX');
SELECT to_number('-f', 'XX');
SELECT to_number('+f', 'XX');
SELECT to_number('0xf', 'XXX');
SELECT to_number('f_f', 'XXX');
SELECT to_number('f.f', 'XXX');
SELECT to_number('f f', 'XXX');
SELECT to_number('Ｆ', 'XX');
SELECT to_number('fff', 'XX');
SELECT to_number(' ', 'XX');

-- Prepared calls exercise nonconstant values and format models as well.
PREPARE ora_hex_number(text, text) AS SELECT to_number($1, $2) AS result;
SELECT $$EXECUTE ora_hex_number('f', 'xx');$$ \gexec
SELECT $$EXECUTE ora_hex_number('ff', 'XX');$$ \gexec
SELECT $$EXECUTE ora_hex_number('g', 'XX');$$ \gexec
SELECT $$EXECUTE ora_hex_number('15', '99');$$ \gexec
DEALLOCATE ora_hex_number;

-- Decimal formats and the one-argument function retain their behavior.
SELECT to_number('15', '99') AS decimal_format,
       to_number('12.34', '99.99') AS decimal_fraction,
       to_number('-1122.34') AS no_format;

SET ivorysql.compatible_mode = pg;
-- Only the Oracle implementation gains hexadecimal format support.
SELECT pg_catalog.to_number('15', '99') AS pg_decimal;
SELECT pg_catalog.to_number('f', 'xx');
SELECT sys.to_number('f', 'xx') AS oracle_hex;
