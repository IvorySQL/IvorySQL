-- Empty VARCHAR2 results must be SQL NULL, not non-null empty text.
SELECT sys.regexp_replace('a', 'a') IS NULL AS omitted_replacement;
SELECT sys.regexp_replace('aaa', 'a', NULL) IS NULL AS null_replacement;
SELECT sys.regexp_replace('abc', '.*', '') IS NULL AS empty_replacement;
SELECT sys.regexp_replace('中文', '.') IS NULL AS multibyte_removal;
SELECT sys.regexp_replace('a', '(a)(b)?', '\2') IS NULL AS empty_backreference;
SELECT sys.regexp_replace('a', 'a', NULL, 1, 1, 'i') IS NULL AS six_arguments;
SELECT regexp_replace('a', 'a') IS NULL AS unqualified_call;
-- The explicit text overload has the same VARCHAR2 result contract.
SELECT sys.regexp_replace('a'::pg_catalog.text, 'a'::pg_catalog.text,
                          NULL::pg_catalog.text) IS NULL AS text_overload;
-- Preserve nonempty results, unmatched input, NULL input and NULL pattern.
SELECT sys.regexp_replace('aba', 'a', NULL, 1, 1) AS one_occurrence;
SELECT sys.regexp_replace('abc', 'z') AS no_match;
SELECT sys.regexp_replace('abc', 'b', 'X') AS replacement;
SELECT sys.regexp_replace('abc', NULL) AS null_pattern;
SELECT sys.regexp_replace(NULL, 'a') IS NULL AS null_source;

-- Data cleaning must not count or persist an empty phone number as present.
SELECT count(sys.regexp_replace(s, '[^0-9]')) AS nonnull_phones
  FROM (SELECT 'abc' AS s FROM dual UNION ALL SELECT 'a1' FROM dual) t;
SELECT count(*) AS missing_phones
  FROM (SELECT 'abc' AS s FROM dual UNION ALL SELECT 'a1' FROM dual) t
 WHERE sys.regexp_replace(s, '[^0-9]') IS NULL;
CREATE TABLE regexp_replace_null_guard (phone varchar2(20) NOT NULL);
INSERT INTO regexp_replace_null_guard
  SELECT sys.regexp_replace('abc', '[^0-9]') FROM dual;
SELECT count(*) AS persisted_empty_phones FROM regexp_replace_null_guard;
INSERT INTO regexp_replace_null_guard
  SELECT sys.regexp_replace('a1', '[^0-9]') FROM dual;
SELECT phone FROM regexp_replace_null_guard;
DROP TABLE regexp_replace_null_guard;

-- The PostgreSQL function must retain its non-NULL empty text result.
SET ivorysql.compatible_mode = pg;
SELECT pg_catalog.regexp_replace('a', 'a', '') IS NOT NULL
       AND pg_catalog.octet_length(pg_catalog.regexp_replace('a', 'a', '')) = 0
       AS pg_empty_text_preserved;
SET ivorysql.compatible_mode = oracle;
