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

-- test order-by clause when order-by columns are not in target list
SELECT employee, CONNECT_BY_ROOT employee_id as "Manager", SYS_CONNECT_BY_PATH(employee, '/') "Path"
FROM example
START WITH manager_id is not null
CONNECT BY PRIOR employee_id = manager_id
ORDER BY employee_id, manager_id;

-- test order-by clause, add order-by columns are to the target list
SELECT employee_id, manager_id, employee, CONNECT_BY_ROOT employee_id as "Manager", SYS_CONNECT_BY_PATH(employee, '/') "Path"
FROM example
START WITH manager_id is not null
CONNECT BY PRIOR employee_id = manager_id
ORDER BY employee_id, manager_id;

-- test CONNECT_BY_ROOT and SYS_CONNECT_BY_PATH when there associated
-- columns are not explicitly specified in the target list.
SELECT CONNECT_BY_ROOT manager_id, SYS_CONNECT_BY_PATH(id, '\') PATH
FROM t_tab
START WITH manager_id = 1
CONNECT BY PRIOR id = manager_id;

DROP TABLE IF EXISTS entities;
CREATE TABLE entities(
    parent_entity varchar(20),
    child_entity varchar(20),
    val int
);

INSERT INTO entities (parent_entity, child_entity,val) VALUES (NULL,'a',100);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('a', 'af',50);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('a', 'ab',50);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('a', 'ax',50);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('ab', 'abc',10);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('ab', 'abd',10);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('ab', 'abe',10);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('abe', 'abes',1);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('abe', 'abet',1);
INSERT INTO entities (parent_entity, child_entity,val) VALUES (NULL,'b',100);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('b', 'bg',50);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('b', 'bh',50);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('b', 'bi',50);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('bi', 'biq',10);
INSERT INTO entities (parent_entity, child_entity,val) VALUES ('bi', 'biv',10);

-- test ORDER BY clause
SELECT parent_entity, child_entity
FROM entities
CONNECT BY PRIOR child_entity = parent_entity
ORDER BY val, 1, 2;

SELECT parent_entity, child_entity
FROM entities
CONNECT BY PRIOR child_entity = parent_entity
ORDER BY val+1, 1, 2;

-- test multiple PRIOR
SELECT parent_entity, child_entity
FROM entities
CONNECT BY PRIOR child_entity = parent_entity AND PRIOR val = 50
ORDER BY 1, 2;

SELECT parent_entity, child_entity
FROM entities
START WITH parent_entity is NULL
CONNECT BY PRIOR child_entity = parent_entity
ORDER BY 1, 2;

-- test case expr with hierarchical statement
SELECT
  CASE SYS_CONNECT_BY_PATH(child_entity, '/')
    WHEN '/ab' THEN 'match /ab'
    WHEN '/abet' THEN 'match /abet'
    ELSE 'Not Matched'
  END AS "case connect by path",
  SYS_CONNECT_BY_PATH(child_entity, '/'),
  CASE CONNECT_BY_ROOT child_entity
    WHEN 'ab' THEN 'match ab'
    WHEN 'abet' THEN 'match abet'
    ELSE 'Not matched'
  END AS "case connect by root",
  CONNECT_BY_ROOT child_entity,
  LEVEL,
  parent_entity, child_entity
FROM entities
CONNECT BY PRIOR child_entity = parent_entity AND PRIOR val = 50
ORDER BY parent_entity;

-- test function call with hierarchical statement
DROP FUNCTION IF EXISTS hier_func_test(x VARCHAR);
CREATE OR REPLACE FUNCTION hier_func_test(x VARCHAR) RETURN VARCHAR AS
BEGIN
  return x;
END;
/

SELECT
  hier_func_test(SYS_CONNECT_BY_PATH(child_entity, '/')) AS "func connect by path",
  hier_func_test(CONNECT_BY_ROOT child_entity) AS "func connect by root",
  LEVEL,
  parent_entity, child_entity
FROM entities
CONNECT BY PRIOR child_entity = parent_entity AND PRIOR val = 50
ORDER BY 1, 2;

-- test array
SELECT ARRAY[['hello'],[ connect_by_root parent_entity]], child_entity
FROM entities
CONNECT BY PRIOR child_entity = parent_entity AND PRIOR val = 50
ORDER BY 1, 2;

-- test coalesce
SELECT COALESCE(connect_by_root parent_entity, 'nil'), child_entity
FROM entities
CONNECT BY PRIOR child_entity = parent_entity AND PRIOR val = 50
ORDER BY 1, 2;

-- test greatest
SELECT GREATEST(connect_by_root parent_entity, child_entity), child_entity
FROM entities
CONNECT BY PRIOR child_entity = parent_entity AND PRIOR val = 50
ORDER BY 1, 2;

-- test least
SELECT LEAST(connect_by_root parent_entity, child_entity), child_entity
FROM entities
CONNECT BY PRIOR child_entity = parent_entity AND PRIOR val = 50
ORDER BY 1, 2;

-- cleanup
DROP TABLE IF EXISTS example;
DROP TABLE IF EXISTS t_tab;
DROP TABLE IF EXISTS emp_;
DROP TABLE IF EXISTS entities;
DROP FUNCTION IF EXISTS hier_func_test(x VARCHAR);
