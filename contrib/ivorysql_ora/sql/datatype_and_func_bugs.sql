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

--
-- Bug #2299: bounds-check multibyte decoding on truncated input.
--
-- A byte-length CHAR cast can split a UTF-8 character, leaving a legal text
-- datum that ends in a truncated multibyte sequence.  The trim paths below
-- must report an invalid byte sequence instead of reading past the end of
-- that datum.  (The to_single_byte() and substrb() halves of the report are
-- addressed separately.)
--
-- rtrim/ltrim/trim: truncated input compared against a set
select rtrim(convert_from('\xe4bda0'::bytea, 'UTF8')::sys.oracharbyte(1), '你');
select ltrim(convert_from('\xe4bda0'::bytea, 'UTF8')::sys.oracharbyte(1), '你');
select trim(convert_from('\xe4bda0'::bytea, 'UTF8')::sys.oracharbyte(1), '你');
select rtrim(convert_from('\xf09f9880'::bytea, 'UTF8')::sys.oracharbyte(3), '😀');
-- a byte-length cut on a character boundary still trims normally
select rtrim(convert_from('\x41e4bda0'::bytea, 'UTF8')::sys.oracharbyte(4), '你');
