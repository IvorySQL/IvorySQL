SET ivorysql.compatible_mode = oracle;

CREATE TABLE ora_like_bigint(col bigint);
INSERT INTO ora_like_bigint VALUES (-428);
INSERT INTO ora_like_bigint VALUES (3.9);
INSERT INTO ora_like_bigint VALUES (17);

-- User-reported literal patterns: no matches, with and without ESCAPE.
SELECT * FROM ora_like_bigint WHERE col LIKE '%\%%';
SELECT * FROM ora_like_bigint WHERE col LIKE '%\%%' ESCAPE '\';
SELECT * FROM ora_like_bigint WHERE col NOT LIKE '%\%%' ORDER BY col;
SELECT * FROM ora_like_bigint WHERE col NOT LIKE '%\%%' ESCAPE '\' ORDER BY col;
SELECT * FROM ora_like_bigint WHERE col LIKE '%\-%';
SELECT * FROM ora_like_bigint WHERE col NOT LIKE '%\-%' ORDER BY col;

INSERT INTO ora_like_bigint VALUES (NULL);

-- The original BIGINT NOT LIKE cases, with the complementary LIKE results.
-- Patterns from a column also exercise runtime escape normalization.
WITH patterns(id, pattern) AS
  (VALUES (1, '1%'), (2, '%8'), (3, '%9%'), (4, '%'),
          (5, '_7'), (6, '%-%'), (7, '%.%'))
SELECT id, pattern,
       coalesce(array_agg(col ORDER BY col) FILTER (WHERE col LIKE pattern),
                '{}'::bigint[]) AS like_rows,
       coalesce(array_agg(col ORDER BY col) FILTER (WHERE col NOT LIKE pattern),
                '{}'::bigint[]) AS not_like_rows
FROM patterns CROSS JOIN ora_like_bigint
GROUP BY id, pattern ORDER BY id;

-- Literal patterns use the same implicit conversion for both operators.
SELECT col FROM ora_like_bigint WHERE col NOT LIKE '1%' ORDER BY col;
SELECT col FROM ora_like_bigint WHERE col NOT LIKE '%' ORDER BY col;

-- Without ESCAPE, backslashes are ordinary characters in Oracle mode.
WITH patterns(id, pattern) AS
  (VALUES (1, '%\%%'), (2, '%\-%'), (3, '%\.%'))
SELECT id, pattern,
       count(*) FILTER (WHERE col LIKE pattern) AS like_count,
       count(*) FILTER (WHERE col NOT LIKE pattern) AS not_like_count
FROM patterns CROSS JOIN ora_like_bigint
GROUP BY id, pattern ORDER BY id;

-- Explicit escapes can only precede %, _, or the escape character itself.
WITH patterns(id, pattern, esc) AS
  (VALUES (1, '%\%%', '\'), (2, '%\_%', '\'), (3, '%\\%', '\'),
          (4, '%+%%', '+'), (5, '%+_%', '+'), (6, '%++%', '+'))
SELECT id,
       count(*) FILTER (WHERE col LIKE pattern ESCAPE esc) AS like_count,
       count(*) FILTER (WHERE col NOT LIKE pattern ESCAPE esc) AS not_like_count
FROM patterns CROSS JOIN ora_like_bigint
GROUP BY id ORDER BY id;
-- A literal escaped minus is invalid, even though the data contains -428.
SELECT * FROM ora_like_bigint WHERE col LIKE '%\-%' ESCAPE '\';
SELECT * FROM ora_like_bigint WHERE col NOT LIKE '%\-%' ESCAPE '\';
SELECT col FROM ora_like_bigint WHERE col LIKE '%\.%' ESCAPE '\';
SELECT col FROM ora_like_bigint WHERE col NOT LIKE '%\.%' ESCAPE '\';
SELECT col FROM ora_like_bigint WHERE col NOT LIKE '%' ESCAPE '++';
SELECT col FROM ora_like_bigint WHERE col NOT LIKE 'abc\' ESCAPE '\';

-- NULL operands and NULL/empty escape expressions retain SQL null semantics.
SELECT (NULL::bigint NOT LIKE '1%') IS NULL AS null_value,
       (17::bigint NOT LIKE NULL) IS NULL AS null_pattern,
       (17::bigint NOT LIKE '%' ESCAPE NULL) IS NULL AS null_escape,
       (17::bigint NOT LIKE '%' ESCAPE '') IS NULL AS empty_escape;

-- Cover int8 boundaries without conversion through a floating point type.
SELECT col, col LIKE '-%' AS negative,
       col NOT LIKE '-%' AS nonnegative,
       col LIKE '%8' AS ends_in_8,
       col NOT LIKE '%8' AS not_ending_in_8
FROM (VALUES ('-9223372036854775808'::bigint), (0::bigint),
             ('9223372036854775807'::bigint)) AS v(col)
ORDER BY col;

-- Explicit text and varchar2 patterns must both resolve for int8 operands.
SELECT 17::bigint NOT LIKE '1%'::text AS text_pattern,
       17::bigint NOT LIKE '1%'::varchar2 AS varchar2_pattern,
       17::bigint NOT LIKE '1%'::varchar2(10 char) AS varchar2_char_pattern,
       17::bigint LIKE '1%'::text AS text_like;

-- Prepared statements resolve int8 operands and normalize parameter patterns.
PREPARE ora_bigint_like(bigint, text, text) AS
SELECT $1 LIKE $2 AS matched, $1 NOT LIKE $2 AS not_matched,
       $1 NOT LIKE $2 ESCAPE $3 AS escaped_not_matched;
SELECT $$EXECUTE ora_bigint_like(-428, '%\-%', '+');$$ \gexec
SELECT $$EXECUTE ora_bigint_like(-428, '%\%%', '\');$$ \gexec
SELECT $$EXECUTE ora_bigint_like(17, '1%', '+');$$ \gexec
SELECT $$EXECUTE ora_bigint_like(-428, '%\-%', '\');$$ \gexec
DEALLOCATE ora_bigint_like;

DROP TABLE ora_like_bigint;
SET ivorysql.compatible_mode = pg;

-- PostgreSQL still requires an explicit cast for numeric pattern matching.
SELECT 17::bigint LIKE '1%';
SELECT 17::bigint NOT LIKE '1%';
SELECT (-428)::bigint::text LIKE '%\-%' AS pg_like,
       (-428)::bigint::text NOT LIKE '%\-%' AS pg_not_like;
