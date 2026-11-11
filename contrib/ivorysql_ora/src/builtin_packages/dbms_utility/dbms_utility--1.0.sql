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

  /* The database version banner, and a bit test. */
  FUNCTION DB_VERSION RETURN TEXT;
  FUNCTION IS_BIT_SET(VALUE NUMBER, BIT_IN_POSITION NUMBER) RETURN BOOLEAN;

  /* Canonical form of an object name: unquoted names upper-cased, without
   * surrounding blanks, plus its length. */
  PROCEDURE CANONICALIZE(NAME TEXT, CANON_NAME OUT TEXT, CANON_LEN OUT INTEGER);

  /* ANALYZE every table in every user schema. */
  PROCEDURE ANALYZE_DATABASE(METHOD TEXT DEFAULT 'COMPUTE',
    ESTIMATE_PERCENT NUMBER DEFAULT 100,
    METHOD_OPT TEXT DEFAULT 'FOR ALL COLUMNS SIZE AUTO');

  /* Resolve an object name the way Oracle does: schema and object parts,
   * object type and OID.  A dblink part is reported as absent. */
  PROCEDURE NAME_RESOLVE(NAME TEXT, CONTEXT INTEGER,
    SCHEMA OUT TEXT, PART1 OUT TEXT, PART2 OUT TEXT, DBLINK OUT TEXT,
    PART1_TYPE OUT INTEGER, OBJECT_NUMBER OUT INTEGER);

  /* Report the objects TYPE refers to (Oracle prints one per line through
   * DBMS_OUTPUT; the string is returned here so callers can inspect it). */
  PROCEDURE GET_DEPENDENCY(P_TYPE TEXT, P_SCHEMA TEXT, P_NAME TEXT);

  /* Split a comma-separated list into an array of trimmed names. */
  PROCEDURE COMMA_TO_TABLE(LIST TEXT, TABLEN OUT INTEGER, TAB OUT TEXT[]);

  /* Join an array of names into a comma-separated list. */
  PROCEDURE TABLE_TO_COMMA(TAB TEXT[], TABLEN OUT INTEGER, LIST OUT TEXT);

  /* ANALYZE every table in a schema. */
  PROCEDURE ANALYZE_SCHEMA(SCHEMANAME TEXT);

  /* PostgreSQL has nothing to recompile, so this validates the schema name
   * and returns, which is what Oracle callers rely on it for. */
  PROCEDURE COMPILE_SCHEMA(SCHEMANAME TEXT);

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

  PROCEDURE CANONICALIZE(NAME TEXT, CANON_NAME OUT TEXT, CANON_LEN OUT INTEGER) IS
  BEGIN
    CANON_NAME := pg_catalog.upper(pg_catalog.btrim(NAME));
    CANON_LEN := pg_catalog.length(CANON_NAME);
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
