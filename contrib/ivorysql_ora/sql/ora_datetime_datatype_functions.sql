/*
 * to_date
 */
SET NLS_DATE_FORMAT = 'MM-DD-YYYY HH24:MI:SS';
SELECT to_date('12-18-2011') FROM DUAL;
SELECT to_date('2011-12-18') FROM DUAL;	--ERROR

SELECT to_date('2011 12  18', 'YYYY MM   DD') FROM DUAL;

SELECT to_date(
    'January 15, 1989, 11:00 A.M.',
    'Month dd, YYYY, HH:MI A.M.',
     'NLS_DATE_LANGUAGE = American')
     FROM DUAL;

/*
 * to_timestamp
 */
SET NLS_TIMESTAMP_FORMAT = 'MM-DD-YYYY HH24:MI:SS.FF9';
SELECT to_timestamp('10-9-2016 14:10:10.123000') FROM DUAL;
SELECT to_timestamp('2016-10-9 14:10:10.123000') FROM DUAL;

SELECT to_timestamp('10-9-2016 14:10:10.123000', 'DD-MM-YYYY HH24:MI:SS.FF9') FROM DUAL;

SELECT to_timestamp(
	'10-9-2016 14:10:10.123000', 
	'DD-MM-YYYY HH24:MI:SS.FF9',
	'NLS_DATE_LANGUAGE = American') FROM DUAL;
	
/*
 * to_timestamp_tz
 */
SET NLS_TIMESTAMP_TZ_FORMAT = 'MM-DD-YYYY HH24:MI:SS.FF9 TZH:TZM';
SELECT to_timestamp_tz('10-9-2016 14:10:10.123000') FROM DUAL;
SELECT to_timestamp_tz('2016-10-9 14:10:10.123000') FROM DUAL;

SELECT to_timestamp_tz('10-9-2016 14:10:10.123000', 'DD-MM-YYYY HH24:MI:SS.FF9') FROM DUAL;

SELECT to_timestamp_tz(
	'10-9-2016 14:10:10.123000', 
	'DD-MM-YYYY HH24:MI:SS.FF9',
	'NLS_DATE_LANGUAGE = American') FROM DUAL;

SELECT to_timestamp_tz('10-9-2016 14:10:10.123000 +8:30', 'DD-MM-YYYY HH24:MI:SS.FF TZH:TZM') FROM DUAL;
SELECT to_timestamp_tz('10-9-2016 14:10:10.123000 +1:00', 'DD-MM-YYYY HH24:MI:SS.FF TZH:TZM') FROM DUAL;
SELECT to_timestamp_tz('10-9-2016 14:10:10.123000 -12:00', 'DD-MM-YYYY HH24:MI:SS.FF TZH:TZM') FROM DUAL;
SELECT to_timestamp_tz('10-9-2016 14:10:10.123000 -13:00', 'DD-MM-YYYY HH24:MI:SS.FF TZH:TZM') FROM DUAL;

/*
 * to_char
 */
-- to_char function for date data type 
SET NLS_DATE_FORMAT = 'MM-DD-YYYY HH24:MI:SS';
CREATE TABLE to_char_tbl(a date);
INSERT INTO to_char_tbl VALUES('11-22-1990 11:11:11');
SELECT to_char(a) FROM to_char_tbl;

SELECT to_char(a, 'DD-MM-YYYY') FROM to_char_tbl;
SELECT to_char(a, 'DD-MM-YYYY HH24:MI:SS') FROM to_char_tbl;

SELECT to_char(
	a, 
	'DD-MM-YYYY HH24:MI:SS',
	'NLS_DATE_LANGUAGE = American') FROM to_char_tbl;

DROP TABLE to_char_tbl;

-- to_char function for timestamp data type
SET NLS_TIMESTAMP_FORMAT = 'MM-DD-YYYY HH24:MI:SS.FF9';
CREATE TABLE to_char_tbl(a timestamp);
INSERT INTO to_char_tbl VALUES('11-22-1990 11:11:11.123456');
SELECT to_char(a) FROM to_char_tbl;

SELECT to_char(a, 'DD-MM-YYYY') FROM to_char_tbl;
SELECT to_char(a, 'DD-MM-YYYY HH24:MI:SS.FF9') FROM to_char_tbl;

SELECT to_char(
	a, 
	'DD-MM-YYYY HH24:MI:SS.FF9',
	'NLS_DATE_LANGUAGE = American') FROM to_char_tbl;

DROP TABLE to_char_tbl;

-- to_char function for timestamp with time zone data type
SET NLS_TIMESTAMP_TZ_FORMAT = 'MM-DD-YYYY HH24:MI:SS.FF9 TZH:TZM';
CREATE TABLE to_char_tbl(a timestamp with time zone);
INSERT INTO to_char_tbl VALUES(timestamp'1990-11-22 11:11:11.123456 +06:30');
SELECT to_char(a) FROM to_char_tbl;

SELECT to_char(a, 'DD-MM-YYYY') FROM to_char_tbl;
SELECT to_char(a, 'DD-MM-YYYY HH24:MI:SS.FF9') FROM to_char_tbl;

SELECT to_char(
	a, 
	'DD-MM-YYYY HH24:MI:SS.FF9',
	'NLS_DATE_LANGUAGE = American') FROM to_char_tbl;

DROP TABLE to_char_tbl;

-- oracle sys date func

SET nls_timestamp_format = 'DD-MON-YY HH24:MI:SS.US';

set NLS_DATE_FORMAT = 'YYYY-MM-DD HH24:MI:SS';
--sys_setract_utc 
CREATE table datetest (aa timestamp);

insert into datetest values (sys_extract_utc(timestamp '2018-03-02 12:01:02'));
insert into datetest values (sys_extract_utc(timestamp '2018-03-02 12:01:02 +1:00'));

select * from datetest;

drop table datetest;

--to_date
select to_date('19901212','YYYYMMDD');
select to_date('19901212','YYYY-MM-DD');
select to_date('19901212','YYYY&MM&DD');
select to_date('1990-12-12','YYYY-MM-DD');

--current_date,current_timestamp
create table datetest as select current_date, current_timestamp, localtimestamp;
select attname, typname from pg_attribute, pg_type where attrelid in (select oid from pg_class where relname = 'datetest') and attnum > 0 and atttypid = pg_type.oid;

drop table datetest;

--to_char
create table datetest (aa varchar2(100),bb number);

insert into datetest values (to_char(date '2017-03-12'),1);
insert into datetest values (to_char(date '2017-03-12','DD-MM-YYYY'),2);
insert into datetest values (to_char(date '2017-03-12','DD-MM-YYYY HH24:MI:SS','NLS_DATE_LANGUAGE = english'),3);

insert into datetest values (to_char(timestamp '2017-03-12 13:12:23'),4);
insert into datetest values (to_char(timestamp '2017-03-12 13:12:23','DD-MM-YYYY'),5);
insert into datetest values (to_char(timestamp '2017-03-12 13:12:23','DD-MM-YYYY HH24:MI:SS'),6);
insert into datetest values (to_char(timestamp '2017-03-12 13:12:23','DD-MM-YYYY HH:MI:SS AM'),7);
insert into datetest values (to_char(timestamp '2017-03-12 13:12:23','DD-MM-YYYY HH24:MI:SS','NLS_DATE_LANGUAGE = english'),8);

insert into datetest values (to_char(timestamptz '2017-03-12 13:12:23 +2:00'),9);
insert into datetest values (to_char(timestamptz '2017-03-12 13:12:23 +2:00','DD-MM-YYYY'),10);
insert into datetest values (to_char(timestamptz '2017-03-12 13:12:23 +2:00','DD-MM-YYYY HH24:MI:SS'),11);
insert into datetest values (to_char(timestamptz '2017-03-12 13:12:23 +2:00','DD-MM-YYYY HH:MI:SS AM'),12);
insert into datetest values (to_char(timestamptz '2017-03-12 13:12:23 +2:00','DD-MM-YYYY HH24:MI:SS','NLS_DATE_LANGUAGE = english'),13);

insert into datetest values (to_char(INTERVAL '123-2' YEAR(3) TO MONTH),14);
insert into datetest values (to_char(INTERVAL '123-2' YEAR(3) TO MONTH,'DD-MM-YYYY'),15);
insert into datetest values (to_char(INTERVAL '123 13:12:34' DAY(3) TO SECOND),16);
insert into datetest values (to_char(INTERVAL '123 13:12:34' DAY(3) TO SECOND(4),'DD-MM-YYYY HH24:MI:SS'),17);

insert into datetest values (to_char(timestamp '2017-03-12 13:12:23','Month MONTH Mon MoN MI Mi mi'),18);
insert into datetest values (to_char(timestamp '2017-03-12 13:12:23','YYYY-text'),19);

select * from datetest;
drop table datetest;

--ADD_MONTHS
create table datetest (aa date);

insert into datetest values (ADD_MONTHS(date '2018-01-23',2));
insert into datetest values (ADD_MONTHS(date '2018-01-23',13));
insert into datetest values (ADD_MONTHS(timestamp '2018-01-23 13:12:14',2));
insert into datetest values (ADD_MONTHS(timestamp '2018-01-23 12:34:45',13));
insert into datetest values (ADD_MONTHS(date'2017-1-30',1.1));  

select * from datetest;
drop table datetest;

--LAST_DAY
create table datetest (aa date);

insert into datetest values (LAST_DAY(date '2018-01-23'));
insert into datetest values (LAST_DAY(date '2018-02-12'));

select * from datetest;
drop table datetest;

--NEXT_DAY
create table datetest (aa date);

insert into datetest values (NEXT_DAY(date '2018-01-23 13:12:34','mon'));
insert into datetest values (NEXT_DAY(date '2018-02-12',2));
insert into datetest values (NEXT_DAY(date '2018-02-12','monday'));

select * from datetest;
drop table datetest;

--MONTHS_BETWEEN
create table datetest (aa number);

insert into datetest values (MONTHS_BETWEEN(date '2018-01-23 13:12:34',date '2014-08-2 13:12:34'));
insert into datetest values (MONTHS_BETWEEN(date '1990-09-29',date '2018-07-13'));
insert into datetest values (MONTHS_BETWEEN(TIMESTAMP '2018-08-09 08:30:00',TIMESTAMP '2018-08-1 09:00:00'));

select * from datetest;
drop table datetest;

--ROUND
create table datetest (aa date);

insert into datetest values (ROUND(date '2018-01-23'));
insert into datetest values (ROUND(date '2018-08-12','cc'));
insert into datetest values (ROUND(date '2018-07-01','yyyy'));
insert into datetest values (ROUND(date '2018-06-30','yyyy'));
insert into datetest values (ROUND(date '2018-04-12','iyyy'));
insert into datetest values (ROUND(date '2018-08-12','q'));
insert into datetest values (ROUND(date '2018-08-12','mm'));
insert into datetest values (ROUND(date '2018-08-16','mm'));
insert into datetest values (ROUND(date '2018-08-12','ww'));
insert into datetest values (ROUND(date '2018-08-12','iw'));
insert into datetest values (ROUND(date '2018-08-12','w'));
insert into datetest values (ROUND(to_date('2018-7-25 11:59:59'),'dd')); 
insert into datetest values (ROUND(to_date('2018-7-25 12:00:00'),'dd')); 
insert into datetest values (ROUND(date '1966-07-27','day'));
insert into datetest values (ROUND(to_date('2018-7-25 13:29:59'),'hh'));  
insert into datetest values (ROUND(to_date('2018-7-25 13:30:23'),'hh'));  
insert into datetest values (ROUND(to_date('2018-7-25 13:29:29'),'mi')); 
insert into datetest values (ROUND(to_date('2018-7-25 13:29:31'),'mi'));  

select * from datetest;
drop table datetest;

--trunc
create table datetest (aa date);

insert into datetest values (TRUNC(date '2018-01-23'));
insert into datetest values (TRUNC(date '2018-08-12','cc'));
insert into datetest values (TRUNC(date '2018-07-01','yyyy'));
insert into datetest values (TRUNC(date '2018-06-30','yyyy'));
insert into datetest values (TRUNC(date '2018-04-12','iyyy'));
insert into datetest values (TRUNC(date '2018-08-12','q'));
insert into datetest values (TRUNC(date '2018-08-12','mm'));
insert into datetest values (TRUNC(date '2018-08-16','mm'));
insert into datetest values (TRUNC(date '2018-08-12','ww'));
insert into datetest values (TRUNC(date '2018-08-12','iw'));
insert into datetest values (TRUNC(date '2018-08-12','w'));
insert into datetest values (TRUNC(to_date('2018-7-25 11:59:59'),'dd')); 
insert into datetest values (TRUNC(to_date('2018-7-25 12:00:00'),'dd')); 
insert into datetest values (TRUNC(date '1966-07-27','day'));
insert into datetest values (TRUNC(to_date('2018-7-25 13:29:59'),'hh'));  
insert into datetest values (TRUNC(to_date('2018-7-25 13:30:23'),'hh'));  
insert into datetest values (TRUNC(to_date('2018-7-25 13:29:29'),'mi')); 
insert into datetest values (TRUNC(to_date('2018-7-25 13:29:31'),'mi'));  

select * from datetest;
drop table datetest;

--NUMTODSINTERVAL

create table datetest (aa interval day(3) to second);

insert into datetest values (NUMTODSINTERVAL(123,'day'));
insert into datetest values (NUMTODSINTERVAL(234,'hour'));
insert into datetest values (NUMTODSINTERVAL(345,'minute'));
insert into datetest values (NUMTODSINTERVAL(678,'second'));

select * from datetest;
drop table datetest;

--NUMTOYMINTERVAL
create table datetest (aa interval year(3) to month);

insert into datetest values (NUMTOYMINTERVAL(123,'year'));
insert into datetest values (NUMTOYMINTERVAL(234,'month'));

select * from datetest;
drop table datetest;

--TO_DSINTERVAL
create table datetest (aa interval day(3) to second);

insert into datetest values (TO_DSINTERVAL('789 13:23:34'));
insert into datetest values (TO_DSINTERVAL('789 13  : 23 : 34'));
insert into datetest values (TO_DSINTERVAL('P100DT210H100M299.898S'));
insert into datetest values (TO_DSINTERVAL(' P0DT0.0S'));   

select * from datetest;
drop table datetest;

--TO_YMINTERVAL
create table datetest (aa interval year(9) to month);

insert into datetest values (TO_YMINTERVAL('567-08'));
insert into datetest values (TO_YMINTERVAL('P234Y8M66DT100H'));
insert into datetest values (TO_YMINTERVAL('99999999 - 1'));  

select * from datetest;
drop table datetest;

--new_time
create table datetest (aa date, bb date);

insert into datetest values (date '2018-7-16',new_time(date '2018-7-16','GMT','AST'));
insert into datetest values (date '1998-2-26',new_time(date '1998-2-26','ADT','YDT'));
insert into datetest values (date '1998-2-26',new_time(date '1998-2-26','PST','CDT'));
insert into datetest values (date '1998-2-26',new_time(date '1998-2-26','YST','BST'));

select * from datetest;
drop table datetest;

--tz_offset
create table datetest (aa varchar2(100));

insert into datetest values (tz_offset('Asia/Shanghai'));
insert into datetest values (tz_offset('GMT'));
select tz_offset('-12:59') from dual; 
select tz_offset('+14:05') from dual; 
	
select * from datetest;
drop table datetest;

--from_tz
SELECT FROM_TZ(TIMESTAMP '2000-03-28 08:00:00', '3:00') FROM DUAL;
  
--sessiontimezone
set timezone = 'Asia/Hong_Kong';
select sessiontimezone() from dual; 


alter session set nls_date_format='YYYY-MM-DD HH24:MI:SS';
alter session set nls_timestamp_format = 'YYYY-MM-DD HH24:MI:SS.ff';
/*
 * round
 */
select round(cast('2012-12-12' as date), 'CC') from dual;
select round(cast('2051-12-12' as date), 'SCC') from dual;
select round(cast('2050-12-12' as date), 'SYYYY') from dual;
select round(cast('2050-06-12' as date), 'IYYY') from dual;
select round(cast('2020-01-1' as date), 'Q') from dual;
select round(cast('2020-02-15' as date), 'MONTH') from dual;
select round(cast('2020-02-29' as date), 'WW') from dual;
select round(cast('2020-03-15' as date), 'IW') from dual;
select round(cast('2020-02-28' as date), 'W') from dual;
select round(cast('2020-03-15' as date), 'DDD') from dual;
select round(cast('2020-06-18' as date), 'DAY') from dual;
select round(cast('2012-12-12' as sys.oradate), 'CC') from dual;
select round(cast('2051-12-12' as sys.oradate), 'SCC') from dual;
select round(cast('2050-12-12' as sys.oradate), 'SYYYY') from dual;
select round(cast('2050-06-12' as sys.oradate), 'IYYY') from dual;
select round(cast('2020-01-1' as sys.oradate), 'Q') from dual;
select round(cast('2020-02-15' as sys.oradate), 'MONTH') from dual;
select round(cast('2020-02-29' as sys.oradate), 'WW') from dual;
select round(cast('2020-03-15' as sys.oradate), 'IW') from dual;
select round(cast('2020-02-28' as sys.oradate), 'W') from dual;
select round(cast('2020-03-15' as sys.oradate), 'DDD') from dual;
select round(cast('2012-12-12 12:00:00' as sys.oratimestamp), 'CC') from dual;
select round(cast('2050-12-12 12:00:00' as sys.oratimestamp), 'SCC') from dual;
select round(cast('2050-06-12 19:20:21' as sys.oratimestamp), 'SYYYY') from dual;
select round(cast('2050-06-12 16:40:55' as sys.oratimestamp), 'IYYY') from dual;
select round(cast('2020-02-16 19:16:12' as sys.oratimestamp), 'Q') from dual;
select round(cast('2020-09-27 18:30:21' as sys.oratimestamp), 'MONTH') from dual;
select round(cast('2020-03-15 12:12:19' as sys.oratimestamp), 'WW') from dual;
select round(cast('2020-02-28 10:00:01' as sys.oratimestamp), 'IW') from dual;
select round(cast('2020-06-18 13:12:18' as sys.oratimestamp), 'DDD') from dual;
select round(cast('2020-02-29 14:40:20' as sys.oratimestamp), 'DAY') from dual;
select round(cast('2020-02-29 11:40:20' as sys.oratimestamp), 'HH') from dual;
select round(cast('2020-02-29 14:40:20' as sys.oratimestamp), 'MI') from dual;
select round(cast('2020-02-29 14:40:20' as sys.oratimestamp)) from dual;
select round(to_timestamp_tz('2012-12-12 12:00:00 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM')) from dual;
select round(to_timestamp_tz('2012-12-12 12:00:00 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'CC') from dual;
select round(to_timestamp_tz('2050-12-12 12:00:00 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'SCC') from dual;
select round(to_timestamp_tz('2051-12-12 12:00:00 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'SCC') from dual;
select round(to_timestamp_tz('2050-06-12 19:20:21 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'SYYYY') from dual;
select round(to_timestamp_tz('2050-06-12 16:40:55 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'IYYY') from dual;
select round(to_timestamp_tz('2020-02-16 19:16:12 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'Q') from dual;
select round(to_timestamp_tz('2020-09-27 18:30:21 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'MONTH') from dual;
select round(to_timestamp_tz('2020-03-15 12:12:19 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'WW') from dual;
select round(to_timestamp_tz('2020-02-28 10:00:01 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'IW') from dual;
select round(to_timestamp_tz('2020-02-23 12:12:14 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'W') from dual;
select round(to_timestamp_tz('2020-06-18 13:12:18 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'DDD') from dual;
select round(to_timestamp_tz('2020-02-29 14:40:20 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'DAY') from dual;
select round(to_timestamp_tz('2020-02-29 11:40:20 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'HH') from dual;
select round(to_timestamp_tz('2020-06-18 14:40:20 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'MI') from dual;

/*
 * trunc
 */
select trunc(cast('2050-12-12' as pg_catalog.date), 'SCC') from dual;
select trunc(cast('2050-06-12' as pg_catalog.date), 'SYYYY') from dual;
select trunc(cast('2020-02-28' as pg_catalog.date), 'IYYY') from dual;
select trunc(cast('2020-02-28' as pg_catalog.date), 'Q') from dual;
select trunc(cast('2020-09-27' as pg_catalog.date), 'MONTH') from dual;
select trunc(cast('2020-03-15' as pg_catalog.date), 'WW') from dual;
select trunc(cast('2020-02-28' as pg_catalog.date), 'IW') from dual;
select trunc(cast('2020-02-23' as pg_catalog.date), 'W') from dual;
select trunc(cast('2020-06-18' as pg_catalog.date), 'DDD') from dual;
select trunc(cast('2020-02-29' as pg_catalog.date), 'DAY') from dual;
select trunc(cast('2050-12-12' as sys.oradate), 'SCC') from dual;
select trunc(cast('2050-06-12' as sys.oradate), 'SYYYY') from dual;
select trunc(cast('2020-02-28' as sys.oradate), 'IYYY') from dual;
select trunc(cast('2020-02-28' as sys.oradate), 'Q') from dual;
select trunc(cast('2020-09-27' as sys.oradate), 'MONTH') from dual;
select trunc(cast('2020-03-15' as sys.oradate), 'WW') from dual;
select trunc(cast('2020-02-28' as sys.oradate), 'IW') from dual;
select trunc(cast('2020-02-23' as sys.oradate), 'W') from dual;
select trunc(cast('2020-06-18' as sys.oradate), 'DDD') from dual;
select trunc(cast('2020-02-29' as sys.oradate), 'DAY') from dual;
select trunc(cast( '2051-12-12 12:00:00'as oratimestamp), 'SCC') from dual;
select trunc(cast( '2050-06-12 19:20:21'as oratimestamp), 'SYYYY') from dual;
select trunc(cast( '2020-02-28 16:40:55'as oratimestamp), 'IYYY') from dual;
select trunc(cast( '2020-07-28 19:16:12'as oratimestamp), 'Q') from dual;
select trunc(cast( '2020-09-27 18:30:21'as oratimestamp), 'MONTH') from dual;
select trunc(cast( '2020-03-15 12:12:19'as oratimestamp), 'WW') from dual;
select trunc(cast( '2020-02-28 10:00:01'as oratimestamp), 'IW') from dual;
select trunc(cast( '2020-02-23 12:12:14'as oratimestamp), 'W') from dual;
select trunc(cast( '2020-06-18 13:12:18'as oratimestamp), 'DDD') from dual;
select trunc(cast( '2020-02-29 14:40:20'as oratimestamp), 'DAY') from dual;
select trunc(cast( '2020-02-29 11:40:20'as oratimestamp), 'HH') from dual;
select trunc(cast( '2020-02-29 18:40:20'as oratimestamp), 'MI') from dual;
select trunc(to_timestamp_tz('2051-12-12 12:00:00 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'SCC') from dual;
select trunc(to_timestamp_tz('2050-06-12 19:20:21 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'SYYYY') from dual;
select trunc(to_timestamp_tz('2020-02-28 16:40:55 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'IYYY') from dual;
select trunc(to_timestamp_tz('2020-02-28 19:16:12 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'Q') from dual;
select trunc(to_timestamp_tz('2020-09-27 18:30:21 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'MONTH') from dual;
select trunc(to_timestamp_tz('2020-03-15 12:12:19 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'WW') from dual;
select trunc(to_timestamp_tz('2020-02-28 10:00:01 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'IW') from dual;
select trunc(to_timestamp_tz('2020-02-23 12:12:14 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'W') from dual;
select trunc(to_timestamp_tz('2020-06-18 13:12:18 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'DDD') from dual;
select trunc(to_timestamp_tz('2020-02-29 14:40:20 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'DAY') from dual;
select trunc(to_timestamp_tz('2020-02-29 11:40:20 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'HH') from dual;
select trunc(to_timestamp_tz('2020-02-29 14:40:50 + 08', 'YYYY-MM-DD HH24:MI:SS TZH:TZM'), 'MI') from dual;

/*
 * to_date
 */
select to_date('50-11-28 17:04:55','RR-MM-dd hh24:mi:ss') from dual;
select to_date('50-11-28 17:04:55','YY-MM-dd hh24:mi:ss') from dual;
select to_date('50-11-28','rr-MM-dd ') from dual;
select to_date('50-11-28 ','YY-MM-dd hh24:mi:ss') from dual;
select to_date('50-11-28 ','RR-MM-dd hh24:mi:ss') from dual;
select to_date('50-11-28 ','RR-MM-dd ') from dual;
select to_date(2454336, 'J') from dual;
select to_date(2454336, 'j') from dual;
select to_date('20-11-28','YY-MM-dd hh24:mi:ss') from dual;
select to_date('20-11-28 10:14:22','YY-MM-dd hh24:mi:ss') from dual;
select to_date('2022-11-28 17:04:55','RRRR-MM-dd hh24:mi:ss') from dual;
select to_date('20-11-28 17:04:55','RRRR-MM-dd hh24:mi:ss') from dual;
select to_date('50-11-28 17:04:55','RRRR-MM-dd hh24:mi:ss') from dual;
alter session set NLS_DATE_FORMAT='YYYY/MM/DD HH24:MI:SS';
select to_date('2019/11/22') from dual;
select to_date('2019/11/27 10:14:22') from dual;
select to_date('2019/11/22', 'yyyy-mm-dd') from dual;
reset NLS_DATE_FORMAT;
--select to_date('120','rr') from dual; --expect:0120-current month-01 00:00:00
--select to_date('120','RR') from dual;	--expect:0120-current month-01 00:00:00
--select to_date('2020','RR') from dual; --expect:2020-current month-01 00:00:00
select to_date(NULL) from dual;
select to_date(NULL,NULL) from dual;
alter session set NLS_DATE_FORMAT='SYYYY-MM-DD HH24:MI:SS';
select to_date('07--4712-23 14:31:23', 'MM-SYYYY-DD HH24:MI:SS') from dual;
select to_date('07-2019-23 14:31:23', 'MM-SYYYY-DD HH24:MI:SS') from dual;
select to_date('9999-07-23 14:31:23', 'SYYYY-MM-DD HH24:MI:SS') from dual;
select to_date('-4712-07-23 14:31:23', 'syyyy-mm-dd hh24:mi:ss') from dual;
--select to_date('-1-07-23 14:31:23', 'syyyy-mm-dd hh24:mi:ss') from dual;
select to_date('+2021-07-23 14:31:23', 'syyyy-mm-dd hh24:mi:ss') from dual;
select to_date('07--2019-23', 'MM-SYYYY-DD') from dual;
--select to_date('-2019', 'SYYYY') from dual; --expect:-2019-current month-01 00:00:00
--select to_date('2019', 'syyyy') from dual; --expect:2019-current month-01 00:00:00
select to_date('2019/11/27 10:14:22') from dual;
--select to_date('120','rr') from dual;	--expect:120-current month-01 00:00:00
--select to_date('120','RR') from dual;	--expect:120-current month-01 00:00:00
--select to_date('2020','RR') from dual;	--expect:2020-current month-01 00:00:00
select to_date(NULL) from dual;
select to_date(NULL,NULL) from dual;
select to_date('07--4712-23 14:31:23', 'MM-SYYYY-DD HH24:MI:SS') from dual;
--test SYYYY date type
select to_date('07--4712-23 14:31:23', 'MM-SYYYY-DD HH24:MI:SS') from dual;
select to_date('07-2019-23 14:31:23', 'MM-SYYYY-DD HH24:MI:SS') from dual;
select to_date('9999-07-23 14:31:23', 'SYYYY-MM-DD HH24:MI:SS') from dual;
select to_date('-4712-07-23 14:31:23', 'syyyy-mm-dd hh24:mi:ss') from dual;
--select to_date('-1-07-23 14:31:23', 'syyyy-mm-dd hh24:mi:ss') from dual;
select to_date('+2021-07-23 14:31:23', 'syyyy-mm-dd hh24:mi:ss') from dual;
select to_date('07--2019-23', 'MM-SYYYY-DD') from dual;
--select to_date('-2019', 'SYYYY') from dual;	--expect:-2019-current month-01 00:00:00
--select to_date('2019', 'syyyy') from dual;	--expect:2019-current month-01 00:00:00
select to_date(20111211, 'YYYYMMDD') from dual;

create table test1(d date);
insert into test1 values (to_date('2009-12-2', 'syyyy-mm-dd'));
insert into test1 values (to_date('-1452-12-2', 'syyyy-mm-dd'));
select to_char(d, 'bcyyyy-mm-dd') from test1;
select * from test1;
drop table test1;


alter session set NLS_DATE_FORMAT='DD-MON-RR HH24:MI:SS';
--select sysdate() from dual;

alter session set NLS_DATE_FORMAT='DD-MON-RR HH24:MI:SS';
--select current_date from dual;


alter session set NLS_DATE_FORMAT='DD-MON-RR HH24:MI:SS';
select last_day('30AUG22') from dual;
select last_day('2022-08-23') from dual; --err

select to_date('-2022-09-21','syyyy-mm-dd') from dual;
select to_timestamp('-20220314121313222','syyyy/mm/dd hh:mi:ss:ff') from dual;
select to_timestamp_tz('-2022-08-22 10:13:18. 1516 -08:00','SYYYY/MM/DD HH:MI:SS:ff TZH:TZM') from dual;


alter session set NLS_TIMESTAMP_FORMAT='YY-MM-DD HH24.MI.SS.FF';
create table ts_tb(a timestamp);
insert into ts_tb values('2022-08-19 11.11.11');   --succ
insert into ts_tb values('122-08-19 11.11.11');     --err
insert into ts_tb values('23-08-19 11.11.11');     --succ
insert into ts_tb values('7-08-19 11.11.11');     --succ
insert into ts_tb values('-08-19 11.11.11');	--err
insert into ts_tb values('22022-08-19 11.11.11');  --err
select * from ts_tb;
select to_char(a, 'YYYY-MM-DD') from ts_tb;
alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24.MI.SS';
select * from ts_tb;
drop table ts_tb;

alter session set NLS_DATE_FORMAT='YY-MM-DD HH24.MI.SS';
create table ts_tb(a date);
insert into ts_tb values('2022-08-19 11.11.11');   --succ
insert into ts_tb values('122-08-19 11.11.11');    --succ
insert into ts_tb values('23-08-19 11.11.11');     --succ
insert into ts_tb values('4-08-19 11.11.11');     --succ
insert into ts_tb values('-08-19 11.11.11');	--err
insert into ts_tb values('22022-08-19 11.11.11');  --err
select * from ts_tb;
select to_char(a, 'YYYY-MM-DD') from ts_tb;
alter session set NLS_DATE_FORMAT='YYYY-MM-DD HH24.MI.SS';
select * from ts_tb;
drop table ts_tb;

reset nls_date_format;
reset nls_timestamp_format;

create table inytom_tb(ytom_clo interval year to month);
insert into inytom_tb values(interval '1-   11   ' year to month);
select * from inytom_tb;
drop table inytom_tb;

create table indtos_tb(dtos_clo interval day to second);
insert into indtos_tb values(interval '2 6: 23' day to minute);
insert into indtos_tb values(interval '2 6:16: 23' day to second);
select * from indtos_tb;
drop table indtos_tb;

alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH.MI.SS.FF AM';
create table ts_tb(a timestamp);
insert into ts_tb values('2022-08-19 12.37.05');
insert into ts_tb values('2022-08-19 12.00.00');
insert into ts_tb values('2022-08-19 12.59.00');
insert into ts_tb values('2022-08-19 11.59.59');
select * from ts_tb;
drop table ts_tb;

reset nls_timestamp_format;


alter session set NLS_DATE_FORMAT='D YYYY-MM-DD HH24.MI.SS';
create table date_tb(date_clo date);
insert into date_tb values('2022-08-22 11.11.11'); --err
alter session set NLS_DATE_FORMAT='DDD YYYY-MM-DD HH24.MI.SS';
insert into date_tb values('2022-08-23 11.11.11'); --err
alter session set NLS_DATE_FORMAT='J YYYY-MM-DD HH24.MI.SS'; 
insert into date_tb values('2459814 2022-08-22 11.11.11'); --succ
alter session set NLS_DATE_FORMAT='FX YYYY-MM-DD HH24.MI.SS';
insert into date_tb values('2022-08-23 11.11.11');	--err
insert into date_tb values('  2022-08-23 11.11.11'); --err
insert into date_tb values(' 2022-08-23 11.11.11'); --succ
insert into date_tb values(' 2022/08-23 11.11.11'); --err
insert into date_tb values(' 2022 -08-23 11.11.11'); --err
insert into date_tb values(' 2022- 08-23 11.11.11'); --err
insert into date_tb values(' 2022-08 -23 11.11.11'); --err
insert into date_tb values(' 2022-08-23  11.11.11'); --err
select * from date_tb;
drop table date_tb;



--timestamp:
alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24.MI.SS.FF';
create table ts_tb(a timestamp);
insert into ts_tb values('2022-0823-19 11.11.11');          --succ			 expect:2022-08-23 19.11.11.110000
insert into ts_tb values('2022-082323-19 11.11.11');        --err
insert into ts_tb values('2022-08-011 11.11.11');          --err
insert into ts_tb values('2022-08-232 11.11.11');        --err
insert into ts_tb values('22022-08-19 11.11.11');          --err
insert into ts_tb values('2022-08-19 004.37.05');          --err
insert into ts_tb values('2022-08-19 11.037.05');          --err
insert into ts_tb values('2022-08-19 11.+37.05');          --succ            expect:2022-08-19 11.37.05.000000
insert into ts_tb values('2022-08-19 11.05.037');          --err
insert into ts_tb values('2022-08-19 11.05.+37');          --succ             expect:2022-08-19 11.05.37.000000
alter session set NLS_TIMESTAMP_FORMAT='YYY-MM-DD HH24.MI.SS.FF';
insert into ts_tb values('2022-08-19 11.11.11');          --err
select * from ts_tb;
drop table ts_tb;

--timestamptz:
alter session set NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24.MI.SS.FF TZH:TZM';
create table tswtz_tb(a timestamp with time zone);
insert into tswtz_tb values('2022-082323-19 11.11.11');        --succ     expect:2022-08-23 23.19.11.110000 +11:00
insert into tswtz_tb values('2022-08-011 11.11.11');          --err
insert into tswtz_tb values('2022-08-232 11.11.11');        --err
insert into tswtz_tb values('22022-08-19 11.11.11');          --err
insert into tswtz_tb values('2022-08-19 004.37.05');          --err
insert into tswtz_tb values('2022-08-19 11.037.05');          --err
insert into tswtz_tb values('2022-08-19 11.+37.05');          --succ        expect:2022-08-19 11.37.05.000000 +08:00
insert into tswtz_tb values('2022-08-19 11.05.037');          --err
insert into tswtz_tb values('2022-08-19 11.05.+37');          --succ         expect:2022-08-19 11.05.37.000000 +08:00
alter session set NLS_TIMESTAMP_TZ_FORMAT='YYY-MM-DD HH24.MI.SS.FF';
insert into tswtz_tb values('2022-08-19 11.11.11');          --err
alter session set NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24.MI.SS.FF';
select * from tswtz_tb;
drop table tswtz_tb;

--date
alter session set NLS_DATE_FORMAT='YYYY-MM-DD HH24.MI.SS';
create table t_tb(a date);
insert into t_tb values('2022-08-19 11.+37.05');          --succ	expect:2022-08-19 11.37.05
insert into t_tb values('2022-08-19 11.05.037');          --err
select * from t_tb;
drop table t_tb;



alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH.MI.SS.FF AM';
create table ts_tb(a timestamp);
insert into ts_tb values ('2022-09-+08 11.11.11');
insert into ts_tb values ('2022-09--08 11.11.11'); --err
insert into ts_tb values ('2022-08-19 ++11.11.11');
insert into ts_tb values ('2022-08-19 11.+11.11');
insert into ts_tb values ('2022-08-19 11.11.1 1'); --err
insert into ts_tb values ('2022-08-19 11.11.+11');
insert into ts_tb values ('2022-08-19 11.11.1-1'); --err
insert into ts_tb values ('2022-08-19 03.37.05.+471801 PM');
select * from ts_tb;
drop table ts_tb;



alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH.MI.SS.FF AM';
CREATE TABLE timestp_tb(timestp_clo timestamp);
insert into timestp_tb values('2022-08-19 03.37.05.47801310 PM'); 
insert into timestp_tb values('2022-08-19 03.37.05.47801370 PM');
insert into timestp_tb values('2022-08-19 03.37.05 PM');
select * from timestp_tb;
drop table timestp_tb;
alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH.MI.SS.FF7 AM';
CREATE TABLE timestp_tb(timestp_clo timestamp(5));
insert into timestp_tb values ('2022-08-19 03.37.05 PM');
select * from timestp_tb;
drop table timestp_tb;
alter session set NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24.MI.SS.FF7 TZH:TZM';
CREATE TABLE timestpwtz_tb(timestpwtz_clo timestamp with time zone);
insert into timestpwtz_tb values ('2022-08-19 03.37.05.4780130000');
insert into timestpwtz_tb values ('2022-08-19 03.37.05.47801300');
insert into timestpwtz_tb values ('2022-08-19 03.37.05.478041');
select * from timestpwtz_tb;
drop table timestpwtz_tb;
alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH.MI.SS.FF5 AM';
CREATE TABLE timestp_tb(timestp_clo timestamp(7));
insert into timestp_tb values ('2022-08-19 03.37.05 PM');
select * from timestp_tb;
drop table timestp_tb;

reset nls_date_format;
reset nls_timestamp_format;
reset nls_timestamp_tz_format;



alter session set NLS_TIMESTAMP_FORMAT='RR-MM-DD HH24.MI.SS.FF';
create table timestp_tb(timestp_clo timestamp);
INSERT INTO timestp_tb VALUES('2022-08-19 11.11.11');   --succ  22-08-19 11.11.11.000000
insert into timestp_tb values('122-08-19 11.11.11');  --succ  22-08-19 11.11.11
select * from timestp_tb;
alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24.MI.SS.FF';
select * from timestp_tb;
drop table timestp_tb;

alter session set NLS_TIMESTAMP_TZ_FORMAT='RR-MM-DD HH24.MI.SS.FF TZH:TZM';
create table timestpwtz_tb(timestp_clo timestamp with time zone);
INSERT INTO timestpwtz_tb VALUES('2022-08-19 11.11.11'); 
insert into timestpwtz_tb values('122-08-19 11.11.11');
select * from timestpwtz_tb;
alter session set NLS_TIMESTAMP_TZ_FORMAT='YYYY-MM-DD HH24.MI.SS.FF TZH:TZM';
select * from timestpwtz_tb;
drop table timestpwtz_tb;

alter session set NLS_TIMESTAMP_FORMAT='RR-MM-DD HH24.MI.SS.FF';
create table timestpwltz_tb(timestp_clo timestamp with local time zone);
INSERT INTO timestpwltz_tb VALUES('2022-08-19 11.11.11'); 
insert into timestpwltz_tb values('122-08-19 11.11.11');
select * from timestpwltz_tb;
alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24.MI.SS.FF';
select * from timestpwltz_tb;
drop table timestpwltz_tb;

alter session set NLS_DATE_FORMAT='RR-MM-DD HH24.MI.SS';
create table ds_tb(date_clo date);
INSERT INTO ds_tb VALUES('2022-08-19 11.11.11');   --succ  22-08-19 11.11.11
insert into ds_tb values('122-08-19 11.11.11');  --succ  22-08-19 11.11.11
select * from ds_tb;
alter session set NLS_DATE_FORMAT='YYYY-MM-DD HH24.MI.SS';
select * from ds_tb;
drop table ds_tb;



alter session set NLS_TIMESTAMP_FORMAT='RRRR-MM-DD HH24.MI.SS.FF';
create table timestp_tb(timestp_clo timestamp);
INSERT INTO timestp_tb VALUES('22022-08-19 11.11.11');   --err
INSERT INTO timestp_tb VALUES('2022-08-19 11.11.11');   --succ
INSERT INTO timestp_tb VALUES('022-08-19 11.11.11');   --succ
INSERT INTO timestp_tb VALUES('22-08-19 11.11.11');   --succ
INSERT INTO timestp_tb VALUES('2-08-19 11.11.11');   --succ
INSERT INTO timestp_tb VALUES('202208-19 11.11.11');   --succ
INSERT INTO timestp_tb VALUES('20220819 11.11.11');   --succ
select * from timestp_tb;
drop table timestp_tb;

alter session set NLS_TIMESTAMP_TZ_FORMAT='RRRR-MM-DD HH24.MI.SS.FF TZH:TZM';
create table timestpwtz_tb(timestp_clo timestamp with time zone);
INSERT INTO timestpwtz_tb VALUES('22022-08-19 11.11.11');   --err
INSERT INTO timestpwtz_tb VALUES('2022-08-19 11.11.11');   --succ
INSERT INTO timestpwtz_tb VALUES('022-08-19 11.11.11');   --succ
INSERT INTO timestpwtz_tb VALUES('22-08-19 11.11.11');   --succ
INSERT INTO timestpwtz_tb VALUES('2-08-19 11.11.11');   --succ
INSERT INTO timestpwtz_tb VALUES('202208-19 11.11.11');   --succ
INSERT INTO timestpwtz_tb VALUES('20220819 11.11.11');   --succ
select * from timestpwtz_tb;
drop table timestpwtz_tb;

alter session set NLS_TIMESTAMP_FORMAT='RRRR-MM-DD HH24.MI.SS.FF';
create table timestpwltz_tb(timestp_clo timestamp with local time zone);
INSERT INTO timestpwltz_tb VALUES('22022-08-19 11.11.11');  --err
INSERT INTO timestpwltz_tb VALUES('2022-08-19 11.11.11');   --succ
INSERT INTO timestpwltz_tb VALUES('022-08-19 11.11.11');   --succ
INSERT INTO timestpwltz_tb VALUES('22-08-19 11.11.11');   --succ
INSERT INTO timestpwltz_tb VALUES('2-08-19 11.11.11');   --succ
INSERT INTO timestpwltz_tb VALUES('202208-19 11.11.11');   --succ
INSERT INTO timestpwltz_tb VALUES('20220819 11.11.11');   --succ
select * from timestpwltz_tb;
drop table timestpwltz_tb;

alter session set NLS_DATE_FORMAT='RRRR-MM-DD HH24.MI.SS';
create table ds_tb(timestp_clo date);
INSERT INTO ds_tb VALUES('22022-08-19 11.11.11');   --err
INSERT INTO ds_tb VALUES('2022-08-19 11.11.11');   --succ
INSERT INTO ds_tb VALUES('022-08-19 11.11.11');   --succ
INSERT INTO ds_tb VALUES('22-08-19 11.11.11');   --succ
INSERT INTO ds_tb VALUES('2-08-19 11.11.11');   --succ
INSERT INTO ds_tb VALUES('202208-19 11.11.11');   --succ
INSERT INTO ds_tb VALUES('20220819 11.11.11');   --succ
select * from ds_tb;
drop table ds_tb;

reset NLS_TIMESTAMP_FORMAT;
reset NLS_TIMESTAMP_TZ_FORMAT;
reset NLS_DATE_FORMAT;

