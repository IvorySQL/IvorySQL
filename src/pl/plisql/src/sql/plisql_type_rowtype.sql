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
ALTER TABLE t1 ALTER COLUMN id TYPE integer using id::integer;

--because the column id type is changed from varchar to int, failed to call the function again
SELECT fun2(2) FROM dual; --failed
ALTER FUNCTION fun2 COMPILE;
SELECT prostatus FROM pg_proc WHERE proname like 'fun2'; --v
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
SELECT fun4(4) FROM dual;  --falled
SELECT fun5(5) FROM dual;  --successfully

ALTER FUNCTION fun3 COMPILE;
ALTER FUNCTION fun4 COMPILE;
ALTER FUNCTION fun5 COMPILE;
SELECT prostatus FROM pg_proc WHERE proname like 'fun3'; --v
SELECT prostatus FROM pg_proc WHERE proname like 'fun4'; --v
SELECT prostatus FROM pg_proc WHERE proname like 'fun5'; --v

SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --falled
SELECT fun5(5) FROM dual;  --successfully

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
SELECT fun4(4) FROM dual;  --falled
SELECT fun5(5) FROM dual;  --falled
ALTER FUNCTION fun3 COMPILE;
ALTER FUNCTION fun4 COMPILE;
ALTER FUNCTION fun5 COMPILE;

SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --falled
SELECT fun5(5) FROM dual;  --falled

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
SELECT fun4(4) FROM dual;  --falled
SELECT fun5(5) FROM dual;  --falled

ALTER FUNCTION fun3 COMPILE;
ALTER FUNCTION fun4 COMPILE;
ALTER FUNCTION fun5 COMPILE;

SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --falled
SELECT fun5(5) FROM dual;  --falled

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
SELECT fun4(4) FROM dual;  --falled
SELECT fun5(5) FROM dual;  --falled
ALTER FUNCTION fun3 COMPILE;
ALTER FUNCTION fun4 COMPILE;
ALTER FUNCTION fun5 COMPILE;

SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --falled
SELECT fun5(5) FROM dual;  --falled

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
SELECT fun4(4) FROM dual;  --falled
SELECT fun5(5) FROM dual;  --falled

ALTER FUNCTION fun3 COMPILE;
ALTER FUNCTION fun4 COMPILE;
ALTER FUNCTION fun5 COMPILE;

SELECT fun3(3) FROM dual;  --failed
SELECT fun4(4) FROM dual;  --falled
SELECT fun5(5) FROM dual;  --falled

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

--6 all_arguments system views
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SET IVORYSQL.IDENTIFIER_CASE_SWITCH = INTERCHANGE;

CREATE TABLE t1(id varchar(20), name varchar(20), id2 number(10,2));
CREATE TABLE t2(id int, name varchar(20));
CREATE VIEW view1 AS SELECT * FROM t1;

--argument is table%ROWTYPE
create or replace  function fn1(v1 t1%ROWTYPE, v2 t2%ROWTYPE, v3 t1.id%TYPE, v4 int) return t1%ROWTYPE as
 a t1%ROWTYPE;
begin
  return a;
end;
/

SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.ALL_ARGUMENTS where OBJECT_NAME like 'FN1';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.USER_ARGUMENTS where OBJECT_NAME like 'FN1';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.DBA_ARGUMENTS where OBJECT_NAME like 'FN1';

--argument is view%ROWTYPE
create or replace  function fn2(v1 view1%ROWTYPE, v2 t2%ROWTYPE, v3 view1.id%TYPE, v4 int) return view1%ROWTYPE as
 a view1%ROWTYPE;
begin
  return a;
end;
/

SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.ALL_ARGUMENTS where OBJECT_NAME like 'FN2';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.USER_ARGUMENTS where OBJECT_NAME like 'FN2';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.DBA_ARGUMENTS where OBJECT_NAME like 'FN2';

--package.var%TYPE
CREATE OR REPLACE PACKAGE pkg1 is
  var1 int;
  var2 t1%ROWTYPE;
  var3 view1%ROWTYPE;
  var4 varchar(40);
  var5 number(10,3);
  FUNCTION pfun(v int) return int;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg1 is
  FUNCTION pfun(v int) RETURN int AS
  BEGIN
    RETURN 1;
  END;
END;
/

create or replace  function fp1(v1 pkg1.var1%TYPE, v2 pkg1.var2%TYPE, v3 pkg1.var3%TYPE, v4 pkg1.var4%TYPE, v5 pkg1.var5%TYPE) return int as
begin
  return 1;
end;
/

SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.ALL_ARGUMENTS where OBJECT_NAME like 'FP1';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.USER_ARGUMENTS where OBJECT_NAME like 'FP1';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.DBA_ARGUMENTS where OBJECT_NAME like 'FP1';

--table.column%TYPE is varchar
create or replace procedure fn3(v1 t1.name%TYPE, v2 t1.id2%TYPE) as
begin
  null;
end;
/
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.ALL_ARGUMENTS where OBJECT_NAME like 'FN3';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.USER_ARGUMENTS where OBJECT_NAME like 'FN3';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.DBA_ARGUMENTS where OBJECT_NAME like 'FN3';

--a package function argument referenced another package var
CREATE OR REPLACE PACKAGE pkg2 is
  FUNCTION pfun2(v pkg1.var1%TYPE) RETURN pkg1.var2%TYPE;
END;
/

CREATE OR REPLACE PACKAGE BODY pkg2 is
  FUNCTION pfun2(v pkg1.var1%TYPE) RETURN pkg1.var2%TYPE AS
    a pkg1.var2%TYPE;
  BEGIN
    RETURN a;
  END;
END;
/
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.ALL_ARGUMENTS where OBJECT_NAME like 'PFUN2';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.USER_ARGUMENTS where OBJECT_NAME like 'PFUN2';
SELECT object_name,package_name,subprogram_id,argument_name,position,sequence,data_level,data_type,defaulted,default_value,default_length,in_out,data_length,data_precision,data_scale,
  radix,type_name,type_subname,type_object_type,pls_type,char_length,char_used,origin_con_id FROM SYS.DBA_ARGUMENTS where OBJECT_NAME like 'PFUN2';

DROP PACKAGE pkg2;
DROP FUNCTION fp1;
DROP PACKAGE pkg1;
DROP FUNCTION fn1;
DROP FUNCTION fn2;
DROP PROCEDURE fn3;
DROP VIEW view1;
DROP TABLE t1;
DROP TABLE t2;

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
