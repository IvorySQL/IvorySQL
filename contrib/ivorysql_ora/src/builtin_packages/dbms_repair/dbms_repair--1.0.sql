/***************************************************************
 *
 * DBMS_REPAIR Package
 *
 * Oracle-compatible block corruption repair and diagnostics.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_repair/dbms_repair--1.0.sql
 *
 ***************************************************************/

-- Internal C resolvers
CREATE FUNCTION sys.dbms_repair_admin_tables_internal(table_name text,
                                                      table_type integer,
                                                      action integer,
                                                      tablespace text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_repair_admin_tables_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_repair_check_object_internal(schema_name text,
                                                      object_name text,
                                                      repair_table_name text)
RETURNS bigint
AS 'MODULE_PATHNAME', 'dbms_repair_check_object_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_repair_fix_corrupt_blocks_internal(schema_name text,
                                                            object_name text)
RETURNS bigint
AS 'MODULE_PATHNAME', 'dbms_repair_fix_corrupt_blocks_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_repair_skip_corrupt_blocks_internal(schema_name text,
                                                             object_name text,
                                                             flags integer)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_repair_skip_corrupt_blocks_internal'
LANGUAGE C VOLATILE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_repair_admin_tables_internal(text, integer, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_repair_check_object_internal(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_repair_fix_corrupt_blocks_internal(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_repair_skip_corrupt_blocks_internal(text, text, integer) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_repair AS

    -- Table types
    repair_table            CONSTANT INTEGER := 1;
    orphan_table            CONSTANT INTEGER := 2;

    -- Admin actions
    create_action           CONSTANT INTEGER := 1;
    purge_action            CONSTANT INTEGER := 2;
    drop_action             CONSTANT INTEGER := 3;

    -- Flags
    skip_flag               CONSTANT INTEGER := 1;
    noskip_flag             CONSTANT INTEGER := 2;

    /*
     * ADMIN_TABLES
     * Creates, purges, or drops repair and orphan-key administration tables.
     */
    PROCEDURE admin_tables(table_name IN VARCHAR2,
                           table_type IN INTEGER,
                           action     IN INTEGER,
                           tablespace IN VARCHAR2 DEFAULT NULL);

    /*
     * CHECK_OBJECT
     * Detects corrupt blocks in the specified relation and records them into repair_table_name.
     */
    PROCEDURE check_object(schema_name       IN  VARCHAR2 DEFAULT NULL,
                           object_name       IN  VARCHAR2,
                           corrupt_count     OUT NUMBER,
                           repair_table_name IN  VARCHAR2 DEFAULT 'REPAIR_TABLE');

    /*
     * FIX_CORRUPT_BLOCKS
     * Fixes corrupt blocks in the specified relation based on repair table entries.
     */
    PROCEDURE fix_corrupt_blocks(schema_name IN  VARCHAR2 DEFAULT NULL,
                                 object_name IN  VARCHAR2,
                                 fix_count   OUT NUMBER);

    /*
     * SKIP_CORRUPT_BLOCKS
     * Configures the relation to skip corrupt blocks during subsequent table scans.
     */
    PROCEDURE skip_corrupt_blocks(schema_name IN VARCHAR2 DEFAULT NULL,
                                  object_name IN VARCHAR2,
                                  flags       IN INTEGER DEFAULT 1);

END dbms_repair;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_repair AS

    PROCEDURE admin_tables(table_name IN VARCHAR2,
                           table_type IN INTEGER,
                           action     IN INTEGER,
                           tablespace IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        PERFORM sys.dbms_repair_admin_tables_internal(table_name::text,
                                                      table_type,
                                                      action,
                                                      tablespace::text);
    END;

    PROCEDURE check_object(schema_name       IN  VARCHAR2 DEFAULT NULL,
                           object_name       IN  VARCHAR2,
                           corrupt_count     OUT NUMBER,
                           repair_table_name IN  VARCHAR2 DEFAULT 'REPAIR_TABLE') IS
    BEGIN
        corrupt_count := sys.dbms_repair_check_object_internal(schema_name::text,
                                                               object_name::text,
                                                               repair_table_name::text);
    END;

    PROCEDURE fix_corrupt_blocks(schema_name IN  VARCHAR2 DEFAULT NULL,
                                 object_name IN  VARCHAR2,
                                 fix_count   OUT NUMBER) IS
    BEGIN
        fix_count := sys.dbms_repair_fix_corrupt_blocks_internal(schema_name::text,
                                                                 object_name::text);
    END;

    PROCEDURE skip_corrupt_blocks(schema_name IN VARCHAR2 DEFAULT NULL,
                                  object_name IN VARCHAR2,
                                  flags       IN INTEGER DEFAULT 1) IS
    BEGIN
        PERFORM sys.dbms_repair_skip_corrupt_blocks_internal(schema_name::text,
                                                             object_name::text,
                                                             flags);
    END;

END dbms_repair;
