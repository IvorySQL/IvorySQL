--
-- oracle like tests
--
set ivorysql.compatible_mode to oracle;

alter session set timezone = '+8';

select '123456'::char(6) like '123%' from dual;
select '123456'::varchar(6) like '123%' from dual;
select '123456'::varchar2 like '123%' from dual;
select '123456'::text like '123%' from dual;

select '123456'::text like '123%'::varchar2 from dual;
SELECT 123456::integer like '123%'::varchar2 from dual;

SELECT 123456::integer like '123%' from dual;
SELECT 123456::int like '123%' from dual;
SELECT 1234::int2 like '123%' from dual;
SELECT 123456::int4 like '123%' from dual;
SELECT 123456::int8 like '123%' from dual;
SELECT 123456::bigint like '123%' from dual;
SELECT 1234::smallint like '123%' from dual;

SELECT 123456::real like '123%' from dual;
SELECT 123456::number like '123%' from dual;
SELECT 123456::numeric like '123%' from dual;

SELECT 123456::dec like '123%' from dual;
SELECT 123456::decimal like '123%' from dual;

SELECT 1234.56::float like '123%' from dual;
SELECT 1234.56::float4 like '123%' from dual;
SELECT 1234.56::float8 like '123%' from dual;
SELECT 1234.56::double precision like '123%' from dual;

select '2022-09-26'::date like '2022%' from dual;
SELECT '2022-09-26 16:39:20'::timestamp like '2022%' from dual;
select '2022-09-26 16:39:20'::timestamptz  like '2022%' from dual;
select '2022-09-26 16:39:20'::timestamp with local time zone like '2022%' from dual;
select '2022-09-26 16:39:20'::time like '16%' from dual;
select '08:55:08 GMT+2'::timetz like '08%' from dual;

select '2022-09-26 16:39:20'::clob like '2022%' from dual;
select '2022-09-26 16:39:20'::nclob like '2022%' from dual;

select '123456'::char(6) like null from dual;
select 123456::integer like null from dual;
SELECT null like '123%' from dual;
SELECT null like '123%'::varchar2 from dual;

create table t_ora_like (id int ,str1 varchar(8), date1 timestamp with time zone, date2 time with time zone, num int, str2 varchar(8));
insert into t_ora_like (id ,str1 ,date1 ,date2) values (123456,'test1','2022-09-26 16:39:20','2022-09-26 16:39:20');
insert into t_ora_like (id ,str1 ,date1 ,date2) values (123457,'test2','2022-09-26 16:40:20','2022-09-26 16:40:20');
insert into t_ora_like (id ,str1 ,date1 ,date2) values (223456,'test3','2022-09-26 16:41:20','2022-09-26 16:41:20');
insert into t_ora_like (id ,str1 ,date1 ,date2) values (123458,'test4','2022-09-26 16:42:20','2022-09-26 16:42:20');
select * from t_ora_like where str1 like 'test%';
select * from t_ora_like where date1 like '2022%';
select * from t_ora_like where date2 like '16%';
select * from t_ora_like where id like '123%';
select * from t_ora_like where id like null;
select * from t_ora_like where num like '123%';
select * from t_ora_like where str2 like 'test%';
drop table t_ora_like;

set ivorysql.compatible_mode to pg;
