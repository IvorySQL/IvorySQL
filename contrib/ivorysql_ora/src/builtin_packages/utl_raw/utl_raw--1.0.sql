/***************************************************************
 *
 * UTL_RAW Package
 *
 * Oracle-compatible binary data manipulation functions.
 *
 * The representation-conversion routines that cannot be written as a plain
 * type cast live in C (utl_raw.c) and are registered below as sys.utl_raw_*
 * functions; the PL/iSQL package wraps them, exactly like UTL_ENCODE and
 * UTL_MATCH.  Oracle's RAW type maps to bytea in IvorySQL.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw--1.0.sql
 *
 ***************************************************************/

/*
 * Register the C implementations in the sys schema.
 * Input/output use bytea (RAW maps to bytea in IvorySQL).
 * STRICT: a NULL argument yields NULL.
 *
 * XRANGE is deliberately not STRICT: a NULL bound means the Oracle default
 * (X'00' for start_byte, X'FF' for end_byte), so the defaults are declared
 * here and the NULLs are handled inside the C function.
 */
CREATE FUNCTION sys.utl_raw_xrange(start_byte bytea DEFAULT NULL,
                                   end_byte bytea DEFAULT NULL)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_xrange'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_raw_cast_to_varchar2(bytea)
RETURNS text
AS 'MODULE_PATHNAME', 'utl_raw_cast_to_varchar2'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_cast_from_binary_integer(integer, integer)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_cast_from_binary_integer'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_cast_to_binary_integer(bytea, integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'utl_raw_cast_to_binary_integer'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

-- UTL_RAW Package Header
CREATE OR REPLACE PACKAGE UTL_RAW IS
    -- Endianness constants consumed by CAST_FROM/TO_BINARY_INTEGER.
    big_endian      CONSTANT INTEGER := 1;
    little_endian   CONSTANT INTEGER := 2;
    machine_endian  CONSTANT INTEGER := 3;

    -- CAST_TO_RAW: the bytes of c in the database character set
    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN RAW;

    -- XRANGE: the inclusive range of one-byte values start_byte..end_byte.
    -- A NULL bound means the Oracle default (X'00' / X'FF'), and the range
    -- wraps through X'FF' to X'00' when start_byte is greater than end_byte.
    FUNCTION XRANGE(start_byte IN RAW DEFAULT NULL,
                    end_byte IN RAW DEFAULT NULL) RETURN RAW;

    -- CAST_TO_VARCHAR2: reinterpret the bytes of r as database-encoding text
    FUNCTION CAST_TO_VARCHAR2(r IN RAW) RETURN VARCHAR2;

    -- CAST_FROM_BINARY_INTEGER: the 4-byte RAW holding the 32-bit integer bin.
    -- Oracle defaults endian to big_endian.  The default here is NULL and the
    -- body substitutes big_endian: a PL/iSQL parameter default is expanded as
    -- a SQL expression, where the package constant is not in scope, so the
    -- constant is applied inside the body instead.
    FUNCTION CAST_FROM_BINARY_INTEGER(bin IN INTEGER,
                                      endian IN INTEGER DEFAULT NULL) RETURN RAW;

    -- CAST_TO_BINARY_INTEGER: the 32-bit integer stored in the RAW r; as in
    -- Oracle, r may be 1 to 4 bytes, and a shorter RAW is zero-extended.
    FUNCTION CAST_TO_BINARY_INTEGER(r IN RAW,
                                    endian IN INTEGER DEFAULT NULL) RETURN INTEGER;
END;

-- UTL_RAW Package Body
CREATE OR REPLACE PACKAGE BODY UTL_RAW IS
    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN RAW IS
    BEGIN
        RETURN pg_catalog.convert_to(c::text, pg_catalog.getdatabaseencoding());
    END;

    FUNCTION XRANGE(start_byte IN RAW DEFAULT NULL,
                    end_byte IN RAW DEFAULT NULL) RETURN RAW IS
    BEGIN
        RETURN sys.utl_raw_xrange(start_byte, end_byte);
    END;

    FUNCTION CAST_TO_VARCHAR2(r IN RAW) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_raw_cast_to_varchar2(r);
    END;

    FUNCTION CAST_FROM_BINARY_INTEGER(bin IN INTEGER,
                                      endian IN INTEGER DEFAULT NULL) RETURN RAW IS
        use_endian INTEGER;
    BEGIN
        IF endian IS NULL THEN
            use_endian := big_endian;
        ELSE
            use_endian := endian;
        END IF;
        RETURN sys.utl_raw_cast_from_binary_integer(bin, use_endian);
    END;

    FUNCTION CAST_TO_BINARY_INTEGER(r IN RAW,
                                    endian IN INTEGER DEFAULT NULL) RETURN INTEGER IS
        use_endian INTEGER;
    BEGIN
        IF endian IS NULL THEN
            use_endian := big_endian;
        ELSE
            use_endian := endian;
        END IF;
        RETURN sys.utl_raw_cast_to_binary_integer(r, use_endian);
    END;
END;
