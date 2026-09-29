/***************************************************************
 *
 * UTL_COMPRESS Package
 *
 * Oracle-compatible data compression functions.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_compress/utl_compress--1.0.sql
 *
 ***************************************************************/

-- C function wrappers
CREATE FUNCTION sys.ora_utl_compress_lz_compress(src bytea, quality integer)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_compress_lz_compress'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION sys.ora_utl_compress_lz_uncompress(src bytea)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_compress_lz_uncompress'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- UTL_COMPRESS Package Definition
-- UTL_COMPRESS package Header
CREATE OR REPLACE PACKAGE UTL_COMPRESS IS
    FUNCTION LZ_COMPRESS(
        src IN RAW,
        quality IN INTEGER DEFAULT 6
    )
    RETURN RAW;

    FUNCTION LZ_UNCOMPRESS(
        src IN RAW
    )
    RETURN RAW;
END UTL_COMPRESS;

-- UTL_COMPRESS package Body
CREATE OR REPLACE PACKAGE BODY UTL_COMPRESS IS
    FUNCTION LZ_COMPRESS(
        src IN RAW,
        quality IN INTEGER DEFAULT 6
    )
    RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_compress_lz_compress(src, quality);
    END;

    FUNCTION LZ_UNCOMPRESS(
        src IN RAW
    )
    RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_compress_lz_uncompress(src);
    END;
END UTL_COMPRESS;