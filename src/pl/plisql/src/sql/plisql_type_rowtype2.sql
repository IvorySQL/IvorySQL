--3 INSERT INTO table_name VALUES var
CREATE TABLE t1(id int, name varchar(20));

--Record that variables are allowed in the VALUES clause of an INSERT statement
DECLARE
  v1 t1%ROWTYPE;
BEGIN
  FOR i IN 1 .. 5 LOOP
    v1.id := i;
	v1.name := 'a' || i;
    INSERT INTO t1 VALUES v1;
  END LOOP;
END;
/
SELECT * FROM t1;

--Record that variables are allowed in the INTO subclause of a RETURNING clause
DECLARE
  v1 t1%ROWTYPE;
  v2 t1%ROWTYPE;
BEGIN
  v1.id := 6; 
  v1.name := 'a6';
  INSERT INTO t1 VALUES v1 returning id,name into v2;
  raise notice 'v2 = %', v2;
END;
/
SELECT * FROM t1;

--test subprograms
DELETE FROM t1;

DECLARE
  FUNCTION f1(a int) RETURN INT AS
    v1 t1%ROWTYPE;
  BEGIN
    v1.id := 7; 
    v1.name := 'a7';
    INSERT INTO t1 VALUES v1;
	return 1;
  END;
BEGIN
  perform f1(1);
END;
/
SELECT * FROM t1;

--test package
CREATE OR REPLACE PACKAGE pkg1 is
  FUNCTION pfun(v int) return varchar;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
  FUNCTION pfun(v int) RETURN varchar AS
    v1 t1%ROWTYPE;
  BEGIN
    v1.id := 8; 
    v1.name := 'efg';
    INSERT INTO t1 VALUES v1;
    RETURN v1.name;
  END;
END;
/

DECLARE
BEGIN
  raise notice '%', pkg1.pfun(1);
END;
/

SELECT * FROM t1;

DROP PACKAGE pkg1;

--INSERT INTO tablename VALUES row_variable 
CREATE TABLE t2(id int, name varchar(20));
DELETE FROM t1;

DECLARE
  v1 t2%ROWTYPE;
BEGIN
  v1.id := 9; 
  v1.name := 'abc9';
  INSERT INTO t1 VALUES v1;
END;
/
SELECT * FROM t1;
DROP TABLE t2;

--nested rowtype
CREATE TABLE tn1(id int, name varchar(20));
CREATE TABLE tn2(c1 t1);

DECLARE
  v1 tn2%ROWTYPE;
BEGIN
  v1.c1.id := 10; 
  v1.c1.name := 'abc10';
  INSERT INTO tn2 VALUES v1;
END;
/
SELECT * FROM tn2;

DECLARE
  v1 tn2%ROWTYPE;
BEGIN
  v1.c1.id := 11; 
  v1.c1.name := 'abcd11';
  INSERT INTO tn1 VALUES v1.c1;
END;
/

SELECT * FROM tn1;

DROP TABLE tn2;
DROP TABLE tn1;

--%ROWTYPE Attribute and Virtual Columns
CREATE TABLE plch_departure (
  destination    VARCHAR2(100),
  departure_time DATE,
  delay          NUMBER(10),
  expected       DATE GENERATED ALWAYS AS (departure_time + delay/24/60/60) STORED
);

DECLARE
 dep_rec plch_departure%ROWTYPE;
BEGIN
  dep_rec.destination := 'X'; 
  dep_rec.departure_time := TO_DATE('2023-2-12');
  dep_rec.delay := 1500;

  INSERT INTO plch_departure VALUES dep_rec;
END;
/

--insert the individual record fields into the table, excluding the virtual column.
DECLARE
  dep_rec plch_departure%rowtype;
BEGIN
  dep_rec.destination := 'X';
  dep_rec.departure_time := TO_DATE('2023-2-12');
  dep_rec.delay := 1500;
 
  INSERT INTO plch_departure (destination, departure_time, delay)
  VALUES (dep_rec.destination, dep_rec.departure_time, dep_rec.delay);
end;
/
SELECT * FROM plch_departure;

DROP TABLE plch_departure;

--rainy-day test cases of the INSERT statment
--If the VALUES clause of an INSERT statement contains a record variable, no other variable or value is allowed in the clause.
DECLARE
  v1 t1%ROWTYPE;
BEGIN
  v1.id := 11; 
  v1.name := 'abc';
  INSERT INTO t1 VALUES v1, v1;
END;
/

--If the INTO subclause of a RETURNING clause contains a record variable, no other variable or value is allowed in the subclause.
DECLARE
  v1 t1%ROWTYPE;
  v2 t1%ROWTYPE;
BEGIN
  v1.id := 12; 
  v1.name := 'abcd';
  INSERT INTO t1 VALUES v1 returning id,name into v2,v2;
END;
/

DECLARE
  v1 t1%ROWTYPE;
BEGIN
  v1.id := 11; 
  v1.name := 'abc';
  INSERT INTO t1 VALUES v1.*;
END;
/

DECLARE
  v1 t1%ROWTYPE;
BEGIN
  v1.id := 11; 
  v1.name := 'abc';
  INSERT INTO t1 VALUES v1 where v1.id > 1;
END;
/

CREATE OR REPLACE FUNCTION f1(v int) RETURN t1%ROWTYPE AS
  a t1%ROWTYPE;
BEGIN
  select * into a from t1;
  RETURN a;
END;
/

--INSERT INTO tablename VALUES func, failed to execute the statement
declare
  r  t1%ROWTYPE;
begin
  insert into t1 values f1(1);
end;
/

--INSERT INTO tablename VALUES row_variable, succeeded to execute the statement
declare
  r  t1%ROWTYPE;
begin
  r :=  f1(1);
  insert into t1 values r;
end;
/

DROP FUNCTION f1(int);

--not support record inserts using the EXECUTE statement.
declare
  r  t1%ROWTYPE;
begin
  r.id := 11; 
  r.name := 'abc';
  execute 'insert into t1 values :1' using r;
end;
/

--INSERT INTO tablename VALUES row_variable which fields are not matched with tablename 
CREATE TABLE t3(id int);
CREATE TABLE t4(id int, name varchar(20), id2 int);
CREATE TABLE t5(id varchar(20), name varchar(20));

DECLARE
  v1 t3%ROWTYPE;
BEGIN
  v1.id := 11;
  INSERT INTO t1 VALUES v1;
END;
/

DECLARE
  v1 t4%ROWTYPE;
BEGIN
  v1.id := 11;
  v1.name := 'a';
  v1.id2 := 12;
  INSERT INTO t1 VALUES v1;
END;
/

DECLARE
  v1 t5%ROWTYPE;
BEGIN
  v1.id := 'a';
  v1.name := 'a';
  INSERT INTO t1 VALUES v1;
END;
/

DROP TABLE t3;
DROP TABLE t4;
DROP TABLE t5;

--a column has a NOT NULL constraint, then the corresponding field of rowtype cannot have a NULL value.
CREATE TABLE t6(id int NOT NULL, name varchar(20));

DECLARE
  v1 t6%ROWTYPE;
BEGIN
  v1.name := 'a';
  INSERT INTO t6 VALUES v1;
END;
/

DROP TABLE t6;


--4 UPDATE table_name SET ROW = var [WHERE...]
DELETE FROM t1;

DECLARE
  v1 t1%ROWTYPE;
  v2 t1%ROWTYPE;
BEGIN
  v1.id := 11; 
  v1.name := 'abc';
  INSERT INTO t1 VALUES v1;

  v2.id := 22;
  v2.name := 'new';
  UPDATE t1 SET ROW = v2;
END;
/
SELECT * FROM t1;

DECLARE
  v2 t1%ROWTYPE;
BEGIN
  v2.id := 33;
  v2.name := 'new3';
  UPDATE t1 AS t SET ROW = v2;
END;
/
SELECT * FROM t1;

--where clause
INSERT INTO t1 VALUES(1, 'a');
SELECT * FROM t1;

DECLARE
  v2 t1%ROWTYPE;
BEGIN
  v2.id := 44;
  v2.name := 'new4';
  UPDATE t1 AS t SET ROW = v2 where id = 33;
END;
/
SELECT * FROM t1;

--Record variables are allowed in the INTO subclause of a RETURNING clause
DELETE FROM t1;
INSERT INTO t1 VALUES(1, 'a');

DECLARE
  v1 t1%ROWTYPE;
  v2 t1%ROWTYPE;
BEGIN
  v2.id := 55;
  v2.name := 'new5';
  UPDATE t1 AS t SET ROW = v2 RETURNING id, name into v1;
  raise notice 'v1 = %', v1;
END;
/
SELECT * FROM t1;

--rainy-day test cases of the UPDATE statment
--cannot set ROW with a subquery
CREATE TABLE t0(id int);
INSERT INTO t0 VALUES(1);

DECLARE
  v2 t0%ROWTYPE;
BEGIN
  v2.id := 66;
  UPDATE t0 AS t SET ROW = (select id from t0 where id = 55);
END;
/
DROP TABLE t0;

DECLARE
  v2 t1%ROWTYPE;
BEGIN
  v2.id := 66;
  v2.name := 'new6';
  UPDATE t1 AS t SET ROW = repeat('x', 10000) WHERE  id = 33;
END;
/

DECLARE
  v2 t1%ROWTYPE;
BEGIN
  v2.id := 66;
  v2.name := 'new6';
  UPDATE t1 AS t SET ROW = v2, id = 1;
END;
/

--In an UPDATE statement, only one SET clause is allowed if ROW is used
DECLARE
  v2 t1%ROWTYPE;
BEGIN
  v2.id := 66;
  v2.name := 'new6';
  UPDATE t1 AS t SET ROW = v2, ROW = v2;
END;
/

--If the INTO subclause of a RETURNING clause contains a record variable, no other variable or value is allowed in the subclause.
DECLARE
  v1 t1%ROWTYPE;
  v2 t1%ROWTYPE;
  v3 int;
BEGIN
  v2.id := 66;
  v2.name := 'new6';
  UPDATE t1 AS t SET ROW = v2 RETURNING id, name,id into v1, v3;
END;
/

--not support functions that return a %ROWTYPE type
CREATE OR REPLACE FUNCTION f2(v int) RETURN t1%ROWTYPE AS
  a t1%ROWTYPE;
BEGIN
  select * into a from t1;
  RETURN a;
END;
/

declare
  r  t1%ROWTYPE;
begin
  UPDATE t1 AS t SET ROW = f2(1);
end;
/
DROP FUNCTION f2(int);

--not support record updates using the EXECUTE statement.
declare
  r  t1%ROWTYPE;
begin
  execute 'UPDATE t1 AS t SET ROW = :1' using r;
end;
/

--5 prostatus in pg_proc catalog
--5.1 set check_function_bodies = on
--5.1.1 simple test
set check_function_bodies = on;

DROP TABLE t1;
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun5(v int) RETURN t1.id%TYPE AS
BEGIN
  RETURN v;
END;
/
SELECT prostatus FROM pg_proc WHERE proname like 'fun5'; --v

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun5';  --1

CREATE OR REPLACE FUNCTION fun6(v int) RETURN int AS
  a t1.id%TYPE;
  b t1.id%TYPE;
BEGIN
  RETURN v;
END;
/
SELECT prostatus FROM pg_proc WHERE proname like 'fun6';  --v

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun6'; --1

CREATE OR REPLACE FUNCTION fun7(v t1.id%TYPE, v1 t1.name%TYPE) RETURN t1.id%TYPE AS
  a t1.id%TYPE;
  b t1.name%TYPE;
BEGIN
  RETURN v;
END;
/
SELECT prostatus FROM pg_proc WHERE proname like 'fun7'; --v

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun7'; --2

CREATE OR REPLACE FUNCTION fun8(v t1%ROWTYPE, v1 t1%ROWTYPE) RETURN t1%ROWTYPE AS
BEGIN
  RETURN v;
END;
/
SELECT prostatus FROM pg_proc WHERE proname like 'fun8'; --v

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun8'; --1

CREATE OR REPLACE FUNCTION fun9() RETURN t1%ROWTYPE AS
  a t1%ROWTYPE;
BEGIN
  RETURN v;
END;
/
SELECT prostatus FROM pg_proc WHERE proname like 'fun9'; --v

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun9';  --1

CREATE OR REPLACE FUNCTION fun10() RETURN int AS
  a t1%ROWTYPE;
  b t1%ROWTYPE;
BEGIN
  RETURN v;
END;
/
SELECT prostatus FROM pg_proc WHERE proname like 'fun10'; --v

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun10';  --1

CREATE OR REPLACE FUNCTION fun11(v t1%ROWTYPE, v1 t1%ROWTYPE) RETURN t1%ROWTYPE AS
  a t1%ROWTYPE;
  b t1%ROWTYPE;
BEGIN
  RETURN v;
END;
/
SELECT prostatus FROM pg_proc WHERE proname like 'fun11'; --v

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun11'; --1

CREATE OR REPLACE FUNCTION fun12(v t1.id%TYPE, v1 t1.id%TYPE, v2 t1.name %TYPE, v3 t1.name%TYPE, v4 t1%ROWTYPE, v5 t1%ROWTYPE) RETURN t1.id%TYPE AS
  a t1.id%TYPE;
  b t1.name%TYPE;
  c t1%ROWTYPE;
BEGIN
  RETURN v;
END;
/
SELECT prostatus FROM pg_proc WHERE proname like 'fun12'; --v

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1' 
  AND d.refobjid = c.oid 
  AND d.objid = p.oid
  AND p.proname like 'fun12'; --2

DROP FUNCTION fun5;
DROP FUNCTION fun6;
DROP FUNCTION fun7;
DROP FUNCTION fun8;
DROP FUNCTION fun9;
DROP FUNCTION fun10;
DROP FUNCTION fun11;
DROP FUNCTION fun12;


--5.1.2
set check_function_bodies = on;

DROP TABLE t1;
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun1(v t1.id%TYPE, v1 t1.id%TYPE) RETURN t1.id%TYPE AS
  id t1.name%TYPE;
BEGIN
  RETURN v;
END;
/
SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --v
SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE d.refobjid = c.oid AND d.objid = p.oid; --2

SELECT fun1(2,2) FROM DUAL; --2

ALTER FUNCTION fun1 COMPILE;

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE d.refobjid = c.oid AND d.objid = p.oid; --2


CREATE OR REPLACE FUNCTION fun1(v t1.id%TYPE, v1 t1.id%TYPE) RETURN t1.id%TYPE AS
BEGIN
  RETURN v + 1;
END;
/

SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --v
SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE d.refobjid = c.oid AND d.objid = p.oid; --1

SELECT fun1(2,2) FROM DUAL; --3
  
ALTER FUNCTION fun1 COMPILE;
SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE d.refobjid = c.oid AND d.objid = p.oid; --1

SELECT fun1(2,2) FROM DUAL; --3

\c 
SELECT fun1(2,2) FROM DUAL; --3

--alter table t1 drop column id
ALTER TABLE T1 DROP COLUMN id;
SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE d.refobjid = c.oid AND d.objid = p.oid;  --0

SELECT fun1(3,3) FROM DUAL; --error
ALTER FUNCTION fun1 COMPILE; --should raise an error, because have dropped id column.

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE d.refobjid = c.oid AND d.objid = p.oid; --0

DROP FUNCTION fun1;

--5.2  when a function has invalid status, rebuild the function using CREATE OR REPLACE, and the function can have VALID status
DROP TABLE t1;

CREATE TABLE t1(id varchar(20), name varchar(20), id2 int);
					
CREATE OR REPLACE FUNCTION fun1(v t1.name%TYPE, v1 t1.name%TYPE) RETURN t1.name%TYPE AS
  id t1.id%TYPE;
BEGIN
  RETURN v;
END;
/
ALTER TABLE T1 DROP COLUMN id;
SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --n
select fun1('a','b') from dual;  --error

CREATE OR REPLACE FUNCTION fun1(v t1.name%TYPE, v1 t1.name%TYPE) RETURN t1.name%TYPE AS
  id t1.id2%TYPE;
  id2 int;
BEGIN
  RETURN 'ab';
END;
/

SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --v
select fun1('a','b') from dual;  --ab
DROP FUNCTION fun1;

--5.3 set check_function_bodies = off
set check_function_bodies = off;

DROP TABLE t1;
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun1(v t1.id%TYPE, v1 t1.id%TYPE) RETURN t1.id%TYPE AS
  id t1.name%TYPE;
BEGIN
  RETURN v;
END;
/
SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --n
SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE d.refobjid = c.oid AND d.objid = p.oid; --0

SELECT fun1(2,2);
ALTER FUNCTION fun1 COMPILE;
SELECT fun1(2,2);

SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --v
SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE d.refobjid = c.oid AND d.objid = p.oid; --2

SELECT fun1(2,2) FROM DUAL;  --2

set check_function_bodies = off;
CREATE OR REPLACE FUNCTION fun1(v t1.id%TYPE, v1 t1.id%TYPE) RETURN t1.id%TYPE AS
BEGIN
  RETURN v + 1;
END;
/
SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --n

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE d.refobjid = c.oid AND d.objid = p.oid; --0

SELECT fun1(2,2) FROM DUAL; --3

\c 
SELECT fun1(2,2) FROM DUAL; --3

--alter table t1 drop column id
ALTER TABLE T1 DROP COLUMN id;
SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE d.refobjid = c.oid AND d.objid = p.oid; --0

SELECT fun1(3,3); --error
ALTER FUNCTION fun1 COMPILE; --should raise an error, because id column has been dropped.

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE d.refobjid = c.oid AND d.objid = p.oid; --0

DROP FUNCTION fun1;
DROP TABLE t1;

RESET IVORYSQL.COMPATIBLE_MODE;
RESET IVORYSQL.IDENTIFIER_CASE_SWITCH;

--7 others
--7.1 parameter datatype of subprocedure in package is %TYPE or %ROWTYPE
create table tb1(id int,name varchar(5));

create or replace package pkg is
  var1 int;
  function test_f(id tb1.id%type) return integer;
end;
/

--successfully
create or replace package body pkg is
  function test_f(id tb1.id%type) return integer is
  begin
    return id;
  end;
end;
/

--failed
create or replace package body pkg is
  var2 varchar2(10);
  function test_f(id int) return integer is
  begin
    return id;
  end;
end;
/
drop package pkg;

create or replace package pkg is
  var1 int;
  function test_f(id tb1%rowtype) return integer;
end;
/
--successfully
create or replace package body pkg is
  function test_f(id tb1%rowtype) return integer is
  begin
    return id;
  end;
end;
/

--failed
create or replace package body pkg is
  function test_f(id tb1.id%type) return integer is
  begin
    return id;
  end;
end;
/
drop package pkg;
drop table tb1;

--7.2 guc plisql.extra_errors
create table tb1(id int,name varchar(5),age int);
insert into tb1 values(1,'sam',20);
insert into tb1 values(2,'amy',30);
create table tb2(id int,name varchar(5));

--successfully
declare
  var1 tb2%rowtype;
begin
  select * into var1 from tb1 where id=2;
end;
/

--successfully
declare
  var1 tb2%rowtype;
begin
  select id into var1 from tb1 where id=2;
end;
/

set plisql.extra_errors = 'all';
--failed
declare
  var1 tb2%rowtype;
begin
  select * into var1 from tb1 where id=2;
end;
/
--failed
declare
  var1 tb2%rowtype;
begin
  select id into var1 from tb1 where id=2;
end;
/

drop table tb2;
drop table tb1;
set plisql.extra_errors = 'none';

--7.3
create table tb1(id int, id2 float4, id3 float8, id4 number, name1 varchar(20), name2 char);

create function fun1(c1 tb1.id%type,c2 tb1.i2d%type, c3 tb1.id3%type, c4 tb1.id4%type, c5 tb1.name1%type, c6 tb1.name2%type) return tb1.name1%type is
begin
  return c5;
end;
/
create function fun1(c1 tb1.id%type,c2 tb1.id2%type, c3 tb1.id3%type, c4 tb1.id4%type, c5 tb1.name1%type, c6 tb1.name2%type) return tb1.name1%type is
begin
  return c5;
end;
/
drop table tb1;
drop function fun1;

--7.4
create table tb1(id int, id2 float4, id3 float8, id4 number, name1 varchar(20), name2 char);

create or replace package pkg1 is
  var1 tb1.id%TYPE;
  FUNCTION fun1(c1 tb1.id%type,c2 tb1.id2%type, c3 tb1.id3%type, c4 tb1.id4%type, c5 tb1.name1%type, c6 tb1.name2%type) return tb1.name1%type;
END;
/

create or replace package body pkg1 is
  a tb1.name1%TYPE := 'a';
  FUNCTION fun1(c1 tb1.id%type,c2 tb1.id2%type, c3 tb1.id3%type, c4 tb1.id4%type, c5 tb1.name1%type, c6 tb1.name2%type) return tb1.name1%type AS
  BEGIN
    RETURN c5;
  END;
END;
/
drop table tb1;
drop package pkg1;

--7.5 failed to compile the functions in CREATE OR REPLACE FUNCTION/PROCEDURE statement
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SET IVORYSQL.IDENTIFIER_CASE_SWITCH = INTERCHANGE;

create or replace  function fun1(id int) return int as
begin
  return abc;
end;
/
SELECT prostatus FROM PG_PROC WHERE PRONAME LIKE 'fun1';
SELECT TEXT FROM SYS.ALL_SOURCE WHERE NAME LIKE 'FUN1';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.ALL_ARGUMENTS where OBJECT_NAME like 'FUN1';
SELECT object_name,procedure_name,subprogram_id,object_type,authid FROM ALL_PROCEDURES WHERE OBJECT_NAME like 'FUN1' ORDER BY object_name,procedure_name;
DROP FUNCTION fun1;

create or replace  function fun2(id int) return int as
begin
  return 1;
end;
/
SELECT prostatus FROM PG_PROC WHERE PRONAME LIKE 'fun2';

SELECT TEXT FROM SYS.ALL_SOURCE WHERE NAME LIKE 'FUN2';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.ALL_ARGUMENTS where OBJECT_NAME like 'FUN2';
SELECT object_name,procedure_name,subprogram_id,object_type,authid FROM ALL_PROCEDURES WHERE OBJECT_NAME like 'FUN2' ORDER BY object_name,procedure_name;


create or replace  function fun2(id int) return int as
begin
  a := 1;
  return a;
end;
/
SELECT prostatus FROM PG_PROC WHERE PRONAME LIKE 'fun2';
SELECT TEXT FROM ALL_SOURCE WHERE NAME LIKE 'FUN2';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.ALL_ARGUMENTS where OBJECT_NAME like 'FUN2';
SELECT object_name,procedure_name,subprogram_id,object_type,authid FROM ALL_PROCEDURES WHERE OBJECT_NAME like 'FUN2' ORDER BY object_name,procedure_name;

DROP FUNCTION fun2;

RESET IVORYSQL.COMPATIBLE_MODE;
RESET IVORYSQL.IDENTIFIER_CASE_SWITCH;

--
--clean up
DROP TABLE employees;
