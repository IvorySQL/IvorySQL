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

-- =============================================================================
-- New UTL_RAW functions (LENGTH, CONCAT, REVERSE, COPIES, XRANGE, SUBSTR,
-- BIT_*, COMPARE, TRANSLATE, CAST_TO_VARCHAR2, CONVERT)
-- =============================================================================

-- LENGTH: byte length (Oracle returns NUMBER)
SELECT UTL_RAW.LENGTH(UTL_RAW.CAST_TO_RAW('hello')) AS len;
SELECT UTL_RAW.LENGTH(UTL_RAW.CAST_TO_RAW('')) AS len_empty;

-- CONCAT: 2 arguments, 4 arguments and the maximum of 12 arguments
SELECT UTL_RAW.CONCAT(UTL_RAW.CAST_TO_RAW('AB'), UTL_RAW.CAST_TO_RAW('CD')) AS cat2;
SELECT UTL_RAW.CONCAT(UTL_RAW.CAST_TO_RAW('A'), UTL_RAW.CAST_TO_RAW('B'),
                      UTL_RAW.CAST_TO_RAW('C'), UTL_RAW.CAST_TO_RAW('D')) AS cat4;
SELECT UTL_RAW.CONCAT(UTL_RAW.CAST_TO_RAW('A'), UTL_RAW.CAST_TO_RAW('B'),
                      UTL_RAW.CAST_TO_RAW('C'), UTL_RAW.CAST_TO_RAW('D'),
                      UTL_RAW.CAST_TO_RAW('E'), UTL_RAW.CAST_TO_RAW('F'),
                      UTL_RAW.CAST_TO_RAW('G'), UTL_RAW.CAST_TO_RAW('H'),
                      UTL_RAW.CAST_TO_RAW('I'), UTL_RAW.CAST_TO_RAW('J'),
                      UTL_RAW.CAST_TO_RAW('K'), UTL_RAW.CAST_TO_RAW('L')) AS cat12;

-- REVERSE: byte order reversed
SELECT UTL_RAW.REVERSE(UTL_RAW.CAST_TO_RAW('ABC')) AS rev;

-- COPIES: repeated n times (Oracle requires n >= 1)
SELECT UTL_RAW.COPIES(UTL_RAW.CAST_TO_RAW('AB'), 3) AS copies;

-- XRANGE: inclusive byte range; default bounds are 0 and 255
SELECT UTL_RAW.XRANGE(65, 67) AS xr;
SELECT UTL_RAW.XRANGE(67, 65) IS NULL AS xr_inverted;
SELECT UTL_RAW.LENGTH(UTL_RAW.XRANGE()) AS xr_defaults;
SELECT UTL_RAW.LENGTH(UTL_RAW.XRANGE(65)) AS xr_one_bound;

-- SUBSTR: Oracle position semantics (1-based, negative counts from the
-- end; pos 0, an out-of-range pos and a bad len raise an error)
SELECT UTL_RAW.SUBSTR(UTL_RAW.CAST_TO_RAW('ABCDE'), 2, 3) AS sub;
SELECT UTL_RAW.SUBSTR(UTL_RAW.CAST_TO_RAW('ABCDE'), -2) AS sub_from_end;
SELECT UTL_RAW.SUBSTR(UTL_RAW.CAST_TO_RAW('ABCDE'), 3) AS sub_rest;

-- BIT_AND / BIT_OR / BIT_XOR / BIT_COMPLEMENT
-- (HEXTORAW makes sure the inputs really are the hex byte values)
SELECT UTL_RAW.BIT_AND(HEXTORAW('F0'), HEXTORAW('0F')) AS band;
SELECT UTL_RAW.BIT_OR(HEXTORAW('F0'), HEXTORAW('0F')) AS bor;
SELECT UTL_RAW.BIT_XOR(HEXTORAW('FF'), HEXTORAW('0F')) AS bxor;
SELECT UTL_RAW.BIT_COMPLEMENT(HEXTORAW('0F')) AS bcomp;

-- BIT_* with operands of different lengths: the operation covers the
-- shorter operand and the longer operand's tail is appended (Oracle)
SELECT UTL_RAW.BIT_AND(HEXTORAW('F0FF'), HEXTORAW('0F')) AS band_uneq;
SELECT UTL_RAW.BIT_OR(HEXTORAW('0F'), HEXTORAW('F0FF')) AS bor_uneq;

-- COMPARE: 0 when equal (a NULL pad defaults to a single 0x00 byte that
-- pads the shorter value), otherwise the 1-based position of the first
-- mismatched byte (Oracle)
SELECT UTL_RAW.COMPARE(UTL_RAW.CAST_TO_RAW('AB'), UTL_RAW.CAST_TO_RAW('AB')) AS cmp_eq;
SELECT UTL_RAW.COMPARE(UTL_RAW.CAST_TO_RAW('AA'), UTL_RAW.CAST_TO_RAW('AB')) AS cmp_pos2;
SELECT UTL_RAW.COMPARE(UTL_RAW.CAST_TO_RAW('AB')
                       || HEXTORAW('00'), UTL_RAW.CAST_TO_RAW('AB')) AS cmp_nulpad_eq;
SELECT UTL_RAW.COMPARE(UTL_RAW.CAST_TO_RAW('AB'), UTL_RAW.CAST_TO_RAW('AB')
                       || HEXTORAW('00')) AS cmp_nulpad_eq2;
SELECT UTL_RAW.COMPARE(UTL_RAW.CAST_TO_RAW('AB')
                       || HEXTORAW('01'), UTL_RAW.CAST_TO_RAW('AB')) AS cmp_nulpad_pos3;
SELECT UTL_RAW.COMPARE(UTL_RAW.CAST_TO_RAW('AB'), UTL_RAW.CAST_TO_RAW('AB')
                       || HEXTORAW('01')) AS cmp_nulpad_pos3b;
SELECT UTL_RAW.COMPARE(UTL_RAW.CAST_TO_RAW('AB'), UTL_RAW.CAST_TO_RAW('ABC'),
                       HEXTORAW('00')) AS cmp_pad_pos3;
SELECT UTL_RAW.COMPARE(UTL_RAW.CAST_TO_RAW('ABC'), UTL_RAW.CAST_TO_RAW('AB'),
                       HEXTORAW('00')) AS cmp_pad_pos3b;

-- TRANSLATE: byte mapping with deletion for unmatched 'from' bytes;
-- repeated bytes in from_set are ignored after the first occurrence
SELECT UTL_RAW.TRANSLATE(UTL_RAW.CAST_TO_RAW('ABCA'), UTL_RAW.CAST_TO_RAW('A'),
                         UTL_RAW.CAST_TO_RAW('X')) AS tr;
SELECT UTL_RAW.TRANSLATE(UTL_RAW.CAST_TO_RAW('ABCA'), UTL_RAW.CAST_TO_RAW('AB'),
                         UTL_RAW.CAST_TO_RAW('X')) AS tr_del;
SELECT UTL_RAW.TRANSLATE(UTL_RAW.CAST_TO_RAW('ABCA'), UTL_RAW.CAST_TO_RAW('ABA'),
                         UTL_RAW.CAST_TO_RAW('XY')) AS tr_dup;

-- CAST_TO_VARCHAR2: interpret RAW bytes as database-encoding text
SELECT UTL_RAW.CAST_TO_VARCHAR2(UTL_RAW.CAST_TO_RAW('hello')) AS c2v;

-- CONVERT: charset conversion (Oracle arg order: r, to_charset, from_charset)
SELECT UTL_RAW.CONVERT(UTL_RAW.CAST_TO_RAW('hello'), 'UTF8', 'UTF8') AS convert;
SELECT UTL_RAW.CONVERT(HEXTORAW('C3A9'), 'LATIN1', 'UTF8') AS convert_latin1;

-- NULL handling
SELECT UTL_RAW.LENGTH(NULL) IS NULL AS len_null;
SELECT UTL_RAW.REVERSE(NULL) IS NULL AS rev_null;
SELECT UTL_RAW.CONCAT(UTL_RAW.CAST_TO_RAW('AB'), NULL) IS NULL AS cat_null;
SELECT UTL_RAW.SUBSTR(NULL, 1) IS NULL AS sub_null;
SELECT UTL_RAW.BIT_AND(NULL, NULL) IS NULL AS band_null;
SELECT UTL_RAW.COMPARE(NULL, NULL) AS cmp_null;
SELECT UTL_RAW.TRANSLATE(NULL, NULL, NULL) IS NULL AS tr_null;
SELECT UTL_RAW.CAST_TO_VARCHAR2(NULL) IS NULL AS c2v_null;

-- Error cases (Oracle raises VALUE_ERROR / invalid parameter): COPIES with
-- n < 1 or a NULL/empty r, SUBSTR with pos = 0, an out-of-range pos or a
-- bad len, COMPARE with a multi-byte pad, XRANGE with out-of-range bounds,
-- and CAST_TO_VARCHAR2 with bytes invalid in the database encoding
\set VERBOSITY terse
SELECT UTL_RAW.COPIES(UTL_RAW.CAST_TO_RAW('AB'), 0) AS copies_zero;
SELECT UTL_RAW.COPIES(UTL_RAW.CAST_TO_RAW('AB'), -1) AS copies_neg;
SELECT UTL_RAW.COPIES(NULL, 3) AS copies_null;
SELECT UTL_RAW.COPIES(UTL_RAW.CAST_TO_RAW(''), 3) AS copies_empty;
SELECT UTL_RAW.SUBSTR(UTL_RAW.CAST_TO_RAW('ABCDE'), 0) AS sub_zero;
SELECT UTL_RAW.SUBSTR(UTL_RAW.CAST_TO_RAW('ABCDE'), 10) AS sub_beyond;
SELECT UTL_RAW.SUBSTR(UTL_RAW.CAST_TO_RAW('ABCDE'), 2, 0) AS sub_len0;
SELECT UTL_RAW.SUBSTR(UTL_RAW.CAST_TO_RAW('ABCDE'), 2, 99) AS sub_len_beyond;
SELECT UTL_RAW.COMPARE(UTL_RAW.CAST_TO_RAW('AB'), UTL_RAW.CAST_TO_RAW('AB'),
                       HEXTORAW('0000')) AS cmp_pad_len;
SELECT UTL_RAW.XRANGE(300, 301) AS xr_range;
SELECT UTL_RAW.CAST_TO_VARCHAR2(HEXTORAW('FF')) AS c2v_bad_enc;
\set VERBOSITY default
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
