--
-- ora_ascii.sql: test ASCII function
--
--
select ascii(321) from dual;

select ascii(213.3f) from dual;

select ascii(123.4d) from dual;

select ascii('abc') from dual;

select ascii('xyz') from dual;

set nls_date_format='DD-MON-YYYY HH24:MI:SS';
select ascii('01-JAN-2026 01:02:03') from dual;

set nls_timestamp_format='DD-MON-YYYY HH24:MI:SS.FF6';
select ascii('11-JAN-2026 01:02:03.00') from dual;

set nls_timestamp_tz_format='DD-MON-YYYY HH24:MI:SS TZH:TZM';
select ascii('22-JAN-2026 01:02:03.00 +01:00') from dual;
