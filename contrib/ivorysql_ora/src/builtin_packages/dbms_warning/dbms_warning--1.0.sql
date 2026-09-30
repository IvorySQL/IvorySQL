/***************************************************************
 *
 * DBMS_WARNING Package
 *
 * Oracle-compatible compiler warning settings and categories.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_warning/dbms_warning--1.0.sql
 *
 ***************************************************************/

-- Internal C resolvers
CREATE FUNCTION sys.dbms_warning_get_category_internal(warning_number integer)
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_warning_get_category_internal'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_warning_add_warning_setting_num_internal(warning_number integer,
                                                                 warning_value text,
                                                                 current_warning_value text)
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_warning_add_warning_setting_num_internal'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_warning_get_warning_setting_num_internal(warning_number integer)
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_warning_get_warning_setting_num_internal'
LANGUAGE C STABLE;

CREATE FUNCTION sys.dbms_warning_set_warning_setting_string_internal(warning_value text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_warning_set_warning_setting_string_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_warning_get_warning_setting_string_internal()
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_warning_get_warning_setting_string_internal'
LANGUAGE C STABLE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_warning_get_category_internal(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_warning_add_warning_setting_num_internal(integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_warning_get_warning_setting_num_internal(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_warning_set_warning_setting_string_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_warning_get_warning_setting_string_internal() FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_warning AS

    /*
     * GET_CATEGORY
     * Returns warning category ('SEVERE', 'INFORMATIONAL', 'PERFORMANCE').
     */
    FUNCTION get_category(warning_number IN INTEGER) RETURN VARCHAR2;

    /*
     * ADD_WARNING_SETTING_NUM
     * Adds or modifies a specific warning code modifier in the settings string.
     */
    FUNCTION add_warning_setting_num(warning_number         IN INTEGER,
                                     warning_value          IN VARCHAR2,
                                     current_warning_value  IN VARCHAR2) RETURN VARCHAR2;

    /*
     * GET_WARNING_SETTING_NUM
     * Returns modifier ('ENABLE', 'DISABLE', 'ERROR') for given warning number.
     */
    FUNCTION get_warning_setting_num(warning_number IN INTEGER) RETURN VARCHAR2;

    /*
     * SET_WARNING_SETTING_STRING
     * Replaces the current session warning settings string.
     */
    PROCEDURE set_warning_setting_string(warning_value IN VARCHAR2);

    /*
     * GET_WARNING_SETTING_STRING
     * Returns the current session warning settings string.
     */
    FUNCTION get_warning_setting_string RETURN VARCHAR2;

END dbms_warning;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_warning AS

    FUNCTION get_category(warning_number IN INTEGER) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.dbms_warning_get_category_internal(warning_number)::varchar2;
    END;

    FUNCTION add_warning_setting_num(warning_number         IN INTEGER,
                                     warning_value          IN VARCHAR2,
                                     current_warning_value  IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.dbms_warning_add_warning_setting_num_internal(warning_number,
                                                                 warning_value::text,
                                                                 current_warning_value::text)::varchar2;
    END;

    FUNCTION get_warning_setting_num(warning_number IN INTEGER) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.dbms_warning_get_warning_setting_num_internal(warning_number)::varchar2;
    END;

    PROCEDURE set_warning_setting_string(warning_value IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_warning_set_warning_setting_string_internal(warning_value::text);
    END;

    FUNCTION get_warning_setting_string RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.dbms_warning_get_warning_setting_string_internal()::varchar2;
    END;

END dbms_warning;
