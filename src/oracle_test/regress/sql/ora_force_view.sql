create view v_bug193 as select * from t_bug193;
create force view v_bug193 as select * from t_bug193;
select pg_get_viewdef('v_bug193');
create force view v_bug193 as select * from t_bug193_1;
select pg_get_viewdef('v_bug193');		-- force view defination not change
create or replace force view v_bug193 as select * from t_bug193_1;
select pg_get_viewdef('v_bug193');		-- force view defination be changed

create table test_bug193(a int);
insert into test_bug193 values(123456);
create view bug193_ok as select * from test_bug193;
select * from bug193_ok;

create force view bug193_ok as select * from t_bug193_2;
select * from bug193_ok;	-- ok
select pg_get_viewdef('bug193_ok');

create or replace force view bug193_ok as select * from t_bug193_2;
select * from bug193_ok;	-- error, view has errors
select pg_get_viewdef('bug193_ok');

create view bug193_ok_1 as select * from test_bug193;
select * from bug193_ok_1;

create table test_bug193_1(a int);
insert into test_bug193_1 values(987654);
create force view bug193_ok_1 as select * from test_bug193_1;	-- error
select pg_get_viewdef('bug193_ok_1');

create or replace force view bug193_ok_1 as select * from test_bug193_1;
select * from bug193_ok_1;
select pg_get_viewdef('bug193_ok_1');

drop table test_bug193_1 cascade;
drop table test_bug193 cascade;
drop view v_bug193;
drop view bug193_ok;

-- compile view
create force view bug193_ok_3 as select * from test_bug193_fail;
create force view bug193_ok_4 as select * from bug193_ok_3;
select * from bug193_ok_3;
select * from bug193_ok_4;

alter view bug193_ok_4 compile;		--View altered with compilation errors

create table test_bug193_fail(a int);
insert into test_bug193_fail values(1314);
alter view bug193_ok_4 compile;

select * from bug193_ok_3;
select * from bug193_ok_4;

drop table test_bug193_fail cascade;

-- the view becomes invalid after the dependent object of the view is deleted.
create table test_193(a int);
insert into test_193 values(2023);
create view v1 as select * from test_193;
create view v2 as select * from v1;
select * from v1;
select * from v2;
drop table test_193;
select * from v1;
select * from v2;
create table test_193(a int);
insert into test_193 values(2024);
select * from v1;
select * from v2;
drop table test_193;
drop view v1;
drop view v2;

-- circular dependency
create force view v1 as select * from v2;
create force view v2 as select * from v1;
select * from v1;
select * from v2;
ALTER VIEW V1 COMPILE;
ALTER VIEW V2 COMPILE;
drop view v1;
drop view v2;

-- function depend view.
create table test_193(a int);
insert into test_193 values(2023);
create view v1 as select * from test_193;
select * from v1;
create or replace function ftest193(x int) return text as
 var v1%ROWTYPE;
begin
SELECT * INTO var FROM v1;
RETURN 'a = ' || var.a;
end;
/
select ftest193(1);
drop table test_193;
select * from v1;		-- err
select ftest193(1);		-- err
create table test_193(a int);
insert into test_193 values(2024);
select * from v1;
select ftest193(1);
drop table test_193;
drop view v1;
drop function ftest193;

create table user_info(id int, uname varchar2(64));
insert into user_info values(1, '111');
insert into user_info values(2, '222');
insert into user_info values(3, '333');
insert into user_info values(4, null);

-- success
select id, (case uname when null then null else uname end) as bm from user_info order by bm;
select id, (case uname when null then null else uname end) as bm from user_info order by length(bm);
select id, (case uname when null then null else uname end) as bm from user_info order by length(case uname when null then null else uname end);
select id, uname as id from user_info tbl order by tbl.id;

-- error
select id, uname as id from user_info order by id;
select id, (case uname when null then null else uname end) as id from user_info order by length(id);
select id, (case uname when null then null else uname end) as id from user_info order by id-100;

drop table user_info;


create table test193(a int, b int);
insert into test193 values(1, 123);
select * from test193;
create view vtest193 as select * from test193;
select * from vtest193;
alter table test193 alter column b type varchar2(128);
select * from vtest193;
insert into test193 values(1, 'abc');
select * from vtest193;
drop view vtest193;
drop table test193;
