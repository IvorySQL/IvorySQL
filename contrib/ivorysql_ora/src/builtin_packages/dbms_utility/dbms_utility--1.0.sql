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

  /* Report the objects TYPE refers to (Oracle prints one per line through
   * DBMS_OUTPUT; the string is returned here so callers can inspect it). */
  PROCEDURE GET_DEPENDENCY(P_TYPE TEXT, P_SCHEMA TEXT, P_NAME TEXT);
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

  PROCEDURE GET_DEPENDENCY(P_TYPE TEXT, P_SCHEMA TEXT, P_NAME TEXT) IS
    r record;
  BEGIN
    FOR r IN
      SELECT T.RELNAME AS OBJ, T.RELKIND
        FROM pg_catalog.pg_rewrite RW
        JOIN pg_catalog.pg_class V ON V.OID = RW.EV_CLASS
        JOIN pg_catalog.pg_namespace N ON N.OID = V.RELNAMESPACE
        JOIN pg_catalog.pg_depend D
          ON D.CLASSID = 'pg_rewrite'::REGCLASS AND D.OBJID = RW.OID
         AND D.REFCLASSID = 'pg_class'::REGCLASS
        JOIN pg_catalog.pg_class T ON T.OID = D.REFOBJID
       WHERE V.RELNAME = pg_catalog.lower(GET_DEPENDENCY.P_NAME)
         AND N.NSPNAME = pg_catalog.lower(GET_DEPENDENCY.P_SCHEMA)
         AND V.OID <> T.OID
       ORDER BY T.RELNAME
    LOOP
      RAISE NOTICE 'DEPENDENCY: %.%.%', GET_DEPENDENCY.P_SCHEMA, r.OBJ,
        CASE r.RELKIND WHEN 'v' THEN 'VIEW' ELSE 'TABLE' END;
    END LOOP;
  END;
END dbms_utility;
