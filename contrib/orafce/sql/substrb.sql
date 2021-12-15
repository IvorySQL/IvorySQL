--Test For substrb
set search_path to oracle, pg_catalog;
set datestyle to ISO,YMD;
SELECT substrb(21212, 2, 2) "substrb";
SELECT substrb(21212, 2) "substrb";
SELECT substrb(21212::int2, 2::int2, 2::int2) "substrb";
SELECT substrb(21221212::int4, 21::int4, 2::int4) "substrb";
SELECT substrb(21221212::int4, 21::int4) "substrb";
SELECT substrb(21221212::int8, 21::int8, 2::int8) "substrb";
SELECT substrb(20191212::int, 2.99::numeric, 2.99::numeric) "substrb";
SELECT substrb(20191212::int, 2::int, 2::int) "substrb";
SELECT substrb(201.91212::numeric, 3::int, 4::int) "substrb";
SELECT substrb(201.91212::numeric, 3.9::numeric, 4.99::numeric) "substrb";
SELECT substrb(201.91212::numeric, 3.9::numeric) "substrb";

SELECT substrb('201912', '2', '4') "substrb";
SELECT substrb('201912', '2') "substrb";
SELECT substrb('abCdeFgh'::char(10), 1::int, 3::int) "substrb";
SELECT substrb('abCdeFgh'::char(10), 1::int, 8::int) "substrb";
SELECT substrb('abCdeFgh'::char(10), 1::int, 10::int) "substrb";
SELECT substrb('abCdeFgh'::char(10), 2.99::numeric) "substrb";
SELECT substrb('今天是个好日子'::varchar(30),7::int, 1::int) "substrb";
SELECT substrb('今天是个好日子'::varchar(30),7::int, 4::int) "substrb";
SELECT substrb('今天是个好日子'::varchar(30),7::int, 6::int) "substrb";
SELECT substrb('今天是个好日子'::varchar(30),7::int, -1::int) "substrb";
SELECT substrb('今天是个好日子'::varchar(30),7.9::numeric, 6.99::numeric) "substrb";
SELECT substrb('今天是周五'::varchar2(20), 1::int, 5::int) "substrb";
SELECT substrb('I like shopping'::nvarchar2(20),7::int, 4::int) "substrb";
SELECT substrb('今天是个好日子'::text,0::int, 6::int) "substrb";
SELECT substrb('今天是个好日子'::text,0::int, 8.99::numeric) "substrb";
SELECT substrb('今天是个好日子'::text,0::int, 8::int) "substrb";
SELECT substrb('今天是个好日子'::text,0::int, 9::int) "substrb";
SELECT substrb('今天是个好日子'::text,0::int) "substrb";
SELECT substrb('今天是个好日子'::text,-15::int,9::int) "substrb";
SELECT substrb('今天是个好日子'::text,-15::int,11::int) "substrb";
SELECT substrb('今天是个好日子'::text,-15::int,11.99::numeric) "substrb";
SELECT substrb('今天是个好日子'::text,-15::int,12::int) "substrb";
SELECT substrb('今天是个好日子'::text,-15::int) "substrb";
SELECT substrb('abCdeFgh'::text, 2::int, 5::int) "substrb";
SELECT substrb('今天是周五'::text, 1::int, 5::int) "substrb";
SELECT substrb('今天是个好日子'::text,5::int) "substrb";
SELECT substrb('今天是个好日子'::text,7::int) "substrb";
SELECT substrb('今天是个好日子'::text,7.9::numeric) "substrb";
SELECT substrb('abcDefGh'::text,5::int) "substrb";
SELECT substrb('abcDefGh'::text,7::int) "substrb";

SELECT substrb('2019-12-12'::date, 2::int, 2::int) "substrb";
SELECT substrb('2019-12-12'::date, 2.9::numeric, 2.99::numeric) "substrb";
SELECT substrb('2019-12-12'::date, 2.9::numeric) "substrb";
SELECT substrb('2019-12-12'::timestamp, 2::int, 2::int) "substrb";
SELECT substrb('2019-12-12'::timestamp, 2.9::numeric, 2.99::numeric) "substrb";
SELECT substrb('2019-12-12'::timestamp, 2.9::numeric) "substrb";

SELECT substrb(null,null,null);
SELECT substrb(null,null);

SELECT substrb('',0::int,0::int);
SELECT substrb('',-2::int,0::int);
SELECT substrb('',-2::int,0.99::numeric);

SELECT substrb('An apple',-20::int,30::int);
SELECT substrb('An apple',-8::int,30::int);
SELECT substrb('An apple',-7::int,30::int);
SELECT substrb('An apple',-9::int,30::int);

SELECT substrb('An apple',0::int,30::int);
SELECT substrb('An apple',0.99::numeric,30::int);
SELECT substrb('An apple',1.99::numeric,30::int);

SELECT substrb('An apple',0::int,3.99::numeric);
SELECT substrb('An apple',0.99::numeric,3.99::numeric);
SELECT substrb('An apple',1.99::numeric,3.99::numeric);

SELECT substrb('',0::int);
SELECT substrb('',-2::int);
SELECT substrb('',-1.99::numeric);

SELECT substrb(' ',0::int);
SELECT substrb(' ',-2::int);
SELECT substrb(' ',-1.99::numeric);

reset search_path;
