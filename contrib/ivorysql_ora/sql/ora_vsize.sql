--
-- VSIZE
--
-- Oracle-compatible VSIZE: number of bytes in the internal representation.
--

-- character data: byte length of the value (header excluded)
SELECT sys.vsize('abc');
SELECT sys.vsize('abc'::varchar2);
SELECT sys.vsize('abc'::varchar);
SELECT sys.vsize('abc'::char(10));
SELECT sys.vsize('abc'::text) = sys.vsize('abc'::varchar2) AS same_as_varchar2;
SELECT sys.vsize('abc') = lengthb('abc') AS same_as_lengthb;

-- multibyte data
SELECT sys.vsize('你好'::text);

-- numeric data
SELECT sys.vsize(0::number);
SELECT sys.vsize(1::number);
SELECT sys.vsize(123::number);
SELECT sys.vsize(1.23::number);
SELECT sys.vsize(123::int4);
SELECT sys.vsize(123::int8);
SELECT sys.vsize(1.23::float8);
SELECT sys.vsize('NaN'::float8);

-- other fixed-width types
SELECT sys.vsize(true);
SELECT sys.vsize('2024-01-01'::date);
SELECT sys.vsize('2024-01-01 10:00:00'::timestamp);
SELECT sys.vsize('2024-01-01 10:00:00+08'::timestamptz);

-- NULL input returns NULL
SELECT sys.vsize(NULL::text);
SELECT sys.vsize(NULL::number);

-- NULL values in a table
CREATE TABLE vsize_tbl(a text, b number);
INSERT INTO vsize_tbl VALUES ('hello', 12345);
INSERT INTO vsize_tbl VALUES (NULL, NULL);
INSERT INTO vsize_tbl VALUES ('world', 0);
SELECT sys.vsize(a), sys.vsize(b) FROM vsize_tbl ORDER BY a NULLS LAST;
DROP TABLE vsize_tbl;

-- large values that get toasted/compressed still report the logical size
SELECT sys.vsize(repeat('a', 100000)) = lengthb(repeat('a', 100000)) AS big_text_matches_lengthb;
SELECT sys.vsize(repeat('a', 100000));
CREATE TABLE vsize_big(a text);
INSERT INTO vsize_big SELECT repeat('b', 200000) FROM generate_series(1, 10);
SELECT bool_and(sys.vsize(a) = lengthb(a)) AS toasted_matches_lengthb, min(sys.vsize(a)) AS min_size FROM vsize_big;
DROP TABLE vsize_big;
