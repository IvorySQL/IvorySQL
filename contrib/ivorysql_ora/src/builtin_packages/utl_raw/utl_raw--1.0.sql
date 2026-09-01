/***************************************************************
 *
 * UTL_RAW Package
 *
 * Oracle-compatible binary data manipulation functions.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw--1.0.sql
 *
 ***************************************************************/

-- C function wrappers
CREATE FUNCTION sys.ora_utl_raw_concat(bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_concat'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_concat(bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_concat'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_concat(bytea, bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_concat'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_concat(bytea, bytea, bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_concat'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_concat(bytea, bytea, bytea, bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_concat'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_concat(bytea, bytea, bytea, bytea, bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_concat'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_concat(bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_concat'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_concat(bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_concat'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_concat(bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_concat'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_concat(bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_concat'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_concat(bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_concat'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_length(bytea)
RETURNS numeric
AS 'MODULE_PATHNAME','ora_utl_raw_length'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_reverse(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_reverse'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_copies(bytea, integer)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_copies'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_xrange(integer, integer)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_xrange'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_substr(bytea, integer)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_substr'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_substr(bytea, integer, integer)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_substr'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_bit_and(bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_bit_and'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_bit_or(bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_bit_or'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_bit_xor(bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_bit_xor'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_bit_complement(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_bit_complement'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_compare(bytea, bytea, bytea)
RETURNS numeric
AS 'MODULE_PATHNAME','ora_utl_raw_compare'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_translate(bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_raw_translate'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_cast_to_varchar2(bytea)
RETURNS text
AS 'MODULE_PATHNAME','ora_utl_raw_cast_to_varchar2'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_convert(bytea, text, text)
RETURNS bytea
AS $$SELECT pg_catalog.convert($1, $3, $2)$$
LANGUAGE SQL IMMUTABLE STRICT PARALLEL SAFE;

-- UTL_RAW Package Header
CREATE OR REPLACE PACKAGE UTL_RAW IS
    -- Endianness constants (used by future CAST_FROM/TO_BINARY_* functions)
    big_endian      CONSTANT INTEGER := 1;
    little_endian   CONSTANT INTEGER := 2;
    machine_endian  CONSTANT INTEGER := 3;

    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN RAW;

    FUNCTION LENGTH(r IN RAW) RETURN NUMBER;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW) RETURN RAW;
    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW) RETURN RAW;
    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW) RETURN RAW;
    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW) RETURN RAW;
    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW) RETURN RAW;
    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW) RETURN RAW;
    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW, r8 IN RAW) RETURN RAW;
    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW, r8 IN RAW, r9 IN RAW) RETURN RAW;
    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW, r8 IN RAW, r9 IN RAW, r10 IN RAW) RETURN RAW;
    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW, r8 IN RAW, r9 IN RAW, r10 IN RAW, r11 IN RAW) RETURN RAW;
    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW, r8 IN RAW, r9 IN RAW, r10 IN RAW, r11 IN RAW, r12 IN RAW) RETURN RAW;

    FUNCTION REVERSE(r IN RAW) RETURN RAW;

    FUNCTION COPIES(r IN RAW, n IN NUMBER) RETURN RAW;

    FUNCTION XRANGE(start IN INTEGER DEFAULT 0, endp IN INTEGER DEFAULT 255) RETURN RAW;

    FUNCTION SUBSTR(r IN RAW, pos IN NUMBER) RETURN RAW;
    FUNCTION SUBSTR(r IN RAW, pos IN NUMBER, len IN NUMBER) RETURN RAW;

    FUNCTION BIT_AND(r1 IN RAW, r2 IN RAW) RETURN RAW;
    FUNCTION BIT_OR(r1 IN RAW, r2 IN RAW) RETURN RAW;
    FUNCTION BIT_XOR(r1 IN RAW, r2 IN RAW) RETURN RAW;
    FUNCTION BIT_COMPLEMENT(r IN RAW) RETURN RAW;

    FUNCTION COMPARE(r1 IN RAW, r2 IN RAW, pad IN RAW DEFAULT NULL) RETURN NUMBER;

    FUNCTION TRANSLATE(r IN RAW, from_raw IN RAW, to_raw IN RAW) RETURN RAW;

    FUNCTION CAST_TO_VARCHAR2(r IN RAW) RETURN VARCHAR2;

    FUNCTION CONVERT(r IN RAW, to_charset IN VARCHAR2, from_charset IN VARCHAR2) RETURN RAW;
END;

-- UTL_RAW Package Body
CREATE OR REPLACE PACKAGE BODY UTL_RAW IS
    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN RAW IS
    BEGIN
        RETURN pg_catalog.convert_to(c::text, pg_catalog.getdatabaseencoding());
    END;

    FUNCTION LENGTH(r IN RAW) RETURN NUMBER IS
    BEGIN
        RETURN sys.ora_utl_raw_length(r);
    END;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2);
    END;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2, r3);
    END;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2, r3, r4);
    END;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2, r3, r4, r5);
    END;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2, r3, r4, r5, r6);
    END;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2, r3, r4, r5, r6, r7);
    END;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW, r8 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2, r3, r4, r5, r6, r7, r8);
    END;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW, r8 IN RAW, r9 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2, r3, r4, r5, r6, r7, r8, r9);
    END;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW, r8 IN RAW, r9 IN RAW, r10 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2, r3, r4, r5, r6, r7, r8, r9, r10);
    END;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW, r8 IN RAW, r9 IN RAW, r10 IN RAW, r11 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11);
    END;

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW, r3 IN RAW, r4 IN RAW, r5 IN RAW, r6 IN RAW, r7 IN RAW, r8 IN RAW, r9 IN RAW, r10 IN RAW, r11 IN RAW, r12 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12);
    END;

    FUNCTION REVERSE(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_reverse(r);
    END;

    FUNCTION COPIES(r IN RAW, n IN NUMBER) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_copies(r, n::integer);
    END;

    FUNCTION XRANGE(start IN INTEGER DEFAULT 0, endp IN INTEGER DEFAULT 255) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_xrange(start, endp);
    END;

    FUNCTION SUBSTR(r IN RAW, pos IN NUMBER) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_substr(r, pos::integer);
    END;

    FUNCTION SUBSTR(r IN RAW, pos IN NUMBER, len IN NUMBER) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_substr(r, pos::integer, len::integer);
    END;

    FUNCTION BIT_AND(r1 IN RAW, r2 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_bit_and(r1, r2);
    END;

    FUNCTION BIT_OR(r1 IN RAW, r2 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_bit_or(r1, r2);
    END;

    FUNCTION BIT_XOR(r1 IN RAW, r2 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_bit_xor(r1, r2);
    END;

    FUNCTION BIT_COMPLEMENT(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_bit_complement(r);
    END;

    FUNCTION COMPARE(r1 IN RAW, r2 IN RAW, pad IN RAW DEFAULT NULL) RETURN NUMBER IS
    BEGIN
        RETURN sys.ora_utl_raw_compare(r1, r2, pad);
    END;

    FUNCTION TRANSLATE(r IN RAW, from_raw IN RAW, to_raw IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_translate(r, from_raw, to_raw);
    END;

    FUNCTION CAST_TO_VARCHAR2(r IN RAW) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.ora_utl_raw_cast_to_varchar2(r);
    END;

    FUNCTION CONVERT(r IN RAW, to_charset IN VARCHAR2, from_charset IN VARCHAR2) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_convert(r, to_charset, from_charset);
    END;
END;
