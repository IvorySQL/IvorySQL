/***************************************************************
 *
 * DBMS_TTS Package
 *
 * Oracle-compatible Transportable Tablespaces (TTS) checks and tools.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_tts/dbms_tts--1.0.sql
 *
 ***************************************************************/

-- Transport set violations view/table
CREATE TABLE IF NOT EXISTS sys.transport_set_violations (
    violation   varchar2(2047)
);

-- Internal C resolvers
CREATE FUNCTION sys.dbms_tts_transport_set_check_internal(ts_list text,
                                                          incl_constraints boolean,
                                                          full_check boolean)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_tts_transport_set_check_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_tts_downgrade_internal()
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_tts_downgrade_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_tts_is_platform_supported_internal(platform_name text)
RETURNS boolean
AS 'MODULE_PATHNAME', 'dbms_tts_is_platform_supported_internal'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_tts_get_endianness_internal(platform_name text)
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_tts_get_endianness_internal'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_tts_check_version_internal(version text)
RETURNS boolean
AS 'MODULE_PATHNAME', 'dbms_tts_check_version_internal'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_tts_transport_set_check_internal(text, boolean, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_tts_downgrade_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_tts_is_platform_supported_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_tts_get_endianness_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_tts_check_version_internal(text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_tts AS

    -- Endianness constants
    big_endian      CONSTANT INTEGER := 1;
    little_endian   CONSTANT INTEGER := 2;

    /*
     * TRANSPORT_SET_CHECK
     * Checks if a set of tablespaces is self-contained.
     * Violations are recorded in sys.transport_set_violations.
     */
    PROCEDURE transport_set_check(ts_list          IN VARCHAR2,
                                  incl_constraints IN BOOLEAN DEFAULT FALSE,
                                  full_check       IN BOOLEAN DEFAULT FALSE);

    /*
     * DOWNGRADE
     * Cleans up transportable tablespace metadata during downgrade.
     */
    PROCEDURE downgrade;

    /*
     * IS_PLATFORM_SUPPORTED
     * Checks if the target platform is supported for cross-platform transport.
     */
    FUNCTION is_platform_supported(platform_name IN VARCHAR2) RETURN BOOLEAN;

    /*
     * GET_ENDIANNESS
     * Returns endianness (1 for big endian, 2 for little endian) of target platform.
     */
    FUNCTION get_endianness(platform_name IN VARCHAR2) RETURN INTEGER;

    /*
     * CHECK_VERSION
     * Checks if target version is compatible with transportable tablespace format.
     */
    FUNCTION check_version(version IN VARCHAR2) RETURN BOOLEAN;

END dbms_tts;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_tts AS

    PROCEDURE transport_set_check(ts_list          IN VARCHAR2,
                                  incl_constraints IN BOOLEAN DEFAULT FALSE,
                                  full_check       IN BOOLEAN DEFAULT FALSE) IS
    BEGIN
        PERFORM sys.dbms_tts_transport_set_check_internal(ts_list::text,
                                                          incl_constraints,
                                                          full_check);
    END;

    PROCEDURE downgrade IS
    BEGIN
        PERFORM sys.dbms_tts_downgrade_internal();
    END;

    FUNCTION is_platform_supported(platform_name IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        RETURN sys.dbms_tts_is_platform_supported_internal(platform_name::text);
    END;

    FUNCTION get_endianness(platform_name IN VARCHAR2) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_tts_get_endianness_internal(platform_name::text);
    END;

    FUNCTION check_version(version IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        RETURN sys.dbms_tts_check_version_internal(version::text);
    END;

END dbms_tts;
