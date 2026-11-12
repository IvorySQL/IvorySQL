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

-- ============================================================
-- XRANGE
-- ============================================================

-- Inclusive range 0x20..0x2F: the 16 bytes 20 21 ... 2F
SELECT UTL_RAW.XRANGE(hextoraw('20'), hextoraw('2F'))
       = hextoraw('202122232425262728292A2B2C2D2E2F');

-- A one-byte range is that byte on its own
SELECT UTL_RAW.XRANGE(hextoraw('41'), hextoraw('41')) = hextoraw('41');

-- Boundary ranges at the low and high end of the byte range
SELECT UTL_RAW.XRANGE(hextoraw('00'), hextoraw('00')) = hextoraw('00');

SELECT UTL_RAW.XRANGE(hextoraw('FE'), hextoraw('FF')) = hextoraw('FEFF');

-- A NULL bound selects the Oracle default: X'00' for start_byte, X'FF' for
-- end_byte.  XRANGE is not STRICT, so the C function receives the NULLs.
SELECT UTL_RAW.XRANGE(NULL, hextoraw('20'))
       = hextoraw('000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F20');

SELECT UTL_RAW.XRANGE(hextoraw('FD'), NULL) = hextoraw('FDFEFF');

SELECT pg_catalog.octet_length(UTL_RAW.XRANGE(NULL, NULL)) = 256;

-- Omitted arguments fall back to the same defaults as explicit NULLs
SELECT UTL_RAW.XRANGE() = UTL_RAW.XRANGE(NULL, NULL);

SELECT UTL_RAW.XRANGE(hextoraw('FE')) = hextoraw('FEFF');

-- An inverted range wraps through X'FF' to X'00'
SELECT UTL_RAW.XRANGE(hextoraw('FE'), hextoraw('01')) = hextoraw('FEFF0001');

-- 0x2F..0x20 wraps: 0x2F..0xFF (209 bytes) followed by 0x00..0x20 (33 bytes)
SELECT pg_catalog.octet_length(UTL_RAW.XRANGE(hextoraw('2F'), hextoraw('20'))) = 242,
       pg_catalog.get_byte(UTL_RAW.XRANGE(hextoraw('2F'), hextoraw('20')), 0) = 47,
       pg_catalog.get_byte(UTL_RAW.XRANGE(hextoraw('2F'), hextoraw('20')), 208) = 255,
       pg_catalog.get_byte(UTL_RAW.XRANGE(hextoraw('2F'), hextoraw('20')), 209) = 0,
       pg_catalog.get_byte(UTL_RAW.XRANGE(hextoraw('2F'), hextoraw('20')), 241) = 32;

-- Both bounds must be exactly one byte
DO $$
BEGIN
    PERFORM UTL_RAW.XRANGE(hextoraw('2021'), hextoraw('2F'));
    RAISE NOTICE 'XRANGE multi-byte bound: no error';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'XRANGE multi-byte bound: error as expected';
END;
$$;

-- ============================================================
-- CAST_TO_VARCHAR2
-- ============================================================

-- The inverse of CAST_TO_RAW for ASCII text
SELECT UTL_RAW.CAST_TO_VARCHAR2(UTL_RAW.CAST_TO_RAW('hello')) = 'hello';

-- Multibyte text survives the byte round-trip
SELECT UTL_RAW.CAST_TO_VARCHAR2(UTL_RAW.CAST_TO_RAW('世界')) = '世界';

-- NULL propagation (STRICT)
SELECT UTL_RAW.CAST_TO_VARCHAR2(NULL) IS NULL;

-- ============================================================
-- CAST_FROM_BINARY_INTEGER / CAST_TO_BINARY_INTEGER
-- ============================================================

-- 0 is all zero bytes in either byte order
SELECT rawtohex(UTL_RAW.CAST_FROM_BINARY_INTEGER(0, 1)) = '00000000';

SELECT rawtohex(UTL_RAW.CAST_FROM_BINARY_INTEGER(0, 2)) = '00000000';

-- 1 is the least significant byte
SELECT rawtohex(UTL_RAW.CAST_FROM_BINARY_INTEGER(1, 1)) = '00000001';

SELECT rawtohex(UTL_RAW.CAST_FROM_BINARY_INTEGER(1, 2)) = '01000000';

-- -1 is the full two's-complement pattern
SELECT rawtohex(UTL_RAW.CAST_FROM_BINARY_INTEGER(-1, 1)) = 'FFFFFFFF';

SELECT rawtohex(UTL_RAW.CAST_FROM_BINARY_INTEGER(-1, 2)) = 'FFFFFFFF';

-- 305419896 = 0x12345678
SELECT rawtohex(UTL_RAW.CAST_FROM_BINARY_INTEGER(305419896, 1)) = '12345678';

SELECT rawtohex(UTL_RAW.CAST_FROM_BINARY_INTEGER(305419896, 2)) = '78563412';

-- CAST_TO_BINARY_INTEGER reads the bytes back
SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('00000001'), 1) = 1;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('01000000'), 2) = 1;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('FFFFFFFF'), 1) = -1;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('FFFFFFFF'), 2) = -1;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('12345678'), 1) = 305419896;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('78563412'), 2) = 305419896;

-- Round-trips for zero, a positive and a negative value under both orders
SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.CAST_FROM_BINARY_INTEGER(0, 1), 1) = 0;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.CAST_FROM_BINARY_INTEGER(0, 2), 2) = 0;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.CAST_FROM_BINARY_INTEGER(123456789, 1), 1) = 123456789;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.CAST_FROM_BINARY_INTEGER(123456789, 2), 2) = 123456789;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.CAST_FROM_BINARY_INTEGER(-123456789, 1), 1) = -123456789;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.CAST_FROM_BINARY_INTEGER(-123456789, 2), 2) = -123456789;

-- NULL propagation (STRICT)
SELECT UTL_RAW.CAST_FROM_BINARY_INTEGER(NULL, 1) IS NULL;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(NULL, 1) IS NULL;

-- The default endianness is big_endian, as in Oracle
SELECT rawtohex(UTL_RAW.CAST_FROM_BINARY_INTEGER(258)) = '00000102';

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('00000102')) = 258;

-- A RAW shorter than four bytes is read as the bytes it is given: they stay
-- the low-order bytes and the missing high-order bytes are zero
SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('0102')) = 258;

SELECT UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('FF')) = 255;

-- A RAW longer than four bytes is rejected
DO $$
BEGIN
    PERFORM UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('0102030405'), 1);
    RAISE NOTICE 'CAST_TO_BINARY_INTEGER long RAW: no error';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'CAST_TO_BINARY_INTEGER long RAW: error as expected';
END;
$$;

-- ============================================================
-- Direct sys.utl_raw_* entry points
-- ============================================================

SELECT sys.utl_raw_xrange(hextoraw('20'), hextoraw('2F'))
       = hextoraw('202122232425262728292A2B2C2D2E2F');

-- The direct entry point applies the same NULL and omitted-argument defaults
SELECT sys.utl_raw_xrange(NULL, hextoraw('02')) = hextoraw('000102');

SELECT sys.utl_raw_xrange(hextoraw('FD'), NULL) = hextoraw('FDFEFF');

SELECT pg_catalog.octet_length(sys.utl_raw_xrange(NULL, NULL)) = 256;

SELECT sys.utl_raw_xrange() = sys.utl_raw_xrange(NULL, NULL);

SELECT sys.utl_raw_xrange(hextoraw('FE'), hextoraw('01')) = hextoraw('FEFF0001');

SELECT sys.utl_raw_cast_to_varchar2(hextoraw('68656C6C6F')) = 'hello';

SELECT rawtohex(sys.utl_raw_cast_from_binary_integer(1, 1)) = '00000001';

SELECT rawtohex(sys.utl_raw_cast_from_binary_integer(1, 2)) = '01000000';

SELECT sys.utl_raw_cast_to_binary_integer(hextoraw('12345678'), 1) = 305419896;

SELECT sys.utl_raw_cast_to_binary_integer(hextoraw('78563412'), 2) = 305419896;

-- ============================================================
-- PL/iSQL interface; the endianness constants are only visible
-- inside a PL/iSQL block, not from top-level SQL.
-- ============================================================

DO $$
DECLARE
    n INTEGER;
BEGIN
    RAISE NOTICE 'big_endian=%, little_endian=%, machine_endian=%',
        UTL_RAW.big_endian, UTL_RAW.little_endian, UTL_RAW.machine_endian;
    IF UTL_RAW.CAST_FROM_BINARY_INTEGER(305419896)
       = UTL_RAW.CAST_FROM_BINARY_INTEGER(305419896, UTL_RAW.big_endian) THEN
        RAISE NOTICE 'default endian is big_endian';
    ELSE
        RAISE NOTICE 'default endian is not big_endian';
    END IF;
    IF UTL_RAW.CAST_FROM_BINARY_INTEGER(1, UTL_RAW.big_endian)
       = hextoraw('00000001') THEN
        RAISE NOTICE 'big_endian bytes OK';
    ELSE
        RAISE NOTICE 'big_endian bytes FAILED';
    END IF;
    IF UTL_RAW.CAST_FROM_BINARY_INTEGER(1, UTL_RAW.little_endian)
       = hextoraw('01000000') THEN
        RAISE NOTICE 'little_endian bytes OK';
    ELSE
        RAISE NOTICE 'little_endian bytes FAILED';
    END IF;
    n := UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('12345678'), UTL_RAW.big_endian);
    RAISE NOTICE 'big-endian 12345678 = %', n;
    n := UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('78563412'), UTL_RAW.little_endian);
    RAISE NOTICE 'little-endian 78563412 = %', n;
    n := UTL_RAW.CAST_TO_BINARY_INTEGER(hextoraw('FFFFFFFF'), UTL_RAW.big_endian);
    RAISE NOTICE 'big-endian FFFFFFFF = %', n;
    IF UTL_RAW.XRANGE(hextoraw('41'), hextoraw('43')) = hextoraw('414243') THEN
        RAISE NOTICE 'XRANGE bytes OK';
    ELSE
        RAISE NOTICE 'XRANGE bytes FAILED';
    END IF;
    IF UTL_RAW.XRANGE(hextoraw('FE'), hextoraw('01')) = hextoraw('FEFF0001') THEN
        RAISE NOTICE 'XRANGE wrap-around OK';
    ELSE
        RAISE NOTICE 'XRANGE wrap-around FAILED';
    END IF;
    IF UTL_RAW.CAST_TO_VARCHAR2(UTL_RAW.CAST_TO_RAW('raw')) = 'raw' THEN
        RAISE NOTICE 'CAST_TO_VARCHAR2 round-trip OK';
    ELSE
        RAISE NOTICE 'CAST_TO_VARCHAR2 round-trip FAILED';
    END IF;
END;
$$;
