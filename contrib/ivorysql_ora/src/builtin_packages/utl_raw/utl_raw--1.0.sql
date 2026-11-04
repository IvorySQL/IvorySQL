/***************************************************************
 *
 * UTL_RAW Package
 *
 * Oracle-compatible binary data manipulation functions.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw--1.0.sql
 *
 ***************************************************************/

-- Oracle declares the source argument as BINARY_INTEGER, but IvorySQL does
-- not currently expose that PL/SQL spelling in package declarations. Using
-- INTEGER here would also reject NUMBER actual arguments before the wrapper
-- can apply Oracle-style integer coercion, because numeric -> int4 is not an
-- implicit function-call cast. Accept NUMBER at this package boundary and
-- retain the explicit int4 cast below to enforce the signed 32-bit domain.
-- PL/iSQL also does not resolve a package constant in this default-expression
-- position, so use the equivalent numeric value of BIG_ENDIAN here.
-- NULL data or endianess returns NULL before validation, as on Oracle.
CREATE FUNCTION sys.ora_utl_raw_cast_from_binary_integer(pg_catalog.int4, pg_catalog.int4)
RETURNS pg_catalog.bytea
AS 'MODULE_PATHNAME', 'ora_utl_raw_cast_from_binary_integer'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_raw_cast_to_binary_integer(pg_catalog.bytea, pg_catalog.int4)
RETURNS pg_catalog.int4
AS 'MODULE_PATHNAME', 'ora_utl_raw_cast_to_binary_integer'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- UTL_RAW Package Header
CREATE OR REPLACE PACKAGE UTL_RAW IS
    -- Endianness constants
    big_endian      CONSTANT INTEGER := 1;
    little_endian   CONSTANT INTEGER := 2;
    machine_endian  CONSTANT INTEGER := 3;

    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN RAW;

    FUNCTION CAST_FROM_BINARY_INTEGER(n IN NUMBER,
                                     endianess IN INTEGER DEFAULT 1) RETURN RAW;
    FUNCTION CAST_TO_BINARY_INTEGER(r IN RAW,
                                   endianess IN INTEGER DEFAULT 1) RETURN INTEGER;
END;

-- UTL_RAW Package Body
CREATE OR REPLACE PACKAGE BODY UTL_RAW IS
    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN RAW IS
    BEGIN
        RETURN pg_catalog.convert_to(c::text, pg_catalog.getdatabaseencoding());
    END;
    FUNCTION CAST_FROM_BINARY_INTEGER(n IN NUMBER,
                                     endianess IN INTEGER DEFAULT 1) RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_raw_cast_from_binary_integer(
            n::pg_catalog.int4, endianess::pg_catalog.int4);
    END;

    FUNCTION CAST_TO_BINARY_INTEGER(r IN RAW,
                                   endianess IN INTEGER DEFAULT 1) RETURN INTEGER IS
    BEGIN
        RETURN sys.ora_utl_raw_cast_to_binary_integer(
            r::pg_catalog.bytea, endianess::pg_catalog.int4);
    END;
END;
