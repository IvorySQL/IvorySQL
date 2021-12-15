--Test For rtrim
set search_path to oracle, pg_catalog;
set datestyle to ISO,YMD;
SELECT rtrim(1231232112, 21) "RTRIM Example";
SELECT rtrim(1231232112) "RTRIM Example";
SELECT rtrim(12312::int2, 21::int2) "RTRIM Example";
SELECT rtrim(1232112::int4, 21::int4) "RTRIM Example";
SELECT rtrim(1232112::int4) "RTRIM Example";
SELECT rtrim(1231232112::int8, 21::int8) "RTRIM Example";
SELECT rtrim(1231232.112, 2.1) "RTRIM Example";
SELECT rtrim(1231232.112::numeric, 2.1::numeric) "RTRIM Example";
SELECT rtrim(1231232.112::numeric) "RTRIM Example";

SELECT rtrim('1231232112', '21') "RTRIM Example";
SELECT rtrim('<=====>BROWNING<=====>', '<>=') "RTRIM Example";
SELECT rtrim(' I like coffee !     ') "RTRIM Example";
SELECT rtrim(' I like coffee !     '::char(5)) "RTRIM Example";
SELECT rtrim(' I like coffee !     '::char(100)) "RTRIM Example";
SELECT rtrim(' I like coffee !'::char(100)) "RTRIM Example";
SELECT rtrim(' I like coffee !     '::text) "RTRIM Example";
SELECT rtrim('<=====>BROWNING<=====>'::char(25), '<>='::char(3)) "RTRIM Example";
SELECT rtrim('<=====>BROWNING<=====>'::varchar(25), '<>='::varchar(5)) "RTRIM Example";
SELECT rtrim('<=====>BROWNING<=====>'::varchar2(25), '<>='::varchar2(5)) "RTRIM Example";
SELECT rtrim('<=====>BROWNING<=====>'::nvarchar2(25), '<>='::nvarchar2(5)) "RTRIM Example";
SELECT rtrim('<=====>BROWNING<=====>'::text, '<>='::text) "RTRIM Example";
SELECT rtrim('我的家我的梦'::varchar2(25), '我的梦'::varchar2(9)) "RTRIM Example";

SELECT rtrim('2019-12-12'::date, '2019-12-12'::date) "RTRIM Example";
SELECT rtrim('2019-12-12'::timestamp, '2019-12-12'::timestamp) "RTRIM Example";
SELECT rtrim('2019-12-12'::date) "RTRIM Example";

SELECT rtrim(null,'nu'::text);
SELECT rtrim('nu'::text,null);
SELECT rtrim(null,null);
SELECT rtrim('','');
SELECT rtrim('',' ');
SELECT rtrim(' ','');
SELECT rtrim(' ',' ');
SELECT rtrim(null);
SELECT rtrim('');
SELECT rtrim(' ');
SELECT rtrim(0::int,0.99::numeric);
SELECT rtrim(-1::int,-1::int);
SELECT rtrim(0::int);
SELECT rtrim(-5::int);
SELECT rtrim(0.99::numeric);
SELECT rtrim(-5.99::numeric);

reset search_path;