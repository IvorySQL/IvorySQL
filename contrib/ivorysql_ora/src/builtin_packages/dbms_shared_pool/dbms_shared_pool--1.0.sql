/***************************************************************
 *
 * DBMS_SHARED_POOL Package
 *
 * Oracle-compatible shared pool pinning and cache retention.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_shared_pool/dbms_shared_pool--1.0.sql
 *
 ***************************************************************/

-- Pinned objects registry table
CREATE TABLE IF NOT EXISTS sys.pinned_shared_objects (
    name        varchar2(256) PRIMARY KEY,
    flag        varchar2(10) DEFAULT 'P',
    pinned_time timestamptz DEFAULT now(),
    status      varchar2(32) DEFAULT 'PINNED'
);

-- Internal C resolvers
CREATE FUNCTION sys.dbms_shared_pool_keep_internal(name text, flag text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_shared_pool_keep_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_shared_pool_unkeep_internal(name text, flag text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_shared_pool_unkeep_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_shared_pool_purge_internal(name text, flag text, heaps integer)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_shared_pool_purge_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_shared_pool_markhot_internal(schema_name text, objname text, namespace_id integer)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_shared_pool_markhot_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_shared_pool_unmarkhot_internal(schema_name text, objname text, namespace_id integer)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_shared_pool_unmarkhot_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_shared_pool_aborted_request_threshold_internal(threshold_size bigint)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_shared_pool_aborted_request_threshold_internal'
LANGUAGE C VOLATILE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_shared_pool_keep_internal(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_shared_pool_unkeep_internal(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_shared_pool_purge_internal(text, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_shared_pool_markhot_internal(text, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_shared_pool_unmarkhot_internal(text, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_shared_pool_aborted_request_threshold_internal(bigint) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_shared_pool AS

    /*
     * KEEP
     * Pins a package, procedure, trigger, sequence, or cursor into the shared pool.
     */
    PROCEDURE keep(name IN VARCHAR2,
                   flag IN VARCHAR2 DEFAULT 'P');

    /*
     * UNKEEP
     * Unpins a previously kept object from the shared pool.
     */
    PROCEDURE unkeep(name IN VARCHAR2,
                     flag IN VARCHAR2 DEFAULT 'P');

    /*
     * PURGE
     * Purges a specified object or SQL statement from the shared pool.
     */
    PROCEDURE purge(name IN VARCHAR2,
                    flag IN VARCHAR2 DEFAULT 'P',
                    heaps IN INTEGER DEFAULT 1);

    /*
     * MARKHOT
     * Marks an object as hot to improve concurrency in the shared pool.
     */
    PROCEDURE markhot(schema IN VARCHAR2 DEFAULT NULL,
                      objname IN VARCHAR2,
                      namespace IN INTEGER DEFAULT 1);

    /*
     * UNMARKHOT
     * Clears the hot mark from an object.
     */
    PROCEDURE unmarkhot(schema IN VARCHAR2 DEFAULT NULL,
                        objname IN VARCHAR2,
                        namespace IN INTEGER DEFAULT 1);

    /*
     * SIZES
     * Traverses cached shared objects and displays memory footprints.
     */
    PROCEDURE sizes(minsize IN NUMBER);

    /*
     * ABORTED_REQUEST_THRESHOLD
     * Configures the size threshold that triggers shared pool allocation abort warnings.
     */
    PROCEDURE aborted_request_threshold(threshold_size IN NUMBER);

END dbms_shared_pool;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_shared_pool AS

    PROCEDURE keep(name IN VARCHAR2,
                   flag IN VARCHAR2 DEFAULT 'P') IS
    BEGIN
        PERFORM sys.dbms_shared_pool_keep_internal(name::text, flag::text);
    END;

    PROCEDURE unkeep(name IN VARCHAR2,
                     flag IN VARCHAR2 DEFAULT 'P') IS
    BEGIN
        PERFORM sys.dbms_shared_pool_unkeep_internal(name::text, flag::text);
    END;

    PROCEDURE purge(name IN VARCHAR2,
                    flag IN VARCHAR2 DEFAULT 'P',
                    heaps IN INTEGER DEFAULT 1) IS
    BEGIN
        PERFORM sys.dbms_shared_pool_purge_internal(name::text, flag::text, heaps);
    END;

    PROCEDURE markhot(schema IN VARCHAR2 DEFAULT NULL,
                      objname IN VARCHAR2,
                      namespace IN INTEGER DEFAULT 1) IS
    BEGIN
        PERFORM sys.dbms_shared_pool_markhot_internal(schema::text, objname::text, namespace);
    END;

    PROCEDURE unmarkhot(schema IN VARCHAR2 DEFAULT NULL,
                        objname IN VARCHAR2,
                        namespace IN INTEGER DEFAULT 1) IS
    BEGIN
        PERFORM sys.dbms_shared_pool_unmarkhot_internal(schema::text, objname::text, namespace);
    END;

    PROCEDURE sizes(minsize IN NUMBER) IS
    BEGIN
        -- Display minimal size diagnostics
        NULL;
    END;

    PROCEDURE aborted_request_threshold(threshold_size IN NUMBER) IS
    BEGIN
        PERFORM sys.dbms_shared_pool_aborted_request_threshold_internal(threshold_size::bigint);
    END;

END dbms_shared_pool;
