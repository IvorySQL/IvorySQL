set datestyle to ISO,YMD;
set search_path to oracle, pg_catalog;
SELECT lengthb(192);
SELECT lengthb(192::int2);
SELECT lengthb(192::int4);
SELECT lengthb(192::int8);
SELECT lengthb(192.922);
SELECT lengthb(192.922::numeric);

SELECT lengthb('192');
SELECT lengthb('Highgo DB!');
SELECT lengthb('今天');
SELECT lengthb('Highgo DB!'::char(10));
SELECT lengthb('Highgo DB!'::char(20));
SELECT lengthb('Highgo DB!'::varchar(20));
SELECT lengthb('Highgo DB!'::varchar2(20));
SELECT lengthb('Highgo DB!'::nvarchar2(20));
SELECT lengthb('Highgo DB!'::text);
SELECT lengthb('今天'::text);
SELECT lengthb('今天是Monday'::char(20));

SELECT lengthb('2019-12-12'::date);
SELECT lengthb('2019-12-12'::timestamp);
SELECT lengthb(null);
SELECT lengthb('');
SELECT lengthb(' ');
SELECT lengthb(0::int);
SELECT lengthb(-2::int);

reset search_path;