--
-- Test Oracle-Compatible ROWID Pseudo-Column
--

--
--1, Support rowid feature via default_with_rowids GUC parameter
--
show ivorysql.default_with_rowids;

-- rowid conflicts with a system column
create table t1(rowid int, a int);	--error

set ivorysql.default_with_rowids to on;

create table t2 (a int, b int);

insert into t2 values(20, 3);
insert into t2 values(5, 7);
insert into t2 values(4, 9);

create table t3 (a int, b int);

insert into t3 values(2, 6);
insert into t3 values(15, 17);
insert into t3 values(5, 30);

-- select without rowid pseudo
select * from t2;
select * from t3;

-- select with rowid pseudo
select (rowid).rowno, * from t2;
select (rowid).rowno, * from t2 where (rowid).rowno = 3;

select (rowid).rowno, * from t3;
select (rowid).rowno, * from t3 where (rowid).rowno = 2;

-- test join
select (t2.rowid).rowno, (t3.rowid).rowno from t2 INNER join t3 on (t2.a = t3.a);

-- test update rowid column
update t2 set rowid = 100 where a = 20; --error

-- test update using rowid
update t2 set a = a + 100 where (rowid).rowno = 3;
select (rowid).rowno, * from t2;

--test delete using rowid
delete from t2 where (rowid).rowno = 1;
select (rowid).rowno, * from t2;

-- test insert rowid column
insert into t2(rowid, a, b) values(50, 2, 3); --error

drop table t2;
drop table t3;

set ivorysql.default_with_rowids to off;

--
--2, Support rowid feature via ALTER TABLE command
--
create table t2 (a int, b int);

insert into t2 values(20, 3);
insert into t2 values(5, 7);
insert into t2 values(4, 9);

alter table t2 set with rowid;

create table t3 (a int, b int);

alter table t3 set with rowid;

insert into t3 values(2, 6);
insert into t3 values(15, 17);
insert into t3 values(5, 30);


-- select without rowid pseudo
select * from t2;
select * from t3;

-- select with rowid pseudo
select (rowid).rowno, * from t2;
select (rowid).rowno, * from t2 where (rowid).rowno = 2;
select (rowid).rowno, * from t3;
select (rowid).rowno, * from t3 where (rowid).rowno = 1;

-- test join
select (t2.rowid).rowno, (t3.rowid).rowno from t2 INNER join t3 on (t2.a = t3.a);

-- test update rowid column
update t2 set rowid = 100 where a = 20; --error

-- test update using rowid
update t2 set a = a + 100 where (rowid).rowno = 3;
select (rowid).rowno, * from t2;

--test delete using rowid
delete from t2 where (rowid).rowno = 1;
select (rowid).rowno, * from t2;

-- test insert rowid column
insert into t2(rowid, a, b) values(50, 2, 3); --error

--
-- ALTER TABLE ... SET WITHOUT ROWID
--
alter table t2 set without rowid;

select (rowid).rowno, * from t2;

-- cleanup
drop table t2;
drop table t3;

--
--3, CREATE TABLE ... WITH ROWID
--
create table t2 (a int, b int) with rowid;

insert into t2 values(20, 3);
insert into t2 values(5, 7);
insert into t2 values(4, 9);

create table t3 (a int, b int) with rowid;

insert into t3 values(2, 6);
insert into t3 values(15, 17);
insert into t3 values(5, 30);

-- select without rowid pseudo
select * from t2;
select * from t3;

-- select with rowid pseudo
select (rowid).rowno, * from t2;
select (rowid).rowno, * from t2 where (rowid).rowno = 1;
select (rowid).rowno, * from t3;
select (rowid).rowno, * from t3 where (rowid).rowno = 2;

-- test join
select (t2.rowid).rowno, (t3.rowid).rowno from t2 INNER join t3 on (t2.a = t3.a);

drop table t2;
drop table t3;

--
--4, Test rowid type
--
create table t2(a int, b int) with rowid;
insert into t2 values(100, 101);

create or replace function tf_r() return int
as
declare
    rr rowid;
begin
    select rowid from t2 into rr;
    raise info 'rr.rowno = %', rr.rowno;
	return 1;
end;
/

select tf_r() from dual;
drop table t2;
drop function tf_r;

--
--5, Test PARTITION TABLE support ROWID
--
create table ptable(id int, td varchar2(100)) partition by list(td) with rowid;
create table pt_01 partition of ptable for values in ('2021-08-05');
create table pt_02 partition of ptable for values in ('2021-08-06');

insert into ptable values(1,'2021-08-05');
insert into ptable values(2,'2021-08-05');
insert into ptable values(3,'2021-08-05');
insert into ptable values(4,'2021-08-05');
insert into ptable values(5,'2021-08-06');
insert into ptable values(6,'2021-08-06');
insert into ptable values(7,'2021-08-06');
insert into ptable values(8,'2021-08-06');

select (rowid).rowno, * from ptable;
select (rowid).rowno, * from pt_01;
select (rowid).rowno, * from pt_02;

drop table ptable;

--
--6, Test default index on rowid
--
create table t2(mystr varchar2(100), id int) with rowid;

insert into t2 SELECT 'INSERT table t2 WITH ROWID', generate_series(1,20000);

select (rowid).rowno, * from t2 limit 10;

explain (COSTS OFF) select (rowid).rowno, * from t2 where (rowid).rowno = 9;

drop table t2;

--
--7, Test CREATE TABLE LIKE
--
create table t2 (a int, b int) with rowid;
create table t2_like (LIKE t2);
insert into t2_like values(20, 3);
insert into t2_like values(5, 7);
insert into t2_like values(4, 9);

select (rowid).rowno, * from t2_like;

drop table t2_like;
drop table t2;

--
--8, Test temp table with rowid
--
create temp table t3(
    mystr  text,
    id      int
) with rowid;

insert into t3 SELECT 'INSERT TEMP table t3 WITH ROWID', generate_series(1,200);

select (rowid).rowno, * from t3 limit 5;

drop table t3;

--
--9, Test GTT with rowid
--
create global temporary table t4(
    mystr  text,
    id      int
) with rowid ON COMMIT PRESERVE ROWS;

insert into t4 SELECT 'INSERT GTT table t4 WITH ROWID', generate_series(1,200);

select (rowid).rowno, * from t4 limit 5;

truncate table t4;
drop table t4;


--
--10, Test View
--
create table t2(mystr varchar2(100), id int) with rowid;
	
insert into t2 SELECT 'INSERT table t2 WITH ROWID', generate_series(1,5);

create view v1 as select (rowid).rowno,* from t2;

select rowno from v1;

select * from v1;

drop view v1;
drop table t2;
