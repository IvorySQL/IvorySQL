/***************************************************************
 *
 * UTL_RAW Package
 *
 * Oracle-compatible binary data manipulation functions.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw--1.0.sql
 *
 ***************************************************************/

-- Inner C helper: converts text bytes to uppercase hex string.
-- STRICT ensures NULL in → NULL out, matching Oracle behavior.
CREATE FUNCTION sys.utl_raw_cast_to_raw(c text)
RETURNS varchar2
AS 'MODULE_PATHNAME', 'ora_utl_raw_cast_to_raw'
LANGUAGE C STRICT IMMUTABLE;

-- UTL_RAW Package Header
CREATE OR REPLACE PACKAGE UTL_RAW IS
    -- Endianness constants (used by future CAST_FROM/TO_BINARY_* functions)
    big_endian      CONSTANT INTEGER := 1;
    little_endian   CONSTANT INTEGER := 2;
    machine_endian  CONSTANT INTEGER := 3;

    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN VARCHAR2;
END;

-- UTL_RAW Package Body
CREATE OR REPLACE PACKAGE BODY UTL_RAW IS
    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_raw_cast_to_raw(c::text);
    END;
END;
