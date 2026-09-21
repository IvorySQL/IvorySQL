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

-- A month outside 1..12 must not be used to index day_tab.  The DCH_MM bounds
-- check is gated on the Oracle parser, so only a PG-parser session reaches
-- final_datetime_check() with an unvalidated month -- that is where day_tab
-- was read out of bounds, and where out->mm - 1 overflowed for INT_MIN.
set ivorysql.compatible_mode = pg;
select '2000--2147483648-01'::sys.oradate;
select '2000-999999-01'::sys.oradate;
select '2000--2147483648-01 00:00:00.000000'::sys.oratimestamp;
select '2000--2147483648-01 00:00:00.000000 +00:00'::sys.oratimestamptz;
select '2000--2147483648-01 00:00:00.000000'::sys.oratimestampltz;
-- an out-of-range month is still rejected, with the PG parser's own message
select '2000-99-01'::sys.oradate;
-- the day check for a valid month must keep working
select '2001-02-29'::sys.oradate;
select '2000-02-29'::sys.oradate;
