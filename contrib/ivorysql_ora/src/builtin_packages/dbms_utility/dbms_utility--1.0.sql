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
  PROCEDURE EXEC_DDL_STATEMENT(parse_string IN VARCHAR2);
  FUNCTION PORT_STRING RETURN VARCHAR2;
  FUNCTION IS_PARALLEL_SERVER RETURN BOOLEAN;
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

  -- Runs a DDL statement given as a string, the way Oracle applications use it
  -- to issue CREATE/ALTER/DROP from a procedure.
  PROCEDURE EXEC_DDL_STATEMENT(parse_string IN VARCHAR2) IS
  BEGIN
    EXECUTE parse_string;
  END;

  -- Oracle returns the operating system and database version string; the
  -- server's version() carries the same two pieces of information.
  FUNCTION PORT_STRING RETURN VARCHAR2 IS
  BEGIN
    RETURN pg_catalog.version();
  END;

  -- Oracle is FALSE outside an Oracle Real Application Clusters instance;
  -- PostgreSQL has no parallel server mode, so it is always FALSE here.
  FUNCTION IS_PARALLEL_SERVER RETURN BOOLEAN IS
  BEGIN
    RETURN FALSE;
  END;
END dbms_utility;
