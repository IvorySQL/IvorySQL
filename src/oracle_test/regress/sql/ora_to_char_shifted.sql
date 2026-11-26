--
-- ORA_TO_CHAR_SHIFTED_ELEMENT
-- Oracle's V format element shifts the value left by the number of digits that
-- follow it and pads the shifted digits with zeroes.
--
-- Note: overflown fields are left to the generic Oracle-mode overflow handling
-- and are not covered here.
--

-- A zero value is rendered as zeroes, not as blanks
SELECT '[' || TO_CHAR(0, 'V9999') || ']' AS zero;

-- The shifted digits are zero-filled to the width of the model
SELECT '[' || TO_CHAR(0.001, 'V9999') || ']' AS shifted_small;
SELECT '[' || TO_CHAR(0.01234, 'V9999') || ']' AS shifted_truncated;

-- A sign replaces the reserved position, and FM drops it
SELECT '[' || TO_CHAR(-0.001, 'V9999') || ']' AS negative;
SELECT '[' || TO_CHAR(0.001, 'FMV9999') || ']' AS fill_mode;
SELECT '[' || TO_CHAR(-0.001, 'FMV9999') || ']' AS fill_mode_negative;

-- Narrower models pad to their own width
SELECT '[' || TO_CHAR(0, 'V999') || ']' AS three_digits;
SELECT '[' || TO_CHAR(0, 'V0') || ']' AS one_digit;

-- Values that already fill the field are unchanged
SELECT '[' || TO_CHAR(0.5, 'V9999') || ']' AS full_width;

-- PostgreSQL mode is unaffected
SET ivorysql.compatible_mode = pg;
SELECT '[' || TO_CHAR(0, 'V9999') || ']' AS pg_mode;
RESET ivorysql.compatible_mode;
