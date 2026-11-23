/***************************************************************
 *
 * DBMS_RLS Package
 *
 * Oracle-compatible Row-Level Security (Virtual Private Database).
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_rls/dbms_rls--1.0.sql
 *
 ***************************************************************/

-- RLS policies catalog table
CREATE TABLE IF NOT EXISTS sys.rls_policies (
    object_owner            varchar2(128),
    object_name             varchar2(128),
    policy_name             varchar2(128),
    function_owner          varchar2(128),
    policy_function         varchar2(128),
    statement_types         varchar2(128),
    update_check            boolean DEFAULT false,
    enable                  boolean DEFAULT true,
    static_policy           boolean DEFAULT false,
    policy_type             integer DEFAULT 1,
    sec_relevant_cols       varchar2(2047),
    sec_relevant_cols_opt   integer DEFAULT 0,
    PRIMARY KEY (object_owner, object_name, policy_name)
);

-- Internal C resolvers
CREATE FUNCTION sys.dbms_rls_add_policy_internal(object_schema text,
                                                 object_name text,
                                                 policy_name text,
                                                 function_schema text,
                                                 policy_function text,
                                                 statement_types text,
                                                 update_check boolean,
                                                 enable boolean,
                                                 static_policy boolean,
                                                 policy_type integer,
                                                 sec_relevant_cols text,
                                                 sec_relevant_cols_opt integer)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_rls_add_policy_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_rls_drop_policy_internal(object_schema text,
                                                  object_name text,
                                                  policy_name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_rls_drop_policy_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_rls_enable_policy_internal(object_schema text,
                                                    object_name text,
                                                    policy_name text,
                                                    enable boolean)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_rls_enable_policy_internal'
LANGUAGE C VOLATILE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_rls_add_policy_internal(text, text, text, text, text, text, boolean, boolean, boolean, integer, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_rls_drop_policy_internal(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_rls_enable_policy_internal(text, text, text, boolean) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_rls AS

    -- Policy types
    dynamic                     CONSTANT INTEGER := 1;
    static_policy               CONSTANT INTEGER := 2;
    shared_static               CONSTANT INTEGER := 3;
    context_sensitive           CONSTANT INTEGER := 4;
    shared_context_sensitive    CONSTANT INTEGER := 5;

    -- Security relevant column options
    all_rows                    CONSTANT INTEGER := 1;

    /*
     * ADD_POLICY
     * Registers a fine-grained access control policy for a relation.
     */
    PROCEDURE add_policy(object_schema         IN VARCHAR2 DEFAULT NULL,
                         object_name           IN VARCHAR2,
                         policy_name           IN VARCHAR2,
                         function_schema       IN VARCHAR2 DEFAULT NULL,
                         policy_function       IN VARCHAR2,
                         statement_types       IN VARCHAR2 DEFAULT 'SELECT,INSERT,UPDATE,DELETE',
                         update_check          IN BOOLEAN DEFAULT FALSE,
                         enable                IN BOOLEAN DEFAULT TRUE,
                         static_policy         IN BOOLEAN DEFAULT FALSE,
                         policy_type           IN INTEGER DEFAULT 1,
                         long_predicate        IN BOOLEAN DEFAULT FALSE,
                         sec_relevant_cols     IN VARCHAR2 DEFAULT NULL,
                         sec_relevant_cols_opt IN INTEGER DEFAULT 0);

    /*
     * DROP_POLICY
     * Removes an existing row-level security policy.
     */
    PROCEDURE drop_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                          object_name   IN VARCHAR2,
                          policy_name   IN VARCHAR2);

    /*
     * ENABLE_POLICY
     * Enables or disables an access control policy.
     */
    PROCEDURE enable_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                            object_name   IN VARCHAR2,
                            policy_name   IN VARCHAR2,
                            enable        IN BOOLEAN DEFAULT TRUE);

    /*
     * REFRESH_POLICY
     * Refreshes cached parsed SQL statements affected by the policy.
     */
    PROCEDURE refresh_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                             object_name   IN VARCHAR2 DEFAULT NULL,
                             policy_name   IN VARCHAR2 DEFAULT NULL);

END dbms_rls;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_rls AS

    PROCEDURE add_policy(object_schema         IN VARCHAR2 DEFAULT NULL,
                         object_name           IN VARCHAR2,
                         policy_name           IN VARCHAR2,
                         function_schema       IN VARCHAR2 DEFAULT NULL,
                         policy_function       IN VARCHAR2,
                         statement_types       IN VARCHAR2 DEFAULT 'SELECT,INSERT,UPDATE,DELETE',
                         update_check          IN BOOLEAN DEFAULT FALSE,
                         enable                IN BOOLEAN DEFAULT TRUE,
                         static_policy         IN BOOLEAN DEFAULT FALSE,
                         policy_type           IN INTEGER DEFAULT 1,
                         long_predicate        IN BOOLEAN DEFAULT FALSE,
                         sec_relevant_cols     IN VARCHAR2 DEFAULT NULL,
                         sec_relevant_cols_opt IN INTEGER DEFAULT 0) IS
    BEGIN
        PERFORM sys.dbms_rls_add_policy_internal(object_schema::text,
                                                 object_name::text,
                                                 policy_name::text,
                                                 function_schema::text,
                                                 policy_function::text,
                                                 statement_types::text,
                                                 update_check,
                                                 enable,
                                                 static_policy,
                                                 policy_type,
                                                 sec_relevant_cols::text,
                                                 sec_relevant_cols_opt);
    END;

    PROCEDURE drop_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                          object_name   IN VARCHAR2,
                          policy_name   IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_rls_drop_policy_internal(object_schema::text,
                                                  object_name::text,
                                                  policy_name::text);
    END;

    PROCEDURE enable_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                            object_name   IN VARCHAR2,
                            policy_name   IN VARCHAR2,
                            enable        IN BOOLEAN DEFAULT TRUE) IS
    BEGIN
        PERFORM sys.dbms_rls_enable_policy_internal(object_schema::text,
                                                    object_name::text,
                                                    policy_name::text,
                                                    enable);
    END;

    PROCEDURE refresh_policy(object_schema IN VARCHAR2 DEFAULT NULL,
                             object_name   IN VARCHAR2 DEFAULT NULL,
                             policy_name   IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        NULL;
    END;

END dbms_rls;
