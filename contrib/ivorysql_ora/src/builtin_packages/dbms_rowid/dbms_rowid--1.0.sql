/***************************************************************
 *
 * DBMS_ROWID Package
 *
 * Oracle-compatible ROWID parsing, creation, and conversion utilities.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_rowid/dbms_rowid--1.0.sql
 *
 ***************************************************************/

/*
 * Register internal C functions in sys schema.
 */
CREATE FUNCTION sys.dbms_rowid_rowid_create(rowid_type integer,
                                            object_number bigint,
                                            relative_fno bigint,
                                            block_number bigint,
                                            row_number bigint)
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_rowid_rowid_create'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_rowid_rowid_type(rowid_val text)
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_rowid_rowid_type'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_rowid_rowid_object(rowid_val text)
RETURNS bigint
AS 'MODULE_PATHNAME', 'dbms_rowid_rowid_object'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_rowid_rowid_relative_fno(rowid_val text)
RETURNS bigint
AS 'MODULE_PATHNAME', 'dbms_rowid_rowid_relative_fno'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_rowid_rowid_block_number(rowid_val text)
RETURNS bigint
AS 'MODULE_PATHNAME', 'dbms_rowid_rowid_block_number'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_rowid_rowid_row_number(rowid_val text)
RETURNS bigint
AS 'MODULE_PATHNAME', 'dbms_rowid_rowid_row_number'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_rowid_rowid_to_absolute_fno(rowid_val text)
RETURNS bigint
AS 'MODULE_PATHNAME', 'dbms_rowid_rowid_to_absolute_fno'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_rowid_rowid_to_extended(rowid_val text)
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_rowid_rowid_to_extended'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_rowid_rowid_to_restricted(rowid_val text)
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_rowid_rowid_to_restricted'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.dbms_rowid_rowid_verify(rowid_val text)
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_rowid_rowid_verify'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_rowid_rowid_create(integer, bigint, bigint, bigint, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_rowid_rowid_type(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_rowid_rowid_object(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_rowid_rowid_relative_fno(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_rowid_rowid_block_number(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_rowid_rowid_row_number(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_rowid_rowid_to_absolute_fno(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_rowid_rowid_to_extended(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_rowid_rowid_to_restricted(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_rowid_rowid_verify(text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_rowid AS

    -- Rowid types
    rowid_type_restricted   CONSTANT INTEGER := 0;
    rowid_type_extended     CONSTANT INTEGER := 1;

    -- Verification results
    rowid_is_valid          CONSTANT INTEGER := 0;
    rowid_is_invalid        CONSTANT INTEGER := 1;

    /*
     * ROWID_CREATE
     * Creates an extended or restricted rowid string based on input components.
     */
    FUNCTION rowid_create(rowid_type IN INTEGER,
                          object_number IN INTEGER,
                          relative_fno IN INTEGER,
                          block_number IN INTEGER,
                          row_number IN INTEGER) RETURN VARCHAR2;

    /*
     * ROWID_TYPE
     * Returns 0 for restricted, 1 for extended rowid.
     */
    FUNCTION rowid_type(row_id IN VARCHAR2) RETURN INTEGER;

    /*
     * ROWID_OBJECT
     * Extracts the data object number from an extended rowid (0 for restricted).
     */
    FUNCTION rowid_object(row_id IN VARCHAR2) RETURN INTEGER;

    /*
     * ROWID_RELATIVE_FNO
     * Extracts the relative file number from a rowid.
     */
    FUNCTION rowid_relative_fno(row_id IN VARCHAR2) RETURN INTEGER;

    /*
     * ROWID_BLOCK_NUMBER
     * Extracts the block number from a rowid.
     */
    FUNCTION rowid_block_number(row_id IN VARCHAR2) RETURN INTEGER;

    /*
     * ROWID_ROW_NUMBER
     * Extracts the row number within the block.
     */
    FUNCTION rowid_row_number(row_id IN VARCHAR2) RETURN INTEGER;

    /*
     * ROWID_TO_ABSOLUTE_FNO
     * Extracts the absolute file number for a rowid.
     */
    FUNCTION rowid_to_absolute_fno(row_id IN VARCHAR2,
                                   schema_name IN VARCHAR2 DEFAULT NULL,
                                   object_name IN VARCHAR2 DEFAULT NULL) RETURN INTEGER;

    /*
     * ROWID_TO_EXTENDED
     * Converts a restricted rowid to an extended rowid.
     */
    FUNCTION rowid_to_extended(old_rowid IN VARCHAR2,
                               schema_name IN VARCHAR2 DEFAULT NULL,
                               object_name IN VARCHAR2 DEFAULT NULL,
                               conversion_type IN INTEGER DEFAULT 0) RETURN VARCHAR2;

    /*
     * ROWID_TO_RESTRICTED
     * Converts an extended rowid to a restricted rowid.
     */
    FUNCTION rowid_to_restricted(old_rowid IN VARCHAR2,
                                 conversion_type IN INTEGER DEFAULT 0) RETURN VARCHAR2;

    /*
     * ROWID_VERIFY
     * Checks if a rowid can be converted and is structurally valid.
     * Returns rowid_is_valid (0) or rowid_is_invalid (1).
     */
    FUNCTION rowid_verify(rowid_val IN VARCHAR2,
                          schema_name IN VARCHAR2 DEFAULT NULL,
                          object_name IN VARCHAR2 DEFAULT NULL,
                          conversion_type IN INTEGER DEFAULT 0) RETURN INTEGER;

END dbms_rowid;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_rowid AS

    FUNCTION rowid_create(rowid_type IN INTEGER,
                          object_number IN INTEGER,
                          relative_fno IN INTEGER,
                          block_number IN INTEGER,
                          row_number IN INTEGER) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.dbms_rowid_rowid_create(rowid_type,
                                           object_number::bigint,
                                           relative_fno::bigint,
                                           block_number::bigint,
                                           row_number::bigint)::varchar2;
    END;

    FUNCTION rowid_type(row_id IN VARCHAR2) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_rowid_rowid_type(row_id::text);
    END;

    FUNCTION rowid_object(row_id IN VARCHAR2) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_rowid_rowid_object(row_id::text)::integer;
    END;

    FUNCTION rowid_relative_fno(row_id IN VARCHAR2) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_rowid_rowid_relative_fno(row_id::text)::integer;
    END;

    FUNCTION rowid_block_number(row_id IN VARCHAR2) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_rowid_rowid_block_number(row_id::text)::integer;
    END;

    FUNCTION rowid_row_number(row_id IN VARCHAR2) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_rowid_rowid_row_number(row_id::text)::integer;
    END;

    FUNCTION rowid_to_absolute_fno(row_id IN VARCHAR2,
                                   schema_name IN VARCHAR2 DEFAULT NULL,
                                   object_name IN VARCHAR2 DEFAULT NULL) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_rowid_rowid_to_absolute_fno(row_id::text)::integer;
    END;

    FUNCTION rowid_to_extended(old_rowid IN VARCHAR2,
                               schema_name IN VARCHAR2 DEFAULT NULL,
                               object_name IN VARCHAR2 DEFAULT NULL,
                               conversion_type IN INTEGER DEFAULT 0) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.dbms_rowid_rowid_to_extended(old_rowid::text)::varchar2;
    END;

    FUNCTION rowid_to_restricted(old_rowid IN VARCHAR2,
                                 conversion_type IN INTEGER DEFAULT 0) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.dbms_rowid_rowid_to_restricted(old_rowid::text)::varchar2;
    END;

    FUNCTION rowid_verify(rowid_val IN VARCHAR2,
                          schema_name IN VARCHAR2 DEFAULT NULL,
                          object_name IN VARCHAR2 DEFAULT NULL,
                          conversion_type IN INTEGER DEFAULT 0) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_rowid_rowid_verify(rowid_val::text);
    END;

END dbms_rowid;
