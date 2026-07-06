--
-- Tests for PL/iSQL %TYPE and and %ROWTYPE Attributes
--1 %TYPE
--1.1 If the declaration of the referenced item is changed, then the declaration of the referencing item changes accordingly.
--1.1.1 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] ALTER [ COLUMN ] column_name [ SET DATA ] TYPE data_type [ COLLATE collation ] [ USING expression ]
--1.1.2 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] DROP [ COLUMN ] [ IF EXISTS ] column_name [ RESTRICT | CASCADE ]
--1.1.3 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] RENAME [ COLUMN ] column_name TO new_column_name
--1.1.4 ALTER TABLE [ IF EXISTS ] name  RENAME TO new_name
--1.1.5 DROP TABLE [ IF EXISTS ] name [, ...] [ CASCADE | RESTRICT ]
--1.2 The referencing variable inherits the Data type and size of the referenced variable
--1.3 The referencing variable inherits the Constraints (unless the referenced item is a column) of the referenced variable
--2 %ROWTYPE
--2.1 function's parameter datatype is tablename%ROWTYPE
--2.2 function's return datatype is tablename%ROWTYPE
--2.3 subprogram's parameter datatype and return datatype are tablename%ROWTYPE
--2.4 the referencing variable inherits the data type and size of the referenced variable
--2.5 if the declaration of the referenced item is changed, then the declaration of the referencing item changes accordingly.
--2.5.1 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] ALTER [ COLUMN ] column_name [ SET DATA ] TYPE data_type [ COLLATE collation ] [ USING expression ]
--2.5.2 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] DROP [ COLUMN ] [ IF EXISTS ] column_name [ RESTRICT | CASCADE ]
--2.5.3 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] RENAME [ COLUMN ] column_name TO new_column_name
--2.5.4 ALTER TABLE [ IF EXISTS ] name  RENAME TO new_name
--2.5.5 DROP TABLE [ IF EXISTS ] name [, ...] [ CASCADE | RESTRICT ]
--3 INSERT INTO table_name VALUES var
--4 UPDATE table_name SET ROW = var [WHERE...]
--5 prostatus in pg_proc catalog
--6 all_arguments system views
--7 others
--

CREATE TABLE employees(first_name varchar(20) not null, 
last_name varchar(20) not null,
phone_number varchar(50));
INSERT INTO employees VALUES ('Steven','Niu','1-650-555-1234');

--1 %TYPE
--1.1 If the declaration of the referenced item is changed, then the declaration of the referencing item changes accordingly.
--1.1.1 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] ALTER [ COLUMN ] column_name [ SET DATA ] TYPE data_type [ COLLATE collation ] [ USING expression ]
CREATE TABLE t1(id int, name varchar(20));

--function's parameter datatype is tablename.columnname%TYPE
CREATE OR REPLACE FUNCTION fun1(v t1.id%TYPE) RETURN varchar AS
BEGIN
  RETURN v;
END;
/

CREATE OR REPLACE PROCEDURE proc1(v t1.id%TYPE) AS
  a varchar(20);
BEGIN
  a := v;
  raise notice '%', a;
END;
/

SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --v
SELECT prostatus FROM pg_proc WHERE proname like 'proc1'; --v

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun1';  --1

SELECT fun1(1) FROM dual;
CALL proc1(1);

ALTER TABLE t1 ALTER COLUMN id TYPE varchar(20);

SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --n
SELECT prostatus FROM pg_proc WHERE proname like 'proc1'; --n
SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun1'; --1

--after changing the column id type from int to varchar, call the function again
SELECT fun1('a') FROM dual;  --successfully
ALTER FUNCTION fun1 COMPILE;
SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --v
SELECT fun1('a') FROM dual; --successfully

CALL proc1('a');  --successfully
ALTER PROCEDURE proc1 COMPILE;
SELECT prostatus FROM pg_proc WHERE proname like 'proc1'; --v
CALL proc1('a');  --successfully

DROP FUNCTION fun1;
DROP PROCEDURE proc1;
DROP TABLE t1;

--function's return datatype is tablename.columnname%TYPE
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun2(v int) RETURN t1.id%TYPE
AS
BEGIN
  RETURN 'a';
END;
/

SELECT fun2(2) FROM dual;
ALTER TABLE t1 ALTER COLUMN id TYPE integer using id::integer;

--because the column id type is changed from varchar to int, failed to call the function again
SELECT fun2(2) FROM dual; --failed
ALTER FUNCTION fun2 COMPILE;
SELECT prostatus FROM pg_proc WHERE proname like 'fun2'; --v
SELECT fun2(2) FROM dual; --failed

DROP FUNCTION fun2; 
DROP TABLE t1;

--Variable datatype is tablename.columnname%TYPE
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun3(v int) RETURN varchar AS
  a t1.id%TYPE := 'a';
BEGIN
  RETURN a;
END;
/

CREATE OR REPLACE FUNCTION fun4(v int) RETURN varchar AS
  FUNCTION inf1(v1 int) RETURN varchar AS
    a t1.id%TYPE := 'a';
  BEGIN
    RETURN a;
  END;
BEGIN
  RETURN inf1(4);
END;
/

CREATE OR REPLACE FUNCTION fun5(v t1.id%TYPE) RETURN varchar AS
  PROCEDURE inp1(v1 t1.id%TYPE) AS
    a varchar(10);
  BEGIN
    a := v1;
    raise notice '%', a;
  END;
BEGIN
  CALL inp1(v);
  RETURN 'a';
END;
/

SELECT fun3(3) FROM dual;
SELECT fun4(4) FROM dual;
SELECT fun5(5) FROM dual;

ALTER TABLE t1 ALTER COLUMN id TYPE integer using id::integer;

SELECT prostatus FROM pg_proc WHERE proname like 'fun3'; --n
SELECT prostatus FROM pg_proc WHERE proname like 'fun4'; --n
SELECT prostatus FROM pg_proc WHERE proname like 'fun5'; --n

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun3'; --1

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun4'; --1

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun5'; --1

--change the column id type from int to varchar, call the function
SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --failed
SELECT fun5(5) FROM dual;  --successfully

ALTER FUNCTION fun3 COMPILE;
ALTER FUNCTION fun4 COMPILE;
ALTER FUNCTION fun5 COMPILE;
SELECT prostatus FROM pg_proc WHERE proname like 'fun3'; --v
SELECT prostatus FROM pg_proc WHERE proname like 'fun4'; --v
SELECT prostatus FROM pg_proc WHERE proname like 'fun5'; --v

SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --failed
SELECT fun5(5) FROM dual;  --successfully

DROP FUNCTION fun3; 
DROP FUNCTION fun4; 
DROP FUNCTION fun5; 
DROP TABLE t1;

--use tablename.columnname%TYPE in package
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE PACKAGE pkg1 is
  var1 t1.id%TYPE;
  FUNCTION pfun(v int) return varchar;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
   a t1.name%TYPE := 'a';
  FUNCTION pfun(v int) RETURN varchar AS
    a t1.id%TYPE := 'a';
	b a%TYPE := 'b';
  BEGIN
    var1 := 'a' || b;
    a := var1;
    RETURN a;
  END;
END;
/

DECLARE
BEGIN
  raise notice '%', pkg1.pfun(1);
END;
/

SELECT count(*) FROM pg_depend d, pg_class c, pg_package p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.pkgname like 'pkg1'; --1
  
ALTER TABLE t1 ALTER COLUMN id TYPE integer using id::integer;

--change the column id type from int to varchar, failed to call the package function again
select pkg1.pfun(1) from dual;  --should raise an error, packages has been discarded


DROP PACKAGE pkg1;
DROP TABLE t1;

--1.1.2 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] DROP [ COLUMN ] [ IF EXISTS ] column_name [ RESTRICT | CASCADE ]
CREATE TABLE t1(id int, name varchar(20));

--function's parameter datatype is tablename.columnname%TYPE
CREATE OR REPLACE FUNCTION fun1(v t1.id%TYPE) RETURN varchar AS
BEGIN
  RETURN v;
END;
/

CREATE OR REPLACE PROCEDURE proc1(v t1.id%TYPE) AS
  a varchar(20);
BEGIN
  a := v;
  raise notice '%', a;
END;
/

SELECT fun1(1) FROM dual;
CALL proc1(1);

SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --v
SELECT prostatus FROM pg_proc WHERE proname like 'proc1'; --v

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun1'; --1

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'proc1'; --1
  
ALTER TABLE t1 DROP COLUMN id;

SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --n
SELECT prostatus FROM pg_proc WHERE proname like 'proc1'; --n

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun1'; --0

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'proc1'; --0

--after dropping the column id, failed to call the function
SELECT fun1('a') FROM dual; --failed
CALL proc1('a'); --failed
ALTER FUNCTION fun1 COMPILE;
ALTER PROCEDURE proc1 COMPILE;
SELECT prostatus FROM pg_proc WHERE proname like 'fun1'; --i
SELECT prostatus FROM pg_proc WHERE proname like 'proc1'; --i

SELECT fun1('a') FROM dual; --failed
CALL proc1('a'); --failed

DROP TABLE t1;
DROP FUNCTION fun1;
DROP PROCEDURE proc1;

--function's return datatype is tablename.columnname%TYPE
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun2(v int) RETURN t1.id%TYPE
AS
BEGIN
  RETURN 'a';
END;
/

SELECT fun2(2) FROM dual;
ALTER TABLE t1 DROP COLUMN id;

--after dropping the column id, failed to call the function again
SELECT fun2(2) FROM dual;

SELECT prostatus FROM pg_proc WHERE proname like 'fun2'; --i

SELECT count(*) FROM pg_depend d, pg_class c, pg_proc p 
  WHERE c.relname like 't1'
  AND d.refobjid = c.oid
  AND d.objid = p.oid
  AND p.proname like 'fun2'; --0
  
DROP TABLE t1;
DROP FUNCTION fun2; 

--Variable datatype is tablename.columnname%TYPE
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun3(v int) RETURN varchar AS
  a t1.id%TYPE := 'a';
BEGIN
  RETURN a;
END;
/

CREATE OR REPLACE FUNCTION fun4(v int) RETURN varchar AS
  FUNCTION inf1(v1 int) RETURN varchar AS
    a t1.id%TYPE := 'a';
  BEGIN
    RETURN a;
  END;
BEGIN
  RETURN inf1(4);
END;
/

CREATE OR REPLACE FUNCTION fun5(v t1.id%TYPE) RETURN varchar AS
  PROCEDURE inp1(v1 t1.id%TYPE) AS
    a varchar(10);
  BEGIN
    a := v1;
    raise notice '%', a;
  END;
BEGIN
  CALL inp1(v);
  RETURN 'a';
END;
/

SELECT fun3(3) FROM dual;
SELECT fun4(4) FROM dual;
SELECT fun5(5) FROM dual;

ALTER TABLE t1 DROP COLUMN id;

--after dropping the column id, call the function again
SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --failed
SELECT fun5(5) FROM dual;  --failed
ALTER FUNCTION fun3 COMPILE;
ALTER FUNCTION fun4 COMPILE;
ALTER FUNCTION fun5 COMPILE;

SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --failed
SELECT fun5(5) FROM dual;  --failed

DROP TABLE t1;
DROP FUNCTION fun3; 
DROP FUNCTION fun4; 
DROP FUNCTION fun5; 

--use tablename.columnname%TYPE in package
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE PACKAGE pkg1 is
  var1 t1.id%TYPE;
  FUNCTION pfun(v int) return varchar;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
  FUNCTION pfun(v int) RETURN varchar AS
    a t1.id%TYPE := 'a';
  BEGIN
    var1 := 'a';
    a := var1;
    RETURN a;
  END;
END;
/

DECLARE
BEGIN
  raise notice '%', pkg1.pfun(1);
END;
/

ALTER TABLE t1 DROP COLUMN id;

--after dropping the column id, failed to call the package function again
DECLARE
BEGIN
  raise notice '%', pkg1.pfun(1);
END;
/

DROP PACKAGE pkg1;
DROP TABLE t1;

--inherit table
CREATE TABLE father_table(c1 integer,c2 varchar(10));
CREATE TABLE child_table(c3 varchar(10)) inherits (father_table);

CREATE OR REPLACE FUNCTION fun6(v int) return varchar as
  a child_table.c3%TYPE := 'a';
BEGIN
  RETURN a;
END;
/

SELECT fun6(1) FROM dual;

ALTER TABLE child_table DROP COLUMN c3; 

SELECT fun6(1) FROM dual; --failed
ALTER FUNCTION fun6 COMPILE;
SELECT fun6(1) FROM dual; --failed

CREATE OR REPLACE FUNCTION fun7(v int) return varchar as
  a child_table.c2%TYPE := 'a';
BEGIN
  RETURN a;
END;
/
SELECT fun7(1) FROM dual;

ALTER TABLE father_table DROP COLUMN c2; 

SELECT fun7(1) FROM dual; --failed
ALTER FUNCTION fun7 COMPILE;
SELECT fun7(1) FROM dual; --failed

DROP FUNCTION fun6;
DROP FUNCTION fun7;
DROP TABLE child_table;
DROP TABLE father_table;


--1.1.3 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] RENAME [ COLUMN ] column_name TO new_column_name
CREATE TABLE t1(id int, name varchar(20));

--function's parameter datatype is tablename.columnname%TYPE
CREATE OR REPLACE FUNCTION fun1(v t1.id%TYPE) RETURN varchar AS
BEGIN
  RETURN v;
END;
/

CREATE OR REPLACE PROCEDURE proc1(v t1.id%TYPE) AS
  a varchar(20);
BEGIN
  a := v;
  raise notice '%', a;
END;
/

SELECT fun1(1) FROM dual;
CALL proc1(1);

ALTER TABLE t1 RENAME COLUMN id to id2;

--after renaming the column id to id2, failed to call the function again
SELECT fun1(1) FROM dual; --failed
ALTER FUNCTION fun1 COMPILE;
SELECT fun1(1) FROM dual; --failed

CALL proc1(1); --failed
ALTER PROCEDURE proc1 COMPILE;
CALL proc1(1); --failed

DROP TABLE t1;
DROP FUNCTION fun1;
DROP PROCEDURE proc1;

--function's return datatype is tablename.columnname%TYPE
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun2(v int) RETURN t1.id%TYPE
AS
BEGIN
  RETURN 'a';
END;
/

SELECT fun2(2) FROM dual;
ALTER TABLE t1 RENAME COLUMN id to id2;

--after renaming the column id to id2, failed to call the function again
SELECT fun2(2) FROM dual; --failed
ALTER FUNCTION fun2 COMPILE;
SELECT fun2(2) FROM dual; --failed

DROP TABLE t1;
DROP FUNCTION fun2; 

--Variable datatype is tablename.columnname%TYPE
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun3(v int) RETURN varchar AS
  a t1.id%TYPE := 'a';
BEGIN
  RETURN a;
END;
/

CREATE OR REPLACE FUNCTION fun4(v int) RETURN varchar AS
  FUNCTION inf1(v1 int) RETURN varchar AS
    a t1.id%TYPE := 'a';
  BEGIN
    RETURN a;
  END;
BEGIN
  RETURN inf1(4);
END;
/

CREATE OR REPLACE FUNCTION fun5(v t1.id%TYPE) RETURN varchar AS
  PROCEDURE inp1(v1 t1.id%TYPE) AS
    a varchar(10);
  BEGIN
    a := v1;
    raise notice '%', a;
  END;
BEGIN
  CALL inp1(v);
  RETURN 'a';
END;
/

SELECT fun3(3) FROM dual;
SELECT fun4(4) FROM dual;
SELECT fun5(5) FROM dual;

ALTER TABLE t1 RENAME COLUMN id to id2;

--after renaming the column id to id2, call the function again
SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --failed
SELECT fun5(5) FROM dual;  --failed

ALTER FUNCTION fun3 COMPILE;
ALTER FUNCTION fun4 COMPILE;
ALTER FUNCTION fun5 COMPILE;

SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --failed
SELECT fun5(5) FROM dual;  --failed

DROP TABLE t1;
DROP FUNCTION fun3; 
DROP FUNCTION fun4; 
DROP FUNCTION fun5; 

--use tablename.columnname%TYPE in package
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE PACKAGE pkg1 is
  var1 t1.id%TYPE;
  FUNCTION pfun(v int) return varchar;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
  FUNCTION pfun(v int) RETURN varchar AS
    a t1.id%TYPE := 'a';
  BEGIN
    var1 := 'a';
    a := var1;
    RETURN a;
  END;
END;
/

DECLARE
BEGIN
  raise notice '%', pkg1.pfun(1);
END;
/

ALTER TABLE t1 RENAME COLUMN id to id2;

--after renaming the column id to id2, failed to call the package function again
DECLARE
BEGIN
  raise notice '%', pkg1.pfun(1);
END;
/

DROP PACKAGE pkg1;
DROP TABLE t1;

--inherit table
CREATE TABLE father_table(c1 integer,c2 varchar(10));
CREATE TABLE child_table(c3 varchar(10)) inherits (father_table);

CREATE OR REPLACE FUNCTION fun6(v int) return varchar as
  a child_table.c3%TYPE := 'a';
BEGIN
  RETURN a;
END;
/

SELECT fun6(1) FROM dual;
ALTER FUNCTION fun6 COMPILE;
SELECT fun6(1) FROM dual;

ALTER TABLE child_table RENAME COLUMN c3 to c4; 

SELECT fun6(1) FROM dual;

CREATE OR REPLACE FUNCTION fun7(v int) return varchar as
  a child_table.c2%TYPE := 'a';
BEGIN
  RETURN a;
END;
/

SELECT fun7(1) FROM dual;

ALTER TABLE father_table RENAME COLUMN c2 to c2_new; 

SELECT fun7(1) FROM dual; --failed
ALTER FUNCTION fun7 COMPILE;
SELECT fun7(1) FROM dual; --failed

DROP FUNCTION fun6;
DROP FUNCTION fun7;
DROP TABLE child_table;
DROP TABLE father_table;


--1.1.4 ALTER TABLE [ IF EXISTS ] name  RENAME TO new_name
CREATE TABLE t1(id int, name varchar(20));

--function's parameter datatype is tablename.columnname%TYPE
CREATE OR REPLACE FUNCTION fun1(v t1.id%TYPE) RETURN varchar AS
BEGIN
  RETURN v;
END;
/

CREATE OR REPLACE PROCEDURE proc1(v t1.id%TYPE) AS
  a varchar(20);
BEGIN
  a := v;
  raise notice '%', a;
END;
/

SELECT fun1(1) FROM dual;
CALL proc1(1);

ALTER TABLE t1 RENAME TO t1_new;

--after renaming the table t1 to t1_new, failed to call the function again
SELECT fun1(1) FROM dual; --failed
CALL proc1(1); --failed
ALTER FUNCTION fun1 COMPILE;
ALTER PROCEDURE proc1 COMPILE;
SELECT fun1(1) FROM dual; --failed
CALL proc1(1); --failed

DROP TABLE t1_new;
DROP FUNCTION fun1;
DROP PROCEDURE proc1;

--function's return datatype is tablename.columnname%TYPE
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun2(v int) RETURN t1.id%TYPE
AS
BEGIN
  RETURN 'a';
END;
/

SELECT fun2(2) FROM dual;
ALTER TABLE t1 RENAME TO t1_new;

--after renaming the table t1 to t1_new, failed to call the function again
SELECT fun2(2) FROM dual; --failed
ALTER FUNCTION fun2 COMPILE;
SELECT fun2(2) FROM dual; --failed

DROP TABLE t1_new;
DROP FUNCTION fun2; 

--Variable datatype is tablename.columnname%TYPE
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun3(v int) RETURN varchar AS
  a t1.id%TYPE := 'a';
BEGIN
  RETURN a;
END;
/

CREATE OR REPLACE FUNCTION fun4(v int) RETURN varchar AS
  FUNCTION inf1(v1 int) RETURN varchar AS
    a t1.id%TYPE := 'a';
  BEGIN
    RETURN a;
  END;
BEGIN
  RETURN inf1(4);
END;
/

CREATE OR REPLACE FUNCTION fun5(v t1.id%TYPE) RETURN varchar AS
  PROCEDURE inp1(v1 t1.id%TYPE) AS
    a varchar(10);
  BEGIN
    a := v1;
    raise notice '%', a;
  END;
BEGIN
  CALL inp1(v);
  RETURN 'a';
END;
/

SELECT fun3(3) FROM dual;
SELECT fun4(4) FROM dual;
SELECT fun5(5) FROM dual;

ALTER TABLE t1 RENAME TO t1_new;

--after renaming the table t1 to t1_new, call the function again
SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --failed
SELECT fun5(5) FROM dual;  --failed
ALTER FUNCTION fun3 COMPILE;
ALTER FUNCTION fun4 COMPILE;
ALTER FUNCTION fun5 COMPILE;

SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --failed
SELECT fun5(5) FROM dual;  --failed

DROP TABLE t1_new;
DROP FUNCTION fun3; 
DROP FUNCTION fun4; 
DROP FUNCTION fun5; 

--use tablename.columnname%TYPE in package
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE PACKAGE pkg1 is
  var1 t1.id%TYPE;
  FUNCTION pfun(v int) return varchar;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
  FUNCTION pfun(v int) RETURN varchar AS
    a t1.id%TYPE := 'a';
  BEGIN
    var1 := 'a';
    a := var1;
    RETURN a;
  END;
END;
/

DECLARE
BEGIN
  raise notice '%', pkg1.pfun(1);
END;
/

ALTER TABLE t1 RENAME TO t1_new;

--after renaming the table t1 to t1_new, failed to call the package function again
DECLARE
BEGIN
  raise notice '%', pkg1.pfun(1);
END;
/

DROP PACKAGE pkg1;
DROP TABLE t1_new;

--inherit table
CREATE TABLE father_table(c1 integer,c2 varchar(10));
CREATE TABLE child_table(c3 varchar(10)) inherits (father_table);

CREATE OR REPLACE FUNCTION fun6(v int) return varchar as
  a child_table.c3%TYPE := 'a';
BEGIN
  RETURN a;
END;
/

SELECT fun6(1) FROM dual;

ALTER TABLE child_table RENAME TO child_table_new;

SELECT fun6(1) FROM dual; --failed
ALTER FUNCTION fun6 COMPILE;
SELECT fun6(1) FROM dual; --failed

CREATE OR REPLACE FUNCTION fun7(v int) return varchar as
  a child_table_new.c2%TYPE := 'a';
BEGIN
  RETURN a;
END;
/
SELECT fun7(1) FROM dual;

ALTER TABLE father_table RENAME TO father_table_new;

SELECT fun7(1) FROM dual;
ALTER FUNCTION fun7 COMPILE;
SELECT fun7(1) FROM dual;

DROP FUNCTION fun6;
DROP FUNCTION fun7;
DROP TABLE child_table_new;
DROP TABLE father_table_new;


--1.1.5 DROP TABLE [ IF EXISTS ] name [, ...] [ CASCADE | RESTRICT ]
CREATE TABLE t1(id int, name varchar(20));

--function's parameter datatype is tablename.columnname%TYPE
CREATE OR REPLACE FUNCTION fun1(v t1.id%TYPE) RETURN varchar AS
BEGIN
  RETURN v;
END;
/

CREATE OR REPLACE PROCEDURE proc1(v t1.id%TYPE) AS
  a varchar(20);
BEGIN
  a := v;
  raise notice '%', a;
END;
/

SELECT fun1(1) FROM dual;
CALL proc1(1);

DROP TABLE t1;

--after dropping the table t1, failed to call the function again
SELECT fun1(1) FROM dual; --failed
CALL proc1(1); --failed
ALTER FUNCTION fun1 COMPILE;
ALTER PROCEDURE proc1 COMPILE;
SELECT fun1(1) FROM dual; --failed
CALL proc1(1); --failed

DROP FUNCTION fun1;
DROP PROCEDURE proc1;

--function's return datatype is tablename.columnname%TYPE
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun2(v int) RETURN t1.id%TYPE
AS
BEGIN
  RETURN 'a';
END;
/

SELECT fun2(2) FROM dual;
DROP TABLE t1;

--after dropping the table t1, failed to call the function again
SELECT fun2(2) FROM dual; --failed
ALTER FUNCTION fun2 COMPILE;
SELECT fun2(2) FROM dual; --failed

DROP FUNCTION fun2; 

--Variable datatype is tablename.columnname%TYPE
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE FUNCTION fun3(v int) RETURN varchar AS
  a t1.id%TYPE := 'a';
BEGIN
  RETURN a;
END;
/

CREATE OR REPLACE FUNCTION fun4(v int) RETURN varchar AS
  FUNCTION inf1(v1 int) RETURN varchar AS
    a t1.id%TYPE := 'a';
  BEGIN
    RETURN a;
  END;
BEGIN
  RETURN inf1(4);
END;
/

CREATE OR REPLACE FUNCTION fun5(v t1.id%TYPE) RETURN varchar AS
  PROCEDURE inp1(v1 t1.id%TYPE) AS
    a varchar(10);
  BEGIN
    a := v1;
    raise notice '%', a;
  END;
BEGIN
  CALL inp1(v);
  RETURN 'a';
END;
/

SELECT fun3(3) FROM dual;
SELECT fun4(4) FROM dual;
SELECT fun5(5) FROM dual;

DROP TABLE t1;

--after dropping the table t1, call the function again
SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --failed
SELECT fun5(5) FROM dual;  --failed

ALTER FUNCTION fun3 COMPILE;
ALTER FUNCTION fun4 COMPILE;
ALTER FUNCTION fun5 COMPILE;

SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --failed
SELECT fun5(5) FROM dual;  --failed

DROP FUNCTION fun3; 
DROP FUNCTION fun4; 
DROP FUNCTION fun5; 

--use tablename.columnname%TYPE in package
CREATE TABLE t1(id varchar(20), name varchar(20));

CREATE OR REPLACE PACKAGE pkg1 is
  var1 t1.id%TYPE;
  FUNCTION pfun(v int) return varchar;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
  FUNCTION pfun(v int) RETURN varchar AS
    a t1.id%TYPE := 'a';
  BEGIN
    var1 := 'a';
    a := var1;
    RETURN a;
  END;
END;
/

DECLARE
BEGIN
  raise notice '%', pkg1.pfun(1);
END;
/

DROP TABLE t1;

--after dropping the table t1, failed to call the package function again
DECLARE
BEGIN
  raise notice '%', pkg1.pfun(1);
END;
/

DROP PACKAGE pkg1;

--inherit table
CREATE TABLE father_table(c1 integer,c2 varchar(10));
CREATE TABLE child_table(c3 varchar(10)) inherits (father_table);

CREATE OR REPLACE FUNCTION fun6(v int) return varchar as
  a child_table.c3%TYPE := 'a';
BEGIN
  RETURN a;
END;
/

SELECT fun6(1) FROM dual;

DROP TABLE child_table;

SELECT fun6(1) FROM dual; --failed
ALTER FUNCTION fun6 COMPILE;
SELECT fun6(1) FROM dual; --failed

CREATE TABLE child_table(c3 varchar(10)) inherits (father_table);
CREATE OR REPLACE FUNCTION fun7(v int) return varchar as
  a child_table.c2%TYPE := 'a';
BEGIN
  RETURN a;
END;
/
SELECT fun7(1) FROM dual;

DROP TABLE father_table cascade;

SELECT fun7(1) FROM dual; --failed
ALTER FUNCTION fun7 COMPILE;
SELECT fun7(1) FROM dual; --failed

DROP FUNCTION fun6;
DROP FUNCTION fun7;


--1.2 The referencing variable inherits the data type and size of the referenced variable
--the following testcase will fail
DECLARE
  name     VARCHAR(25) NOT NULL := 'Niu';
  surname  name%TYPE := 'abcdefgabcdefgabcdefgabcdefg';
BEGIN
  raise notice 'name=%' ,name;
  raise notice 'surname=%' ,surname;
END;
/


--1.3 The referencing variable inherits the Constraints (unless the referenced item is a column) of the referenced variable
--the following testcase will fail
DECLARE
  name     VARCHAR(25) NOT NULL := 'Niu';
  surname  name%TYPE ;
BEGIN
  raise notice 'name=%' ,name;
  raise notice 'surname=%' ,surname;
END;
/

CREATE OR REPLACE PROCEDURE proc1(id int)
as
  name     VARCHAR(25) NOT NULL := 'Niu';
  surname  proc1.name%TYPE;
BEGIN
  null;
END;
/

--successfully
DECLARE
  name     VARCHAR(25) NOT NULL := 'Niu';
  surname  name%TYPE := 'Jones';
BEGIN
  raise notice 'name=%' ,name;
  raise notice 'surname=%' ,surname;
END;
/  

--the referenced item is a column with constraints 
CREATE TABLE t_notnull(id int NOT NULL);
DECLARE
  name     t_notnull.id%TYPE;
BEGIN
  raise notice 'name=%' ,name;
END;
/
DROP TABLE t_notnull;

--already supports cursor_variable%TYPE
CREATE TABLE tp1(unique1 int);
CREATE OR REPLACE PROCEDURE proc1(id int) 
AS
  curs1 CURSOR FOR SELECT * FROM tp1;
  curs2 refcursor;
  curs3 CURSOR (key integer) FOR SELECT * FROM tp1 WHERE unique1 = key;
  curs4 curs1%TYPE;
  curs5 curs2%TYPE;
  curs6 curs3%TYPE;
BEGIN
  OPEN curs1;
  CLOSE curs1;
END;
/	
CALL proc1(1);
DROP TABLE tp1;
DROP PROCEDURE proc1;

--2 %ROWTYPE
--2.1 function's parameter datatype is tablename%ROWTYPE
CREATE OR REPLACE PROCEDURE p0(v employees%ROWTYPE) AS
BEGIN
  raise notice 'v.first_name = %, v.last_name = %, v.phone_number = %',
    v.first_name, v.last_name, v.phone_number;
END;
/

DECLARE
  a employees%ROWTYPE;
BEGIN
  select * into a from employees ;
  raise notice 'a=%', a;
  call p0(a);
END;
/

\df p0

DROP PROCEDURE p0(employees%ROWTYPE);

--2.2 function's return datatype is tablename%ROWTYPE
CREATE OR REPLACE FUNCTION f1(v int) RETURN employees%ROWTYPE AS
  a employees%ROWTYPE;
BEGIN
  select * into a from employees ;
  RETURN a;
END;
/

DECLARE
  res employees%ROWTYPE;
BEGIN
  res := f1(1);
  raise notice 'res.first_name = %, res.last_name = %, res.phone_number = %',
    res.first_name, res.last_name, res.phone_number;
END;
/

\df f1
DROP FUNCTION f1;

--2.3 subprogram's parameter datatype and return datatype are tablename%ROWTYPE
DECLARE
  a employees%ROWTYPE;
  PROCEDURE p1(v employees%ROWTYPE) AS
  BEGIN
    raise notice 'v.first_name = %, v.last_name = %, v.phone_number = %',
      v.first_name, v.last_name, v.phone_number;
  END;

  FUNCTION f1(v int) RETURN employees%ROWTYPE AS
    a employees%ROWTYPE;
  BEGIN
    select * into a from employees ;
    RETURN a;
  END;
BEGIN
  CALL p1(f1(1));
END;
/

--2.4 The referencing variable inherits the data type and size of the referenced variable
CREATE TABLE t1 (
  c1 INTEGER DEFAULT 0 NOT NULL,
  c2 INTEGER DEFAULT 1 NOT NULL
);
 
DECLARE
  t1_row t1%ROWTYPE;
BEGIN
  raise notice 't1_row.c1 = %, t1_row.c2 = %', t1_row.c1, t1_row.c2;
END;
/
DROP TABLE t1;

--2.5 If the declaration of the referenced item is changed, then the declaration of the referencing item changes accordingly.
--2.5.1 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] ALTER [ COLUMN ] column_name [ SET DATA ] TYPE data_type [ COLLATE collation ] [ USING expression ]
CREATE TABLE tmpe (first_name varchar(20) not null, 
last_name varchar(20) not null,
phone_number varchar(50));
INSERT INTO tmpe VALUES ('Steven','Niu','1650');

CREATE OR REPLACE PROCEDURE p1(v tmpe%ROWTYPE) AS
  a tmpe.phone_number%TYPE;
BEGIN
  a := 'abc';
END;
/

CREATE OR REPLACE FUNCTION f1(v int) RETURN tmpe%ROWTYPE AS
  a tmpe%ROWTYPE;
BEGIN
  a.phone_number := 'abc';
  RETURN a;
END;
/

CREATE OR REPLACE PACKAGE pkg1 is
  var1 tmpe%ROWTYPE;
  FUNCTION pfun(v tmpe%ROWTYPE) RETURN tmpe%ROWTYPE;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
  FUNCTION pfun(v tmpe%ROWTYPE) RETURN tmpe%ROWTYPE AS
    r tmpe%ROWTYPE;
  BEGIN
    var1.phone_number := 'abc';
    r.phone_number :=  var1;
    RETURN v;
  END;
END;
/

ALTER TABLE tmpe ALTER COLUMN phone_number TYPE integer using phone_number::integer;

--after changing the column phone_number type from varchar to int, failed to call the function again
DECLARE
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  CALL p1(a);
END;
/

ALTER PROCEDURE p1 COMPILE;
DECLARE
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  CALL p1(a);
END;
/

DECLARE
  res tmpe%ROWTYPE;
BEGIN
  res := f1(1);
  raise notice 'res.first_name = %, res.last_name = %, res.phone_number = %',
    res.first_name, res.last_name, res.phone_number;
END;
/

DECLARE
BEGIN
  CALL p1(f1(1));
END;
/

DECLARE
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  raise notice '%', pkg1.pfun(a);
END;
/

DROP PROCEDURE p1(v tmpe%ROWTYPE);
DROP FUNCTION f1(v int);
DROP PACKAGE pkg1;
DROP TABLE tmpe CASCADE;


--2.5.2 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] DROP [ COLUMN ] [ IF EXISTS ] column_name [ RESTRICT | CASCADE ]
CREATE TABLE tmpe (first_name varchar(20) not null, 
last_name varchar(20) not null,
phone_number varchar(50));
INSERT INTO tmpe VALUES ('Steven','Niu','1650');

CREATE OR REPLACE PROCEDURE p1(v tmpe%ROWTYPE) AS
BEGIN
  raise notice 'v.first_name = %, v.last_name = %, v.phone_number = %',
    v.first_name, v.last_name, v.phone_number;
END;
/

CREATE OR REPLACE FUNCTION f1(v int) RETURN tmpe%ROWTYPE AS
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  raise notice 'a.first_name = %, a.last_name = %, a.phone_number = %',
    a.first_name, a.last_name, a.phone_number; 
  RETURN a;
END;
/

CREATE OR REPLACE FUNCTION f2(v int) RETURN varchar AS
  a tmpe%ROWTYPE;
BEGIN
  RETURN a.phone_number;
END;
/

CREATE OR REPLACE FUNCTION f3(v int) RETURN varchar AS
  a tmpe%ROWTYPE;
  r varchar(20);
BEGIN
  r := a.phone_number;
  RETURN r;
END;
/

CREATE OR REPLACE PACKAGE pkg1 is
  var1 tmpe%ROWTYPE;
  FUNCTION pfun(v tmpe%ROWTYPE) RETURN tmpe%ROWTYPE;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
  FUNCTION pfun(v tmpe%ROWTYPE) RETURN tmpe%ROWTYPE AS
    r tmpe%ROWTYPE;
  BEGIN
    r.phone_number :=  'abc';
    RETURN v;
  END;
END;
/

ALTER TABLE tmpe DROP COLUMN phone_number;

--after dropping the column phone_number, failed to call the function and procedure again
DECLARE
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  CALL p1(a);
END;
/

DECLARE
  res tmpe%ROWTYPE;
BEGIN
  res := f1(1);
  raise notice 'res.first_name = %, res.last_name = %, res.phone_number = %',
    res.first_name, res.last_name, res.phone_number;
END;
/

DECLARE
BEGIN
  CALL p1(f1(1));
END;
/

DECLARE
  res varchar(20);
BEGIN
  res := f2(1);
  raise notice 'res = %', res;
END;
/

DECLARE
  res varchar(20);
BEGIN
  res := f3(1);
  raise notice 'res = %', res;
END;
/

DECLARE
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  raise notice '%', pkg1.pfun(a);
END;
/

DROP PROCEDURE p1(v tmpe%ROWTYPE);
DROP FUNCTION f1(v int);
DROP FUNCTION f2(v int);
DROP FUNCTION f3(v int);
DROP PACKAGE pkg1;
DROP TABLE tmpe CASCADE;

--2.5.3 ALTER TABLE [ IF EXISTS ] [ ONLY ] name [ * ] RENAME [ COLUMN ] column_name TO new_column_name
CREATE TABLE tmpe (first_name varchar(20) not null, 
last_name varchar(20) not null,
phone_number varchar(50));
INSERT INTO tmpe VALUES ('Steven','Niu','1650');

CREATE OR REPLACE PROCEDURE p1(v tmpe%ROWTYPE) AS
BEGIN
  raise notice 'v.first_name = %, v.last_name = %, v.phone_number = %',
    v.first_name, v.last_name, v.phone_number;
END;
/

CREATE OR REPLACE FUNCTION f1(v int) RETURN tmpe%ROWTYPE AS
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  raise notice 'a.first_name = %, a.last_name = %, a.phone_number = %',
    a.first_name, a.last_name, a.phone_number; 
  RETURN a;
END;
/

CREATE OR REPLACE FUNCTION f2(v int) RETURN varchar AS
  a tmpe%ROWTYPE;
BEGIN
  RETURN a.phone_number;
END;
/

CREATE OR REPLACE FUNCTION f3(v int) RETURN varchar AS
  a tmpe%ROWTYPE;
  r varchar(20);
BEGIN
  r := a.phone_number;
  RETURN r;
END;
/

CREATE OR REPLACE PACKAGE pkg1 is
  var1 tmpe%ROWTYPE;
  FUNCTION pfun(v tmpe%ROWTYPE) RETURN tmpe%ROWTYPE;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
  FUNCTION pfun(v tmpe%ROWTYPE) RETURN tmpe%ROWTYPE AS
    r tmpe%ROWTYPE;
  BEGIN
    r.phone_number :=  'abc';
    RETURN v;
  END;
END;
/

ALTER TABLE tmpe RENAME COLUMN phone_number TO phone;

--after renaming the column phone_number to phone, failed to call the function 
DECLARE
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  CALL p1(a);
END;
/

DECLARE
  res tmpe%ROWTYPE;
BEGIN
  res := f1(1);
  raise notice 'res.first_name = %, res.last_name = %, res.phone_number = %',
    res.first_name, res.last_name, res.phone_number;
END;
/

DECLARE
BEGIN
  CALL p1(f1(1));
END;
/

DECLARE
  res varchar(20);
BEGIN
  res := f2(1);
  raise notice 'res = %', res;
END;
/

DECLARE
  res varchar(20);
BEGIN
  res := f3(1);
  raise notice 'res = %', res;
END;
/

DECLARE
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  raise notice '%', pkg1.pfun(a);
END;
/

DROP PROCEDURE p1(v tmpe%ROWTYPE);
DROP FUNCTION f1(v int);
DROP FUNCTION f2(v int);
DROP FUNCTION f3(v int);
DROP PACKAGE pkg1;
DROP TABLE tmpe CASCADE;


--2.5.4 ALTER TABLE [ IF EXISTS ] name  RENAME TO new_name
CREATE TABLE tmpe (first_name varchar(20) not null, 
last_name varchar(20) not null,
phone_number varchar(50));
INSERT INTO tmpe VALUES ('Steven','Niu','1650');

CREATE OR REPLACE PROCEDURE p1(v tmpe%ROWTYPE) AS
BEGIN
  raise notice 'v.first_name = %, v.last_name = %, v.phone_number = %',
    v.first_name, v.last_name, v.phone_number;
END;
/

CREATE OR REPLACE FUNCTION f1(v int) RETURN tmpe%ROWTYPE AS
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  raise notice 'a.first_name = %, a.last_name = %, a.phone_number = %',
    a.first_name, a.last_name, a.phone_number; 
  RETURN a;
END;
/

CREATE OR REPLACE FUNCTION f2(v int) RETURN varchar AS
  a tmpe%ROWTYPE;
BEGIN
  RETURN a.phone_number;
END;
/

CREATE OR REPLACE FUNCTION f3(v int) RETURN varchar AS
  a tmpe%ROWTYPE;
  r varchar(20);
BEGIN
  r := a.phone_number;
  RETURN r;
END;
/

CREATE OR REPLACE PACKAGE pkg1 is
  var1 tmpe%ROWTYPE;
  FUNCTION pfun(v tmpe%ROWTYPE) RETURN tmpe%ROWTYPE;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
  FUNCTION pfun(v tmpe%ROWTYPE) RETURN tmpe%ROWTYPE AS
    r tmpe%ROWTYPE;
  BEGIN
    r.phone_number :=  'abc';
    RETURN v;
  END;
END;
/

ALTER TABLE tmpe RENAME TO tmpe2;

--after renaming the table tmpe to tmpe2, failed to call the function and procedure again
DECLARE
  a tmpe2%ROWTYPE;
BEGIN
  select * into a from tmpe2;
  CALL p1(a);
END;
/

DECLARE
  res tmpe2%ROWTYPE;
BEGIN
  res := f1(1);
  raise notice 'res.first_name = %, res.last_name = %, res.phone_number = %',
    res.first_name, res.last_name, res.phone_number;
END;
/

DECLARE
BEGIN
  CALL p1(f1(1));
END;
/


DECLARE
  res varchar(20);
BEGIN
  res := f2(1);
  raise notice 'res = %', res;
END;
/

DECLARE
  res varchar(20);
BEGIN
  res := f3(1);
  raise notice 'res = %', res;
END;
/

DECLARE
  a tmpe2%ROWTYPE;
BEGIN
  select * into a from tmpe2;
  raise notice '%', pkg1.pfun(a);
END;
/

DROP PROCEDURE p1(v tmpe2%ROWTYPE);
DROP FUNCTION f1(v int);
DROP FUNCTION f2(v int);
DROP FUNCTION f3(v int);
DROP PACKAGE pkg1;
DROP TABLE tmpe2 CASCADE;


--2.5.5 DROP TABLE [ IF EXISTS ] name [, ...] [ CASCADE | RESTRICT ]
CREATE TABLE tmpe (first_name varchar(20) not null, 
  last_name varchar(20) not null,
  phone_number varchar(50));
INSERT INTO tmpe VALUES ('Steven','Niu','1650');

CREATE OR REPLACE PROCEDURE p1(v tmpe%ROWTYPE) AS
BEGIN
  raise notice 'v.first_name = %, v.last_name = %, v.phone_number = %',
    v.first_name, v.last_name, v.phone_number;
END;
/

CREATE OR REPLACE FUNCTION f1(v int) RETURN tmpe%ROWTYPE AS
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  raise notice 'a.first_name = %, a.last_name = %, a.phone_number = %',
    a.first_name, a.last_name, a.phone_number; 
  RETURN a;
END;
/

CREATE OR REPLACE FUNCTION f2(v int) RETURN varchar AS
  a tmpe%ROWTYPE;
BEGIN
  RETURN a.phone_number;
END;
/

CREATE OR REPLACE FUNCTION f3(v int) RETURN varchar AS
  a tmpe%ROWTYPE;
  r varchar(20);
BEGIN
  r := a.phone_number;
  RETURN r;
END;
/

CREATE OR REPLACE PACKAGE pkg1 is
  var1 tmpe%ROWTYPE;
  FUNCTION pfun(v tmpe%ROWTYPE) RETURN tmpe%ROWTYPE;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
  FUNCTION pfun(v tmpe%ROWTYPE) RETURN tmpe%ROWTYPE AS
    r tmpe%ROWTYPE;
  BEGIN
    r.phone_number :=  'abc';
    RETURN v;
  END;
END;
/

DROP TABLE tmpe;

--after dropping the table tmpe, failed to call the function and procedure
DECLARE
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  CALL p1(a);
END;
/

DECLARE
  res tmpe%ROWTYPE;
BEGIN
  res := f1(1);
  raise notice 'res.first_name = %, res.last_name = %, res.phone_number = %',
    res.first_name, res.last_name, res.phone_number;
END;
/

DECLARE
BEGIN
  CALL p1(f1(1));
END;
/

DECLARE
  res varchar(20);
BEGIN
  res := f2(1);
  raise notice 'res = %', res;
END;
/

DECLARE
  res varchar(20);
BEGIN
  res := f3(1);
  raise notice 'res = %', res;
END;
/

DECLARE
  a tmpe%ROWTYPE;
BEGIN
  select * into a from tmpe;
  raise notice '%', pkg1.pfun(a);
END;
/

DROP PROCEDURE p1;
DROP FUNCTION f1(v int);
DROP FUNCTION f2(v int);
DROP FUNCTION f3(v int);
DROP PACKAGE pkg1;


