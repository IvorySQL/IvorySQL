--
-- Statement level tracking
--

SET pg_stat_statements.track_utility = TRUE;
SELECT pg_stat_statements_reset();

-- DO block - top-level tracking.
CREATE TABLE stats_track_tab (x int);
SET pg_stat_statements.track = 'top';
DELETE FROM stats_track_tab;
DO $$
BEGIN
  DELETE FROM stats_track_tab;
END;
$$ LANGUAGE plpgsql;
SELECT toplevel, calls, query FROM pg_stat_statements
  WHERE query LIKE '%DELETE%' ORDER BY query COLLATE "C", toplevel;
SELECT pg_stat_statements_reset();

-- DO block - all-level tracking.
SET pg_stat_statements.track = 'all';
DELETE FROM stats_track_tab;
DO $$
BEGIN
  DELETE FROM stats_track_tab;
END; $$;
DO LANGUAGE plpgsql $$
BEGIN
  -- this is a SELECT
  PERFORM 'hello world'::TEXT;
END; $$;
SELECT toplevel, calls, query FROM pg_stat_statements
  ORDER BY query COLLATE "C", toplevel;

-- PL/pgSQL function - top-level tracking.
SET pg_stat_statements.track = 'top';
SET pg_stat_statements.track_utility = FALSE;
SELECT pg_stat_statements_reset();
CREATE FUNCTION PLUS_TWO(i INTEGER) RETURNS INTEGER AS $$
DECLARE
  r INTEGER;
BEGIN
  SELECT (i + 1 + 1.0)::INTEGER INTO r;
  RETURN r;
END; $$ LANGUAGE plpgsql;

SELECT PLUS_TWO(3);
SELECT PLUS_TWO(7);

-- SQL function --- use LIMIT to keep it from being inlined
CREATE FUNCTION PLUS_ONE(i INTEGER) RETURNS INTEGER AS
$$ SELECT (i + 1.0)::INTEGER LIMIT 1 $$ LANGUAGE SQL;

SELECT PLUS_ONE(8);
SELECT PLUS_ONE(10);

SELECT calls, rows, query FROM pg_stat_statements ORDER BY query COLLATE "C";

-- PL/pgSQL function - all-level tracking.
SET pg_stat_statements.track = 'all';
SELECT pg_stat_statements_reset();

-- we drop and recreate the functions to avoid any caching funnies
DROP FUNCTION PLUS_ONE(INTEGER);
DROP FUNCTION PLUS_TWO(INTEGER);

-- PL/pgSQL function
CREATE FUNCTION PLUS_TWO(i INTEGER) RETURNS INTEGER AS $$
DECLARE
  r INTEGER;
BEGIN
  SELECT (i + 1 + 1.0)::INTEGER INTO r;
  RETURN r;
END; $$ LANGUAGE plpgsql;

SELECT PLUS_TWO(-1);
SELECT PLUS_TWO(2);

-- SQL function --- use LIMIT to keep it from being inlined
CREATE FUNCTION PLUS_ONE(i INTEGER) RETURNS INTEGER AS
$$ SELECT (i + 1.0)::INTEGER LIMIT 1 $$ LANGUAGE SQL;

SELECT PLUS_ONE(3);
SELECT PLUS_ONE(1);

SELECT calls, rows, query FROM pg_stat_statements ORDER BY query COLLATE "C";
DROP FUNCTION PLUS_ONE(INTEGER);

--
-- pg_stat_statements.track = none
--
SET pg_stat_statements.track = 'none';
SELECT pg_stat_statements_reset();

SELECT 1 AS "one";
SELECT 1 + 1 AS "two";

SELECT calls, rows, query FROM pg_stat_statements ORDER BY query COLLATE "C";
SELECT pg_stat_statements_reset();
