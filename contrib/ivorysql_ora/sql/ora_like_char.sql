SET ivorysql.compatible_mode = oracle;

-- Keep the padding of both CHAR length semantics during LIKE matching.
CREATE TABLE ora_like_char(id integer, b CHAR(18 BYTE), c CHAR(18 CHAR));
INSERT INTO ora_like_char VALUES
    (1, 'bc', 'bc'), (2, 'abc', 'abc'), (3, 'abcd', 'abcd'),
    (4, 'bem', 'bem'), (5, 'abcdefg', 'abcdefg'),
    (6, '小巷人家', '小巷人家'), (7, '三体', '三体'),
    (8, 'Sam', 'Sam'), (9, 'sam', 'sam'), (10, 'am', 'am'),
    (11, NULL, NULL);

-- Original report: no value ends in d after being padded to CHAR(18).
SELECT id FROM ora_like_char WHERE b LIKE '%d' ORDER BY id;
SELECT id FROM ora_like_char WHERE b NOT LIKE '%d' ORDER BY id;

-- Exercise nonconstant patterns, underscores, UTF-8, and complementary results.
WITH patterns(id, pattern) AS
    (VALUES (1, 'a%'), (2, '%d'), (3, '%e%'), (4, '%'),
            (5, '_m'), (6, 'be_'), (7, '_b_'), (8, '%_'),
            (9, '_%'), (10, '%人%'), (11, 'S%'), (12, '%d%'),
            (13, '% '), (14, 'abcd______________'))
SELECT p.id, pattern,
       count(*) FILTER (WHERE b LIKE pattern) AS byte_like,
       count(*) FILTER (WHERE b NOT LIKE pattern) AS byte_not_like,
       count(*) FILTER (WHERE c LIKE pattern) AS char_like,
       count(*) FILTER (WHERE c NOT LIKE pattern) AS char_not_like
FROM patterns p CROSS JOIN ora_like_char t
GROUP BY p.id, pattern ORDER BY p.id;

-- Verify padding exists in storage and ordinary text casts still trim it.
SELECT id, length(b) AS byte_chars, length(c) AS char_chars
FROM ora_like_char WHERE id IN (3, 6, 7) ORDER BY id;
SELECT length(b::text) AS cast_length, b::text LIKE '%d' AS explicit_cast,
       b = 'abcd' AS equality,
       CAST('abcd' AS VARCHAR2(18)) LIKE '%d' AS varchar_like
FROM ora_like_char WHERE id = 3;

-- CHAR patterns must retain their own padding before like_escape runs.
SELECT b LIKE CAST('%d' AS CHAR(16 BYTE)) AS byte_pattern,
       b LIKE CAST('%d' AS CHAR(18 BYTE)) AS longer_byte_pattern,
       b NOT LIKE CAST('%d' AS CHAR(18 BYTE)) AS longer_byte_not_like,
       b LIKE CAST('%d' AS CHAR(16 CHAR)) AS mixed_pattern,
       c LIKE CAST('%d' AS CHAR(16 BYTE)) AS mixed_value,
       c LIKE CAST('%d' AS CHAR(16 CHAR)) AS char_pattern
FROM ora_like_char WHERE id = 3;
SELECT b LIKE CAST('%d' AS CHAR(16 BYTE)) ESCAPE '+' AS escaped_pattern,
       b LIKE CAST('%d' AS CHAR(18 BYTE)) ESCAPE '+' AS escaped_longer,
       b NOT LIKE CAST('%d' AS CHAR(18 BYTE)) ESCAPE '+' AS escaped_not_like
FROM ora_like_char WHERE id = 3;

-- An escaped underscore consumes one character; padding must also match.
SELECT CAST('a_' AS CHAR(5)) LIKE 'a\_' ESCAPE '\' AS no_padding,
       CAST('a_' AS CHAR(5)) LIKE 'a\_   ' ESCAPE '\' AS with_padding,
       CAST('a_' AS CHAR(5)) LIKE 'a\_%' ESCAPE '\' AS trailing_wildcard,
       CAST('a_' AS CHAR(5)) NOT LIKE 'a\_' ESCAPE '\' AS not_like;
SELECT CAST('小_' AS CHAR(5 CHAR)) LIKE '小\_' ESCAPE '\' AS no_padding,
       CAST('小_' AS CHAR(5 CHAR)) LIKE '小\_%' ESCAPE '\' AS trailing_wildcard;

-- Padding also counts toward the required single-character escape length.
SELECT b LIKE '%d' ESCAPE CAST('+' AS CHAR(2)) FROM ora_like_char WHERE id = 3;
SELECT b NOT LIKE '%d' ESCAPE CAST('+' AS CHAR(2)) FROM ora_like_char WHERE id = 3;
SELECT b LIKE '%d' ESCAPE CAST('+' AS CHAR(1)) AS single_escape,
       b NOT LIKE '%d' ESCAPE CAST('+' AS CHAR(1)) AS single_not_like
FROM ora_like_char WHERE id = 3;

-- NULLs stay unknown, including typed CHAR patterns and escape arguments.
SELECT (b LIKE '%d') IS NULL AS null_value,
       (b NOT LIKE '%d') IS NULL AS null_not_like
FROM ora_like_char WHERE id = 11;
SELECT (b LIKE CAST(NULL AS CHAR(18))) IS NULL AS null_pattern,
       (b LIKE '%d' ESCAPE NULL) IS NULL AS null_escape,
       (b NOT LIKE '%d' ESCAPE NULL) IS NULL AS null_not_escape
FROM ora_like_char WHERE id = 3;

-- Planning with an index and stored expressions must keep the same semantics.
CREATE INDEX ora_like_char_idx ON ora_like_char(b);
SET enable_seqscan = off;
SELECT id FROM ora_like_char WHERE b LIKE 'a%' ORDER BY id;
SELECT id FROM ora_like_char WHERE b LIKE '%d' ORDER BY id;
RESET enable_seqscan;
CREATE VIEW ora_like_char_view AS SELECT id FROM ora_like_char WHERE b LIKE '%d';
SELECT count(*) FROM ora_like_char_view;
-- Restoring the deparsed definition must preserve the padding semantics.
SELECT 'CREATE OR REPLACE VIEW ora_like_char_view AS ' ||
       pg_get_viewdef('ora_like_char_view'::regclass) \gexec
SELECT count(*) FROM ora_like_char_view;
DROP VIEW ora_like_char_view;
CREATE VIEW ora_like_char_pattern_view AS
SELECT b LIKE CAST('%d' AS CHAR(16)) AS padded_pattern,
       b LIKE CAST('%d' AS CHAR(18)) AS longer_pattern,
       b NOT LIKE CAST('%d' AS CHAR(18)) ESCAPE '+' AS escaped_not_like
FROM ora_like_char WHERE id = 3;
SELECT * FROM ora_like_char_pattern_view;
SELECT 'CREATE OR REPLACE VIEW ora_like_char_pattern_view AS ' ||
       pg_get_viewdef('ora_like_char_pattern_view'::regclass) \gexec
SELECT * FROM ora_like_char_pattern_view;
DROP VIEW ora_like_char_pattern_view;
CREATE TABLE ora_like_char_generated
    (b CHAR(18), matched boolean GENERATED ALWAYS AS (b LIKE '%d') VIRTUAL);
INSERT INTO ora_like_char_generated(b) VALUES ('abcd');
SELECT matched FROM ora_like_char_generated;
DROP TABLE ora_like_char_generated;

-- Reparse a prepared statement when changing compatibility mode.
SELECT b LIKE $1::text AS matched, b NOT LIKE $1::text AS not_matched
FROM ora_like_char WHERE id = 3 \parse ora_like_char_prepared
\bind_named ora_like_char_prepared '%d' \g
SET ivorysql.compatible_mode = pg;
\bind_named ora_like_char_prepared '%d' \g
-- Native PG CHAR keeps its existing padding-sensitive behavior, too.
SELECT CAST('abcd' AS CHAR(18)) LIKE '%d' AS pg_char_like,
       CAST('abcd' AS CHAR(18)) NOT LIKE '%d' AS pg_char_not_like,
       CAST('abcd' AS CHAR(18)) LIKE '%d              ' AS pg_padded;
SET ivorysql.compatible_mode = oracle;
\bind_named ora_like_char_prepared '%d' \g
\close_prepared ora_like_char_prepared
DROP TABLE ora_like_char;
