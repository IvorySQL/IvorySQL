drop package pkg;

create or replace package pkg is
  x int;
  y varchar := 'test';
  
  -- no argument function creation
  function tfunc return int;
  
  -- no argument procedure creation
  procedure tpro;
  
  function tfunc2(x int) return int;
  procedure tpro(x int);
end;
/

create or replace package body pkg is
  -- no argument function creation, no declaration section
  function tfunc return int as
  begin
  	null;
  end;
  
  -- no argument procedure creation, with declarations
  procedure tpro as
  	pvar int;
  begin
   	pvar:=10;
  end;
  
  
  function tfunc2(x int) return int as
  begin
  	null;
  end;
  
  procedure tpro(x int) as
  begin
  	null;
  end;
end;
/

-- Package 'pkg' should have all 5 memebers.
select proname, proargtypes from pg_proc p, pg_package pk where pronamespace=pk.oid and pkgname='pkg' order by proname;

drop package pkg;

create or replace package pkg is
  x int;
  y varchar := 'test';
  
  -- no argument function creation
  function tfunc return int;
end;
/

create or replace package body pkg is
	function tfunc return int as
  	begin
  		-- IF statement
		if y == 'test' then
			null;
		end if;

  		-- IF/elsif/else statement
		if y = 'test' then
			null;
		elsif x == 10 then
			null;
		elsif x == 11 then
			null;
		else
			null;
		end if;
		
		-- CASE statement
		case x
		 	when 1 then null;
			when 2 then null;
			else
				null;
		end case;
		
		-- CASE without selector statement
		case 
		 	when x == 1 then null;
			when x == 2 then null;
			else
				null;
		end case;
  	end;
end;
/

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

-- without schema qualification
select pkg.tfunc(10);

-- with schema qualification
select public.pkg.tfunc(100);

-- with database.schema qualification
select postgres.public.pkg.tfunc(10);
DROP package pkg;

--
-- package with some variable initializations and implicit constructor.
--
create or replace package pkg is
	x int := 1;
	foo int;
	function tfunc(x int) return int;
end;
/

create or replace package body pkg is
  a int := 10; 
  b numeric := 10.2; 
  y varchar := 'hello';
   
   function tfunc(x int) return int as
   begin
   	return x;
   end;
end;
/

select proname, prosrc from pg_proc p, pg_package pk where pronamespace=pk.oid and pkgname='pkg' order by proname;
drop package pkg;

--
-- Test package functions and procedures overloading
--
create or replace package pkg 
is
  -- no argument function creation
  function tfunc return int;
  
  -- no argument procedure creation
  procedure tpro;

  -- overload functions and procedures
  function tfunc(x int,y int) return int;
  procedure tpro(x int);
end;
/


create or replace package body pkg 
is
  function tfunc return int 
  as
  begin
   return 0;
  end;
  
  procedure tpro 
  as
  	pvar int;
  begin
   pvar:=10;
  end;
  
  function tfunc(x int,y int) return int 
  as
  begin
   return (x+y);
  end;
  
  procedure tpro(x int) 
  as
  	y int;
  begin
   y := x;
  end;
end;
/

-- invoking package functions
select pkg.tfunc();
select pkg.tfunc(1,2);

drop package pkg;


--
-- Test package explicit initialization function
--
create or replace package pkg 
is
 x int := 1;
 a int;
	
 function tfunc(x int) return int;
end;
/
 
create or replace package body pkg 
is
 b numeric; 
 y varchar;
	
 function tfunc(x int) return int 
 as
 begin
  return x;
 end;

 -- explicit initialization
 begin
  a := 10; 
  b := 10.2; 
  y := 'hello';	
end;
/

select proname, 'Package Constructor', prosrc from pg_proc p, pg_package pk where pronamespace=pk.oid and proname='pkg' order by proname;
drop package pkg;

--
-- create package with definer rights
--
create or replace package pkg AUTHID DEFINER
is
 function fdef return text;
end;
/

create or replace package body pkg
is
 function fdef return text
 as
 begin
  return 'AUTHID DEFINER';
 end;
end;
/

select pkg.fdef();

drop package pkg;

--
-- create package with invoker rights
--
create or replace package pkg AUTHID CURRENT_USER
is
 function finvok return text;
end;
/

create or replace package body pkg
is
 function finvok return text
 as
 begin
  return 'AUTHID CURRENT_USER';
 end;
end;
/

select pkg.finvok();

drop package pkg;


--
-- cover ROWTYPE and TYPE syntax
--
create table tb_pkg(t_id int, t_name text);

create or replace package pkg
is
 function read_line(id int) return text;
 procedure inst_tb(tid tb_pkg.t_id%TYPE, tname tb_pkg.t_name%TYPE);
end;
/

create or replace package body pkg
is

 function read_line(id int) return text
 as
   line tb_pkg%ROWTYPE;
 begin
 	select * into line from tb_pkg where t_id = id;
    return line;
 end;

 procedure inst_tb(tid tb_pkg.t_id%TYPE, tname tb_pkg.t_name%TYPE)
 as
 begin
	insert into tb_pkg values(tid,tname);
 end; 
end;
/


drop table tb_pkg;
drop package pkg;

--
--ACL privilege test 
--
drop role if exists postgres;
create role postgres superuser;
drop role if exists pkger1;
drop role if exists pkger2;

create role pkger1;
create role pkger2;

set role to pkger1;

create or replace package pkg is
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


revoke all on package pkg from public;

set role to pkger2;
select pkg.tfunc(10);

set role to pkger1;
grant EXECUTE on PACKAGE pkg to pkger2;

set role to pkger2;
select pkg.tfunc(10);

set role to postgres;

drop package pkg;
drop role pkger1;
drop role pkger2;



--
-- Compatible with the declare syntax in oracle
--
create or replace package pkg is
function tfunc return int;
end;
/

create or replace package body pkg is
function tfunc return int as
	--DECLARE is optional here
	x int;
	z varchar;
	begin
		null;
		declare  --DECLARE is mandatory here
		a int;
		b int;
		begin
			null;
		end;
		return 1;
	end;
end;
/

select pkg.tfunc();
drop package pkg;

--
-- Support oracle compatible function and procedure creation through PSQL client.
--
drop function if exists test_ora;
create or replace function test_ora(a int) return int
as
begin  
	return a;
end;
/

select test_ora(10);
drop function test_ora;

drop procedure if exists test_pro;
create or replace procedure test_pro() 
is
begin  
	null;
end;
/

call test_pro();
drop procedure test_pro;


-- Test oracle-style function and procedure without parameter
create or replace function test_ora return int
as
begin
	return 1;
end;
/

select test_ora();
drop function test_ora;

create or replace procedure test_pro
is
begin
	null;
end;
/

call test_pro();
drop procedure test_pro;


--
-- execute a package function without arguments, allow the invocaton without parentheses.
--
create or replace package pkg
is
 x int;
 y varchar := 'test';

 function tfunc return int;
end;
/

create or replace package body pkg
is

 function tfunc return int as
 begin
  return 716;
 end;

end;
/

-- PG behavior
select pkg.tfunc();
select public.pkg.tfunc();

-- Compatible with Oracle behavior
select pkg.tfunc;
select public.pkg.tfunc;

drop package pkg;

--acccess package variable

create or replace package pkg is
x int:=9999;
function tfunc return int;
end;
/

create or replace package body pkg is
function tfunc return int as
declare
	a int;
	begin
		select pkg.x into a;return a;
	end;
end;
/

create schema ab;
create or replace package ab.pkg is
x int:=9999;
function tfunc return int;
end;
/
create or replace package body ab.pkg is
function tfunc return int as declare a int;
begin
select pkg.x into a;return a;
end;
end;
/

select ab.pkg.x; -- error, because package variables not accessible from outside PL constucts
select ab.pkg.tfunc;

drop package pkg;
drop schema ab CASCADE;

-- create a test table
drop table IF EXISTS test;

create table test(x int, y varchar(100));
insert into test values(1, 'One');
insert into test values(2, 'Two');
insert into test values(3, 'Three');

-- creat a package with cursor variable
-- define one function to open and another to fetch.
create or replace package pkg is
	CURSOR c1 IS SELECT x,y FROM test;
	function c_open return int;
	function c_fetch return int;
end;
/

create or replace package body pkg is
	function c_open return int as
	begin
		OPEN c1;
		return 0;
	end;

	function c_fetch return int as
		v_x  test.x%TYPE;
		v_y  test.y%TYPE;
	begin
		LOOP
            FETCH c1 INTO v_x, v_y;
			EXIT WHEN NOT FOUND;
			raise info '%, %', v_x, v_y;
		END LOOP;

		CLOSE c1;
		return 0;
	end;

begin
	raise info 'initializer';
end;
/

select pkg.c_open();
select pkg.c_fetch();

select pkg.c_fetch(); -- error
select pkg.c_open(); -- reopen
select pkg.c_fetch(); -- fetch again

-- cleanup existing objects
drop package pkg;
drop table IF EXISTS test;
drop package pkgvar;
drop function if exists foo_var;

-- Test some scalar type variables access in PL construct
create or replace package pkgvar is
	v_int int;
    v_int_init int := 100;	-- initilize variable
	v_varchar varchar(20);
	v_varchar_init varchar(20) := 'Test Value';

	function tf return int;
end;
/

create or replace package body pkgvar is
	v_int_priv int;			-- private variable
	function tf return int as
	begin
		v_int_priv := 101;
		raise info 'pkgvar.v_int: %', pkgvar.v_int;
		raise info 'pkgvar.v_int_init: %', pkgvar.v_int_init;
		raise info 'pkgvar.v_int_priv: %', pkgvar.v_int_priv;
		raise info 'pkgvar.v_varchar: %', pkgvar.v_varchar;
		raise info 'pkgvar.v_varchar_init: %', pkgvar.v_varchar_init;
		return 0;
	end;
begin
	raise info 'initializer';
end;
/

-- try to access package uninitialized and initilized variables
-- execution should successful.
create or replace function foo_var() return int as
	x int;
	y varchar(20);
begin

	x := pkgvar.v_int + 10;
	raise info 'pkgvar.v_int: %', x; -- NULL

	pkgvar.v_int := 1;				-- assign some value
	raise info 'pkgvar.v_int: %', pkgvar.v_int;

	x := pkgvar.v_int_init + 10;
	raise info 'pkgvar.v_int_init: %', x;
	pkgvar.v_int_init := x;
	raise info 'pkgvar.v_int_init: %', pkgvar.v_int_init;

	y := pkgvar.v_varchar;
	raise info 'pkgvar.v_varchar: %', y;	-- NULL

	y := pkgvar.v_varchar_init;
	raise info 'pkgvar.v_varchar_init: %', y;

	pkgvar.v_varchar := 'Test Val 1';
	pkgvar.v_varchar_init := 'Test Val 2';
	raise info 'pkgvar.v_varchar: %', pkgvar.v_varchar;
	raise info 'pkgvar.v_varchar_init: %', pkgvar.v_varchar_init;

	return x;
end;
/

select foo_var();
select pkgvar.tf(); -- call package see if the values update?

-- try to access private package variable
-- should get an error
create or replace function foo_var() return int as
	x int;
begin
	x := pkgvar.v_int_priv + 10;
	raise info 'pkgvar.v_int: %', x;
	return x;
end;
/

drop package pkgvar;
drop function foo_var;

create table test(x int, y varchar(100));
insert into test values(1, 'One');
insert into test values(2, 'Two');
insert into test values(3, 'Three');

-- Test cursor variables in package
-- create a package with cursor and a rowtype var
create or replace package pkgvar is
	CURSOR c1 IS SELECT x,y FROM test;

	v_test       test%ROWTYPE;
	function c_open return int;		-- function to open a cursor
	function c_fetch return int;	-- function fetch data from already
									-- opened cursor.
end;
/

create or replace package body pkgvar is
	function c_open return int as
	begin
		raise info 'v_test in c_open: %', v_test;
		OPEN c1;
		return 0;
	end;

	function c_fetch return int as
	begin
		LOOP
            FETCH c1 INTO v_test;
			EXIT WHEN NOT FOUND;
			raise info 'v_test in c_fetch: %', v_test;
		END LOOP;

		CLOSE c1;
		raise info 'v_test in c_fetch end: %', v_test;
		return 0;
	end;

begin
	raise info 'initializer';
end;
/

select pkgvar.c_open();		-- open cursor
select pkgvar.c_fetch();	-- fetch values and close cursor

create or replace function foo_var() return int as
 x int;
 v_test       test%ROWTYPE;
begin
	open pkgvar.c1;			-- open cursor in PL construct
	LOOP
		FETCH pkgvar.c1 INTO v_test;	-- fetch cursor
		EXIT WHEN NOT FOUND;
		raise info 'v_test in c_fetch: %', v_test;
	END LOOP;
	CLOSE pkgvar.c1;

	-- v_test should persist
	raise info 'v_test in c_fetch end: %', v_test;
	return 0;
end;
/

select foo_var();

-- clear our all objects.
drop package pkgvar;
drop function foo_var;
drop table if exists test;


-- Test package vars without package body
create or replace package pkgvar is
	v_int int;
    v_int_init int := 100;	-- initilize variable
end;
/

create or replace function foo_var() return int as
begin
	raise info 'pkgvar.v_int: %', pkgvar.v_int;
	pkgvar.v_int := 0;
	raise info 'pkgvar.v_int_init: %', pkgvar.v_int_init;
	pkgvar.v_int_init := pkgvar.v_int_init + 1;

	return pkgvar.v_int;
end;
/
select foo_var();
select foo_var();
select foo_var();

-- clear our all objects.
drop package pkgvar;
drop function foo_var;


--
-- Test cursor with parameter in package
--
create table test(x int, y varchar(100));
insert into test values(1, 'One');
insert into test values(2, 'Two');
insert into test values(3, 'Three');

create or replace package pkgcur1
as
	cursor c1(in_v int) return test%rowtype;

	curvar test%rowtype;

	function open_cur(m int) return int;
	function fetch_cur return int;
end;
/

create or replace package body pkgcur1
as
	cursor c1(in_v int) return test%rowtype
	is
		select x,y from test where x = in_v;


	function open_cur(m int) return int
	as
	begin
		raise info 'open the cursor c1.';
		open c1(m);
		return 1;
	end;

	function fetch_cur return int
	as
	begin
		fetch c1 into curvar;
		raise info 'curvar.x = %, curvar.y = %', curvar.x, curvar.y;
		close c1;
		return 0;
	end;
end;
/

--
-- Test the same cursor in different packages
--
create or replace package pkgcur2
as
	cursor c1(in_v int) return test%rowtype;
	curvar test%rowtype;

	function open_cur(m int) return int;
	function fetch_cur return int;
end;
/

create or replace package body pkgcur2
as
	cursor c1(in_v int) return test%rowtype
	is
		select x,y from test where x = in_v;


	function open_cur(m int) return int
	as
	begin
		raise info 'open the cursor c1.';
		open c1(m);
		return 1;
	end;

	function fetch_cur return int
	as
	begin
		fetch c1 into curvar;
		raise info 'curvar.x = %, curvar.y = %', curvar.x, curvar.y;
		close c1;
		return 0;
	end;
end;
/

create or replace package pkgcur3
as
	cursor emp_cur(a int)
	is
		select * from test where x = a;
	emp_rec emp_cur%rowtype;
	function get_emp_info(a int) return int;
end;
/

create or replace package body pkgcur3
as
	function get_emp_info(a int) return int
	as
	begin
		open emp_cur(a);
		loop
			fetch emp_cur into emp_rec;
			exit when not found;
			raise notice 'fetch emp_rec:%,%', emp_rec.x,emp_rec.y;
		end loop;
		close emp_cur;
		return 0;
	end;
end;
/

select pkgcur1.open_cur(1);
select pkgcur2.open_cur(1);
select pkgcur3.open_cur(1);

select name, statement from pg_cursors;

select pkgcur1.fetch_cur;
select pkgcur2.fetch_cur;
select pkgcur3.fetch_cur;

drop package pkgcur1;
drop package pkgcur2;
drop package pkgcur3;
drop table if exists test;


-- Test package vars with package body but without initializer
create or replace package pkgvar is
	v_int int;
    v_int_init int := 100;	-- initilize variable
	function tf return int;
end;
/

create or replace package body pkgvar is
	v_int_priv int := 100;
	function tf return int as
	begin
		raise info 'function tf called';
		return 0;
	end;
end;
/

create or replace function foo_var() return int as
begin
	raise info 'pkgvar.v_int: %', pkgvar.v_int;
	pkgvar.v_int := 0;
	raise info 'pkgvar.v_int_init: %', pkgvar.v_int_init;
	pkgvar.v_int_init := pkgvar.v_int_init + 1;

	return pkgvar.v_int;
end;
/
select foo_var();
select foo_var();
select foo_var();

-- error on accessing package private variables
create or replace function foo_var() return int as
begin
	raise info 'pkgvar.v_int_priv: %', pkgvar.v_int_priv;
	return pkgvar.v_int_priv;
end;
/

-- clear our all objects.
drop package pkgvar;
drop function foo_var;


create or replace package pkgvar is
	v_int int;
    v_int_init int := 100;	-- initilize variable
	function tf return int;
end;
/

create or replace package body pkgvar is
	v_int_priv int := 100;
	function tf return int as
	begin
		raise info 'function tf called';
		return 0;
	end;
end;
/

create or replace function foo_var() return int as
begin
	raise info 'pkgvar.v_int: %', pkgvar.v_int;
	pkgvar.v_int := 0;
	raise info 'pkgvar.v_int_init: %', pkgvar.v_int_init;
	pkgvar.v_int_init := pkgvar.v_int_init + 1;

	return pkgvar.v_int;
end;
/
select foo_var();

-- drop package and see if the function notices that the package has
-- dropped.
drop package pkgvar;
select foo_var(); -- should throw error

-- clear our all objects.
drop package pkgvar;
drop function foo_var;


-- test package function/procedure calls.
CREATE TABLE dept (
    deptno          NUMERIC(2) NOT NULL,
    dname           VARCHAR(14),
    loc             VARCHAR(13)
);

INSERT INTO dept VALUES (10,'R&D','ISB');
INSERT INTO dept VALUES (20,'HeadOffice','China');
INSERT INTO dept VALUES (30,'R&D 2','Canada');

CREATE TABLE emp_ (
    empno           NUMERIC(4) NOT NULL,
    ename           VARCHAR(10),
    job             VARCHAR(9),
    mgr             NUMERIC(4),
    hiredate        DATE,
    sal             NUMERIC(7,2) ,
    comm            NUMERIC(7,2),
    deptno          NUMERIC(2)
);

CREATE TABLE jobhist (
    empno           NUMERIC(4) NOT NULL,
    startdate       DATE,
    enddate         DATE,
    job             VARCHAR(9),
    sal             NUMERIC(7,2),
    comm            NUMERIC(7,2),
    deptno          NUMERIC(2),
    chgdesc         VARCHAR(80)
);

CREATE OR REPLACE PACKAGE emp_admin
IS
    v_dname  VARCHAR(14);
    v_sal    NUMERIC := 0;

    FUNCTION get_dept_name
    (
        p_deptno NUMERIC
    ) RETURN VARCHAR;

    FUNCTION update_emp_sal
    (
        p_empno         NUMERIC,
        p_raise         NUMERIC
    ) RETURN NUMERIC;

    PROCEDURE hire_emp
    (
        p_empno         NUMERIC,
        p_ename         VARCHAR,
        p_job           VARCHAR,
        p_sal           NUMERIC,
        p_hiredate      DATE,
        p_comm          NUMERIC,
        p_mgr           NUMERIC,
        p_deptno        NUMERIC
    );

    PROCEDURE fire_emp
    (
        p_empno         NUMERIC
    );
END emp_admin;
/

CREATE OR REPLACE PACKAGE BODY emp_admin
IS
    FUNCTION get_dept_name (
        p_deptno        IN NUMERIC
    ) RETURN VARCHAR
    IS
    BEGIN
        SELECT dname INTO v_dname FROM dept WHERE deptno = p_deptno;
        RETURN v_dname;
    END;

    FUNCTION update_emp_sal (
        p_empno         IN NUMERIC,
        p_raise         IN NUMERIC
    ) RETURN NUMERIC
    IS
    BEGIN
        SELECT sal INTO v_sal FROM emp_ WHERE empno = p_empno;
        v_sal := v_sal + p_raise;
        UPDATE emp_ SET sal = v_sal WHERE empno = p_empno;

        RETURN v_sal;
    END;

    PROCEDURE hire_emp (
        p_empno         NUMERIC,
        p_ename         VARCHAR,
        p_job           VARCHAR,
        p_sal           NUMERIC,
        p_hiredate      DATE,
        p_comm          NUMERIC,
        p_mgr           NUMERIC,
        p_deptno        NUMERIC
    )
    AS
    BEGIN
        INSERT INTO emp_ (empno, ename, job, sal, hiredate, comm, mgr, deptno) VALUES (p_empno, p_ename, p_job, p_sal,p_hiredate, p_comm, p_mgr, p_deptno);
    END;

    PROCEDURE fire_emp (
        p_empno         NUMERIC
    )
    AS
    BEGIN
        DELETE FROM emp_ WHERE empno = p_empno;
    END;
END;
/

CREATE OR REPLACE PACKAGE emp_ops
AS

	FUNCTION add_emp
	(
        v_empno         NUMERIC,
        v_ename         VARCHAR,
        v_job           VARCHAR,
        v_sal           NUMERIC,
		v_hiredate      DATE,
        v_comm          NUMERIC,
        v_mgr           NUMERIC,
        v_deptno        NUMERIC
    ) RETURN numeric;
END;
/

CREATE OR REPLACE PACKAGE BODY emp_ops
AS
    v_dname         VARCHAR(14);
    total_emp	    Numeric;

	FUNCTION add_emp
	(
        v_empno         NUMERIC,
        v_ename         VARCHAR,
        v_job           VARCHAR,
        v_sal           NUMERIC,
		v_hiredate      DATE,
        v_comm          NUMERIC,
        v_mgr           NUMERIC,
        v_deptno        NUMERIC
    ) RETURN numeric IS
    BEGIN
		v_dname := emp_admin.get_dept_name(10);
		raise notice 'dept name : %',v_dname;

		-- Call package procedure hire_emp
		emp_admin.hire_emp (v_empno,v_ename,v_job,v_sal,v_hiredate,v_comm,v_mgr,v_deptno);

        select count(*) into total_emp from emp_;
		raise notice 'total employees : %',total_emp;
		return 0;
    END;
END;
/

select public.emp_admin.get_dept_name(10);

select emp_ops.add_emp(100,'SMITH','CLERK',7902,to_date('17-12-2018','dd-mm-yyyy'),800,NULL,20);

drop table if exists dept;
drop table if exists emp_;
drop table if exists jobhist;
drop package emp_ops;
drop package emp_admin;

-- Test can access fields of test%rowtype.
create table test(x int, y varchar(100));
insert into test values(1, 'One');
insert into test values(2, 'Two');
insert into test values(3, 'Three');

create or replace package pkgvar
as
	cursor emp_cur is select * from test;
	emp_rec test%rowtype;
	function get_emp_info return int;
end;
/

create or replace package body pkgvar
as
	function get_emp_info return int as
	begin
		open emp_cur;
		loop
			fetch emp_cur into emp_rec;
			exit when not found;
			raise notice 'emp_rec = %, %', emp_rec.x, emp_rec.y; -- access record fields
		end loop;
		close emp_cur;
		return 0;
	end;
end;
/

select pkgvar.get_emp_info();

drop package pkgvar;
drop table if exists test;

-- Test package function calls without package qualification within package
create or replace function f4(x int) return int as
begin
	raise info 'function outter f4 called';
	x := f1(1);
	return 0;
end;
/

create or replace function f1(x int) return int as
begin
	raise info 'function outter f1 called';
	return 0;
end;
/

create or replace package pkg as
	function f1(x int) return int;
	function f2(x int) return int;
end;
/

create or replace package body pkg as
	function f1(x int) return int as
	begin
		raise info 'function f1 called';
		x:=f4(x);
		return 0;
	end;

	function f2(x int) return int as
	y int;
	begin
		y := f1(1);
		raise info 'function f2 called';
		return y;
	end;

end;
/
select pkg.f2(1);
drop package pkg;
drop function f1(x int);
drop function f4(x int);

-- Test package procedure calls without package qualification within package
create or replace procedure p4 (x int) is
y int;
begin
	raise info 'procedure outter p4 called';
	call p1(1); -- call to non package procedure.
end;
/

create or replace procedure p1 (x int) is
y int;
begin
	raise info 'procedure outter p1 called';
end;
/

create or replace package pkg as
	procedure p1 (x int);
	procedure p2 (x int);
end;
/

create or replace package body pkg as
	procedure p1 (x int) as
	y int;
	begin
		raise info 'procedure p1 called';
		p4(1);
	end;

	procedure p2 (x int) as
	y int;
	begin
		p1(1);
		raise info 'procedure p2 called';
	end;
end;
/
call pkg.p2(1);
drop package pkg;
drop procedure p1 (x int);
drop procedure p4 (x int);

-- Test TYPE IS RECORD. Type is created in spec and body.
drop table if exists test;
create table test(x int, y varchar(100));
insert into test values(1, 'One');

create or replace package pkgrec as
    type rectype is record(a test.x%type, b test.y%type);

    rcvar rectype;
    function initvars return int;
	function getvars return int;
end;
/

create or replace package body pkgrec as
	type rectype_priv is record(a test.x%type, b test.y%type);

	rcvar_pr rectype_priv;

	function initvars return int as
	begin
	   select x, y into rcvar from test where x = 1;
	   rcvar_pr = rcvar;
	   rcvar_pr.a := rcvar_pr.a + 10;
	   rcvar_pr.b := rcvar_pr.b || ' Ten';

       return rcvar_pr.a;
	end;

	function getvars return int as
	begin
		raise info 'rcvar.a = %, rcvar.b = %', rcvar.a, rcvar.b;
		raise info 'rcvar_pr.a = %, rcvar_pr.b = %', rcvar_pr.a, rcvar_pr.b;
		return 0;
	end;
end;
/

-- create body again to see if it still works. (test should pass)
create or replace package body pkgrec as
	type rectype_priv is record(a test.x%type, b test.y%type);

	rcvar_pr rectype_priv;

	function initvars return int as
	begin
	   select x, y into rcvar from test where x = 1;
	   rcvar_pr = rcvar;
	   rcvar_pr.a := rcvar_pr.a + 10;
	   rcvar_pr.b := rcvar_pr.b || ' Ten';

       return rcvar_pr.a;
	end;

	function getvars return int as
	begin
		raise info 'rcvar.a = %, rcvar.b = %', rcvar.a, rcvar.b;
		raise info 'rcvar_pr.a = %, rcvar_pr.b = %', rcvar_pr.a, rcvar_pr.b;
		return 0;
	end;
end;
/

--Test Type IS RECORD in functions
create or replace function get_rec() return int as
    type rectype is record(a int, b varchar(100));
    rcvar rectype;
begin
    select x, y into rcvar from test where x = 1;
    raise info 'rcvar.x = %, rcvar.y = %', rcvar.x, rcvar.y;
    return rcvar.x;
end;
/

--cleanup
select pkgrec.initvars;
select pkgrec.getvars;
select get_rec();
drop package pkgrec;
drop table if exists test;
drop function get_rec();

--test funtion pg_identify_object_as_address(classid,objid,objsubid)
create or replace package pkg as
v_int int:=100;
end;
/
create or replace function fun_call() return int as
var int8;
begin
	select oid into var from pg_variable where varname='v_int';
	perform pg_identify_object_as_address(561,var,0);
	return 0;
end;
/
select fun_call();
drop package pkg;
drop function fun_call;


--with schema test
create schema abs;
create or replace package abs.pkg as
var int;
function tfunc return int;
end;
/
create or replace package body abs.pkg as
function tfunc return int as
begin
	return 0;
end;
end;
/
select abs.pkg.tfunc();
drop package abs.pkg;
drop schema abs;

create table test(x int, y varchar(100));
insert into test values(1, 'One');
insert into test values(2, 'Two');

create or replace package pkgrec as
    type rectype is record(a test.x%type, b test.y%type);
    rcvar rectype;
    function initvars return int;
	function getvars return int;
end;
/

create or replace package body pkgrec as
	type rectype_priv is record(a test.x%type, b test.y%type);
	rcvar_pr rectype_priv;

	function initvars return int as
	begin
		select x, y into rcvar from test where x = 2;
		rcvar_pr = rcvar;
		rcvar_pr.a := rcvar_pr.a + 10;
		rcvar_pr.b := rcvar_pr.b || ' Ten';

		return rcvar_pr.a;
	end;

	function getvars return int as
	begin
		raise info 'rcvar.a = %, rcvar.b = %', rcvar.a, rcvar.b;
		raise info 'rcvar_pr.a = %, rcvar_pr.b = %', rcvar_pr.a, rcvar_pr.b;
		return 0;
	end;
end;
/

create or replace function printrec() return int as
begin
	raise info 'rcvar.x = %, rcvar.y = %', pkgrec.rcvar.a, pkgrec.rcvar.b;
    select x, y into pkgrec.rcvar from test where x = 1;
	raise info 'rcvar.x = %, rcvar.y = %', pkgrec.rcvar.a, pkgrec.rcvar.b;

    return pkgrec.rcvar.a;
return 0;
end;
/

--
select pkgrec.initvars();
select printrec();
select pkgrec.getvars();

drop function printrec;
drop package pkgrec;
drop table test;

--
--Test type ... is ref cursor in package
--
create table test(x int, y varchar(100));
insert into test values(1, 'One');
insert into test values(2, 'Two');
insert into test values(3, 'Three');

create or replace package pkg_ref
as
	type t_refcur is ref cursor;

	tref t_refcur;
	trow test%rowtype;

	function refunc(in_a int) return int;
end;
/

create or replace package body pkg_ref
as
	function refunc(in_a int) return int
	as
	begin
		open tref for select * from test where x = in_a;
		fetch tref into trow;
		raise info 'trow.x = %, trow.y = %', trow.x, trow.y;
		close tref;
		return trow.x;
	end;
end;
/

select pkg_ref.refunc(1);
select pkg_ref.refunc(2);
select pkg_ref.refunc(3);
drop package pkg_ref;
select name, statement, is_holdable, is_binary, is_scrollable from pg_cursors;

--
--Test type ... is ref cursor in PL functions
--
create or replace function tfunc(a int) return int
as
	type t_refcur is ref cursor;
	tref t_refcur;
	trow test%rowtype;
begin
	open tref for select * from test where x = a;
	fetch tref into trow;
	raise info 'trow.x = %, trow.y = %', trow.x, trow.y;
	return trow.x;
end;
/

select tfunc(1);
select tfunc(2);
select tfunc(3);

drop function tfunc;
drop table test;

--
--Test DROP PACKAGE BODY feature
--
create or replace package pkgvar
is
	v_int int;
    v_int_init int := 100;
	function tf return int;
end;
/

create or replace package body pkgvar
is
	v_int_priv int := 1000;
	type rectype is record(a int, b text);
	function tf return int as
	begin
		raise info 'function tf called';
		return v_int_priv;
	end;
	function tp return int as
	begin
		return v_int_init;
	end;
end;
/

select pkgvar.tf();
select pkgvar.tp();

select proname,prosrc from pg_proc proc, pg_package pk where proname = 'tf' and pronamespace = pk.oid;
select proname,prosrc from pg_proc proc, pg_package pk where proname = 'tp' and pronamespace = pk.oid;
select varname from pg_variable pv, pg_package pk where varnamespace = pk.oid;
select typname from pg_type pt, pg_package pk where typtype = 'c' and typnamespace = pk.oid;

DROP PACKAGE BODY pkgvar;

select proname,prosrc from pg_proc proc, pg_package pk where proname = 'tf' and pronamespace = pk.oid;
select proname,prosrc from pg_proc proc, pg_package pk where proname = 'tp' and pronamespace = pk.oid;
select varname from pg_variable pv, pg_package pk where varnamespace = pk.oid;
select typname from pg_type pt, pg_package pk where typtype = 'c' and typnamespace = pk.oid;

DROP PACKAGE BODY pkgvar;

select pkgvar.tf();
DROP PACKAGE pkgvar;

--test drop package body when there is no body infomation
create or replace package pkgvar is
	v_int int;
    v_int_init int := 100;
	function tf return int;
end;
/
DROP PACKAGE BODY pkgvar;
select pkgvar.tf;
DROP PACKAGE pkgvar;

--close the opened cursor when drop package body
create table test(x int, y varchar(100));
insert into test values(1, 'One');
insert into test values(2, 'Two');
insert into test values(3, 'Three');

create or replace package pkg is
	CURSOR c1 IS SELECT x,y FROM test;
	function c_open return int;
	function c_fetch return int;
end;
/

create or replace package body pkg is
	function c_open return int as
	begin
		OPEN c1;
		return 0;
	end;

	function c_fetch return int as
		v_x  test.x%TYPE;
		v_y  test.y%TYPE;
	begin
		LOOP
            FETCH c1 INTO v_x, v_y;
			EXIT WHEN NOT FOUND;
			raise info '%, %', v_x, v_y;
		END LOOP;

		CLOSE c1;
		return 0;
	end;

begin
	raise info 'initializer';
end;
/
select * from pg_cursors;
select pkg.c_open();
select name, statement, is_holdable, is_binary, is_scrollable from pg_cursors;
DROP PACKAGE BODY pkg;
select name, statement, is_holdable, is_binary, is_scrollable from pg_cursors;
DROP TABLE test;
DROP PACKAGE pkg;

--
-- support package function return the defined type
--
CREATE OR REPLACE PACKAGE example
AS
	TYPE extyp IS RECORD (a INT, b VARCHAR(100));
	FUNCTION myfunc(x INT) RETURN extyp;
end;
/

CREATE OR REPLACE PACKAGE BODY example
AS
	FUNCTION myfunc(x INT) RETURN extyp
	AS
		f_emp extyp;
	BEGIN
		f_emp.a := x;
		f_emp.b := 'Hello IvorySQL!';
		RETURN f_emp;
	END;
END;
/

select example.myfunc(2022);

DROP PACKAGE example;

--
-- Test package array variable
--
CREATE OR REPLACE PACKAGE pkg IS
  x int[] := array[1,2,3,4];
  FUNCTION tfunc RETURN INT;
END;
/
CREATE OR REPLACE PACKAGE BODY pkg IS
  FUNCTION tfunc RETURN INT AS
  BEGIN
    raise info 'current array values of var x: %', x;
    x[1] := x[1] + 1;
	x[4] := x[4] + 1;
    RETURN x[1] + x[4];
  END;
END;
/

select pkg.tfunc;
select pkg.tfunc;
DROP PACKAGE pkg;

--
-- support calling package functions without schema qualification
-- for package created in pg_catalog
--
create or replace package pg_catalog.pkg
is
	function f return int;
end;
/

create or replace package body pg_catalog.pkg
is
	function f return int
	is
	begin
		return 10;
	end;
end;
/

select pkg.f();
select pg_catalog.pkg.f();
drop package pg_catalog.pkg;
