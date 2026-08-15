-- Test UTL_RAW package

-- Basic CAST_TO_RAW: verify bytes are preserved
SELECT UTL_RAW.CAST_TO_RAW('hello');
SELECT UTL_RAW.CAST_TO_RAW('ABC');

-- NULL input returns NULL
SELECT UTL_RAW.CAST_TO_RAW(NULL) IS NULL;

-- Empty string
SELECT UTL_RAW.CAST_TO_RAW('');

-- Multi-byte characters (Chinese)
SELECT UTL_RAW.CAST_TO_RAW('你好');

-- Mixed Chinese and ASCII characters
SELECT UTL_RAW.CAST_TO_RAW('你好ABC世界');

-- Package constants
SELECT UTL_RAW.big_endian;

-- Special characters
SELECT UTL_RAW.CAST_TO_RAW('a b c');
SELECT UTL_RAW.CAST_TO_RAW('\n');

-- CAST_TO_RAW preserves bytes in a non-UTF8 database
\set original_db :DBNAME
CREATE DATABASE utl_raw_latin1
    TEMPLATE template0 ENCODING 'LATIN1' LC_COLLATE 'C' LC_CTYPE 'C';
\c utl_raw_latin1
SELECT pg_catalog.encode(
    UTL_RAW.CAST_TO_RAW(pg_catalog.convert_from(pg_catalog.decode('e9', 'hex'), 'LATIN1')),
    'hex');
\c :original_db
DROP DATABASE utl_raw_latin1;
