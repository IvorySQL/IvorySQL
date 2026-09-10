/***************************************************************
 *
 * DBMS_APPLICATION_INFO Package
 *
 * Oracle-compatible session metadata registration and diagnostics.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_application_info/dbms_application_info--1.0.sql
 *
 ***************************************************************/

/*
 * Internal C functions in sys schema.
 */
CREATE FUNCTION sys.dbms_application_info_set_module(module_name text, action_name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_application_info_set_module'
LANGUAGE C VOLATILE PARALLEL RESTRICTED;

CREATE FUNCTION sys.dbms_application_info_set_action(action_name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_application_info_set_action'
LANGUAGE C VOLATILE PARALLEL RESTRICTED;

CREATE FUNCTION sys.dbms_application_info_set_client_info(client_info text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_application_info_set_client_info'
LANGUAGE C VOLATILE PARALLEL RESTRICTED;

CREATE FUNCTION sys.dbms_application_info_get_module()
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_application_info_get_module'
LANGUAGE C VOLATILE PARALLEL RESTRICTED;

CREATE FUNCTION sys.dbms_application_info_get_action()
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_application_info_get_action'
LANGUAGE C VOLATILE PARALLEL RESTRICTED;

CREATE FUNCTION sys.dbms_application_info_get_client_info()
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_application_info_get_client_info'
LANGUAGE C VOLATILE PARALLEL RESTRICTED;

/* Revoke PUBLIC execute on internal resolver functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_application_info_set_module(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_application_info_set_action(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_application_info_set_client_info(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_application_info_get_module() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_application_info_get_action() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_application_info_get_client_info() FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_application_info AS

    set_session_longops_nohint CONSTANT INTEGER := -1;

    /*
     * SET_MODULE
     * Sets the name of the current application or module (up to 48 bytes)
     * and optionally the current action (up to 32 bytes).
     */
    PROCEDURE set_module(module_name IN VARCHAR2,
                         action_name IN VARCHAR2);

    /*
     * SET_ACTION
     * Sets the name of the current action within the current module (up to 32 bytes).
     */
    PROCEDURE set_action(action_name IN VARCHAR2);

    /*
     * SET_CLIENT_INFO
     * Supplies additional information about the client application (up to 64 bytes).
     */
    PROCEDURE set_client_info(client_info IN VARCHAR2);

    /*
     * READ_MODULE
     * Reads the current values of module and action for the session.
     */
    PROCEDURE read_module(module_name OUT VARCHAR2,
                          action_name OUT VARCHAR2);

    /*
     * READ_CLIENT_INFO
     * Reads the current value of client_info for the session.
     */
    PROCEDURE read_client_info(client_info OUT VARCHAR2);

END dbms_application_info;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_application_info AS

    PROCEDURE set_module(module_name IN VARCHAR2,
                         action_name IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_application_info_set_module(module_name, action_name);
    END;

    PROCEDURE set_action(action_name IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_application_info_set_action(action_name);
    END;

    PROCEDURE set_client_info(client_info IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_application_info_set_client_info(client_info);
    END;

    PROCEDURE read_module(module_name OUT VARCHAR2,
                          action_name OUT VARCHAR2) IS
    BEGIN
        module_name := sys.dbms_application_info_get_module();
        action_name := sys.dbms_application_info_get_action();
    END;

    PROCEDURE read_client_info(client_info OUT VARCHAR2) IS
    BEGIN
        client_info := sys.dbms_application_info_get_client_info();
    END;

END dbms_application_info;
