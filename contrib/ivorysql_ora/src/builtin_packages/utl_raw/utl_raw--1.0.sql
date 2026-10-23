/***************************************************************
 *
 * UTL_RAW Package
 *
 * Oracle-compatible binary data manipulation functions.
 *
 * The byte-level work lives in C (utl_raw.c) and is registered below as
 * sys.utl_raw_* functions; the PL/iSQL package wraps them, exactly like
 * UTL_ENCODE and UTL_MATCH.  Oracle's RAW maps to bytea in IvorySQL.
 *
 * NULL handling: every C function is STRICT, so a NULL argument yields NULL.
 * The arguments for which Oracle gives NULL a special meaning are therefore
 * resolved by the PL/iSQL wrappers:
 *   - SUBSTR's len defaults to NULL, meaning "through the end of r";
 *   - COMPARE's pad defaults to NULL, meaning "pad with 0x00 bytes", and two
 *     NULL RAW values compare equal (0);
 *   - CONCAT skips NULL values and is NULL only when all twelve are NULL;
 *   - OVERLAY's len defaults to NULL, meaning length(overlay_str), and its pad
 *     defaults to NULL, meaning "fill with 0x00 bytes".
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw--1.0.sql
 *
 ***************************************************************/

/*
 * Register the C implementations in the sys schema.
 * Input/output use bytea (RAW maps to bytea in IvorySQL).
 * STRICT: returns NULL automatically when an argument is NULL.
 */
CREATE FUNCTION sys.utl_raw_length(bytea)
RETURNS integer
AS 'MODULE_PATHNAME', 'utl_raw_length'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_substr(bytea, integer)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_substr'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_substr(bytea, integer, integer)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_substr_len'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_concat(bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_concat'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_compare(bytea, bytea)
RETURNS integer
AS 'MODULE_PATHNAME', 'utl_raw_compare'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_compare(bytea, bytea, bytea)
RETURNS integer
AS 'MODULE_PATHNAME', 'utl_raw_compare_pad'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_bit_and(bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_bit_and'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_bit_or(bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_bit_or'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_bit_xor(bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_bit_xor'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_bit_complement(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_bit_complement'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_reverse(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_reverse'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_overlay(bytea, bytea, integer, integer)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_overlay'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_overlay_pad(bytea, bytea, integer, integer, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_overlay_pad'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_translate(bytea, bytea, bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_translate'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_raw_copies(bytea, integer)
RETURNS bytea
AS 'MODULE_PATHNAME', 'utl_raw_copies'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

-- UTL_RAW Package Header
CREATE OR REPLACE PACKAGE UTL_RAW IS
    -- Endianness constants (used by future CAST_FROM/TO_BINARY_* functions)
    big_endian      CONSTANT INTEGER := 1;
    little_endian   CONSTANT INTEGER := 2;
    machine_endian  CONSTANT INTEGER := 3;

    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN RAW;

    -- LENGTH: number of bytes in r
    FUNCTION LENGTH(r IN RAW) RETURN INTEGER;

    -- SUBSTR: len bytes of r starting at pos (1-based; negative counts back)
    FUNCTION SUBSTR(r IN RAW, pos IN INTEGER, len IN INTEGER DEFAULT NULL) RETURN RAW;

    -- CONCAT: the supplied values in order; NULL values are skipped
    FUNCTION CONCAT(r1 IN RAW DEFAULT NULL, r2 IN RAW DEFAULT NULL,
                    r3 IN RAW DEFAULT NULL, r4 IN RAW DEFAULT NULL,
                    r5 IN RAW DEFAULT NULL, r6 IN RAW DEFAULT NULL,
                    r7 IN RAW DEFAULT NULL, r8 IN RAW DEFAULT NULL,
                    r9 IN RAW DEFAULT NULL, r10 IN RAW DEFAULT NULL,
                    r11 IN RAW DEFAULT NULL, r12 IN RAW DEFAULT NULL) RETURN RAW;

    -- COMPARE: 1-based position of the first differing byte, 0 if equal
    FUNCTION COMPARE(r1 IN RAW, r2 IN RAW, pad IN RAW DEFAULT NULL) RETURN INTEGER;

    -- BIT_AND/BIT_OR/BIT_XOR: byte-wise ops over the longer operand, with
    -- the shorter one padded (X'FF' for BIT_AND, X'00' for BIT_OR/BIT_XOR)
    FUNCTION BIT_AND(r1 IN RAW, r2 IN RAW) RETURN RAW;
    FUNCTION BIT_OR(r1 IN RAW, r2 IN RAW) RETURN RAW;
    FUNCTION BIT_XOR(r1 IN RAW, r2 IN RAW) RETURN RAW;

    -- BIT_COMPLEMENT: byte-wise one's complement
    FUNCTION BIT_COMPLEMENT(r IN RAW) RETURN RAW;

    -- REVERSE: bytes of r in reverse order
    FUNCTION REVERSE(r IN RAW) RETURN RAW;

    -- OVERLAY: replace len bytes of target at pos with overlay_str
    FUNCTION OVERLAY(overlay_str IN RAW, target IN RAW,
                     pos IN INTEGER DEFAULT 1, len IN INTEGER DEFAULT NULL,
                     pad IN RAW DEFAULT NULL) RETURN RAW;

    -- TRANSLATE: translate the bytes of r through the from -> to table
    FUNCTION TRANSLATE(r IN RAW, from_set IN RAW, to_set IN RAW) RETURN RAW;

    -- COPIES: n concatenated copies of r
    FUNCTION COPIES(r IN RAW, n IN INTEGER) RETURN RAW;
END;

-- UTL_RAW Package Body
CREATE OR REPLACE PACKAGE BODY UTL_RAW IS
    FUNCTION CAST_TO_RAW(c IN VARCHAR2) RETURN RAW IS
    BEGIN
        RETURN pg_catalog.convert_to(c::text, pg_catalog.getdatabaseencoding());
    END;

    FUNCTION LENGTH(r IN RAW) RETURN INTEGER IS
    BEGIN
        RETURN sys.utl_raw_length(r);
    END;

    FUNCTION SUBSTR(r IN RAW, pos IN INTEGER, len IN INTEGER DEFAULT NULL) RETURN RAW IS
    BEGIN
        IF len IS NULL THEN
            RETURN sys.utl_raw_substr(r, pos);
        END IF;
        RETURN sys.utl_raw_substr(r, pos, len);
    END;

    FUNCTION CONCAT(r1 IN RAW DEFAULT NULL, r2 IN RAW DEFAULT NULL,
                    r3 IN RAW DEFAULT NULL, r4 IN RAW DEFAULT NULL,
                    r5 IN RAW DEFAULT NULL, r6 IN RAW DEFAULT NULL,
                    r7 IN RAW DEFAULT NULL, r8 IN RAW DEFAULT NULL,
                    r9 IN RAW DEFAULT NULL, r10 IN RAW DEFAULT NULL,
                    r11 IN RAW DEFAULT NULL, r12 IN RAW DEFAULT NULL)
                    RETURN RAW IS
        result RAW;
    BEGIN
        -- Oracle ignores NULL values, so only the all-NULL call returns NULL.
        IF r1 IS NULL AND r2 IS NULL AND r3 IS NULL AND r4 IS NULL AND
           r5 IS NULL AND r6 IS NULL AND r7 IS NULL AND r8 IS NULL AND
           r9 IS NULL AND r10 IS NULL AND r11 IS NULL AND r12 IS NULL THEN
            RETURN NULL;
        END IF;

        result := COALESCE(r1, '\x'::bytea);
        result := sys.utl_raw_concat(result, COALESCE(r2, '\x'::bytea));
        result := sys.utl_raw_concat(result, COALESCE(r3, '\x'::bytea));
        result := sys.utl_raw_concat(result, COALESCE(r4, '\x'::bytea));
        result := sys.utl_raw_concat(result, COALESCE(r5, '\x'::bytea));
        result := sys.utl_raw_concat(result, COALESCE(r6, '\x'::bytea));
        result := sys.utl_raw_concat(result, COALESCE(r7, '\x'::bytea));
        result := sys.utl_raw_concat(result, COALESCE(r8, '\x'::bytea));
        result := sys.utl_raw_concat(result, COALESCE(r9, '\x'::bytea));
        result := sys.utl_raw_concat(result, COALESCE(r10, '\x'::bytea));
        result := sys.utl_raw_concat(result, COALESCE(r11, '\x'::bytea));
        result := sys.utl_raw_concat(result, COALESCE(r12, '\x'::bytea));
        RETURN result;
    END;

    FUNCTION COMPARE(r1 IN RAW, r2 IN RAW, pad IN RAW DEFAULT NULL) RETURN INTEGER IS
    BEGIN
        -- Two NULL RAW values compare equal in Oracle.
        IF r1 IS NULL AND r2 IS NULL THEN
            RETURN 0;
        END IF;
        IF pad IS NULL THEN
            RETURN sys.utl_raw_compare(r1, r2);
        END IF;
        RETURN sys.utl_raw_compare(r1, r2, pad);
    END;

    FUNCTION BIT_AND(r1 IN RAW, r2 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.utl_raw_bit_and(r1, r2);
    END;

    FUNCTION BIT_OR(r1 IN RAW, r2 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.utl_raw_bit_or(r1, r2);
    END;

    FUNCTION BIT_XOR(r1 IN RAW, r2 IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.utl_raw_bit_xor(r1, r2);
    END;

    FUNCTION BIT_COMPLEMENT(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.utl_raw_bit_complement(r);
    END;

    FUNCTION REVERSE(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.utl_raw_reverse(r);
    END;

    FUNCTION OVERLAY(overlay_str IN RAW, target IN RAW,
                     pos IN INTEGER DEFAULT 1, len IN INTEGER DEFAULT NULL,
                     pad IN RAW DEFAULT NULL) RETURN RAW IS
        use_len INTEGER;
    BEGIN
        IF len IS NULL THEN
            use_len := sys.utl_raw_length(overlay_str);
        ELSE
            use_len := len;
        END IF;

        IF pad IS NULL THEN
            RETURN sys.utl_raw_overlay(overlay_str, target, pos, use_len);
        END IF;
        RETURN sys.utl_raw_overlay_pad(overlay_str, target, pos, use_len, pad);
    END;

    FUNCTION TRANSLATE(r IN RAW, from_set IN RAW, to_set IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.utl_raw_translate(r, from_set, to_set);
    END;

    FUNCTION COPIES(r IN RAW, n IN INTEGER) RETURN RAW IS
    BEGIN
        RETURN sys.utl_raw_copies(r, n);
    END;
END;
