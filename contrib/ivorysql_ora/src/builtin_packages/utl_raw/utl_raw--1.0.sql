/***************************************************************
 *
 * UTL_RAW Package
 *
 * Oracle-compatible binary data manipulation functions.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw--1.0.sql
 *
 ***************************************************************/

-- UTL_RAW Package Header
CREATE OR REPLACE PACKAGE UTL_RAW IS
    -- Endianness constants (used by future CAST_FROM/TO_BINARY_* functions)
    big_endian      CONSTANT INTEGER := 1;
    little_endian   CONSTANT INTEGER := 2;
    machine_endian  CONSTANT INTEGER := 3;

    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN RAW;
    FUNCTION CAST_TO_VARCHAR2(r IN RAW) RETURN VARCHAR2;
    FUNCTION LENGTH(r IN RAW) RETURN NUMBER;
    FUNCTION SUBSTR(r IN RAW, pos IN NUMBER, len IN NUMBER DEFAULT NULL) RETURN RAW;
    FUNCTION CONCAT(r1 IN RAW DEFAULT NULL, r2 IN RAW DEFAULT NULL, r3 IN RAW DEFAULT NULL, r4 IN RAW DEFAULT NULL,
                    r5 IN RAW DEFAULT NULL, r6 IN RAW DEFAULT NULL, r7 IN RAW DEFAULT NULL, r8 IN RAW DEFAULT NULL,
                    r9 IN RAW DEFAULT NULL, r10 IN RAW DEFAULT NULL, r11 IN RAW DEFAULT NULL, r12 IN RAW DEFAULT NULL) RETURN RAW;
    FUNCTION XRANGE(start_byte IN RAW DEFAULT NULL, end_byte IN RAW DEFAULT NULL) RETURN RAW;
    FUNCTION COPIES(r IN RAW, n IN NUMBER) RETURN RAW;
    FUNCTION REVERSE(r IN RAW) RETURN RAW;
    FUNCTION BIT_AND(r1 IN RAW, r2 IN RAW) RETURN RAW;
    FUNCTION BIT_OR(r1 IN RAW, r2 IN RAW) RETURN RAW;
    FUNCTION BIT_XOR(r1 IN RAW, r2 IN RAW) RETURN RAW;
    FUNCTION BIT_COMPLEMENT(r IN RAW) RETURN RAW;
    FUNCTION COMPARE(r1 IN RAW, r2 IN RAW, pad IN RAW DEFAULT NULL) RETURN NUMBER;
    FUNCTION TRANSLATE(r IN RAW, from_set IN RAW, to_set IN RAW) RETURN RAW;
    FUNCTION OVERLAY(overlay_str IN RAW, target IN RAW, pos IN NUMBER DEFAULT 1, len IN NUMBER DEFAULT NULL, pad IN RAW DEFAULT NULL) RETURN RAW;
    FUNCTION CAST_FROM_BINARY_INTEGER(n IN NUMBER, endianness IN NUMBER) RETURN RAW;
    FUNCTION CAST_TO_BINARY_INTEGER(r IN RAW, endianness IN NUMBER) RETURN NUMBER;
    FUNCTION CAST_FROM_BINARY_DOUBLE(n IN BINARY_DOUBLE, endianness IN NUMBER) RETURN RAW;
    FUNCTION CAST_TO_BINARY_DOUBLE(r IN RAW, endianness IN NUMBER) RETURN BINARY_DOUBLE;
    FUNCTION CAST_FROM_BINARY_FLOAT(n IN BINARY_FLOAT, endianness IN NUMBER) RETURN RAW;
    FUNCTION CAST_TO_BINARY_FLOAT(r IN RAW, endianness IN NUMBER) RETURN BINARY_FLOAT;
    FUNCTION TRANSLITERATE(r IN RAW, to_set IN RAW DEFAULT NULL, from_set IN RAW DEFAULT NULL, pad IN RAW DEFAULT NULL) RETURN RAW;
END;

-- C implementations registered as sys-level functions
CREATE FUNCTION sys.ora_utl_raw_cast_to_varchar2(r bytea)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_utl_raw_cast_to_varchar2'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_length(r bytea)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_utl_raw_length'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_substr(r bytea, pos integer, len integer DEFAULT NULL)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_substr'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sys.ora_utl_raw_concat(r1 bytea DEFAULT NULL, r2 bytea DEFAULT NULL, r3 bytea DEFAULT NULL, r4 bytea DEFAULT NULL, r5 bytea DEFAULT NULL, r6 bytea DEFAULT NULL, r7 bytea DEFAULT NULL, r8 bytea DEFAULT NULL, r9 bytea DEFAULT NULL, r10 bytea DEFAULT NULL, r11 bytea DEFAULT NULL, r12 bytea DEFAULT NULL)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_concat'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sys.ora_utl_raw_copies(r bytea, n integer)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_copies'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_reverse(r bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_reverse'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_bit_and(r1 bytea, r2 bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_bit_and'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_bit_or(r1 bytea, r2 bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_bit_or'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_bit_xor(r1 bytea, r2 bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_bit_xor'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_bit_complement(r bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_bit_complement'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_compare(r1 bytea DEFAULT NULL, r2 bytea DEFAULT NULL, pad bytea DEFAULT NULL)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_utl_raw_compare'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sys.ora_utl_raw_translate(r bytea, from_set bytea, to_set bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_translate'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sys.ora_utl_raw_overlay(overlay_str bytea, target bytea, pos integer DEFAULT 1, len integer DEFAULT NULL, pad bytea DEFAULT NULL)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_overlay'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sys.ora_utl_raw_cast_from_binary_integer(n integer, endianness integer)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_cast_from_binary_integer'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_cast_to_binary_integer(r bytea, endianness integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_utl_raw_cast_to_binary_integer'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_transliterate(r bytea, to_set bytea DEFAULT NULL, from_set bytea DEFAULT NULL, pad bytea DEFAULT NULL)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_transliterate'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sys.ora_utl_raw_cast_from_binary_double(n double precision, endianness integer)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_cast_from_binary_double'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_cast_to_binary_double(r bytea, endianness integer)
RETURNS double precision
AS 'MODULE_PATHNAME', 'ora_utl_raw_cast_to_binary_double'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_cast_from_binary_float(n real, endianness integer)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_cast_from_binary_float'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_raw_cast_to_binary_float(r bytea, endianness integer)
RETURNS real
AS 'MODULE_PATHNAME', 'ora_utl_raw_cast_to_binary_float'
LANGUAGE C IMMUTABLE STRICT;

-- UTL_RAW Package Body
CREATE OR REPLACE PACKAGE BODY UTL_RAW IS
    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN RAW IS
    BEGIN
        RETURN pg_catalog.convert_to(c::text, pg_catalog.getdatabaseencoding());
    END;

    FUNCTION CAST_TO_VARCHAR2(r IN RAW) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.ora_utl_raw_cast_to_varchar2(r);
    END;

    FUNCTION LENGTH(r IN RAW) RETURN NUMBER IS
    BEGIN
        RETURN sys.ora_utl_raw_length(r);
    END;

    FUNCTION SUBSTR(r IN RAW, pos IN NUMBER, len IN NUMBER DEFAULT NULL) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_substr(r, pos, len);
    END;

    FUNCTION CONCAT(r1 IN RAW DEFAULT NULL, r2 IN RAW DEFAULT NULL, r3 IN RAW DEFAULT NULL, r4 IN RAW DEFAULT NULL,
                    r5 IN RAW DEFAULT NULL, r6 IN RAW DEFAULT NULL, r7 IN RAW DEFAULT NULL, r8 IN RAW DEFAULT NULL,
                    r9 IN RAW DEFAULT NULL, r10 IN RAW DEFAULT NULL, r11 IN RAW DEFAULT NULL, r12 IN RAW DEFAULT NULL) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12);
    END;

    FUNCTION XRANGE(start_byte IN RAW DEFAULT NULL, end_byte IN RAW DEFAULT NULL) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_xrange(start_byte, end_byte);
    END;

    FUNCTION COPIES(r IN RAW, n IN NUMBER) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_copies(r, n);
    END;

    FUNCTION REVERSE(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_reverse(r);
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

    FUNCTION TRANSLATE(r IN RAW, from_set IN RAW, to_set IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_translate(r, from_set, to_set);
    END;

    FUNCTION OVERLAY(overlay_str IN RAW, target IN RAW, pos IN NUMBER DEFAULT 1, len IN NUMBER DEFAULT NULL, pad IN RAW DEFAULT NULL) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_overlay(overlay_str, target, pos, len, pad);
    END;

    FUNCTION CAST_FROM_BINARY_INTEGER(n IN NUMBER, endianness IN NUMBER) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_cast_from_binary_integer(n, endianness);
    END;

    FUNCTION CAST_TO_BINARY_INTEGER(r IN RAW, endianness IN NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN sys.ora_utl_raw_cast_to_binary_integer(r, endianness);
    END;

    FUNCTION CAST_FROM_BINARY_DOUBLE(n IN BINARY_DOUBLE, endianness IN NUMBER) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_cast_from_binary_double(n, endianness);
    END;

    FUNCTION CAST_TO_BINARY_DOUBLE(r IN RAW, endianness IN NUMBER) RETURN BINARY_DOUBLE IS
    BEGIN
        RETURN sys.ora_utl_raw_cast_to_binary_double(r, endianness);
    END;

    FUNCTION CAST_FROM_BINARY_FLOAT(n IN BINARY_FLOAT, endianness IN NUMBER) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_cast_from_binary_float(n, endianness);
    END;

    FUNCTION CAST_TO_BINARY_FLOAT(r IN RAW, endianness IN NUMBER) RETURN BINARY_FLOAT IS
    BEGIN
        RETURN sys.ora_utl_raw_cast_to_binary_float(r, endianness);
    END;

    FUNCTION TRANSLITERATE(r IN RAW, to_set IN RAW DEFAULT NULL, from_set IN RAW DEFAULT NULL, pad IN RAW DEFAULT NULL) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_transliterate(r, to_set, from_set, pad);
    END;
END;
