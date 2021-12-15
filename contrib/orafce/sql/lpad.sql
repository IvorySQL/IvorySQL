--Test For lpad
set search_path to oracle, pg_catalog;
set datestyle to ISO,YMD;
SELECT oracle.lpad(123, 20, 0);
SELECT oracle.lpad(123, 20);
SELECT oracle.lpad(123::int2, 20::int2, 0::int2);
SELECT oracle.lpad(123::int4, 20::int4, 0::int4);
SELECT oracle.lpad(123::int4, 20::int4);
SELECT oracle.lpad(123::int8, 20::int8, 0::int8);
SELECT oracle.lpad(123.99::numeric, 20.99::numeric, 0.9::numeric);
SELECT oracle.lpad(123.00::numeric, 20.99::numeric, 0.9::numeric);
SELECT oracle.lpad(123.00::numeric, 20::int, 0::int);
SELECT oracle.lpad(123.00::int, 20.99::numeric, 0.9::numeric);
SELECT oracle.lpad(123.99::numeric, 20.99::numeric);

SELECT oracle.lpad('123', '20'::int, '0');
SELECT oracle.lpad('123', '20.94'::numeric, '0');
SELECT oracle.lpad('123', '20'::int);
SELECT oracle.lpad('123', '20.95'::numeric);
SELECT oracle.lpad('I like'::char(10), 20::int, '#$'::char);
SELECT oracle.lpad('I like'::char(10), 20::int, '#$'::char(2));
SELECT oracle.lpad('I like'::char(10), 20::int);
SELECT oracle.lpad('$@'::char(2), 20::int, 'I like'::char(10));
SELECT oracle.lpad('$@'::char(2), 20.99::numeric);
SELECT oracle.lpad('I like'::varchar(20), 20::int, '#$'::varchar(20));
SELECT oracle.lpad('I like'::varchar2(20), 20::int, '#$'::varchar2(20));
SELECT oracle.lpad('I like'::nvarchar2(20), 20::int, '#$'::nvarchar2(20));
SELECT lpad('I like'::text, 20::int, '#$'::text);
SELECT oracle.lpad('I like'::text, 20.99::numeric, '#$'::text);
SELECT oracle.lpad('I like'::text, 20.99::numeric);
SELECT lpad('I Love China'::text, 25::int);
SELECT oracle.lpad('I Love China'::text, 25.99::numeric);
SELECT lpad('I Love China'::text, 7::int, '#$'::text);
SELECT oracle.lpad('I Love China'::text, 7.99::numeric, '#$'::text);
SELECT lpad('我来自China'::text, 25::int, '#$'::text);
SELECT oracle.lpad('我来自China'::text, 25.99::numeric, '#$'::text);
SELECT oracle.lpad('我来自China'::text, 25.99::numeric);
SELECT lengthb(oracle.lpad('我来自China'::text, 25.99::numeric, '#$'::text));
SELECT lengthb(oracle.lpad('我来自China'::text, 25.99::numeric));
SELECT length(oracle.lpad('我来自China'::text, 25.99::numeric, '#$'::text));
SELECT length(oracle.lpad('我来自China'::text, 25.99::numeric));

SELECT oracle.lpad('2019-12-12'::date, 20::int, '2019-12-13'::date);
SELECT oracle.lpad('2019-12-12'::date, 20.99::numeric, '2019-12-13'::date);
SELECT oracle.lpad('2019-12-12'::date, 20.99::numeric);
SELECT oracle.lpad('2019-12-12'::timestamp, 20::int, '2019-12-13'::timestamp);
SELECT oracle.lpad('2019-12-12'::timestamp, 20.99::numeric, '2019-12-13'::timestamp);
SELECT oracle.lpad('2019-12-12'::timestamp, 20.99::numeric);
SELECT oracle.lpad('2019-12-12'::date, 20::int, '2019-12-13'::timestamp);

SELECT oracle.lpad(null,null,null);
SELECT oracle.lpad(null,null);

SELECT lpad('ab'::text,-8::int,'*@'::text);
SELECT lpad('ab'::text,-1::int,'*@'::text);
SELECT oracle.lpad('ab'::text,-1.9::numeric,'*@'::text);
SELECT oracle.lpad('ab'::text,-0.9::numeric,'*@'::text);
SELECT oracle.lpad('ab'::text,0.9::numeric,'*@'::text);
SELECT lpad('ab'::text,0::int,'*@'::text);

SELECT lpad(null,2::int);
SELECT oracle.lpad(null,2.99::numeric);

SELECT lpad('ab'::text,-8::int);
SELECT lpad('ab'::text,-1::int);
SELECT oracle.lpad('ab'::text,-1.9::numeric);
SELECT oracle.lpad('ab'::text,-0.9::numeric);
SELECT oracle.lpad('ab'::text,0.9::numeric);
SELECT lpad('ab'::text,0::int);

SELECT oracle.lpad('',3::int,'');
SELECT oracle.lpad('',3.99::numeric,'');
SELECT oracle.lpad('',-3::int,'');
SELECT oracle.lpad('',0::int,'');
SELECT oracle.lpad('',3::int);
SELECT oracle.lpad('',3.99::numeric);
SELECT oracle.lpad('',-3::int);
SELECT oracle.lpad('',0::int);

SELECT oracle.lpad(' ',3::int,' ');
SELECT oracle.lpad(' ',3.99::numeric,' ');
SELECT oracle.lpad(' ',-3::int,' ');
SELECT oracle.lpad(' ',0::int,' ');
SELECT oracle.lpad(' ',3::int);
SELECT oracle.lpad(' ',3.99::numeric);
SELECT oracle.lpad(' ',-3::int);
SELECT oracle.lpad(' ',0::int);

reset search_path;