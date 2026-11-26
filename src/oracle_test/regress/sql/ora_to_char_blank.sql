--
-- ORA_TO_CHAR_BLANK_ELEMENT
-- Oracle's B format element prints blanks for the integer part of a
-- fixed-point number when that part is zero.
--

-- A zero value is rendered as blanks, and so is its decimal point
SELECT '[' || TO_CHAR(0, 'B9999') || ']' AS zero_int;
SELECT '[' || TO_CHAR(0, 'B9999.99') || ']' AS zero_with_decimal;

-- A non-zero value keeps its digits
SELECT '[' || TO_CHAR(123, 'B9999') || ']' AS digits;

-- Only the integer part is blank when the value is fractional
SELECT '[' || TO_CHAR(0.5, 'B9999.99') || ']' AS fraction;
SELECT '[' || TO_CHAR(-0.5, 'B9999.99') || ']' AS fraction_neg;

-- FM collapses the blank field entirely
SELECT '[' || TO_CHAR(0, 'FMB9999') || ']' AS fill_mode;

-- The element behaves the same for every numeric input type
SELECT '[' || TO_CHAR(0::int8, 'B9999') || ']' AS zero_int8,
       '[' || TO_CHAR(0::numeric, 'B9999') || ']' AS zero_numeric,
       '[' || TO_CHAR(0::float8, 'B9999') || ']' AS zero_float8;

-- Without B the leading zero is still printed
SELECT '[' || TO_CHAR(0, '9999') || ']' AS no_blank;

-- PostgreSQL mode is unaffected
SET ivorysql.compatible_mode = pg;
SELECT '[' || TO_CHAR(0, 'B9999') || ']' AS pg_mode;
RESET ivorysql.compatible_mode;
