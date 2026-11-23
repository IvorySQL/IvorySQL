--
-- DUMP
--
-- Oracle-compatible DUMP: returns internal data type code, byte length,
-- optional character set, and byte values of internal representation.
--

-- Character data (Typ=1 for varchar2/text, Typ=96 for char/bpchar)
SELECT dump('abc');
SELECT dump(CAST('abc' AS VARCHAR2));
SELECT dump('abc'::varchar);
SELECT dump('abc'::char(5));

-- Multibyte character data
SELECT dump('你好'::text);

-- Return formats: 8 (Octal), 10 (Decimal), 16 (Hex), 17 (ASCII/Char)
SELECT dump('abc', 10);
SELECT dump('abc', 8);
SELECT dump('abc', 16);
SELECT dump('abc', 17);

-- Start position and length arguments
SELECT dump('abcdef', 10, 1, 3);
SELECT dump('abcdef', 10, 3, 2);
SELECT dump('abcdef', 16, 4, 2);
SELECT dump('abcdef', 17, 2, 4);

-- Format + 1000: CharacterSet inclusion (e.g., 1010, 1016, 1017)
SELECT dump('abc', 1010) LIKE 'Typ=% Len=3 CharacterSet=%: 97,98,99' AS dump_1010_has_charset;
SELECT dump('abc', 1016) LIKE 'Typ=% Len=3 CharacterSet=%: 61,62,63' AS dump_1016_has_charset;
SELECT dump('abc', 1017) LIKE 'Typ=% Len=3 CharacterSet=%: a,b,c' AS dump_1017_has_charset;

-- Numeric data types (Typ=2 for number/numeric/integer)
SELECT dump(0::number);
SELECT dump(123::number);
SELECT dump(123::int4);
SELECT dump(123::int8);

-- Floating point types (Typ=100 for binary_float, Typ=101 for binary_double)
SELECT dump(1.25::float4);
SELECT dump(1.25::float8);

-- Date and datetime types (Typ=12 for date/oradate, Typ=180 for timestamp)
SELECT dump('2024-01-01'::date);
SELECT dump('2024-01-01 12:00:00'::timestamp);

-- Raw / bytea types (Typ=23)
SELECT dump(E'\\x010203'::bytea, 16);

-- Format 17 with control characters
SELECT dump(E'a\nb', 17);
SELECT dump(E'x\ty', 17);

-- NULL input yields NULL (Oracle semantics)
SELECT dump(NULL::text);
SELECT dump(NULL::number);
SELECT dump(NULL::int4, 16);

-- Boundary edge cases: start_position beyond length, length exceeds remaining bytes
SELECT dump('abc', 10, 5, 2);
SELECT dump('abc', 10, 2, 10);
SELECT dump('abc', 10, 0, 2);

-- Uncaught invalid format error verification (assert client ERROR output)
SELECT dump('abc', 99);
SELECT dump('abc', -1);

-- Table storage and expressions with DUMP
CREATE TABLE dump_test_tab (
    id int4,
    v_char char(10),
    v_varchar2 varchar2(20),
    v_num number,
    v_raw raw(10)
);

INSERT INTO dump_test_tab VALUES (1, 'hello', 'world', 123.45, E'\\xdeadbeef'::bytea);
INSERT INTO dump_test_tab VALUES (2, NULL, NULL, NULL, NULL);

SELECT id,
       dump(v_char, 10, 1, 5) AS dump_char,
       dump(v_varchar2) AS dump_varchar2,
       dump(v_num) AS dump_num,
       dump(v_raw, 16) AS dump_raw
  FROM dump_test_tab
 ORDER BY id;

DROP TABLE dump_test_tab;

-- Catalog contract verification for sys.dump overloads
SELECT p.proname, p.pronargs, p.prorettype::regtype, p.provolatile, p.proparallel
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname = 'dump'
 ORDER BY p.pronargs;

