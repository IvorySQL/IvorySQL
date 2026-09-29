/***************************************************************
 *
 * DBMS_MONITOR Package
 *
 * Oracle-compatible workload monitoring, statistics, and trace controls.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_monitor/dbms_monitor--1.0.sql
 *
 ***************************************************************/

-- Monitoring catalog tables
CREATE TABLE IF NOT EXISTS sys.monitored_client_ids (
    client_id       varchar2(128) PRIMARY KEY,
    stat_enabled    boolean DEFAULT false,
    trace_enabled   boolean DEFAULT false,
    updated_time    timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sys.monitored_sessions (
    session_id      integer,
    serial_num      integer,
    trace_enabled   boolean DEFAULT false,
    waits           boolean DEFAULT true,
    binds           boolean DEFAULT false,
    plan_stat       varchar2(64) DEFAULT 'FIRST_EXECUTION',
    updated_time    timestamptz DEFAULT now(),
    PRIMARY KEY (session_id, serial_num)
);

-- Internal C resolvers
CREATE FUNCTION sys.dbms_monitor_client_id_stat_enable_internal(client_id text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_monitor_client_id_stat_enable_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_monitor_client_id_stat_disable_internal(client_id text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_monitor_client_id_stat_disable_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_monitor_client_id_trace_enable_internal(client_id text,
                                                                 waits boolean,
                                                                 binds boolean,
                                                                 plan_stat text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_monitor_client_id_trace_enable_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_monitor_client_id_trace_disable_internal(client_id text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_monitor_client_id_trace_disable_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_monitor_session_trace_enable_internal(session_id integer,
                                                               serial_num integer,
                                                               waits boolean,
                                                               binds boolean,
                                                               plan_stat text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_monitor_session_trace_enable_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_monitor_session_trace_disable_internal(session_id integer,
                                                                serial_num integer)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_monitor_session_trace_disable_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_monitor_database_trace_enable_internal(waits boolean,
                                                                binds boolean,
                                                                plan_stat text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_monitor_database_trace_enable_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_monitor_database_trace_disable_internal()
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_monitor_database_trace_disable_internal'
LANGUAGE C VOLATILE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_monitor_client_id_stat_enable_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_monitor_client_id_stat_disable_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_monitor_client_id_trace_enable_internal(text, boolean, boolean, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_monitor_client_id_trace_disable_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_monitor_session_trace_enable_internal(integer, integer, boolean, boolean, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_monitor_session_trace_disable_internal(integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_monitor_database_trace_enable_internal(boolean, boolean, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_monitor_database_trace_disable_internal() FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_monitor AS

    /*
     * CLIENT_ID_STAT_ENABLE / DISABLE
     * Enables or disables statistics collection for a specific client_id.
     */
    PROCEDURE client_id_stat_enable(client_id IN VARCHAR2);
    PROCEDURE client_id_stat_disable(client_id IN VARCHAR2);

    /*
     * CLIENT_ID_TRACE_ENABLE / DISABLE
     * Enables or disables SQL tracing for a specific client_id.
     */
    PROCEDURE client_id_trace_enable(client_id  IN VARCHAR2,
                                     waits      IN BOOLEAN DEFAULT TRUE,
                                     binds      IN BOOLEAN DEFAULT FALSE,
                                     plan_stat  IN VARCHAR2 DEFAULT 'FIRST_EXECUTION');
    PROCEDURE client_id_trace_disable(client_id IN VARCHAR2);

    /*
     * SESSION_TRACE_ENABLE / DISABLE
     * Enables or disables SQL trace for a session with wait and bind variable options.
     */
    PROCEDURE session_trace_enable(session_id IN INTEGER DEFAULT 0,
                                   serial_num IN INTEGER DEFAULT 0,
                                   waits      IN BOOLEAN DEFAULT TRUE,
                                   binds      IN BOOLEAN DEFAULT FALSE,
                                   plan_stat  IN VARCHAR2 DEFAULT 'FIRST_EXECUTION');
    PROCEDURE session_trace_disable(session_id IN INTEGER DEFAULT 0,
                                    serial_num IN INTEGER DEFAULT 0);

    /*
     * DATABASE_TRACE_ENABLE / DISABLE
     * Enables or disables instance-wide SQL tracing.
     */
    PROCEDURE database_trace_enable(waits     IN BOOLEAN DEFAULT TRUE,
                                    binds     IN BOOLEAN DEFAULT FALSE,
                                    plan_stat IN VARCHAR2 DEFAULT 'FIRST_EXECUTION');
    PROCEDURE database_trace_disable;

END dbms_monitor;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_monitor AS

    PROCEDURE client_id_stat_enable(client_id IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_monitor_client_id_stat_enable_internal(client_id::text);
    END;

    PROCEDURE client_id_stat_disable(client_id IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_monitor_client_id_stat_disable_internal(client_id::text);
    END;

    PROCEDURE client_id_trace_enable(client_id  IN VARCHAR2,
                                     waits      IN BOOLEAN DEFAULT TRUE,
                                     binds      IN BOOLEAN DEFAULT FALSE,
                                     plan_stat  IN VARCHAR2 DEFAULT 'FIRST_EXECUTION') IS
    BEGIN
        PERFORM sys.dbms_monitor_client_id_trace_enable_internal(client_id::text, waits, binds, plan_stat::text);
    END;

    PROCEDURE client_id_trace_disable(client_id IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_monitor_client_id_trace_disable_internal(client_id::text);
    END;

    PROCEDURE session_trace_enable(session_id IN INTEGER DEFAULT 0,
                                   serial_num IN INTEGER DEFAULT 0,
                                   waits      IN BOOLEAN DEFAULT TRUE,
                                   binds      IN BOOLEAN DEFAULT FALSE,
                                   plan_stat  IN VARCHAR2 DEFAULT 'FIRST_EXECUTION') IS
    BEGIN
        PERFORM sys.dbms_monitor_session_trace_enable_internal(session_id,
                                                               serial_num,
                                                               waits,
                                                               binds,
                                                               plan_stat::text);
    END;

    PROCEDURE session_trace_disable(session_id IN INTEGER DEFAULT 0,
                                    serial_num IN INTEGER DEFAULT 0) IS
    BEGIN
        PERFORM sys.dbms_monitor_session_trace_disable_internal(session_id, serial_num);
    END;

    PROCEDURE database_trace_enable(waits     IN BOOLEAN DEFAULT TRUE,
                                    binds     IN BOOLEAN DEFAULT FALSE,
                                    plan_stat IN VARCHAR2 DEFAULT 'FIRST_EXECUTION') IS
    BEGIN
        PERFORM sys.dbms_monitor_database_trace_enable_internal(waits, binds, plan_stat::text);
    END;

    PROCEDURE database_trace_disable IS
    BEGIN
        PERFORM sys.dbms_monitor_database_trace_disable_internal();
    END;

END dbms_monitor;
