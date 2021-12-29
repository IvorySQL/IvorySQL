SET client_encoding = utf8;
set datestyle='ISO,MDY';
set time zone 'PRC';
set compatible_mode = 'oracle';

create table TBL_TEST(id int, dtime oracle.date);
insert into TBL_TEST values (1, '1921-07-01');
select * from TBL_TEST ;
drop table TBL_TEST;

select '11' + '2021-10-27 18:09:32'::oracle.date;
select '10000' + '2021-10-27 18:09:32'::oracle.date;
select '10000' + '2021-10-31 23:50:32'::oracle.date;
select '10000' + '2021-02-28 23:50:32'::oracle.date;

select '1921-07-01 12:13:16'::date + 1234.13;
select '1921-07-01 12:13:16'::date + 9999.9;
select '2021-08-01 12:13:16'::date + 8735.8;

select '2021-08-01 12:13:16'::date + '8735.8'::interval;
select '2021-08-01 12:13:16'::timestamp + '8735.8'::interval;

select '2021-08-01 12:13:16'::date + 123.123::numeric;
select '2021-08-01 12:13:16'::date + 123234::numeric;

select '2021-08-01 12:13:16'::date + '12345';
select '2021-08-01 12:13:16'::date + '123456789';

select '2021-08-01 12:13:16'::date + 123.1345678;
select '2021-08-01 12:13:16'::date + 555.552;

select 123.12 + '2021-10-28 09:07:15'::oracle.date;
select 990099 + '2021-10-28 09:07:15'::oracle.date;
select 99 + '2021-10-28 09:07:15'::oracle.date;

select 1234.123::numeric(7, 2) + '2021-10-28 09:10:22'::oracle.date;
select 10.123::numeric(7, 2) + '2021-10-28 09:10:22'::oracle.date;

select '10'::interval + '2021-10-28 09:10:22'::oracle.date;
select '10010'::interval + '2021-10-28 09:10:22'::oracle.date;

select 1.123456 + '2021-10-28 09:15:22'::oracle.date;
select 100.25631 + '2021-10-28 09:15:22'::oracle.date;

select '2021-10-28 09:15:22'::oracle.date - '1921-10-28 09:15:22'::oracle.date;
select '2021-10-28 09:15:22'::oracle.date - '1971-10-28 09:15:22'::oracle.date;

select '2021-10-28 09:15:22'::oracle.date - 123.223::numeric(7, 3);
select '2021-10-28 09:15:22'::oracle.date - 999::numeric(7, 3);

select '2021-10-28 09:15:22'::oracle.date - '999'::interval;
select '2029-10-28 09:15:22'::oracle.date - '999'::interval;

select '2029-10-28 09:15:22'::oracle.date - 999.1230;
select '1927-08-28 09:15:22'::oracle.date - 100.1230;
select '1927-08-28 09:15:22'::oracle.date - 100.123012324;

select '1922-12-11 13:14:15'::timestamptz < '1922-12-11 13:14:15'::oracle.date;
select '1922-12-11 13:14:14.1234'::timestamptz < '1922-12-11 13:14:15'::oracle.date;

select '1922-12-11 13:14:14.1234'::pg_catalog.date < '1922-12-11 13:14:15'::oracle.date;
select '2023-12-11 13:14:14.1234'::pg_catalog.date < '2022-12-11 13:14:15'::oracle.date;

select '2023-12-11 13:14:14.1234'::oracle.date < '2022-12-11 13:14:15'::oracle.date;
select '2023-12-11 13:14:14.1234'::oracle.date < '2022-12-11 13:14:15'::pg_catalog.date;
select '2023-12-11 13:14:14.1234'::oracle.date < '2024-12-11 13:14:15'::pg_catalog.date;
select '2023-12-11 13:14:14.1234'::oracle.date < '2023-12-11 13:14:14.1235'::pg_catalog.date;
select '2023-12-11 13:14:14.1234'::oracle.date < '2023-12-12 13:14:14.1235'::pg_catalog.date;

select '2023-12-11 13:14:14.1234'::oracle.date < '2023-12-12 13:14:14.1235'::timestamptz;
select '2023-12-12 13:14:14.1234'::oracle.date < '2023-12-12 13:14:14.1235'::timestamptz;
select '2023-12-12 13:14:14.1234'::oracle.date < '2023-12-12 13:14:14.1234'::timestamptz;
select '2023-12-12 14:14:14.1234'::oracle.date < '2023-12-12 13:14:14.1234'::timestamptz;

select '2023-12-12 14:14:14.1234'::pg_catalog.date < '2023-12-12 13:14:14.1234'::oracle.date;
select '2023-12-12 14:14:14.1234'::pg_catalog.date < '2021-12-12 13:14:14.1234'::oracle.date;
select '2023-12-12 14:14:14.1234'::pg_catalog.date < '2021-12-12 19:00:00'::oracle.date;

select '2023-12-12 14:14:14.1234'::pg_catalog.date <= '2021-12-12 19:00:00'::oracle.date;
select '2020-12-12 14:14:14.1234'::pg_catalog.date <= '2021-12-12 19:00:00'::oracle.date;
select '2020-12-12 14:14:14.1234'::pg_catalog.date <= '2020-12-12 19:00:00'::oracle.date;

select '2020-12-12 14:14:14.1234'::pg_catalog.date <= '2020-12-12 19:00:00'::timestamptz;
select '2020-12-12 22:14:14.1234'::pg_catalog.date <= '2020-12-12 19:00:00'::timestamptz;

select '2020-12-12 22:14:14.1234'::oracle.date <= '2020-12-12 19:00:00'::pg_catalog.date;
select '2020-12-12 22:14:14.1234'::oracle.date <= '2020-12-11 19:00:00'::pg_catalog.date;
select '2020-12-12 22:14:14.1234'::oracle.date <= '2020-12-15 19:00:00'::pg_catalog.date;

select '2021-10-28 22:14:14.1234'::timestamptz <= '2021-10-28 22:14:14.1234'::oracle.date;
select '2021-10-28 22:14:14'::timestamptz <= '2021-10-28 22:14:14.1234'::oracle.date;
select '2021-10-28 22:14:14'::timestamptz <= '2021-10-28 22:14:14'::oracle.date;

select '2021-10-28 22:14:14'::oracle.date <= '2021-10-28 22:14:14'::oracle.date;
select '2021-10-28 22:14:15'::oracle.date <= '2021-10-28 22:14:14'::oracle.date;

select '2021-10-28 22:14:14'::timestamptz <> '2021-10-28 22:14:12'::oracle.date;
select '2021-10-28 22:14:12'::timestamptz <> '2021-10-28 22:14:12'::oracle.date;

select '2021-10-28 22:14:12'::oracle.date <> '2021-10-28 22:14:12'::oracle.date;
select '2021-10-28 22:14:13'::oracle.date <> '2021-10-28 22:14:12'::oracle.date;

select '2021-10-28 22:14:13'::pg_catalog.date <> '2021-10-28 22:14:12'::oracle.date;
select '2021-10-28 22:14:12'::pg_catalog.date <> '2021-10-28 22:14:12'::oracle.date;

select '2021-10-28 22:14:12'::oracle.date <> '2021-10-28 22:14:12'::pg_catalog.date;
select '2021-10-28 22:14:12'::oracle.date <> '2021-10-28 22:14:12'::pg_catalog.date;
select '2021-10-29 21:10:00'::oracle.date <> '2021-10-28 22:14:12'::pg_catalog.date;

select '2021-10-29 21:10:00'::oracle.date <> '2021-10-28 22:14:12'::timestamptz;
select '2021-10-29 21:10:00'::oracle.date <> '2021-10-29 21:10:00'::timestamptz;

select '2021-10-29 21:10:00'::oracle.date = '2021-10-29 21:10:00'::timestamptz;
select '2021-10-29 21:10:00'::oracle.date = '2021-10-29 21:10:01'::timestamptz;

select '2021-10-29 21:10:00'::timestamptz = '2021-10-29 21:10:01'::oracle.date;
select '2021-10-29 21:10:00'::timestamptz = '2021-10-29 21:10:00'::oracle.date;

select '2021-10-29 21:10:00'::oracle.date = '2021-10-29 21:10:00'::oracle.date;
select '2021-10-29 21:10:00'::oracle.date = '2021-10-29 21:10:01'::oracle.date;

select '2021-10-29 21:10:00'::pg_catalog.date = '2021-10-29 21:10:01'::oracle.date;
select '2021-10-29 21:10:00'::pg_catalog.date = '2021-10-29 21:10:00'::oracle.date;

select '2021-10-29 21:10:00'::oracle.date = '2021-10-29 21:10:00'::pg_catalog.date;
select '2021-10-29 21:10:00'::oracle.date = '2021-10-29 21:10:01'::pg_catalog.date;

select '2021-10-29 21:10:00'::oracle.date > '2021-10-29 21:10:01'::oracle.date;
select '2021-10-29 21:10:00'::oracle.date > '2021-10-29 21:10:00'::oracle.date;

select '2021-10-29 21:10:00'::timestamptz > '2021-10-29 21:10:00'::oracle.date;
select '2021-10-29 21:10:00'::timestamptz > '2021-10-29 21:10:01'::oracle.date;

select '2021-10-29 21:10:00'::oracle.date > '2021-10-29 21:10:01'::timestamptz;
select '2021-10-29 21:10:00'::oracle.date > '2021-10-29 21:10:00'::timestamptz;

select '2021-10-29 21:10:00'::oracle.date > '2021-10-29 21:10:00'::pg_catalog.date;
select '2021-10-29 21:10:00'::oracle.date > '2021-10-29 21:10:01'::pg_catalog.date;

select '2021-10-29 21:10:00'::pg_catalog.date > '2021-10-29 21:10:01'::oracle.date;
select '2021-10-29 21:10:00'::pg_catalog.date > '2021-10-29 21:10:00'::oracle.date;

select '2021-10-29 21:10:00'::pg_catalog.date >= '2021-10-29 21:10:00'::oracle.date;
select '2021-10-29 21:10:00'::pg_catalog.date >= '2021-10-29 21:10:01'::oracle.date;

select '2021-10-29 21:10:00'::oracle.date >= '2021-10-29 21:10:01'::oracle.date;
select '2021-10-29 21:10:00'::oracle.date >= '2021-10-29 21:10:00'::oracle.date;

select '2021-10-29 21:10:00'::oracle.date >= '2021-10-29 21:10:00'::pg_catalog.date;
select '2021-10-29 21:10:00'::oracle.date >= '2021-10-29 21:10:01'::pg_catalog.date;
select '2021-10-30 21:10:00'::oracle.date >= '2021-10-29 21:10:01'::pg_catalog.date;
select '2021-10-28 21:10:00'::oracle.date >= '2021-10-29 21:10:01'::pg_catalog.date;

select '2021-10-28 21:10:00'::oracle.date >= '2021-10-29 21:10:01'::timestamptz;
select '2021-10-29 21:10:00'::oracle.date >= '2021-10-29 21:10:01'::timestamptz;
select '2021-10-29 21:10:00'::oracle.date >= '2021-10-29 21:10:00'::timestamptz;

select '2021-10-29 21:10:00'::timestamptz >= '2021-10-29 21:10:00'::oracle.date;
select '2021-10-29 21:10:00'::timestamptz >= '2021-10-29 21:10:01'::oracle.date;

select '2021-10-29 21:10:00'::oracle.date || '2021-10-28 21:09:00'::oracle.date;
select '2021-10-29 21:10:00'::oracle.date || ' '::text || '2021-10-28 21:09:00'::oracle.date;
select '2021-10-29 21:10:00'::oracle.date || ' before day is: : '::text || '2021-10-28 21:09:00'::oracle.date;


create table TBL_TEST(id int, dtime oracle.date);
insert into TBL_TEST values (1, '2021-10-29 21:10:00');
select * from TBL_TEST ;

select dtime || ' before day is: : '::text || '2021-10-28 21:09:00'::oracle.date from TBL_TEST;

drop table TBL_TEST;


CREATE TABLE DATE_TBL (f1 date);

INSERT INTO DATE_TBL VALUES ('1957-04-09');
INSERT INTO DATE_TBL VALUES ('1957-06-13');
INSERT INTO DATE_TBL VALUES ('1996-02-28');
INSERT INTO DATE_TBL VALUES ('1996-02-29');
INSERT INTO DATE_TBL VALUES ('1996-03-01');
INSERT INTO DATE_TBL VALUES ('1996-03-02');
INSERT INTO DATE_TBL VALUES ('1997-02-28');
INSERT INTO DATE_TBL VALUES ('1997-02-29');
INSERT INTO DATE_TBL VALUES ('1997-03-01');
INSERT INTO DATE_TBL VALUES ('1997-03-02');
INSERT INTO DATE_TBL VALUES ('2000-04-01');
INSERT INTO DATE_TBL VALUES ('2000-04-02');
INSERT INTO DATE_TBL VALUES ('2000-04-03');
INSERT INTO DATE_TBL VALUES ('2038-04-08');
INSERT INTO DATE_TBL VALUES ('2039-04-09');
INSERT INTO DATE_TBL VALUES ('2040-04-10');

SELECT f1 AS "Fifteen" FROM DATE_TBL;

SELECT f1 AS "Nine" FROM DATE_TBL WHERE f1 < '2000-01-01';

SELECT f1 AS "Three" FROM DATE_TBL
  WHERE f1 BETWEEN '2000-01-01' AND '2001-01-01';

SET datestyle TO iso;  -- display results in ISO

SET datestyle TO ymd;

SELECT date 'January 8, 1999';
SELECT date '1999-01-08';
SELECT date '1999-01-18';
SELECT date '1/8/1999';
SELECT date '1/18/1999';
SELECT date '18/1/1999';
SELECT date '01/02/03';
SELECT date '19990108';
SELECT date '990108';
SELECT date '1999.008';
SELECT date 'J2451187';
SELECT date 'January 8, 99 BC';

SELECT date '99-Jan-08';
SELECT date '1999-Jan-08';
SELECT date '08-Jan-99';
SELECT date '08-Jan-1999';
SELECT date 'Jan-08-99';
SELECT date 'Jan-08-1999';
SELECT date '99-08-Jan';
SELECT date '1999-08-Jan';

SELECT date '99 Jan 08';
SELECT date '1999 Jan 08';
SELECT date '08 Jan 99';
SELECT date '08 Jan 1999';
SELECT date 'Jan 08 99';
SELECT date 'Jan 08 1999';
SELECT date '99 08 Jan';
SELECT date '1999 08 Jan';

SELECT date '99-01-08';
SELECT date '1999-01-08';
SELECT date '08-01-99';
SELECT date '08-01-1999';
SELECT date '01-08-99';
SELECT date '01-08-1999';
SELECT date '99-08-01';
SELECT date '1999-08-01';

SELECT date '99 01 08';
SELECT date '1999 01 08';
SELECT date '08 01 99';
SELECT date '08 01 1999';
SELECT date '01 08 99';
SELECT date '01 08 1999';
SELECT date '99 08 01';
SELECT date '1999 08 01';

SET datestyle TO dmy;

SELECT date 'January 8, 1999';
SELECT date '1999-01-08';
SELECT date '1999-01-18';
SELECT date '1/8/1999';
SELECT date '1/18/1999';
SELECT date '18/1/1999';
SELECT date '01/02/03';
SELECT date '19990108';
SELECT date '990108';
SELECT date '1999.008';
SELECT date 'J2451187';
SELECT date 'January 8, 99 BC';

SELECT date '99-Jan-08';
SELECT date '1999-Jan-08';
SELECT date '08-Jan-99';
SELECT date '08-Jan-1999';
SELECT date 'Jan-08-99';
SELECT date 'Jan-08-1999';
SELECT date '99-08-Jan';
SELECT date '1999-08-Jan';

SELECT date '99 Jan 08';
SELECT date '1999 Jan 08';
SELECT date '08 Jan 99';
SELECT date '08 Jan 1999';
SELECT date 'Jan 08 99';
SELECT date 'Jan 08 1999';
SELECT date '99 08 Jan';
SELECT date '1999 08 Jan';

SELECT date '99-01-08';
SELECT date '1999-01-08';
SELECT date '08-01-99';
SELECT date '08-01-1999';
SELECT date '01-08-99';
SELECT date '01-08-1999';
SELECT date '99-08-01';
SELECT date '1999-08-01';

SELECT date '99 01 08';
SELECT date '1999 01 08';
SELECT date '08 01 99';
SELECT date '08 01 1999';
SELECT date '01 08 99';
SELECT date '01 08 1999';
SELECT date '99 08 01';
SELECT date '1999 08 01';

SET datestyle TO mdy;

SELECT date 'January 8, 1999';
SELECT date '1999-01-08';
SELECT date '1999-01-18';
SELECT date '1/8/1999';
SELECT date '1/18/1999';
SELECT date '18/1/1999';
SELECT date '01/02/03';
SELECT date '19990108';
SELECT date '990108';
SELECT date '1999.008';
SELECT date 'J2451187';
SELECT date 'January 8, 99 BC';

SELECT date '99-Jan-08';
SELECT date '1999-Jan-08';
SELECT date '08-Jan-99';
SELECT date '08-Jan-1999';
SELECT date 'Jan-08-99';
SELECT date 'Jan-08-1999';
SELECT date '99-08-Jan';
SELECT date '1999-08-Jan';

SELECT date '99 Jan 08';
SELECT date '1999 Jan 08';
SELECT date '08 Jan 99';
SELECT date '08 Jan 1999';
SELECT date 'Jan 08 99';
SELECT date 'Jan 08 1999';
SELECT date '99 08 Jan';
SELECT date '1999 08 Jan';

SELECT date '99-01-08';
SELECT date '1999-01-08';
SELECT date '08-01-99';
SELECT date '08-01-1999';
SELECT date '01-08-99';
SELECT date '01-08-1999';
SELECT date '99-08-01';
SELECT date '1999-08-01';

SELECT date '99 01 08';
SELECT date '1999 01 08';
SELECT date '08 01 99';
SELECT date '08 01 1999';
SELECT date '01 08 99';
SELECT date '01 08 1999';
SELECT date '99 08 01';
SELECT date '1999 08 01';

-- Check upper and lower limits of date range
SELECT date '4714-11-24 BC';
SELECT date '4714-11-23 BC';  -- out of range
SELECT date '5874897-12-31';
SELECT date '5874898-01-01';  -- out of range

RESET datestyle;

--
-- Simple math
-- Leave most of it for the horology tests
--

SELECT f1 - date '2000-01-01' AS "Days From 2K" FROM DATE_TBL;

SELECT f1 - date 'epoch' AS "Days From Epoch" FROM DATE_TBL;

SELECT date 'yesterday' - date 'today' AS "One day";

SELECT date 'today' - date 'tomorrow' AS "One day";

SELECT date 'yesterday' - date 'tomorrow' AS "Two days";

SELECT date 'tomorrow' - date 'today' AS "One day";

SELECT date 'today' - date 'yesterday' AS "One day";

SELECT date 'tomorrow' - date 'yesterday' AS "Two days";

--
-- test extract!
--
-- epoch
--
SELECT EXTRACT(EPOCH FROM DATE        '1970-01-01');     --  0
SELECT EXTRACT(EPOCH FROM TIMESTAMP   '1970-01-01');     --  0
SELECT EXTRACT(EPOCH FROM TIMESTAMPTZ '1970-01-01+00');  --  0
--
-- century
--

SELECT EXTRACT(CENTURY FROM DATE '0101-12-31 BC'); -- -2
SELECT EXTRACT(CENTURY FROM DATE '0100-12-31 BC'); -- -1
SELECT EXTRACT(CENTURY FROM DATE '0001-12-31 BC'); -- -1
SELECT EXTRACT(CENTURY FROM DATE '0001-01-01');    --  1
SELECT EXTRACT(CENTURY FROM DATE '0001-01-01 AD'); --  1
SELECT EXTRACT(CENTURY FROM DATE '1900-12-31');    -- 19
SELECT EXTRACT(CENTURY FROM DATE '1901-01-01');    -- 20
SELECT EXTRACT(CENTURY FROM DATE '2000-12-31');    -- 20
SELECT EXTRACT(CENTURY FROM DATE '2001-01-01');    -- 21
SELECT EXTRACT(CENTURY FROM CURRENT_DATE)>=21 AS True;     -- true
--
-- millennium
--
SELECT EXTRACT(MILLENNIUM FROM DATE '0001-12-31 BC'); -- -1
SELECT EXTRACT(MILLENNIUM FROM DATE '0001-01-01 AD'); --  1
SELECT EXTRACT(MILLENNIUM FROM DATE '1000-12-31');    --  1
SELECT EXTRACT(MILLENNIUM FROM DATE '1001-01-01');    --  2
SELECT EXTRACT(MILLENNIUM FROM DATE '2000-12-31');    --  2
SELECT EXTRACT(MILLENNIUM FROM DATE '2001-01-01');    --  3
-- next test to be fixed on the turn of the next millennium;-)
SELECT EXTRACT(MILLENNIUM FROM CURRENT_DATE);         --  3
--
-- decade
--
SELECT EXTRACT(DECADE FROM DATE '1994-12-25');    -- 199
SELECT EXTRACT(DECADE FROM DATE '0010-01-01');    --   1
SELECT EXTRACT(DECADE FROM DATE '0009-12-31');    --   0
SELECT EXTRACT(DECADE FROM DATE '0001-01-01 BC'); --   0
SELECT EXTRACT(DECADE FROM DATE '0002-12-31 BC'); --  -1
SELECT EXTRACT(DECADE FROM DATE '0011-01-01 BC'); --  -1
SELECT EXTRACT(DECADE FROM DATE '0012-12-31 BC'); --  -2
--
-- some other types:
--
-- on a timestamp.
SELECT EXTRACT(CENTURY FROM NOW())>=21 AS True;       -- true
SELECT EXTRACT(CENTURY FROM TIMESTAMP '1970-03-20 04:30:00.00000'); -- 20
-- on an interval
SELECT EXTRACT(CENTURY FROM INTERVAL '100 y');  -- 1
SELECT EXTRACT(CENTURY FROM INTERVAL '99 y');   -- 0
SELECT EXTRACT(CENTURY FROM INTERVAL '-99 y');  -- 0
SELECT EXTRACT(CENTURY FROM INTERVAL '-100 y'); -- -1
--
-- test trunc function!
--
set datestyle='ISO,MDY';
SELECT DATE_TRUNC('MILLENNIUM', TIMESTAMP '1970-03-20 04:30:00.00000'); -- 1001
SELECT DATE_TRUNC('MILLENNIUM', DATE '1970-03-20'); -- 1001-01-01
SELECT DATE_TRUNC('CENTURY', TIMESTAMP '1970-03-20 04:30:00.00000'); -- 1901
SELECT DATE_TRUNC('CENTURY', DATE '1970-03-20'); -- 1901
SELECT DATE_TRUNC('CENTURY', DATE '2004-08-10'); -- 2001-01-01
SELECT DATE_TRUNC('CENTURY', DATE '0002-02-04'); -- 0001-01-01
SELECT DATE_TRUNC('CENTURY', DATE '0055-08-10 BC'); -- 0100-01-01 BC
SELECT DATE_TRUNC('DECADE', DATE '1993-12-25'); -- 1990-01-01
SELECT DATE_TRUNC('DECADE', DATE '0004-12-25'); -- 0001-01-01 BC
SELECT DATE_TRUNC('DECADE', DATE '0002-12-31 BC'); -- 0011-01-01 BC
--
-- test infinity
--
select 'infinity'::date, '-infinity'::date;
select 'infinity'::date > 'today'::date as t;
select '-infinity'::date < 'today'::date as t;
select isfinite('infinity'::date), isfinite('-infinity'::date), isfinite('today'::date);
--
-- oscillating fields from non-finite date/timestamptz:
--
SELECT EXTRACT(HOUR FROM DATE 'infinity');      -- NULL
SELECT EXTRACT(HOUR FROM DATE '-infinity');     -- NULL
SELECT EXTRACT(HOUR FROM TIMESTAMP   'infinity');      -- NULL
SELECT EXTRACT(HOUR FROM TIMESTAMP   '-infinity');     -- NULL
SELECT EXTRACT(HOUR FROM TIMESTAMPTZ 'infinity');      -- NULL
SELECT EXTRACT(HOUR FROM TIMESTAMPTZ '-infinity');     -- NULL
-- all possible fields
SELECT EXTRACT(MICROSECONDS  FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(MILLISECONDS  FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(SECOND        FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(MINUTE        FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(HOUR          FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(DAY           FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(MONTH         FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(QUARTER       FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(WEEK          FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(DOW           FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(ISODOW        FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(DOY           FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(TIMEZONE      FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(TIMEZONE_M    FROM DATE 'infinity');    -- NULL
SELECT EXTRACT(TIMEZONE_H    FROM DATE 'infinity');    -- NULL
--
-- monotonic fields from non-finite date/timestamptz:
--
SELECT EXTRACT(EPOCH FROM DATE 'infinity');         --  Infinity
SELECT EXTRACT(EPOCH FROM DATE '-infinity');        -- -Infinity
SELECT EXTRACT(EPOCH FROM TIMESTAMP   'infinity');  --  Infinity
SELECT EXTRACT(EPOCH FROM TIMESTAMP   '-infinity'); -- -Infinity
SELECT EXTRACT(EPOCH FROM TIMESTAMPTZ 'infinity');  --  Infinity
SELECT EXTRACT(EPOCH FROM TIMESTAMPTZ '-infinity'); -- -Infinity
-- all possible fields
SELECT EXTRACT(YEAR       FROM DATE 'infinity');    --  Infinity
SELECT EXTRACT(DECADE     FROM DATE 'infinity');    --  Infinity
SELECT EXTRACT(CENTURY    FROM DATE 'infinity');    --  Infinity
SELECT EXTRACT(MILLENNIUM FROM DATE 'infinity');    --  Infinity
SELECT EXTRACT(JULIAN     FROM DATE 'infinity');    --  Infinity
SELECT EXTRACT(ISOYEAR    FROM DATE 'infinity');    --  Infinity
SELECT EXTRACT(EPOCH      FROM DATE 'infinity');    --  Infinity
--
-- wrong fields from non-finite date:
--
SELECT EXTRACT(MICROSEC  FROM DATE 'infinity');     -- ERROR:  timestamp units "microsec" not recognized

-- test constructors
select make_date(2013, 7, 15);
select make_date(-44, 3, 15);
select make_time(8, 20, 0.0);
-- should fail
select make_date(2013, 2, 30);
select make_date(2013, 13, 1);
select make_date(2013, 11, -1);
select make_time(10, 55, 100.1);
select make_time(24, 0, 2.1);

DROP TABLE DATE_TBL;
