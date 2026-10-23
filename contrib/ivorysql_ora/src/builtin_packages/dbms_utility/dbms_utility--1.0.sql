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

  /* The database version banner, and a bit test. */
  FUNCTION DB_VERSION RETURN TEXT;
  FUNCTION IS_BIT_SET(VALUE NUMBER, BIT_IN_POSITION NUMBER) RETURN BOOLEAN;
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

  FUNCTION DB_VERSION RETURN TEXT IS
  BEGIN
    RETURN pg_catalog.current_setting('server_version');
  END;

  FUNCTION IS_BIT_SET(VALUE NUMBER, BIT_IN_POSITION NUMBER) RETURN BOOLEAN IS
  BEGIN
    IF VALUE IS NULL OR BIT_IN_POSITION IS NULL OR BIT_IN_POSITION < 0 THEN
      RETURN NULL;
    END IF;
    RETURN pg_catalog.mod(
             pg_catalog.trunc(VALUE::numeric /
                 pg_catalog.power(2::numeric, BIT_IN_POSITION::numeric)),
             2::numeric) = 1;
  END;
END dbms_utility;
