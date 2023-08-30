--
-- PLISQL
--

-- return is a non-reserved keyword, Can be used as object name.
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
RETURN record 
IS
BEGIN 
   b := a;
   c := a; 
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


<<
main >>
begin
null;
end;

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

--
-- Compatible with Oracle:
-- The input parameter type is %rowtype
--
create table t1(a int, b int);

create or  replace function ftest(a in t1%rowtype)
 return int 
  as 
begin  a.a = 25; a.b= 26; raise notice '%',a;
return 25;
end;
/

select * from ftest(null::t1);

drop function ftest;
drop table t1;
