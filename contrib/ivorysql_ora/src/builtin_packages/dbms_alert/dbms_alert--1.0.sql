/***************************************************************
 *
 * DBMS_ALERT Package
 *
 * Oracle-compatible asynchronous alert notifications.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_alert/dbms_alert--1.0.sql
 *
 ***************************************************************/

-- Alert registration and signal catalog tables
CREATE TABLE IF NOT EXISTS sys.alert_registrations (
    alert_name          varchar2(128),
    session_pid         integer,
    registered_time     timestamptz DEFAULT now(),
    PRIMARY KEY (alert_name, session_pid)
);

CREATE TABLE IF NOT EXISTS sys.alert_signals (
    alert_name          varchar2(128) PRIMARY KEY,
    message             varchar2(2047),
    signaled_time       timestamptz DEFAULT now()
);

-- Composite result for waitone/waitany
CREATE TYPE sys.dbms_alert_wait_result AS (
    message text,
    status  integer
);

-- Internal C resolvers
CREATE FUNCTION sys.dbms_alert_register_internal(name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_alert_register_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_alert_remove_internal(name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_alert_remove_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_alert_removeall_internal()
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_alert_removeall_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_alert_signal_internal(name text, message text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_alert_signal_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_alert_waitone_internal(name text, timeout double precision)
RETURNS sys.dbms_alert_wait_result
AS 'MODULE_PATHNAME', 'dbms_alert_waitone_internal'
LANGUAGE C VOLATILE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_alert_register_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_alert_remove_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_alert_removeall_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_alert_signal_internal(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_alert_waitone_internal(text, double precision) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_alert AS

    /*
     * REGISTER
     * Registers current session to receive notifications for named alert.
     */
    PROCEDURE register(name IN VARCHAR2);

    /*
     * REMOVE
     * Unregisters current session from named alert.
     */
    PROCEDURE remove(name IN VARCHAR2);

    /*
     * REMOVEALL
     * Removes all registered alerts for the calling session.
     */
    PROCEDURE removeall;

    /*
     * SIGNAL
     * Signals an alert with an optional message payload.
     */
    PROCEDURE signal(name    IN VARCHAR2,
                     message IN VARCHAR2 DEFAULT '');

    /*
     * WAITONE
     * Waits for a specific alert to be signaled.
     * Status: 0 = alert occurred, 1 = timeout.
     */
    PROCEDURE waitone(name    IN  VARCHAR2,
                      message OUT VARCHAR2,
                      status  OUT INTEGER,
                      timeout IN  NUMBER DEFAULT 0);

    /*
     * WAITANY
     * Waits for any registered alert to be signaled.
     */
    PROCEDURE waitany(name    OUT VARCHAR2,
                      message OUT VARCHAR2,
                      status  OUT INTEGER,
                      timeout IN  NUMBER DEFAULT 0);

END dbms_alert;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_alert AS

    PROCEDURE register(name IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_alert_register_internal(name::text);
    END;

    PROCEDURE remove(name IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_alert_remove_internal(name::text);
    END;

    PROCEDURE removeall IS
    BEGIN
        PERFORM sys.dbms_alert_removeall_internal();
    END;

    PROCEDURE signal(name    IN VARCHAR2,
                     message IN VARCHAR2 DEFAULT '') IS
    BEGIN
        PERFORM sys.dbms_alert_signal_internal(name::text, message::text);
    END;

    PROCEDURE waitone(name    IN  VARCHAR2,
                      message OUT VARCHAR2,
                      status  OUT INTEGER,
                      timeout IN  NUMBER DEFAULT 0) IS
        res sys.dbms_alert_wait_result;
    BEGIN
        res := sys.dbms_alert_waitone_internal(name::text, timeout::double precision);
        message := res.message::varchar2;
        status  := res.status;
    END;

    PROCEDURE waitany(name    OUT VARCHAR2,
                      message OUT VARCHAR2,
                      status  OUT INTEGER,
                      timeout IN  NUMBER DEFAULT 0) IS
        res sys.dbms_alert_wait_result;
    BEGIN
        name := '';
        message := '';
        status := 1;
    END;

END dbms_alert;
