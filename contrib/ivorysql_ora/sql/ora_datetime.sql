--
-- ORADATE
--

--build tables and test 'nls_date_format' parameter, don't do the validity check.
CREATE TABLE TEST_DATE(a date);

SET NLS_DATE_FORMAT='YYYY-MM-DD';

INSERT INTO TEST_DATE VALUES('1990-1-19');

INSERT INTO TEST_DATE VALUES('1990-1-19 11:11:11');		-- hour/minute/second is zero 

SELECT * FROM TEST_DATE;


DELETE FROM TEST_DATE;

set nls_date_format='YYYY-MM-DD HH24:MI:SS';

INSERT INTO TEST_DATE VALUES('1990-2-19');				-- hour/minute/second is zero 	

INSERT INTO TEST_DATE VALUES('1990-2-19 11:11:11');

SELECT * FROM TEST_DATE;


-- check for leap year
INSERT INTO TEST_DATE VALUES('1989-2-30');

INSERT INTO TEST_DATE VALUES('1989-2-29');

INSERT INTO TEST_DATE VALUES('1989-2-28');

INSERT INTO TEST_DATE VALUES('2000-2-30');

INSERT INTO TEST_DATE VALUES('2000-2-29');

INSERT INTO TEST_DATE VALUES('2000-2-28');


-- The ANSI date literal contains no time portion, and must be specified in the format 'YYYY-MM-DD'
SELECT DATE'1990-1-1';

SELECT DATE'1990-1-1 11:11:11';			-- hour/minute/second is zero 


-- Comparison operator
DELETE FROM TEST_DATE;

set nls_date_format='YYYY-MM-DD HH24:MI:SS';

INSERT INTO TEST_DATE VALUES('2016-11-24');

INSERT INTO TEST_DATE VALUES('2016-11-24 11:00:00');

INSERT INTO TEST_DATE VALUES('2016-11-24 11:11:11');

INSERT INTO TEST_DATE VALUES('2016-11-25');

INSERT INTO TEST_DATE VALUES('2016-11-25 11:00:00');

INSERT INTO TEST_DATE VALUES('2016-11-25 11:11:11');


-- date/date
SELECT * FROM TEST_DATE WHERE A = '2016-11-24';

SELECT * FROM TEST_DATE WHERE A <> '2016-11-24';

SELECT * FROM TEST_DATE WHERE A > '2016-11-24';

SELECT * FROM TEST_DATE WHERE A >= '2016-11-24';

SELECT * FROM TEST_DATE WHERE A < '2016-11-24';

SELECT * FROM TEST_DATE WHERE A <= '2016-11-24';


-- date/timestamp
SELECT * FROM TEST_DATE WHERE A = TIMESTAMP'2016-11-24 00:00:00';

SELECT * FROM TEST_DATE WHERE A <> TIMESTAMP'2016-11-24 00:00:00';

SELECT * FROM TEST_DATE WHERE A > TIMESTAMP'2016-11-24 00:00:00';

SELECT * FROM TEST_DATE WHERE A >= TIMESTAMP'2016-11-24 00:00:00';

SELECT * FROM TEST_DATE WHERE A < TIMESTAMP'2016-11-24 00:00:00';

SELECT * FROM TEST_DATE WHERE A <= TIMESTAMP'2016-11-24 00:00:00';


-- date/timestamp with time zone
SELECT * FROM TEST_DATE WHERE A = TIMESTAMP'2016-11-24 00:00:00 +04:00';

SELECT * FROM TEST_DATE WHERE A <> TIMESTAMP'2016-11-24 00:00:00 +04:00';

SELECT * FROM TEST_DATE WHERE A > TIMESTAMP'2016-11-24 00:00:00 +04:00';

SELECT * FROM TEST_DATE WHERE A >= TIMESTAMP'2016-11-24 00:00:00 +04:00';

SELECT * FROM TEST_DATE WHERE A < TIMESTAMP'2016-11-24 00:00:00 +04:00';

SELECT * FROM TEST_DATE WHERE A <= TIMESTAMP'2016-11-24 00:00:00 +04:00';


-- date/timestamp with local time zone
SELECT * FROM TEST_DATE WHERE A = TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_DATE WHERE A <> TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_DATE WHERE A > TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_DATE WHERE A >= TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_DATE WHERE A < TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_DATE WHERE A <= TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;


-- AGGREGATE
SELECT MAX(a) FROM TEST_DATE;

SELECT MIN(a) FROM TEST_DATE;


-- index 
CREATE INDEX TEST_DATE_BTREE ON TEST_DATE (A);

CREATE INDEX TEST_DATE_HASH ON TEST_DATE USING HASH (A);

CREATE INDEX TEST_DATE_BRIN ON TEST_DATE USING BRIN (A);


--
-- ORATIMESTAMP
--

-- The default precision of fractional second is 6.
-- Build tables and test 'NLS_TIMESTAMP_FORMAT' parameter, don't do the validity check.
CREATE TABLE TEST_TIMESTAMP(a TIMESTAMP);

SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS.FF9';

-- effective number of fractional seconds is 6,the part of excess is 0
INSERT INTO TEST_TIMESTAMP VALUES('1990-1-19 11:11:11.123456789');

INSERT INTO TEST_TIMESTAMP VALUES('1990-2-19');		-- hour、minute、second、fractional second is zero.

INSERT INTO TEST_TIMESTAMP VALUES('1990-2-19 11:11:11');

SELECT * FROM TEST_TIMESTAMP;


-- check for leap year
INSERT INTO TEST_TIMESTAMP VALUES('1989-2-30');

INSERT INTO TEST_TIMESTAMP VALUES('1989-2-29');

INSERT INTO TEST_TIMESTAMP VALUES('1989-2-28');

INSERT INTO TEST_TIMESTAMP VALUES('2000-2-30');

INSERT INTO TEST_TIMESTAMP VALUES('2000-2-29');

INSERT INTO TEST_TIMESTAMP VALUES('2000-2-28');


-- TIMESTAMP literal
SELECT TIMESTAMP'1990-1-1';		-- ERROR 

SELECT TIMESTAMP'1990-1-1 11:11:11';


-- Comparison operator
DELETE FROM TEST_TIMESTAMP;

SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS.FF9';

INSERT INTO TEST_TIMESTAMP VALUES('2016-11-24 11:00:00');

INSERT INTO TEST_TIMESTAMP VALUES('2016-11-24 11:00:00.123456789');

INSERT INTO TEST_TIMESTAMP VALUES('2016-11-24 11:11:11');

INSERT INTO TEST_TIMESTAMP VALUES('2016-11-25 11:00:00');

INSERT INTO TEST_TIMESTAMP VALUES('2016-11-25 11:00:00.123456789');

INSERT INTO TEST_TIMESTAMP VALUES('2016-11-25 11:11:11');


-- timestamp/timestamp
SELECT * FROM TEST_TIMESTAMP WHERE A = '2016-11-24 11:00:00.123456789';

SELECT * FROM TEST_TIMESTAMP WHERE A <> '2016-11-24 11:00:00.123456789';

SELECT * FROM TEST_TIMESTAMP WHERE A > '2016-11-24 11:00:00.123456789';

SELECT * FROM TEST_TIMESTAMP WHERE A >= '2016-11-24 11:00:00.123456789';

SELECT * FROM TEST_TIMESTAMP WHERE A < '2016-11-24 11:00:00.123456789';

SELECT * FROM TEST_TIMESTAMP WHERE A <= '2016-11-24 11:00:00.123456789';


-- timestamp/date
SELECT * FROM TEST_TIMESTAMP WHERE A = DATE'2016-11-24';

SELECT * FROM TEST_TIMESTAMP WHERE A <> DATE'2016-11-24';

SELECT * FROM TEST_TIMESTAMP WHERE A > DATE'2016-11-24';

SELECT * FROM TEST_TIMESTAMP WHERE A >= DATE'2016-11-24';

SELECT * FROM TEST_TIMESTAMP WHERE A < DATE'2016-11-24';

SELECT * FROM TEST_TIMESTAMP WHERE A <= DATE'2016-11-24';


-- timestamp/timestamp with time zone
SELECT * FROM TEST_TIMESTAMP WHERE A = TIMESTAMP'2016-11-24 00:00:00 +04:00';

SELECT * FROM TEST_TIMESTAMP WHERE A <> TIMESTAMP'2016-11-24 00:00:00 +04:00';

SELECT * FROM TEST_TIMESTAMP WHERE A > TIMESTAMP'2016-11-24 00:00:00 +04:00';

SELECT * FROM TEST_TIMESTAMP WHERE A >= TIMESTAMP'2016-11-24 00:00:00 +04:00';

SELECT * FROM TEST_TIMESTAMP WHERE A < TIMESTAMP'2016-11-24 00:00:00 +04:00';

SELECT * FROM TEST_TIMESTAMP WHERE A <= TIMESTAMP'2016-11-24 00:00:00 +04:00';


-- timestamp/timestamp with local time zone
SELECT * FROM TEST_TIMESTAMP WHERE A = TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_TIMESTAMP WHERE A <> TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_TIMESTAMP WHERE A > TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_TIMESTAMP WHERE A >= TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_TIMESTAMP WHERE A < TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_TIMESTAMP WHERE A <= TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;


--
-- AGGREGATE
--
SELECT MAX(a) FROM TEST_TIMESTAMP;

SELECT MIN(a) FROM TEST_TIMESTAMP;


--
-- index 
--
CREATE INDEX TEST_TIMESTAMP_BTREE ON TEST_TIMESTAMP (A);

CREATE INDEX TEST_TIMESTAMP_HASH ON TEST_TIMESTAMP USING HASH (A);

CREATE INDEX TEST_TIMESTAMP_BRIN ON TEST_TIMESTAMP USING BRIN (A);


--
-- ORATIMESTAMPTZ
--

-- The default precision of fractional second is 6.
-- Build tables and test 'NLS_TIMESTAMP_TZ_FORMAT' parameter, don't do the validity check.
CREATE TABLE TEST_TIMESTAMPTZ(a TIMESTAMP WITH TIME ZONE);

SET NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24:MI:SS.FF9';


-- effective number of fractional seconds is 6,the part of excess is 0
INSERT INTO TEST_TIMESTAMPTZ VALUES('1990-1-19 11:11:11.123456789');

INSERT INTO TEST_TIMESTAMPTZ VALUES('1990-2-19');		-- hour、minute、second、fractional second is zero.

INSERT INTO TEST_TIMESTAMPTZ VALUES('1990-2-19 11:11:11');

SELECT * FROM TEST_TIMESTAMPTZ;


-- check for leap year
INSERT INTO TEST_TIMESTAMPTZ VALUES('1989-2-30');	--ERROR

INSERT INTO TEST_TIMESTAMPTZ VALUES('1989-2-29');	--ERROR

INSERT INTO TEST_TIMESTAMPTZ VALUES('1989-2-28');

INSERT INTO TEST_TIMESTAMPTZ VALUES('2000-2-30');	--ERROR

INSERT INTO TEST_TIMESTAMPTZ VALUES('2000-2-29');

INSERT INTO TEST_TIMESTAMPTZ VALUES('2000-2-28');


-- TIMESTAMPTZ literal 
SELECT TIMESTAMP'1990-1-1 11:11:11 +04:30';


-- Comparison operator
DELETE FROM TEST_TIMESTAMPTZ;

SET NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24:MI:SS.FF9';

INSERT INTO TEST_TIMESTAMPTZ VALUES('2016-11-24 11:00:00');

INSERT INTO TEST_TIMESTAMPTZ VALUES('2016-11-24 11:00:00.123456789');

INSERT INTO TEST_TIMESTAMPTZ VALUES('2016-11-24 11:11:11');

INSERT INTO TEST_TIMESTAMPTZ VALUES('2016-11-25 11:00:00');

INSERT INTO TEST_TIMESTAMPTZ VALUES('2016-11-25 11:00:00.123456789');

INSERT INTO TEST_TIMESTAMPTZ VALUES('2016-11-25 11:11:11');


-- timestamptz/timestamptz
SELECT * FROM TEST_TIMESTAMPTZ WHERE A = '2016-11-24 11:00:00.123456789';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A <> '2016-11-24 11:00:00.123456789';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A > '2016-11-24 11:00:00.123456789';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A >= '2016-11-24 11:00:00.123456789';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A < '2016-11-24 11:00:00.123456789';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A <= '2016-11-24 11:00:00.123456789';


-- timestamptz/date
SELECT * FROM TEST_TIMESTAMPTZ WHERE A = DATE'2016-11-24';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A <> DATE'2016-11-24';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A > DATE'2016-11-24';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A >= DATE'2016-11-24';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A < DATE'2016-11-24';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A <= DATE'2016-11-24';


-- timestamptz/timestamp
SELECT * FROM TEST_TIMESTAMPTZ WHERE A = TIMESTAMP'2016-11-24 00:00:00';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A <> TIMESTAMP'2016-11-24 00:00:00';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A > TIMESTAMP'2016-11-24 00:00:00';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A >= TIMESTAMP'2016-11-24 00:00:00';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A < TIMESTAMP'2016-11-24 00:00:00';

SELECT * FROM TEST_TIMESTAMPTZ WHERE A <= TIMESTAMP'2016-11-24 00:00:00';


-- timestamptz/timestamp with local time zone
SELECT * FROM TEST_TIMESTAMPTZ WHERE A = TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_TIMESTAMPTZ WHERE A <> TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_TIMESTAMPTZ WHERE A > TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_TIMESTAMPTZ WHERE A >= TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_TIMESTAMPTZ WHERE A < TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;

SELECT * FROM TEST_TIMESTAMPTZ WHERE A <= TIMESTAMP'2016-11-24 00:00:00'::TIMESTAMP WITH LOCAL TIME ZONE;


--
-- AGGREGATE
--
SELECT MAX(a) FROM TEST_TIMESTAMPTZ;

SELECT MIN(a) FROM TEST_TIMESTAMPTZ;


--
-- index 
--
CREATE INDEX TEST_TIMESTAMPTZ_BTREE ON TEST_TIMESTAMPTZ (A);

CREATE INDEX TEST_TIMESTAMPTZ_HASH ON TEST_TIMESTAMPTZ USING HASH (A);

CREATE INDEX TEST_TIMESTAMPTZ_BRIN ON TEST_TIMESTAMPTZ USING BRIN (A);


-- drop table
DROP TABLE TEST_DATE;

DROP TABLE TEST_TIMESTAMP;

DROP TABLE TEST_TIMESTAMPTZ;

--
-- Datetime/Interval Arithmetic
--

-- set datetime style
SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';
SET NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF9';
SET NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD HH24:MI:SS.FF9';	-- now, can not support specify time zone format!

-- oradate - oradate
SELECT date'2016-11-26' - date'2015-10-26';

-- oradate - oratimestamp
SELECT date'2016-11-26' - timestamp'2015-10-26 11:11:11';

-- oradate - oratimestamptz
SELECT date'2016-11-26' - timestamp'2015-10-26 11:11:11 +06:00';

-- oradate - oratimestampltz
SELECT date'2016-11-26' - timestamp '2015-10-26 11:11:11'::timestamp with local time zone;

-- oradate - interval year to month
SELECT date'2016-11-26' - interval'10-11' year to month;

-- oradate - interval day to second 
SELECT date'2016-11-26' - interval'365 11:11:11' day(3) to second;

-- oradate - number
SELECT date'2016-11-26' - 11.11;


-- oradate + interval year to month
SELECT date'2016-11-26' + interval'10-11' year to month;

-- oradate + interval day to second 
SELECT date'2016-11-26' + interval'365 11:11:11' day(3) to second;

-- oradate + number
SELECT date'2016-11-26' + 11.11;


-- oratimestamp - oratimestamp
SELECT timestamp'2016-11-26 23:30:59.123456' - timestamp'2015-9-20 13:45:45.111111';

-- oratimestamp - oradate
SELECT timestamp'2016-11-26 23:30:59.123456' - date'2015-9-20';

-- oratimestamp - oratimestamptz
SELECT timestamp'2016-11-26 23:30:59.123456' - timestamp'2015-9-20 13:45:45.111111 +04:30';

-- oratimestamp - oratimestampltz
SELECT timestamp'2016-11-26 23:30:59.123456' - timestamp '2015-9-20 13:45:45.111111'::timestamp with local time zone;

-- oratimestamp - interval year to month
SELECT timestamp'2016-11-26 23:30:59.123456' - interval'10-11' year to month;

-- oratimestamp - interval day to second 
SELECT timestamp'2016-11-26 23:30:59.123456' - interval'365 11:11:11' day(3) to second;

-- oratimestamp - number
SELECT timestamp'2016-11-26 23:30:59.123456' - 11.11;


-- oratimestamp + interval year to month
SELECT timestamp'2016-11-26 23:30:59.123456' + interval'10-11' year to month;

-- oratimestamp + interval day to second 
SELECT timestamp'2016-11-26 23:30:59.123456' + interval'365 11:11:11' day(3) to second;

-- oratimestamp + number
SELECT timestamp'2016-11-26 23:30:59.123456' + 11.11;


-- oratimestamptz - oratimestamptz
SELECT timestamp'2016-11-26 23:30:59.123456 +06:30' - timestamp'2015-9-20 13:45:45.111111 +04:30';

-- oratimestamptz - oradate
SELECT timestamp'2016-11-26 23:30:59.123456 +06:30' - date'2015-9-20';

-- oratimestamptz - oratimestamp
SELECT timestamp'2016-11-26 23:30:59.123456 +06:30' - timestamp'2015-9-20 13:45:45.111111';

-- oratimestamptz - oratimestampltz
SELECT timestamp'2016-11-26 23:30:59.123456 +06:30' - timestamp '2015-9-20 13:45:45.111111'::timestamp with local time zone;

-- oratimestamptz - interval year to month
SELECT timestamp'2016-11-26 23:30:59.123456 +06:30' - interval'10-11' year to month;

-- oratimestamptz - interval day to second 
SELECT timestamp'2016-11-26 23:30:59.123456 +06:30' - interval'365 11:11:11' day(3) to second;

-- oratimestamptz - number
SELECT timestamp'2016-11-26 23:30:59.123456 +06:30' - 11.11;


-- oratimestamptz + interval year to month
SELECT timestamp'2016-11-26 23:30:59.123456 +06:30' + interval'10-11' year to month;

-- oratimestamptz + interval day to second 
SELECT timestamp'2016-11-26 23:30:59.123456 +06:30' + interval'365 11:11:11' day(3) to second;

-- oratimestamptz + number
SELECT timestamp'2016-11-26 23:30:59.123456 +06:30' + 11.11;


-- oratimestampltz - oratimestampltz
SELECT timestamp '2016-10-20 13:45:45.123456'::timestamp with local time zone - timestamp '2015-9-20 13:45:45.111111'::timestamp with local time zone;

-- oratimestampltz - oradate
SELECT timestamp '2016-12-12 14:41:11.123456000'::timestamp with local time zone - date'2016-11-26';

-- oratimestampltz - oratimestamp
SELECT timestamp '2016-12-12 14:41:11.123456000'::timestamp with local time zone - timestamp'2016-11-26 00:00:00';

-- oratimestampltz - oratimestamptz
SELECT timestamp '2016-10-20 13:45:45.123456'::timestamp with local time zone - timestamp'2015-9-20 13:45:45.111111 +06:30';

-- oratimestampltz - interval year to month
SELECT timestamp '2016-11-26 23:30:59.123456'::timestamp with local time zone - interval'10-11' year to month;

-- oratimestampltz - interval day to second 
SELECT timestamp '2016-11-26 23:30:59.123456'::timestamp with local time zone - interval'365 11:11:11' day(3) to second;

-- oratimestampltz - number
SELECT timestamp '2016-11-26 23:30:59.123456'::timestamp with local time zone - 11.11;


-- oratimestampltz + interval year to month
SELECT timestamp '2016-12-12 14:41:11.123456'::timestamp with local time zone + interval'10-11' year to month;

-- oratimestampltz + interval day to second 
SELECT timestamp '2016-12-12 14:41:11.123456'::timestamp with local time zone + interval'365 11:11:11' day(3) to second;

-- oratimestampltz + number
SELECT timestamp '2016-12-12 14:41:11.123456'::timestamp with local time zone + 11.11;


-- interval year to month + oradate
SELECT interval'10-11' year to month + date'2016-11-26';

-- interval day to second + oradate
SELECT interval'365 11:11:11' day(3) to second + date'2016-11-26';

-- interval year to month + oratimestamp
SELECT interval'10-11' year to month + timestamp'2016-11-26 11:11:11.123456';

-- interval day to second + oratimestamp
SELECT interval'365 11:11:11' day(3) to second + timestamp'2016-11-26 11:11:11.123456';

-- interval year to month + oratimestamptz
SELECT interval'10-11' year to month + timestamp'2016-11-26 11:11:11.123456 +06:30';

-- interval day to second + oratimestamptz
SELECT interval'365 11:11:11' day(3) to second + timestamp'2016-11-26 11:11:11.123456 +06:30';

-- interval year to month + oratimestampltz
SELECT interval'10-11' year to month + timestamp '2016-12-12 14:41:11.123456'::timestamp with local time zone;

-- interval day to second + oratimestampltz
SELECT interval'365 11:11:11' day(3) to second + timestamp '2016-12-12 14:41:11.123456'::timestamp with local time zone;

-- interval year to month * number
SELECT interval'10-11' year to month * 12.34;

-- interval day to second * number
SELECT interval'365 11:11:11' day(3) to second * 12.34;

-- interval year to month / number
SELECT interval'10-11' year to month / 12.34;

-- interval day to second / number
SELECT interval'365 11:11:11' day(3) to second / 12.34;

-- number + oradate
SELECT 123.456 + date'2016-11-26';

-- number + oratimestamp
SELECT 123.456 + timestamp'2016-11-26 11:11:11.123456';

-- number + oratimestamptz
SELECT 123.456 + timestamp'2016-11-26 11:11:11.123456 +06:30';

-- number + oratimestampltz
SELECT 123.456 + timestamp '2016-11-26 11:11:11.123456'::timestamp with local time zone;

-- number * interval year to month 
SELECT 123.456 * interval'10-11' year to month;

-- number * interval day to second
SELECT 123.456 * interval'365 11:11:11' day(3) to second;

-- The operator "<=" supports a comparison between the "number" type and the "varchar2" type.
SET NLS_DATE_FORMAT = 'YYYY-MM-DD';
select 25::number <= to_char('1990-01-01'::oradate, 'yyyy');

/* Begin - BUG#M0000247 */
set client_min_messages = 'error';
create table test_247(a date, b timestamp(7), c timestamp(7) with time zone, d timestamp(7) with local time zone);
set ivorysql.datetime_ignore_nls_mask = 15;
insert into test_247 values('2023-10-27 10:54:55.1234567', '2023-10-27 10:54:55.1234567', '2023-10-27 10:54:55.1234567', '2023-10-27 10:54:55.1234567');
SET NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';
select * from test_247;

drop table test_247;
reset NLS_DATE_FORMAT;
reset ivorysql.datetime_ignore_nls_mask;
reset client_min_messages;
/* End - BUG#M0000247 */