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
    FUNCTION REVERSE(r IN RAW) RETURN RAW;
END;

-- UTL_RAW Package Body
CREATE OR REPLACE PACKAGE BODY UTL_RAW IS
    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN RAW IS
    BEGIN
        RETURN pg_catalog.convert_to(c::text, pg_catalog.getdatabaseencoding());
    END;

    FUNCTION CAST_TO_VARCHAR2(r IN RAW) RETURN VARCHAR2 IS
    BEGIN
        RETURN pg_catalog.convert_from(r, pg_catalog.getdatabaseencoding());
    END;

    FUNCTION LENGTH(r IN RAW) RETURN NUMBER IS
    BEGIN
        RETURN pg_catalog.octet_length(r);
    END;

    FUNCTION REVERSE(r IN RAW) RETURN RAW IS
        result RAW := ''::raw;
        i INTEGER;
    BEGIN
        FOR i IN REVERSE 1 .. pg_catalog.octet_length(r) LOOP
            result := result || pg_catalog.substring(r FROM i FOR 1);
        END LOOP;
        RETURN result;
    END;
END;
