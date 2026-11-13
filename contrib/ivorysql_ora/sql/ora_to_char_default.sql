SET ivorysql.compatible_mode = oracle;

-- A shadow of the wrapper's helper functions in an earlier schema must
-- not change the default conversion: the wrapper resolves strpos/rtrim/
-- regexp_replace and the width-fitting helpers (concat/ltrim/rtrim/length/
-- abs/substring/lpad/rpad) in pg_catalog explicitly.  The server refuses
-- pseudo-type "any" arguments for SQL and PL/pgSQL user functions, so the
-- concat shadow is declared over VARIADIC text[] instead: an unqualified
-- concat(some text) in the wrapper body would still bind to it ahead of
-- pg_catalog.concat given this search_path.  The drop-cascade notice is
-- silenced because its stderr arrival can race stdout on Oracle-wire
-- connections.
CREATE SCHEMA tochar_shadow;
/
CREATE FUNCTION tochar_shadow.strpos(text, text) RETURNS int
  LANGUAGE sql IMMUTABLE AS 'SELECT 0';
/
CREATE FUNCTION tochar_shadow.rtrim(text, text) RETURNS text
  LANGUAGE sql IMMUTABLE AS 'SELECT repeat(''#'', length($1))';
/
CREATE FUNCTION tochar_shadow.regexp_replace(text, text, text) RETURNS text
  LANGUAGE sql IMMUTABLE AS 'SELECT ''shadowed''';
/
CREATE FUNCTION tochar_shadow.concat(VARIADIC text[]) RETURNS text
  LANGUAGE sql IMMUTABLE AS 'SELECT ''shadowed''::text';
/
CREATE FUNCTION tochar_shadow.ltrim(text, text) RETURNS text
  LANGUAGE sql IMMUTABLE AS 'SELECT ''shadowed''::text';
/
CREATE FUNCTION tochar_shadow.length(text) RETURNS int
  LANGUAGE sql IMMUTABLE AS 'SELECT -1';
/
CREATE FUNCTION tochar_shadow.abs(integer) RETURNS integer
  LANGUAGE sql IMMUTABLE AS 'SELECT -1';
/
CREATE FUNCTION tochar_shadow.substring(text, integer) RETURNS text
  LANGUAGE sql IMMUTABLE AS 'SELECT ''shadowed''::text';
/
CREATE FUNCTION tochar_shadow.substring(text, integer, integer) RETURNS text
  LANGUAGE sql IMMUTABLE AS 'SELECT ''shadowed''::text';
/
CREATE FUNCTION tochar_shadow.lpad(text, integer, text) RETURNS text
  LANGUAGE sql IMMUTABLE AS 'SELECT ''shadowed''::text';
/
CREATE FUNCTION tochar_shadow.rpad(text, integer, text) RETURNS text
  LANGUAGE sql IMMUTABLE AS 'SELECT ''shadowed''::text';
/
SET search_path = tochar_shadow, pg_catalog;
SELECT to_char(cast('0.50' as number)) AS not_shadowed FROM dual;
SELECT to_char(cast('100.0' as number)) AS not_shadowed_too FROM dual;
SELECT to_char(cast('1e100' as number)) AS not_shadowed_sci FROM dual;
RESET search_path;
SET client_min_messages = warning;
DROP SCHEMA tochar_shadow CASCADE;
/

-- TO_CHAR of a number without a format model converts the value to a
-- VARCHAR2 "exactly long enough to hold its significant digits" (Oracle
-- 23ai SQL Language Reference): trailing fraction zeros are not kept and
-- the integer digit is omitted for values between -1 and 1.

-- Values between -1 and 1 lose the integer zero.
SELECT to_char(0.5) FROM dual;
SELECT to_char(-0.5) FROM dual;
SELECT to_char(0.10) FROM dual;
SELECT to_char(0.000001) FROM dual;
SELECT to_char(0.000000015) FROM dual;

-- Trailing fraction zeros are not significant.
SELECT to_char(1.50) FROM dual;
SELECT to_char(100.0) FROM dual;
SELECT to_char(-100.0) FROM dual;
SELECT to_char(123.4500) FROM dual;
SELECT to_char(10.0) FROM dual;

-- Zero keeps a single digit, negative zero is not a thing for NUMBER.
SELECT to_char(0.0) FROM dual;
SELECT to_char(0) FROM dual;
SELECT to_char(-0.0) FROM dual;

-- Plain integers are unchanged.
SELECT to_char(100) FROM dual;
SELECT to_char(-44444) FROM dual;

-- Large values stay plain decimal digits while the text fits 40 characters.
SELECT to_char(10000000000) FROM dual;
SELECT to_char(123456789012345678901234567890) FROM dual;

-- The default model is TM9.  Probing Oracle Database 23ai Free shows the
-- normalized fixed-point text is kept only while it fits within 40
-- characters, the sign included: 1e39 (40 characters) and 40 nines stay
-- fixed-point while 1e40 switches to scientific notation, and the
-- negative side carries the sign into the budget (-1e39 needs 41
-- characters).
SELECT to_char(1e38) FROM dual;
SELECT to_char(1e39) FROM dual;
SELECT to_char(999999999999999999999999999999999999999) FROM dual;
SELECT to_char(9999999999999999999999999999999999999999) FROM dual;
SELECT to_char(1234567890123456789012345678901234567890) FROM dual;
SELECT to_char(-999999999999999999999999999999999999999) FROM dual;
SELECT to_char(-9999999999999999999999999999999999999999) FROM dual;
SELECT to_char(-1234567890123456789012345678901234567890) FROM dual;
SELECT to_char(1e40) FROM dual;
SELECT to_char(99999999999999999999999999999999999999999) FROM dual;
SELECT to_char(1e41) FROM dual;
SELECT to_char(-1e39) FROM dual;

-- Scientific notation always spans exactly 40 characters, the sign
-- included: the mantissa is zero-padded to fill the width and the
-- exponent carries a sign with at least two digits.
SELECT to_char(1e45) FROM dual;
SELECT to_char(1e50) FROM dual;
SELECT to_char(1e62) FROM dual;
SELECT to_char(1e63) FROM dual;
SELECT to_char(1e64) FROM dual;
SELECT to_char(-1e63) FROM dual;
SELECT to_char(1e100) FROM dual;
SELECT to_char(-1e100) FROM dual;
SELECT to_char(1e-100) FROM dual;
SELECT to_char(-1e-100) FROM dual;
SELECT to_char(1.5e100) FROM dual;
SELECT to_char(-1.5e100) FROM dual;

-- The lower boundary follows the same 40-character rule on the
-- normalized text: 1e-39 renders as a 40-character fraction and stays
-- fixed-point, while anything needing more room switches (1.5e-39, and
-- -1e-39 where the sign pushes past the budget).
SELECT to_char(1e-36) FROM dual;
SELECT to_char(1e-37) FROM dual;
SELECT to_char(1e-38) FROM dual;
SELECT to_char(1e-39) FROM dual;
SELECT to_char(-1e-39) FROM dual;
SELECT to_char(1.5e-39) FROM dual;
SELECT to_char(1e-40) FROM dual;
SELECT to_char(1e-41) FROM dual;
SELECT to_char(5e-40) FROM dual;
SELECT to_char(1e-63) FROM dual;
SELECT to_char(1e-64) FROM dual;
SELECT to_char(-1e-63) FROM dual;
SELECT to_char(-1e-64) FROM dual;

-- Small exponents render zero-padded to two digits.
SELECT to_char(1.2345678901234567890123456789012345678901e-9) FROM dual;

-- Significant digits move into the mantissa; trailing zeros of the
-- integer part fold into the exponent and the mantissa is zero-padded
-- to the width.
SELECT to_char(123e100) FROM dual;
SELECT to_char(123456789e100) FROM dual;
SELECT to_char(1.234567890123456789012345678901234e60) FROM dual;
SELECT to_char(1.23456789012345678901234567890123e40) FROM dual;

-- Rounding at the mantissa cut is half-up and a carry folds into the
-- exponent: the 35th significant digit rounds 34 kept digits up, and
-- nines beyond 1e99 carry all the way.
SELECT to_char(1.2345678901234567890123456789012345e100) FROM dual;
SELECT to_char(9.999999999999999999999999999999999999999e99) FROM dual;
SELECT to_char(999999999999999999999999999999999999999e15) FROM dual;
SELECT to_char(1.9999999999999999999999999999999999999999e100) FROM dual;

-- Values too long for the mantissa keep their first 35 significant
-- digits: the 64- and 65-digit integers differ only past that cut.
SELECT to_char(cast('12345678901234567890123456789012345678901234567890123456789012345' as number)) FROM dual;
SELECT to_char(cast('1234567890123456789012345678901234567890123456789012345678901234' as number)) FROM dual;

-- Past the 40-character budget the fixed and the scientific rendering
-- compete: the fixed form rounds the value to whatever fits, the
-- scientific form rounds it to the mantissa width, and the one that
-- keeps more significant digits wins.  A 40-significant-digit fraction
-- at e-9 keeps only 31 digits when truncated, so scientific wins, at
-- e-5 both keep 35 and fixed wins, at e-4 fixed keeps 36 and wins.
SELECT to_char(1.234567890123456789012345678901234567890e9) FROM dual;
SELECT to_char(1.234567890123456789012345678901234567890e15) FROM dual;
SELECT to_char(1.234567890123456789012345678901234567890e-4) FROM dual;
SELECT to_char(1.234567890123456789012345678901234567890e-5) FROM dual;
SELECT to_char(-1.234567890123456789012345678901234567890e-5) FROM dual;
SELECT to_char(1.234567890123456789012345678901234567890e-6) FROM dual;
SELECT to_char(-1.234567890123456789012345678901234567890e-6) FROM dual;
SELECT to_char(123456789012345678901234567890123456789.12) FROM dual;

-- A fraction pushed past the budget rounds into the integer part; the
-- sign counts toward the budget, so the negative twins of the 40-digit
-- integers switch while their positive forms stay fixed.
SELECT to_char(999999999999999999999999999999999999999.9) FROM dual;
SELECT to_char(cast('1234567890123456789012345678901234567890.5' as number)) FROM dual;
SELECT to_char(1234567890123456789012345678901234567890.9) FROM dual;
SELECT to_char(1234567890123456789012345678901234567890.999) FROM dual;
SELECT to_char(9999999999999999999999999999999999999999.9) FROM dual;
SELECT to_char(-1234567890123456789012345678901234567890.5) FROM dual;
SELECT to_char(-1234567890123456789012345678901234567890.123456789) FROM dual;
SELECT to_char(-1234567890123456789012345678901234567890.9) FROM dual;

-- When both candidates represent the same rounded value fixed notation
-- wins: rounding 9.99..9e-5 either way yields '.0001', the e-6 twin
-- yields '.00001', and 9.99..9e-40 rounds to the fixed '.000..1' - its
-- negative twin switches because the sign eats one decimal of the
-- budget and the fixed form cannot carry any more.
SELECT to_char(9.999999999999999999999999999999999999999e-5) FROM dual;
SELECT to_char(9.999999999999999999999999999999999999999e-6) FROM dual;
SELECT to_char(9.999999999999999999999999999999999999999e-37) FROM dual;
SELECT to_char(9.999999999999999999999999999999999999999e-38) FROM dual;
SELECT to_char(9.999999999999999999999999999999999999999e-39) FROM dual;
SELECT to_char(9.999999999999999999999999999999999999999e-40) FROM dual;
SELECT to_char(-9.999999999999999999999999999999999999999e-40) FROM dual;
SELECT to_char(3e-39) FROM dual;
SELECT to_char(5.5e-38) FROM dual;

-- The budget counts the normalized fixed-point text, not the raw scale:
-- trailing fraction zeros are dropped before the length is checked.
SELECT to_char(cast('123.45000000000000000000000000000000000000000000000000000000000000000000000' as number)) FROM dual;

-- NULL propagates.
SELECT to_char(NULL::number) IS NULL AS null_propagates FROM dual;

-- Result type is the Oracle VARCHAR2.
SELECT pg_typeof(to_char(0.5)) AS result_type FROM dual;

-- Inputs explicitly typed as NUMBER behave the same.
SELECT to_char(cast('4.00' as number)) FROM dual;
SELECT to_char(cast('4.0010' as number)) FROM dual;
SELECT to_char(cast('0.50' as number)) FROM dual;
SELECT to_char(cast('-0.50' as number)) FROM dual;

-- The text overload stays an identity pass-through.
SELECT to_char('4.0010') FROM dual;
SELECT to_char('0.50') FROM dual;

-- With an explicit format model the output is unchanged by this behavior.
SELECT to_char(0.5, '9.99') FROM dual;
SELECT to_char(-0.5, '9.99') FROM dual;
SELECT to_char(1.50, 'FM9.99') FROM dual;
SELECT to_char(123.456, '999.999') FROM dual;
SELECT to_char(100, '999.99') FROM dual;
