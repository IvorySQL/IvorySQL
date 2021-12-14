set datestyle to ISO,YMD;
set search_path to oracle, pg_catalog;
SELECT btrim(121232112, 21) "BTRIM Example";
SELECT btrim(121232112) "BTRIM Example";
SELECT btrim(12312::int2, 21::int2) "BTRIM Example";
SELECT btrim(1223112::int4, 21::int4) "BTRIM Example";
SELECT btrim(1223112::int4) "BTRIM Example";
SELECT btrim(121232112::int8, 21::int8) "BTRIM Example";
SELECT btrim(2.13232112, 2.1) "BTRIM Example";
SELECT btrim(2.13232112::numeric, 2.1::numeric) "BTRIM Example";
SELECT btrim(2.13232112::numeric) "BTRIM Example";

SELECT btrim('121232112', '21') "BTRIM Example";
SELECT btrim('<=====>BROWNING<=====>', '<>=') "BTRIM Example";
SELECT btrim('  abddfsdga  ') "BTRIM Example";
SELECT btrim('  abddfsdga  '::char(5)) "BTRIM Example";
SELECT btrim('  abddfsdga  '::char(100)) "BTRIM Example";
SELECT btrim('  abddfsdga  '::varchar2(25)) "BTRIM Example";
SELECT btrim('<=====>BROWNING<=====>'::char(25), '<>='::char(3)) "BTRIM Example";
SELECT btrim('<=====>BROWNING<=====>'::varchar(25), '<>='::varchar(5)) "BTRIM Example";
SELECT btrim('<=====>BROWNING<=====>'::varchar2(25), '<>='::varchar2(5)) "BTRIM Example";
SELECT btrim('<=====>BROWNING<=====>'::nvarchar2(25), '<>='::nvarchar2(5)) "BTRIM Example";
SELECT btrim('<=====>BROWNING<=====>'::text, '<>='::text) "BTRIM Example";
SELECT btrim('我的家我的梦我的'::varchar2(25), '我的家'::varchar2(9)) "BTRIM Example";

SELECT btrim('2019-12-12'::date, '2019-12-12'::date) "BTRIM Example";
SELECT btrim('2019-12-12'::timestamp, '2019-12-12'::timestamp) "BTRIM Example";
SELECT btrim('2019-12-12'::timestamp) "BTRIM Example";

SELECT btrim(null,'nu'::text);
SELECT btrim('nu'::text,null);
SELECT btrim(null,null);
SELECT btrim('','');
SELECT btrim('',' ');
SELECT btrim(' ','');
SELECT btrim(' ',' ');
SELECT btrim(0::int,0.99::numeric);
SELECT btrim(-1::int,-1::int);

SELECT btrim(null);
SELECT btrim('');
SELECT btrim(' ');
SELECT btrim(0::int);
SELECT btrim(-5::int);
SELECT btrim(0.99::numeric);
SELECT btrim(-5.99::numeric);

reset search_path;
