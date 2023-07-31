show ivorysql.enable_emptystring_to_NULL;
CREATE TABLE null_tb (id number);
ALTER TABLE null_tb add (salary float default '');
INSERT INTO null_tb (id) VALUES (1);
SELECT id FROM null_tb WHERE salary is NULL;
DROP TABLE null_tb;

CREATE TABLE null_student
(id number NOT NULL,name varchar2(8)
,special_id number
,grade float
,birthday date
,remark varchar2(255));
INSERT INTO null_student (id,grade) VALUES (6,'');
SELECT * FROM null_student;
DROP TABLE null_student;

CREATE TABLE test1(a int,b varchar(20) default '' not null);
INSERT INTO test1(a) VALUES(1);	--error
INSERT INTO test1(a,b) VALUES(2,'aa');
INSERT INTO test1(a,b) VALUES(3, 'aaa');
INSERT INTO test1(b) VALUES (''); --error
DROP TABLE test1;

CREATE TABLE test2(x int, n numeric, t timestamp,d date,r real,p double precision);
INSERT INTO test2 VALUES (1,1.23, to_timestamp_tz('2021-01-13 16:44:43.566308+08','YYYY-MM-DD HH24:MI:SS.FF TZH:TZM'),to_date('2021-01-13','YYYY-MM-DD'),1.2, 12.344444);
INSERT INTO test2 VALUES (2,NULL,NULL,NULL,NULL,NULL);
INSERT INTO test2 VALUES (3,'','','','','');
SELECT * FROM test2 WHERE n is NULL;
SELECT * FROM test2 WHERE n=NULL;
SELECT * FROM test2 WHERE n='';

UPDATE test2 set t='' WHERE x=1;
SELECT * FROM test2 WHERE t is NULL;
UPDATE test2 set d=null WHERE x=1;
SELECT * FROM test2 WHERE d is NULL;
DROP TABLE test2;

SELECT 1+'';
SELECT 1-'';
SELECT 1*'';
SELECT 1/'';
SELECT 1%'';

set temp_tablespaces to '';
reset temp_tablespaces;
SELECT length('') FROM dual;
