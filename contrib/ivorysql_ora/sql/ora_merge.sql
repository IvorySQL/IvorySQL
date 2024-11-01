--
-- Ivory_merge
--
--SET compatible_mode = oracle;

CREATE TABLE people_source (
  person_id  INTEGER NOT NULL PRIMARY KEY,
  first_name VARCHAR(20) NOT NULL,
  last_name  VARCHAR(20) NOT NULL,
  title      VARCHAR(10) NOT NULL
);

CREATE TABLE people_target (
  person_id  INTEGER NOT NULL PRIMARY KEY,
  first_name VARCHAR(20) NOT NULL,
  last_name  VARCHAR(20) NOT NULL,
  title      VARCHAR(10) NOT NULL
);


INSERT INTO people_target VALUES (1, 'John', 'Smith', 'Mr');
INSERT INTO people_target VALUES (2, 'alice', 'jones', 'Mrs');
INSERT INTO people_target VALUES (3, 'tony', 'james', 'Mr');

INSERT INTO people_source VALUES (2, 'Alice', 'Jones', 'Mrs.');
INSERT INTO people_source VALUES (3, 'Jane', 'Doe', 'Miss');
INSERT INTO people_source VALUES (4, 'Dave', 'Brown', 'Mr');

SELECT * FROM people_target;
SELECT * FROM people_source;

--
-- Test WHEN MATCHED THEN update
--
BEGIN;

MERGE INTO people_target pt
USING people_source ps
ON    (pt.person_id = ps.person_id)
WHEN MATCHED THEN UPDATE
  SET pt.first_name = ps.first_name,
      pt.last_name = ps.last_name,
      pt.title = ps.title
;

SELECT * FROM people_target;

ROLLBACK;

-- Add WHERE condition
BEGIN;

MERGE INTO people_target pt
USING people_source ps
ON    (pt.person_id = ps.person_id)
WHEN MATCHED THEN UPDATE
  SET pt.first_name = ps.first_name,
      pt.last_name = ps.last_name,
      pt.title = ps.title
      WHERE pt.title = 'Mrs'
;

SELECT * FROM people_target;

ROLLBACK;

-- Append DELETE clause
-- 1
BEGIN;

MERGE INTO people_target pt
USING people_source ps
ON    (pt.person_id = ps.person_id)
WHEN MATCHED THEN UPDATE
  SET pt.first_name = ps.first_name,
      pt.last_name = ps.last_name,
      pt.title = ps.title
  DELETE WHERE pt.title  = 'Mrs.';

SELECT * FROM people_target;

ROLLBACK;


-- Append DELETE clause
-- 2
BEGIN;

MERGE INTO people_target pt
USING people_source ps
ON    (pt.person_id = ps.person_id)
WHEN MATCHED THEN
  UPDATE SET pt.first_name = ps.first_name,
             pt.last_name = ps.last_name,
             pt.title = ps.title
         WHERE pt.title = 'Mrs'
  DELETE WHERE pt.title  = 'Mrs.'
;

SELECT * FROM people_target;

ROLLBACK;


--
-- Test WHEN NOT MATCHED THEN insert
--
BEGIN;

MERGE INTO people_target pt
USING people_source ps
ON    (pt.person_id = ps.person_id)
WHEN NOT MATCHED THEN
  INSERT (person_id, first_name, last_name, title)
   VALUES (ps.person_id, ps.first_name, ps.last_name, ps.title)
;

SELECT * FROM people_target;

ROLLBACK;

--
-- Test WHEN MATCHED & WHEN NOT MATCHED
--
BEGIN;

MERGE INTO people_target pt
USING people_source ps
ON    (pt.person_id = ps.person_id)
WHEN MATCHED THEN
  UPDATE SET pt.first_name = ps.first_name,
             pt.last_name = ps.last_name,
             pt.title = ps.title
         WHERE pt.title = 'Mrs'
  DELETE WHERE pt.title  = 'Mrs.'
WHEN NOT MATCHED THEN
  INSERT (person_id, first_name, last_name, title)
   VALUES (ps.person_id, ps.first_name, ps.last_name, ps.title)
;

SELECT * FROM people_target;

ROLLBACK;


--
-- Test Columns referenced in the ON Clause cannot be updated
--
-- 1
MERGE INTO people_target pt
USING people_source ps
ON    (pt.person_id = ps.person_id)
WHEN MATCHED THEN UPDATE
  SET pt.person_id = pt.person_id + 10
;

-- 2
MERGE INTO people_target pt
USING people_source ps
ON    (pt.person_id + 1 = ps.person_id + 1)
WHEN MATCHED THEN UPDATE
  SET pt.person_id = pt.person_id + 10
;

-- 3
CREATE OR REPLACE FUNCTION tco(x int) RETURNS INT
AS $$
BEGIN
	RETURN x;
END;
$$ LANGUAGE plpgsql;
/

MERGE INTO people_target pt
USING people_source ps
ON    (tco(pt.person_id) = ps.person_id)
WHEN MATCHED THEN UPDATE
  SET pt.person_id = pt.person_id + 10
;

DROP FUNCTION tco;
SELECT * FROM people_target;


--
-- Test trigger
--

-- trigger functions
CREATE OR REPLACE FUNCTION up_trigg_before() RETURNS trigger
AS $$
BEGIN
    RAISE info 'Before update trigger -> Updating';
    RETURN old;
END;
$$ LANGUAGE plpgsql;
/

CREATE OR REPLACE FUNCTION up_trigg_after() RETURNS trigger
AS $$
BEGIN
    RAISE info 'After update trigger -> Updating';
    INSERT INTO people_target VALUES(23, 'LeBron', 'James', 'Mr');
    RETURN old;
END;
$$ LANGUAGE plpgsql;
/

CREATE OR REPLACE FUNCTION del_trigg_before() RETURNS trigger
AS $$
BEGIN
    RAISE info 'Before delete trigger -> Deleting';
    RETURN old;
END;
$$ LANGUAGE plpgsql;
/

CREATE OR REPLACE FUNCTION del_trigg_after() RETURNS trigger
AS $$
BEGIN
    RAISE info 'After delete trigger -> Deleting';
    RETURN old;
END;
$$ LANGUAGE plpgsql;
/

-- create statement-level trigger
CREATE TRIGGER tri_update_be BEFORE UPDATE ON people_target
 FOR EACH STATEMENT EXECUTE PROCEDURE up_trigg_before();

CREATE TRIGGER tri_update_af AFTER UPDATE ON people_target
 FOR EACH STATEMENT EXECUTE PROCEDURE up_trigg_after();

CREATE TRIGGER tri_delete_be BEFORE DELETE ON people_target
 FOR EACH STATEMENT EXECUTE PROCEDURE del_trigg_before();

CREATE TRIGGER tri_delete_af AFTER DELETE ON people_target
 FOR EACH STATEMENT EXECUTE PROCEDURE del_trigg_after();


-- Merge statement
BEGIN;

MERGE INTO people_target pt
USING people_source ps
ON    (pt.person_id = ps.person_id)
WHEN MATCHED THEN UPDATE
  SET pt.first_name = ps.first_name,
      pt.last_name = ps.last_name,
      pt.title = ps.title
  DELETE WHERE pt.title  = 'Mrs.';

select * from people_target;

ROLLBACK;

-- cleanup
drop trigger tri_update_be on people_target;
drop trigger tri_update_af on people_target;
drop trigger tri_delete_be on people_target;
drop trigger tri_delete_af on people_target;

drop function up_trigg_before;
drop function up_trigg_after;
drop function del_trigg_before;
drop function del_trigg_after;


-- row-level trigger function, modify the NEW.title
CREATE OR REPLACE FUNCTION trigger_test() RETURNS trigger
AS $$
BEGIN
  RAISE INFO 'trigger_test-> new.title';
  NEW.title := 'abc';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
/

CREATE TRIGGER row_tri_bef_up BEFORE UPDATE ON people_target
  FOR EACH ROW EXECUTE PROCEDURE trigger_test();

-- Merge statement
BEGIN;

MERGE INTO people_target pt
USING people_source ps
ON    (pt.person_id = ps.person_id)
WHEN MATCHED THEN UPDATE
  SET pt.first_name = ps.first_name,
      pt.last_name = ps.last_name
  DELETE WHERE pt.title  = 'Mrs.';

SELECT * FROM people_target;

ROLLBACK;

-- cleanup
drop trigger row_tri_bef_up on people_target;
drop function trigger_test;

drop table people_target;
drop table people_source;


CREATE TABLE members (
    member_id INT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    rank VARCHAR(20)
);

CREATE TABLE member_staging AS
SELECT * FROM members;

-- insert into members table
INSERT INTO members(member_id, first_name, last_name, rank) VALUES(1,'Abel','Wolf','Gold');
INSERT INTO members(member_id, first_name, last_name, rank) VALUES(2,'Clarita','Franco','Platinum');
INSERT INTO members(member_id, first_name, last_name, rank) VALUES(3,'Darryl','Giles','Silver');
INSERT INTO members(member_id, first_name, last_name, rank) VALUES(4,'Dorthea','Suarez','Silver');
INSERT INTO members(member_id, first_name, last_name, rank) VALUES(5,'Katrina','Wheeler','Silver');
INSERT INTO members(member_id, first_name, last_name, rank) VALUES(6,'Lilian','Garza','Silver');
INSERT INTO members(member_id, first_name, last_name, rank) VALUES(7,'Ossie','Summers','Gold');
INSERT INTO members(member_id, first_name, last_name, rank) VALUES(8,'Paige','Mcfarland','Platinum');
INSERT INTO members(member_id, first_name, last_name, rank) VALUES(9,'Ronna','Britt','Platinum');
INSERT INTO members(member_id, first_name, last_name, rank) VALUES(10,'Tressie','Short','Bronze');

-- insert into member_staging table
INSERT INTO member_staging(member_id, first_name, last_name, rank) VALUES(1,'Abel','Wolf','Silver');
INSERT INTO member_staging(member_id, first_name, last_name, rank) VALUES(2,'Clarita','Franco','Platinum');
INSERT INTO member_staging(member_id, first_name, last_name, rank) VALUES(3,'Darryl','Giles','Bronze');
INSERT INTO member_staging(member_id, first_name, last_name, rank) VALUES(4,'Dorthea','Gate','Gold');
INSERT INTO member_staging(member_id, first_name, last_name, rank) VALUES(5,'Katrina','Wheeler','Silver');
INSERT INTO member_staging(member_id, first_name, last_name, rank) VALUES(6,'Lilian','Stark','Silver');

SELECT * FROM members ORDER BY member_id;
SELECT * FROM member_staging ORDER BY member_id;

-- Test MATCHED and NOT MATCHED
BEGIN;

MERGE INTO member_staging x
USING (SELECT member_id, first_name, last_name, rank FROM members) y
ON (x.member_id  = y.member_id)
WHEN MATCHED THEN
    UPDATE SET x.first_name = y.first_name,
                        x.last_name = y.last_name,
                        x.rank = y.rank
    WHERE x.first_name <> y.first_name OR
           x.last_name <> y.last_name OR
           x.rank <> y.rank
WHEN NOT MATCHED THEN
    INSERT(member_id, first_name, last_name, rank)
    VALUES(y.member_id, y.first_name, y.last_name, y.rank)
;

SELECT * FROM member_staging ORDER BY member_id;

ROLLBACK;

-- Add DELETE clause
BEGIN;

MERGE INTO member_staging x
USING (SELECT member_id, first_name, last_name, rank FROM members) y
ON (x.member_id  = y.member_id)
WHEN MATCHED THEN
    UPDATE SET x.first_name = y.first_name,
                        x.last_name = y.last_name,
                        x.rank = y.rank
    WHERE x.first_name <> y.first_name OR
           x.last_name <> y.last_name OR
           x.rank <> y.rank
    DELETE WHERE x.rank = 'Silver'
WHEN NOT MATCHED THEN
    INSERT(member_id, first_name, last_name, rank)
    VALUES(y.member_id, y.first_name, y.last_name, y.rank)
;

SELECT * FROM member_staging ORDER BY member_id;

ROLLBACK;

--
-- Test alias.column in INSERT clause
--
show ivorysql.insert_enable_alias;
-- enable insert alias
set ivorysql.insert_enable_alias to on;
show ivorysql.insert_enable_alias;

BEGIN;

MERGE INTO member_staging x
USING (SELECT member_id, first_name, last_name, rank FROM members) y
ON (x.member_id  = y.member_id)
WHEN MATCHED THEN
    UPDATE SET x.first_name = y.first_name,
                        x.last_name = y.last_name,
                        x.rank = y.rank
    WHERE x.first_name <> y.first_name OR
           x.last_name <> y.last_name OR
           x.rank <> y.rank
    DELETE WHERE x.rank = 'Silver'
WHEN NOT MATCHED THEN
    INSERT(x.member_id, x.first_name, x.last_name, x.rank)
    VALUES(y.member_id, y.first_name, y.last_name, y.rank)
;

SELECT * FROM member_staging ORDER BY member_id;

ROLLBACK;

-- EXPLAIN
BEGIN;

EXPLAIN (COSTS OFF) MERGE INTO member_staging x
USING (SELECT member_id, first_name, last_name, rank FROM members) y
ON (x.member_id  = y.member_id)
WHEN MATCHED THEN
    UPDATE SET x.first_name = y.first_name,
                        x.last_name = y.last_name,
                        x.rank = y.rank
    WHERE x.first_name <> y.first_name OR
           x.last_name <> y.last_name OR
           x.rank <> y.rank
    DELETE WHERE x.rank = 'Silver'
WHEN NOT MATCHED THEN
    INSERT(x.member_id, x.first_name, x.last_name, x.rank)
    VALUES(y.member_id, y.first_name, y.last_name, y.rank)
;

SELECT * FROM member_staging ORDER BY member_id;

ROLLBACK;

reset ivorysql.insert_enable_alias;
drop table members;
drop table member_staging;

--

--
CREATE TABLE target (tid integer, balance integer);
CREATE TABLE source (sid integer, delta integer);

INSERT INTO target VALUES (1, 10);
INSERT INTO target VALUES (2, 20);
INSERT INTO target VALUES (3, 30);

INSERT INTO source VALUES (2, 5);
INSERT INTO source VALUES (3, 20);
INSERT INTO source VALUES (2, 5);

SELECT * from target;
SELECT * from source;

-- Merge statement
MERGE INTO target t
USING source s
ON (t.tid = s.sid)
WHEN MATCHED THEN
	UPDATE SET balance = 0
	DELETE WHERE balance = 0;

drop table target;
drop table source;


--

--
CREATE TABLE wq_target_TIMU048170046 (tid integer not null, balance integer DEFAULT -1);
CREATE TABLE wq_source_TIMU048170046 (balance integer, sid integer);

INSERT INTO wq_source_TIMU048170046 (sid, balance) VALUES (1, 100);

select * from wq_target_TIMU048170046;
select * from wq_source_TIMU048170046;

create or replace function merge_when_and_write_TIMU048170046(bflag int)
RETURN int
IS
BEGIN
    IF bflag <10 then
        RETURN 1;
    ELSE
        RETURN 0;
    END IF;
    ROLLBACK;
END;
/

MERGE INTO wq_target_TIMU048170046 t
USING wq_source_TIMU048170046 s ON (t.tid = s.sid)
WHEN MATCHED THEN
UPDATE SET balance = t.balance + s.balance
  WHERE merge_when_and_write_TIMU048170046(8)=1;

MERGE INTO wq_source_TIMU048170046 t
USING wq_source_TIMU048170046 s ON (t.ctid = s.ctid)
WHEN MATCHED THEN
 UPDATE SET ctid = s.ctid;


INSERT INTO wq_target_TIMU048170046 (tid, balance) VALUES (1, 100);

MERGE INTO wq_target_TIMU048170046 t
USING wq_target_TIMU048170046 s ON (t.ctid = s.ctid)
WHEN MATCHED THEN
 UPDATE SET balance = t.balance + s.balance;

select * from wq_target_TIMU048170046;
DROP function merge_when_and_write_TIMU048170046;
DROP table wq_target_TIMU048170046;
DROP table wq_source_TIMU048170046;
