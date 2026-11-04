--
-- Test that bare INTERVAL (without a field qualifier such as
-- YEAR TO MONTH or DAY TO SECOND) keeps working in Oracle parser
-- mode.  A bare INTERVAL is standard PostgreSQL syntax (e.g.
-- '2 days'::interval); it falls back to the built-in interval type,
-- while the qualified Oracle forms still map to the Oracle interval
-- types sys.yminterval / sys.dsinterval.
--
SET ivorysql.compatible_mode = oracle;

-- text input via cast (the '2 days'::interval use case)
SELECT '2 days'::interval;
SELECT '2 days'::interval, '-1 days +02:03'::interval;
SELECT '1.5 weeks'::interval AS "Ten days twelve hours";
SELECT '256 microseconds'::interval * (2^55)::float8;
SELECT '{1 day, 2 days}'::interval[];

-- text input via INTERVAL literal (SQL99 syntax)
SELECT INTERVAL '2 days';
SELECT INTERVAL '01:00' AS "One hour";
SELECT INTERVAL (3) '1.5';
SELECT INTERVAL '1-2';

-- bare INTERVAL type name in type and DDL contexts
SELECT '1 year 2 mons'::interval::text;
CREATE TABLE interval_bare_oracle (a interval, b interval[]);
INSERT INTO interval_bare_oracle VALUES ('2 days', '{1 day, 2 days}');
SELECT a, b FROM interval_bare_oracle;
DROP TABLE interval_bare_oracle;
CREATE FUNCTION interval_bare_oracle_func(interval) RETURNS interval
LANGUAGE SQL AS $$ SELECT $1 $$;
/
SELECT interval_bare_oracle_func('2 days');
DROP FUNCTION interval_bare_oracle_func(interval);

-- qualified Oracle forms must still map to the Oracle interval types
SELECT INTERVAL '2' DAY;
SELECT INTERVAL '2023-01' YEAR(4) TO MONTH;
SELECT INTERVAL '-1 12:00:00' DAY(2) TO SECOND;

SET ivorysql.compatible_mode = pg;