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

  /* Resolve an object name the way Oracle does: schema and object parts,
   * object type and OID.  A dblink part is reported as absent. */
  PROCEDURE NAME_RESOLVE(NAME TEXT, CONTEXT INTEGER,
    SCHEMA OUT TEXT, PART1 OUT TEXT, PART2 OUT TEXT, DBLINK OUT TEXT,
    PART1_TYPE OUT INTEGER, OBJECT_NUMBER OUT INTEGER);
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

  PROCEDURE NAME_RESOLVE(NAME TEXT, CONTEXT INTEGER,
    SCHEMA OUT TEXT, PART1 OUT TEXT, PART2 OUT TEXT, DBLINK OUT TEXT,
    PART1_TYPE OUT INTEGER, OBJECT_NUMBER OUT INTEGER) IS
    dot  int;
    rest text := pg_catalog.btrim(NAME);
  BEGIN
    DBLINK := NULL;
    PART1_TYPE := 0;
    OBJECT_NUMBER := 0;
    dot := pg_catalog.strpos(rest, '.');
    IF dot > 0 THEN
      SCHEMA := pg_catalog.substr(rest, 1, dot - 1);
      PART1 := pg_catalog.substr(rest, dot + 1);
    ELSE
      SCHEMA := pg_catalog.upper(current_user::text);
      PART1 := rest;
    END IF;
    PART2 := NULL;
    SELECT C.OID::int
      INTO OBJECT_NUMBER
      FROM pg_catalog.pg_class C
      JOIN pg_catalog.pg_namespace N ON N.OID = C.RELNAMESPACE
     WHERE N.NSPNAME = pg_catalog.lower(SCHEMA)
       AND C.RELNAME = pg_catalog.lower(PART1);
    IF NOT FOUND THEN
      SELECT P.OID::int
        INTO OBJECT_NUMBER
        FROM pg_catalog.pg_proc P
        JOIN pg_catalog.pg_namespace N ON N.OID = P.PRONAMESPACE
       WHERE N.NSPNAME = pg_catalog.lower(SCHEMA)
         AND P.PRONAME = pg_catalog.lower(PART1)
       LIMIT 1;
      IF FOUND THEN
        PART1_TYPE := 2;
      ELSE
        RAISE EXCEPTION 'object %.% does not exist', SCHEMA, PART1;
      END IF;
    END IF;
  END;
END dbms_utility;
