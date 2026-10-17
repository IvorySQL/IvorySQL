-- Timestamp differences can exceed the int64 microsecond range used by
-- PostgreSQL intervals even when both input timestamps are finite.
SET TIME ZONE 'UTC';

SELECT sys.oratimestamp_mi(
           pg_catalog.timestamp '294000-01-01'::sys.oratimestamp,
           pg_catalog.timestamp '1000-01-01'::sys.oratimestamp);

SELECT sys.oratimestamp_mi(
           pg_catalog.timestamp '1000-01-01'::sys.oratimestamp,
           pg_catalog.timestamp '294000-01-01'::sys.oratimestamp);

-- The SQL subtraction operator reaches the same interval overflow path.
SELECT pg_catalog.timestamp '294000-01-01'::sys.oratimestamp
       OPERATOR(sys.-)
       pg_catalog.timestamp '1000-01-01'::sys.oratimestamp;

-- Oracle DATE subtraction returns a NUMBER, so preserve the wide difference.
SELECT sys.oradate_mi(
           pg_catalog.date '294000-01-01'::sys.oradate,
           pg_catalog.date '1000-01-01'::sys.oradate) > 100000000;

SELECT sys.oradate_mi(
           pg_catalog.date '1000-01-01'::sys.oradate,
           pg_catalog.date '294000-01-01'::sys.oradate) < -100000000;

SELECT sys.oradate_mi(
           pg_catalog.date '2000-01-02'::sys.oradate,
           pg_catalog.date '2000-01-01'::sys.oradate) = 1;

-- DATE subtraction through the operator must keep the large NUMBER result.
SELECT (pg_catalog.date '294000-01-01'::sys.oradate
        OPERATOR(sys.-)
        pg_catalog.date '1000-01-01'::sys.oradate) > 100000000;

SELECT sys.oradate_mi_oratimestampltz(
           pg_catalog.date '294000-01-01'::sys.oradate,
           pg_catalog.timestamptz '1000-01-01 00:00:00+00'::sys.oratimestamptz);

SELECT sys.oradate_mi_oratimestampltz(
           pg_catalog.date '1000-01-01'::sys.oradate,
           pg_catalog.timestamptz '294000-01-01 00:00:00+00'::sys.oratimestamptz);

SELECT sys.oratimestampltz_mi_oradate(
           sys.oratimestamp_oratimestampltz(
               pg_catalog.timestamp '294000-01-01 00:00:00'::sys.oratimestamp),
           pg_catalog.date '1000-01-01'::sys.oradate);

SELECT sys.oratimestampltz_mi_oradate(
           sys.oratimestamp_oratimestampltz(
               pg_catalog.timestamp '1000-01-01 00:00:00'::sys.oratimestamp),
           pg_catalog.date '294000-01-01'::sys.oradate);

-- A representable difference near the upper timestamp boundary still works.
SELECT sys.oratimestamp_mi(
           pg_catalog.timestamp '294000-01-02'::sys.oratimestamp,
           pg_catalog.timestamp '294000-01-01'::sys.oratimestamp) IS NOT NULL;

RESET TIME ZONE;
