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

-- 5. DO UPDATE is parsed but rejected (not implemented yet)
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

-- cleanup
DROP TABLE copy_on_conflict_t1, copy_on_conflict_t2, copy_on_conflict_t3,
	copy_on_conflict_tp, copy_on_conflict_t4 CASCADE;
