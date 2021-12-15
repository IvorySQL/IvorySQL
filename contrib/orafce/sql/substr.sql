--Test For substr
set search_path to oracle, pg_catalog;
set datestyle to ISO,YMD;
SELECT substr(21212, 2, 2) "substr";
SELECT substr(21212, 2) "substr";
SELECT substr(21212::int2, 2::int2, 2::int2) "substr";
SELECT substr(21221212::int4, 21::int4, 2::int4) "substr";
SELECT substr(21221212::int4, 21::int4) "substr";
SELECT substr(21221212::int8, 21::int8, 2::int8) "substr";
SELECT substr(20191212::int8, 2.99::numeric, 2.99::numeric) "substr";
SELECT substr(20191212::int8, 2::int, 2::int) "substr";
SELECT substr(201.91212::numeric, 3::int, 4::int) "substr";
SELECT substr(201.91212::numeric, 3.9::numeric, 4.99::numeric) "substr";
SELECT substr(201.91212::numeric, 3.9::numeric) "substr";

SELECT substr('201912', '2', '2') "substr";
SELECT substr('201912', '2') "substr";
SELECT substr('abCdeFgh'::char(10), 1::int, 3::int) "substr";
SELECT substr('abCdeFgh'::char(10), 1::int, 8::int) "substr";
SELECT substr('abCdeFgh'::char(10), 1::int, 10::int) "substr";
SELECT substr('abCdeFgh'::char(10), 2.99::numeric) "substr";
SELECT substr('今天是周五'::varchar, 1::int, 5::int) "substr";
SELECT substr('今天是周五'::varchar2, 1::int, 5::int) "substr";
SELECT substr('今天是周五'::varchar2, 1.9::numeric, 5.99::numeric) "substr";
SELECT substr('今天是周五'::varchar2, 2.9::numeric) "substr";
SELECT substr('今天是周五'::nvarchar2, 1::int, 5::int) "substr";
SELECT substr('abCdeFgh'::text, 2::int, 5::int) "substr";
SELECT substr('今天是周五'::text, 1::int, 5::int) "substr";
SELECT substr('今天是个好日子'::varchar(20),3::int,5::int) "substr";
SELECT substr('今天是个好日子'::text,-4::int,2::int) "substr";
SELECT substr('今天是个好日子'::char(10),5::int) "substr";
SELECT substr('今天是个好日子'::char(10),5.9::numeric) "substr";
SELECT substr('今天是个好日子'::varchar(10),-2::int) "substr";
SELECT substr('今天是个好日子'::varchar(10),-2.99::numeric) "substr";
SELECT substr('今天是个好日子'::varchar2(10),3::int,5::int) "substr";
SELECT substr('今天是个好日子'::nvarchar2(10),-4::int,2::int) "substr";
SELECT substr('今天是个好日子'::text,-6::int,2::int) "substr";
SELECT substr('今天是个好日子'::text,-7::int,2::int) "substr";
SELECT substr('今天是个好日子',-8::int,2::int) "substr";
SELECT substr('今天是个好日子'::nvarchar2(10),-4::int) "substr";
SELECT substr('今天是个好日子'::text,-6::int) "substr";
SELECT substr('今天是个好日子'::text,-7::int) "substr";
SELECT substr('今天是个好日子',-8::int) "substr";

SELECT substr('2019-12-12'::date, 2::int, 2::int) "substr";
SELECT substr('2019-12-12'::date, 2.9::numeric, 2.99::numeric) "substr";
SELECT substr('2019-12-12'::date, 2.9::numeric) "substr";
SELECT substr('2019-12-12'::timestamp, 2::int, 2::int) "substr";
SELECT substr('2019-12-12'::timestamp, 2.9::numeric, 2.99::numeric) "substr";
SELECT substr('2019-12-12'::timestamp, 2.9::numeric) "substr";

SELECT substr(null,null,null);
SELECT substr(null,null);

SELECT substr('',0::int,0::int);
SELECT substr('',-2::int,0::int);
SELECT substr('',-2::int,0.99::numeric);

SELECT substr('An apple',-20::int,30::int);
SELECT substr('An apple',-8::int,30::int);
SELECT substr('An apple',-7::int,30::int);
SELECT substr('An apple',-9::int,30::int);

SELECT substr('An apple',0::int,30::int);
SELECT substr('An apple',0.99::numeric,30::int);
SELECT substr('An apple',1.99::numeric,30::int);

SELECT substr('An apple',0::int,3.99::numeric);
SELECT substr('An apple',0.99::numeric,3.99::numeric);
SELECT substr('An apple',1.99::numeric,3.99::numeric);

SELECT substr('',0::int);
SELECT substr('',-2::int);
SELECT substr('',-1.99::numeric);

SELECT substr(' ',0::int);
SELECT substr(' ',-2::int);
SELECT substr(' ',-1.99::numeric);

reset search_path;
