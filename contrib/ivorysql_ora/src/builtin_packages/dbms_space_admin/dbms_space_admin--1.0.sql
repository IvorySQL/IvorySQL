/***************************************************************
 *
 * DBMS_SPACE_ADMIN Package
 *
 * Oracle-compatible tablespace and segment administration utilities.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_space_admin/dbms_space_admin--1.0.sql
 *
 ***************************************************************/

-- Internal C resolvers
CREATE FUNCTION sys.dbms_space_admin_tablespace_verify_internal(tablespace_name text,
                                                                verify_mode integer)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_space_admin_tablespace_verify_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_space_admin_segment_verify_internal(schema_name text,
                                                             segment_name text,
                                                             segment_type text,
                                                             verify_mode integer)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_space_admin_segment_verify_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_space_admin_tablespace_fix_segment_states_internal(tablespace_name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_space_admin_tablespace_fix_segment_states_internal'
LANGUAGE C VOLATILE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_space_admin_tablespace_verify_internal(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_space_admin_segment_verify_internal(text, text, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_space_admin_tablespace_fix_segment_states_internal(text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_space_admin AS

    -- Verification modes
    segment_verify_basic        CONSTANT INTEGER := 1;
    segment_verify_deep         CONSTANT INTEGER := 2;

    tablespace_verify_basic     CONSTANT INTEGER := 1;
    tablespace_verify_extents   CONSTANT INTEGER := 2;

    /*
     * TABLESPACE_VERIFY
     * Verifies integrity of the specified tablespace.
     */
    PROCEDURE tablespace_verify(tablespace_name IN VARCHAR2,
                                verify_mode     IN INTEGER DEFAULT 1);

    /*
     * SEGMENT_VERIFY
     * Verifies structural consistency of a database segment.
     */
    PROCEDURE segment_verify(schema_name    IN VARCHAR2 DEFAULT NULL,
                             segment_name   IN VARCHAR2,
                             segment_type   IN VARCHAR2 DEFAULT 'TABLE',
                             verify_mode    IN INTEGER DEFAULT 1);

    /*
     * TABLESPACE_FIX_SEGMENT_STATES
     * Corrects inconsistent segment states in the tablespace.
     */
    PROCEDURE tablespace_fix_segment_states(tablespace_name IN VARCHAR2);

END dbms_space_admin;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_space_admin AS

    PROCEDURE tablespace_verify(tablespace_name IN VARCHAR2,
                                verify_mode     IN INTEGER DEFAULT 1) IS
    BEGIN
        PERFORM sys.dbms_space_admin_tablespace_verify_internal(tablespace_name::text,
                                                                verify_mode);
    END;

    PROCEDURE segment_verify(schema_name    IN VARCHAR2 DEFAULT NULL,
                             segment_name   IN VARCHAR2,
                             segment_type   IN VARCHAR2 DEFAULT 'TABLE',
                             verify_mode    IN INTEGER DEFAULT 1) IS
    BEGIN
        PERFORM sys.dbms_space_admin_segment_verify_internal(schema_name::text,
                                                             segment_name::text,
                                                             segment_type::text,
                                                             verify_mode);
    END;

    PROCEDURE tablespace_fix_segment_states(tablespace_name IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_space_admin_tablespace_fix_segment_states_internal(tablespace_name::text);
    END;

END dbms_space_admin;
