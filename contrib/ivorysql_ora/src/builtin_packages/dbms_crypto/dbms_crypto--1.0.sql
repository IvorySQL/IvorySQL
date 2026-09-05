/***************************************************************
 *
 * DBMS_CRYPTO Package
 *
 * Oracle-compatible cryptographic hashing, MAC, and random generators.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_crypto/dbms_crypto--1.0.sql
 *
 ***************************************************************/

/*
 * Register the internal C functions in sys schema.
 */
CREATE FUNCTION sys.dbms_crypto_hash(src bytea, typ integer)
RETURNS bytea
AS 'MODULE_PATHNAME', 'dbms_crypto_hash'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_crypto_mac(src bytea, typ integer, key bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'dbms_crypto_mac'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_crypto_randombytes(number_bytes integer)
RETURNS bytea
AS 'MODULE_PATHNAME', 'dbms_crypto_randombytes'
LANGUAGE C VOLATILE PARALLEL RESTRICTED;

CREATE FUNCTION sys.dbms_crypto_randominteger()
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_crypto_randominteger'
LANGUAGE C VOLATILE PARALLEL RESTRICTED;

/* Revoke PUBLIC execute on internal resolver functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_crypto_hash(bytea, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_crypto_mac(bytea, integer, bytea) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_crypto_randombytes(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_crypto_randominteger() FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_crypto AS

    -- Hash Algorithm Constants
    hash_md4        CONSTANT INTEGER := 1;
    hash_md5        CONSTANT INTEGER := 2;
    hash_sh1        CONSTANT INTEGER := 3;
    hash_sh256      CONSTANT INTEGER := 4;
    hash_sh384      CONSTANT INTEGER := 5;
    hash_sh512      CONSTANT INTEGER := 6;

    -- MAC Algorithm Constants
    hmac_md5        CONSTANT INTEGER := 1;
    hmac_sh1        CONSTANT INTEGER := 2;
    hmac_sh256      CONSTANT INTEGER := 3;
    hmac_sh384      CONSTANT INTEGER := 4;
    hmac_sh512      CONSTANT INTEGER := 5;

    /*
     * HASH
     * Computes a one-way hash value from input RAW data.
     */
    FUNCTION hash(src IN RAW,
                  typ IN INTEGER) RETURN RAW;

    /*
     * HASH overload for CLOB / VARCHAR2 text input.
     */
    FUNCTION hash(src IN VARCHAR2,
                  typ IN INTEGER) RETURN RAW;

    /*
     * MAC
     * Computes a keyed Message Authentication Code (HMAC).
     */
    FUNCTION mac(src IN RAW,
                 typ IN INTEGER,
                 key IN RAW) RETURN RAW;

    /*
     * MAC overload for VARCHAR2 input.
     */
    FUNCTION mac(src IN VARCHAR2,
                 typ IN INTEGER,
                 key IN RAW) RETURN RAW;

    /*
     * RANDOMBYTES
     * Generates a pseudo-random sequence of raw bytes.
     */
    FUNCTION randombytes(number_bytes IN INTEGER) RETURN RAW;

    /*
     * RANDOMINTEGER
     * Generates a random integer across the full integer range.
     */
    FUNCTION randominteger RETURN INTEGER;

END dbms_crypto;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_crypto AS

    FUNCTION hash(src IN RAW,
                  typ IN INTEGER) RETURN RAW IS
    BEGIN
        RETURN sys.dbms_crypto_hash(src, typ);
    END;

    FUNCTION hash(src IN VARCHAR2,
                  typ IN INTEGER) RETURN RAW IS
    BEGIN
        RETURN sys.dbms_crypto_hash(pg_catalog.convert_to(src::text, pg_catalog.getdatabaseencoding()), typ);
    END;

    FUNCTION mac(src IN RAW,
                 typ IN INTEGER,
                 key IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.dbms_crypto_mac(src, typ, key);
    END;

    FUNCTION mac(src IN VARCHAR2,
                 typ IN INTEGER,
                 key IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.dbms_crypto_mac(pg_catalog.convert_to(src::text, pg_catalog.getdatabaseencoding()), typ, key);
    END;

    FUNCTION randombytes(number_bytes IN INTEGER) RETURN RAW IS
    BEGIN
        RETURN sys.dbms_crypto_randombytes(number_bytes);
    END;

    FUNCTION randominteger RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_crypto_randominteger();
    END;

END dbms_crypto;
