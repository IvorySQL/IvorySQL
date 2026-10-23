/***************************************************************
 *
 * DBMS_UTILITY Package
 *
 * Oracle-compatible utility functions.
 *
 ***************************************************************/

-- C function wrappers
CREATE FUNCTION sys.ora_format_error_backtrace() RETURNS TEXT
AS 'MODULE_PATHNAME', 'ora_format_error_backtrace'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_format_error_stack() RETURNS TEXT
AS 'MODULE_PATHNAME', 'ora_format_error_stack'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_format_call_stack() RETURNS TEXT
AS 'MODULE_PATHNAME', 'ora_format_call_stack'
LANGUAGE C VOLATILE;

COMMENT ON FUNCTION sys.ora_format_error_backtrace() IS 'Internal function for DBMS_UTILITY.FORMAT_ERROR_BACKTRACE';
COMMENT ON FUNCTION sys.ora_format_error_stack() IS 'Internal function for DBMS_UTILITY.FORMAT_ERROR_STACK';
COMMENT ON FUNCTION sys.ora_format_call_stack() IS 'Internal function for DBMS_UTILITY.FORMAT_CALL_STACK';

-- DBMS_UTILITY Package Definition
CREATE OR REPLACE PACKAGE dbms_utility IS
  FUNCTION FORMAT_ERROR_BACKTRACE RETURN TEXT;
  FUNCTION FORMAT_ERROR_STACK RETURN TEXT;
  FUNCTION FORMAT_CALL_STACK RETURN TEXT;

  /* ANALYZE every table in a schema. */
  PROCEDURE ANALYZE_SCHEMA(SCHEMANAME TEXT);

  /* PostgreSQL has nothing to recompile, so this validates the schema name
   * and returns, which is what Oracle callers rely on it for. */
  PROCEDURE COMPILE_SCHEMA(SCHEMANAME TEXT);
END dbms_utility;

CREATE OR REPLACE PACKAGE BODY dbms_utility IS
  FUNCTION FORMAT_ERROR_BACKTRACE RETURN TEXT IS
  BEGIN
    RETURN sys.ora_format_error_backtrace();
  END;

  FUNCTION FORMAT_ERROR_STACK RETURN TEXT IS
  BEGIN
    RETURN sys.ora_format_error_stack();
  END;

  FUNCTION FORMAT_CALL_STACK RETURN TEXT IS
  BEGIN
    RETURN sys.ora_format_call_stack();
  END;

  PROCEDURE ANALYZE_SCHEMA(SCHEMANAME TEXT) IS
    r record;
  BEGIN
    FOR r IN SELECT C.RELNAME
               FROM pg_catalog.pg_class C
               JOIN pg_catalog.pg_namespace N ON N.OID = C.RELNAMESPACE
              WHERE N.NSPNAME = pg_catalog.lower(ANALYZE_SCHEMA.SCHEMANAME)
                AND C.RELKIND IN ('r', 'p')
    LOOP
      EXECUTE pg_catalog.format('ANALYZE %I.%I',
                               pg_catalog.lower(ANALYZE_SCHEMA.SCHEMANAME),
                               r.RELNAME);
    END LOOP;
  END;

  PROCEDURE COMPILE_SCHEMA(SCHEMANAME TEXT) IS
    n int;
  BEGIN
    SELECT count(*) INTO n
      FROM pg_catalog.pg_namespace
     WHERE NSPNAME = pg_catalog.lower(COMPILE_SCHEMA.SCHEMANAME);
    IF n = 0 THEN
      RAISE EXCEPTION 'schema % does not exist',
        COMPILE_SCHEMA.SCHEMANAME;
    END IF;
  END;
END dbms_utility;
