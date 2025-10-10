--
-- Tests for psql features that aren't closely connected to any
-- specific server features.
-- The main features is compatible with Oracle SQL*PLUS client command.
--

\set EXECUTE_RUN_PREPARE off

--
-- VAR[IABLE] command
--

-- with or without semicolons
variable x number
variable y number;

-- LIST all bind variables
variable

-- list specified bind variables
variable x
variable y;

-- the variable name "x" is already taken by a psql bind variable.
\set x
\set shellvar

-- the variable name "shellvar" is already taken by a psql shell variable.
variable shellvar number

-- Supported datatypes
variable x number
variable x binary_float
variable x binary_double
variable x char
variable x char(100)
variable x char(100 char)
variable x char(100 byte)
variable x nchar(100)
variable x varchar2
variable x varchar2(100)
variable x varchar2(100 char)
variable x varchar2(100 byte)
variable x nvarchar2(100)

-- Bind variable length cannot exceed 2000.
variable x char(2001)
variable x char(2001 char)
variable x char(2001 byte)
variable x nchar(2001)

-- Bind variable length cannot exceed 32767.
variable x varchar2(32768)
variable x varchar2(32768 char)
variable x varchar2(32768 byte)
variable x nvarchar2(32768)

-- Redefine will overwrite the original bind variable
variable x number = 666
variable x
print x

variable x varchar2(20 char) = 'redefine'
variable x
print x

-- Bind variable names must start with a letter
-- SP2-0553: Illegal variable name "xxx".
variable _abc number
variable #abc number
variable $abc number
variable +abc number
variable 1 number
variable 2 number

-- content can include letters, digits, and _ # $
variable a_b number
variable a#b number
variable a$b number
variable a4b number

-- A bind variable name can be a multibyte character
variable 中文 number = 3.14
variable 中文
print 中文

variable a中文b number = 123456
variable a中文b
print a中文b

-- discard the following text when encountering "(" , ")" or ",".
-- SP2-0553: Illegal variable name "a?".
variable a?)xx number
variable a?(xx number
variable a?,xx number

-- SP2-0553: Illegal variable name "?a".
variable ?a)xx number
variable ?a(xx number
variable ?a,xx number

-- character '(' means discard the following string
variable truncate varchar2(30 char) = 'this is a ( truncate!'
variable truncate (it look like a comment)
print truncate

-- character ')' means discard the following string
variable truncate varchar2(30 char) = 'this is a ) truncate!'
variable truncate)ignore
print truncate

-- character ',' means discard the following string
variable truncate varchar2(30 char) = 'this is a , truncate!'
variable truncate,ignore
print truncate

-- correct prompt for invalid variable names
-- SP2-0553: Illegal variable name "a'b".
variable a'b number
-- SP2-0553: Illegal variable name "a"b".
variable a"b number
-- SP2-0553: Illegal variable name "'a'".
variable 'a' number
-- SP2-0553: Illegal variable name ""a"".
variable "a" number
-- SP2-0553: Illegal variable name "a'b'".
variable a'b' number
-- SP2-0553: Illegal variable name "a"b"".
variable a"b" number

-- error, issue a usage
variable a ?
variable a a

-- allow preceding comments
-- ok
/*123*/variable comment number=123
/* /* */ variable comment number=123

-- psql keywords as variable name
variable BINARY_DOUBLE number
variable BINARY_FLOAT number
variable BYTE number
variable CHAR number
variable NCHAR number
variable NUMBER number
variable NVARCHAR2 number
variable VARCHAR2 number
variable VARIABLE number
variable PRINT number
-- list all
variable

-- nls_length_semantics
alter session set nls_length_semantics = 'byte';
variable a char(10)
variable b varchar2(10)
variable c nvarchar2(10)
alter session set nls_length_semantics = 'char';
variable a
variable b
variable c

variable aa char(10)
variable bb varchar2(10)
variable cc nvarchar2(10)
alter session set nls_length_semantics = 'byte';
variable aa
variable bb
variable cc

-- Initialization
-- Both single and double quotes are supported.
variable x varchar2(10)='123'
print x
variable x varchar2(10)="12345"
print x

-- Initial value errors do not affect the success of bind variable creation.
-- SP2-0425: "abc" is not a valid NUMBER
variable fail number=abc
variable fail
print fail

-- Support extended quote(i.e. double writing)
variable x varchar2(10)=''''
print x
variable x varchar2(10)=""""
print x
variable x varchar2(10)=a b c
print x
variable x varchar2(10)= a b c
print x
variable x varchar2(10)='a b c'
print x
variable x varchar2(10)=' a b c'
print x
variable x varchar2(10)='a' 'b' 'c'
print x
variable x varchar2(10)='12'x'
print x

-- string "'12''" missing terminating quote (').
variable x varchar2(10)='12''
-- string "'12''345" missing terminating quote (').
variable x number='12''345
-- string ""12""345" missing terminating quote (").
variable x number="12""345
-- string "'12'' 23" missing terminating quote (').
variable x number='12'' 23
-- string ""12"" 23" missing terminating quote (").
variable x number="12"" 23

-- SP2-0425: "12'345" is not a valid NUMBER 
variable x number='12''345'
-- OK, space is separator
variable x number='12' '345'
print x

-- Invalid error message content for each data type
-- SP2-0425: "abc" is not a valid NUMBER
variable v1 number='abc'
-- SP2-0425: "abc" is not a valid BINARY_FLOAT
variable v2 binary_float='abc'
-- SP2-0425: "abc" is not a valid BINARY_DOUBLE
variable v3 binary_double='abc'
-- SP2-0631: String beginning "abcd" is too long
variable v4 varchar2(3)='abcd'
variable v4 char(3)='abcd'

-- oracle is success, but error when PRINT.
-- well, I think it may be a flaw of Oracle, 
-- we keep reporting errors.
variable v4 nchar(3)='abcd'
variable v4 nvarchar2(3)='abcd'

-- SP2-0306: Invalid option.
-- Usage: VAR[IABLE] <variable> [type][= value]
variable aaa number=

--
-- assign value
--
variable a number = 999
print a
variable a = 123
print a
variable a = 345
print a
-- SP2-0425: "abc" is not a valid NUMBER
variable a = 'abc'

-- SP2-0553: Illegal variable name "a'b".
variable a'b = 123

-- SP2-0552: Bind variable "noexist" not declared.
variable noexist = 123

-- SP2-1657: Variable assignment requires a value following equal sign.
-- Usage: VAR[IABLE] <variable> [type][= value]
variable a =

-- SP2-0553: Illegal variable name "a?a".
variable a?a =
variable a?a number =   

variable a varchar2(3)='qqq'
print a
-- SP2-0631: String beginning "qqqqqq" is too long
variable a = 'qqqqqq'
-- string "'qqqqqq" missing terminating quote (').
variable a = 'qqqqqq
-- string ""qqqqqq" missing terminating quote (").
variable a = "qqqqqq

-- VARIABLE can be abbreviated as VAR
var my char(4) = '123'
print my
var my = '1234';
print my
var my = '12345'
print my
var

--
-- PRINT command
--
variable v1 number = 3.14
variable v2 binary_float = 3.14
variable v3 binary_double = 3.14
variable v4 varchar2(10) = varchar2;
variable v5 char(10) = char

-- ok
print v1
print v3 v5
print

-- SP2-0552: Bind variable "NOEXIST" not declared.
-- v1 and v2 was successfully printed.
print v1 noexist v2

-- invalid host/bind variable name.
print v1 a'b v2

-- For a'b, an error is reported when the bind variable 'a' is not exits:
--	SP2-0552: Bind variable "A" not declared. 
-- But when we declare the bind variable 'a' and execute it repeatedly, an error will be reported:
--	ORA-00923: FROM keyword not found where expected
-- Therefore, I think Oracle may parse a'b into an alias clause, 'a' is the target entry, 'b' is its alias,
-- PRINT is just a client command, there is no alias syntax in SQL,  so I think Oracle's error message is
-- not accurate enough, My error report here is not going to be completely consistent with Oracle, but should
-- be consistent with the VARIABLE a'b , that is, an error is reported: invalid host/bind variable name.
print a'b
print a"b

-- Unlike Oracle, these two syntaxes are the same
print a'b'
print a 'b'

-- Unlike Oracle, these two syntaxes are the same
print a "b"
print a"b"

--
-- Referencing bind variables
--
-- Referencing bind variables within anonymous blocks.
variable v1 number = 123
variable v2 binary_float = 3.14
variable v3 binary_double = 3.1415926
variable v4 char = 't'
variable v5 char(100) = 'this is char(100) datatype'
variable v6 char(100 char) = 'this is char(100 char) datatype'
variable v7 char(100 byte) = 'this is char(100 byte) datatype'
variable v8 nchar(100) = 'this is nchar(100) datatype'
variable v9 varchar2 = 't'
variable v10 varchar2(100) = 'this is varchar2(100) datatype'
variable v11 varchar2(100 char) = 'this is varchar2(100 char) datatype'
variable v12 varchar2(100 byte) = 'this is varchar2(100 byte) datatype'

-- can be used as an lvalue or an rvalue
declare
lval1 number;
lval2 binary_float;
lval3 binary_double;
lval4 char;
lval5 char(100);
lval6 char(100 char);
lval7 char(100 byte);
lval8 nchar(100);
lval9 varchar2;
lval10 varchar2(100);
lval11 varchar2(100 char);
lval12 varchar2(100 byte);
begin
raise notice 'old value of v1 is %', :v1;
raise notice 'old value of v2 is %', :v2;
raise notice 'old value of v3 is %', :v3;
raise notice 'old value of v4 is %', :v4;
raise notice 'old value of v5 is %', :v5;
raise notice 'old value of v6 is %', :v6;
raise notice 'old value of v7 is %', :v7;
raise notice 'old value of v8 is %', :v8;
raise notice 'old value of v9 is %', :v9;
raise notice 'old value of v10 is %', :v10;
raise notice 'old value of v11 is %', :v11;
raise notice 'old value of v12 is %', :v12;

lval1 := :v1;
lval2 := :v2;
lval3 := :v3;
lval4 := :v4;
lval5 := :v5;
lval6 := :v6;
lval7 := :v7;
lval8 := :v8;
lval9 := :v9;
lval10 := :v10;
lval11 := :v11;
lval12 := :v12;

:v1 := 3.141592657;
:v2 := 3.141592657;
:v3 := 3.141592657;
:v4 := 'f';
:v5 := 'new value = ' || :v5;
:v6 := 'new value = ' || :v6;
:v7 := 'new value = ' || :v7;
:v8 := 'new value = ' || :v8;
:v9 := 'f';
:v10 := 'new value = ' || :v10;
:v11 := 'new value = ' || :v11;
:v12 := 'new value = ' || :v12;

raise notice 'new value of v1 is %', :v1;
raise notice 'new value of v2 is %', :v2;
raise notice 'new value of v3 is %', :v3;
raise notice 'new value of v4 is %', :v4;
raise notice 'new value of v5 is %', :v5;
raise notice 'new value of v6 is %', :v6;
raise notice 'new value of v7 is %', :v7;
raise notice 'new value of v8 is %', :v8;
raise notice 'new value of v9 is %', :v9;
raise notice 'new value of v10 is %', :v10;
raise notice 'new value of v11 is %', :v11;
raise notice 'new value of v12 is %', :v12;

raise notice 'the value of local variable is %', lval1;
raise notice 'the value of local variable is %', lval2;
raise notice 'the value of local variable is %', lval3;
raise notice 'the value of local variable is %', lval4;
raise notice 'the value of local variable is %', lval5;
raise notice 'the value of local variable is %', lval6;
raise notice 'the value of local variable is %', lval7;
raise notice 'the value of local variable is %', lval8;
raise notice 'the value of local variable is %', lval9;
raise notice 'the value of local variable is %', lval10;
raise notice 'the value of local variable is %', lval11;
raise notice 'the value of local variable is %', lval12;
end;
/
print v1
print v2
print v3
print v4
print v5
print v6
print v7
print v8
print v9
print v10
print v11
print v12

-- error out of range
var x char(3 byte) = 'abc'
print x

var x char(3 char) = '数据库'
print x

begin
raise notice 'old value of :x is %', :x;
:x := '瀚高集团';
raise notice 'new value of :x is %', :x;
end;
/

print x

-- catch exception
begin
raise notice 'old value of :x is %', :x;
:x := '瀚高集团';
EXCEPTION WHEN OTHERS THEN
	raise notice 'Get an exception and reassign an acceptable value to the bind variable';
	:x := '瀚高';
raise notice 'new value of :x is %', :x;
end;
/

print x

-- Referencing bind variables within non-anonymous block queries
var x number = 4
var y char(20) = 'bindvar_test'
var z char(20) = 'select'
var m number = 999
var n char(5) = '888'
print x
print y
print z
print m
print n

create table bindvar_test(a number);
insert into bindvar_test values(1);
insert into bindvar_test values(2);
insert into bindvar_test values(3);
insert into bindvar_test values(4);
insert into bindvar_test values(5);
select * from bindvar_test;
-- ok
select * from bindvar_test where a = :x;

-- ok
insert into bindvar_test values(:m);
insert into bindvar_test values(:n);
select * from bindvar_test;

-- ok
delete from bindvar_test where a = :x;
select * from bindvar_test;

-- error, cannot use input host variables to supply SQL keywords or the names of database objects or data definition statements. 
select * from :y;
:z * from bindvar_test;
drop table :y;
drop table bindvar_test;

-- Referencing bind variables in functions or procedures as input or output host variable.
var x number=10
var y number=20
var z char(6)='input'

CREATE OR REPLACE FUNCTION f_test (x NUMBER, y OUT NUMBER, z OUT char) return int AS
BEGIN
raise info '%', x;
raise info '%', y;
raise info '%', z;
y := x;
z := 'output';
raise info '%', x;
raise info '%', y;
raise info '%', z;
return 999;
END;
/

-- error out within Oracle: ORA-06572: Function F_TEST has out arguments.
-- error out within IvorySQL: ERROR:  OUT or IN OUT arguments of the funtion f_test must be variables.
select f_test(:x, :y, :z) from dual;

-- error out within Oracle: ORA-06572: Function F_TEST has out arguments.
-- IvorySQL can execute successfully. Will be changed in the future?
select * from f_test(:x, :y, :z);
print x
print y
print z

-- CALL statement
exec :x := 3.14
exec :z := 'any'
CREATE OR REPLACE PROCEDURE p_test (x NUMBER, y IN OUT NUMBER, z OUT char) AS
BEGIN
raise info '%', x;
raise info '%', y;
raise info '%', z;
y := x;
z := 'output';
raise info '%', x;
raise info '%', y;
raise info '%', z;
END;
/

call p_test(:x, :y, :z);
print x
print y
print z

--clean
drop function f_test;
drop procedure p_test;

--
-- EXECUTE
--
var x number;
print x

-- there is not necessarily a space after exec.
exec:x := 111;
print x

exec:x := 222
print x

exec :x := 333;
print x

exec :x := 444
print x

-- Usage: EXEC[UTE] statement
exec
execute
/* Comments and whitespace are ignored */exec
/* Comments and whitespace are ignored */ execute

-- An error is reported on overflow

var x char(3 char)
exec :x := '数据库';
print x
exec :x := '数据库1';
print x

var x varchar2(3 char)
exec :x := '数据库';
print x
exec :x := '数据库1';
print x

var x number
exec :x := '3.14'
print x
exec :x := 'abc'
print x

-- host variable not exist
exec :nohostvar := '123'
