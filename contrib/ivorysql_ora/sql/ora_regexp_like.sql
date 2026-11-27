-- Ordinary calls with literals and text arguments use Oracle semantics.
SELECT CASE WHEN REGEXP_LIKE('abc', 'a') THEN 'Y' ELSE 'N' END AS matched;
SELECT CASE WHEN REGEXP_LIKE('abc', 'a', 'xq') THEN 'Y' ELSE 'N' END FROM dual;
SELECT CASE WHEN REGEXP_LIKE('abc', 'a', 'xqz') THEN 'Y' ELSE 'N' END FROM dual;
SELECT REGEXP_LIKE('abc'::text, 'a'::text, 'q'::text);
SELECT sys.REGEXP_LIKE('abc', 'a', 'xq');
SELECT REGEXP_LIKE('abc', 'a', 'z');
SELECT REGEXP_LIKE('abc', 'a', 'p');
SELECT REGEXP_LIKE('abc', 'a', 'g');
SELECT REGEXP_LIKE('abc', 'a', 'I');
SELECT REGEXP_LIKE('abc', 'a', 'x中');
SELECT REGEXP_LIKE(NULL, 'a', 'q');
SELECT REGEXP_LIKE('abc', NULL, 'q');

-- Case options are applied in order; expanded syntax ignores whitespace.
SELECT REGEXP_LIKE('abc', '^A', 'i') AS insensitive,
       REGEXP_LIKE('abc', '^A', 'ic') AS last_sensitive,
       REGEXP_LIKE('abc', '^A', 'ci') AS last_insensitive,
       REGEXP_LIKE('abc', 'a b c', 'x') AS expanded;

-- A NULL match parameter means defaults; NULL source/pattern is unknown.
SELECT REGEXP_LIKE('abc', 'a', NULL) AS null_flags,
       REGEXP_LIKE('abc', 'a', '') AS empty_flags,
       REGEXP_LIKE(NULL, 'a') IS NULL AS null_source,
       REGEXP_LIKE('abc', NULL, 'i') IS NULL AS null_pattern;
SELECT sys.REGEXP_LIKE(CAST('abc' AS VARCHAR2(10)),
                       CAST('a' AS VARCHAR2(10)),
                       CAST(NULL AS VARCHAR2(10))) AS varchar_null_flags;

-- Oracle defaults, n (dot matches newline), and m (line anchors) are distinct.
SELECT REGEXP_LIKE('a' || CHR(10) || 'b', '^a.b$') AS default_mode,
       REGEXP_LIKE('a' || CHR(10) || 'b', '^a.b$', NULL) AS null_mode,
       REGEXP_LIKE('a' || CHR(10) || 'b', '^a.b$', 'n') AS n_mode,
       REGEXP_LIKE('a' || CHR(10) || 'b', '^a.b$', 'm') AS m_mode,
       REGEXP_LIKE('a' || CHR(10) || 'b', '^a.b$', 'mn') AS mn_mode,
       REGEXP_LIKE('a' || CHR(10) || 'b', '^a.b$', 'nm') AS nm_mode;
SELECT REGEXP_LIKE('a' || CHR(10) || 'b', '^b$') AS default_mode,
       REGEXP_LIKE('a' || CHR(10) || 'b', '^b$', 'n') AS n_mode,
       REGEXP_LIKE('a' || CHR(10) || 'b', '^b$', 'm') AS m_mode,
       REGEXP_LIKE('a' || CHR(10) || 'b', '^b$', 'mn') AS mn_mode;

-- Check both native text and Oracle VARCHAR2 columns, including NULLs.
CREATE TABLE regexp_like_inputs (id integer, t text, v VARCHAR2(30));
INSERT INTO regexp_like_inputs VALUES
    (1, 'a' || CHR(10) || 'b', 'a' || CHR(10) || 'b'),
    (2, 'abc', 'abc'), (3, NULL, NULL);
SELECT id, REGEXP_LIKE(t, '^a.b$') AS text_default,
       REGEXP_LIKE(v, '^a.b$') AS varchar_default,
       REGEXP_LIKE(t, '^a.b$', 'n') AS text_n,
       REGEXP_LIKE(v, '^a.b$', 'n') AS varchar_n,
       REGEXP_LIKE(t, '^b$', 'm') AS text_m,
       REGEXP_LIKE(v, '^b$', 'm') AS varchar_m
FROM regexp_like_inputs ORDER BY id;
SELECT REGEXP_LIKE(v, 'a', 'q') FROM regexp_like_inputs WHERE id = 2;
DROP TABLE regexp_like_inputs;

-- Explicit PostgreSQL qualification remains available in Oracle mode.
SELECT pg_catalog.REGEXP_LIKE('abc', 'a', 'q') AS explicitly_pg;
SELECT pg_catalog.REGEXP_LIKE('a' || CHR(10) || 'b', '^a.b$') AS pg_default;

-- Prepared statements must be reparsed correctly after a mode change.
SELECT REGEXP_LIKE($1::text, $2::text, $3::text) \parse regexp_like_prepared
\bind_named regexp_like_prepared 'abc' 'a' 'q' \g
SET ivorysql.compatible_mode = pg;
\bind_named regexp_like_prepared 'abc' 'a' 'q' \g
SELECT REGEXP_LIKE('abc', 'a', 'q') AS pg_quoted;
SELECT REGEXP_LIKE('a' || CHR(10) || 'b', '^a.b$') AS pg_default,
       REGEXP_LIKE('a' || CHR(10) || 'b', '^a.b$', 'n') AS pg_n,
       REGEXP_LIKE('a' || CHR(10) || 'b', '^a.b$', 'm') AS pg_m,
       REGEXP_LIKE('a' || CHR(10) || 'b', '^a.b$', 's') AS pg_s;
SELECT REGEXP_LIKE('abc', 'a', 'xq');
SELECT REGEXP_LIKE('abc', 'a', 'xqz');
SET ivorysql.compatible_mode = oracle;
\bind_named regexp_like_prepared 'abc' 'a' 'q' \g
\close_prepared regexp_like_prepared

-- Explicit search_path order and schema-qualified user functions are honored.
SET search_path = pg_catalog, sys, public;
SELECT REGEXP_LIKE('abc', 'a', 'q') AS pg_path_first;
RESET search_path;
CREATE SCHEMA regexp_like_user;
CREATE FUNCTION regexp_like_user.regexp_like(text, text, text)
RETURNS bool LANGUAGE SQL IMMUTABLE AS 'SELECT false';
/
SET search_path = regexp_like_user, sys, pg_catalog;
SELECT REGEXP_LIKE('abc', 'a', 'q') AS user_path_first;
SELECT sys.REGEXP_LIKE('abc', 'a', 'q');
RESET search_path;
SELECT regexp_like_user.REGEXP_LIKE('abc', 'a', 'q') AS explicitly_user;
DROP FUNCTION regexp_like_user.regexp_like(text, text, text);
DROP SCHEMA regexp_like_user;
