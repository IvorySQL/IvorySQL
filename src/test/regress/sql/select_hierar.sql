drop table if exists emp_;
CREATE TABLE emp_ (
empno NUMERIC(4) NOT NULL CONSTRAINT emp_pk PRIMARY KEY,
ename VARCHAR(10),
job VARCHAR(9),
mgr NUMERIC(4),
hiredate DATE,
sal NUMERIC(7,2),
comm NUMERIC(7,2),
deptno NUMERIC(2)
);

INSERT INTO emp_ VALUES (7369,'SMITH','CLERK',7902,'17-DEC-80',800,NULL,20);
INSERT INTO emp_ VALUES (7499,'ALLEN','SALESMAN',7698,'20-FEB-81',1600,300,30);
INSERT INTO emp_ VALUES (7521,'WARD','SALESMAN',7698,'22-FEB-81',1250,500,30);
INSERT INTO emp_ VALUES (7566,'JONES','MANAGER',7839,'02-APR-81',2975,NULL,20);
INSERT INTO emp_ VALUES (7654,'MARTIN','SALESMAN',7698,'28-SEP-81',1250,1400,30);
INSERT INTO emp_ VALUES (7698,'BLAKE','MANAGER',7839,'01-MAY-81',2850,NULL,30);
INSERT INTO emp_ VALUES (7782,'CLARK','MANAGER',7839,'09-JUN-81',2450,NULL,10);
INSERT INTO emp_ VALUES (7788,'SCOTT','ANALYST',7566,'19-APR-87',3000,NULL,20);
INSERT INTO emp_ VALUES (7839,'KING','PRESIDENT',NULL,'17-NOV-81',5000,NULL,10);
INSERT INTO emp_ VALUES (7844,'TURNER','SALESMAN',7698,'08-SEP-81',1500,0,30);
INSERT INTO emp_ VALUES (7876,'ADAMS','CLERK',7788,'23-MAY-87',1100,NULL,20);
INSERT INTO emp_ VALUES (7900,'JAMES','CLERK',7698,'03-DEC-81',950,NULL,30);
INSERT INTO emp_ VALUES (7902,'FORD','ANALYST',7566,'03-DEC-81',3000,NULL,20);
INSERT INTO emp_ VALUES (7934,'MILLER','CLERK',7782,'23-JAN-82',1300,NULL,10);

WITH RECURSIVE ref (level, empno, ename, mgr, sal) AS
(
    SELECT 1 AS level, empno, ename, mgr, sal
    FROM emp_
    WHERE ename = 'BLAKE'
    UNION ALL
    SELECT ref.level+1, emp_.empno, emp_.ename, emp_.mgr, emp_.sal
    FROM emp_, ref
    WHERE ref.empno = emp_.mgr
)
SELECT * FROM ref;

-- startwith, connectby
SELECT LEVEL, empno, ename, mgr, sal
FROM emp_
CONNECT BY PRIOR empno = mgr
START WITH ename = 'BLAKE';

CREATE TABLE t_tab (id int, manager_id int);
INSERT INTO t_tab VALUES (1, 0);
INSERT INTO t_tab VALUES (2, 1);
INSERT INTO t_tab VALUES (3, 2);
select * from t_tab;

-- PRIOR on left
WITH RECURSIVE test (id, manager_id) AS (
    SELECT id, manager_id FROM t_tab
  UNION ALL
    SELECT t2.id, t2.manager_id FROM test t, t_tab t2 WHERE t.id = t2.manager_id
  )
  SELECT * FROM test order by id;

SELECT id, manager_id from t_tab CONNECT BY prior id =  manager_id order by id;

-- PRIOR on right
WITH RECURSIVE test (id, manager_id) AS (
    SELECT id, manager_id FROM t_tab
  UNION ALL
    SELECT t2.id, t2.manager_id FROM test t, t_tab t2 WHERE t2.id = t.manager_id
  )
  SELECT * FROM test order by id;
SELECT id, manager_id from t_tab CONNECT BY  id =  prior manager_id order by id;


-- no PRIOR
WITH RECURSIVE test (id, manager_id) AS (
    SELECT id, manager_id FROM t_tab
  UNION ALL
    SELECT t2.id, t2.manager_id FROM test t, t_tab t2 WHERE t2.id = t2.manager_id
  )
  SELECT * FROM test order by id;

SELECT id, manager_id from t_tab CONNECT BY  id =  manager_id order by id;

-- tests with level in expression
SELECT id, manager_id, level, level * 100 * manager_id  from t_tab CONNECT BY prior id =  manager_id order by id;
SELECT level, level * 100 * manager_id, id, manager_id from t_tab CONNECT BY id =  prior manager_id order by id;

-- test CONNECT_BY_ROOT and SYS_CONNECT_BY_PATH
create table example(manager_id int, employee_id int, employee VARCHAR);
insert into example values(NULL, 1, 'Nick');
insert into example values(1, 2, 'Josh');
insert into example values(2, 3, 'Ali');
insert into example values(NULL, 4, 'Joe');
insert into example values(4, 5, 'Kyle');

SELECT employee_id, manager_id, employee, CONNECT_BY_ROOT employee_id as "Manager", SYS_CONNECT_BY_PATH(employee, '/') "Path"
FROM example
START WITH manager_id is not null
CONNECT BY PRIOR employee_id = manager_id
order by employee_id, manager_id;


-- cleanup
DROP TABLE IF EXISTS example;
DROP TABLE IF EXISTS t_tab;
DROP TABLE IF EXISTS emp_;
