--
-- ORA_TO_CHAR_TM
-- Oracle's TM (text minimum) number format element: the shortest possible form,
-- with no padding, no trailing fractional zeroes and no leading zero before the
-- decimal point.
--

SELECT '[' || TO_CHAR(0, 'TM') || ']' AS zero,
       '[' || TO_CHAR(0.5, 'TM') || ']' AS fraction,
       '[' || TO_CHAR(-0.5, 'TM') || ']' AS fraction_neg;

SELECT '[' || TO_CHAR(1000, 'TM') || ']' AS integer,
       '[' || TO_CHAR(123.456, 'TM') || ']' AS decimals,
       '[' || TO_CHAR(1234567.89, 'TM') || ']' AS large;

-- trailing fractional zeroes are dropped
SELECT '[' || TO_CHAR(1.500, 'TM') || ']' AS trimmed;

-- the element wins over the other elements in the model
SELECT '[' || TO_CHAR(1.5, 'TM9') || ']' AS with_digit,
       '[' || TO_CHAR(1.5, 'FMTM') || ']' AS with_fm,
       '[' || TO_CHAR(1.5, 'tm') || ']' AS lower;

-- every numeric input type goes through the same path
SELECT '[' || TO_CHAR(0.5::int4, 'TM') || ']' AS int4_trunc,
       '[' || TO_CHAR(1000::int8, 'TM') || ']' AS int8,
       '[' || TO_CHAR(0.5::numeric, 'TM') || ']' AS numeric_in,
       '[' || TO_CHAR(0.5::float4, 'TM') || ']' AS float4_in,
       '[' || TO_CHAR(0.5::float8, 'TM') || ']' AS float8_in;

-- PostgreSQL mode keeps treating it as literal text
SET ivorysql.compatible_mode = pg;
SELECT '[' || TO_CHAR(1.5, 'TM') || ']' AS pg_mode;
RESET ivorysql.compatible_mode;
