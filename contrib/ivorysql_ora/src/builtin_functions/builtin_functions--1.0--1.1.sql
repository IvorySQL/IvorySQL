-- Upgrade path for the TO_CHAR volatility fix.
-- New installs receive STABLE directly from builtin_functions--1.0.sql, while
-- existing 1.0 installations keep their old IMMUTABLE definitions until this
-- script is applied with ALTER EXTENSION ivorysql_ora UPDATE TO '1.1'.

-- Guard against pre-existing expression indexes built while these overloads
-- were IMMUTABLE.  Changing only the volatility metadata leaves those indexes
-- in place, but their keys are session-dependent, so they can become stale or
-- missing after NLS/timezone settings change.  Fail with an actionable error
-- instead of silently upgrading the function volatility.
DO $$
DECLARE
    bad RECORD;
BEGIN
    FOR bad IN
        SELECT n.nspname AS schema_name, c.relname AS index_name
        FROM pg_depend AS d
        JOIN pg_class AS c
          ON c.oid = d.objid
         AND c.relkind = 'i'
        JOIN pg_namespace AS n
          ON n.oid = c.relnamespace
        WHERE d.classid = 'pg_class'::regclass
          AND d.refclassid = 'pg_proc'::regclass
          AND d.deptype = 'n'
          AND d.refobjid IN (
              'sys.to_char(sys.oradate)'::regprocedure,
              'sys.to_char(sys.oradate,text)'::regprocedure,
              'sys.to_char(sys.oradate,text,text)'::regprocedure,
              'sys.to_char(sys.oratimestamp)'::regprocedure,
              'sys.to_char(sys.oratimestamp,text)'::regprocedure,
              'sys.to_char(sys.oratimestamp,text,text)'::regprocedure,
              'sys.to_char(sys.oratimestamptz)'::regprocedure,
              'sys.to_char(sys.oratimestamptz,text)'::regprocedure,
              'sys.to_char(sys.oratimestamptz,text,text)'::regprocedure,
              'sys.to_char(sys.oratimestampltz)'::regprocedure,
              'sys.to_char(sys.oratimestampltz,text)'::regprocedure,
              'sys.to_char(sys.oratimestampltz,text,text)'::regprocedure
          )
        ORDER BY 1, 2
    LOOP
        RAISE EXCEPTION 'cannot upgrade ivorysql_ora: expression index %.% depends on sys.to_char overloads whose volatility changes from IMMUTABLE to STABLE; drop the index or replace the expression with an immutable form, then retry ALTER EXTENSION ivorysql_ora UPDATE',
            bad.schema_name, bad.index_name;
    END LOOP;
END$$;

ALTER FUNCTION sys.to_char(sys.oradate) STABLE;
ALTER FUNCTION sys.to_char(sys.oradate, text) STABLE;
ALTER FUNCTION sys.to_char(sys.oradate, text, text) STABLE;

ALTER FUNCTION sys.to_char(sys.oratimestamp) STABLE;
ALTER FUNCTION sys.to_char(sys.oratimestamp, text) STABLE;
ALTER FUNCTION sys.to_char(sys.oratimestamp, text, text) STABLE;

ALTER FUNCTION sys.to_char(sys.oratimestamptz) STABLE;
ALTER FUNCTION sys.to_char(sys.oratimestamptz, text) STABLE;
ALTER FUNCTION sys.to_char(sys.oratimestamptz, text, text) STABLE;

ALTER FUNCTION sys.to_char(sys.oratimestampltz) STABLE;
ALTER FUNCTION sys.to_char(sys.oratimestampltz, text) STABLE;
ALTER FUNCTION sys.to_char(sys.oratimestampltz, text, text) STABLE;
