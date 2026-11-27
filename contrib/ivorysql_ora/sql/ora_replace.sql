-- Empty, NULL, and omitted replacements all remove the search string.
SELECT '[' || REPLACE('hello world', 'world', '') || ']' AS empty_replacement,
       '[' || REPLACE('hello world', 'world', NULL) || ']' AS null_replacement,
       '[' || REPLACE('hello world', 'world') || ']' AS omitted_replacement,
       LENGTH(REPLACE('hello world', 'world', '')) AS result_length;

-- A NULL or empty search string leaves the source unchanged.
SELECT REPLACE('hello world', NULL, 'x') AS null_search,
       REPLACE('hello world', '', 'x') AS empty_search,
       REPLACE('hello world', NULL) AS omitted_replacement;
SELECT REPLACE(NULL, 'world', 'x') IS NULL AS null_source,
       REPLACE('', 'world', 'x') IS NULL AS empty_source;

-- Completely removing the source yields NULL, not a non-NULL empty text.
SELECT REPLACE('world', 'world', '') IS NULL AS fully_deleted,
       REPLACE('world', 'world', NULL) IS NULL AS null_replacement,
       REPLACE('world', 'world') IS NULL AS omitted_replacement,
       sys.REPLACE('world'::varchar2, 'world'::varchar2,
                   NULL::varchar2) IS NULL AS varchar_deleted;

-- Other replacement behavior, including repeated and multibyte matches.
SELECT REPLACE('JACK and JUE', 'J', 'BL') AS replaced,
       REPLACE('aaaaa', 'aa', '') AS repeated,
       REPLACE('abc', 'x', '') AS no_match,
       REPLACE('abcabc', 'abc', 'abc') AS unchanged;
SELECT REPLACE(UNISTR('\4E2D\6587\4E2D\6587'), UNISTR('\4E2D\6587'), 'x') AS multibyte,
       REPLACE(UNISTR('\4E2D\6587'), UNISTR('\4E2D\6587'), '') IS NULL AS multibyte_deleted;

-- Both text and VARCHAR2 columns must use Oracle NULL argument rules.
CREATE TABLE replace_inputs (id integer, t text, v varchar2(30), needle text);
INSERT INTO replace_inputs VALUES
    (1, 'hello world', 'hello world', 'world'),
    (2, 'hello world', 'hello world', NULL),
    (3, 'world', 'world', 'world'),
    (4, NULL, NULL, 'world');
SELECT id, REPLACE(t, needle, NULL) AS text_result,
       REPLACE(v, needle, NULL) AS varchar_result,
       REPLACE(t, needle, NULL) IS NULL AS result_is_null,
       LENGTH(REPLACE(t, needle, NULL)) AS result_length
FROM replace_inputs ORDER BY id;
DROP TABLE replace_inputs;

-- Raw empty text arguments are handled by the Oracle implementation too.
SET ivorysql.enable_emptystring_to_null = off;
SELECT sys.REPLACE('', 'x', 'y') IS NULL AS empty_source,
       sys.REPLACE('abc', '', NULL) AS empty_search,
       sys.REPLACE('abc', 'abc', '') IS NULL AS fully_deleted;
RESET ivorysql.enable_emptystring_to_null;

-- An explicit PG search path or qualification keeps PostgreSQL semantics.
SET search_path = pg_catalog, sys, public;
SELECT REPLACE('hello world', 'world', NULL) IS NULL AS pg_path_first;
RESET search_path;
SELECT pg_catalog.REPLACE('hello world', 'world', NULL) IS NULL AS pg_qualified;

-- Default PG-mode calls retain strict NULL handling and empty text output.
SET ivorysql.compatible_mode = pg;
SELECT '[' || REPLACE('hello world', 'world', '') || ']' AS pg_empty_replacement,
       REPLACE('hello world', 'world', NULL) IS NULL AS pg_null_replacement,
       REPLACE('hello world', NULL, 'x') IS NULL AS pg_null_search;
SELECT REPLACE('world', 'world', '') IS NULL AS pg_deleted_is_null,
       LENGTH(REPLACE('world', 'world', '')) AS pg_deleted_length;
SET ivorysql.compatible_mode = oracle;

-- Switching to the Oracle built-in must preserve expression eligibility.
BEGIN;
SET LOCAL client_min_messages = error;
ALTER FUNCTION sys.replace(text, text, text) RENAME TO replace_before_oid_test;
CREATE FUNCTION sys.replace(text, text, text DEFAULT NULL)
RETURNS text AS '$libdir/ivorysql_ora', 'ora_replace'
LANGUAGE C IMMUTABLE CALLED ON NULL INPUT;
/
ALTER EXTENSION ivorysql_ora ADD FUNCTION sys.replace(text, text, text);
SELECT 'sys.replace(text,text,text)'::regprocedure::oid >= 16384 AS high_oid;
CREATE TABLE replace_generated (s text,
    r text GENERATED ALWAYS AS (REPLACE(s, 'world', NULL)) VIRTUAL);
INSERT INTO replace_generated(s) VALUES ('hello world'), ('world'), (NULL);
SELECT s, r, r IS NULL AS result_is_null FROM replace_generated
ORDER BY s COLLATE "C" NULLS LAST;
CREATE PUBLICATION replace_pub FOR TABLE replace_generated
    WHERE (REPLACE(s, 'world', 'x') = 'x') WITH (publish = 'insert');
SELECT count(*) AS function_dependencies FROM pg_depend
WHERE refclassid = 'pg_proc'::regclass
  AND refobjid = 'sys.replace(text,text,text)'::regprocedure
  AND classid IN ('pg_publication_rel'::regclass, 'pg_attrdef'::regclass);

-- An immutable SQL replacement of the extension member is still rejected.
SAVEPOINT rejected;
CREATE OR REPLACE FUNCTION sys.replace(text, text, text DEFAULT NULL)
RETURNS text LANGUAGE SQL IMMUTABLE CALLED ON NULL INPUT AS 'SELECT $1';
/
CREATE PUBLICATION replace_bad_pub FOR TABLE replace_generated
    WHERE (REPLACE(s, 'world', 'x') = 'x') WITH (publish = 'insert');
ROLLBACK TO rejected;
ROLLBACK;
