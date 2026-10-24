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

-- Oracle LIKE does not have a default escape character (including for CLOB).
create table t_ora_like_escape (id int, str clob);
insert into t_ora_like_escape values
    (1, ' ab%m'), (2, '123m_ab'), (3, 'ert#qw'), (4, 'fa\fsd'), (5, 'x''y');
select 1 as step, array_agg(id order by id) as matched from t_ora_like_escape where str like '%%%'
union all
select 2, array_agg(id order by id) from t_ora_like_escape where str like '%_%'
union all
select 3, array_agg(id order by id) from t_ora_like_escape where str like '%\%'
union all
select 4, array_agg(id order by id) from t_ora_like_escape where str like '%#%'
union all
select 5, array_agg(id order by id) from t_ora_like_escape where str like '%''%'
union all
select 6, array_agg(id order by id) from t_ora_like_escape where str like '%\%%'
union all
select 7, array_agg(id order by id) from t_ora_like_escape where str like '%\_%'
union all
select 8, array_agg(id order by id) from t_ora_like_escape where str like '%\\%'
union all
select 9, array_agg(id order by id) from t_ora_like_escape where str like '%\#%'
union all
select 10, array_agg(id order by id) from t_ora_like_escape where str like '%\''%'
union all
select 11, array_agg(id order by id) from t_ora_like_escape where str like '%\%%' escape '\'
union all
select 12, array_agg(id order by id) from t_ora_like_escape where str like '%\_%' escape '\'
union all
select 13, array_agg(id order by id) from t_ora_like_escape where str like '%\\%' escape '\'
union all
select 14, array_agg(id order by id) from t_ora_like_escape where str like '%+%%' escape '+'
order by step;
-- Invalid escapes are checked even when no row could match the pattern.
select * from t_ora_like_escape where str like '%\#%' escape '\';
select * from t_ora_like_escape where str like '%\''%' escape '\';
select * from t_ora_like_escape where str like '%++%%' escape '++';
select 'abc' like 'xyz\' escape '\';
select 'abc' not like '%+x%' escape '+';

-- Other string types, NOT LIKE, and literal backslashes at the pattern end.
select 'fa\fsd'::varchar2 like '%\%' as varchar2_like,
       'fa\fsd'::varchar2 not like '%\%' as varchar2_not_like,
       'ab%m'::varchar2 like '%\%%' escape '\' as escaped_like,
       'fa\fsd'::char(6) like '%\%' as char_like,
       'fa\fsd'::nclob like '%\%' as nclob_like,
       'abc\' like 'abc\' as trailing_backslash;
select 'ab%m' not like '%\%%' escape '\' as escaped_not_like,
       (null like '%\%') is null as null_value,
       ('abc' like null) is null as null_pattern,
       ('abc' like '%' escape null) is null as null_escape,
       ('abc' like '%' escape '') is null as empty_escape;

-- Escape length and scanning must be measured in characters, not bytes.
select 'a%b' like '%汉%%' escape '汉' as escaped_percent,
       'a_b' like '%汉_%' escape '汉' as escaped_underscore,
       'a汉b' like '%汉汉%' escape '汉' as escaped_escape,
       'a\b' like '%\%' escape '+' as literal_backslash;
select 'abc' like '%汉x%' escape '汉';
select 'abc' like '%' escape '汉字';

-- A stored pattern is normalized at execution time.
select value like pattern as matched
from (values ('fa\fsd'::text, '%\%'::text),
             ('abc'::text, '%\%'::text)) as v(value, pattern);
prepare ora_like_escape_plan(text, text, text) as
    select $1 like $2 as matched, $1 like $2 escape $3 as explicit_escape;
-- Bypass Oracle psql's EXECUTE-to-PL/iSQL command rewriting.
select $$execute ora_like_escape_plan('fa\fsd', '%\%', '+');$$ \gexec

set ivorysql.compatible_mode to pg;
-- Prepared Oracle expressions retain their semantics after a mode switch.
select $$execute ora_like_escape_plan('fa\fsd', '%\%', '+');$$ \gexec
deallocate ora_like_escape_plan;
-- PostgreSQL keeps its default backslash escape and permissive escaping.
select 'fa\fsd' like '%\%' as default_escape,
       'fa\fsd' like '%\\%' as escaped_backslash,
       'ert#qw' like '%\#%' escape '\' as escaped_hash,
       'x''y' like '%\''%' escape '\' as escaped_quote,
       'fa\fsd' like '%\%' escape '' as no_escape;
prepare pg_like_escape_plan(text, text) as select $1 like $2 as matched;
set ivorysql.compatible_mode to oracle;
select $$execute pg_like_escape_plan('fa\fsd', '%\%');$$ \gexec
deallocate pg_like_escape_plan;
drop table t_ora_like_escape;
set ivorysql.compatible_mode to pg;
