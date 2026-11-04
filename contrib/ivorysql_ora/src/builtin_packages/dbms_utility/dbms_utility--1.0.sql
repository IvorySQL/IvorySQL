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
{anchor}
/*
 * New members: GET_TIME, DB_VERSION, GET_HASH_VALUE (C) and the
 * COMMA_TO_TABLE / TABLE_TO_COMMA text[] helpers (SQL).
 */
CREATE FUNCTION sys.ora_dbms_utility_get_time()
RETURNS bigint
AS 'MODULE_PATHNAME', 'ora_dbms_utility_get_time'
LANGUAGE C VOLATILE PARALLEL RESTRICTED;

CREATE FUNCTION sys.ora_dbms_utility_db_version()
RETURNS text
AS 'MODULE_PATHNAME', 'ora_dbms_utility_db_version'
LANGUAGE C STABLE PARALLEL SAFE;

CREATE FUNCTION sys.ora_dbms_utility_db_compatibility()
RETURNS text
AS 'MODULE_PATHNAME', 'ora_dbms_utility_db_compatibility'
LANGUAGE C STABLE PARALLEL SAFE;

CREATE FUNCTION sys.ora_dbms_utility_get_hash_value(text, bigint, bigint)
RETURNS bigint
AS 'MODULE_PATHNAME', 'ora_dbms_utility_get_hash_value'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.ora_dbms_utility_comma_to_table(text)
RETURNS text[]
AS $$ SELECT array_agg(btrim(x)) FROM regexp_split_to_table($1, ',') AS _(x) $$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.ora_dbms_utility_table_to_comma(text[])
RETURNS text
AS $$ SELECT array_to_string($1, ',') $$
LANGUAGE SQL IMMUTABLE PARALLEL SAFE;

-- DBMS_UTILITY Package Definition
CREATE OR REPLACE PACKAGE dbms_utility IS
  FUNCTION FORMAT_ERROR_BACKTRACE RETURN TEXT;
  FUNCTION FORMAT_ERROR_STACK RETURN TEXT;
  FUNCTION FORMAT_CALL_STACK RETURN TEXT;

  FUNCTION GET_TIME RETURN NUMBER;
  PROCEDURE DB_VERSION(version OUT VARCHAR2, compatibility OUT VARCHAR2);
  FUNCTION GET_HASH_VALUE(name VARCHAR2, base NUMBER, hash_size NUMBER) RETURN NUMBER;
  PROCEDURE COMMA_TO_TABLE(list VARCHAR2, tablen OUT TEXT[]);
  PROCEDURE TABLE_TO_COMMA(tablen TEXT[], list OUT VARCHAR2);
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
    RETURN sys.ora_dbms_utility_get_time();
  END;

  PROCEDURE DB_VERSION(version OUT VARCHAR2, compatibility OUT VARCHAR2) IS
  BEGIN
    version := sys.ora_dbms_utility_db_version();
    compatibility := sys.ora_dbms_utility_db_compatibility();
  END;

  FUNCTION GET_HASH_VALUE(name VARCHAR2, base NUMBER, hash_size NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN sys.ora_dbms_utility_get_hash_value(name, base, hash_size);
  END;

  PROCEDURE COMMA_TO_TABLE(list VARCHAR2, tablen OUT TEXT[]) IS
  BEGIN
    tablen := sys.ora_dbms_utility_comma_to_table(list);
  END;

  PROCEDURE TABLE_TO_COMMA(tablen TEXT[], list OUT VARCHAR2) IS
  BEGIN
    list := sys.ora_dbms_utility_table_to_comma(tablen);
  END;
END dbms_utility;
