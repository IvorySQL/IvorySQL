-- COPY ON CONFLICT (AnalyticDB-compatible DO ON CONFLICT DO NOTHING)
DROP TABLE IF EXISTS copy_on_conflict_t1, copy_on_conflict_t2, copy_on_conflict_t3,
	copy_on_conflict_tp, copy_on_conflict_tp_lo, copy_on_conflict_tp_hi,
	copy_on_conflict_t4 CASCADE;
CREATE TABLE copy_on_conflict_t1 (id int PRIMARY KEY, name text);
INSERT INTO copy_on_conflict_t1 VALUES (1, 'old-1'), (2, 'old-2');

-- 1. DO NOTHING skips conflicting rows, inserts the rest
COPY copy_on_conflict_t1 FROM STDIN DO ON CONFLICT DO NOTHING;
1	new-1
2	new-2
3	new-3
\.
SELECT * FROM copy_on_conflict_t1 ORDER BY id;

-- 2. no-conflict data behaves like plain COPY
COPY copy_on_conflict_t1 FROM STDIN DO ON CONFLICT DO NOTHING;
4	four
\.
SELECT count(*) FROM copy_on_conflict_t1;

-- 3. table without unique constraint is rejected at startup
CREATE TABLE copy_on_conflict_t2 (a int, b text);
COPY copy_on_conflict_t2 FROM '/dev/null' DO ON CONFLICT DO NOTHING;

-- 4. COPY TO does not accept ON CONFLICT
COPY copy_on_conflict_t1 TO STDOUT DO ON CONFLICT DO NOTHING;

-- 5. DO UPDATE with empty input: no conflicts, no-op (see section below for behavior)
COPY copy_on_conflict_t1 FROM '/dev/null' DO ON CONFLICT DO UPDATE;

-- 6. multi-column unique index
CREATE TABLE copy_on_conflict_t3 (a int, b int, c text, UNIQUE (a, b));
INSERT INTO copy_on_conflict_t3 VALUES (1, 1, 'keep');
COPY copy_on_conflict_t3 FROM STDIN DO ON CONFLICT DO NOTHING;
1	1	dup
1	2	ok
\.
SELECT * FROM copy_on_conflict_t3 ORDER BY a, b;

-- 7. partitioned table: uniqueness enforced per leaf partition
CREATE TABLE copy_on_conflict_tp (id int PRIMARY KEY, v text) PARTITION BY RANGE (id);
CREATE TABLE copy_on_conflict_tp_lo PARTITION OF copy_on_conflict_tp FOR VALUES FROM (0) TO (10);
CREATE TABLE copy_on_conflict_tp_hi PARTITION OF copy_on_conflict_tp FOR VALUES FROM (10) TO (20);
INSERT INTO copy_on_conflict_tp VALUES (1, 'p-old'), (11, 'h-old');
COPY copy_on_conflict_tp FROM STDIN DO ON CONFLICT DO NOTHING;
1	p-dup
5	p-new
11	h-dup
15	h-new
\.
SELECT * FROM copy_on_conflict_tp ORDER BY id;

-- 8. combined with ON_ERROR ignore: type errors and conflicts handled independently
CREATE TABLE copy_on_conflict_t4 (id int PRIMARY KEY, v int);
INSERT INTO copy_on_conflict_t4 VALUES (1, 100);
COPY copy_on_conflict_t4 FROM STDIN WITH (ON_ERROR ignore) DO ON CONFLICT DO NOTHING;
1	bad-dup
2	notanumber
2	200
\.
SELECT * FROM copy_on_conflict_t4 ORDER BY id;

-- 9. parenthesized option syntax also accepts on_conflict
COPY copy_on_conflict_t1 FROM STDIN WITH (on_conflict 'nothing');
5	five
\.
SELECT * FROM copy_on_conflict_t1 WHERE id = 5;

-- 10. unknown on_conflict value is rejected
COPY copy_on_conflict_t1 FROM '/dev/null' WITH (on_conflict 'bogus');

-- ===== DO ON CONFLICT DO UPDATE =====
-- 11. DO UPDATE overwrites conflicting rows (full-row overwrite)
DROP TABLE IF EXISTS copy_on_conflict_u1 CASCADE;
CREATE TABLE copy_on_conflict_u1 (id int PRIMARY KEY, name text);
INSERT INTO copy_on_conflict_u1 VALUES (1, 'old-1'), (2, 'old-2');
COPY copy_on_conflict_u1 FROM STDIN DO ON CONFLICT DO UPDATE;
1	new-1
2	new-2
3	new-3
\.
SELECT * FROM copy_on_conflict_u1 ORDER BY id;

-- 12. DO UPDATE without conflicts behaves like plain COPY
COPY copy_on_conflict_u1 FROM STDIN DO ON CONFLICT DO UPDATE;
4	four
\.
SELECT count(*) FROM copy_on_conflict_u1;

-- 13. multi-column unique index with DO UPDATE
DROP TABLE IF EXISTS copy_on_conflict_u3 CASCADE;
CREATE TABLE copy_on_conflict_u3 (a int, b int, c text, UNIQUE (a, b));
INSERT INTO copy_on_conflict_u3 VALUES (1, 1, 'keep');
COPY copy_on_conflict_u3 FROM STDIN DO ON CONFLICT DO UPDATE;
1	1	changed
1	2	ok
\.
SELECT * FROM copy_on_conflict_u3 ORDER BY a, b;

-- 14. partitioned table: in-partition DO UPDATE
DROP TABLE IF EXISTS copy_on_conflict_up CASCADE;
CREATE TABLE copy_on_conflict_up (id int PRIMARY KEY, v text) PARTITION BY RANGE (id);
CREATE TABLE copy_on_conflict_up_lo PARTITION OF copy_on_conflict_up FOR VALUES FROM (0) TO (10);
CREATE TABLE copy_on_conflict_up_hi PARTITION OF copy_on_conflict_up FOR VALUES FROM (10) TO (20);
INSERT INTO copy_on_conflict_up VALUES (1, 'p-old'), (11, 'h-old');
COPY copy_on_conflict_up FROM STDIN DO ON CONFLICT DO UPDATE;
1	p-new
5	ins
11	h-new
\.
SELECT * FROM copy_on_conflict_up ORDER BY id;

-- 15. stored generated columns are recomputed on DO UPDATE
DROP TABLE IF EXISTS copy_on_conflict_u6 CASCADE;
CREATE TABLE copy_on_conflict_u6 (id int PRIMARY KEY, a int,
	b int GENERATED ALWAYS AS (a * 2) STORED);
INSERT INTO copy_on_conflict_u6 VALUES (1, 5, DEFAULT);
COPY copy_on_conflict_u6 (id, a) FROM STDIN DO ON CONFLICT DO UPDATE;
1	10
\.
SELECT * FROM copy_on_conflict_u6;

-- 16. AFTER ROW UPDATE triggers fire on DO UPDATE
DROP TABLE IF EXISTS copy_on_conflict_u7, copy_on_conflict_u7_log CASCADE;
CREATE TABLE copy_on_conflict_u7 (id int PRIMARY KEY, v text);
CREATE TABLE copy_on_conflict_u7_log (id int, old_v text, new_v text);
CREATE FUNCTION copy_on_conflict_u7_trg() RETURNS trigger AS $$
BEGIN
  INSERT INTO copy_on_conflict_u7_log VALUES (OLD.id, OLD.v, NEW.v);
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER copy_on_conflict_u7_trg AFTER UPDATE ON copy_on_conflict_u7
	FOR EACH ROW EXECUTE FUNCTION copy_on_conflict_u7_trg();
INSERT INTO copy_on_conflict_u7 VALUES (1, 'old');
COPY copy_on_conflict_u7 FROM STDIN DO ON CONFLICT DO UPDATE;
1	new
\.
SELECT * FROM copy_on_conflict_u7;
SELECT * FROM copy_on_conflict_u7_log;

-- 17. partitioned table unique constraints must include partition columns
-- (PG rule: cross-partition updates are therefore unreachable for ON CONFLICT)
DROP TABLE IF EXISTS copy_on_conflict_u5 CASCADE;
CREATE TABLE copy_on_conflict_u5 (id int, uid int UNIQUE, v text) PARTITION BY RANGE (id);

-- 18. duplicate constrained values within one COPY with DO UPDATE raises
-- the standard INSERT ON CONFLICT error ('cannot affect row a second time')
DROP TABLE IF EXISTS copy_on_conflict_u8 CASCADE;
CREATE TABLE copy_on_conflict_u8 (id int PRIMARY KEY, v text);
INSERT INTO copy_on_conflict_u8 VALUES (1, 'existing');
COPY copy_on_conflict_u8 FROM STDIN DO ON CONFLICT DO UPDATE;
1	first
1	second
\.
SELECT * FROM copy_on_conflict_u8;

-- 19. same for DO NOTHING: the second duplicate is also skipped, no error
DROP TABLE IF EXISTS copy_on_conflict_u9 CASCADE;
CREATE TABLE copy_on_conflict_u9 (id int PRIMARY KEY, v text);
INSERT INTO copy_on_conflict_u9 VALUES (1, 'existing');
COPY copy_on_conflict_u9 FROM STDIN DO ON CONFLICT DO NOTHING;
1	first
1	second
2	ok
\.
SELECT * FROM copy_on_conflict_u9 ORDER BY id;

-- cleanup
DROP TABLE copy_on_conflict_t1, copy_on_conflict_t2, copy_on_conflict_t3,
	copy_on_conflict_tp, copy_on_conflict_tp_lo, copy_on_conflict_tp_hi,
	copy_on_conflict_t4, copy_on_conflict_u1, copy_on_conflict_u3,
	copy_on_conflict_up, copy_on_conflict_up_lo, copy_on_conflict_up_hi,
	copy_on_conflict_u6, copy_on_conflict_u7, copy_on_conflict_u7_log CASCADE;
