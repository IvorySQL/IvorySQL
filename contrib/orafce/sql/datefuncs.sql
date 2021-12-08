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

--new_time function
select oracle.new_time(timestamp '2020-12-12 17:45:18', 'AST', 'ADT') from dual;
select oracle.new_time(timestamp '2020-12-12 17:45:18', 'BST', 'BDT') from dual;
select oracle.new_time(timestamp '2020-12-12 17:45:18', 'CST', 'CDT') from dual;
select oracle.new_time(timestamp '2020-12-12 17:45:18', 'EST', 'EDT') from dual;
select oracle.new_time(timestamp '2020-12-12 17:45:18', 'HST', 'HDT') from dual;
select oracle.new_time(timestamp '2020-12-12 17:45:18', 'MST', 'MDT') from dual;
select oracle.new_time(timestamp '2020-12-12 17:45:18', 'PST', 'PDT') from dual;
select oracle.new_time(timestamp '2020-12-12 17:45:18', 'YST', 'YDT') from dual;
select oracle.new_time(timestamp '2020-12-12 17:45:18', 'GMT', 'EDT') from dual;
select oracle.new_time(timestamp '2020-12-12 17:45:18', 'NST', 'GMT') from dual;
select oracle.new_time('2020-10-12 17:42:58 +08'::timestamptz, 'AST', 'ADT') from dual;
select oracle.new_time('2020-11-12 17:42:58 +08'::timestamptz, 'BST', 'BDT') from dual;
select oracle.new_time('2020-12-12 13:45:58 +08'::timestamptz, 'CST', 'CDT') from dual;
select oracle.new_time('2020-10-12 13:45:18 +08'::timestamptz, 'EST', 'EDT') from dual;
select oracle.new_time('2020-11-12 17:49:18 +08'::timestamptz, 'HST', 'HDT') from dual;
select oracle.new_time('2020-12-12 17:49:28 +08'::timestamptz, 'MST', 'MDT') from dual;
select oracle.new_time('2020-10-12 17:45:28 +08'::timestamptz, 'PST', 'PDT') from dual;
select oracle.new_time('2020-10-12 16:45:18 +08'::timestamptz, 'YST', 'YDT') from dual;
select oracle.new_time('2020-11-12 16:41:28 +08'::timestamptz, 'GMT', 'EDT') from dual;
select oracle.new_time('2020-12-12 17:41:18 +08'::timestamptz, 'NST', 'GMT') from dual;

set compatible_mode to oracle ;
--add_months function
select oracle.add_months(oracle.date '2020-02-15',7) from dual;
select oracle.add_months(oracle.date '2018-12-15',14) from dual;
select oracle.add_months(oracle.date '2019-12-15',12) from dual;
select oracle.add_months(oracle.date '0019-12-15',40) from dual;
select oracle.add_months(timestamp '2020-02-15 12:12:09',7) from dual;
select oracle.add_months(timestamp '2018-12-15 19:12:09',14) from dual;
select oracle.add_months(timestamp '2018-12-15 19:12:09',12) from dual;
select oracle.add_months(timestamp '2018-12-15 19:12:09',40) from dual;
select oracle.add_months(timestamptz'2020-02-15 12:12:09 +08',7) from dual;
select oracle.add_months(timestamptz'2018-12-15 12:12:09 +08',24) from dual;
select oracle.add_months(timestamptz'2018-12-15 12:12:09 +08',100) from dual;
select oracle.add_months(timestamptz'2018-12-15 12:12:09 +08',120) from dual;
select oracle.add_months(oracle.date '-2020-02-15',7) from dual;
select oracle.add_months(oracle.date '-2018-12-15',14) from dual;
select oracle.add_months(oracle.date '-2019-12-15',12) from dual;
select oracle.add_months(oracle.date '-0019-12-15',40) from dual;
select oracle.add_months(oracle.date '-0002-12-15',40) from dual;
select oracle.add_months(oracle.date '0002-12-15',-40) from dual;
select oracle.add_months(oracle.date '-0002-12-15 12:14:15',40) from dual;
select oracle.add_months(oracle.date '-0002-12-15 12:14:15',12) from dual;
select oracle.add_months(oracle.date '-0002-12-15 12:14:15',13) from dual;
select oracle.add_months(oracle.date '0002-12-15 10:02:09',-40) from dual;
select oracle.add_months(oracle.date '0002-12-15 10:02:09',-23) from dual;
select oracle.add_months(oracle.date '0002-12-15 10:02:09',-24) from dual;

--months_between function
select oracle.months_between(oracle.date '2020-03-15', oracle.date '2020-02-20') from dual;
select oracle.months_between(oracle.date '2020-02-10', oracle.date '2020-05-20') from dual;
select oracle.months_between(oracle.date '2021-11-10', oracle.date '2020-05-20') from dual;
select oracle.months_between(oracle.date '2021-11-10', oracle.date '2008-05-20') from dual;
select oracle.months_between(timestamp '2021-11-10 20:20:20', timestamp '2020-05-20 16:20:20') from dual;
select oracle.months_between(timestamp '2022-05-15 20:20:20', timestamp '2020-01-20 19:20:20') from dual;
select oracle.months_between(timestamp '2021-11-10 20:20:20', timestamp '2020-05-20 16:20:20') from dual;
select oracle.months_between(timestamp '2020-11-10 20:20:20', timestamp '2025-05-20 16:20:20') from dual;
select oracle.months_between(timestamptz '2021-11-10 20:20:20 +08', timestamptz '2020-05-20 16:20:20 +08') from dual;
select oracle.months_between(timestamptz '2021-11-10 00:00:00 +08', timestamptz '2020-05-20 16:20:20 +08') from dual;
select oracle.months_between(oracle.date '2021-11-10', timestamptz '2020-05-20 16:20:20 +08') from dual;
select oracle.months_between(timestamptz '2020-01-10 01:00:00 +08', timestamptz '2028-05-19 16:25:20 +08') from dual;
select oracle.months_between(timestamptz '2021-11-10 20:20:20 +05', timestamptz '2020-05-20 16:20:20 +03') from dual;
select oracle.months_between(timestamptz '2008-01-31 11:32:11 +8', timestamptz '2008-02-29 11:12:12') from dual;
select oracle.months_between(oracle.date '-2020-03-15', oracle.date '-2020-02-20') from dual;
select oracle.months_between(oracle.date '-2020-02-10', oracle.date '-2020-05-20') from dual;
select oracle.months_between(oracle.date '-2021-11-10', oracle.date '-2020-05-20') from dual;
select oracle.months_between(oracle.date '-2021-11-10 12:12:30', oracle.date '-2008-05-20 13:15:12') from dual;