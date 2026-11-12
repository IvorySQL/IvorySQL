/***************************************************************
 *
 * DBMS_DDL Package
 *
 * Oracle-compatible DDL helpers for Oracle mode.
 *
 * This first cut implements the two most-used subprograms:
 *   ALTER_COMPILE   recompiles a stored procedure, function, package or
 *                   package body.
 *   ANALYZE_OBJECT  updates the statistics of a table.
 *
 * Out of scope: the deprecated WRAP / CREATE_WRAPPED subprograms and the
 * Oracle-specific ANALYZE_OBJECT tuning options (estimate_rows,
 * estimate_percent, method_opt, partname).  TEXT names are treated as
 * Oracle unquoted identifiers when they are all upper case; mixed-case names
 * are treated as quoted identifiers.
 *
 ***************************************************************/

CREATE FUNCTION sys.ora_dbms_ddl_alter_compile(text, text, text)
RETURNS void
AS 'MODULE_PATHNAME','ora_dbms_ddl_alter_compile'
LANGUAGE C
VOLATILE;

CREATE FUNCTION sys.ora_dbms_ddl_analyze_object(text, text, text, text)
RETURNS void
AS 'MODULE_PATHNAME','ora_dbms_ddl_analyze_object'
LANGUAGE C
VOLATILE;

CREATE PACKAGE dbms_ddl AS

    PROCEDURE alter_compile(object_type TEXT,
                            schema TEXT,
                            name TEXT,
                            reuse_settings BOOLEAN DEFAULT TRUE);

    PROCEDURE analyze_object(object_type TEXT,
                             schema TEXT,
                             name TEXT,
                             method TEXT,
                             estimate_rows NUMBER DEFAULT NULL,
                             estimate_percent NUMBER DEFAULT NULL,
                             method_opt TEXT DEFAULT NULL,
                             partname TEXT DEFAULT NULL);

END dbms_ddl;

CREATE PACKAGE BODY dbms_ddl AS

    PROCEDURE alter_compile(object_type TEXT,
                            schema TEXT,
                            name TEXT,
                            reuse_settings BOOLEAN DEFAULT TRUE) IS
    BEGIN
        PERFORM sys.ora_dbms_ddl_alter_compile(object_type, schema, name);
    END;

    PROCEDURE analyze_object(object_type TEXT,
                             schema TEXT,
                             name TEXT,
                             method TEXT,
                             estimate_rows NUMBER DEFAULT NULL,
                             estimate_percent NUMBER DEFAULT NULL,
                             method_opt TEXT DEFAULT NULL,
                             partname TEXT DEFAULT NULL) IS
    BEGIN
        PERFORM sys.ora_dbms_ddl_analyze_object(object_type, schema, name, method);
    END;

END dbms_ddl;

GRANT EXECUTE ON PACKAGE dbms_ddl TO PUBLIC;
