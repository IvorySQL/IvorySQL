/***************************************************************
 *
 * UTL_IDENT Package
 *
 * Oracle-compatible environment identification flags for conditional
 * compilation and runtime environment detection.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_ident/utl_ident--1.0.sql
 *
 ***************************************************************/

/*
 * Register internal C functions in sys schema.
 */
CREATE FUNCTION sys.utl_ident_is_oracle_server()
RETURNS boolean
AS 'MODULE_PATHNAME', 'utl_ident_is_oracle_server'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_ident_is_oracle_client()
RETURNS boolean
AS 'MODULE_PATHNAME', 'utl_ident_is_oracle_client'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_ident_is_timesten()
RETURNS boolean
AS 'MODULE_PATHNAME', 'utl_ident_is_timesten'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_ident_is_oracle_forms()
RETURNS boolean
AS 'MODULE_PATHNAME', 'utl_ident_is_oracle_forms'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_ident_is_satellite()
RETURNS boolean
AS 'MODULE_PATHNAME', 'utl_ident_is_satellite'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_ident_environment()
RETURNS text
AS 'MODULE_PATHNAME', 'utl_ident_environment'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_ident_get_release_major()
RETURNS integer
AS 'MODULE_PATHNAME', 'utl_ident_get_release_major'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_ident_get_release_minor()
RETURNS integer
AS 'MODULE_PATHNAME', 'utl_ident_get_release_minor'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_ident_get_version_string()
RETURNS text
AS 'MODULE_PATHNAME', 'utl_ident_get_version_string'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_ident_matches_environment(env text)
RETURNS boolean
AS 'MODULE_PATHNAME', 'utl_ident_matches_environment'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

/* Revoke PUBLIC execute on internal resolver functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.utl_ident_is_oracle_server() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_ident_is_oracle_client() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_ident_is_timesten() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_ident_is_oracle_forms() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_ident_is_satellite() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_ident_environment() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_ident_get_release_major() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_ident_get_release_minor() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_ident_get_version_string() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_ident_matches_environment(text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE utl_ident AS

    -- Environment Identification Constants
    is_oracle_server    CONSTANT BOOLEAN := TRUE;
    is_oracle_client    CONSTANT BOOLEAN := FALSE;
    is_timesten         CONSTANT BOOLEAN := FALSE;
    is_oracle_forms     CONSTANT BOOLEAN := FALSE;
    is_satellite        CONSTANT BOOLEAN := FALSE;

    -- Version and Release Constants
    oracle_release      CONSTANT INTEGER := 23;
    oracle_version      CONSTANT INTEGER := 0;

    /*
     * GET_ENVIRONMENT
     * Returns the name of the active database environment (e.g. 'ORACLE_SERVER').
     */
    FUNCTION get_environment RETURN VARCHAR2;

    /*
     * CHECK_SERVER
     * Returns TRUE if executing inside an Oracle-compatible database server.
     */
    FUNCTION check_server RETURN BOOLEAN;

    /*
     * GET_RELEASE
     * Returns the major release compatibility number (e.g. 23).
     */
    FUNCTION get_release RETURN INTEGER;

    /*
     * GET_VERSION
     * Returns the minor release compatibility number (e.g. 0).
     */
    FUNCTION get_version RETURN INTEGER;

    /*
     * GET_VERSION_STRING
     * Returns human-readable version string for the active Oracle compatibility layer.
     */
    FUNCTION get_version_string RETURN VARCHAR2;

    /*
     * MATCHES_ENVIRONMENT
     * Returns TRUE if target environment string matches the active environment.
     */
    FUNCTION matches_environment(env IN VARCHAR2) RETURN BOOLEAN;

END utl_ident;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY utl_ident AS

    FUNCTION get_environment RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_ident_environment();
    END;

    FUNCTION check_server RETURN BOOLEAN IS
    BEGIN
        RETURN sys.utl_ident_is_oracle_server();
    END;

    FUNCTION get_release RETURN INTEGER IS
    BEGIN
        RETURN sys.utl_ident_get_release_major();
    END;

    FUNCTION get_version RETURN INTEGER IS
    BEGIN
        RETURN sys.utl_ident_get_release_minor();
    END;

    FUNCTION get_version_string RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_ident_get_version_string();
    END;

    FUNCTION matches_environment(env IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        RETURN sys.utl_ident_matches_environment(env);
    END;

END utl_ident;
