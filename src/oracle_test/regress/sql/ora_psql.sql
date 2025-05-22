--
-- Tests for psql features that aren't closely connected to any
-- specific server features.
-- The main features is compatible with Oracle SQL*PLUS client command.
--

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