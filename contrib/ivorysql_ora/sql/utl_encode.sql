--
-- utl_encode.sql
--
-- Tests for UTL_ENCODE package (BASE64_ENCODE and BASE64_DECODE functions)
--

-- ============================================================
-- Tests for UTL_ENCODE.BASE64_ENCODE
-- ============================================================

-- NULL input returns NULL (STRICT modifier)
SELECT utl_encode.base64_encode(NULL) IS NULL;

-- Basic encoding: hextoraw('48656C6C6F') = 'Hello' bytes
-- Expected: 'SGVsbG8=\n' = hextoraw('534756736247383D0A')
SELECT rawtohex(utl_encode.base64_encode(hextoraw('48656C6C6F'))) = '534756736247383D0A';

-- Round-trip at line-break boundary: 48 bytes (exactly 1 line of 64 base64 chars)
-- hextoraw(rpad('0',96,'0')) produces 48 zero bytes
SELECT utl_encode.base64_decode(utl_encode.base64_encode(
    hextoraw(rpad('0', 96, '0'))
)) = hextoraw(rpad('0', 96, '0'));

-- Round-trip at line-break boundary: 49 bytes (spans 2 lines)
SELECT utl_encode.base64_decode(utl_encode.base64_encode(
    hextoraw(rpad('0', 98, '0'))
)) = hextoraw(rpad('0', 98, '0'));

-- PL/iSQL package interface test for encode
DECLARE
    v_src     RAW(100) := hextoraw('48656C6C6F');
    v_encoded RAW(200);
    line      TEXT;
    status    INTEGER;
BEGIN
    v_encoded := utl_encode.base64_encode(v_src);
    dbms_output.enable();
    dbms_output.put_line('encoded=' || rawtohex(v_encoded));
    dbms_output.get_line(line, status);
    RAISE NOTICE '%', line;
END;
/

-- ============================================================
-- Tests for UTL_ENCODE.BASE64_DECODE
-- ============================================================

-- NULL input returns NULL (STRICT modifier)
SELECT utl_encode.base64_decode(NULL) IS NULL;

-- Decode known base64 string: 'SGVsbG8=\n' -> 'Hello' bytes
-- hextoraw('534756736247383D0A') = 'SGVsbG8=\n', hextoraw('48656C6C6F') = 'Hello'
SELECT rawtohex(utl_encode.base64_decode(hextoraw('534756736247383D0A'))) = '48656C6C6F';

-- Round-trip: base64_decode(base64_encode(x)) = x for 'Hello'
SELECT utl_encode.base64_decode(utl_encode.base64_encode(
    hextoraw('48656C6C6F')
)) = hextoraw('48656C6C6F');

-- Round-trip: large input (200 bytes, multiple lines of encoded output)
-- hextoraw(rpad('AB',400,'AB')) produces 200 bytes of 0xAB
SELECT utl_encode.base64_decode(utl_encode.base64_encode(
    hextoraw(rpad('AB', 400, 'AB'))
)) = hextoraw(rpad('AB', 400, 'AB'));

-- Whitespace-only input returns empty RAW
-- hextoraw('0A0D200A') = LF CR SP LF; rawtohex of empty RAW returns NULL in Oracle mode
SELECT rawtohex(utl_encode.base64_decode(hextoraw('0A0D200A'))) IS NULL;

-- Invalid base64 characters raise ERROR
-- hextoraw('5A5A5A21') = 'ZZZ!' where '!' is not a valid base64 character
SELECT utl_encode.base64_decode(hextoraw('5A5A5A21'));

-- PL/iSQL package interface test for decode
DECLARE
    v_src     RAW(100) := hextoraw('48656C6C6F');
    v_encoded RAW(200);
    v_decoded RAW(200);
    line      TEXT;
    status    INTEGER;
BEGIN
    v_encoded := utl_encode.base64_encode(v_src);
    v_decoded := utl_encode.base64_decode(v_encoded);
    dbms_output.enable();
    dbms_output.put_line('round_trip_match=' || CASE WHEN v_decoded = v_src THEN 't' ELSE 'f' END);
    dbms_output.get_line(line, status);
    RAISE NOTICE '%', line;
END;
/
