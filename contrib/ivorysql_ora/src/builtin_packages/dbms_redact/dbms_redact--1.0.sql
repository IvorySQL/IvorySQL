/***************************************************************
 *
 * DBMS_REDACT Package
 *
 * Oracle-compatible Data Redaction policies and column masking.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_redact/dbms_redact--1.0.sql
 *
 ***************************************************************/

-- Redaction policy catalog tables
CREATE TABLE IF NOT EXISTS sys.redaction_policies (
    object_owner        varchar2(128),
    object_name         varchar2(128),
    policy_name         varchar2(128),
    expression          text,
    enable              boolean DEFAULT true,
    policy_description  varchar2(2047),
    PRIMARY KEY (object_owner, object_name, policy_name)
);

CREATE TABLE IF NOT EXISTS sys.redaction_columns (
    object_owner        varchar2(128),
    object_name         varchar2(128),
    policy_name         varchar2(128),
    column_name         varchar2(128),
    function_type       integer,
    function_parameters text,
    PRIMARY KEY (object_owner, object_name, policy_name, column_name)
);

-- Internal C resolvers
CREATE FUNCTION sys.dbms_redact_add_policy_internal(object_schema text,
                                                    object_name text,
                                                    policy_name text,
                                                    expression text,
                                                    function_type integer,
                                                    column_name text,
                                                    function_parameters text,
                                                    policy_description text,
                                                    enable boolean)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_redact_add_policy_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_redact_drop_policy_internal(object_schema text,
                                                     object_name text,
                                                     policy_name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_redact_drop_policy_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_redact_enable_policy_internal(object_schema text,
                                                       object_name text,
                                                       policy_name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_redact_enable_policy_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_redact_disable_policy_internal(object_schema text,
                                                        object_name text,
                                                        policy_name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_redact_disable_policy_internal'
LANGUAGE C VOLATILE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_redact_add_policy_internal(text, text, text, text, integer, text, text, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_redact_drop_policy_internal(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_redact_enable_policy_internal(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_redact_disable_policy_internal(text, text, text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_redact AS

    -- Function types
    full            CONSTANT INTEGER := 1;
    partial         CONSTANT INTEGER := 2;
    random          CONSTANT INTEGER := 3;
    none            CONSTANT INTEGER := 4;
    regexp          CONSTANT INTEGER := 5;

    /*
     * ADD_POLICY
     * Creates a data redaction policy for a specified table and column.
     */
    PROCEDURE add_policy(object_schema        IN VARCHAR2 DEFAULT NULL,
                         object_name          IN VARCHAR2,
                         policy_name          IN VARCHAR2,
                         column_name          IN VARCHAR2,
                         function_type        IN INTEGER DEFAULT 1,
                         function_parameters  IN VARCHAR2 DEFAULT NULL,
                         expression           IN VARCHAR2 DEFAULT '1=1',
                         enable               IN BOOLEAN DEFAULT TRUE,
                         policy_description   IN VARCHAR2 DEFAULT NULL);

    /*
     * DROP_POLICY
     * Drops an existing data redaction policy.
     */
    PROCEDURE drop_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                          object_name   IN VARCHAR2,
                          policy_name   IN VARCHAR2);

    /*
     * ENABLE_POLICY
     * Enables an inactive redaction policy.
     */
    PROCEDURE enable_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                            object_name   IN VARCHAR2,
                            policy_name   IN VARCHAR2);

    /*
     * DISABLE_POLICY
     * Disables an active redaction policy.
     */
    PROCEDURE disable_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                             object_name   IN VARCHAR2,
                             policy_name   IN VARCHAR2);

END dbms_redact;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_redact AS

    PROCEDURE add_policy(object_schema        IN VARCHAR2 DEFAULT NULL,
                         object_name          IN VARCHAR2,
                         policy_name          IN VARCHAR2,
                         column_name          IN VARCHAR2,
                         function_type        IN INTEGER DEFAULT 1,
                         function_parameters  IN VARCHAR2 DEFAULT NULL,
                         expression           IN VARCHAR2 DEFAULT '1=1',
                         enable               IN BOOLEAN DEFAULT TRUE,
                         policy_description   IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        PERFORM sys.dbms_redact_add_policy_internal(object_schema::text,
                                                    object_name::text,
                                                    policy_name::text,
                                                    expression::text,
                                                    function_type,
                                                    column_name::text,
                                                    function_parameters::text,
                                                    policy_description::text,
                                                    enable);
    END;

    PROCEDURE drop_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                          object_name   IN VARCHAR2,
                          policy_name   IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_redact_drop_policy_internal(object_schema::text,
                                                     object_name::text,
                                                     policy_name::text);
    END;

    PROCEDURE enable_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                            object_name   IN VARCHAR2,
                            policy_name   IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_redact_enable_policy_internal(object_schema::text,
                                                       object_name::text,
                                                       policy_name::text);
    END;

    PROCEDURE disable_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                             object_name   IN VARCHAR2,
                             policy_name   IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_redact_disable_policy_internal(object_schema::text,
                                                        object_name::text,
                                                        policy_name::text);
    END;

END dbms_redact;
