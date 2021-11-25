\set VERBOSITY terse
SET client_encoding = utf8;
set datestyle='ISO,MDY';
set time zone 'PRC';

select oracle.from_tz('2021-11-08 09:12:39','+16:00') from dual;
select oracle.from_tz('2021-11-08 09:12:39','-12:00') from dual;
select oracle.from_tz('2021-11-08 09:12:39','Asia/Shanghai123123') from dual;
select oracle.from_tz('2021-11-08 09:12:39','Asia/Shanghai') from dual;
select oracle.from_tz('2021-11-08 09:12:39','SAST') from dual;
select oracle.from_tz('2021-11-08 09:12:39','SAST123') from dual;
select oracle.from_tz(NULL,'SAST') from dual;
select oracle.from_tz('2021-11-08 09:12:31',NULL) from dual;
select oracle.from_tz(NULL,NULL) from dual;

--numtodsinterval function
select oracle.numtodsinterval(2147483647.1232131232,'day') from dual;
select oracle.numtodsinterval(2147483646.1232131232,'day') from dual;
select oracle.numtodsinterval(2147483647.1232131232,'hour') from dual;
select oracle.numtodsinterval(2147483648.1232131232,'hour') from dual;
select oracle.numtodsinterval(128849018879.1232131232,'minute') from dual;
select oracle.numtodsinterval(128849018880.1232131232,'minute') from dual;
select oracle.numtodsinterval(7730941132799.1232131232,'second') from dual;
select oracle.numtodsinterval(7730941132800.1232131232,'second') from dual;
select oracle.numtodsinterval(NULL,'second') from dual;
select oracle.numtodsinterval(7730941132800.1232131232,NULL) from dual;
select oracle.numtodsinterval(NULL,NULL) from dual;

--numtoyminterval function
select oracle.numtoyminterval(178956970.1232131232,'year') from dual;
select oracle.numtoyminterval(178956971.1232131232,'year') from dual;
select oracle.numtoyminterval(2147483646.1232131232,'month') from dual;
select oracle.numtoyminterval(2147483647.1232131232,'month') from dual;
select oracle.numtoyminterval(NULL,'month') from dual;
select oracle.numtoyminterval(2147483647.1232131232,NULL) from dual;
select oracle.numtoyminterval(NULL,NULL) from dual;

--sys_extract_utc function
select oracle.sys_extract_utc('2018-03-28 11:30:00.00 +09:00'::timestamptz) from dual;
select oracle.sys_extract_utc(NULL) from dual;

--sessiontimezone and dbtimezone function
select oracle.sessiontimezone() from dual;
select oracle.dbtimezone() from dual;

--days_between function
select oracle.days_between('2021-11-25 15:33:16'::timestamp,'2019-01-01 00:00:00'::timestamp) from dual;
select oracle.days_between('2019-09-08 09:09:09'::timestamp,'2019-01-01 00:00:00'::timestamp) from dual;
select oracle.days_between('2021-11-25 09:09:09'::timestamp,'2019-01-01 00:00:00'::timestamp) from dual;
select oracle.days_between(NULL,'2019-01-01 00:00:00'::timestamp) from dual;
select oracle.days_between('2019-09-08 09:09:09'::timestamp,NULL) from dual;
select oracle.days_between(NULL,NULL) from dual;

--days_between_tmtz function
select oracle.days_between_tmtz('2019-09-08 09:09:09+08'::timestamptz,'2019-05-08 12:34:09+08'::timestamptz) from dual;
select oracle.days_between_tmtz('2019-09-08 09:09:09+08'::timestamptz,'2019-05-08 12:34:09+09'::timestamptz) from dual;
select oracle.days_between_tmtz('2019-09-08 09:09:09-08'::timestamptz,'2019-05-08 12:34:09+09'::timestamptz) from dual;
select oracle.days_between_tmtz(NULL,'2019-05-08 12:34:09+08'::timestamptz) from dual;
select oracle.days_between_tmtz('2019-09-08 09:09:09+08'::timestamptz,NULL) from dual;
select oracle.days_between_tmtz(NULL,NULL) from dual;

--add_days_to_timestamp function
select oracle.add_days_to_timestamp('1009-09-15 09:00:00'::timestamp, '3267.123'::numeric) from dual;
select oracle.add_days_to_timestamp(NULL, '3267.123'::numeric) from dual;
select oracle.add_days_to_timestamp('1009-09-15 09:00:00'::timestamp, NULL) from dual;
select oracle.add_days_to_timestamp(NULl, NULL) from dual;

--subtract function
select oracle.subtract('2019-11-25 16:51:20'::timestamp,'3267.123'::numeric) from dual;
select oracle.subtract('2019-11-25 16:51:20'::timestamp, '2018-11-25 16:51:12'::timestamp) from dual;
select oracle.subtract(NULL,'3267.123'::numeric) from dual;
select oracle.subtract('2019-11-25 16:51:20'::timestamp,NULL) from dual;
select oracle.subtract(NULL,NULL) from dual;