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
--bug#0000857
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
insert into datetest values (TO_DSINTERVAL('789 13  : 23 : 34'));/* BUGID:0000440 */
insert into datetest values (TO_DSINTERVAL('P100DT210H100M299.898S'));
insert into datetest values (TO_DSINTERVAL(' P0DT0.0S'));   /* BUGID:0000436 */

select * from datetest;
drop table datetest;

--TO_YMINTERVAL
create table datetest (aa interval year(9) to month);

insert into datetest values (TO_YMINTERVAL('567-08'));
insert into datetest values (TO_YMINTERVAL('P234Y8M66DT100H'));
insert into datetest values (TO_YMINTERVAL('99999999 - 1'));  /* BUGID:0000440 */

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
select tz_offset('-12:59') from dual; /* BUG:0000444 */
select tz_offset('+14:05') from dual; /* BUG:0000444 */
	
select * from datetest;
drop table datetest;

--from_tz
SELECT FROM_TZ(TIMESTAMP '2000-03-28 08:00:00', '3:00') FROM DUAL;
  
--sessiontimezone
set timezone = 'Asia/Hong_Kong';
select sessiontimezone() from dual; /* BUG:0000427 */
alter session set NLS_DATE_FORMAT='DD-MON-RR HH24:MI:SS';
--select current_date from dual;
