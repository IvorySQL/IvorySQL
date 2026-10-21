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

  /* Centiseconds, for measuring elapsed time between two calls. */
  FUNCTION GET_TIME RETURN NUMBER;

  /* A deterministic hash of NAME in [BASE, BASE + HASH_SIZE - 1]. */
  FUNCTION GET_HASH_VALUE(NAME TEXT, BASE NUMBER, HASH_SIZE NUMBER) RETURN NUMBER;

  /* Split "owner.name@link" into its parts; Oracle passes five OUT
   * parameters, and the parts that are absent come back NULL. */
  PROCEDURE NAME_TOKENIZE(NAME TEXT, A OUT TEXT, B OUT TEXT, C OUT TEXT,
                          D OUT TEXT, E OUT TEXT);
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

  FUNCTION GET_TIME RETURN NUMBER IS
  BEGIN
    RETURN pg_catalog.floor(
             pg_catalog.date_part('epoch', pg_catalog.clock_timestamp()) * 100)::numeric;
  END;

  FUNCTION GET_HASH_VALUE(NAME TEXT, BASE NUMBER, HASH_SIZE NUMBER) RETURN NUMBER IS
    h numeric;
  BEGIN
    IF NAME IS NULL OR BASE IS NULL OR HASH_SIZE IS NULL OR HASH_SIZE <= 0 THEN
      RETURN NULL;
    END IF;
    h := pg_catalog.hashtext(NAME)::numeric;
    RETURN BASE + pg_catalog.mod(pg_catalog.abs(h), HASH_SIZE::numeric);
  END;

  PROCEDURE NAME_TOKENIZE(NAME TEXT, A OUT TEXT, B OUT TEXT, C OUT TEXT,
                          D OUT TEXT, E OUT TEXT) IS
    rest text := NAME;
    pos  int;
  BEGIN
    A := NULL; B := NULL; C := NULL; D := NULL; E := NULL;
    IF NAME IS NULL THEN
      RETURN;
    END IF;
    pos := pg_catalog.strpos(rest, '@');
    IF pos > 0 THEN
      C := pg_catalog.substr(rest, pos + 1);
      rest := pg_catalog.substr(rest, 1, pos - 1);
    END IF;
    pos := pg_catalog.strpos(rest, '.');
    IF pos > 0 THEN
      A := pg_catalog.substr(rest, 1, pos - 1);
      B := pg_catalog.substr(rest, pos + 1);
    ELSE
      B := rest;
    END IF;
  END;
END dbms_utility;
