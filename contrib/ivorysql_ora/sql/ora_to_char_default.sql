SET ivorysql.compatible_mode = oracle;

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

-- Large values stay plain decimal digits, no scientific notation.
SELECT to_char(10000000000) FROM dual;
SELECT to_char(123456789012345678901234567890) FROM dual;

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

-- A same-signature pg_catalog.regexp_replace shadow in an earlier schema
-- must not change the default conversion: the wrapper resolves its
-- helpers in pg_catalog explicitly.
CREATE SCHEMA tochar_shadow;
CREATE FUNCTION tochar_shadow.strpos(text, text) RETURNS int
  LANGUAGE sql IMMUTABLE AS 'SELECT 0';
CREATE FUNCTION tochar_shadow.rtrim(text, text) RETURNS text
  LANGUAGE sql IMMUTABLE AS 'SELECT repeat(''#'', length($1))';
CREATE FUNCTION tochar_shadow.regexp_replace(text, text, text) RETURNS text
  LANGUAGE sql IMMUTABLE AS 'SELECT ''shadowed''';
SET search_path = tochar_shadow, pg_catalog;
SELECT to_char(cast('0.50' as number)) AS not_shadowed FROM dual;
SELECT to_char(cast('100.0' as number)) AS not_shadowed_too FROM dual;
RESET search_path;
DROP SCHEMA tochar_shadow CASCADE;
