-- Tests the case conversion rule for quoted identifiers.
-- 1. if guc parameter "identifier_case_switch" value is "interchange":
-- 	  1). If the alphas in the identifier quoted by double quotes are all the upper case, convert the upper case to the lower case.
-- 	  2). If the alphas in the identifier quoted by double quotes are all the lower case, convert the lower case to the upper case.
-- 	  3). If the alphas in the identifier quoted by double quotes are case-mixed, leave the identifier unchanged.
-- 2. if guc parameter "identifier_case_switch" value is "lowcase", convert all identifiers to the lower case.
-- 3. if guc parameter "identifier_case_switch" value is "normal", The rules for converting identifiers are the same as for native PG.

----1. "identifier_case_switch" value is "interchange"
SET ivorysql.enable_case_switch = true;
SET ivorysql.identifier_case_switch = interchange;
CREATE TABLE "ABC"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = 'ABC';
SELECT relname FROM pg_class WHERE relname = 'abc';
SELECT * FROM "ABC";
SELECT * FROM ABC;
SELECT * FROM abc;
SELECT * FROM Abc;
SELECT * FROM "Abc"; -- ERROR
DROP TABLE abc;

CREATE TABLE "Abc"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = 'ABC';
SELECT relname FROM pg_class WHERE relname = 'abc';
SELECT relname FROM pg_class WHERE relname = 'Abc';
SELECT * FROM "ABC"; -- ERROR
SELECT * FROM ABC; -- ERROR
SELECT * FROM abc; -- ERROR
SELECT * FROM Abc; -- ERROR
SELECT * FROM "Abc";
DROP TABLE "Abc";

CREATE TABLE "abc"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = 'ABC';
SELECT relname FROM pg_class WHERE relname = 'abc';
SELECT relname FROM pg_class WHERE relname = 'Abc';
SELECT * FROM "ABC"; -- ERROR
SELECT * FROM ABC; -- ERROR
SELECT * FROM abc; -- ERROR
SELECT * FROM Abc; -- ERROR
SELECT * FROM "Abc"; -- ERROR
SELECT * FROM "abc";
DROP TABLE "abc";

CREATE TABLE "中国ABC中国"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = '中国ABC中国';
SELECT relname FROM pg_class WHERE relname = '中国abc中国';
SELECT relname FROM pg_class WHERE relname = '中国Abc中国';
SELECT * FROM "中国ABC中国";
SELECT * FROM 中国ABC中国;
SELECT * FROM 中国abc中国;
SELECT * FROM "中国Abc中国"; -- ERROR
DROP TABLE "中国ABC中国";

CREATE TABLE "中国Abc中国"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = '中国ABC中国';
SELECT relname FROM pg_class WHERE relname = '中国abc中国';
SELECT relname FROM pg_class WHERE relname = '中国Abc中国';
SELECT * FROM "中国ABC中国"; -- ERROR
SELECT * FROM 中国ABC中国; -- ERROR
SELECT * FROM 中国abc中国; -- ERROR
SELECT * FROM "中国Abc中国";
DROP TABLE "中国Abc中国";

CREATE TABLE "中国abc中国"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = '中国ABC中国';
SELECT relname FROM pg_class WHERE relname = '中国abc中国';
SELECT relname FROM pg_class WHERE relname = '中国Abc中国';
SELECT * FROM "中国ABC中国"; -- ERROR
SELECT * FROM 中国ABC中国; -- ERROR
SELECT * FROM 中国abc中国; -- ERROR
SELECT * FROM "中国Abc中国"; -- ERROR
SELECT * FROM "中国abc中国";
DROP TABLE "中国abc中国";

CREATE TABLE t_48("ABC" int);
SELECT "ABC" FROM t_48;
SELECT ABC FROM t_48;
SELECT "abc" FROM t_48; -- ERROR
SELECT abc FROM t_48;
SELECT "Abc" FROM t_48; -- ERROR
SELECT attname FROM pg_attribute WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 't_48');
DROP TABLE t_48;

CREATE TABLE t_48("Abc" int);
SELECT "ABC" FROM t_48; -- ERROR
SELECT ABC FROM t_48; -- ERROR
SELECT "abc" FROM t_48; -- ERROR
SELECT abc FROM t_48; -- ERROR
SELECT "Abc" FROM t_48;
SELECT attname FROM pg_attribute WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 't_48');
DROP TABLE t_48;

CREATE TABLE t_48("abc" int);
SELECT "ABC" FROM t_48; -- ERROR
SELECT ABC FROM t_48; -- ERROR
SELECT "abc" FROM t_48;
SELECT abc FROM t_48; -- ERROR
SELECT "Abc" FROM t_48; -- ERROR
SELECT attname FROM pg_attribute WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 't_48');
DROP TABLE t_48;

CREATE TABLE "ABC"(a INT, b INT);
CREATE TABLE "abc"(a INT, b INT);
SELECT relname FROM pg_class WHERE relname in ('abc', 'ABC') order by relname;
INSERT INTO abc VALUES(1,1);
INSERT INTO "ABC" VALUES(2,2);
INSERT INTO ABC VALUES(3,3);
INSERT INTO "abc" VALUES(4,4);
SELECT * FROM "ABC";
SELECT * FROM "abc";
DROP TABLE "ABC";
DROP TABLE "abc";

--database
create database db1;
create database DB2;
create database "db3";
create database "DB4";
create database "Db5";
drop database db1;
drop database db2;
drop database "db3";
drop database "DB4";
drop database "Db5";

--user
create user u1;
create user U2;
create user "u3";
create user "U4";
create user "Uu5";
create user Uu6;
drop user u1;
drop user U2;
drop user "u3";
drop user "U4";
drop user "Uu5";
drop user Uu6;

RESET ivorysql.identifier_case_switch;

----2. "identifier_case_switch" value is "lowercase"
SET ivorysql.identifier_case_switch = lowercase;
CREATE TABLE "ABC"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = 'ABC';
SELECT relname FROM pg_class WHERE relname = 'abc';
SELECT * FROM "ABC";
SELECT * FROM ABC;
SELECT * FROM abc;
DROP TABLE "ABC";

CREATE TABLE "abc"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = 'ABC';
SELECT relname FROM pg_class WHERE relname = 'abc';
SELECT * FROM "abc";
SELECT * FROM ABC;
SELECT * FROM abc;
DROP TABLE "abc";

CREATE TABLE "Abc"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = 'Abc';
SELECT relname FROM pg_class WHERE relname = 'ABC';
SELECT relname FROM pg_class WHERE relname = 'abc';
SELECT * FROM "Abc";
SELECT * FROM ABC; -- ERROR
SELECT * FROM abc; -- ERROR
SELECT * FROM Abc; -- ERROR

DROP TABLE "Abc";

--database
create database db1;
create database DB2;
create database "db3";
create database "DB4";
create database "Db5";
drop database db1;
drop database db2;
drop database db3;
drop database db4;
drop database "Db5";

--user
create user u1;
create user U2;
create user "u3";
create user "U4";
create user "Uu5";
create user Uu6;
drop user u1;
drop user U2;
drop user u3;
drop user u4;
drop user "Uu5";
drop user uu6;

RESET ivorysql.identifier_case_switch;

----3. "identifier_case_switch" value is "normal"
SET ivorysql.identifier_case_switch = normal;
CREATE TABLE "ABC"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = 'ABC';
SELECT relname FROM pg_class WHERE relname = 'abc';
SELECT * FROM "ABC";
SELECT * FROM ABC; --ERROR
SELECT * FROM abc; --ERROR
DROP TABLE "ABC";

CREATE TABLE "abc"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = 'ABC';
SELECT relname FROM pg_class WHERE relname = 'abc';
SELECT * FROM "abc";
SELECT * FROM ABC;
SELECT * FROM abc;
DROP TABLE "abc";

CREATE TABLE "Abc"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = 'Abc';
SELECT relname FROM pg_class WHERE relname = 'ABC';
SELECT relname FROM pg_class WHERE relname = 'abc';
SELECT * FROM "Abc";
SELECT * FROM ABC; -- ERROR
SELECT * FROM abc; -- ERROR
SELECT * FROM Abc; -- ERROR

DROP TABLE "Abc";

--database
create database db1;
create database DB2;
create database "db3";
create database "DB4";
create database "Db5";
drop database db1;
drop database DB2;
drop database "db3";
drop database "DB4";
drop database "Db5";

--user
create user u1;
create user U2;
create user "u3";
create user "U4";
create user "Uu5";
create user Uu6;
drop user u1;
drop user U2;
drop user "u3";
drop user "U4";
drop user "Uu5";
drop user Uu6;

RESET ivorysql.identifier_case_switch;
RESET ivorysql.enable_case_switch;

----test guc parameter "enable_case_switch" feature
SET ivorysql.enable_case_switch = false;
SET ivorysql.identifier_case_switch = interchange;

CREATE TABLE "ABC"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = 'ABC';
SELECT relname FROM pg_class WHERE relname = 'abc';
SELECT * FROM "ABC";
SELECT * FROM ABC;	 -- ERROR
SELECT * FROM abc; 	 -- ERROR
SELECT * FROM Abc; 	 -- ERROR
SELECT * FROM "Abc"; -- ERROR
DROP TABLE "ABC";

CREATE TABLE "abc"(c1 int, c2 int);
SELECT relname FROM pg_class WHERE relname = 'ABC';
SELECT relname FROM pg_class WHERE relname = 'abc';
SELECT relname FROM pg_class WHERE relname = 'Abc';
SELECT * FROM "ABC"; -- ERROR
SELECT * FROM ABC; -- ERROR
SELECT * FROM abc; -- ERROR
SELECT * FROM Abc; -- ERROR
SELECT * FROM "Abc"; -- ERROR
SELECT * FROM "abc";
DROP TABLE "abc";

CREATE TABLE t_48("Abc" int);
SELECT "ABC" FROM t_48; -- ERROR
SELECT ABC FROM t_48; -- ERROR
SELECT "abc" FROM t_48; -- ERROR
SELECT abc FROM t_48; -- ERROR
SELECT "Abc" FROM t_48;
SELECT attname FROM pg_attribute WHERE attrelid = (SELECT oid FROM pg_class WHERE relname = 't_48');
DROP TABLE t_48;

RESET ivorysql.identifier_case_switch;
RESET ivorysql.enable_case_switch;
