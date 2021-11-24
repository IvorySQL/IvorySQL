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
