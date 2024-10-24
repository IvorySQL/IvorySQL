--test ok
--create a event trigger,package support event trigger
--test ok
create table test_object(event varchar(256), tag varchar(256));

create function test_event_trigger_f() returns event_trigger as $$
BEGIN
    insert into test_object values(tg_event, tg_tag);
END
$$ language plisql;
/

--test sys.standard package
CREATE OR REPLACE package sys.standard IS
BINARY_FLOAT_NAN constant BINARY_FLOAT;
  BINARY_FLOAT_INFINITY constant BINARY_FLOAT;
  BINARY_FLOAT_MAX_NORMAL constant BINARY_FLOAT;
  BINARY_FLOAT_MIN_NORMAL constant BINARY_FLOAT;
  BINARY_FLOAT_MAX_SUBNORMAL constant BINARY_FLOAT;
  BINARY_FLOAT_MIN_SUBNORMAL constant BINARY_FLOAT;
  BINARY_DOUBLE_NAN constant BINARY_DOUBLE;
  BINARY_DOUBLE_INFINITY constant BINARY_DOUBLE;
  BINARY_DOUBLE_MAX_NORMAL constant BINARY_DOUBLE;
  BINARY_DOUBLE_MIN_NORMAL constant BINARY_DOUBLE;
  BINARY_DOUBLE_MAX_SUBNORMAL constant BINARY_DOUBLE;
  BINARY_DOUBLE_MIN_SUBNORMAL constant BINARY_DOUBLE;
end;
/

GRANT EXECUTE ON package sys.standard TO public;

--ok
create or replace package test_pkg is
  var1 integer;
  function test_f(id integer) return integer;
  procedure test_p(id integer);
end;
/

--raise error for subprogram or cursor not define
create or replace package body test_pkg is
  function test_f(id integer) return integer is
  begin
    return 23;
  end;
begin
  var1 := 23;
end;
/

--raise error for A subprogram body  xxx
create or replace package body test_pkg is
  function test_d(id integer) return integer;
  function test_f(id integer) return integer is
  begin
    return 23;
  end;
  procedure test_p(id integer) is
    var1 integer;
  begin
    var1 := test_f(23);
  end;
begin
  var1 := 23;
end;
/

--raise error for A subprogram body must xxx
create or replace package body test_pkg is
  function "Test_d"(id integer) return integer;
  function test_f(id integer) return integer is
  begin
    return 23;
  end;
  procedure test_p(id integer) is
    var1 integer;
  begin
    var1 := test_f(23);
  end;
begin
  var1 := 23;
end;
/


--raise error for A subprogram body must xxx
create or replace package body test_pkg is
  function test_f(id integer) return integer is
    var1 integer;
    function test_f1(id integer) return integer;
  begin
    return 23;
  end;
  procedure test_p(id integer) is
    var1 integer;
  begin
    var1 := test_f(23);
  end;
begin
  var1 := 23;
end;
/

DROP package test_pkg;

--test ok
create event trigger regress_event_trigger_end on ddl_command_end
   execute procedure test_event_trigger_f();

--use table to replace user defined record type
CREATE TABLE mds(id integer,name varchar(23));

--test ok
create or replace package pkg as
gvar mds%rowtype;
function test(id integer) return integer;
function test(id integer,name varchar) return integer;
end pkg;
/

--test ok
create or replace package public.pkg as
gvar mds%rowtype;
function test(id integer) return integer;
function test(id varchar) return varchar;
function test(id integer,name varchar) return integer;
end;
/
--test ok
create or replace package body pkg as
 function test(id integer) return integer is
 var1 integer;
 begin
    var1 := id;
    return var1 + 1;
  end;
  function test(id varchar) return varchar is
    var1 varchar(23);
   begin
      var1 := 'welcome to test';
      return var1;
   end;
  function test(id integer,name varchar) return integer is
  var1 integer;
  name1 varchar(25);
  begin
       var1 := id + 1;
       name1 := 'xiexie';
       return 23;
   end;
end pkg;
/

--test ok
create or replace package body pkg as
 function test(id integer) return integer is
 var1 integer;
 begin
    var1 := id;
    return var1 + 1;
  end;
  function test(id integer,name varchar) return integer is
  var1 integer;
  name1 varchar(25);
  begin
       var1 := id + 1;
       name1 := 'xiexie';
       return 23;
  end;
  function test(id varchar) return varchar is
    var1 integer;
  begin
     var1 := 23;
     return id;
  end;
end;
/
--test ok
create or replace package body pkg as
 function test(id integer) return integer is
 var1 integer;
 begin
    var1 := id;
    raise info 'gvar=%', gvar;
    gvar.id := gvar.id + 1;
    gvar.name := 'welcome';
    return var1 + 1;
  end;
  function test(id integer,name varchar) return integer is
  var1 integer;
  name1 varchar(25);
  begin
       var1 := id + 1;
       name1 := 'xiexie';
       return 23;
   end;
   function test(id varchar) return varchar is
   var1 integer;
   begin
        var1 := 23;
	return id;
   end;
   begin
        gvar.id := 23;
	gvar.name := 'global init block';
	raise info 'package init block %', gvar;
   end;
/

select *from pkg.test(23);

declare
 var integer;
begin
  raise info '%', pkg.gvar;
  pkg.gvar.id := 1;
  pkg.gvar.name := 'package var change';
  raise info 'pkg.gvar=%', pkg.gvar;
end;
/

declare
  var mds%rowtype;
begin
  var.name := 'welcome to beijing';
  raise info '%', var;
end;
/

--ok
declare
 var1 mds%rowtype;
 var2 mds%rowtype;
 var3 mds%rowtype;
 name varchar(256);
 function test_package(ids IN  mds%rowtype, ids1 mds%rowtype,name1  varchar) return mds%rowtype is
   var1 mds%rowtype;
 begin
     ids.id := ids1.id + 1;
     ids.name := ids1.name;
     name1 := 'wel come to pkgtype';
     var1.id := 1;
     var1.name := 'a return pkg type';
     return var1;
 end;
begin
 var1.id := pkg.gvar.id;
 var1.name := pkg.gvar.name;
 raise info 'var1=%', var1;
 var3.id := 0;
 var3.name := 'a in package type';
 var1 := test_package(var2, var3, name);
 raise info 'var1=%',var1;
 raise info 'var2=%', var2;
 raise info 'var3=%', var3;
 raise info 'name=%', name;
end;
/


declare
 var1 mds%rowtype;
begin
 var1.id := pkg.gvar.id;
 var1.name := pkg.gvar.name;
 raise info 'var1=%', var1;
end;
/

--test call package function
declare
  var1 integer;
 begin
   var1 := pkg.test(23);
   pkg.gvar.id := 123;
   pkg.gvar.name := 'must print me';
   var1 := pkg.test(24);
   var1 := pkg.test(23,'welcome to beijing');
 end;
 /

declare
 var1 pkg.gvar%type;
 var2 pkg.gvar.name%type;
begin
  var1.id := 23;
  var2 := 'a pkg type of type';
  var1.name := var2;
  raise info 'var1=%', var1;
end;
/

--test function rely on package
create or replace function test_package(id integer) return integer is
 var1 mds%rowtype;
 var2 integer;
begin
  var1 := pkg.gvar;
  var2 := pkg.test(23);
  pkg.gvar.id := var1.id + 1;
  raise info 'var1=%', var1;
  return var2;
end;
/

--test ok
select * from test_package(23);
SELECT test_package(23) FROM dual;

drop package pkg;

--test failed
SELECT test_package(23) FROM dual;

create or replace package public.pkg as
gvar mds%rowtype;
function test(id integer) return integer;
function test(id varchar) return varchar;
function test(id integer,name varchar) return integer;
end;
/
--test ok
create or replace package body pkg as
 function test(id integer) return integer is
 var1 integer;
 begin
    var1 := id;
    return var1 + 1;
  end;
  function test(id varchar) return varchar is
    var1 varchar(23);
   begin
      var1 := 'welcome to test';
      return var1;
   end;
  function test(id integer,name varchar) return integer is
  var1 integer;
  name1 varchar(25);
  begin
       var1 := id + 1;
       name1 := 'xiexie';
       return 23;
   end;
end pkg;
/

--test ok
select test_package(23) FROM dual;

drop function test_package(integer);

--test create package proper
--test ok
create or replace editionable package pkg_no1 authid definer accessible by (function kds, package mds)
is
  var1 integer;
  function test_mds(id integer) return integer;
end pkg_no1;
/

--test ok
create or replace editionable package body pkg_no1
is
    var11 integer;
    function test_mds(id integer) return integer is
     var1 integer;
     begin
         var1 := id;
	 return var1;
     end;
 end;
 /

--test failed
create or replace noneditionable package body pkg_no1
is
    var11 integer;
    function test_mds(id integer) return integer is
     var1 integer;
     begin
         var1 := id;
	 return var1;
     end;
 end;
 /

--test failed
create or replace noneditionable package pkg_no1 authid definer accessible by (function kds, package mds)
is
  var1 integer;
  function test_mds(id integer) return integer;
end pkg_no1;
/

--test ok
create or replace package pkg_no1 authid definer accessible by (function kds, package mds)
is
  var1 integer;
  function test_mds(id integer) return integer;
end pkg_no1;
/

--test ok
create or replace editionable package pkg_no1 authid definer accessible by (function kds, package mds)
is
  var1 integer;
  function test_mds(id integer) return integer;
end pkg_no1;
/

--test ok
alter package pkg_no1 noneditionable;

--test failed
create or replace package pkg_no1 authid definer accessible by (function kds, package mds)
is
  var1 integer;
  function test_mds(id integer) return integer;
end pkg_no1;
/

--test ok
create or replace noneditionable package body pkg_no1
is
    var11 integer;
    function test_mds(id integer) return integer is
     var1 integer;
     begin
         var1 := id;
	 return var1;
     end;
 end;
 /

--test drop package body ok
drop package body pkg_no1;

--test drop package
drop package pkg_no1;

--test ok
create or replace package pkg_no1 authid current_user accessible by (function kds, package mds)
is
  var1 integer;
  function test_mds(id integer) return integer;
end pkg_no1;
/

--test ok
create or replace package pkg_no1 authid current_user accessible by (function kds, package mds)
is
  var1 integer;
  function test_mds(id integer) return integer;
end pkg_no1;
/

--failed
CREATE USER test_user;

alter package pkg_no1 owner to test_user;

\dk+ pkg_no1

--test ok
create or replace package pkg_no1 authid definer accessible by (function kds, package mds)
is
  var1 integer;
  function test_mds(id integer) return integer;
end pkg_no1;
/

\dk+ pkg_no1


--test failed
create or replace noneditionable package body pkg_no1 is
  function test_mds(id integer) return integer
  is
    var1 integer;
  begin
     var1 := id;
     return var1;
  end;
end;
/

--test failed
create or replace noneditionable package pkg_no1 authid definer accessible by (function kds, package mds)
is
  var1 integer;
  function test_mds(id integer) return integer;
end pkg_no1;
/

--test ok
create or replace package body pkg_no1 is
  function test_mds(id integer) return integer
  is
    var1 integer;
  begin
     var1 := id;
     return var1;
  end;
end;
/

--test ok
create or replace package body pkg_no1 is
  function test_mds(id integer) return integer
  is
    var1 integer;
  begin
     var1 := id;
     return var1;
  end;
end;
/

--test drop package
drop package pkg_no1;

--test faield
drop package body pkg_no1;

--ok
DROP USER test_user;

---test rename stmt
--test ok
alter package pkg rename to pkg1;

--test failed
alter package pkg rename to pkg2;

--test comment
--test ok
comment on package pkg1 is 'a first package comment';

--test failed
comment on package body pkg1 is 'a first package body comment';

--test failed
comment on package body pkg2 is 'a error package body comment';

--test ownerstmt
create user dwdai1;
create user dwdai2;

--test ok
alter package pkg1 owner to dwdai1;

--test ok
alter package pkg1 owner to dwdai2;

--test set schema stmt
create schema schema_test1;

--test ok
alter package pkg1 set schema schema_test1;

--test failed
alter package pkg1 set schema public;

--test ok
alter package schema_test1.pkg1 set schema public;

--test drop
--test ok
drop package if exists pkg2;

--test ok
drop package body if exists pkg2;

drop package pkg1;

--test interval
create or replace package pkg as
gvar mds%rowtype;
function test(id interval year to month) return integer;
function test(id interval day to second) return integer;
function tests(id interval year to month) return integer;
end;
/

create or replace package body pkg as
   function test(id interval year to month) return integer is
    var1 integer;
   begin
      raise info 'a interval year to month function';
      var1 := 23;
      return var1;
   end;
   function test(id interval day to second) return integer is
    var1 integer;
   begin
      raise info 'a interval day to second function';
      var1 := 23;
      return var1;
   end;
   function tests(id interval year to month) return integer is
      var1 integer;
   begin
      raise info 'a tests function for interval year to month';
      var1 := 23;
      return var1;
    end;
end;
/

declare
  var1 interval year to month;
  var2 interval day to second;
  var3 integer;
begin
   var3 := pkg.test(var1);
   var3 := pkg.test(var2);
end;
/

--test failed
declare
  var1 interval year to month;
  var2 interval day to second;
  var3 integer;
begin
  var3 := pkg.tests(var1);
  var3 := pkg.tests(var2);
end;
/

drop package pkg;

--test package ref cursor and explicit cursor %rowtype
insert into mds values(1,'welcome to beijing');

create or replace package pkg as
   c1 CURSOR is select * from mds;
   test_var1 mds%rowtype;
   test_var2 mds%rowtype;
   function test(id integer) return integer;
end;
/

create or replace package body pkg as
 function test(id integer) return integer is
  var1 integer;
 begin
   var1 := 25;
   raise info 'test_var1=%', test_var1;
   raise info 'test_var2=%', test_var2;
   return var1;
 end;
end;
/

declare
  var1 integer;
  r mds%rowtype;
 begin
   pkg.test_var1.name := 'a test_var1';
   pkg.test_var2.id := 23;

   open pkg.c1;
   fetch pkg.c1 into r;
   raise info 'r=%', r;
   close pkg.c1;
   var1 := pkg.test(23);
end;
/

drop package pkg;

--test package body has init block
create or replace package pkg as
   c1 cursor is select * from mds;
   test_var1 mds%rowtype;
   test_var2 mds%rowtype;
   function test(id integer) return integer;
end;
/

create or replace package body pkg as
 function test(id integer) return integer is
  var1 integer;
 begin
   var1 := 25;
   raise info 'test_var1=%', test_var1;
   raise info 'test_var2=%', test_var2;
   return var1;
 end;
begin
   test_var1.id := 23;
end;
/

insert into mds values(2,'welcome to beijing');
declare
  var1 integer;
  r mds%rowtype;
 begin
   pkg.test_var1.name := 'a test_var1';
   pkg.test_var2.id := 23;

   open pkg.c1;
   LOOP
	fetch pkg.c1 into r;
	exit when NOT FOUND;
	raise info 'r=%', r;
   end loop;

   close pkg.c1;
   var1 := pkg.test(23);
end;
/

drop package pkg;

--test failed package include function define
create or replace package pkg as
 var1 integer;
 function test_id(id integer) return integer is
 var1 integer;
 begin
   var1:= 23;
   return var1;
 end;
end;
/

--test faild package has ref cursor variable
create or replace package pkg is
 var1 refcursor;
end;
/

--test sucess
create or replace package pkg is
 function test(id integer) return integer;
end;
/

--test failed
create or replace package body pkg is
  var2 refcursor;
  function test(id integer) return integer is
    var3 refcursor;
  begin
     open var3 for select 1 from dual;
     close var3;
     return 2;
  end;
end;
/

--test sucess
create or replace package body pkg is
  var2 integer;
  function test(id integer) return integer is
    var3 refcursor;
  begin
     open var3 for select 1 from dual;
     close var3;
     return 2;
  end;
end;
/

drop package pkg;

--test pg cursor
insert into mds values(1,'xiexie');
insert into mds values(2,'welcome to be');
insert into mds values(3,'welcome to hunan');

create or replace package pkg is
 c1 cursor is select * from mds;
 PROCEDURE test_open;
 PROCEDURE test_fetch;
 PROCEDURE test_close;
end;
/

create or replace package body pkg is
 c2 cursor is select * from mds;
 var2 mds%rowtype;
 PROCEDURE test_open is
 begin
     open c2;
 END test_open;
 PROCEDURE test_fetch IS
 BEGIN
    FETCH c2 INTO var2;
	raise info 'var2 = %', var2;
 END test_fetch;
 PROCEDURE test_close IS
 BEGIN
   CLOSE c2;
 END test_close;
end;
/

declare
 r mds%rowtype;
 ret integer;
begin
  open pkg.c1;
  fetch pkg.c1 into r;
  raise info '%',r.name;
  call pkg.test_open();
  call pkg.test_fetch();
  call pkg.test_close();
end;
/

declare
 r mds%rowtype;
 ret integer;
begin
  fetch pkg.c1 into r;
  raise info '%',r.name;
   call pkg.test_open();
end;
/

declare
 r mds%rowtype;
 ret integer;
begin
  fetch pkg.c1 into r;
  raise info '%',r.name;
  call pkg.test_fetch();
end;
/

declare
 r mds%rowtype;
 ret integer;
begin
  fetch pkg.c1 into r;
  raise info '%',r.name;
  call pkg.test_close();
end;
/

--raise error
declare
 r mds%rowtype;
 ret integer;
begin
  fetch pkg.c1 into r;
  raise info '%',r.name;
  call pkg.test_close();
  --raise syntax error
  fetchs pkg.c2 INTO r;
end;
/

drop package pkg;

--test replace src doesn't change
--test ok
create or replace package pkg is
var1  integer;
function set(id varchar) return integer;
end;
/

--test ok
create or replace package body pkg is
var2 varchar2(256);
function set(id varchar) return integer is
begin
   raise info 'var2=%',var2;
   var2 := id;
   return 0;
end;
begin
  raise info 'init block';
end;
/

--set variable
declare
 ret integer;
begin
 pkg.var1 := 23;
 ret := pkg.set('welcome');
end;
/
--
declare
  ret integer;
begin
  ret := pkg.set('to beijing');
  raise info 'pkg.var1=%', pkg.var1;
end;
/

--create or replace package specification doesn't change
create or replace package pkg is
var1  integer;
function set(id varchar) return integer;
end;
/

--print 'to beijing' and 23
declare
  ret integer;
begin
  ret := pkg.set('print to beijing');
  raise info 'pkg.var1=%', pkg.var1;
end;
/

begin
  pkg.var1 := pkg.var1 + 1;
end;
/

--create or replace package body
create or replace package body pkg is
var2 varchar2(256);
function set(id varchar) return integer is
begin
   raise info 'var2=%',var2;
   var2 := id;
   return 0;
end;
begin
  raise info 'init block';
end;
/

--print 'print to beijing' and 24
declare
  ret integer;
begin
  ret := pkg.set('print to beijing');
  raise info 'pkg.var1=%', pkg.var1;
end;
/

drop package pkg;

DROP TABLE mds;

--test after replace package cursor has open
create table mds(id integer,name varchar(23));
insert into mds values(1,'xiexie');
insert into mds values(2,'welcome');


Create or replace package pkg is
  c1 cursor is select * from mds;
End;
/

declare
  var1 mds%rowtype;
begin
  open pkg.c1;
  fetch pkg.c1 into var1;
  raise info '%',var1.name;
end;
/

--recreate package
Create or replace package pkg is
  c1 cursor is select * from mds;
  var1 integer;
End;
/

--report cursor is not open
declare
  var1 mds%rowtype;
begin
  fetch pkg.c1 into var1;
  raise info '%',var1.name;
exception
  WHEN others THEN
     raise info 'cursor not open';
end;
/

drop package pkg;

--test recreate package and remove variable which body referencing
create or replace package pkg is
var1 integer;
var2 integer;
end;
/

create or replace package body pkg is
begin
  var2 := 23;
  raise info '%','init block';
end;
/

--recreate package
create or replace package pkg is
var1 integer;
end;
/

--access and report error
begin
 pkg.var1 := 23;
end;
/

--drop
drop package pkg;

--test function return package'datum
create or replace package pkg is
var1 varchar(256);
var2 mds%rowtype;
end;
/

create or replace package body pkg is
begin
  var2.id := 1;
  var2.name := 'welcome to tuple';
  var1 := 'return a pkg datum';
  raise info 'init block';
end;
/

--create function
create or replace function test_pa(id integer) return varchar is
var2 mds%rowtype;
function test_pa1(id integer) return mds%rowtype is
begin
  return pkg.var2;
end;
begin
  var2 := test_pa1(23);
  raise info 'var2=%',var2;
  return pkg.var1;
end;
/

--access and print init block and pkg.var2 and return a pkg datum
declare
 ret varchar(256);
begin
  ret := test_pa(23);
  raise info 'ret=%', ret;
end;
/

drop function test_pa(integer);
drop package pkg;

---test package install
---1 instation
---1.1 reinstall package specification
 ---1.1.1 no body
 --test ok
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/
--access
--print 23 and null
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assing
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--recreate
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
var4 constant integer := 2;
end;
/

--print null
begin
 raise info '%', pkg.var3;
end;
/

--create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/
--print 23 and null
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--change constant value
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 26;
var3 integer;
end;
/

--print null
begin
 raise info '%',pkg.var3;
end;
/

--recreate
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

--access print 23 and null
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--re create and don't change
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

--print 25
begin
 raise info '%',pkg.var3;
end;
/

--re create by changing capital
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 INTEGER;
end;
/

--print null
begin
 raise info '%',pkg.var3;
end;
/

--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

--print 23 and null
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/
--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--re create and change 24 to 22 + 2
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 22+2;
var3 integer;
end;
/

--print null
begin
 raise info '%',pkg.var3;
end;
/

create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/
--print 23 and null
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 22+2;
var3 integer;
var4 constant integer := 4;
end;
/

--print null
begin
 raise info '%',pkg.var3;
end;
/

create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

--print 23 and null
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

create or replace package pkg is
var4 constant integer := 4;
var1 constant integer := 23;
var2 constant integer := 22+2;
var3 integer;
end;
/

--print null
begin
 raise info '%',pkg.var3;
end;
/

--1.1.2 has body
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info 'init block';
end;
/

--print 23 init block and 3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
var4 constant integer := 2;
end;
/

--print init block and 3
begin
 raise info '%',pkg.var3;
end;
/

--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info 'init block';
end;
/

--print 23 init block and 3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 26;
var3 integer;
end;
/

--print init block and 3
begin
 raise info '%',pkg.var3;
end;
/

--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info 'init block';
end;
/


--print 23, init block and 3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--re create and doesn't change
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

--print 25
begin
 raise info '%',pkg.var3;
end;
/

--re create and integer change to INTEGER
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 INTEGER;
end;
/

--print init block and 3
begin
 raise info '%',pkg.var3;
end;
/

--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info '%','init block';
end;
/

Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--re create and change 24 to 22 + 2
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 22+2;
var3 integer;
end;
/

--print init block and 3
begin
 raise info '%',pkg.var3;
end;
/


--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info 'init block';
end;
/

--print 23 and init block,3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--re create and add constand at tail
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 22+2;
var3 integer;
var4 constant integer := 4;
end;
/

--print init block and 3
begin
 raise info '%',pkg.var3;
end;
/

--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info 'init block';
end;
/

--print 23,init block and 3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--re create and add constand at head
create or replace package pkg is
var4 constant integer := 4;
var1 constant integer := 23;
var2 constant integer := 22+2;
var3 integer;
end;
/

--print init block and 3
begin
 raise info '%',pkg.var3;
end;
/


--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info '%','init block';
end;
/

--print 23
Declare
  Var1 mds%rowtype;
Begin
  Var1.id := 1;
  raise info '%',pkg.var1;
End;
/

--print 23,init block and 3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24 + 2;
end;
/

create or replace package body pkg is
begin
   raise info 'init block';
end;
/

--print 26 but oracle will init package status
Begin
 raise info '%',pkg.var2;
End;
/

--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info '%','init block';
end;
/

--print 23,init block, 3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/


--create function
create or replace function kds(id integer) return integer is
begin
  raise info '%', pkg.var3;
  return 0;
end;
/

--re create and add access
create or replace package pkg accessible by (function kds, package mds) is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

--print init block and 3
Declare
 Ret integer;
begin
 ret := kds(23);
end;
/

drop function kds(integer);


--1.2 test re create package body
--recreate
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info '%','init block';
end;
/

--print 23,init block,3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/


--re create body add constant
create or replace package body pkg is
 var4 constant integer := 4;
begin
   var3 := 3;
   raise info '%','init block';
end;
/

--print init block and 3
begin
 raise info '%',pkg.var3;
end;
/

--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info '%','init block';
end;
/

--print 23,init block and 3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--test assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--re create body and add raise info
create or replace package body pkg is
begin
   var3 := 3;
   raise info '%','init block';
   raise info '%','add output';
end;
/

--print init block,add output,3
begin
 raise info '%',pkg.var3;
end;
/

-- re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info '%','init block';
end;
/

--print 23,init block,3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

---test assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/


--re create body and don't change anything
create or replace package body pkg is
begin
   var3 := 3;
   raise info '%','init block';
end;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--re create package body and change capital
create or replace package body pkg is
begin
   var3 := 3;
   raise info '%','init Block';
end;
/

--print init block and 3
begin
 raise info '%',pkg.var3;
end;
/


--re create
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info '%','init block';
end;
/

--print 23,init block,3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/

--re create body and change 3 to 2 + 1
create or replace package body pkg is
begin
   var3 := 2+1;
   raise info '%','init block';
end;
/

--print init block and 3
begin
 raise info '%',pkg.var3;
end;
/

--recreate
create or replace package pkg is
var1 constant integer := 23;
var2 constant integer := 24;
var3 integer;
end;
/

create or replace package body pkg is
begin
   var3 := 3;
   raise info '%','init block';
end;
/

--print 23,init block and 3
Begin
 raise info '%',pkg.var1;
 raise info '%',pkg.var3;
End;
/

--assign
Begin
 Pkg.var3 := 25;
End;
/

--print 25
Begin
 raise info '%',pkg.var3;
end;
/


--test recreate body and add constat at tail
create or replace package body pkg is
var4 constant integer := 4;
begin
   var3 := 3;
   raise info '%','init block';
end;
/

--print init block and 3
begin
 raise info '%',pkg.var3;
end;
/

drop package pkg;

--test package references package
create or replace package pkg is
var1 mds%rowtype;
function test(id integer, var2 mds) return mds;
end;
/

create or replace package body pkg is
 function test(id integer, var2 mds%rowtype) return mds is
  var3 mds%rowtype;
 begin
   var2.id := 1;
   var2.name := 'a out name';
   var3.id := var2.id + 1;
   var3.name := var2.name || 'change';
   return var3;
 end;
end;
 /

create or replace package pkg1 is
 var1 mds%rowtype;
 var2 pkg.var1%type;
 function test(id integer, var3  mds%rowtype) return mds%rowtype;
end;
/

create or replace package body pkg1 is
  function test(id integer, var3  mds%rowtype) return mds%rowtype is
  var4 mds%rowtype;
  begin
    var3.id := 0;
    var3.name := 'a pkg1 name';
    var4.id := var3.id + 1;
    var4.name := var3.name || 'pkg1';
    return var4;
  end;
end;
/

--invok
declare
  var1 pkg1.var1%type;
  var2 pkg.var1%type;
  var3 pkg1.var2%type;
  var4 pkg.var1%rowtype;
begin
  var4 := pkg.test(23,var2);
  var3 := pkg1.test(23,var1);
  raise info 'var2=%,var4=%',var2,var4;
  raise info 'var1=%,var3=%',var1,var3;
end;
/

--again
declare
  var1 pkg1.var1%type;
  var2 pkg.var1%type;
  var3 pkg1.var2%type;
  var4 pkg.var1%rowtype;
begin
  var4 := pkg.test(23,var2);
  var3 := pkg1.test(23,var1);
  raise info 'var2=%,var4=%',var2,var4;
  raise info 'var1=%,var3=%',var1,var3;
end;
/

declare
  var1 pkg1.var1%type;
  var2 pkg.var1%type;
  var3 pkg1.var2%type;
  var4 pkg.var1%rowtype;
begin
  var4 := pkg1.var1;
  var3 := pkg.var1;
  raise info 'var2=%,var4=%',var2,var4;
  raise info 'var1=%,var3=%',var1,var3;
end;
/

--again
declare
  var1 pkg1.var1%type;
  var2 pkg.var1%type;
  var3 pkg1.var2%type;
  var4 pkg.var1%rowtype;
begin
  var4 := pkg1.var1;
  var3 := pkg.var1;
  raise info 'var2=%,var4=%',var2,var4;
  raise info 'var1=%,var3=%',var1,var3;
end;
/

--create a function rely on pkg1
create or replace function test_rely(id integer) return integer is
 var1 pkg1.var1%type;
begin
  var1.id := pkg1.var1.id;
  var1.name := 'a rely function';
  pkg1.var1.name := 'a change value';
  raise info 'pkg1.var1=%', pkg1.var1;
  return 23;
end;
/

--call function print (,"a change value")
select * from test_rely(23);
SELECT test_rely(23) FROM dual;


--test print (23,"a change value")
declare
  var1 integer;
begin
  pkg1.var1.id := 23;
  var1 := test_rely(23);
end;
/

--drop package pkg;
drop package pkg;

--call function and report error
select test_rely(23) FROM dual;

drop package pkg1;
drop function test_rely(integer);

--test body reference package variable and pkg.xx
create or replace package pkg is
var1 mds%rowtype;
function test(id integer) return integer;
function test(id varchar) return integer;
end;
/

create or replace package body pkg is
var4 pkg.var1%type;
function test(id integer) return integer is
var1 mds%rowtype;
begin
  pkg.var1.id := pkg.var1.id + 1;
  pkg.var1.name := pkg.var1.name || 'xiexie';
  var1.id := pkg.var1.id + 1;
  var1.name := 'welcome to beijing';
  raise info 'var1=%',var1;
  return 0;
end;
function test(id varchar) return integer is
var1 integer;
begin
   var1 := pkg.test(23);
    return pkg.var1.id;
end;
begin
  pkg.var1.id := 0;
  pkg.var1.name := 'init block';
  raise info 'init block';
end;
/

--print init block var1=(2,"welcome to beijing") pkg.var1=(1,"init blockxiexie")
declare
 ret integer;
begin
  ret := pkg.test('welcome');
  raise info 'pkg.var1=%',pkg.var1;
end;
/

--accesss block variable and report error
begin
 pkg.var4.id := 1;
end;
/

drop package pkg;

--clean data
drop event trigger regress_event_trigger_end;
drop function test_event_trigger_f();
drop table test_object;
drop schema schema_test1;
drop user dwdai1, dwdai2;


--test check create package lable
--test failed
create or replace package pkg_no1 as
 gvar mds%rowtype;
 function test(id integer) return integer;
 function test(id varchar) return varchar;
 function test(id integer,name varchar) return integer;
end pkg;
/

--test ok
create or replace package pkg_no1 as
 gvar mds%rowtype;
 function test(id integer) return integer;
 function test(id varchar) return varchar;
 function test(id integer,name varchar) return integer;
end pkg_no1;
/

--test failed
create or replace package body pkg_no1 as
 function test(id integer) return integer is
 var1 integer;
 begin
 var1 := id;
 return var1 + 1;
 end;
 function test(id varchar) return varchar is
 var1 varchar(23);
 begin
 var1 := 'welcome to test';
 return var1;
 end;
 function test(id integer,name varchar) return integer is
 var1 integer;
 name1 varchar(25);
 begin
 var1 := id + 1;
 name1 := 'xiexie';
 return 23;
 end;
 end pkg;
 /

 --test success
create or replace package body pkg_no1 as
 function test(id integer) return integer is
 var1 integer;
 begin
 var1 := id;
 return var1 + 1;
 end;
 function test(id varchar) return varchar is
 var1 varchar(23);
 begin
 var1 := 'welcome to test';
 return var1;
 end;
 function test(id integer,name varchar) return integer is
 var1 integer;
 name1 varchar(25);
 begin
 var1 := id + 1;
 name1 := 'xiexie';
 return 23;
 end;
 end pkg_no1;
 /

 --drop package
 drop package pkg_no1;

 --tes schema function argument and return type rely on package
 --create package and body
create or replace package pkg is
var1 mds%rowtype;
var2 mds%rowtype;
end;
/

create or replace package body pkg is
begin
   raise info 'init block';
end;
/

create or replace package pkg1 is
 var1 mds%rowtype;
end;
/

--create schema function which argument rely on package
create or replace function func_relay_pkg(id integer, pkg_type pkg.var1%type) return integer is
begin
  raise info '%',pkg_type.name;
  return 23;
end;
/

--reload failed
create function func_relay_pkg(id integer, pkg_type pkg1.var1%type) return integer is
begin
  raise info '%', pkg_type.name;
  return 23;
end;
/

--test ok
declare
 id integer;
 var1 pkg.var1%type;
begin
  var1.id := 23;
  var1.name := 'print me';
  id := func_relay_pkg(23, var1);
end;
/


CREATE TABLE mdss(id integer,name varchar2(256));

-- test failed
declare
  id integer;
  var1 mdss%rowtype;
begin
   var1.id := 23;
   var1.name := 'print me';
   id := func_relay_pkg(23, var1);
end;
/

--create schema function which return type is in package
create or replace function test_fun(id integer, name varchar) return pkg.var1%type is
 var1 pkg.var1%rowtype;
begin
  var1.id := 23;
  var1.name := 'return me';
  return var1;
end;
/

--test ok
declare
 var1 pkg.var1%type;
begin
  var1 := test_fun(23,'xiexie');
  raise info '%',var1.name;
end;
/

--create function use out
create or replace function test_out(id integer, tarray pkg.var1%type) return pkg.var1%type is
var1 mds%rowtype;
begin
  var1.id := 1;
  var1.name := 'xiexie';
  return var1;
end;
/

--test ok
declare
  var1 pkg.var1%type;
  var2 pkg.var1%type;
begin
  var1 := test_out(23, var2);
  raise info '%', var1.name;
  raise info '%',var2.name;
end;
/

drop package pkg;

--test failed
declare
 id integer;
 var1 mdss%rowtype;
begin
  var1.id := 23;
  var1.name := 'print me';
  id := func_relay_pkg(23, var1);
end;
/

--test failed
declare
 var1 mdss%rowtype;
begin
  var1 := test_fun(23,'xiexie');
  raise info '%',var1.name;
end;
/

--test failed
declare
  var1 integer;
  var2 varchar(256);
begin
  var1 := test_out(23, var2);
  raise info '%',var1;
  raise info '%',var2;
end;
/

--recoreate package
create or replace package pkg is
var1 mds%rowtype;
var2 mds%rowtype;
end;
/

--test ok
declare
 id integer;
 var1 pkg.var1%type;
begin
  var1.id := 23;
  var1.name := 'print me';
  id := func_relay_pkg(23, var1);
end;
/

--test ok
declare
 var1 pkg.var1%type;
begin
  var1 := test_fun(23,'xiexie');
  raise info '%',var1.name;
end;
/

--test ok
declare
  var1 pkg.var1%type;
  var2 pkg.var1%type;
begin
  var1 := test_out(23, var2);
  raise info '%',var1.name;
  raise info '%', var2.name;
end;
/

drop function test_out;

drop function test_fun(integer,varchar);
drop function func_relay_pkg;

drop package pkg;

--test %type
create or replace package pkg is
var1 mds%rowtype;
var2 integer;
end;
/

create or replace function test_type(id public.pkg.var2%type) return integer
is
begin
 return id;
end;
/

select test_type(23) from dual;

create or replace function test_return_type(id integer) return pkg.var2%type
is
begin
  return id;
end;
/

select test_return_type(23) from dual;

create or replace function test_return_record(ids integer) return pkg.var1%type
is
  id pkg.var1%type;
begin
  id.id := 2;
  id.name := 'welcome to beijing';
  return id;
end;
/

select test_return_record(23) from dual;

create or replace function test_return_record(ids integer) return pkg.var1%type
is
  id pkg.var1%type;
begin
  id.id := 2;
  id.name := 'welcome to beijing';
  return id;
end;
/

select test_return_record(23) from dual;

drop function test_return_record(integer);
drop function test_return_type(integer);
drop function test_type(integer);
drop package pkg;
drop package pkg1;


--test discard package
---create package pkg;
create or replace package pkg is
 var1 mds%rowtype;
 function test(id integer) return integer;
end;
/

create or replace package body pkg is
  function test(id integer) return integer is
  begin
   raise info 'pkg package func';
   return id;
  end;
begin
  raise info 'pkg init block';
end;
/

--create package pkg1
create or replace package pkg1 is
 var2 pkg.var1%type;
 function test(id integer) return integer;
end;
/

create or replace package body pkg1 is
 function test(id integer) return integer is
 begin
   raise info 'pkg1 package func';
   return id;
 end;
begin
  raise info 'pkg1 init blokc';
end;
/

--create function func
create or replace function func(id integer) return integer is
 var1 pkg.var1%type;
begin
  var1.id := pkg1.var2.id;
  return 23;
end;
/

begin
  pkg.var1.id := 1;
  pkg1.var2.id := 2;
  pkg.var1.id := func(23);
end;
/

discard package;

--test first reference pkg1
create or replace function func(id integer) return integer is
 var1 integer;
begin
  var1 := pkg1.var2.id;
  pkg1.var2.id := pkg.var1.id;
  return 23;
end;
/

begin
  pkg.var1.id := 1;
  pkg1.var2.id := 2;
  pkg.var1.id := func(23);
end;
/

discard all;

begin
  pkg.var1.id := 1;
  pkg1.var2.id := 2;
  pkg.var1.id := func(23);
end;
/

discard package;

--drop function and package;
drop package pkg;
drop package pkg1;
drop function func(integer);

--test drop package invert order
create or replace package pkg is
 var1 mds%rowtype;
 function test(id integer) return integer;
end;
/

create or replace package body pkg is
  function test(id integer) return integer is
  begin
   raise info 'pkg package func';
   return id;
  end;
begin
  raise info 'pkg init block';
end;
/

--create package pkg1
create or replace package pkg1 is
 var2 pkg.var1%type;
 function test(id integer) return integer;
end;
/

create or replace package body pkg1 is
 function test(id integer) return integer is
 begin
   raise info 'pkg1 package func';
   return id;
 end;
begin
  raise info 'pkg1 init blokc';
end;
/

--create function func
create or replace function func(id integer) return integer is
 var1 pkg.var1%rowtype;
begin
  var1.id := pkg1.var2.id;
  return 23;
end;
/

begin
  pkg.var1.id := 1;
  pkg1.var2.id := 2;
  pkg.var1.id := func(23);
end;
/

drop function func(integer);
drop package pkg1;
drop package pkg;

--test global var define after or before function define
--test ok
create or replace package pkg is
 var1 integer;
 function test(id integer) return integer;
end;
/

--test ok
create or replace package body pkg is
  var2 integer;
  function test(id integer) return integer is
  begin
    return id;
  end;
begin
  var2 := 23;
end;
/

--test failed global var after function define
create or replace package body pkg is
  function test(id integer) return integer is
  begin
    return id;
  end;
  var2 integer;
begin
  var2 := 23;
end;
/

--test ok
create or replace package body pkg is
  var2 integer;
  function test(id integer) return integer is
  begin
    return id;
  end;
  procedure test1(id integer);
  procedure test1(id integer) is
  begin
    var1 := 23;
  end;
begin
  var2 := 23;
end;
/

--test ok
create or replace package body pkg is
  var2 integer;
  function test(id integer) return integer is
  begin
    return id;
  end;
  procedure test1(id integer);
  procedure test1(id integer) is
  begin
    var1 := 23;
  end;
  function test2(id integer) return integer;
  function test2(id integer) return integer is
  begin
     return id;
  end;
begin
  var2 := 23;
end;
/

--test failed
create or replace package body pkg is
  var2 integer;
  function test(id integer) return integer is
  begin
    return id;
  end;
  procedure test1(id integer);
  procedure test1(id integer) is
  begin
    var1 := 23;
  end;
  function test2(id integer) return integer;
  function test2(id integer) return integer is
  begin
     return id;
  end;
  c1 cursor is select * from dual;
begin
  var2 := 23;
end;
/

--test ok
create or replace package pkg is
var1 integer;
procedure test();
end;
/

--test ok
create or replace package body pkg is
 var2 integer;
 procedure test() is
 begin
   raise info 'block';
 end;
end;
/

--test failed
create or replace package body pkg is
 procedure test() is
 begin
   raise info 'block';
 end;
 var2 integer;
end;
/

--test ok
create or replace package body pkg is
 procedure test() is
 begin
   raise info 'block';
 end;
end;
/

--clean data
drop package pkg;

--test
create table emp1(empno int,ename char(10),job char(20),mgr int,hiredate date,sal number,comm number,deptno int);
create or replace package pg_myfirst
is
procedure sp_emp_insert;
function f_getename(i_empno number) return varchar2;
function f_out(id integer, name varchar) return varchar;
procedure f1_out(id integer, name varchar);
function f2_out(id integer, var2 mds%rowtype) return mds%rowtype;
end pg_myfirst;
/

create or replace package body pg_myfirst
is
procedure sp_emp_insert
is
begin
insert into emp1(empno,ename,job,mgr,hiredate,sal,comm,deptno)
values(7384,'WangYi','SALESMAN',7698,to_date('2011-07-29','yyyy-mm-dd'),1250.00,1400.00,30);
end;
function f_getename(i_empno number)
return varchar2
is
v_ename varchar2(200);
begin
select ename into v_ename from emp1 where empno=i_empno;
return v_ename;
end;
function f_out(id integer, name varchar) return varchar is
begin
   name := 'xiexie';
   return 'welcome';
end;
procedure f1_out(id integer, name varchar) is
begin
  name := 'jsdfljsf';
end;
function f2_out(id integer, var2 mds%rowtype) return mds%rowtype is
  var1 mds%rowtype;
begin
  var2.id := 1;
  var2.name := 'out name';
  var1.id := 2;
  var1.name := 'return name';
  return var1;
end;
end pg_myfirst;
/

declare
  out_var varchar(256);
  ret_var varchar(256);
  ret_mds mds%rowtype;
  out_mds mds%rowtype;
begin
  ret_var := pg_myfirst.f_out(23,out_var);
  raise info 'ret_var=%, out_var=%', ret_var, out_var;
  ret_mds := pg_myfirst.f2_out(23, out_mds);
  raise info 'ret_mds=%, out_mds=%', ret_mds,out_mds;
end;
/

call pg_myfirst.sp_emp_insert();

select * FROM pg_myfirst.f_getename(7384);

select pg_myfirst.f_getename(7384) from dual;

select * from pg_myfirst.f_out(23,NULL);
select pg_myfirst.f_out(23,NULL) from dual;

call pg_myfirst.f1_out(23,NULL);
call pg_myfirst.f1_out(23,NULL);

select pg_myfirst.f2_out(23,NULL) FROM dual;
SELECT * FROM pg_myfirst.f2_out(23,NULL);

-- drop data
drop package pg_myfirst;
drop table emp1;

--test
create or replace package pkg is
function test(id integer) return integer;
var1 mds%rowtype;
end;
/

--test body failed
create or replace package body pkg is
  function test(id integer) return integer is
     i integer := 1;
  begin
     pkg.test.i := 1;
     raise notice '%',pkg.test.i;
     pkg.i := 1;
     raise notice '%',pkg.i;
    return 1;
  end;
end;
/

--failed
create or replace package body pkg is
   var2 pkg.var1%type;
   function test(id integer) return integer is
      i integer := 1;
   begin
      pkg.test.i := 1;
      raise notice '%',pkg.test.i;
      pkg.i := 1;
      raise notice '%',pkg.i;
     return 1;
   end;
end;
/

drop package pkg;

--test package references itself by package name
--test ok
create or replace package pkg is
function test(id integer) return integer;
var1 mds%rowtype;
var2 pkg.var1%type;
var3 pkg.var2%type;
end;
/

--test ok
create or replace package body pkg is
 var4 pkg.var1%type;
 function test(id integer) return integer is
 begin
   pkg.var2.id := 23;
   pkg.var2.name := 'a schema pkg test';
   raise info '%', pkg.var2.name;
   return 23;
 end;
begin
  var4.id := 1;
  var4.name := 'a package';
  var4.id := pkg.test(23);
end;
/


--print twice a schema pkg test
declare
  var1 integer;
begin
  var1 := public.pkg.test(23);
end;
/

--print a schema pkg test
declare
  var1 integer;
begin
  var1 := public.pkg.test(23);
end;
/

drop package public.pkg;

--test failed
create or replace package pkg is
function test(id integer) return integer;
var1 mds%rowtype;
var2 pkg.var1%type;
var3 pkg.var4%type;
end;
/

--test func.id as expression
--test ok
create or replace package pkg is
function test(id integer) return integer;
var1 varchar(20);
end;
/

create or replace package body pkg is
 function test(id integer) return integer is
   i int := 1;
 begin
    raise notice '%,%',test.id, test.i;
    return 1;
 end;
end;
/

declare
  var1 integer;
begin
  var1 := pkg.test(23);
end;
/

drop package pkg;

--test schema and package as the same name
create schema pkg;
set search_path to pkg;

CREATE TABLE mds(id integer, name varchar2(256));

create or replace package pkg is
 pkg1 mds%rowtype;
end;
/

create or replace package body pkg is
begin
  pkg.pkg1.id := 1;
  pkg.pkg1.name := 'init string';
  raise info 'init pkg.pkg';
end;
/

create or replace package pkg1 is
 var1 integer;
 function test(id integer) return integer;
end;
/

create or replace package body pkg1 is
 function test(id integer) return integer is
 begin
    return pkg.pkg1.id;
 end;
begin
  raise info 'init pkg.pkg1';
end;
/

--raise info init pkg.pkg1 init pkg.pkg and
-- print var1=1,pkg.pkg1.id=1
declare
  var1 integer;
begin
  var1 := pkg1.test(23);
  raise info 'var1=%,pkg.pkg1.id=%', var1, pkg.pkg1.id;
end;
/

--again
-- print var1=1,pkg.pkg1.id=1
declare
  var1 integer;
begin
  var1 := pkg1.test(23);
  raise info 'var1=%,pkg.pkg1.id=%', var1, pkg.pkg1.id;
end;
/

drop package pkg;
drop package pkg1;
DROP TABLE mds;
drop schema pkg;

--test
set search_path to public;
create table test1(id integer,name varchar(23));

create or replace package pkg is
  id integer;
  function test(id integer) return test1;
end;
/

create or replace package body pkg is
  function test(id integer) return test1 is
    var1 test1%rowtype;
  begin
    id := pkg.id;
    var1.id := pkg.id + 1;
    var1.name := 'xiexie';
    return var1;
end;
begin
  raise  info '%', 'init block';
end;
/

declare
  var1 mds%rowtype;
  var2 int;
  i int;
begin
    for i in 1 .. 10 LOOP
        pkg.id := i;
	var1 := pkg.test(var2);
	raise info 'var1=%,var2=%', var1,var2;
     end loop;
end;
/

drop package pkg;
drop table test1;


--test review rely on package
create or replace package pkg is
 var1 integer;
 function test(id integer) return integer;
end;
/

create or replace package body pkg is
  function test(id integer) return integer is
  begin
    return var1;
  end;
begin
  var1 := 23;
end;
/

--test ok
create or replace view test_view_p as select pkg.test(23) as id from dual;

--test ok
select * from test_view_p;

begin
 pkg.var1 := 26;
end;
/

--ok
select * from test_view_p;

--replace package
CREATE OR REPLACE package pkg IS
  var1 integer;
  FUNCTION test(id integer) RETURN varchar2;
end;
/

--raise error
SELECT * FROM test_view_p;

--replace package body
CREATE OR REPLACE package body pkg IS
  FUNCTION test(id integer) RETURN varchar2 IS
  BEGIN
   RETURN 'xiexie';
  end;
end;
/

--ok
SELECT * FROM test_view_p;


--test function argument and return rely
--on package
CREATE OR REPLACE FUNCTION test_f(id pkg.var1%type) RETURN pkg.var1%type
is
BEGIN
  RETURN id;
end;
/

--create a view rely on test_f
CREATE VIEW test_f_view_f AS SELECT test_f(23) FROM dual;

--ok
SELECT test_f(23) FROM dual;
SELECT * FROM test_f_view_f;

--replace package
CREATE OR REPLACE package pkg IS
  var1 varchar2(256);
  FUNCTION test(id integer) RETURN varchar2;
end;
/

--ok
SELECT test_f('xiexie') FROM dual;
SELECT * FROM test_f_view_f;

--replace
CREATE OR REPLACE package pkg IS
  var1 number;
  FUNCTION test(id integer) RETURN varchar2;
end;
/

--ok
SELECT test_f(1.45) FROM dual;
SELECT * FROM test_f_view_f;


--replace function arguments
CREATE OR REPLACE package pkg IS
  var1 integer;
  FUNCTION test(id varchar2) RETURN varchar2;
end;
/

CREATE OR REPLACE package body pkg IS
  FUNCTION test(id varchar2) RETURN varchar2 IS
  BEGIN
   RETURN id;
  end;
end;
/

--ok
SELECT * FROM test_view_p;

--clean data
DROP package pkg cascade;

--failed
SELECT test_f(1.45) FROM dual;
SELECT * FROM test_f_view_f;

--clean data
DROP VIEW test_f_view_f;
DROP FUNCTION test_f;

--package rowtype assign
CREATE OR REPLACE package test_pkg IS
  var1 mds%rowtype;
  FUNCTION test_f(id integer) RETURN integer;
end;
/

CREATE OR REPLACE package body test_pkg IS
  FUNCTION test_f(id integer) RETURN integer IS
  BEGIN
     RETURN var1.id;
  end;
end;
/

CREATE OR REPLACE package test_pkg1 IS
  var1 mds%rowtype;
  FUNCTION test_f(id integer) RETURN varchar2;
END test_pkg1;
/

CREATE OR REPLACE package body test_pkg1 IS
  FUNCTION test_f(id integer) RETURN varchar2 IS
  BEGIN
    RETURN var1.name;
  end;
end;
/

BEGIN
  test_pkg.var1.id := 1;
  test_pkg.var1.name := 'xiexie';
end;
/

BEGIN
  test_pkg1.var1 := test_pkg.var1;
end;
/

--print 'xiexie'
BEGIN
  raise info '%', test_pkg1.test_f(23);
end;
/

BEGIN
  test_pkg1.var1 := test_pkg.var1;
  test_pkg1.var1.id := 28;
  test_pkg.var1 := test_pkg1.var1;
end;
/

--print 28
BEGIN
  raise info '%',test_pkg.test_f(23);
end;
/

--clean data
DROP package test_pkg;
DROP package test_pkg1;


--test icase
create schema "PkgSchema";

create or replace package "PkgSchema"."Pkg" is
  var1 integer;
  function "Test_f"(id integer) return integer;
end;
/

create or replace package body "PkgSchema"."Pkg" is
  function "Test_f"(id integer) return integer is
  begin
    return id;
  end;
end;
/

create or replace function test_sn(id "PkgSchema"."Pkg".var1%type) return "PkgSchema"."Pkg".var1%type
is
begin
  return id;
end;
/

create view Test_Sn_View as select "PkgSchema"."Pkg"."Test_f"(23) from dual;

--ok
select * from Test_Sn_View;
SELECT test_sn(23) FROM dual;

DROP VIEW Test_Sn_View;
DROP function test_sn(id "PkgSchema"."Pkg".var1%type);
DROP package "PkgSchema"."Pkg";
DROP SCHEMA "PkgSchema";

--test view doesn't allow to pkg.var
create or replace package pkg is
 var1 integer;
 function test(id integer) return integer;
end;
/

create or replace package body pkg is
  function test(id integer) return integer is
  begin
    return var1;
  end;
begin
  var1 := 23;
end;
/

--test failed
create or replace view test_view_pvar as select pkg.var1 as id from dual;

--test failed
create or replace view test_view_p1 as select pkg.test(pkg.var1) as id from dual;

--test ok
drop package pkg cascade;

--test
create or replace package pkg is
 var1 integer;
end;
/

create or replace package body pkg is
begin
  raise info 'init block';
end;
/

--package variable as a param
declare
  procedure test(id integer) is
  begin
    raise info '%',id;
  end;
 begin
   call test(pkg.var1);
 end;
/

drop package pkg;

--test drop owned to
create user DWXIAO WITH PASSWORD '123456';

CREATE SCHEMA DWXIAO;

ALTER SCHEMA DWXIAO owner TO DWXIAO;

create or replace package DWXIAO.mds is
var1 integer;
end;
/

drop owned by DWXIAO cascade;

drop user DWXIAO;

--test
create table test_row(id integer,name varchar(23));

insert into test_row values(1,'xiexie');
create or replace package dwdai_pkg is
 procedure test(ids integer);
end;
/

create or replace package body dwdai_pkg is
  procedure test(ids integer) is
    str_outbound_dtl     test_row%rowtype;
     cur_outbound_dtl CURSOR(
	        is_id         test_row.id%type
		)    IS SELECT  * FROM test_row
			WHERE ids  = is_id;
    ln_outboundid test_row.id%type;
  begin
     ln_outboundid := 1;
     open cur_outbound_dtl(ln_outboundid);
     fetch cur_outbound_dtl into str_outbound_dtl;
     SELECT id INTO ln_outboundid FROM test_row WHERE id = str_outbound_dtl.id;
     close cur_outbound_dtl;
     insert into test_row(id, name) select str_outbound_dtl.id, str_outbound_dtl.name from dual;
 end;
end;
/

begin
  call dwdai_pkg.test(23);
end;
/

drop package dwdai_pkg;
drop table test_row;

create or replace package dwdai_pkg is
  var1 integer;
  function test(id integer,name varchar) return integer;
end;
/

create or replace package dwdai_pkg1 is
  var1 integer;
  function f1(id integer) return integer;
end;
/

create or replace package body dwdai_pkg is
  function test(id integer,name varchar) return integer is
    var1 integer;
  begin
     var1 := dwdai_pkg1.f1(23);
  end;
end;
/


create or replace package body dwdai_pkg1 is
  function f1(id integer) return integer is
    var1 integer;
  begin
     var1 := dwdai_pkg.test(23,'xiexie');
  end;
end;
/

drop package dwdai_pkg1;
drop package dwdai_pkg;

create or replace package dwdai_pkg is
  var1 integer;
  function test(id integer,name varchar) return integer;
end;
/

create or replace package dwdai_pkg1 is
  var1 integer;
  function f1(id integer) return integer;
end;
/

create or replace package body dwdai_pkg is
  function test(id integer,name varchar) return integer is
    var1 integer;
    var2 mds%rowtype;
  begin
     dwdai_pkg1.var1 := 23;
     var1 := 23;
  end;
end;
/


create or replace package body dwdai_pkg1 is
  function f1(id integer) return integer is
    var1 integer;
    var2 mds%rowtype;
  begin
     dwdai_pkg.var1 := 23;
     var1 := 23;
  end;
end;
/

declare
  var1 integer;
begin
  var1 := dwdai_pkg1.var1;
end;
/

drop package dwdai_pkg1;
drop package dwdai_pkg;

--test refernece its self
create or replace package dwdai_pkg IS
  var0 mds%rowtype;
  var1 integer;
  function test(id integer,name varchar) return integer;
  var2 public.dwdai_pkg.var0%type;
end;
/

create or replace package body dwdai_pkg is
  var3 public.dwdai_pkg.var2%type;
  function test(id integer,name varchar) return integer is
	var2 public.dwdai_pkg.var2%type;
  begin
      dwdai_pkg.var1 := 23;
      public.dwdai_pkg.var1 := 23;
      return 23;
  end;
end;
/

drop package dwdai_pkg;

--test
create table employees(id integer,name varchar(23));

create or replace package pkg is
  c1 CURSOR is select * from employees;
  procedure test(id integer);
end;
/


create or replace package body pkg is
 procedure test(id integer) is
 begin
   raise info 'xiexie';
 END test;
 END pkg;
 /

drop table employees;

call pkg.test(23);

create table employees(id integer,name varchar(23));

call pkg.test(23);

drop package pkg;
drop table employees;

--test
CREATE OR REPLACE PACKAGE DBMS_METADATA3 AUTHID DEFINER AS
	FUNCTION GET_DDL3(OBJTYPE VARCHAR2(63)) RETURN TEXT;
	FUNCTION GET_VIEW_DDL3(OBJTYPE VARCHAR2(63)) RETURN TEXT;
END;
/

CREATE OR REPLACE PACKAGE BODY DBMS_METADATA3 IS
	FUNCTION GET_DDL3(OBJTYPE VARCHAR2(63)) RETURN TEXT IS
		ddl TEXT;
	BEGIN
		ddl := DBMS_METADATA3.GET_VIEW_DDL3(OBJTYPE);
		RETURN ddl;
	END;

	FUNCTION GET_VIEW_DDL3(OBJTYPE VARCHAR2(63)) RETURN TEXT
	AS
	DECLARE
	BEGIN
		RETURN 'abc';
	END;
END;
/

DECLARE
	i text;
	j varchar2(63) := 'hello';
BEGIN
	i := DBMS_METADATA3.get_ddl3(j);
	raise notice '%',i;
END;
/

drop package DBMS_METADATA3;

--test
CREATE OR REPLACE PACKAGE DBMS_METADATA3 AUTHID DEFINER AS
	FUNCTION GET_DDL3(OBJTYPE VARCHAR2(63)) RETURN TEXT;
	FUNCTION GET_VIEW_DDL3(OBJTYPE VARCHAR2(63)) RETURN TEXT;
	FUNCTION GET_FUNC_DDL3(OBJTYPE VARCHAR2(63)) RETURN TEXT;
END;
/

CREATE OR REPLACE PACKAGE BODY DBMS_METADATA3 IS
	FUNCTION GET_DDL3(OBJTYPE VARCHAR2(63)) RETURN TEXT IS
		ddl TEXT;
	BEGIN
		ddl := DBMS_METADATA3.GET_FUNC_DDL3(OBJTYPE);
		RETURN ddl;
	END;

	FUNCTION GET_VIEW_DDL3(OBJTYPE VARCHAR2(63)) RETURN TEXT
	AS
	DECLARE
	BEGIN
		RETURN 'abc';
	END;

	FUNCTION GET_FUNC_DDL3(OBJTYPE VARCHAR2(63)) RETURN TEXT
	AS
	DECLARE
	BEGIN
		RETURN 'abc';
	END;
END;
/


DECLARE
	i text;
	j varchar2(63) := 'hello';
BEGIN
	i := DBMS_METADATA3.get_ddl3(j);
	raise notice '%',i;
END;
/

drop package DBMS_METADATA3;

--test
CREATE OR REPLACE PACKAGE DBMS_XMLGEN1 IS
	FUNCTION NEWCONTEXT (
	query IN VARCHAR2)
	RETURN NUMBER;
	FUNCTION NEWCONTEXT (
	queryString IN REFCURSOR)
	RETURN NUMBER;
end;
/

create or replace package body DBMS_XMLGEN1
is
	FUNCTION NEWCONTEXT (
	query IN VARCHAR2)
	RETURN NUMBER
	IS
	BEGIN
		RETURN 1;
	END;
	FUNCTION NEWCONTEXT (
	queryString IN REFCURSOR)
	RETURN NUMBER
	IS
	BEGIN
		RETURN 1;
	END;
end;
/

declare
 id integer;
begin
  id := DBMS_XMLGEN1.NEWCONTEXT('xiexie');
  raise info '%',id;
end;
/

drop package DBMS_XMLGEN1;

--test
create or replace package pkg_end as
gvar mds%rowtype;
function test(id integer) return integer;
function test(id varchar) return varchar;
function test(id integer,name varchar) return integer;
end;
/
--test ok
create or replace package body pkg_end as
 function test(id integer) return integer is
 var1 integer;
 begin
    var1 := id;
    return var1 + 1;
  end test;
  function test(id varchar) return varchar is
    var1 varchar(23);
   begin
      var1 := 'welcome to test';
      return var1;
   end test;
  function test(id integer,name varchar) return integer is
  PROCEDURE GET_YSBDS AS
  V_ITEMPSTR VARCHAR2(6000);
  BEGIN
	raise info 'hello on nest test';
  END GET_YSBDS;
  begin
    call GET_YSBDS();
    return 23;
  end test;
end pkg_end;
/

BEGIN
	raise info '%',pkg_end.test(1);
	raise info '%',pkg_end.test(1,'hello');
	raise info '%',pkg_end.test('hello');
END;
/
drop package pkg_end;

--test
create or replace package dwdai_pkg is
	function test(id integer) return integer;
end dwdai_pkg;
/

create or replace package body dwdai_pkg is
	var1 integer;
	function test(id integer) return integer is
	begin
		return 23;
	end test;
begin
	var1 := 2;
end dwdai_pkg;
/

declare
	id integer;
begin
	id := dwdai_pkg.test(23);
	raise info '%', id;
end;
/

create or replace package dwdai_pkg as
	function test(id integer) return integer;
end dwdai_pkg;
/

create or replace package body dwdai_pkg as
	function test(id integer) return integer is
		v_last_name  VARCHAR2(25);
		v_emp_id     NUMBER(6);
	begin
		v_emp_id := 2;
		IF v_emp_id > 0 THEN
			v_emp_id := v_emp_id - 1;
			raise notice '%',v_emp_id;
		END IF;
		return id;
	end;
end dwdai_pkg;
/

declare
	id integer;
begin
	id := dwdai_pkg.test(23);
	raise info '%', id;
end;
/

declare
	id integer;
	function test(id integer) return integer is
		v_last_name  VARCHAR2(25);
		v_emp_id     NUMBER(6);
	begin
		v_emp_id := 2;
		IF v_emp_id > 0 THEN
			v_emp_id := v_emp_id - 1;
			raise notice '%',v_emp_id;
		END IF;
		return id;
	end;
begin
	id := test(23);
end;
/

create or replace package pkg_end as
	gvar mds%rowtype;
	function test(id integer) return integer;
	function test(id varchar) return varchar;
	function test(id integer,name varchar) return integer;
end;
/

--test ok
create or replace package body pkg_end as
	function test(id integer) return integer is
		var1 integer;
	begin
		var1 := id;
		return var1 + 1;
	end test;
	function test(id varchar) return varchar is
		var1 varchar(23);
	begin
		var1 := 'welcome to test';
		return var1;
	end test;
	function test(id integer,name varchar) return integer is
		PROCEDURE GET_YSBDS AS
			V_ITEMPSTR VARCHAR2(6000);
		BEGIN
			raise info '%','hello on nest test';
		END GET_YSBDS;
	begin
		call GET_YSBDS();
		return 23;
	end test;
end pkg_end;
/

declare
	id integer;
begin
	id := pkg_end.test(23);
	raise info '%', id;
end;
/

create or replace package dwdai_pkg is
	procedure test(id integer);
	function test1(id integer) return integer;
	var1 mds%rowtype;
end;
/

create or replace package body dwdai_pkg is
	var2 mds%rowtype;
	procedure test(id integer) is
		procedure test_inline(id integer);
		procedure test_inline(id integer) is
		begin
			raise info '%', id;
		end;
		var3 integer;
	begin
		raise info '%', id;
	end;
	function func_test2(id integer) return integer is
		function test_inline2(id integer) return integer is
		begin
			return 24;
		end;
	begin
		return 23;
	end;
	function test1(id integer) return integer is
		procedure test22(id integer) is
		begin
			raise info '%', id;
		end;
	begin
		return 25;
	end;
begin
	var1.id := 23;
end;
/

begin
  call dwdai_pkg.test(23);
end;
/

CREATE OR REPLACE PACKAGE public.DBMS_ALERT AUTHID DEFINER AS
	PROCEDURE DEFERED_SIGNAL();
	PROCEDURE REGISTER(name IN text);
	PROCEDURE REMOVE(name IN text);
	PROCEDURE REMOVEALL();
	PROCEDURE SET_DEFAULTS(sensitivity IN float8);
	PROCEDURE SIGNAL(_event IN text, _message IN text);
	PROCEDURE WAITANY(name OUT text, message OUT text, status OUT integer, timeout IN float8);
	PROCEDURE WAITONE(name IN text, message OUT text, status OUT integer, timeout IN float8);
END;
/
create or replace package body public.DBMS_ALERT  IS
	PROCEDURE DEFERED_SIGNAL() is
	BEGIN
		call rp_defered_signal();
	END;

	PROCEDURE REGISTER(name IN text) is
	BEGIN
		call rp_register(name);
	END;

	PROCEDURE REMOVE(name IN text) is
	BEGIN
		call rp_remove(name);
	END;

	PROCEDURE REMOVEALL() IS
	BEGIN
		call rp_removeall();
	END;

	PROCEDURE SET_DEFAULTS(sensitivity IN float8) IS
	BEGIN
		call rp_set_defaults(sensitivity);
	END;

	PROCEDURE SIGNAL(_event IN text, _message IN text) IS
	BEGIN
		call rp_signal(_event, _message);
	END;

	PROCEDURE WAITANY(name OUT text, message OUT text, status OUT integer, timeout IN float8) IS
	  v record;
	BEGIN
		v = rp_waitany(timeout);
		name = v.name;
		message = v.message;
		status = v.status;
	END;

	PROCEDURE WAITONE(name IN text, message OUT text, status OUT integer, timeout IN float8) IS
	  v record;
	BEGIN
		v = rp_waitone(name, timeout);
		message = v.message;
		status = v.status;
	END;

BEGIN
	BEGIN
		DROP TABLE __rp_ora_alerts;
		EXCEPTION WHEN OTHERS THEN NULL;
	END;
	CREATE TEMP TABLE __rp_ora_alerts(event text, message text);
	REVOKE ALL ON TABLE __rp_ora_alerts FROM PUBLIC;
	CREATE CONSTRAINT TRIGGER __rp_ora_alert_signal AFTER INSERT ON __rp_ora_alerts INITIALLY DEFERRED FOR EACH ROW EXECUTE PROCEDURE rp_defered_signal();
END;
/

drop package public.DBMS_ALERT;
drop package dwdai_pkg;
drop package pkg_end;


--test
create schema test;

create or replace package test.pkg as
	var1 mds%rowtype;
	gvar int;
end pkg;
/

--test ok
create or replace package body test.pkg as
begin
	gvar := 1;
	var1.id := 23;
	var1.name := 'xiexie';
end;
/

declare
	var1 int;
	var2 test.pkg.var1%type;
	var3 varchar(25);
begin
	var1 := test.pkg.gvar;
	var2 := test.pkg.var1;
	raise info '%,%,%', var1,var2,var3;
end;
/

drop package test.pkg;
drop schema test;

--test
CREATE OR REPLACE PACKAGE pkg AS
    pvar mds%rowtype;
    FUNCTION rec_test(ivar pkg.pvar%TYPE) RETURN integer;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg AS
    FUNCTION rec_test(ivar pkg.pvar%TYPE) RETURN integer IS
        var1 pvar%TYPE;
    BEGIN
        var1.id := ivar.id + 1;
        var1.name := 'Bob#' || var1.id;
        pvar := var1;
        RETURN var1.id;
    END;
END;
/

DECLARE
    var1 pkg.pvar%TYPE;
BEGIN
    var1.id := 1;
    var1.name := 'Bob#' || var1.id;

    raise info '%', var1.id || '. ' || var1.name;
    raise info '%', pkg.rec_test(var1) || '. ' || pkg.pvar.name;
END;
/

CREATE OR REPLACE PACKAGE pkg AS
    pvar mds%rowtype;
    FUNCTION rec_test(ivar pkg.pvar%TYPE) RETURN integer;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg AS
    FUNCTION rec_test(ivar pkg.pvar%TYPE) RETURN integer IS
        var1 pvar%TYPE;
    BEGIN
        raise info '%', ivar.id || '. ' || ivar.name;
        var1.id := ivar.id + 1;
        var1.name := 'Bob#' || var1.id;
        pvar.id := var1.id;
        pvar.name := var1.name;
        --pvar := var1;
        RETURN var1.id;
    END;
END;
/

DECLARE
    var1 pkg.pvar%TYPE;
BEGIN
    var1.id := 1;
    var1.name := 'Bob#' || var1.id;

    raise info '%', pkg.rec_test(var1) || '. ' || pkg.pvar.name;
END;
/

CREATE OR REPLACE PACKAGE pkg AS
    pvar mds%rowtype;
    FUNCTION rec_test(ivar pkg.pvar%TYPE) RETURN integer;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg AS
    FUNCTION rec_test(ivar pkg.pvar%TYPE) RETURN integer IS
        var1 pvar%TYPE;
    BEGIN
        var1.id := ivar.id + 1;
        var1.name := 'Bob#' || var1.id;
        pvar := var1;
        RETURN var1.id;
    END;
END;
/

DECLARE
    var1 pkg.pvar%TYPE;
	var2 varchar2(256);
BEGIN
    var1.id := 1;
    var1.name := 'Bob#' || var1.id;

    raise info '%', var1.id || '. ' || var1.name;
	var2 := pkg.rec_test(var1)  || pkg.pvar.name;
    raise info '%', var2;
END;
/

CREATE OR REPLACE PACKAGE pkg AS
    pvar mds%rowtype;
    FUNCTION rec_test(ivar pkg.pvar%TYPE) RETURN integer;
	function rect_test1(id integer) return integer;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg AS
    FUNCTION rec_test(ivar pkg.pvar%TYPE) RETURN integer IS
        var1 pvar%TYPE;
    BEGIN
        var1.id := ivar.id + 1;
        var1.name := 'Bob#' || var1.id;
        pvar := var1;
        RETURN var1.id;
    END;
	function rect_test1(id integer) return integer is
	   var2 pvar%TYPE;
	begin
	   var2.id := 1;
	   var2.name := 'Bob#' || var2.id;
	   raise info '%', rec_test(var2) || '.' || pvar.name;
	   return 23;
	end;
END;
/

select pkg.rect_test1(23) from dual;

CREATE OR REPLACE PACKAGE pkg AS
	name varchar(23);
    FUNCTION rec_test(id integer) RETURN integer;
	function rect_test1(id integer) return integer;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg AS
    FUNCTION rec_test(id integer) RETURN integer IS
    BEGIN
		name := 'welcome';
        RETURN 1;
    END;
	function rect_test1(id integer) return integer is
	begin
	   raise info '%', rec_test(23) || '.' || name;
	   return 23;
	end;
END;
/


select pkg.rect_test1(23) from dual;

--inline function
declare
  name varchar(23);
  var1 integer;
  FUNCTION rec_test(id integer) RETURN integer IS
    BEGIN
		name := 'welcome';
        RETURN 1;
    END;
  function rect_test1(id integer) return integer is
    var2 varchar2(23);
  begin
       var2 := rec_test(23) || name;
	   raise info '%', var2;
	   return 23;
	end;
begin
  var1 := rect_test1(23);
end;
/

create table test1(id integer,name varchar2(23));

--oracle raise error, but we success
declare
  name varchar(23) :='1';
  var1 integer;
  FUNCTION rec_test(id integer) RETURN integer IS
    BEGIN
		name := 'welcome';
        RETURN 1;
    END;
  function rect_test1(id integer) return integer is
    var2 varchar2(23);
	var1 integer;
  begin
       --raise info '%', name;
	   insert into test1 values(rec_test(23), name);
	   name := '';
	   var1 := rec_test(23);
	   insert into test1 values(var1, name);
	   return 23;
	end;
begin
  var1 := rect_test1(23);
end;
/

select *from test1;

--clean data
drop package pkg;
drop table test1;


CREATE OR REPLACE PACKAGE test_pkg IS
  FUNCTION test_fds(id integer) RETURN integer;
  FUNCTION test_fds(id mds%rowtype) RETURN integer;
  PROCEDURE test_proc(id integer);
  var2 integer := 0;
  var4 CONSTANT integer := 23;
  var1 mds%rowtype;
END;
/

CREATE OR REPLACE PACKAGE BODY test_pkg IS
  var3 mds%rowtype;
  var5 integer := 23;

  FUNCTION test_fds(id integer) RETURN integer IS
  BEGIN
    var1.id := id +1;
    var1.name := 'test_fds integer';
    raise info 'invoke test_fds(integer)';
    RETURN 1;
  END;

  FUNCTION test_fds(id mds%rowtype) RETURN integer IS
  BEGIN
    var1.id := id.id;
    var1.name := id.name;
    raise info 'invoke test_fds(mds)';
    RETURN 2;
  END;

  PROCEDURE test_proc(id integer) IS
  BEGIN
    raise info 'invoke test_proc';
  END;

  PROCEDURE test_private(id integer) IS
  BEGIN
    var2 := id;
  END;

BEGIN
  call test_private(var5);
  raise info 'init package';
END;
/

declare
  id integer;
begin
  id := test_pkg.test_fds(23);
end;
/

declare
  var1 test_pkg.var1%type;
  var2 integer;
begin
  var1.id := 1;
  var1.name := 'ok';
end;
/

declare
  var1 test_pkg.var1%type;
begin
  test_pkg.var1.name := 'set a value';
  raise info '%', test_pkg.var1.name;
  var1.name := 'welcome to';
end;
/

declare
  var1 test_pkg.var1%type;
  var3 integer;
  var4 integer;
begin
  var1.id := 1;
  var1.name := 'one';
  var4 := test_pkg.test_fds(var1);
  var3 := 20;
  var4 := test_pkg.test_fds(var3);
end;
/

begin
  raise info '%', test_pkg.var1.name;
end;
/

begin
  raise info '%',test_pkg.var1.name;
end;
/

drop package test_pkg;

create or replace package test_pkg is
  var1 integer;
end;
/

create or replace package test_pkg1 is
  var1 test_pkg.var1%type;
end;
/

begin
  test_pkg1.var1 := 23;
end;
/

--print 23
begin
  raise info '%',test_pkg1.var1;
end;
/


--clean data
drop package test_pkg;
drop package test_pkg1;


create or replace package test_pkg is
   equip_categ_meter  constant varchar2(10) := '01';
   equip_categ_meter1 constant varchar2(10) := '02';
   equip_categ_meter2 constant varchar2(256) := test_pkg.equip_categ_meter || '$' || test_pkg.equip_categ_meter1;
end;
/

--ok
begin
  raise info '%',test_pkg.equip_categ_meter2;
end;
/

--ok
begin
  raise info '%',test_pkg.equip_categ_meter2;
end;
/

drop package test_pkg;

set check_function_bodies = off;

create or replace package test_pkg is
   equip_categ_meter  constant varchar2(10) := '01';
   equip_categ_meter1 constant varchar2(10) := '02';
   equip_categ_meter2 constant varchar2(256) := test_pkg.equip_categ_meter || '$' || test_pkg.equip_categ_meterx;
end;
/

--raise error
begin
  raise info '%', test_pkg.equip_categ_meter1;
end;
/

--again error
begin
  raise info '%', test_pkg.equip_categ_meter1;
end;
/

drop package test_pkg;

--function
create or replace function test_f(id integer) return integer is
  var1 integer := 23;
  var2 integer := test_f.var1;
begin
  raise info '%', var1;
  return 23;
end;
/

--ok
select test_f(23) from dual;

drop function test_f;

--
create or replace package pkg_992 is
  SESSION constant integer := 10;
  function test_f(id integer := pkg_992.SESSION) return integer;
end;
/

create or replace package body pkg_992 is
  function test_f(id integer := pkg_992.SESSION) return integer is
  begin
    return id;
  end;
end;
/
select pkg_992.test_f(23) from dual;
drop package pkg_992;

create or replace package pkg_992 is
  SESSION  integer := 0;
  function test_f(id integer := SESSION) return integer;
end;
/
create or replace package body pkg_992 is
  function test_f(id integer := pkg_992.SESSION) return integer is
  begin
    return id;
  end;
end;
/
select pkg_992.test_f(23) from dual;
drop package pkg_992;

create or replace package pkg_992 is
  SESSION constant integer := 10;
  function test_f(id integer := pkg_992.SESSION) return integer;
  function test_f2(id2 integer := pkg_992.SESSION) return integer;
end;
/

create or replace package body pkg_992 is
  function test_f(id integer := pkg_992.SESSION) return integer is
  begin
    return id;
  end;
  function test_f2(id2 integer := pkg_992.SESSION) return integer is
  begin
    return id2;
  end;
end;
/
select pkg_992.test_f2(23) from dual;
drop package pkg_992;

reset check_function_bodies;


--
create or replace package test_pkg is
  var1 integer;
  function test_f(id integer) return integer;
end;
/

create or replace package test_referce is
  var1 test_pkg.var1%type;
  var2 integer;
end;
/

create or replace package body test_pkg is
  function test_f(id integer) return integer is
    var2 test_referce.var2%type;
    var1 integer;
  begin
    return 23;
  end;
end;
/

--print 23
select test_pkg.test_f(23) from dual;


--discard package
discard package;

drop package test_pkg;
drop package test_referce;

create or replace package test_pkg is
  var1 integer;
  function test_f(id integer) return integer;
end;
/

create or replace package test_reference is
  var1 test_pkg.var1%type;
  function test_f(id integer) return integer;
end;
/

create or replace package body test_reference is
  function test_f(id integer) return integer is
    var1 integer;
  begin
    var1 := test_pkg.var1;
    return 23;
  end;
end;
/

--raise error
create or replace package body test_pkg is
 function test_f(id integer) return integer is
   var1 integer;
 begin
   var1 := substr('xiexie', test_reference.test_f(23));
   insert into testxx;
   return 23;
 end;
end;
/

--clean data
drop package test_pkg;
drop package test_reference;

--create user
create user test;
create user test1;
CREATE SCHEMA test1;
CREATE SCHEMA test;

ALTER SCHEMA test1 owner TO test1;
ALTER SCHEMA test owner TO test;

--set session
set session authorization test;

--create package
create or replace package test.test_pkg is
  var1 integer;
  function test_f(id integer) return integer;
end;
/

--create package body
create or replace package body test.test_pkg is
  function test_f(id integer) return integer is
     var1 integer;
  begin
     return 23;
  end;
end;
/

--set session
set session authorization test1;

--set session super user
reset session authorization;

--ok
drop package test.test_pkg;
DROP SCHEMA test;
drop user test;
DROP SCHEMA test1;
drop user test1;


--empty package
CREATE OR REPLACE PACKAGE pkg_ca_purp_card_jl IS
END pkg_ca_purp_card_jl;
/

--report error
CREATE OR REPLACE PACKAGE BODY pkg_ca_purp_card_jl IS
END pkg_ca_purp_card_j2;
/

--empty package body
CREATE OR REPLACE PACKAGE BODY pkg_ca_purp_card_jl IS
END pkg_ca_purp_card_jl;
/

CREATE OR REPLACE PACKAGE BODY pkg_ca_purp_card_jl IS
END;
/

CREATE OR REPLACE PACKAGE BODY pkg_ca_purp_card_jl IS
  var1 integer;
END pkg_ca_purp_card_jl;
/

drop package pkg_ca_purp_card_jl;


--
CREATE OR REPLACE PACKAGE "PKG_MP_CONSTANTS" IS
	meter_status_standard CONSTANT VARCHAR2(10) := '006';
END "PKG_MP_CONSTANTS";
/

CREATE OR REPLACE PACKAGE BODY "PKG_MP_CONSTANTS" IS
/********************************************************************
 #function:????????
 #version:1.01
 #author:??
 #createdate:2009-06-16
********************************************************************/

END "PKG_MP_CONSTANTS";
/

CREATE OR REPLACE PACKAGE BODY "PKG_MP_CONSTANTS" IS
END "PKG_MP_CONSTANTS";
/

begin
 raise info '%', "PKG_MP_CONSTANTS".meter_status_standard;
end;
/

drop package "PKG_MP_CONSTANTS";


CREATE OR REPLACE PACKAGE PKG1 AS
    PROCEDURE P1;
END;
/

CREATE OR REPLACE PACKAGE BODY PKG1 AS
    -- private variable
    pv int := 0;
    PROCEDURE P1 AS
    BEGIN
        PKG1.pv := 1;
    END;
BEGIN
    PKG1.pv := 2;
END;
/

CREATE OR REPLACE PACKAGE BODY PKG1 AS
    -- private variable
	pv int := 0;
    pv1 varchar2(23);
    PROCEDURE P1 AS
    BEGIN
        PKG1.pv :=  PKG1.pv + 1;
    END;
	function test_f(id integer) return integer is
	begin
	  return id + 1;
	end;
BEGIN
    PKG1.pv := 0;
	PKG1.pv1 := 'xiexie';
    call PKG1.p1();
	PKG1.pv := PKG1.test_f(PKG1.pv);
	raise info '%', PKG1.pv;
END;
/

begin
  call pkg1.p1();
end;
/

drop package pkg1;

--test pg array and object  type
create type complex1 as (r float8, i float8);
create type quadarray as (c1 complex1[], c2 complex1);

CREATE OR REPLACE package test_pkg IS
  var1 complex1;
  var2 text[];
  FUNCTION test_var2_id(i integer) RETURN TEXT;
  procedure test_assign_var1(id float8, id1 float8);
end;
/

CREATE OR REPLACE package body test_pkg IS
  FUNCTION test_var2_id(i integer) RETURN TEXT IS
  BEGIN
     RETURN var2[i];
  end;
  procedure test_assign_var1(id float8, id1 float8) IS
  BEGIN
     var1.r := id;
	 var1.i := id1;
  end;
BEGIN
  var1.r := 1.4;
  var1.i := 1.6;
  var2 := array['abc','def','hjk'];
end;
/

BEGIN
  raise info '%', test_pkg.test_var2_id(1);
end;
/

BEGIN
  raise info '%', test_pkg.var1;
  call test_pkg.test_assign_var1(0.1,0.2);
  raise info '%', test_pkg.var1;
end;
/

BEGIN
  test_pkg.var2[5] := 'abc';
  raise info '%', test_pkg.var2;
end;
/

--again
BEGIN
  test_pkg.var2[4] := 'abc1';
  raise info '%', test_pkg.var2;
end;
/

DECLARE
  var1 complex1;
  var2 text[];
BEGIN
  var1 := test_pkg.var1;
  var2 := test_pkg.var2;
  raise info '%,%',var1,var2;
end;
/

--again
DECLARE
  var1 complex1;
  var2 text[];
BEGIN
  var1 := test_pkg.var1;
  var2 := test_pkg.var2;
  raise info '%,%',var1,var2;
end;
/

DROP package test_pkg;

CREATE OR REPLACE package test_pkg IS
  var1 quadarray;
  FUNCTION test_f(id integer) RETURN quadarray;
end;
/

CREATE OR REPLACE package body test_pkg IS
  FUNCTION test_f(id integer) RETURN quadarray IS
  BEGIN
     RETURN var1;
  end;
end;
/

DECLARE
  var1 quadarray;
BEGIN
  var1.c1[1].i := 1;
  var1.c1[1].r := 1.4;
  var1.c2.i := 1.5;
  var1.c2.r := 1.6;
  test_pkg.var1 := var1;
  raise info '%', test_pkg.var1;
end;
/

DECLARE
  var1 quadarray;
BEGIN
  var1 := test_pkg.test_f(1);
  raise info '%', var1;
end;
/

--again
DECLARE
  var1 quadarray;
BEGIN
  var1 := test_pkg.test_f(1);
  raise info '%', var1;
end;
/

DROP package test_pkg;
DROP type quadarray;
DROP type complex1;

--support polymorphic type
CREATE OR REPLACE package test_pkg IS
  var1 integer;
  var2 number;
  var3 point;
  FUNCTION f1(x anyelement) RETURN anyelement;
end;
/

CREATE OR REPLACE package body test_pkg is
   function f1(x anyelement) return anyelement as
   begin
	return x + 1;
   END;
end;
/

begin
   test_pkg.var1 := test_pkg.f1(42);
   test_pkg.var2 := test_pkg.f1(4.5);
   raise info 'var1=%,var2=%',test_pkg.var1,test_pkg.var2;
   test_pkg.var3 := test_pkg.f1(point(3,4));
   raise info 'var3=%', test_pkg.var3;
end;
/

begin
   test_pkg.var1 := test_pkg.f1(42);
   test_pkg.var2 := test_pkg.f1(4.5);
   raise info 'var1=%,var2=%',test_pkg.var1,test_pkg.var2;
end;
/


--ok
CREATE OR REPLACE package test_pkg IS
   var1 integer;
   var2 number;
   var3 mds%rowtype;
   function f1(x anyelement) return anyelement;
end;
/

CREATE OR REPLACE package body test_pkg AS
  FUNCTION f1(x anyelement) RETURN anyelement AS
  begin
    var3.id := var3.id + 1;
	var3.name := var3.name || x;
	return x + 1;
   END;
BEGIN
   var3.id := 1;
   var3.name := 'ok';
   var1 := f1(42);
   var2 := f1(4.5);
   raise info 'var1=%,var2=%',var1,var2;
   raise info '%', var3;
end;
/

DECLARE
  var1 mds%rowtype;
BEGIN
   var1.id := 1;
   var1.name := 'welcome';
   test_pkg.var3 := var1;
end;
/

DECLARE
  var1 mds%rowtype;
  var2 number;
  var3 varchar2(256);
BEGIN
  var2 := test_pkg.f1(1.4);
  var3 := test_pkg.f1(2);
  var1 := test_pkg.var3;
  raise info '%', var1;
end;
/

--again
DECLARE
  var1 mds%rowtype;
  var2 number;
  var3 varchar2(256);
BEGIN
  var2 := test_pkg.f1(23);
  var3 := test_pkg.f1(0);
  var1 := test_pkg.var3;
  raise info '%', var1;
end;
/


--ok
CREATE OR REPLACE package test_pkg is
  function f1(x anyarray) return anyarray;
end;
/
CREATE OR REPLACE package body test_pkg IS
  FUNCTION f1(x anyarray) RETURN anyarray is
  begin
     return x;
  end;
end;
/

BEGIN
  raise info '%,%', test_pkg.f1(array[2,4]),test_pkg.f1(array[4.5, 7.7]);
end;
/

BEGIN
  raise info '%,%', test_pkg.f1(array[4,5]),test_pkg.f1(array[5.5, 7.8]);
end;
/

DROP package test_pkg;

--test scheam function and package function Priority
CREATE schema test_schema;

CREATE OR REPLACE FUNCTION test_schema.test_f(id integer) RETURN integer
IS
BEGIN
   raise info 'scheam test_f invoke';
   RETURN id;
end;
/

CREATE OR REPLACE PROCEDURE test_schema.test_p(id integer) IS
BEGIN
   raise info 'schema test_p invoke';
END test_p;
/

CREATE OR REPLACE function test_schema.test_f1(id integer) RETURN integer IS
BEGIN
   raise info 'scheam test_f1 invoke';
   RETURN id;
END test_f1;
/

CREATE OR REPLACE PROCEDURE test_schema.test_p1(id integer) IS
BEGIN
  raise info 'schema test_p1 invoke';
end;
/


CREATE OR REPLACE package test_schema IS
  FUNCTION test_f(id integer) RETURN integer;
  procedure test_p(id integer);
end;
/

CREATE OR REPLACE package body test_schema IS
  FUNCTION test_f(id integer) RETURN integer IS
  BEGIN
     raise info 'package test_f invoke';
	 RETURN id;
  end;
  PROCEDURE test_p(id integer) IS
  BEGIN
    raise info 'package test_p invok';
  end;
end;
/

--invoke package function
SELECT test_schema.test_f(23) FROM dual;

--invoke package procedure
call test_schema.test_p(23);

--raise error
SELECT test_schema.test_f1(23) FROM dual;

--raise error
call test_schema.test_p1(23);

--drop package
DROP package test_schema;

--ok
SELECT test_schema.test_f1(23) FROM dual;

--ok
call test_schema.test_p1(23);

--drop schema
DROP SCHEMA test_schema cascade;

-- privileges on packages
CREATE USER test_user;
create user test_user1;
create user test_user2;

GRANT CREATE ON SCHEMA public TO test_user;

SET SESSION AUTHORIZATION test_user;

CREATE package priv_package is
 var1 integer;
 function test_f(id integer) return integer;
 procedure test_p(id integer);
end;
/

create package body priv_package is
  function test_f(id integer) return integer is
  begin
     return id;
  end;
  procedure test_p(id integer) is
  begin
    raise info 'call test_p';
  end;
end;
/

CREATE package priv_package1 is
 var1 integer;
 function test_f(id integer) return integer;
 procedure test_p(id integer);
end;
/

create package body priv_package1 is
  function test_f(id integer) return integer is
  begin
     return id;
  end;
  procedure test_p(id integer) is
  begin
    raise info 'call test_p';
  end;
end;
/

REVOKE ALL ON package priv_package, priv_package1 FROM PUBLIC;

GRANT EXECUTE ON package priv_package,priv_package1 TO test_user1;

GRANT USAGE ON package priv_package TO test_user1; -- semantic error

GRANT ALL PRIVILEGES ON package priv_package TO test_user1;

GRANT EXECUTE ON package priv_package1 TO test_user1;

SET SESSION AUTHORIZATION test_user2;

--raise error
declare
  var1 integer;
begin
  var1 := priv_package.var1;
end;
/

--raise error
declare
  var1 priv_package.var1%type;
begin
  var1 := 1;
end;
/

--raise error
call priv_package.test_p(23);

--raise error
select priv_package.test_f(23) from dual;

SET SESSION AUTHORIZATION test_user1;

--ok
declare
  var1 integer;
begin
  var1 := priv_package.var1;
end;
/

--ok
declare
  var1 priv_package.var1%type;
begin
  var1 := 1;
end;
/

--ok
call priv_package.test_p(23);

--ok
select priv_package.test_f(23) from dual;

SET SESSION AUTHORIZATION test_user;

GRANT EXECUTE ON package priv_package TO test_user2;

SET SESSION AUTHORIZATION test_user2;

--ok
declare
  var1 integer;
begin
  var1 := priv_package.var1;
end;
/

--ok
declare
  var1 priv_package.var1%type;
begin
  var1 := 1;
end;
/

--ok
call priv_package.test_p(23);

--ok
select priv_package.test_f(23) from dual;

reset SESSION AUTHORIZATION;

REVOKE ALL ON ALL PACKAGES IN SCHEMA public FROM test_user2;
REVOKE ALL ON ALL PACKAGES IN SCHEMA public FROM test_user1;

ALTER DEFAULT PRIVILEGES GRANT ALL ON packages TO test_user2;
ALTER DEFAULT PRIVILEGES REVOKE ALL ON packages FROM test_user2;

--clean privileges data
DROP package priv_package;
DROP package priv_package1;
DROP USER test_user1;
REVOKE CREATE ON SCHEMA public FROM test_user;
DROP USER test_user;
DROP USER test_user2;


CREATE OR REPLACE package test_pkg IS
	PROCEDURE proc1(number1 NUMBER);
	PROCEDURE proc2(number2 NUMBER);
	PROCEDURE proc3(number3 NUMBER);
	PROCEDURE proc4(number4 NUMBER);
end;
/

CREATE OR REPLACE package body test_pkg is
	PROCEDURE proc2(number2 NUMBER) IS
	BEGIN
		call proc1(number2);
		raise info '%', number2;
		raise info '%','proc2';
	END;

	PROCEDURE proc4(number4 NUMBER) IS
	BEGIN
		raise info '%','proc4';
		call proc3(number4);
		raise info 'proc3 out %', number4;
	END;

	PROCEDURE proc1(number1 NUMBER) IS
	BEGIN
		raise info '%','proc1';
		number1 := 0;
	END;

	PROCEDURE proc3(number3 NUMBER) IS
	BEGIN
		raise info '%', 'proc3';
		number3 := 1;
	END;
BEGIN
	call proc2(1);
	call proc4(2);
END;
/

call test_pkg.proc1(23);

discard package;

DROP package test_pkg;

CREATE OR REPLACE package pkg IS
  var1 integer;
  FUNCTION test_f(id integer) RETURN integer;
end;
/

CREATE OR REPLACE package body pkg IS
  FUNCTION test_f(id integer) RETURN integer IS
  BEGIN
    RETURN 23;
  end;
end;
/

CREATE OR REPLACE FUNCTION test_f(id pkg.var1%type, name varchar2 DEFAULT '123') RETURN pkg.var1%type IS
BEGIN
   RETURN id;
end;
/

CREATE VIEW test_view_f AS SELECT test_f(23) FROM dual;

SELECT test_f(23,'xiexie') FROM dual;
SELECT test_f(23) FROM dual;
SELECT * FROM test_view_f;

CREATE OR REPLACE package pkg IS
  var1 varchar2(256);
  FUNCTION test_f(id integer) RETURN integer;
end;
/

CREATE OR REPLACE package body pkg IS
  FUNCTION test_f(id integer) RETURN integer IS
  BEGIN
    RETURN 23;
  end;
end;
/


SELECT test_f('mdsxx','xiexie') FROM dual;
SELECT test_f('mdsxx') FROM dual;
SELECT * FROM test_view_f;

DROP VIEW test_view_f;
DROP FUNCTION test_f;
DROP package pkg;

CREATE OR REPLACE package test_pkg IS
  var1 mds%rowtype;
  var2 constant integer := 4;
end;
/

BEGIN
  test_pkg.var1.id := 23;
  test_pkg.var1.name := 'xiexie';
end;
/

CREATE OR REPLACE package body test_pkg IS
BEGIN
  var1.id := 23;
  var1.name := 'ok';
  raise info 'init block';
end;
/

--no invoke init block
BEGIN
  raise info '%', test_pkg.var2;
end;
/

--invoke init block
BEGIN
  raise info '%', test_pkg.var1;
end;
/

DROP package test_pkg;

--test standard package
CREATE schema test_schema;

--failed because standard only in sys
CREATE OR REPLACE package test_schema.standard IS
  var1 integer;
end;
/

--success
CREATE OR REPLACE package sys.standard IS
  standard_var1 integer;
  FUNCTION test_f(id integer) RETURN integer;
end;
/

CREATE OR REPLACE package body sys.standard IS
  var2 integer;
  FUNCTION test_f(id integer) RETURN integer IS
  BEGIN
     raise info 'standard func';
	 RETURN 23;
  end;
end;
/

--rename failed
ALTER package sys.standard rename TO pkg;

--set scheam failed
ALTER package sys.standard SET schema test_schema;

--ok
DECLARE
  var2 integer;
BEGIN
  standard_var1 := 23;
  raise info '%', standard_var1;
end;
/


--ok
BEGIN
  raise info '%', standard_var1;
end;
/

DECLARE
 var1 integer;
BEGIN
  var1 := sys.standard.test_f(23);
  var1 := standard.test_f(23);
  var1 := test_f(23);
end;
/

--drop
DROP package sys.standard;
DROP SCHEMA test_schema;

--test #option dump
CREATE OR REPLACE package test_pkg IS
#OPTION DUMP
var1 integer;
FUNCTION test_f(id integer) RETURN integer;
PROCEDURE test_p(id integer);
END test_pkg;
/

CREATE OR REPLACE package body test_pkg IS
#OPTION DUMP
var2 integer;
FUNCTION test_f(id integer) RETURN integer IS
  var3 integer;
  FUNCTION test_f(id integer) RETURN integer IS
  BEGIN
    RETURN 23;
  END test_f;
  PROCEDURE test_pp(id integer) IS
  BEGIN
    raise info 'ok';
  END test_pp;
BEGIN
   RETURN id;
end;
PROCEDURE test_p(id integer) IS
  FUNCTION test_ff(id integer) RETURN integer IS
  BEGIN
    RETURN id;
  end;
  PROCEDURE test_pp(id integer) IS
  BEGIN
    raise info 'xiexie';
  END test_pp;
BEGIN
   raise info 'welcome';
end;
BEGIN
  var1 := 23;
  var2 := 46;
end;
/

DROP package test_pkg;

--test found variable
create table test_found(id integer);

insert into test_found values(2);

create or replace package test_pkg is
  function test_f(id integer) return integer;
  function test_f1(id integer) return integer;
end;
/

create or replace package body test_pkg is
  var1 integer;
  function test_f(id integer) return integer is
  begin
    update test_found set id = 2;
    if found then
      raise info 'test_f found';
    else
       raise info 'test_f not found';
    end if;
    return id;
  end;
  function test_f1(id integer) return integer is
  begin
   if found then
     raise info 'test_f1 found';
     var1 := test_f(23);
   else
     raise info 'test_f1 not found';
     var1 := test_f(23);
   end if;
   if found  then
     raise info 'test_f1 again found';
   else
     raise info 'test_f1 again not found';
   end if;
   return 23;
 end;
end;
/

--raise info
--test_f1 not found
--test_f found
--test_f1 again found
declare
  var1 integer;
begin
  var1 := test_pkg.test_f1(23);
end;
/

--clean
DROP package test_pkg;
DROP TABLE test_found;

--test pg record in package
CREATE TABLE test_record(id integer,name varchar2(23));
CREATE TABLE test_record1(id integer,name varchar2(23),id2 integer);

INSERT INTO test_record1 VALUES(1,'sfdjsjf',23);

CREATE OR REPLACE package test_pkg IS
  r record;
  FUNCTION test_f(id record) RETURN integer;
end;
/

CREATE OR REPLACE package body test_pkg IS
  FUNCTION test_f(id record) RETURN integer IS
  BEGIN
    raise info '%',id;
	RETURN 23;
  end;
BEGIN
  SELECT * INTO r FROM test_record;
  raise exception 'xiexie';
exception
  when others then
    raise info 'not data';
	INSERT INTO test_record VALUES(1,'xiexie');
	SELECT * INTO r FROM test_record;
end;
/

--ref type
DECLARE
  r test_pkg.r%type;
BEGIN
  raise info 'r=%',r;
end;
/

--ref func
DECLARE
  r record;
  var1 integer;
BEGIN
  var1 := test_pkg.test_f(r);
end;
/

DECLARE
  r record;
  var1 integer;
BEGIN
  SELECT * INTO r FROM test_record;
  var1 := test_pkg.test_f(r);
end;
/

--again ref r
DECLARE
  r test_pkg.r%type;
BEGIN
  raise info '%',r;
  r := test_pkg.r;
  raise info '%',r;
end;
/

DECLARE
  r test_pkg.r%type;
BEGIN
  raise info '%',r;
  SELECT * INTO test_pkg.r FROM test_record1;
  raise info '%',test_pkg.r;
end;
/

DROP package test_pkg;
DROP TABLE test_record;
DROP TABLE test_record1;

create table test_cursor(id integer,name varchar2(25));

insert into test_cursor values(1,'welcome');

create or replace package test_pkg is
  c cursor is select * from test_cursor;
end;
/

create or replace package test_pkg1 is
  c cursor is select * from test_cursor;
end;
/

declare
  var1 test_cursor%rowtype;
begin
  open test_pkg.c;
  fetch test_pkg.c into var1;
  raise info '%', var1;
  open test_pkg1.c;
  fetch test_pkg1.c into var1;
  raise info '%', var1;
  close test_pkg.c;
  close test_pkg1.c;
end;
/


declare
  c1 cursor is select * from test_cursor;
  var1 test_cursor%rowtype;
begin
  open c1;
  declare
     c1 cursor is select * from test_cursor;
   begin
     open c1;
     fetch c1 into var1;
     raise info 'inter-%', var1;
     close c1;
   end;
   fetch c1 into var1;
   raise info 'outer-%', var1;
   close c1;
end;
/

DROP package test_pkg;
DROP package test_pkg1;
DROP TABLE test_cursor;

--test replace change pg_proc argtypes
--and rettypes
SET ivorysql.identifier_case_switch = INTERCHANGE;

create or replace package test_pkg is
  var1 integer;
end;
/

create or replace function test_f(id test_pkg.var1%type) return test_pkg.var1%type is
begin
   return id;
end;
/

create or replace procedure test_p(id test_pkg.var1%type, name out test_pkg.var1%type) is
begin
   raise info '%-%',id,name;
   name := id;
end;
/

create or replace procedure test_p1(id1 integer,id test_pkg.var1%type, name out test_pkg.var1%type) is
begin
   raise info '%-%',id,name;
   name := id;
end;
/

CREATE OR REPLACE VIEW test_view AS SELECT test_f(23) AS id FROM dual;

--ok
SELECT test_f(23) FROM dual;
SELECT * FROM test_view;
DECLARE
  name integer;
  var1 varchar2(23);
BEGIN
  call test_p(23,name);
  raise info '%',name;
  call test_p1(24,24,name);
  raise info '%',name;
end;
/

create or replace package test_pkg is
  var1 varchar2(256);
end;
/

--ok
select test_f('abc') from dual;
SELECT * FROM test_view;
DECLARE
  name varchar2(256);
  var1 varchar2(256);
BEGIN
  call test_p('abc',name);
  raise info '%',name;
  call test_p1(23,'abc',name);
  raise info '%',name;
end;
/

create or replace package test_pkg is
  var1 integer;
end;
/

--ok
SELECT test_f(23) FROM dual;
SELECT * FROM test_view;
DECLARE
  name integer;
  var1 varchar2(23);
BEGIN
  call test_p(23,name);
  raise info '%',name;
  call test_p1(24,24,name);
  raise info '%',name;
end;
/


create or replace function test_f(id test_pkg.var1%type) return test_pkg.var1%type is
begin
   return id;
end;
/

create or replace procedure test_p(id test_pkg.var1%type, name out test_pkg.var1%type) is
begin
   raise info '%-%',id,name;
   name := id;
end;
/

create or replace procedure test_p1(id1 integer,id test_pkg.var1%type, name out test_pkg.var1%type) is
begin
   raise info '%-%',id,name;
   name := id;
end;
/

CREATE OR REPLACE VIEW test_view AS SELECT test_f(23) AS id FROM dual;

--ok
SELECT * FROM test_view;
SELECT test_f(23) FROM dual;
DECLARE
  name integer;
  var1 varchar2(23);
BEGIN
  call test_p(23,name);
  raise info '%',name;
  call test_p1(24,24,name);
  raise info '%',name;
end;
/

--clear
DROP VIEW test_view;
DROP FUNCTION test_f;
DROP PROCEDURE test_p;
DROP PROCEDURE test_p1;
DROP package test_pkg;

--clean data
DROP FUNCTION test_event_trigger;
DROP TABLE mds;
DROP TABLE mdss;

