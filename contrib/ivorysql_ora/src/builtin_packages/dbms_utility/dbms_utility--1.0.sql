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

  /* Split a comma-separated list into an array of trimmed names. */
  PROCEDURE COMMA_TO_TABLE(LIST TEXT, TABLEN OUT INTEGER, TAB OUT TEXT[]);

  /* Join an array of names into a comma-separated list. */
  PROCEDURE TABLE_TO_COMMA(TAB TEXT[], TABLEN OUT INTEGER, LIST OUT TEXT);
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

  PROCEDURE COMMA_TO_TABLE(LIST TEXT, TABLEN OUT INTEGER, TAB OUT TEXT[]) IS
  BEGIN
    IF LIST IS NULL THEN
      TABLEN := 0;
      TAB := NULL;
      RETURN;
    END IF;
    SELECT pg_catalog.array_agg(pg_catalog.btrim(E)),
           pg_catalog.count(*)::int
      INTO TAB, TABLEN
      FROM pg_catalog.unnest(pg_catalog.string_to_array(COMMA_TO_TABLE.LIST, ',')) AS E;
  END;

  PROCEDURE TABLE_TO_COMMA(TAB TEXT[], TABLEN OUT INTEGER, LIST OUT TEXT) IS
  BEGIN
    IF TAB IS NULL THEN
      TABLEN := 0;
      LIST := NULL;
      RETURN;
    END IF;
    TABLEN := pg_catalog.array_length(TAB, 1);
    LIST := pg_catalog.array_to_string(TAB, ',');
  END;
END dbms_utility;
