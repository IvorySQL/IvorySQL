--
-- VSIZE
--
-- Oracle-compatible VSIZE: number of bytes in the internal representation.
--

-- character data: byte length of the value (header excluded)
SELECT vsize('abc');
SELECT vsize(CAST('abc' AS VARCHAR2));
SELECT vsize('abc'::varchar);
SELECT vsize('abc'::char(10));
SELECT vsize('abc'::text) = vsize(CAST('abc' AS VARCHAR2)) AS same_as_varchar2;
SELECT vsize('abc') = lengthb('abc') AS same_as_lengthb;

-- multibyte data
SELECT vsize('你好'::text);

-- numeric data: byte length in Oracle's internal NUMBER format
-- (one exponent byte, one mantissa byte per two significant decimal
-- digits, plus a terminator byte for negative values; zero is one byte)
SELECT vsize(0::number);
SELECT vsize(1::number);
SELECT vsize(123::number);
SELECT vsize(1.23::number);
SELECT vsize(123::int4);
SELECT vsize(123::int8);
SELECT vsize(1.23::float8);
SELECT vsize('NaN'::float8);

-- NUMBER-format boundaries, values cross-checked against Oracle:
-- trailing zeros are not stored, negatives carry a terminator byte
SELECT vsize(100);
SELECT vsize(1000000);
SELECT vsize(-1);
SELECT vsize(-1200);
SELECT vsize(12345.67);
SELECT vsize(0.0000000001);
SELECT vsize(12345678901234567890123456789012345678);

-- other fixed-width types
SELECT vsize(true);
SELECT vsize('2024-01-01'::date);
SELECT vsize('2024-01-01 10:00:00'::timestamp);
SELECT vsize('2024-01-01 10:00:00+08'::timestamptz);

-- NULL input returns NULL
SELECT vsize(NULL::text);
SELECT vsize(NULL::number);

-- NULL values in a table
CREATE TABLE vsize_tbl(a text, b number);
INSERT INTO vsize_tbl VALUES ('hello', 12345);
INSERT INTO vsize_tbl VALUES (NULL, NULL);
INSERT INTO vsize_tbl VALUES ('world', 0);
SELECT vsize(a), vsize(b) FROM vsize_tbl ORDER BY a NULLS LAST;
DROP TABLE vsize_tbl;

-- large values that get toasted/compressed still report the logical size
SELECT vsize(repeat('a', 100000)) = lengthb(repeat('a', 100000)) AS big_text_matches_lengthb;
SELECT vsize(repeat('a', 100000));
CREATE TABLE vsize_big(a text);
INSERT INTO vsize_big SELECT repeat('b', 200000) FROM generate_series(1, 10);
SELECT bool_and(vsize(a) = lengthb(a)) AS toasted_matches_lengthb, min(vsize(a)) AS min_size FROM vsize_big;
DROP TABLE vsize_big;
