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
    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW) RETURN RAW;
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

CREATE FUNCTION sys.ora_utl_raw_concat(r1 bytea, r2 bytea)
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

CREATE FUNCTION sys.ora_utl_raw_compare(r1 bytea, r2 bytea, pad bytea DEFAULT NULL)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_utl_raw_compare'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sys.ora_utl_raw_translate(r bytea, from_set bytea, to_set bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_translate'
LANGUAGE C IMMUTABLE STRICT;

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

    FUNCTION CONCAT(r1 IN RAW, r2 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_concat(r1, r2);
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
END;
