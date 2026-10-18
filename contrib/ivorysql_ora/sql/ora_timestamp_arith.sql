-- Follow PostgreSQL timestamp subtraction when the intermediate int64
-- microsecond difference overflows, even when both inputs are finite.
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
           pg_catalog.date '1000-01-01'::sys.oradate) = 107016052;

SELECT sys.oradate_mi(
           pg_catalog.date '1000-01-01'::sys.oradate,
           pg_catalog.date '294000-01-01'::sys.oradate) = -107016052;

SELECT sys.oradate_mi(
           pg_catalog.date '2000-01-02'::sys.oradate,
           pg_catalog.date '2000-01-01'::sys.oradate) = 1;

-- DATE subtraction through the operator must keep the large NUMBER result.
SELECT (pg_catalog.date '294000-01-01'::sys.oradate
        OPERATOR(sys.-)
        pg_catalog.date '1000-01-01'::sys.oradate) = 107016052;

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
           pg_catalog.timestamp '294000-01-01'::sys.oratimestamp) AS one_day;

SELECT sys.oratimestamp_mi(
           pg_catalog.timestamp '294000-01-01'::sys.oratimestamp,
           pg_catalog.timestamp '294000-01-02'::sys.oratimestamp) AS negative_one_day;

-- Subtract small DATE differences before converting them to floating point.
SELECT sys.oradate_mi(
           pg_catalog.timestamp '294000-01-01 00:00:01'::sys.oratimestamp::sys.oradate,
           pg_catalog.timestamp '294000-01-01 00:00:00'::sys.oratimestamp::sys.oradate)
       AS one_second_in_days;

RESET TIME ZONE;
