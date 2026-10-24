/***************************************************************
 *
 * DBMS_ERRLOG Package
 *
 * Oracle-compatible DML error logging table generation.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_errlog/dbms_errlog--1.0.sql
 *
 ***************************************************************/

-- Error log registry table
CREATE TABLE IF NOT EXISTS sys.errlog_tables (
    dml_table_name      varchar2(128),
    err_log_table_name  varchar2(128),
    err_log_owner       varchar2(128),
    created_time        timestamptz DEFAULT now(),
    PRIMARY KEY (dml_table_name, err_log_table_name)
);

-- Internal C resolvers
CREATE FUNCTION sys.dbms_errlog_create_error_log_internal(dml_table_name text,
                                                          err_log_table_name text,
                                                          err_log_table_owner text,
                                                          skip_unsupported boolean)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_errlog_create_error_log_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_errlog_drop_error_log_internal(dml_table_name text,
                                                        err_log_table_name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_errlog_drop_error_log_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_errlog_purge_error_log_internal(dml_table_name text,
                                                         err_log_table_name text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_errlog_purge_error_log_internal'
LANGUAGE C VOLATILE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_errlog_create_error_log_internal(text, text, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_errlog_drop_error_log_internal(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_errlog_purge_error_log_internal(text, text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_errlog AS

    /*
     * CREATE_ERROR_LOG
     * Creates an error logging table for the specified DML table.
     */
    PROCEDURE create_error_log(dml_table_name          IN VARCHAR2,
                               err_log_table_name      IN VARCHAR2 DEFAULT NULL,
                               err_log_table_owner     IN VARCHAR2 DEFAULT NULL,
                               err_log_table_space     IN VARCHAR2 DEFAULT NULL,
                               skip_unsupported        IN BOOLEAN DEFAULT FALSE);

    /*
     * DROP_ERROR_LOG
     * Drops the specified error log table.
     */
    PROCEDURE drop_error_log(dml_table_name     IN VARCHAR2,
                             err_log_table_name IN VARCHAR2 DEFAULT NULL);

    /*
     * PURGE_ERROR_LOG
     * Truncates records in the error log table while preserving table structure.
     */
    PROCEDURE purge_error_log(dml_table_name     IN VARCHAR2,
                              err_log_table_name IN VARCHAR2 DEFAULT NULL);

END dbms_errlog;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_errlog AS

    PROCEDURE create_error_log(dml_table_name          IN VARCHAR2,
                               err_log_table_name      IN VARCHAR2 DEFAULT NULL,
                               err_log_table_owner     IN VARCHAR2 DEFAULT NULL,
                               err_log_table_space     IN VARCHAR2 DEFAULT NULL,
                               skip_unsupported        IN BOOLEAN DEFAULT FALSE) IS
    BEGIN
        PERFORM sys.dbms_errlog_create_error_log_internal(dml_table_name::text,
                                                          err_log_table_name::text,
                                                          err_log_table_owner::text,
                                                          skip_unsupported);
    END;

    PROCEDURE drop_error_log(dml_table_name     IN VARCHAR2,
                             err_log_table_name IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        PERFORM sys.dbms_errlog_drop_error_log_internal(dml_table_name::text,
                                                        err_log_table_name::text);
    END;

    PROCEDURE purge_error_log(dml_table_name     IN VARCHAR2,
                              err_log_table_name IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        PERFORM sys.dbms_errlog_purge_error_log_internal(dml_table_name::text,
                                                         err_log_table_name::text);
    END;

END dbms_errlog;
