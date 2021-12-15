--Test For rpad
set search_path to oracle, pg_catalog;
set datestyle to ISO,YMD;
SELECT oracle.rpad(123, 20, 0);
SELECT oracle.rpad(123, 20);
SELECT oracle.rpad(123::int2, 20::int2, 0::int2);
SELECT oracle.rpad(123::int4, 20::int4, 0::int4);
SELECT oracle.rpad(123::int4, 20::int4);
SELECT oracle.rpad(123::int8, 20::int8, 0::int8);
SELECT oracle.rpad(123.99::numeric, 20.99::numeric, 0.9::numeric);
SELECT oracle.rpad(123.00::numeric, 20.99::numeric, 0.9::numeric);
SELECT oracle.rpad(123.00::numeric, 20::int, 0::int);
SELECT oracle.rpad(123.00::int, 20.99::numeric, 0.9::numeric);
SELECT oracle.rpad(123.99::numeric, 20.99::numeric);

SELECT oracle.rpad('123', '20'::int, '0');
SELECT oracle.rpad('123', '20.99'::numeric, '0');
SELECT oracle.rpad('123', '20'::int);
SELECT oracle.rpad('123', '20.99'::numeric);
SELECT oracle.rpad('I like'::char(10), 20::int, '#$'::char);
SELECT oracle.rpad('I like'::char(10), 20::int, '#$'::char(2));
SELECT oracle.rpad('I like'::char(10), 20::int);
SELECT oracle.rpad('$@'::char(2), 20, 'I like'::char(10));
SELECT oracle.rpad('$@'::char(2), 20);
SELECT oracle.rpad('I like'::varchar(20), 20::int, '#$'::varchar(20));
SELECT oracle.rpad('I like'::varchar2(20), 20::int, '#$'::varchar2(20));
SELECT oracle.rpad('I like'::nvarchar2(20), 20::int, '#$'::nvarchar2(20));
SELECT rpad('I like'::text, 20::int, '#$'::text);
SELECT oracle.rpad('I like'::text, 20.99::numeric, '#$'::text);
SELECT oracle.rpad('I like'::text, 20.99::numeric);
SELECT rpad('I Love China'::text, 25::int);
SELECT oracle.rpad('I Love China'::text, 25.99::numeric);
SELECT rpad('I Love China'::text, 7::int, '#$'::text);
SELECT oracle.rpad('I Love China'::text, 7.99::numeric, '#$'::text);
SELECT rpad('我来自China'::text, 25::int, '#$'::text);
SELECT oracle.rpad('我来自China'::text, 25.99::numeric, '#$'::text);
SELECT oracle.rpad('我来自China'::text, 25.99::numeric);
SELECT lengthb(rpad('我来自China'::text, 25.99::numeric, '#$'::text));
SELECT lengthb(rpad('我来自China'::text, 25.99::numeric));
SELECT length(rpad('我来自China'::text, 25.99::numeric, '#$'::text));
SELECT length(rpad('我来自China'::text, 25.99::numeric));


SELECT oracle.rpad('2019-12-12'::date, 20::int, '2019-12-13'::date);
SELECT oracle.rpad('2019-12-12'::date, 20.99::numeric, '2019-12-13'::date);
SELECT oracle.rpad('2019-12-12'::date, 20.99::numeric);
SELECT oracle.rpad('2019-12-12'::timestamp, 20::int, '2019-12-13'::timestamp);
SELECT oracle.rpad('2019-12-12'::timestamp, 20.99::numeric, '2019-12-13'::timestamp);
SELECT oracle.rpad('2019-12-12'::timestamp, 20.99::numeric);
SELECT oracle.rpad('2019-12-12'::date, 20.99::numeric, '2019-12-13'::timestamp);

SELECT oracle.rpad(null,null,null);
SELECT oracle.rpad(null,null);

SELECT rpad('ab'::text,-8::int,'*@'::text);
SELECT rpad('ab'::text,-1::int,'*@'::text);
SELECT oracle.rpad('ab'::text,-1.9::numeric,'*@'::text);
SELECT oracle.rpad('ab'::text,-0.9::numeric,'*@'::text);
SELECT oracle.rpad('ab'::text,0.9::numeric,'*@'::text);
SELECT rpad('ab'::text,0::int,'*@'::text);

SELECT oracle.rpad(null,2::int);
SELECT oracle.rpad(null,2.99::numeric);

SELECT rpad('ab'::text,-8::int);
SELECT rpad('ab'::text,-1::int);
SELECT oracle.rpad('ab'::text,-1.9::numeric);
SELECT oracle.rpad('ab'::text,-0.9::numeric);
SELECT oracle.rpad('ab'::text,0.9::numeric);
SELECT rpad('ab'::text,0::int);

SELECT oracle.rpad('',3::int,'');
SELECT oracle.rpad('',3.99::numeric,'');
SELECT oracle.rpad('',-3::int,'');
SELECT oracle.rpad('',0::int,'');
SELECT oracle.rpad('',3::int);
SELECT oracle.rpad('',3.99::numeric);
SELECT oracle.rpad('',-3::int);
SELECT oracle.rpad('',0::int);

SELECT oracle.rpad(' ',3::int,' ');
SELECT oracle.rpad(' ',3.99::numeric,' ');
SELECT oracle.rpad(' ',-3::int,' ');
SELECT oracle.rpad(' ',0::int,' ');
SELECT oracle.rpad(' ',3::int);
SELECT oracle.rpad(' ',3.99::numeric);
SELECT oracle.rpad(' ',-3::int);
SELECT oracle.rpad(' ',0::int);

reset search_path;