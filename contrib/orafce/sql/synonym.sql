/*
 * test synonym
 *
 */
create user usertest;
grant create on database contrib_regression to usertest;
set role to usertest;

set compatible_mode to oracle ;

create table test(id int, name text);
insert into test values (1,'zhangsan'),(2,'lisi');
insert into test values (5,'qianwu');
insert into test values (6,'sunliu');
insert into test values (7,'zhouqi');
create synonym syntest for test;
create public synonym syntest for test1;
select * from syntest;
insert into syntest values (8,'wuba');
select * from syntest;
alter table syntest add column age int;
select * from syntest;
create synonym syntest1 for syntest;
create synonym syntest2 for syntest1;
create synonym syntest3 for syntest2;
select * from syntest3;
select * from syntest2;
select * from syntest1;
drop table test;
select * from syntest;

create table mytest(id int, name text);
insert into mytest values (1,'zhangsan'),(2,'lisi');
insert into mytest values (5,'qianwu');
create view mytestview as select * from mytest where id < 4;
create public synonym synviewtest for mytestview;
create synonym synviewtest for mytestview;
select * from synviewtest;
drop view mytestview;
select * from synviewtest;

create sequence serial start 100;
select nextval('serial');
select nextval('serial');
create public synonym synseq for serial;
select * from serial;
select * from synseq;
drop sequence serial;
select * from synseq;

select * from user_synonyms;
select * from all_synonyms;

create schema syntestuser;
set search_path to "$user", public, syntestuser;

create function testfunc1(id int)
returns int
as $$
begin
		return 11;
end;
$$ language plpgsql;

create function syntestuser.testfunc1(id int)
returns int
as $$
begin
		return 12;
end;
$$ language plpgsql;

create function testfunc1(id int, age int)
returns int
as $$
begin
		return 22;
end;
$$ language plpgsql;

create synonym syntestuser.synfunc for syntestuser.testfunc1;
create public synonym syntestuser.synfunc1 for syntestuser.testfunc1;
create public synonym synfunc1 for syntestuser.testfunc1;
create public synonym synfunc2 for testfunc1;
create synonym syntestuser.synfunc3 for testfunc1;
create synonym synfunc4 for testfunc1;
select synfunc(1);
select synfunc1(1);
select synfunc2(1);
select synfunc3(3);
select synfunc4(4);
drop function testfunc1(int);
select synfunc(1);
select synfunc1(1);
select synfunc2(1);
select synfunc3(3);
select synfunc4(4);
select synfunc(1,2);
select synfunc1(1,2);
select synfunc2(1,2);
select synfunc3(3,2);
select synfunc4(4,2);

drop package pkg;

create or replace package pkg is
  x int;
  y varchar := 'test';
  
  function tfunc(x int) return int;
end;
/

create or replace package body pkg is
  
  function tfunc(x int) return int as
  begin
	return x;
  end;
end;
/

create synonym pkg_syn for pkg;
create synonym syntestuser.pkg_syn1 for pkg;

-- without schema qualification
select pkg.tfunc(10);
select pkg_syn.tfunc(11);
select pkg_syn1.tfunc(12);

-- with schema qualification
select public.pkg.tfunc(1001);
select public.pkg_syn.tfunc(1002);
select public.pkg_syn1.tfunc(1003);

-- with database.schema qualification
select contrib_regression.public.pkg.tfunc(101);
select contrib_regression.public.pkg_syn.tfunc(102);
select contrib_regression.public.pkg_syn1.tfunc(103);

drop package pkg;
select pkg_syn.tfunc(10);
select pkg_syn1.tfunc(10);

create or replace synonym my617 for test;
create or replace synonym my617 for test;
create synonym my617 for test;
create or replace public synonym my617 for test;
create or replace public synonym my617 for test;
create public synonym my617 for test;

create materialized view materview1 as select * from mytest where id > 1;
create materialized view materview2 as select * from mytest where id > 0;
select * from materview1;
select * from materview2;
create synonym synmaterview1 for materview1;
create public synonym synmaterview1 for materview2;
select * from synmaterview1;
drop materialized view materview1;
select * from synmaterview1;
drop materialized view materview2;
select * from synmaterview1;

create type bb as (id int, name text);
create synonym mybb for bb;
create synonym mybb1 for mybb;
create synonym mybb2 for mybb1;
create synonym mybb3 for mybb2;

create table testbb (id mybb);
create table testbb1 (id mybb1);
create table testbb2 (id mybb2);
create table testbb3 (id mybb3);

insert into testbb values ((1, 'zhangsan'));
insert into testbb1 values ((1, 'zhangsan'));
insert into testbb2 values ((1, 'zhangsan')), ((2, 'lisi'));
insert into testbb3 values ((1, 'zhangsan')), ((2, 'lisi'));

select * from testbb;
select * from testbb1;
select * from testbb2;
select * from testbb3;

create synonym syntestbb for testbb;
create synonym syntestbb1 for testbb1;
create synonym syntestbb2 for testbb2;
create synonym syntestbb3 for testbb3;

--create synonym syntestbbn for syntestbb;

select * from syntestbb;
select * from syntestbb1;
select * from syntestbb2;
select * from syntestbb3;

--select * from syntestbbn;

create public synonym pubsyntestbb for testbb;
create public synonym pubsyntestbb1 for testbb1;
create public synonym pubsyntestbb2 for testbb2;
create public synonym pubsyntestbb3 for testbb3;

select * from pubsyntestbb;
select * from pubsyntestbb1;
select * from pubsyntestbb2;
select * from pubsyntestbb3;

create view viwtestbb as select * from testbb;
create view viwtestbb1 as select * from testbb1;
create view viwtestbb2 as select * from testbb2;
create view viwtestbb3 as select * from testbb3;

create synonym synviwtestbb for viwtestbb;
create synonym synviwtestbb1 for viwtestbb1;
create synonym synviwtestbb2 for viwtestbb2;
create synonym synviwtestbb3 for viwtestbb3;

select * from synviwtestbb;
select * from synviwtestbb1;
select * from synviwtestbb2;
select * from synviwtestbb3;

create materialized view matviwtestbb as select * from testbb;
create materialized view matviwtestbb1 as select * from testbb1;
create materialized view matviwtestbb2 as select * from testbb2;
create materialized view matviwtestbb3 as select * from testbb3;

create synonym matsynviwtestbb for matviwtestbb;
create synonym matsynviwtestbb1 for matviwtestbb1;
create synonym matsynviwtestbb2 for matviwtestbb2;
create synonym matsynviwtestbb3 for matviwtestbb3;

select * from matsynviwtestbb;
select * from matsynviwtestbb1;
select * from matsynviwtestbb2;
select * from matsynviwtestbb3;

create sequence serial start 101;
create synonym synserial for serial;

select nextval('serial');
select nextval('synserial');

create function func1(ID mybb) returns mybb
as $$
declare
	idd mybb;
begin
	idd := id;
	return idd;
end ;
$$ language plpgsql;

select func1((1, 'zhangsan'));

select * from all_synonyms;
set role to default;
select * from dba_synonyms;
set role to usertest;
select * from user_synonyms;

create synonym synfunc1 for func1;
select synfunc1((1, 'zhangsan'));

do $$declare
	idd mybb;
begin
	idd := (1, 'zhangsan');
	raise notice '%', idd;
end ;
$$ language plpgsql;

drop function func1;

create domain aa as int;
create synonym myaa for aa;
create table testaa(id myaa);

select (1, 'zhangsan')::mybb;
select (2, 'zhangsanfeng')::mybb;

drop synonym myaa;
drop synonym mybb;
drop synonym mybb1;
drop synonym mybb2;
drop synonym mybb3;

drop synonym syntestbb;
drop synonym syntestbb1;
drop synonym syntestbb2;
drop synonym syntestbb3;

drop public synonym pubsyntestbb;
drop public synonym pubsyntestbb1;
drop public synonym pubsyntestbb2;
drop public synonym pubsyntestbb3;

drop view viwtestbb;
drop view viwtestbb1;
drop view viwtestbb2;
drop view viwtestbb3;

drop synonym synviwtestbb;
drop synonym synviwtestbb1;
drop synonym synviwtestbb2;
drop synonym synviwtestbb3;

drop materialized view matviwtestbb;
drop materialized view matviwtestbb1;
drop materialized view matviwtestbb2;
drop materialized view matviwtestbb3;

drop synonym matsynviwtestbb;
drop synonym matsynviwtestbb1;
drop synonym matsynviwtestbb2;
drop synonym matsynviwtestbb3;

--drop synonym syntestbbn;

drop table testbb;
drop table testbb1;
drop table testbb2;
drop table testbb3;

drop sequence serial;
drop synonym synserial;

drop synonym synfunc1;

drop type aa;
drop type bb;

set role to default;
create user usr1;
create user usr2;

set role usr1;
create table test(id int);

set role usr2;
create synonym syntesttb for test;

select * from syntesttb;
set role to default ;
grant select on public.test to usr2;

set role usr2;
select * from syntesttb;
create view testview as select * from test;
create synonym testsynview for testview;
select * from testview;

set role usr1;
drop synonym syntesttb;
drop synonym testsynview;

set role usr2;
drop synonym syntesttb;
drop synonym testsynview;

set role to default ;
drop view testview;
drop table test;

create type type_aa as(id int, name text);
set role usr2;
create public synonym testsyn for type_aa;
create table testaaa(id testsyn);

set role usr1;
create table testaaa1(id testsyn);

set role to default ;
drop table testaaa ;
drop type type_aa;

--test priority
create type typ_aa as(id int, name text);
create table test(id int, name text, addr text);

create synonym my_test_synonym for test;
create public  synonym my_test_synonym for typ_aa;

create table test_synonym(id my_test_synonym);
insert into test_synonym values ((1, 'zhangsanfeng', 'wudangshan'));
select * from test_synonym;

drop synonym my_test_synonym;
create table test_synonympub(id my_test_synonym);
insert into test_synonympub values ((1, 'zhangsanfeng'));
select * from test_synonympub;

drop public synonym my_test_synonym;

drop table test_synonym;
drop table test_synonympub;
drop table test;

drop type typ_aa;

create table test(id int, name text, addr text);
create table test1(id int, flg int);
create view testview as select * from test;

create public synonym test1_synonym for test1;
create synonym test1_synonym for testview;
select * from test1_synonym;

drop view testview;
drop table test;
drop table test1;

drop synonym test1_synonym;
drop public synonym test1_synonym;

create user syntestuser;
create user testuser;
grant create on database contrib_regression to syntestuser;
grant create on database contrib_regression to testuser;

set role to syntestuser;
create schema syntestuser1;
create schema syntestuser2;

create table syntestuser1.test (f1 int, f2 int);
create table syntestuser2.test (f1 int, f2 text);
create table syntestuser1.tbl (id int);
create table syntestuser2.tbl (id int);

create procedure syntestuser1.insert_data(a integer, b integer)
language sql
as $$
insert into syntestuser1.tbl values (a);
insert into syntestuser1.tbl values (b);
$$;

create procedure syntestuser2.insert_data(a integer, b integer)
language sql
as $$
insert into syntestuser2.tbl values (a + b);
$$;

create public synonym syninsert_data1 for syntestuser1.insert_data;
create synonym syninsert_data2 for syntestuser2.insert_data;
create synonym mysyntest1 for syntestuser1.test;
create public synonym mysyntest2 for syntestuser2.test;
create synonym mysyntest3 for syntestuser1.test;
create public synonym mysyntest3 for syntestuser2.test;
select * from user_synonyms;
insert into syntestuser1.test values (1,11), (2,22), (4,45);
insert into syntestuser2.test values (1,'chengdu'), (2,'sichuan');
select * from mysyntest1;
select * from mysyntest2;
select * from mysyntest3;
call syninsert_data1(1, 2);
call syninsert_data2(1, 2);
select * from syntestuser1.tbl;
select * from syntestuser2.tbl;

grant select on syntestuser1.test to testuser;
grant select on syntestuser2.test to testuser;
grant usage on schema syntestuser1 to testuser;
grant usage on schema syntestuser2 to testuser;
grant all privileges on all TABLES in schema syntestuser1 to testuser;
grant all privileges on all TABLES in schema syntestuser2 to testuser;

set role to testuser;
create synonym syninsert_data3 for syninsert_data1;
create public synonym syninsert_data4 for syninsert_data2;
create synonym mysyntest4 for syntestuser1.test;
create public synonym mysyntest5 for syntestuser2.test;
create synonym mysyntest6 for syntestuser1.test;
create public synonym mysyntest6 for syntestuser2.test;
select * from user_synonyms;
select * from mysyntest4;
select * from mysyntest5;
select * from mysyntest6;
select * from mysyntest1;
select * from mysyntest2;
select * from mysyntest3;
call syninsert_data1(1, 2);
call syninsert_data2(1, 2);
call syninsert_data3(1, 2);
call syninsert_data4(1, 2);
select * from syntestuser1.tbl;
select * from syntestuser2.tbl;
set role to default;
