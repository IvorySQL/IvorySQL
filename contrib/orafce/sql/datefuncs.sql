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

