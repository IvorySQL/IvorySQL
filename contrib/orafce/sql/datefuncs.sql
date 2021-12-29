\set VERBOSITY terse
SET client_encoding = utf8;
set datestyle='ISO,MDY';
set time zone 'PRC';
set compatible_mode to oracle;

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

--trunc function
select oracle.trunc(cast('2050-12-12' as oracle.date), 'SCC');
select oracle.trunc(cast('2050-06-12' as oracle.date), 'SYYYY');
select oracle.trunc(cast('2020-02-28' as oracle.date), 'IYYY');
select oracle.trunc(cast('2020-02-28' as oracle.date), 'Q');
select oracle.trunc(cast('2020-09-27' as oracle.date), 'MONTH');
select oracle.trunc(cast('2020-03-15' as oracle.date), 'WW');
select oracle.trunc(cast('2020-02-28' as oracle.date), 'IW');
select oracle.trunc(cast('2020-02-23' as oracle.date), 'W');
select oracle.trunc(cast('2020-06-18' as oracle.date), 'DDD');
select oracle.trunc(cast('2020-02-29' as oracle.date), 'DAY');
select oracle.trunc(cast('2050-12-12 12:12:13' as oracle.date), 'SCC');
select oracle.trunc(cast('2050-06-12 19:00:00' as oracle.date), 'SYYYY');
select oracle.trunc(cast('2020-02-28 20:00:00' as oracle.date), 'IYYY');
select oracle.trunc(cast('2020-02-28 21:01:09' as oracle.date), 'Q');
select oracle.trunc(cast('2020-09-27 22:10:12' as oracle.date), 'MONTH');
select oracle.trunc(cast('2020-03-15 23:15:36' as oracle.date), 'WW');
select oracle.trunc(cast('2020-02-28 09:11:12' as oracle.date), 'IW');
select oracle.trunc(cast('2020-02-23 14:20:18' as oracle.date), 'W');
select oracle.trunc(cast('2020-06-18 22:20:12' as oracle.date), 'DDD');
select oracle.trunc(cast('2020-02-29 08:00:01' as oracle.date), 'DAY');
select oracle.trunc(timestamp '2051-12-12 12:00:00', 'SCC');
select oracle.trunc(timestamp '2050-06-12 19:20:21', 'SYYYY');
select oracle.trunc(timestamp '2020-02-28 16:40:55', 'IYYY');
select oracle.trunc(timestamp '2020-07-28 19:16:12', 'Q');
select oracle.trunc(timestamp '2020-09-27 18:30:21', 'MONTH');
select oracle.trunc(timestamp '2020-03-15 12:12:19', 'WW');
select oracle.trunc(timestamp '2020-02-28 10:00:01', 'IW');
select oracle.trunc(timestamp '2020-02-23 12:12:14', 'W');
select oracle.trunc(timestamp '2020-06-18 13:12:18', 'DDD');
select oracle.trunc(timestamp '2020-02-29 14:40:20', 'DAY');
select oracle.trunc(timestamp '2020-02-29 11:40:20', 'HH');
select oracle.trunc(timestamp '2020-02-29 18:40:20', 'MI');
select oracle.trunc(timestamptz '2051-12-12 12:00:00 + 08', 'SCC');
select oracle.trunc(timestamptz '2050-06-12 19:20:21 + 08', 'SYYYY');
select oracle.trunc(timestamptz '2020-02-28 16:40:55 + 08', 'IYYY');
select oracle.trunc(timestamptz '2020-02-28 19:16:12 + 08', 'Q');
select oracle.trunc(timestamptz '2020-09-27 18:30:21 + 08', 'MONTH');
select oracle.trunc(timestamptz '2020-03-15 12:12:19 + 08', 'WW');
select oracle.trunc(timestamptz '2020-02-28 10:00:01 + 08', 'IW');
select oracle.trunc(timestamptz '2020-02-23 12:12:14 + 08', 'W');
select oracle.trunc(timestamptz '2020-06-18 13:12:18 + 08', 'DDD');
select oracle.trunc(timestamptz '2020-02-29 14:40:20 + 08', 'DAY');
select oracle.trunc(timestamptz '2020-02-29 11:40:20 + 08', 'HH');
select oracle.trunc(timestamptz '2020-02-29 14:40:50 + 08', 'MI');

--round function
select oracle.round(cast('2012-12-12' as oracle.date), 'CC');
select oracle.round(cast('2051-12-12' as oracle.date), 'SCC');
select oracle.round(cast('2050-12-12' as oracle.date), 'SYYYY');
select oracle.round(cast('2050-06-12' as oracle.date), 'IYYY');
select oracle.round(cast('2020-01-1'  as oracle.date), 'Q');
select oracle.round(cast('2020-02-15' as oracle.date), 'MONTH');
select oracle.round(cast('2020-02-29' as oracle.date), 'WW');
select oracle.round(cast('2020-03-15' as oracle.date), 'IW');
select oracle.round(cast('2020-02-28' as oracle.date), 'W');
select oracle.round(cast('2020-03-15' as oracle.date), 'DDD');
select oracle.round(cast('2020-06-18' as oracle.date), 'DAY');
select oracle.round(cast('2012-12-12 12:13:15' as oracle.date), 'CC');
select oracle.round(cast('2051-12-12 19:00:00' as oracle.date), 'SCC');
select oracle.round(cast('2050-12-12 20:00:00' as oracle.date), 'SYYYY');
select oracle.round(cast('2050-06-12 21:40:00' as oracle.date), 'IYYY');
select oracle.round(cast('2020-01-1 22:00:00'  as oracle.date), 'Q');
select oracle.round(cast('2020-02-15 23:57:09' as oracle.date), 'MONTH');
select oracle.round(cast('2020-02-29 11:11:00' as oracle.date), 'WW');
select oracle.round(cast('2020-03-15 09:05:21' as oracle.date), 'IW');
select oracle.round(cast('2020-02-28 21:11:01' as oracle.date), 'W');
select oracle.round(cast('2020-03-15 13:04:21' as oracle.date), 'DDD');
select oracle.round(cast('2020-06-18 22:03:01' as oracle.date), 'DAY');
select oracle.round(timestamp '2012-12-12 12:00:00', 'CC');
select oracle.round(timestamp '2050-12-12 12:00:00', 'SCC');
select oracle.round(timestamp '2050-06-12 19:20:21', 'SYYYY');
select oracle.round(timestamp '2050-06-12 16:40:55', 'IYYY');
select oracle.round(timestamp '2020-02-16 19:16:12', 'Q');
select oracle.round(timestamp '2020-09-27 18:30:21', 'MONTH');
select oracle.round(timestamp '2020-03-15 12:12:19', 'WW');
select oracle.round(timestamp '2020-02-28 10:00:01', 'IW');
select oracle.round(timestamp '2020-02-23 12:12:14', 'W');
select oracle.round(timestamp '2020-06-18 13:12:18', 'DDD');
select oracle.round(timestamp '2020-02-29 14:40:20', 'DAY');
select oracle.round(timestamp '2020-02-29 11:40:20', 'HH');
select oracle.round(timestamp '2020-02-29 14:40:20', 'MI');
select oracle.round(timestamptz '2012-12-12 12:00:00 + 08', 'CC');
select oracle.round(timestamptz '2050-12-12 12:00:00 + 08', 'SCC');
select oracle.round(timestamptz '2051-12-12 12:00:00 + 08', 'SCC');
select oracle.round(timestamptz '2050-06-12 19:20:21 + 08', 'SYYYY');
select oracle.round(timestamptz '2050-06-12 16:40:55 + 08', 'IYYY');
select oracle.round(timestamptz '2020-02-16 19:16:12 + 08', 'Q');
select oracle.round(timestamptz '2020-09-27 18:30:21 + 08', 'MONTH');
select oracle.round(timestamptz '2020-03-15 12:12:19 + 08', 'WW');
select oracle.round(timestamptz '2020-02-28 10:00:01 + 08', 'IW');
select oracle.round(timestamptz '2020-02-23 12:12:14 + 08', 'W');
select oracle.round(timestamptz '2020-06-18 13:12:18 + 08', 'DDD');
select oracle.round(timestamptz '2020-02-29 14:40:20 + 08', 'DAY');
select oracle.round(timestamptz '2020-02-29 11:40:20 + 08', 'HH');
select oracle.round(timestamptz '2020-06-18 14:40:20 + 08', 'MI');

--next_day function
select oracle.next_day(date '2020-02-15', 'Monday') from dual;
select oracle.next_day(date '2020-02-29', 'Monday') from dual;
select oracle.next_day(date '2020-06-14', 'Wednesday') from dual;
select oracle.next_day(date '2020-07-20', 'Wednesday') from dual;
select oracle.next_day(date '2020-09-15', 'Friday') from dual;
select oracle.next_day(date '2020-09-22', 'Friday') from dual;
select oracle.next_day(date '2020-02-15', 2) from dual;
select oracle.next_day(date '2020-02-29', 2) from dual;
select oracle.next_day(date '2020-06-14', 4) from dual;
select oracle.next_day(date '2020-07-20', 4) from dual;
select oracle.next_day(date '2020-09-15', 6) from dual;
select oracle.next_day(date '2020-09-22', 6) from dual;
select oracle.next_day(oracle.date '2020-02-15 12:10:10', 2) from dual;
select oracle.next_day(oracle.date '2020-02-29 09:45:59', 3) from dual;
select oracle.next_day(oracle.date '2020-06-14 01:20:12', 4) from dual;
select oracle.next_day(oracle.date '2020-07-20 14:20:23', 5) from dual;
select oracle.next_day(oracle.date '2020-09-15 05:19:43', 6) from dual;
select oracle.next_day(oracle.date '2020-09-22 12:00:00', 7) from dual;
select oracle.next_day(to_timestamp('2020-02-29 14:40:50', 'YYYY-MM-DD HH24:MI:SS'), 'Tuesday') from dual;
select oracle.next_day(to_timestamp('2020-05-05 19:43:51', 'YYYY-MM-DD HH24:MI:SS'), 'thursday') from dual;
select oracle.next_day(to_timestamp('2020-06-22 19:43:51', 'YYYY-MM-DD HH24:MI:SS'), 'Saturday') from dual;
select oracle.next_day(to_timestamp('2020-07-01 19:43:51', 'YYYY-MM-DD HH24:MI:SS'), 'Sunday') from dual;
select oracle.next_day(to_timestamp('2020-02-29 14:40:50', 'YYYY-MM-DD HH24:MI:SS'), 3) from dual;
select oracle.next_day(to_timestamp('2020-05-05 19:43:51', 'YYYY-MM-DD HH24:MI:SS'), 5) from dual;
select oracle.next_day(to_timestamp('2020-06-22 19:43:51', 'YYYY-MM-DD HH24:MI:SS'), 7) from dual;
select oracle.next_day(to_timestamp('2020-07-01 19:43:51', 'YYYY-MM-DD HH24:MI:SS'), 1) from dual;
select oracle.next_day('2020-02-29 14:40:50'::timestamptz, 'Tuesday') from dual;
select oracle.next_day('2020-05-05 19:43:51'::timestamptz, 'thursday') from dual;
select oracle.next_day('2020-06-22 19:43:51'::timestamptz, 'Saturday') from dual;
select oracle.next_day('2020-07-01 19:43:51'::timestamptz, 'Sunday') from dual;
select oracle.next_day('2020-02-29 14:40:50'::timestamptz, 3) from dual;
select oracle.next_day('2020-05-05 19:43:51'::timestamptz, 5) from dual;
select oracle.next_day('2020-06-22 19:43:51'::timestamptz, 7) from dual;
select oracle.next_day('2020-07-01 19:43:51'::timestamptz, 1) from dual;

--last_day function
select oracle.last_day(date '2020-02-15');
select oracle.last_day(date '2020-07-11');
select oracle.last_day(date '2020-09-09');
select oracle.last_day(date '2020-02-15');
select oracle.last_day(date '2020-07-11');
select oracle.last_day(date '2020-09-09');
select oracle.last_day(date '2020-02-15');
select oracle.last_day(date '2020-11-11');
select oracle.last_day(date '2020-09-09');
select oracle.last_day('2020-02-12 12:45:12'::timestamp) from dual;
select oracle.last_day(timestamp '2020-05-17 13:27:19') from dual;
select oracle.last_day(timestamp '2020-08-21 19:20:40') from dual;
select oracle.last_day('2020-10-05 12:45:12 +08'::timestamptz) from dual;
select oracle.last_day('2020-12-17 13:27:19 +08'::timestamptz) from dual;
select oracle.last_day('2020-11-29 19:20:40 +08'::timestamptz) from dual;
select oracle.last_day('-0001-3-1 13:27:19'::oracle.date) from dual;
select oracle.last_day('-0001-4-1 13:27:19'::oracle.date) from dual;
select oracle.last_day('-0001-2-1 13:27:19'::oracle.date) from dual;
select oracle.last_day('-0004-2-1 13:27:19'::oracle.date) from dual;

select oracle.last_day(oracle.date '2021-01-15 14:20:23');
select oracle.last_day(oracle.date '2021-02-11 09:10:21');
select oracle.last_day(oracle.date '2021-03-09 12:33:11');
select oracle.last_day(oracle.date '2021-04-15 11:59:59');
select oracle.last_day(oracle.date '2021-05-01 12:10:01');
select oracle.last_day(oracle.date '2021-06-18 01:00:01');
select oracle.last_day(oracle.date '2021-07-07 05:20:18');
select oracle.last_day(oracle.date '2021-08-15 17:19:13');
select oracle.last_day(oracle.date '2021-09-15 16:19:10');
select oracle.last_day(oracle.date '2021-11-11 17:30:00');
select oracle.last_day(oracle.date '2021-12-09 22:00:00');

