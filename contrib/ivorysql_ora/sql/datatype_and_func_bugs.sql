--
-- Mainly contains bug-modified test cases for built-in datatypes and built-in functions.
--

create table dtos_tb1tidid004134318(dtos_clo interval day to second);
insert into dtos_tb1tidid004134318 values(interval '--2 07:16:23' day to second);
insert into dtos_tb1tidid004134318 values(interval ' 2 07:16:23' day to second);
insert into dtos_tb1tidid004134318 values(interval ' -2 07:16:23' day to second);
select * from dtos_tb1tidid004134318;
CREATE FUNCTION f_noparam() 
RETURN int 
IS 
BEGIN  
RETURN 1; 
END;
/

alter session set NLS_DATE_FORMAT='yyyy-mm-dd hh24:mi:ss';
select add_months('2022-08-23',3) from dual;
alter session set NLS_LENGTH_SEMANTICS='BYTE';
create table char_tb(char_clo char(3));
insert into char_tb values('测试');
alter session set NLS_LENGTH_SEMANTICS='CHAR';
create table char_tb2(char_clo char(3));
insert into char_tb2 values('测试');
create schema s1;
create function s1.f_alter(arg1 number)
return int
is
begin
return 1;
end;
/

create function s1.f_alter(arg1 number, arg2 number)
return int
is
begin
return 1;
end;
/

create function s1.f_alter(arg1 OUT int)
return number
is
begin
return;
end;
/

create function s1.f_alter(arg1 text)
return int
is
begin
return 1;
end;
/

create function s1.f_alter(arg1 number, arg2 number, arg3 number default 10)
return int
is
begin
return 1;
end;
/

alter function s1.f_alter compile;
alter function s1.f_alter(arg1 number) compile;
alter function s1.f_alter(arg1 number, arg2 number) compile;
alter function s1.f_alter(arg1 OUT int) compile;
alter function s1.f_alter(arg1 text) compile;
alter function s1.f_alter(arg1 number, arg2 number, arg3 number default 10) compile;
alter function s1.f_alter(arg1 number, arg2 number, arg3 number) compile;

-- OID comparisons ignore leading zeroes, including the all-zero value.
select 0::oid = cast('000' as char(3 char));
select cast('000' as char(3 char)) = 0::oid;
select not (0::oid <> cast('000' as char(3 char)));
select not (cast('000' as char(3 char)) <> 0::oid);

-- The comparison helpers are deterministic and safe for planner use.
select count(*) = 4 as oid_char_comparisons_are_immutable
from pg_catalog.pg_proc
where oid = any (array['sys.oid_cc_eq(oid,sys.oracharchar)'::regprocedure,
                       'sys.cc_oid_eq(sys.oracharchar,oid)'::regprocedure,
                       'sys.oid_cc_ne(oid,sys.oracharchar)'::regprocedure,
                       'sys.cc_oid_ne(sys.oracharchar,oid)'::regprocedure])
  and provolatile = 'i'
  and proisstrict
  and proparallel = 's';
-- clean
drop table dtos_tb1tidid004134318;
drop table char_tb2;
drop table char_tb;
drop function f_noparam();
drop function s1.f_alter(arg1 number);
drop function s1.f_alter(arg1 number, arg2 number);
drop function s1.f_alter(arg1 OUT int);
drop function s1.f_alter(arg1 text);
drop function s1.f_alter(arg1 number, arg2 number, arg3 number);
