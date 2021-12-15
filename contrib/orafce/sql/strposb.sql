--Test For strposb
set search_path to oracle, pg_catalog;
set datestyle to ISO,YMD;
SELECT strposb(123456, 345) "pos in str";
SELECT strposb(12345::int2, 345::int2) "pos in str";
SELECT strposb(123456::int, 345::int) "pos in str";
SELECT strposb(12345678::int8, 3456::int8) "pos in str";
SELECT strposb(12345678.910, 678.91) "pos in str";
SELECT strposb(12345678.910::numeric, 678.91::numeric) "pos in str";

SELECT strposb('123456789', '78') "pos in str";
SELECT strposb('CANDIDE, strposb', 'strposb') "pos in str";
SELECT strposb('CANDIDE, strposb'::char(100), 'strposb'::char(100)) "pos in str";
SELECT strposb('CANDIDE, strposb'::varchar(100), 'strposb'::varchar(100)) "pos in str";
SELECT strposb('CANDIDE, strposb'::varchar2(100), 'strposb'::varchar2(100)) "pos in str";
SELECT strposb(123456::varchar2, 345::varchar2) "pos in str";
SELECT strposb('CANDIDE, strposb'::nvarchar2(100), 'strposb'::nvarchar2) "pos in str";
SELECT strposb('CANDIDE, strposb'::text, 'strposb'::text) "pos in str";

SELECT strposb('2019-12-12'::date, '2019-12-12'::date) "pos in str";
SELECT strposb('2019-12-12'::timestamp, '2019-12-12'::timestamp) "pos in str";

SELECT strposb(null,null);
SELECT strposb('','');
SELECT strposb(' ',' ');
SELECT strposb(0::int,0::int);
SELECT strposb(-2::int,-2::int);
SELECT strposb(0.99::numeric,0.99::numeric);
SELECT strposb(-2.99::numeric,-2.89::numeric);

reset search_path;
