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

  /* ANALYZE every table in every user schema. */
  PROCEDURE ANALYZE_DATABASE(METHOD TEXT DEFAULT 'COMPUTE',
    ESTIMATE_PERCENT NUMBER DEFAULT 100,
    METHOD_OPT TEXT DEFAULT 'FOR ALL COLUMNS SIZE AUTO');
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

  PROCEDURE ANALYZE_DATABASE(METHOD TEXT DEFAULT 'COMPUTE',
    ESTIMATE_PERCENT NUMBER DEFAULT 100,
    METHOD_OPT TEXT DEFAULT 'FOR ALL COLUMNS SIZE AUTO') IS
    r record;
  BEGIN
    FOR r IN SELECT N.NSPNAME, C.RELNAME
               FROM pg_catalog.pg_class C
               JOIN pg_catalog.pg_namespace N ON N.OID = C.RELNAMESPACE
              WHERE C.RELKIND IN ('r', 'p')
                AND N.NSPNAME NOT IN ('pg_catalog', 'information_schema',
                                      'pg_toast')
    LOOP
      EXECUTE pg_catalog.format('ANALYZE %I.%I', r.NSPNAME, r.RELNAME);
    END LOOP;
  END;
END dbms_utility;
