/***************************************************************
 *
 * DBMS_SYSTEM Package
 *
 * Oracle-compatible system diagnostics and trace utilities.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_system/dbms_system--1.0.sql
 *
 ***************************************************************/

-- Internal C resolvers
CREATE FUNCTION sys.dbms_system_ksdwrt_internal(dest integer, msg text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_system_ksdwrt_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_system_set_sql_trace_in_session_internal(sid integer, serial integer, sql_trace boolean)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_system_set_sql_trace_in_session_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_system_set_ev_internal(sid integer, serial integer, event_id integer, event_level integer, name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_system_set_ev_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_system_read_ev_internal(event_id integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_system_read_ev_internal'
LANGUAGE C STABLE;

CREATE FUNCTION sys.dbms_system_get_env_internal(var text)
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_system_get_env_internal'
LANGUAGE C STABLE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_system_ksdwrt_internal(integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_system_set_sql_trace_in_session_internal(integer, integer, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_system_set_ev_internal(integer, integer, integer, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_system_read_ev_internal(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_system_get_env_internal(text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_system AS

    -- Destination constants for KSDWRT
    dest_trace      CONSTANT INTEGER := 1;
    dest_alert      CONSTANT INTEGER := 2;
    dest_both       CONSTANT INTEGER := 3;

    /*
     * KSDWRT
     * Writes formatted diagnostic messages to trace files or alert log.
     */
    PROCEDURE ksdwrt(dest IN INTEGER,
                     msg  IN VARCHAR2);

    /*
     * SET_SQL_TRACE_IN_SESSION
     * Enables or disables SQL tracing for the specified session (sid, serial#).
     */
    PROCEDURE set_sql_trace_in_session(sid       IN INTEGER,
                                       serial    IN INTEGER,
                                       sql_trace IN BOOLEAN);

    /*
     * SET_EV
     * Sets event levels for diagnostic events in a session.
     */
    PROCEDURE set_ev(si  IN INTEGER,
                     se  IN INTEGER,
                     ev  IN INTEGER,
                     le  IN INTEGER,
                     nm  IN VARCHAR2 DEFAULT '');

    /*
     * READ_EV
     * Reads current event level for diagnostic events.
     */
    PROCEDURE read_ev(iev IN  INTEGER,
                      oev OUT INTEGER);

    /*
     * GET_ENV
     * Retrieves an environment variable.
     */
    PROCEDURE get_env(var IN VARCHAR2,
                      val OUT VARCHAR2);

END dbms_system;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_system AS

    PROCEDURE ksdwrt(dest IN INTEGER,
                     msg  IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_system_ksdwrt_internal(dest, msg::text);
    END;

    PROCEDURE set_sql_trace_in_session(sid       IN INTEGER,
                                       serial    IN INTEGER,
                                       sql_trace IN BOOLEAN) IS
    BEGIN
        PERFORM sys.dbms_system_set_sql_trace_in_session_internal(sid, serial, sql_trace);
    END;

    PROCEDURE set_ev(si  IN INTEGER,
                     se  IN INTEGER,
                     ev  IN INTEGER,
                     le  IN INTEGER,
                     nm  IN VARCHAR2 DEFAULT '') IS
    BEGIN
        PERFORM sys.dbms_system_set_ev_internal(si, se, ev, le, nm::text);
    END;

    PROCEDURE read_ev(iev IN  INTEGER,
                      oev OUT INTEGER) IS
    BEGIN
        oev := sys.dbms_system_read_ev_internal(iev);
    END;

    PROCEDURE get_env(var IN VARCHAR2,
                      val OUT VARCHAR2) IS
    BEGIN
        val := sys.dbms_system_get_env_internal(var::text)::varchar2;
    END;

END dbms_system;
