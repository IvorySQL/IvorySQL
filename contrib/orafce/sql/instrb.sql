--Test For instrb
set search_path to oracle, pg_catalog;
set datestyle to ISO,YMD;
SELECT instrb(20121209,12::int, 1::text, 2, 4) "instrb";
SELECT instrb(20121209,12::int, 1::text, '2') "instrb";
SELECT instrb(20121209,12::int, 1::text, 2, '4', 5) "instrb";
SELECT instrb(20121209) "instrb";
SELECT instrb(20121209,12, 1, 2) "instrb";
SELECT instrb(20121209,12, 1) "instrb";
SELECT instrb(20121209,12) "instrb";
SELECT instrb(2012::int2,12::int2, 1::int2, 2::int2) "instrb";
SELECT instrb(2012::int2,12::int2, 1::int2) "instrb";
SELECT instrb(2012::int2,12::int2) "instrb";
SELECT instrb(20121209::int,12::int, 1.9::int, 2.99::int) "instrb";
SELECT instrb(20121209::int,12::int, 1.9::int) "instrb";
SELECT instrb(20121209::int,12::int) "instrb";
SELECT instrb(20121212::int8,1212::int8, 1.9::int8, 1.99::int8) "instrb";
SELECT instrb(20121212::int8,1212::int8, 1.9::int8) "instrb";
SELECT instrb(20121212::int8,1212::int8) "instrb";
SELECT instrb(201212.09::int,12.9::int, 1.9::numeric, 2.99::numeric) "instrb";
SELECT instrb(201212.12::numeric,12.12::numeric, 1.9::int, 1.99::int) "instrb";
SELECT instrb(201212.12::numeric,12.12::numeric, 1.9::numeric, 1.99::numeric) "instrb";
SELECT instrb(201212.12::numeric,12.12::numeric, 1.9::numeric) "instrb";
SELECT instrb(201212.12::numeric,12.12::numeric) "instrb";

SELECT instrb('CORPORATE FLOOR','OR',5,2) "instrb";
SELECT instrb('CORPORATE FLOOR','OR',5) "instrb";
SELECT instrb('CORPORATE FLOOR','OR') "instrb";
SELECT instrb('CORPORATE FLOOR'::char(20),'OR'::char(2),5::int,2::int) "instrb";
SELECT instrb('CORPORATE FLOOR'::char(20),'OR'::char(2),5::int) "instrb";
SELECT instrb('CORPORATE FLOOR'::char(20),'OR'::char(2)) "instrb";
SELECT instrb('CORPORATE FLOOR'::varchar,'OR'::varchar, -3::int, 2::int) "instrb";
SELECT instrb('CORPORATE FLOOR'::varchar,'OR'::varchar, -3::int) "instrb";
SELECT instrb('CORPORATE FLOOR'::varchar,'OR'::varchar) "instrb";
SELECT instrb('CORPORATE FLOOR'::varchar,'OTR'::varchar, -3::int, 2::int) "instrb";
SELECT instrb('CORPORATE FLOOR'::varchar2(20),'OR'::varchar2(5), 3::int, -2::int) "Instring";
SELECT instrb('CORPORATE FLOOR'::varchar2(20),'OR'::varchar2(5), -3::int, 2::int) "instrb";
SELECT instrb('CORPORATE FLOOR'::varchar2(20),'OR'::varchar2(5), -3.9::numeric, 2.9::numeric) "instrb";
SELECT instrb('CORPORATE FLOOR'::varchar2(20),'OR'::varchar2(5), -3::int, 2.9::numeric) "instrb";
SELECT instrb('CORPORATE FLOOR'::varchar2(20),'OR'::varchar2(5), -3.9::numeric, 2::int) "instrb";
SELECT instrb('CORPORATE FLOOR'::nvarchar2,'OR'::nvarchar2, 3::int, 2::int) "instrb";
SELECT instrb('CORPORATE FLOOR'::text,'OR'::text, 3::int, 2::int) "instrb";
SELECT instrb('日日花前长病酒，花前月下举杯饮'::text,'花前'::varchar2(100),1::int,1::int) "instrb";
SELECT instrb('日日花前长病酒，花前月下举杯饮'::varchar(100),'花前'::nvarchar2(100),1::int,2::int) "instrb";
SELECT instrb(cast('CORPORATE FLOOR' as text), cast('OR' as text), 10::int, 2::int) "instrb";
SELECT instrb('今天是Aa周一1'::nvarchar2(20),'周一'::text, 1::int, 1.99::numeric) "instrb";
SELECT instrb('今天是Aa周一1'::nvarchar2(20),'周一'::text, 1.9::numeric, 1::int) "instrb";
SELECT instrb('今天是Aa周一1'::nvarchar2(20),'周一'::text, 1.9::numeric, 1.99::numeric) "instrb";
SELECT instrb('今天是Aa周一1'::nvarchar2(20),'周一'::text, 1.9::numeric) "instrb";
SELECT instrb('今天是Aa周一1'::nvarchar2(20),'周一'::text) "instrb";

SELECT instrb('2019-12-12'::date,'2019-12-12'::date, 1::int, 1::int) "instrb";
SELECT instrb('2019-12-12'::date,'2019-12-12'::date, 1.9::numeric, 1.99::numeric) "instrb";
SELECT instrb('2019-12-12'::date,'2019-12-12'::date, 1.99::numeric) "instrb";
SELECT instrb('2019-12-12'::date,'2019-12-12'::date) "instrb";
SELECT instrb('2019-12-12'::timestamp,'2019-12-12'::timestamp,1::int,1::int) "instrb";
SELECT instrb('2019-12-12'::timestamp,'2019-12-12'::timestamp,1.9::numeric,1.99::numeric) "instrb";
SELECT instrb('2019-12-12'::timestamp,'2019-12-12'::timestamp,1::int) "instrb";
SELECT instrb('2019-12-12'::timestamp,'2019-12-12'::timestamp) "instrb";

SELECT instrb(null,null,null,null);
SELECT instrb(null,null,null);
SELECT instrb(null,null);

SELECT instrb('','',-2::int,1::int);
SELECT instrb('','',-1::int,1::int);
SELECT instrb('','',0::int,1::int);
SELECT instrb('','',2::int,1::int);
SELECT instrb(' ',' ',0::int,1::int);
SELECT instrb(' ',' ',-1::int,1::int);
SELECT instrb('abcdCde'::varchar,'Cd'::text,0.99::numeric,1.99::numeric);
SELECT instrb('abcdCde'::text,'Cd'::text,-1.99::numeric,1::int);
SELECT instrb('abcdCde'::text,'Cd'::varchar2,-8.9::numeric,1::int);

SELECT instrb('','',0::int);
SELECT instrb('','',-1::int);
SELECT instrb('','',0.9::numeric);
SELECT instrb('','',-1.9::numeric);
SELECT instrb(' ',' ',0::int);
SELECT instrb(' ',' ',-1::int);

SELECT instrb('','');
SELECT instrb(' ',' ');

reset search_path;
