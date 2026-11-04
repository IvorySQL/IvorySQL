/***************************************************************
 *
 * DBMS_MVIEW Package
 *
 * Oracle-compatible Materialized View administration and refresh.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_mview/dbms_mview--1.0.sql
 *
 ***************************************************************/

-- Internal C resolvers
CREATE FUNCTION sys.dbms_mview_refresh_internal(list text,
                                                method text,
                                                rollback_seg text,
                                                push_deferred_rpc boolean,
                                                refresh_after_errors boolean,
                                                purge_option boolean,
                                                parallelism integer,
                                                heap_compression boolean,
                                                atomic_refresh boolean)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_mview_refresh_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_mview_refresh_all_mviews_internal()
RETURNS bigint
AS 'MODULE_PATHNAME', 'dbms_mview_refresh_all_mviews_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_mview_purge_mview_from_log_internal(mview_id text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_mview_purge_mview_from_log_internal'
LANGUAGE C VOLATILE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_mview_refresh_internal(text, text, text, boolean, boolean, boolean, integer, boolean, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_mview_refresh_all_mviews_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_mview_purge_mview_from_log_internal(text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_mview AS

    /*
     * REFRESH
     * Refreshes one or more comma-separated materialized views.
     */
    PROCEDURE refresh(list                 IN VARCHAR2,
                      method               IN VARCHAR2 DEFAULT '?',
                      rollback_seg         IN VARCHAR2 DEFAULT NULL,
                      push_deferred_rpc    IN BOOLEAN DEFAULT TRUE,
                      refresh_after_errors IN BOOLEAN DEFAULT FALSE,
                      purge_option         IN NUMBER DEFAULT 1,
                      parallelism          IN NUMBER DEFAULT 0,
                      heap_compression     IN BOOLEAN DEFAULT FALSE,
                      atomic_refresh       IN BOOLEAN DEFAULT TRUE);

    /*
     * REFRESH_ALL_MVIEWS
     * Refreshes all user-defined materialized views in the database.
     */
    PROCEDURE refresh_all_mviews(number_of_failures OUT NUMBER,
                                 method             IN  VARCHAR2 DEFAULT '?',
                                 rollback_seg       IN  VARCHAR2 DEFAULT NULL,
                                 refresh_after_errors IN BOOLEAN DEFAULT FALSE,
                                 atomic_refresh     IN  BOOLEAN DEFAULT TRUE);

    /*
     * PURGE_MVIEW_FROM_LOG
     * Purges rows from materialized view log for specified view.
     */
    PROCEDURE purge_mview_from_log(mview_id IN VARCHAR2);

END dbms_mview;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_mview AS

    PROCEDURE refresh(list                 IN VARCHAR2,
                      method               IN VARCHAR2 DEFAULT '?',
                      rollback_seg         IN VARCHAR2 DEFAULT NULL,
                      push_deferred_rpc    IN BOOLEAN DEFAULT TRUE,
                      refresh_after_errors IN BOOLEAN DEFAULT FALSE,
                      purge_option         IN NUMBER DEFAULT 1,
                      parallelism          IN NUMBER DEFAULT 0,
                      heap_compression     IN BOOLEAN DEFAULT FALSE,
                      atomic_refresh       IN BOOLEAN DEFAULT TRUE) IS
    BEGIN
        PERFORM sys.dbms_mview_refresh_internal(list::text,
                                                method::text,
                                                rollback_seg::text,
                                                push_deferred_rpc,
                                                refresh_after_errors,
                                                (purge_option > 0),
                                                COALESCE(parallelism, 0)::integer,
                                                heap_compression,
                                                atomic_refresh);
    END;

    PROCEDURE refresh_all_mviews(number_of_failures OUT NUMBER,
                                 method             IN  VARCHAR2 DEFAULT '?',
                                 rollback_seg       IN  VARCHAR2 DEFAULT NULL,
                                 refresh_after_errors IN BOOLEAN DEFAULT FALSE,
                                 atomic_refresh     IN  BOOLEAN DEFAULT TRUE) IS
        ref_count bigint;
    BEGIN
        ref_count := sys.dbms_mview_refresh_all_mviews_internal();
        number_of_failures := 0;
    END;

    PROCEDURE purge_mview_from_log(mview_id IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_mview_purge_mview_from_log_internal(mview_id::text);
    END;

END dbms_mview;
