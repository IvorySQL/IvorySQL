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
    INSERT(member_id, first_name, last_name, rank)
    VALUES(y.member_id, y.first_name, y.last_name, y.rank)
;

SELECT * FROM member_staging ORDER BY member_id;

ROLLBACK;

drop table members;
drop table member_staging;

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

--
-- Test MERGE on trigger-updatable views (UPDATE and UPDATE ... DELETE WHERE)
--
CREATE TABLE merge_view_base (id int PRIMARY KEY, val int);
INSERT INTO merge_view_base VALUES (1, 10), (2, 20), (3, 30);
CREATE VIEW merge_view_upd AS SELECT id, val FROM merge_view_base;

CREATE OR REPLACE FUNCTION merge_view_upd_fn() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        UPDATE merge_view_base SET val = NEW.val WHERE id = OLD.id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        DELETE FROM merge_view_base WHERE id = OLD.id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;
/

CREATE TRIGGER merge_view_upd_trg
    INSTEAD OF UPDATE ON merge_view_upd
    FOR EACH ROW EXECUTE FUNCTION merge_view_upd_fn();

-- View with INSTEAD OF UPDATE only: plain UPDATE succeeds
MERGE INTO merge_view_upd t
USING (SELECT 1 AS id, 15 AS val) s
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET val = s.val;
SELECT * FROM merge_view_base ORDER BY id;

-- View without INSTEAD OF DELETE: DELETE WHERE errors cleanly instead of crashing
MERGE INTO merge_view_upd t
USING (SELECT 1 AS id, -5 AS val) s
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET val = s.val DELETE WHERE t.val < 0;
SELECT * FROM merge_view_base ORDER BY id;

-- View with both INSTEAD OF UPDATE and INSTEAD OF DELETE: UPDATE + DELETE WHERE works
CREATE TRIGGER merge_view_del_trg
    INSTEAD OF DELETE ON merge_view_upd
    FOR EACH ROW EXECUTE FUNCTION merge_view_upd_fn();

MERGE INTO merge_view_upd t
USING (VALUES (1, -1), (2, 25)) AS s(id, val)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET val = s.val DELETE WHERE s.val < 0
RETURNING merge_action(), t.id, t.val;
SELECT * FROM merge_view_base ORDER BY id;

DROP VIEW merge_view_upd;
DROP FUNCTION merge_view_upd_fn();
DROP TABLE merge_view_base;

--
-- Test cross-partition MERGE UPDATE and UPDATE ... DELETE WHERE
--
CREATE TABLE merge_part (id int, part int, val int) PARTITION BY LIST (part);
CREATE TABLE merge_part_1 PARTITION OF merge_part FOR VALUES IN (1);
CREATE TABLE merge_part_2 PARTITION OF merge_part FOR VALUES IN (2);
INSERT INTO merge_part VALUES (1, 1, 10), (2, 1, 20), (3, 1, 30);

-- Cross-partition UPDATE without DELETE WHERE (row 2 moves to part 2)
-- and with DELETE WHERE (row 1 moves to part 2 then gets deleted from part 2;
-- sibling row 3 in part 1 must remain intact).
MERGE INTO merge_part t
USING (VALUES (1, 2, -5), (2, 2, 25)) AS s(id, part, val)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET part = s.part, val = s.val DELETE WHERE t.val < 0;

SELECT tableoid::regclass AS part_rel, id, part, val FROM merge_part ORDER BY id;
DROP TABLE merge_part;

--
-- Test MERGE UPDATE ... DELETE WHERE with RETURNING merge_action()
--
CREATE TABLE merge_ret_t (id int PRIMARY KEY, val int);
INSERT INTO merge_ret_t VALUES (1, 10), (2, 20);
MERGE INTO merge_ret_t t
USING (VALUES (1, -5), (2, 25)) AS s(id, val)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET val = s.val DELETE WHERE t.val < 0
RETURNING merge_action(), t.id, t.val;
SELECT * FROM merge_ret_t ORDER BY id;
DROP TABLE merge_ret_t;

--
-- Test cross-partition MERGE UPDATE ... DELETE WHERE with RETURNING on a
-- destination partition having a dropped column, reordered columns, and a
-- BEFORE INSERT trigger.
--
CREATE TABLE merge_part_ret (id int, part int, val int) PARTITION BY LIST (part);
CREATE TABLE merge_part_ret_1 PARTITION OF merge_part_ret FOR VALUES IN (1);
CREATE TABLE merge_part_ret_2 (extra text, val int, part int, id int);
ALTER TABLE merge_part_ret_2 DROP COLUMN extra;
ALTER TABLE merge_part_ret ATTACH PARTITION merge_part_ret_2 FOR VALUES IN (2);

CREATE OR REPLACE FUNCTION merge_part_ret_bi_fn() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.val := NEW.val * 10;
    RETURN NEW;
END;
$$;
/

CREATE TRIGGER merge_part_ret_bi_trg
    BEFORE INSERT ON merge_part_ret_2
    FOR EACH ROW EXECUTE FUNCTION merge_part_ret_bi_fn();

INSERT INTO merge_part_ret VALUES (1, 1, 10), (2, 1, 20), (3, 1, 30);

MERGE INTO merge_part_ret t
USING (VALUES (1, 2, -5), (2, 2, 25)) AS s(id, part, val)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET part = s.part, val = s.val DELETE WHERE t.val < -10
RETURNING tableoid::regclass AS ret_rel, merge_action(), t.id, t.part, t.val;

SELECT tableoid::regclass AS part_rel, id, part, val FROM merge_part_ret ORDER BY id;
DROP TABLE merge_part_ret;
DROP FUNCTION merge_part_ret_bi_fn();

--
-- Test multiple WHEN MATCHED clauses: unmatched first UPDATE ... DELETE WHERE
-- must skip its attached DELETE clause and evaluate subsequent WHEN MATCHED.
--
CREATE TABLE merge_multi_when (id int PRIMARY KEY, val int);
INSERT INTO merge_multi_when VALUES (1, -10), (2, 20), (3, -30);

MERGE INTO merge_multi_when t
USING (VALUES (1, 100, 2), (2, -1, 1), (3, 200, 2)) AS s(id, val, flag)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET val = s.val WHERE s.flag = 1 DELETE WHERE t.val < 0
WHEN MATCHED THEN UPDATE SET val = s.val + 1000 WHERE s.flag = 2
RETURNING merge_action(), t.id, t.val;

SELECT * FROM merge_multi_when ORDER BY id;
DROP TABLE merge_multi_when;

--
-- Test WHEN NOT MATCHED BY SOURCE THEN UPDATE ... DELETE WHERE preserves
-- matchKind and does not hijack a preceding WHEN MATCHED THEN UPDATE.
--
CREATE TABLE merge_nmbs (id int PRIMARY KEY, val int);
INSERT INTO merge_nmbs VALUES (1, -20), (2, -5), (3, 50);

MERGE INTO merge_nmbs t
USING (VALUES (1, -30)) AS s(id, val)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET val = s.val
WHEN NOT MATCHED BY SOURCE THEN UPDATE SET val = t.val - 10 DELETE WHERE t.val < 0
RETURNING merge_action(), t.id, t.val;

SELECT * FROM merge_nmbs ORDER BY id;
DROP TABLE merge_nmbs;

--
-- Test BEFORE DELETE trigger returning NULL aborts DELETE WHERE while keeping
-- the UPDATE and reporting UPDATE in RETURNING merge_action().
--
CREATE TABLE merge_bd_skip (id int PRIMARY KEY, val int);
INSERT INTO merge_bd_skip VALUES (1, 10), (2, 20);

CREATE OR REPLACE FUNCTION merge_bd_skip_fn() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.id = 1 THEN
        RETURN NULL;
    END IF;
    RETURN OLD;
END;
$$;
/

CREATE TRIGGER merge_bd_skip_trg
    BEFORE DELETE ON merge_bd_skip
    FOR EACH ROW EXECUTE FUNCTION merge_bd_skip_fn();

MERGE INTO merge_bd_skip t
USING (VALUES (1, -5), (2, -6)) AS s(id, val)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET val = s.val DELETE WHERE t.val < 0
RETURNING merge_action(), t.id, t.val;

SELECT * FROM merge_bd_skip ORDER BY id;
DROP TABLE merge_bd_skip;
DROP FUNCTION merge_bd_skip_fn();

--
-- Test unreachable WHEN clause check is preserved after UPDATE ... DELETE WHERE
--
CREATE TABLE merge_unreach_t (id int, val int);
MERGE INTO merge_unreach_t t
USING (SELECT 1 AS id, 2 AS val) s
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET val = s.val DELETE WHERE t.val < 0
WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.val)
WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.val + 1);
DROP TABLE merge_unreach_t;

--
-- Test cross-partition UPDATE ... DELETE WHERE when destination partition
-- BEFORE INSERT trigger returns NULL (skips insert): must not crash on
-- uninitialized inserted_tuple pointer.
--
CREATE TABLE merge_part_skip (id int, part int, val int) PARTITION BY LIST (part);
CREATE TABLE merge_part_skip_1 PARTITION OF merge_part_skip FOR VALUES IN (1);
CREATE TABLE merge_part_skip_2 PARTITION OF merge_part_skip FOR VALUES IN (2);

CREATE OR REPLACE FUNCTION merge_part_skip_bi_fn() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.id = 1 THEN
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$$;
/

CREATE TRIGGER merge_part_skip_bi_trg
    BEFORE INSERT ON merge_part_skip_2
    FOR EACH ROW EXECUTE FUNCTION merge_part_skip_bi_fn();

INSERT INTO merge_part_skip VALUES (1, 1, 10), (2, 1, 20);

MERGE INTO merge_part_skip t
USING (VALUES (1, 2, -5), (2, 2, -6)) AS s(id, part, val)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET part = s.part, val = s.val DELETE WHERE t.val < 0;

SELECT tableoid::regclass AS part_rel, id, part, val FROM merge_part_skip ORDER BY id;
DROP TABLE merge_part_skip;
DROP FUNCTION merge_part_skip_bi_fn();

--
-- Test RLS DELETE policy enforcement on Oracle MERGE UPDATE ... DELETE WHERE
-- (both regular table and cross-partition update).
--
CREATE ROLE merge_rls_user;
CREATE TABLE merge_rls_t (id int PRIMARY KEY, val int, can_del boolean);
INSERT INTO merge_rls_t VALUES (1, 10, false), (2, 20, true);
ALTER TABLE merge_rls_t ENABLE ROW LEVEL SECURITY;
CREATE POLICY merge_rls_sel ON merge_rls_t FOR SELECT TO merge_rls_user USING (true);
CREATE POLICY merge_rls_upd ON merge_rls_t FOR UPDATE TO merge_rls_user USING (true) WITH CHECK (true);
CREATE POLICY merge_rls_del ON merge_rls_t FOR DELETE TO merge_rls_user USING (can_del);
GRANT SELECT, UPDATE, DELETE ON merge_rls_t TO merge_rls_user;

CREATE TABLE merge_rls_part (id int, part int, val int, can_del boolean) PARTITION BY LIST (part);
CREATE TABLE merge_rls_part_1 PARTITION OF merge_rls_part FOR VALUES IN (1);
CREATE TABLE merge_rls_part_2 PARTITION OF merge_rls_part FOR VALUES IN (2);
INSERT INTO merge_rls_part VALUES (1, 1, 10, false), (2, 1, 20, true);
ALTER TABLE merge_rls_part ENABLE ROW LEVEL SECURITY;
CREATE POLICY merge_rls_part_sel ON merge_rls_part FOR SELECT TO merge_rls_user USING (true);
CREATE POLICY merge_rls_part_ins ON merge_rls_part FOR INSERT TO merge_rls_user WITH CHECK (true);
CREATE POLICY merge_rls_part_upd ON merge_rls_part FOR UPDATE TO merge_rls_user USING (true) WITH CHECK (true);
CREATE POLICY merge_rls_part_del ON merge_rls_part FOR DELETE TO merge_rls_user USING (can_del);
GRANT SELECT, INSERT, UPDATE, DELETE ON merge_rls_part TO merge_rls_user;

SET ROLE merge_rls_user;

-- Regular table: DELETE WHERE matches row 1 (can_del = false) -> must fail RLS!
MERGE INTO merge_rls_t t
USING (VALUES (1, -5)) AS s(id, val)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET val = s.val DELETE WHERE t.val < 0;

-- Regular table: DELETE WHERE matches row 2 (can_del = true) -> allowed!
MERGE INTO merge_rls_t t
USING (VALUES (2, -5)) AS s(id, val)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET val = s.val DELETE WHERE t.val < 0;

-- Cross-partition: row 1 (can_del = false) -> fails DELETE RLS on partition move/delete!
MERGE INTO merge_rls_part t
USING (VALUES (1, 2, -5)) AS s(id, part, val)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET part = s.part, val = s.val DELETE WHERE t.val < 0;

-- Cross-partition: row 2 (can_del = true) -> succeeds and deletes row 2!
MERGE INTO merge_rls_part t
USING (VALUES (2, 2, -5)) AS s(id, part, val)
ON (t.id = s.id)
WHEN MATCHED THEN UPDATE SET part = s.part, val = s.val DELETE WHERE t.val < 0;

RESET ROLE;

SELECT * FROM merge_rls_t ORDER BY id;
SELECT * FROM merge_rls_part ORDER BY id;
DROP TABLE merge_rls_t;
DROP TABLE merge_rls_part;
DROP ROLE merge_rls_user;
