--
-- PLISQL
--

-- return is a non-reserved keyword, can be used as object name.
CREATE TABLE RETURN (fooid INT, foosubid INT, fooname TEXT);
INSERT INTO RETURN VALUES (1, 2, 'three');
INSERT INTO RETURN VALUES (4, 5, 'six');
SELECT * FROM RETURN;

-- Creating a parameterless function cannot have an empty parenthesis.
-- FAILED
CREATE or replace FUNCTION ora_func() RETURN integer AS
BEGIN    
    RETURN 1;
END;
/

-- OK
CREATE or replace FUNCTION ora_func RETURN integer AS
BEGIN    
    RETURN 1;
END;
/
select ora_func() from dual;

-- NOCOPY.
CREATE OR REPLACE FUNCTION test_nocopy(a IN int, b OUT NOCOPY int, c IN OUT NOCOPY int) 
RETURN int
IS
BEGIN 
   b := a;
   c := a; 
   return 1;
END;
/

-- The outermost DECLARE block of a function does not have the DECLARE keyword.
CREATE OR REPLACE
FUNCTION ora_func (num1 IN int, num2 IN int)
RETURN int
AS
 num3 int :=10;
 num4 int :=10;
 num5 int;
BEGIN
 num3 := num1 + num2;
 num4 := num1 * num2;
 num5 := num3 * num4;
RETURN num5;
END;
/

select ora_func(5,9)from dual;

-- IS keyword
CREATE or replace EDITIONABLE FUNCTION ora_func RETURN integer IS
BEGIN    
    RETURN 1;
END;
/

--
-- Only syntactically compatible and do not implement functionality. 
-- therefore the identifiers and objects etc used in these only syntactically 
-- compatible clauses are dummy.
--

-- EDITIONABLE
CREATE or replace EDITIONABLE FUNCTION ora_func RETURN integer IS
BEGIN    
    RETURN 1;
END;
/

-- NONEDITIONABLE
CREATE or replace NONEDITIONABLE FUNCTION ora_func RETURN integer IS
BEGIN    
    RETURN 1;
END;
/

-- sharing_clause
CREATE or replace FUNCTION ora_func RETURN integer
SHARING = METADATA
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE
IS
BEGIN    
    RETURN 1;
END;
/

-- invoker_rights_clause
CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID CURRENT_USER
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
IS
BEGIN    
    RETURN 1;
END;
/

-- accessible_by_clause
CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER ACCESSIBLE BY ( B )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER ACCESSIBLE BY ( A.B )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER ACCESSIBLE BY ( FUNCTION A.B )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D, PACKAGE E,
TRIGGER F, TYPE G )
IS
BEGIN    
    RETURN 1;
END;
/

-- default_collation_clause
CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
IS
BEGIN    
    RETURN 1;
END;
/

-- deterministic_clause
CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
IS
BEGIN    
    RETURN 1;
END;
/

-- parallel_enable_clause
CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY ANY )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY VALUE ( B ) )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY HASH ( B, C ) )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY HASH ( B, C ) ORDER A BY ( E,F ) )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY HASH ( B, C ) CLUSTER A BY ( E,F ) )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) ORDER A BY ( E,F ) )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
IS
BEGIN    
    RETURN 1;
END;
/

-- result_cache_clause
CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ()
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
IS
BEGIN    
    RETURN 1;
END;
/

-- aggregate_clause
CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING pg_catalog.int4
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING int
IS
BEGIN    
    RETURN 1;
END;
/

-- pipelined_clause
CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING int
PIPELINED
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING int
PIPELINED USING pg_catalog.int4
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING int
PIPELINED ROW POLYMORPHIC
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING int
PIPELINED ROW POLYMORPHIC USING pg_catalog.int4
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING int
PIPELINED TABLE POLYMORPHIC USING pg_catalog.int4
IS
BEGIN    
    RETURN 1;
END;
/

-- sql_macro_clause
CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING int
PIPELINED TABLE POLYMORPHIC USING pg_catalog.int4
SQL_MACRO 
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING int
PIPELINED TABLE POLYMORPHIC USING pg_catalog.int4
SQL_MACRO ( scalar )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING int
PIPELINED TABLE POLYMORPHIC USING pg_catalog.int4
SQL_MACRO ( type => scalar )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING int
PIPELINED TABLE POLYMORPHIC USING pg_catalog.int4
SQL_MACRO ( table )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE or replace FUNCTION ora_func RETURN integer
SHARING = NONE AUTHID DEFINER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
DEFAULT COLLATION USING_NLS_COMP
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
RESULT_CACHE RELIES_ON ( data_source1, data_source2)
AGGREGATE USING int
PIPELINED TABLE POLYMORPHIC USING pg_catalog.int4
SQL_MACRO ( type => table )
IS
BEGIN    
    RETURN 1;
END;
/

--
-- procedure
--

-- The outermost DECLARE block of a procedure does not have the DECLARE keyword.
CREATE OR REPLACE PROCEDURE ora_procedure()
AS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

call ora_procedure();

-- IS keyword
CREATE OR REPLACE PROCEDURE ora_procedure
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

-- EDITIONABLE
CREATE OR REPLACE EDITIONABLE PROCEDURE ora_procedure
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

-- NONEDITIONABLE
CREATE OR REPLACE NONEDITIONABLE PROCEDURE ora_procedure
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

-- sharing_clause 
CREATE OR REPLACE PROCEDURE ora_procedure
SHARING = METADATA
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

CREATE OR REPLACE PROCEDURE ora_procedure
SHARING = NONE
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

-- default_collation_clause
CREATE OR REPLACE PROCEDURE ora_procedure
SHARING = METADATA
DEFAULT COLLATION USING_NLS_COMP
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

-- invoker_rights_clause
CREATE OR REPLACE PROCEDURE ora_procedure
SHARING = METADATA
DEFAULT COLLATION USING_NLS_COMP
AUTHID CURRENT_USER
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

CREATE OR REPLACE PROCEDURE ora_procedure
SHARING = METADATA
DEFAULT COLLATION USING_NLS_COMP
AUTHID DEFINER
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

-- accessible_by_clause
CREATE OR REPLACE PROCEDURE ora_procedure
SHARING = METADATA
DEFAULT COLLATION USING_NLS_COMP
AUTHID CURRENT_USER
ACCESSIBLE BY ( B )
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

CREATE OR REPLACE PROCEDURE ora_procedure
SHARING = METADATA
DEFAULT COLLATION USING_NLS_COMP
AUTHID CURRENT_USER
ACCESSIBLE BY ( A.B )
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

CREATE OR REPLACE PROCEDURE ora_procedure
SHARING = METADATA
DEFAULT COLLATION USING_NLS_COMP
AUTHID CURRENT_USER
ACCESSIBLE BY ( FUNCTION A.B )
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

CREATE OR REPLACE PROCEDURE ora_procedure
SHARING = METADATA
DEFAULT COLLATION USING_NLS_COMP
AUTHID CURRENT_USER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D )
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

CREATE OR REPLACE PROCEDURE ora_procedure
SHARING = METADATA
DEFAULT COLLATION USING_NLS_COMP
AUTHID CURRENT_USER
ACCESSIBLE BY ( FUNCTION A.B, PROCEDURE C.D, PACKAGE E, TRIGGER F, TYPE G )
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

--
-- clean
--
DROP TABLE RETURN;
DROP FUNCTION ora_func();
DROP FUNCTION test_nocopy(a IN int, b OUT NOCOPY int, c IN OUT NOCOPY int);
DROP PROCEDURE ora_procedure();

--test alter function compile or editionable
create or replace function test_func(id integer) return integer is
var1 integer;
begin
  var1 := 23;
  return var1 + 2;
end;
/

create or replace function test_pg_func(id integer) returns integer as $$
begin
  return 23;
end;
$$ LANGUAGE PLPGSQL;
/

alter function test_func editionable;
alter function public.test_func noneditionable;
alter function test_func compile;
alter function test_func compile debug;
alter function test_func compile debug sd = mv;
alter function test_func compile debug reuse settings;

-----alter pg function
alter function test_pg_func editionable;
alter function public.test_pg_func noneditionable;
alter function public.test_pg_func compile;
alter function public.test_pg_func compile debug;
alter function public.test_pg_func compile debug sd = mv;
alter function public.test_pg_func compile debug reuse settings;

--drop function
drop function test_func(integer);
drop function test_pg_func(integer);

--test alter procedure compile or editionable
create or replace procedure test_proc(id integer) is
  var1 integer := 10;
begin
  RAISE NOTICE 'in test_proc, var1 = %', var1;
end;
/

create or replace procedure test_pg_proc(id integer) AS $$
declare
  var1 integer := 20;
begin
  raise notice 'in test_pg_proc, var1 = %', var1;
end;
$$ LANGUAGE plpgsql;
/

alter procedure test_proc editionable;
alter procedure public.test_proc noneditionable;
alter procedure test_proc compile;
alter procedure test_proc compile debug;
alter procedure test_proc compile debug sd = mv;
alter procedure test_proc compile debug reuse settings;

-----alter pg procedure
alter procedure test_pg_proc editionable;
alter procedure public.test_pg_proc noneditionable;
alter procedure public.test_pg_proc compile;
alter procedure public.test_pg_proc compile debug;
alter procedure public.test_pg_proc compile debug sd = mv;
alter procedure public.test_pg_proc compile debug reuse settings;

--drop procedure
drop function test_proc;--error
drop procedure test_proc;
drop procedure test_pg_proc(integer);

--
-- Oracle anonymous block
--
begin
null;
end;
/

declare
begin
null;
end;
/

<<main>>
begin
null;
end;
/


<<main>>
declare
begin
null;
end;
/


<<main>>
declare
i integer := 10;
begin
 raise notice '%', i;
 raise notice '%', main.i;
end;
/

<<main>>
i integer := 10;
begin
 raise notice '%', i;
 raise notice '%', main.i;
end;
/

<< main >>
begin
null;
end;
/

<<
main >>
begin
null;
end;
/

<<
main
>>
begin
null;
end;
/

declare
i integer := 10;
begin
 raise notice '%', i;
end;
/

DECLARE
  grade CHAR(1);
BEGIN
  grade := 'B';

  CASE grade
    WHEN 'A' THEN raise notice 'Excellent';
    WHEN 'B' THEN raise notice 'Very Good';
  END CASE;
EXCEPTION
  WHEN CASE_NOT_FOUND THEN
    raise notice 'No such grade';
END;
/

declare
"a b c end; " text;
a_output text;
begin
"a b c end; " := ' end;  ';
raise notice '%', "a b c end; ";

a_output := "a b c end; ";
raise notice '%', a_output;

a_output := '''end;''';
raise notice '%', a_output;

a_output := '''''end;''''';
raise notice '%', a_output;
a_output := 'end;
'' '''' ''''''
''
''''
''''''
"
end;   ';
raise notice '%', a_output;
end;
/

--
-- Compatible with Oracle:
-- Parentheses can be omitted when calling parameterless functions
--
create or replace function f_noparentheses
return int is
begin
return 11;
end;
/

create table t_noparentheses(f_noparentheses int);
insert into t_noparentheses values(123);
select f_noparentheses from t_noparentheses;

-- When the function name and the column name are the same, we preferentially resolve to the column name.
select f_noparentheses from dual;
select f_noparentheses from t_noparentheses;

CREATE OR REPLACE FUNCTION test_func RETURN integer
AUTHID DEFINER
DETERMINISTIC
PARALLEL_ENABLE ( PARTITION A BY RANGE ( B, C ) CLUSTER A BY ( E,F ) )
IS
BEGIN    
    RETURN 1;
END;
/

CREATE OR REPLACE PROCEDURE test_proc
AUTHID CURRENT_USER
IS
	p integer := 20;   
begin
	raise notice '%', p;
end;
/

-- nested subproc of plisql
create or replace function test_subproc_func(a in out integer) returns integer as
$$
declare
  mds integer;
  original integer;
  function square(original in out integer) return integer;
  function square(original in out integer) return integer
  AS
  declare
       original_squared integer;
  begin
       original_squared := original * original;
       original := original_squared + 1;
       return original_squared;
   end;
begin
    mds := 10;
    original := square(mds);
    raise info '%',original;
    a := original + 1;
    return mds;
end;$$ language plisql;
/

-- pg_get_functiondef
SELECT pg_get_functiondef('test_func'::regproc) from dual;
SELECT pg_get_functiondef('test_proc'::regproc) from dual;
SELECT pg_get_functiondef('test_subproc_func'::regproc) from dual;

-- ivy_get_plisql_functiondef is only used to get plisql func/proc definition.
SELECT ivy_get_plisql_functiondef('test_func'::regproc) from dual;
SELECT ivy_get_plisql_functiondef('test_proc'::regproc) from dual;
SELECT ivy_get_plisql_functiondef('test_subproc_func'::regproc) from dual;

DROP PROCEDURE test_proc();
DROP FUNCTION test_func();
DROP FUNCTION test_subproc_func(int);

--
-- Compatible with Oracle:
-- The input parameter type is %rowtype
--
create or replace procedure protest 
as 
begin
raise notice 'protest';
end;
/ 

CALL protest;  -- should failed 
CALL protest();
exec protest;      
exec protest();
drop  procedure protest ;

create or replace procedure procedure_addtest (a int, b int)
as 
begin 
raise notice 'a + b = %', a + b;
end;
/ 

exec procedure_addtest(12,13);
drop procedure procedure_addtest;

--
-- Tests for procedures / exec syntax
--
CREATE or replace PROCEDURE test_proc1
AS 
BEGIN
    NULL;
END;
/

CALL test_proc1;  -- should failed 
CALL test_proc1();
EXEC test_proc1;   
EXEC test_proc1();
DROP PROCEDURE test_proc1;

CREATE TABLE test1 (a int);
CREATE OR REPLACE PROCEDURE test_proc3(x int)
AS 
BEGIN
    INSERT INTO test1 VALUES (x);
END;
/

EXEC test_proc3(55);
SELECT * FROM test1;


-- nested CALL
TRUNCATE TABLE test1;
CREATE or replace PROCEDURE test_proc4(y int)
AS
BEGIN
     test_proc3(y);
     test_proc3($1);
END;
/

EXEC test_proc4(66);
SELECT * FROM test1;

EXEC test_proc4(66);
SELECT * FROM test1;
DROP PROCEDURE test_proc3;
DROP PROCEDURE test_proc4;
DROP TABLE test1;

-- output arguments
CREATE or replace PROCEDURE test_proc5(INOUT a text)
AS 
BEGIN
    a := a || '+' || a;
END;
/

CALL test_proc5('abc');
EXEC test_proc5('abc');
DROP PROCEDURE test_proc5;

CREATE or replace PROCEDURE test_proc6(a int, INOUT b int, INOUT c int)
AS 
BEGIN
    b := b * a;
    c := c * a;
END;
/

CALL test_proc6(2, 3, 4);
EXEC test_proc6(2, 3, 4);
DROP PROCEDURE test_proc6;
-- recursion with output arguments

CREATE OR REPLACE PROCEDURE test_proc7(x int, INOUT a int, INOUT b numeric)
AS
BEGIN
IF x > 1 THEN
    a := x / 10;
    b := x / 2;
     test_proc7(b::int, a, b);
END IF;
END;
/

CALL test_proc7(100, -1, -1);
EXEC test_proc7(100, -1, -1);
DROP PROCEDURE test_proc7;

CREATE OR REPLACE PROCEDURE test_proc8a(INOUT a int, INOUT b int)
AS 
BEGIN
  RAISE NOTICE 'a: %, b: %', a, b;
  a := a * 10;
  b := b + 10;
END;
/

EXEC test_proc8a(10, 20);
EXEC test_proc8a(b => 20, a => 10);
DROP PROCEDURE test_proc8a;

CREATE OR REPLACE PROCEDURE test_proc8b( a  int,  b  int)
AS 
va int;
vb int;
BEGIN
  va := a * 10;
  vb := b + 10;
  raise notice '% %', va, vb;
END;
/
EXEC test_proc8b(100, 200);
EXEC test_proc8b(b => 200, a => 100);
DROP PROCEDURE test_proc8b;


CREATE OR REPLACE PROCEDURE test_proc8c(a  int,  b  int default 200)
AS 
va varchar2(50);
vb varchar2(50);
BEGIN
  va := a * 10;
  vb := b + 10;
   raise notice '% %', va, vb;
END;
/
EXEC test_proc8c(10);
EXEC test_proc8c(100, 500);
EXEC test_proc8c(b => 500, a => 100);
DROP PROCEDURE test_proc8c;


-- add test 
CREATE OR REPLACE PROCEDURE protest 
AS 
BEGIN 
raise notice 'protest';
END;
/

-- function
CREATE OR REPLACE FUNCTION functest()
RETURN INT4
AS 
BEGIN
protest();  -- No need to write "CALL" anymore.
raise notice 'functest';
RETURN 25;
END;
/

SELECT functest();
DROP FUNCTION functest;

-- procedure
CREATE OR REPLACE PROCEDURE protest2
AS
BEGIN 
protest();          -- No need to write "CALL" anymore.
raise notice 'protest2';
END;
/

CALL protest2();

DROP PROCEDURE  protest2;
DROP PROCEDURE  protest;

-- schema.procedure
CREATE SCHEMA stest;
CREATE OR REPLACE PROCEDURE stest.protest 
AS 
BEGIN 
raise notice 'stest.protest';
END;
/

-- function
CREATE OR REPLACE FUNCTION functest2()
RETURN INT4
AS 
BEGIN
stest.protest();  -- No need to write "CALL" anymore.
raise notice 'functest2';
RETURN 25;
END;
/

SELECT functest2();
DROP FUNCTION functest2;

-- procedure
CREATE OR REPLACE PROCEDURE protest2
AS
BEGIN 
stest.protest();          -- No need to write "CALL" anymore.
raise notice 'protest2';
END;
/

CALL protest2();

DROP PROCEDURE  protest2;
DROP PROCEDURE  stest.protest;
-- An empty parenthesis cannot be ignored
create or replace procedure p_noarg()
is
begin
raise notice 'this procedure without args';
end;
/

-- fail
call p_noarg;

--ok
call p_noarg();

create or replace function f_noarg()
return number
is
begin
raise notice 'this function without args';
return 999;
end;
/

variable x number;

-- fail
call f_noarg into :x;

--ok
call f_noarg() into :x;
print x

-- function or procedure with default value
create or replace procedure p_defs(a varchar2 default 'i am a default string')
is
begin
raise notice '%', a;
end;
/

-- fail
call p_defs;

-- ok
call p_defs();
--ok
call p_defs('new string');

create or replace function f_defs(a number default 1314)
return number
is
begin
raise notice '%', a;
return a;
end;
/

variable x number

--fail
call f_defs into :x;

--ok
call f_defs() into :x;
print x

--ok
call f_defs(999) into :x;
print x

drop function f_defs;
drop procedure p_defs;
drop function f_noarg();
drop procedure p_noarg();

--
-- Truncate when the bind variable and the function return type or param type
-- are the same and the typmod of the bind variable overflows.
-- Fails when the bind variable and the function return type are or param type
-- not same but can cast and the typmod of the bind variable overflows.
--
create or replace procedure ff_proc(a varchar2, b varchar2)
is
begin
raise notice '%', a;
raise notice '%', b;
raise notice '%', a||b;
end;
/

-- ok
call ff_proc('123456789', '123456789');

create or replace function ff_test(a varchar2, b varchar2)
return varchar2
is
begin
raise notice '%', a;
raise notice '%', b;
return a||b;
end;
/

-- ok
variable x varchar2(10 char);
call ff_test('123456789', '123456789') into :x;
print x

-- ok
variable x varchar2(10 byte);
call ff_test('123456789', '123456789') into :x;
print x

-- error
variable x char(10 char);
call ff_test('123456789', '123456789') into :x;
print x

-- error
variable x char(10 byte);
call ff_test('123456789', '123456789') into :x;
print x

-- ok
variable x number;
call ff_test('123456789', '123456789') into :x;
print x

-- error
variable x number;
call ff_test('abc', '123456789') into :x;
print x

create or replace procedure f_proc(a varchar2, b out varchar2)
is
begin
raise notice '%', a;
raise notice '%', b;
b := a;
end;
/

-- ok
variable x varchar2(5 char)
call f_proc('123456789', :x);
print

-- ok
variable x varchar2(5 byte)
call f_proc('123456789', :x);
print

-- error
variable x char(5 char)
call f_proc('123456789', :x);
print

-- error
variable x char(5 byte)
call f_proc('123456789', :x);
print

create or replace function f_test(a varchar2, b out varchar2)
return varchar2
is
begin
raise notice '%', a;
raise notice '%', b;
b := a;
raise notice '%', a;
raise notice '%', b;
return a||b;
end;
/

-- ok
variable x varchar2(10) = '123456789'
variable y varchar2(11)
variable z varchar2(12 char)
call f_test(:x, :y) INTO :z;
print x y z

-- ok
variable x varchar2(10) = '123456789'
variable y varchar2(11)
variable z varchar2(12 byte)
call f_test(:x, :y) INTO :z;
print x y z

-- ok
variable x varchar2(10) = '123456789'
variable y varchar2(5 char)
variable z varchar2(20)
call f_test(:x, :y) INTO :z;
print x y z

-- ok
variable x varchar2(10) = '123456789'
variable y varchar2(5 byte)
variable z varchar2(20)
call f_test(:x, :y) INTO :z;
print x y z

-- error
variable x varchar2(10) = '123456789'
variable y varchar2(11)
variable z varchar2(12 char)

begin
:z := f_test(:x, :y);
end;
/
print x y z

-- error
variable x char(10) = '123456789'
variable y char(11)
variable z char(12 char)
call f_test(:x, :y) INTO :z;
print x y z

-- error
variable x char(10) = '123456789'
variable y char(11)
variable z char(12 byte)
call f_test(:x, :y) INTO :z;
print x y z

-- ok
variable x char(10) = '123456789'
variable y char(11)
variable z char(20 char)
call f_test(:x, :y) INTO :z;
print x y z

-- ok
variable x char(10) = '123456789'
variable y char(11)
variable z char(20 byte)
call f_test(:x, :y) INTO :z;
print x y z

-- error
variable x char(10) = '123456789'
variable y char(5 char)
variable z char(20)
call f_test(:x, :y) INTO :z;
print x y z

-- error
variable x char(10) = '123456789'
variable y char(5 byte)
variable z char(20)
call f_test(:x, :y) INTO :z;
print x y z

-- ok
variable x char(10) = '123456789'
variable y char(10 char)
variable z char(20)
call f_test(:x, :y) INTO :z;
print x y z

-- ok
variable x char(10) = '123456789'
variable y char(10 byte)
variable z char(20)
call f_test(:x, :y) INTO :z;
print x y z

-- ORA-06578: output parameter cannot be a duplicate bind.
-- Cause: The bind variable corresponding to an IN/OUT or
-- OUT parameter for a function or a procedure or a function
-- return value in a CALL statement cannot be a duplicate bind variable.
call f_test(:x, :x) INTO :z;
call f_proc(:x, :x);

--clean
drop procedure ff_proc;
drop procedure f_proc;
drop function f_test;
drop function ff_test;

--
-- ROWNUM as function parameter and variable name
-- Oracle allows ROWNUM as parameter/variable name in PL/SQL.
-- https://github.com/IvorySQL/IvorySQL/pull/1000#issuecomment-3717690863
--

-- Test 1: Function with 'rownum' as parameter name
-- Oracle: Creates successfully
CREATE OR REPLACE FUNCTION test_rownum_param(rownum IN VARCHAR2) RETURN INTEGER IS
BEGIN
    RAISE NOTICE 'Parameter value: %', rownum;
    RETURN 23;
END;
/

-- Test 2: Call the function with variable named 'rownum'
-- Oracle: Runs successfully
DECLARE
    rownum VARCHAR2(256) := 'hello';
    ret INTEGER;
BEGIN
    ret := test_rownum_param(rownum);
    RAISE NOTICE 'Return value: %', ret;
END;
/

-- Test 3: Named parameter call using 'rownum =>'
-- Oracle: Runs successfully
DECLARE
    ret INTEGER;
BEGIN
    ret := test_rownum_param(rownum => 'world');
    RAISE NOTICE 'Named param return: %', ret;
END;
/

-- Cleanup (may fail if function wasn't created)
DROP FUNCTION IF EXISTS test_rownum_param;

