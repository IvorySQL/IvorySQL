-- Upgrade path for the new sys.median aggregate.
-- New installs receive these objects from builtin_functions--1.0.sql and,
-- because CREATE EXTENSION reaches version 1.1 by running the 1.0 script
-- followed by this one, re-execute this script right after creating them;
-- existing 1.0 installations, which do not have the objects at all, run it
-- through ALTER EXTENSION ivorysql_ora UPDATE TO '1.1'.  The statements
-- below are therefore written to work in both contexts: the functions use
-- CREATE OR REPLACE (harmless re-execution for fresh installs, creation
-- for upgraded ones), and the aggregate is dropped if present before it
-- is created (CREATE AGGREGATE has no OR REPLACE form).
-- These objects are new in this version, so no guards against
-- incompatible pre-existing definitions are needed here.

CREATE OR REPLACE FUNCTION sys.median_transfn(sys.number[], sys.number)
RETURNS sys.number[]
LANGUAGE sql
IMMUTABLE
CALLED ON NULL INPUT
PARALLEL SAFE
AS $$ SELECT CASE WHEN $2 IS NULL THEN $1
                  ELSE pg_catalog.array_append($1, $2) END $$;

CREATE OR REPLACE FUNCTION sys.median_finalfn(sys.number[])
RETURNS sys.number
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $$
    SELECT CASE WHEN n = 0 THEN NULL
                WHEN n % 2 = 1 THEN v[(n + 1) / 2]
                ELSE pg_catalog.trim_scale(
                       ((v[n / 2] OPERATOR(sys.+) v[n / 2 + 1]) OPERATOR(sys.*) 0.5::sys.number)
                       ::pg_catalog.numeric)::sys.number END
    FROM (SELECT array_agg(x ORDER BY x) AS v, count(*)::int AS n
          FROM unnest($1) AS t(x) WHERE x IS NOT NULL) s
$$;

DROP AGGREGATE IF EXISTS sys.median(sys.number);
CREATE AGGREGATE sys.median(sys.number) (
    SFUNC = sys.median_transfn,
    STYPE = sys.number[],
    FINALFUNC = sys.median_finalfn,
    COMBINEFUNC = pg_catalog.array_cat,
    INITCOND = '{}',
    PARALLEL = SAFE
);
