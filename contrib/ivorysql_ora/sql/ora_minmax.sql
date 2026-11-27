-- A numeric first argument uses Oracle numeric precedence, not integer input.
SELECT GREATEST(1, '3.925', '2.4') AS greatest,
       LEAST(1, '3.925', '2.4') AS least,
       LEAST(1, '2.1', '.000832') AS small_fraction;
SELECT GREATEST(1, '3.925', 2.4) AS mixed_numeric,
       LEAST(-1, '-3.925', '-2.4') AS negative,
       GREATEST(1, '123456789012345678901234567890.125') AS exact_number;
SELECT GREATEST(9223372036854775807::bigint, '9223372036854775807.125') AS bigint_number,
       LEAST(1::smallint, '0.125') AS smallint_number;
SELECT pg_typeof(GREATEST(1, '3.925')) AS number_result,
       pg_typeof(GREATEST(1, 2.4f, '3.925')) AS float_result,
       pg_typeof(LEAST(1, 2.4d, '3.925')) AS double_result,
       pg_typeof(GREATEST(1, 2.4d, 3.5f)) AS double_precedence;
SELECT GREATEST(1, 2.4f, '3.925') = CAST('3.925' AS BINARY_FLOAT) AS float_value,
       LEAST(1, 2.4d, '.000832') = CAST('.000832' AS BINARY_DOUBLE) AS double_value;

-- A character first argument compares text and returns VARCHAR2.
SELECT GREATEST('9', 10) AS character_greatest,
       LEAST('9', 10) AS character_least,
       GREATEST('1', '3.925', '2.4') AS all_strings;
SELECT pg_typeof(GREATEST(CAST('9' AS CHAR(3 BYTE)), 10)) AS byte_result,
       pg_typeof(LEAST(CAST('9' AS CHAR(3 CHAR)), 10)) AS char_result;
SELECT '[' || GREATEST(CAST('abc' AS CHAR(5)), 'abc ') || ']' AS char_greatest,
       '[' || LEAST(CAST('abc' AS CHAR(5)), 'abc ') || ']' AS char_least,
       '[' || LEAST(CAST('abc' AS CHAR(5 CHAR)), 'abc ') || ']' AS char_semantics;
SELECT GREATEST('a' COLLATE "C", 'B') AS collated_greatest,
       LEAST('a' COLLATE "C", 'B') AS collated_least;
ALTER SESSION SET NLS_LENGTH_SEMANTICS = CHAR;
SELECT pg_typeof(GREATEST('a', 'b')) =
       pg_typeof(CAST('b' AS VARCHAR2(10 CHAR))) AS char_literal_type;
ALTER SESSION SET NLS_LENGTH_SEMANTICS = DEFAULT;

-- Non-numeric, non-character first arguments keep their original type.
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';
SELECT GREATEST(DATE '2020-01-01', '2021-01-01') AS later_date,
       LEAST(DATE '2020-01-01', '2021-01-01') AS earlier_date;
ALTER SESSION SET NLS_DATE_FORMAT = DEFAULT;

-- NULL (including an empty Oracle string) propagates in either operation.
SELECT GREATEST(1, NULL, 3) IS NULL AS middle_null,
       LEAST(NULL, 1, 3) IS NULL AS first_null,
       GREATEST(1, 3, NULL) IS NULL AS last_null,
       LEAST(NULL, NULL) IS NULL AS all_null,
       GREATEST('a', '') IS NULL AS empty_string;
SELECT GREATEST(1, NULL, 'bad') IS NULL AS skipped_bad_number,
       LEAST(1, NULL, 1 / 0) IS NULL AS skipped_division,
       GREATEST(NULL, 1 / 0) IS NULL AS first_null;

CREATE TABLE minmax_inputs (id integer, n number, v varchar2(30));
INSERT INTO minmax_inputs VALUES (1, 1, '3.925'), (2, NULL, 'bad');
SELECT id, GREATEST(n, v) AS greatest, LEAST(n, v) AS least
FROM minmax_inputs ORDER BY id;
-- Do not fold an unreachable constant conversion or division during planning.
SELECT id, GREATEST(n, 'bad') IS NULL AS skipped_bad_number,
       LEAST(n, 1 / 0) IS NULL AS skipped_division
FROM minmax_inputs WHERE id = 2;
SELECT id, GREATEST(n, LEAST(1, 'bad')) IS NULL AS nested_expression
FROM minmax_inputs WHERE id = 2;
-- Earlier errors and incompatible argument types must still be rejected.
SELECT GREATEST(1, 'bad', NULL);
SELECT LEAST(1, 'bad');
SELECT GREATEST(n, 'bad', NULL) FROM minmax_inputs WHERE id = 1;
SELECT GREATEST(1, NULL, DATE '2020-01-01');

-- Argument expansion remains necessary even when constant evaluation is deferred.
SET ivorysql.compatible_mode = pg;
CREATE FUNCTION minmax_default(a integer DEFAULT 7, b integer DEFAULT 3)
RETURNS integer LANGUAGE SQL IMMUTABLE AS 'SELECT a + b';
/
SET ivorysql.compatible_mode = oracle;
SELECT id, GREATEST(n, minmax_default(b => 5)) AS named_default,
       LEAST(n, minmax_default()) AS all_defaults
FROM minmax_inputs ORDER BY id;
DROP FUNCTION minmax_default;

-- Each reached argument is evaluated once; later arguments stop at NULL.
CREATE SEQUENCE minmax_seq START WITH 1;
SELECT GREATEST(nextval('minmax_seq'), 2, 3) AS single_evaluation,
       currval('minmax_seq') AS sequence_value;
SELECT LEAST(nextval('minmax_seq'), NULL, nextval('minmax_seq')) IS NULL AS middle_null,
       currval('minmax_seq') AS sequence_value;
SELECT GREATEST(NULL, nextval('minmax_seq')) IS NULL AS first_null,
       currval('minmax_seq') AS sequence_value;
DROP SEQUENCE minmax_seq;

-- The declared type of a prepared argument still controls numeric conversion.
PREPARE minmax_prepared(integer, varchar2, varchar2) AS
SELECT GREATEST($1, $2, $3), LEAST($1, $2, $3);
-- Send SQL EXECUTE directly, bypassing the client's SQL*Plus EXECUTE command.
SELECT 'EXECUTE minmax_prepared(1, ''3.925'', ''2.4'')' \gexec
SELECT 'EXECUTE minmax_prepared(NULL, ''bad'', ''2.4'')' \gexec
DEALLOCATE minmax_prepared;

-- Saving and deparsing a view must retain CHAR padding and Oracle NULL rules.
CREATE VIEW minmax_view AS
SELECT GREATEST(n, v), LEAST(n, v),
       '[' || GREATEST(CAST('abc' AS CHAR(5)), 'abc ') || ']' AS padded
FROM minmax_inputs;
SELECT * FROM minmax_view ORDER BY greatest NULLS LAST;
SELECT 'CREATE OR REPLACE VIEW minmax_view AS ' ||
       pg_get_viewdef('minmax_view'::regclass) \gexec
SELECT * FROM minmax_view ORDER BY greatest NULLS LAST;
SET ivorysql.compatible_mode = pg;
SELECT * FROM minmax_view ORDER BY greatest NULLS LAST;

-- Native PostgreSQL type inference and its treatment of NULL are unchanged.
SELECT GREATEST(1, '3.925', '2.4');
SELECT GREATEST(1, NULL, 3) AS pg_greatest,
       LEAST(1, NULL, 3) AS pg_least,
       GREATEST('9', 10) AS pg_numeric;
CREATE VIEW minmax_pg_view AS SELECT GREATEST(1, NULL, 3), LEAST(1, NULL, 3);
SET ivorysql.compatible_mode = oracle;
SELECT * FROM minmax_pg_view;
DROP VIEW minmax_pg_view;
DROP VIEW minmax_view;
DROP TABLE minmax_inputs;
