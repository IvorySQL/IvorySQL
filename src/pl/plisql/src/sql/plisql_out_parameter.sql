create table books(id integer,name varchar(256),price integer,shelf varchar(256));

create or replace function test_return_out(id integer,price out integer,name out varchar) return varchar 
as
begin
  price := 20000;
  name := 'test a char out';
  return 'welcome to QingDao';
end;
/

declare
  revchar varchar(256);
  name varchar(256);
  id integer;
  price integer;
begin
  id := 34;
  revchar := test_return_out(id,price,name);
  raise notice 'id=%',id;
  raise notice 'price=%',price;
  raise notice 'name=%',name;
  raise notice 'retvar=%',revchar;
end;
/

--test the length of out-paramter actual value is longer than out variable

declare
  name varchar(3);
  price integer;
  id integer;
  revchar varchar(5);
begin
  id := 34;
  revchar := test_return_out(id,price,name);
  raise notice 'id=%',id;
  raise notice 'revchar=%',revchar;
  raise notice 'price=%',price;
  raise notice 'name=%',name;
end;
/

--test pass out paramters by name
declare
  id integer;
  name varchar(256);
  price integer;
  revchar varchar(256);
begin
  id := 34;
  revchar := test_return_out(id=>id,price=>price,name=>name);
  raise notice 'id=%',id;
  raise notice 'revchar=%',revchar;
  raise notice 'price=%',price;
  raise notice 'name=%',name;
end;
/


--test order of name and position paramaters
--postion notation is not allowed to be appeared after name notation
declare
  id integer;
  price integer;
  name varchar(256);
  revchar varchar(256);
begin
  id := 34;
  revchar := test_return_out(id=>id,price=>price,name);
  raise notice 'id=%',id;
  raise notice 'revchar=%',revchar;
  raise notice 'price=%',price;
  raise notice 'name=%', name;
end;
/

--test both name and position notation exist
declare
  id integer;
  name varchar(256);
  prices integer;
  revchar varchar(256);
begin
  id := 34;
  revchar := test_return_out(id,name=>name,price=>prices);
  raise notice 'id=%',id;
  raise notice 'revchar=%',revchar;
  raise notice 'prices=%',prices;
  raise notice 'name=%',name;
end;
/

drop function test_return_out(integer,integer,varchar);


--use varchar datatype for IN variable
create or replace procedure test_proc_out(id integer,price out integer,name varchar)
as
begin
  price := 2000 + id;
end;
/

declare
 id integer;
 prices integer;
 namet varchar(256);
begin
 id := 200;
 namet := 'in variable would not change';
 call test_proc_out(id,prices,namet);
 raise notice 'id=%',id;
 raise notice 'prices=%',prices;
 raise notice 'namet=%',namet;
end;
/

drop procedure test_proc_out(integer,integer,varchar);

--function return value 
create or replace function test_operator(id integer,price out integer) return integer
as
begin
  price := 1000 + id;
  return id;
end;
/

declare
  id integer;
  prices integer;
  ret integer;
begin
  id := 200;
  ret := test_operator(id,prices);
  raise notice 'prices=%',prices;
  raise notice 'ret=%',ret;
end;
/

declare
  id integer;
  prices integer;
  ret integer;
begin
  id := 200;
  ret := test_operator(id,prices) + id + 4;
  raise notice 'prices=%',prices;
  raise notice 'ret=%',ret;
end;
/

drop function test_operator(integer,integer);

--can't assign value to IN mode variable
create or replace function test_inchange(id integer,name varchar,nameout out varchar) return integer
as
begin
  id := 23;
  name := 'a test';
  nameout := '';
  return 2;
end;
/


--report error when IN OUT paramater has default value
create or replace function test_return_inout(id integer,price in out integer default 100,name out varchar) return varchar 
as
begin
  price := 20000 + price;
  name := 'this is a test';
  return 'welcome to QingDao';
end;
/

create or replace function test_return_inout(id integer,price in out integer,name out varchar) return varchar
as
begin
  price := 20000 + price;
  name := 'this is a test';
  return 'welcome to QingDao';
end;
/

declare
  id integer;
  name varchar(256);
  retvar varchar(256);
  price integer;
begin
  id := 25;
  price := 100;
  retvar := test_return_inout(id,price,name);
  raise notice 'retvar=%',retvar;
  raise notice 'name=%',name;
  raise notice 'price=%',price;
end;
/

drop function test_return_inout(integer,integer,varchar);


--IN mode paramters can have default value, but OUT mode paramter can not
create or replace function test_return_inout(id integer default 10,stotal out integer) return int 
as
begin
  stotal := id;
  return 11;
end;
/

declare
  stotal integer;
  nret int;
begin 
  nret := test_return_inout(stotal); 
end;
/

declare
  stotal integer;
  nret int;
begin
  nret := test_return_inout(stotal=>stotal); 
  raise notice 'stotal=%',stotal;
  raise notice 'nret=%',nret;
end;
/

drop function test_return_inout(integer, integer);

create or replace function test_return_inout(id integer default 10,price integer default 20,stotal out integer) return varchar 
as
begin
  stotal := 100 + id * price;
  return 'welcome to QingDao';
end;
/

declare
  stotal integer;
  nret varchar(256);
begin
  nret := test_return_inout(stotal);--error
end;
/

declare
  stotal integer;
  nret varchar(256);
begin
  nret := test_return_inout(stotal=>stotal);  
  raise notice 'stotal=%',stotal;
  raise notice 'nret=%',nret;
end;
/

declare
  stotal integer;
  nret varchar(256);
  id integer;
begin
  id := 30;
  nret := test_return_inout(id=>id,stotal=>stotal); 
  raise notice 'stotal=%',stotal;--700
end;
/


declare
stotal integer;
nret varchar(256);
id integer;
begin
 id := 30;
 nret := test_return_inout(price=>id,stotal=>stotal); 
 raise notice 'stotal=%',stotal;--400
end;
/

--print value
declare
  stotal integer;
  nret varchar(256);
  id integer;
begin
  id := 30;
  nret := test_return_inout(price=>id,id=>id,stotal=>stotal); 
  raise notice 'stotal=%',stotal;--1000
end;
/

--print value
declare
  stotal integer;
  nret varchar(256);
  id integer;
begin
  id := 30;
  nret := test_return_inout(price=>id,id=>id,stotal=>id); 
  raise notice 'stotal=%',id;--1000
end;
/

--print value
declare
  stotal integer;
  nret varchar(256);
  id integer;
begin
  id := 30;
  nret := test_return_inout(stotal=>id,price=>id,id=>id); 
  raise notice 'stotal=%',id;--1000
end;
/

drop function test_return_inout(integer,integer,integer);

--test varchar-out
create or replace function test_return_inout(stotal out varchar,id varchar default 'abc',price varchar default 'def') return varchar
as
begin
  stotal = id || price;
  return 'welcome to QingDao';
end;
/

declare
  id varchar(256);
  nret varchar(256);
begin
  nret := test_return_inout(stotal=>id,price=>id,id=>id);
  raise notice 'stotal=%',id; --null
end;
/

--print test abctest abc
declare
  id varchar(256);
  nret varchar(256);
begin
  id := 'test abc';
  nret := test_return_inout(stotal=>id,price=>id,id=>id);
  raise notice 'stotal=%',id;
end;
/

drop function test_return_inout(varchar,varchar,varchar);


--test default value
create or replace function test_default_var(id integer default 10,price integer default 20) return integer
as
begin
  return id*2 + price;
end;
/

select * from test_default_var(20,30);--70
select test_default_var(100);--220

--print 40
declare
  ids integer;
begin
  ids = test_default_var();
  raise notice 'ids=%',ids;
end;
/

--print 60
declare
ids integer;
id integer;
begin
 id := 20;
 ids := test_default_var(id);
 raise notice 'ids=%',ids;
end;
/

drop function test_default_var(integer,integer);

--pass OUT paramater by Const
create or replace function test_return_out(id integer,price out integer,name out varchar) return varchar
as
begin
  price := 20000;
  name := 'test a char out';
  return 'welcome to QingDao';
end;
/

---test failed
declare
  id integer;
  ret varchar(256);
begin
  ret := test_return_out(id,12, NULL);
  raise notice 'ret=%',ret;
end;
/

declare
  id integer;
  ret varchar(256);
begin
  ret := test_return_out(id,12,'thanks'::varchar);
  raise notice 'ret=%',ret;
end;
/

drop function test_return_out(integer,integer,varchar);


--test IN OUT mode paramter
create or replace function test_return_out(id integer,price in out integer,name in out varchar) return varchar
as
begin
  price := 2 + id;
  name := 'test a char out';
  return 'welcome to QingDao';
end;
/

declare
  id integer := 1;
  ret varchar(256);
  name varchar(20);
  price integer;
begin
  ret := test_return_out(id,price,name);
  raise notice 'price=%, name=%',price,name;
  raise notice 'ret=%',ret;
end;
/

drop function test_return_out(integer,integer,varchar);


--test multiple out-paramters, function returns void
create or replace function test_return_out(id integer,price out integer,name out varchar) return void
as
begin
  price := 20000 + id;
  name := 'test a char out';
end;
/

declare
  id integer := 1;
  ret varchar(256);
  name varchar(20);
  price integer;
begin
  ret := test_return_out(id,price,name);
  raise notice 'price=%, name=%',price,name;
  raise notice 'ret=%',ret;
end;
/

drop function test_return_out(integer,integer,varchar);

--test single out-paramter, function returns void
create or replace function test_return_out(id integer,price out integer) return void
as
begin
  price := 20000 + id;
end;
/

declare
  id integer := 1;
  ret varchar(256);
  price integer;
begin
  ret := test_return_out(id,price);
  raise notice 'price=%',price;
  raise notice 'ret=%',ret;
end;
/

drop function test_return_out(integer,integer);


--test single out-paramter, function returns non-void
create or replace function test_return_out(id integer,price out integer) return int
as
begin
  price := 20000 + id;
  return 11;
end;
/

declare
  id integer := 1;
  ret varchar(256);
  price integer;
begin
  ret := test_return_out(id,price);
  raise notice 'price=%',price;
  raise notice 'ret=%',ret;
end;
/

drop function test_return_out(integer,integer);

--test procedure is called inside another procedure
create or replace procedure test_return_out_proc(id integer,price out varchar,name out varchar)
as
declare
begin
  price := 'test_return_out price';
  name := 'test_return_out name';
end;
/

create or replace procedure call_return_out_proc(id integer,price out varchar,name out varchar)
as
declare
  name1 varchar(256);
  id1 integer;
begin
  id1 := 256;
  call test_return_out_proc(id,price,name1);
  name := 'call_return_out name';
  raise notice 'return_out id=%',id;
  raise notice 'return_out price=%',price;
  raise notice 'return_out name1=%',name1;
end;
/

declare
  id integer := 1;
  name varchar(256);
  price varchar(256);
begin
  call call_return_out_proc(id,price, name);
  raise notice 'price=%',price;
  raise notice 'name=%',name;
end;
/

drop procedure test_return_out_proc(integer,varchar,varchar);
drop procedure call_return_out_proc(integer,varchar,varchar);


--test out-paramster from outer
create or replace function test_return_out(id integer,price out varchar,name out varchar) return integer
as
declare
  ids integer;
begin
  raise notice 'thanks';
  ids := id + 100;
  price := 'thanks' || ids;
  name := 'welcome to QingDao' || ids;
  return ids;
end;
/

create or replace function call_test_return_out(id integer,price out varchar,name out varchar) return integer
as
declare
  ids integer;
begin
  ids := 300;
  return test_return_out(test_return_out(ids, price,name),price,name);
end;
/

declare
  price varchar(256);
  name varchar(256);
  ids integer;
begin
  ids := call_test_return_out(23,price,name);
  raise notice 'price=%',price;
  raise notice 'name=%',name;
  raise notice 'ids=%',ids;
end;
/

drop function call_test_return_out(integer,varchar,varchar);
drop function test_return_out(integer,varchar,varchar);


--out parameter is first parameter
create or replace function test_return_out(price out integer,name out varchar,id integer) return varchar
as
begin
  price := 20000;
  name := 'test a char out';
  return 'welcome to QingDao';
end;
/

declare
  ret varchar(256);
  price integer;
  name varchar(256);
begin
  ret := test_return_out(price,name,23);
  raise notice 'price=%',price;
  raise notice 'name=%',name;
end;
/

drop function test_return_out(integer,varchar,integer);


--test cast of datatype in parameter
create or replace function test_cast_parameter(id integer,price out varchar) return integer
as
declare
begin
  price := 25;
  return 24;
end;
/


declare
  books integer;
  ret integer;
begin
  ret := test_cast_parameter(23,books::varchar);
  raise notice 'books=%',books;
end;
/

drop function test_cast_parameter(integer,varchar);


--test type parameters
create type testtype1 AS (a int, b text);
create type testtype2 as (a varchar);

create or replace function test_type_parameter(id integer, typeout out testtype1, type1out out testtype2) return testtype1 as
begin
  typeout.a := 3;
  typeout.b := 'thanks';
  type1out.a := 'welcome to QingDao';
  return typeout;
end;
/

declare
  books1 testtype2;
  books testtype1;
  ret testtype1;
begin
  ret := test_type_parameter(23,books,books1);
  raise notice 'books=%',books;
  raise notice 'ret=%',ret;
  raise notice 'books1=%',books1;
end;
/

drop function test_type_parameter(integer,testtype1,testtype2);
drop type testtype1;
drop type testtype2;

--test IN/OUT actual parameters with initial values
create or replace function test_init_out_inout(id integer,price out integer, total in out integer) return varchar as
begin
  raise notice 'price = %,total =%',price,total;
  price := 1986;
  total := 1986 * 10;
  return 'thanks';
end;
/

declare
  id integer;
  price integer;
  total integer;
  return_x varchar(256);
begin
  id := 23;
  price := 24;
  total := 25;
  return_x := test_init_out_inout(id,price,total); --null, 25
  raise notice '%,%,%', return_x, price, total;
end;
/


--test failed
create cast(varchar as integer) with inout as implicit;

declare
  abc varchar(256);
  return_x varchar(256);
begin
  abc := 'thanks';
  return_x := test_init_out_inout(23, abc,abc);
  raise notice '%,%', return_x, abc;
end;
/

--test name notation
declare
  abc varchar(256);
  return_x varchar(256);
  total integer;
begin
  return_x := test_init_out_inout(23,total=>total,price=>abc);
  raise notice '%,%,%', return_x, abc,total;
end;
/

drop cast(varchar as integer);
drop function test_init_out_inout(integer,integer,integer);


--failed to create function which has OUT parameter and returns setof
create or replace function test_return_setof_out(id varchar,books out integer) return setof integer as
declare
  bookss integer;
begin
  NULL;
end;
/


create or replace function test_return_setof_inout(id varchar,books inout integer) return setof integer as
declare
  booksss integer;
begin
  NULL;
end;
/


--test function that returns record datatype
create table t1(id int, name varchar(20));
insert into t1 values(10,'a');

create or replace function f1(id integer,price out varchar) return record as
declare
  r record;
begin
 price := 25;
 select * from t1 into r;
 return r;
end;
/

declare
  a varchar(20);
  ret record;
begin
  ret := f1(23,a);
  raise notice 'a= %,ret=%',a, ret; --a= 25, ret=(10,a)
end;
/

drop function f1(integer, varchar);
drop table t1;

--test out parameter which datatype is year to month
create or replace function test_interval(id integer, time1 out interval year to month, time2 out interval year to month[], time3 interval year to month) return interval year to month as
declare
  books interval year to month[3];
begin
  books[0] := interval '1-1' year to month;
  books[1] := interval '1-2' year to month;
  books[2] := interval '1-3' year to month;
  time1 := interval '1-2' year to month;
  time2 := books;
  return time3;
end;
/

declare
  id integer;
  time1 interval year to month;
  time2 interval year to month[3];
  time3 interval year to month;
  time4 interval year to month;
begin
  id := 23;
  time3 := interval '1-4' year to month;
  time4 := test_interval(id, time1,time2,time3);
  raise info '%',time1;
  raise info '%',time2;
  raise info '%',time3;
  raise info '%',time4;
end;
/


--test out paramater which datatype is day to second
create or replace function test_interval(id integer, time1 out interval day to second, time2 out interval day to second[], time3 interval day to second) return interval day to second as
declare
  books interval day to second[3];
begin
  books[0] := interval '4 13:12:12' day to second;
  books[1] := interval '5 13:12:12' day to second;
  books[2] := interval '6 13:12:12' day to second;
  time1 := interval '4 12:12:12' day to second;
  time2 := books;
  return time3;
end;
/

declare
  id integer;
  time1 interval day to second;
  time2 interval day to second[3];
  time3 interval day to second;
  time4 interval day to second;
begin
  id := 23;
  time3 := interval '4 14:12:12' day to second;
  time4 := test_interval(id, time1, time2, time3);
  raise info '%',time1;
  raise info '%',time2;
  raise info '%',time3;
  raise info '%',time4;
end;
/

--test out paramater which datatype is number
create or replace function test_number(id integer,number1 out number, number2 out number[],number3 number) return number as
declare
  books number(4,2)[3];
begin
  books[0] := 23.34;
  books[1] := 24.34;
  books[2] := 25.34;
  number1 := 3.14;
  number2 := books;
  return number3;
end;
/

declare
  id integer;
  number1 number;
  number2 number[3];
  number3 number;
  number4 number;
begin
  id := 2;
  number3 := 24.12;
  number4 := test_number(id, number1,number2,number3);
  raise info '%',number1;
  raise info '%',number2;
  raise info '%',number3;
  raise info '%',number4;
end;
/


--test out paramater which datatype is binary_float
create or replace function test_binary_float(id integer,binary1 out binary_float, binary2 out binary_float[],binary3 binary_float) return binary_float as
declare
  books binary_float[3];
begin
  books[0] := 3.1415926;
  books[1] := 4.1415926;
  books[2] := 5.1415926;
  binary1 := 213.256;
  binary2 := books;
  return binary3;
end;
/

declare
  id integer;
  binary1 binary_float;
  binary2 binary_float[3];
  binary3 binary_float;
  binary4 binary_float;
begin
  id := 2;
  binary3 := 24.12;
  binary4 := test_binary_float(id, binary1,binary2,binary3);
  raise info '%',binary1;
  raise info '%',binary2;
  raise info '%',binary3;
  raise info '%',binary4;
end;
/

--test out paramater which datatype is binary_double
create or replace function test_binary_double(id integer,binary1 out binary_double, binary2 out binary_double[],binary3 binary_double) return binary_double as
declare
  books binary_double[3];
begin
  books[0] := 3.1415926;
  books[1] := 4.1415926;
  books[2] := 5.1415926;
  binary1 := 213.256;
  binary2 := books;
  return binary3;
end;
/

declare
  id integer;
  binary1 binary_double;
  binary2 binary_double[3];
  binary3 binary_double;
  binary4 binary_double;
begin
  id := 2;
  binary3 := 24.12;
  binary4 := test_binary_double(id, binary1,binary2,binary3);
  raise info '%',binary1;
  raise info '%',binary2;
  raise info '%',binary3;
  raise info '%',binary4;
end;
/

drop function test_interval(integer,interval year to month, interval year to month[], interval year to month);
drop function test_interval(integer,interval day to second, interval day to second[], interval day to second);
drop function test_number(integer,number,number[],number);
drop function test_binary_float(integer,binary_float,binary_float[],binary_float);
drop function test_binary_double(integer,binary_double,binary_double[],binary_double);

--the datatype returned by function is table 
create table test(id integer,name varchar(23));

drop function test;
create or replace function test(id out integer) return test as
declare
  var1 test%rowtype;
begin
  id := 1;
  var1.id := 23;
  var1.name := 'thanks';
  return var1;
end;
/

declare
  r test%rowtype;
  var1 integer;
  i int;
begin
  for i in 1 .. 10 LOOP
	r := test(var1);
	raise info 'var1=%,r=%', var1,r;
  end loop;
end;
/

drop function test(integer);
drop table test;


--test domain
create domain domain_type as int check(value < 5);
create domain domain_domain_type as domain_type;

create or replace function test_out(id out domain_domain_type) return integer as
declare
begin
  id := 2;
  return 23;
end;
/

declare
  id domain_domain_type;
  ret integer;
begin
  ret := test_out(id);
  raise notice 'return is %', ret;
  raise notice 'out value is %', id;
end;
/

drop function test_out(domain_domain_type);
drop domain domain_domain_type;
drop domain domain_type;


--datatype of out paramater is table 
create table t_out(d int, t text[]);

create or replace function f1(i out t_out) return text as 
declare
begin
  i.d := 2;
  i.t := '{''1a'',''2b''}'::text[];
  return 'boo';
end;
/

drop function f1(t_out);
drop table t_out;

--out parameter in procedure 
create or replace  procedure p (
  a    integer,  -- IN by default
  b    in integer,
  c    out integer,
  d    in out BINARY_FLOAT
)
as
declare
begin
 -- Print values of parameters:
  raise notice 'Inside procedure p:';
  raise notice 'IN a = %', a;
  raise notice 'IN b = %', b;
  raise notice 'OUT c = %', c;
  raise notice 'IN OUT d =%', d;
  -- it is ok to reference IN parameters a and b,
  -- but cannot assign values to them.
  c := a+10;  -- Assign value to OUT parameter
  d := 40/20;  -- Assign value to IN OUT parameter
end;
/

declare
  aa  CONSTANT integer := 1;
  bb  integer  := 2;
  ee  integer;
  ff  binary_float := 5;
begin
  call p (1,
     (bb+3)*4,
     ee,       -- uninitialized variable
     ff        -- initialized variable
   );

  raise notice 'after procedure p:';
  raise notice 'IN aa = %', aa;
  raise notice 'IN bb = %', bb;
  raise notice 'OUT ee = %', ee;
  raise notice 'IN OUT ff =%' ,ff;
end;
/

drop procedure p(integer, integer, integer, BINARY_FLOAT);

--function out
create or replace function f1 (
  a    integer,  -- IN by default
  b    in integer,
  c    out integer,
  d    in out BINARY_FLOAT
) return int
as
declare
begin
 -- Print values of parameters:
  raise notice 'Inside procedure p:';
  raise notice 'IN a = %', a;
  raise notice 'IN b = %', b;
  raise notice 'OUT c = %', c;
  raise notice 'IN OUT d =%', d;
  -- it is ok to reference IN parameters a and b,
  -- but cannot assign values to them.
  c := a+10;  -- Assign value to OUT parameter
  d := 40/20;  -- Assign value to IN OUT parameter
  return 1;
end;
/

declare
  aa  CONSTANT integer := 1;
  bb  integer  := 2;
  ee  integer;
  ff  binary_float := 5;
  ret integer;
begin
  ret := f1 (1,
     (bb+3)*4,
     ee,       -- uninitialized variable
     ff        -- initialized variable
   );

  raise notice 'after procedure p:';
  raise notice 'IN aa = %', aa;
  raise notice 'IN bb = %', bb;
  raise notice 'OUT ee = %', ee;
  raise notice 'IN OUT ff =%' ,ff;
end;
/

drop function f1(integer, integer, integer, BINARY_FLOAT);

--if function's return type is non-void, the function body must has RETURN statement
--if there is no RETURN statement, the function can be created, but when it is called, 
--an error is raised
create or replace function f2(id integer,price out integer) return varchar 
as
begin
  price := 2;
end;
/

declare
  a varchar(20);
  b int;
begin
  a := f2(1, b);
end;
/

drop function f2(integer, integer);

--test anonymous block with out paramaters
do $$
declare
  a int;
begin
  :x := 1;
  :y := 2;
end; $$ using out, out;

do $$
declare
  id integer;
begin
  id := 1;
  :x := id + 2 + 100;
  :y := :x + 200;
  raise notice 'id=%',id;
end; $$ using out,out;

--test failed
do $$
declare
  id integer;
begin
  id := 1;
  :x := id + 2 + 100;
  :y := :x + 200;
  :z := :x + :y + 12;
raise notice 'id=%',id;
end; $$ using out,out;

--test failed
do $$
declare
  id integer;
begin
  id := 1;
  :x := id + 2 + 100;
  :y := :x + 200;
  raise notice 'id=%',id;
end; $$ using out,out,out;

--test bind by name 
create or replace function test_out(id integer, name out varchar, price out integer) return integer is
begin
  name := 'thanks';
  price := id;
  return 23;
end;
/

set ivorysql.allow_out_parameter_const = true;
set ivorysql.out_parameter_column_position = true;

select * from test_out(23, NULL, NULL);

create or replace function test_out1(id integer, name out varchar, id2 in out integer, price out integer, id3 integer, id4 out integer)
return integer
is
begin
  name := 'thanks';
  price := id;
  id2 := id + 23;
  id4 := id3 + 54;
  return 23;
end;
/

select * from test_out1(23, NULL, 24, NULL, 5, NULL);

set ivorysql.allow_out_parameter_const = false;
set ivorysql.out_parameter_column_position = false;
drop function test_out(integer,varchar, integer);
drop function test_out1(integer, varchar, integer, integer, integer, integer);

--test get_parameter_description function
select * from get_parameter_description('insert into t values(:x,:y)');
select * from get_parameter_description('delete from t where xxx = :xx');
select * from get_parameter_description('update t set t1 = :x and t2 = :y');
select * from get_parameter_description('BEGIN
                          CALL RAISE_SALARY(:emp_number, :new_sal);
                          END;');
select * from get_parameter_description('
 declare
	id integer;
	price integer;
	id1 integer;
	id2 varchar(256);
begin
	insert into test_books(id,id2,name) values(:1,:2,:3);
	id := :1;
	:1 := id * 2 + 1;
	:2 := :1 + 100;
	:3 := ''this is a test ok'';
	:4 := 23;
	execute immediate ''declare books integer; begin books := 1000; :x := books + 100;end;'' using out id;
end;');

--clean data
drop table books;

