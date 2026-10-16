--
-- ora_ascii.sql: test ASCII function
--
--
select ascii(321) from dual;

select ascii(213.3f) from dual;

select ascii(123.4d) from dual;

select ascii('abc') from dual;

select ascii('xyz') from dual;

select ascii(to_char('2026-01-01'::date,'DD-MON-YYYY HH24:MI:SS')) from dual;

select ascii(to_char('2026-01-11 01:02:03.00'::timestamp,'DD-MON-YYYY HH24:MI:SS.FF6')) from dual;

select ascii(to_char('2026-01-22 01:02:03.00 +01:00'::timestamptz,'DD-MON-YYYY HH24:MI:SS TZH:TZM')) from dual;

select ascii('') is null from dual;