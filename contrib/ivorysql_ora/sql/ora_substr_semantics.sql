--
-- Oracle-compatible SUBSTR character semantics
--

SET ivorysql.compatible_mode = oracle;

SELECT substr('abcdef', 2, 2) AS normal_positive;
SELECT substr('abcdef', 0, 2) AS zero_position;
SELECT substr('abcdef', -2, 2) AS negative_position;
SELECT substr('abcdef', -2) AS negative_without_length;
SELECT substr('abcdef', 2, 0) IS NULL AS zero_length_is_null;
SELECT substr('abcdef', 2, -1) IS NULL AS negative_length_is_null;
SELECT substr('abcdef', 20) IS NULL AS past_end_is_null;

-- Positions count characters rather than bytes.
SELECT substr('你好吗', -2, 1) AS multibyte_negative;
SELECT substr('你好吗', 0, 2) AS multibyte_zero;

-- Numeric positions and lengths retain the existing Oracle coercion path.
SELECT substr('abcdef', 2.4::number, 2.4::number) AS numeric_arguments;

-- The byte-semantic variant remains unchanged.
SELECT substrb('abcdef', -2, 2) AS substrb_control;

-- PostgreSQL mode must continue using pg_catalog.substr semantics.
SET ivorysql.compatible_mode = pg;
SELECT substr('abcdef', 0, 2) AS pg_zero_position;
SELECT substr('abcdef', 2, 0) IS NULL AS pg_zero_length_is_null;

RESET ivorysql.compatible_mode;
