--
-- ALTER_INDEX
-- Test Oracle-compatible ALTER INDEX ... REBUILD / UNUSABLE syntax
-- Covers: REBUILD, REBUILD ONLINE, REBUILD TABLESPACE, REBUILD PARTITION,
--         UNUSABLE
--

-- Clean up in case a prior regression run failed
SET client_min_messages TO 'warning';
DROP TABLE IF EXISTS employees    CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS sales      CASCADE;
RESET client_min_messages;

-- ============================================================
-- Setup
-- ============================================================

CREATE TABLE employees (id int PRIMARY KEY, val text);
INSERT INTO employees SELECT g, 'val'||g FROM generate_series(1,500) g;
CREATE INDEX idx_employees_val ON employees(val);

CREATE TABLE products (a int, b text, c numeric);
INSERT INTO products SELECT g, 'b'||g, g*1.1 FROM generate_series(1,200) g;
CREATE INDEX idx_products_a  ON products(a);
CREATE INDEX idx_products_b  ON products(b);
CREATE UNIQUE INDEX idx_products_ab ON products(a, b);

CREATE TABLE sales (id int, region text) PARTITION BY RANGE (id);
CREATE TABLE sales_p1 PARTITION OF sales FOR VALUES FROM (1)    TO (1001);
CREATE TABLE sales_p2 PARTITION OF sales FOR VALUES FROM (1001) TO (2001);
INSERT INTO sales SELECT g, CASE WHEN g<=1000 THEN 'east' ELSE 'west' END
  FROM generate_series(1,2000) g;
CREATE INDEX idx_sales_id   ON sales(id);
CREATE UNIQUE INDEX idx_sales_uniq ON sales(id, region);

-- ============================================================
-- GROUP 1: Basic REBUILD (no options)
-- ============================================================

-- T01: plain index
ALTER INDEX idx_employees_val REBUILD;

-- T02: primary key index
ALTER INDEX employees_pkey REBUILD;

-- T03: unique index
ALTER INDEX idx_products_ab REBUILD;

-- T04: partitioned parent index (rebuilds all leaf partitions)
ALTER INDEX idx_sales_id REBUILD;

-- ============================================================
-- GROUP 2: REBUILD ONLINE
-- ============================================================

-- T05: plain index ONLINE (equivalent to REINDEX CONCURRENTLY)
ALTER INDEX idx_employees_val REBUILD ONLINE;

-- T06: partitioned parent index ONLINE
ALTER INDEX idx_sales_id REBUILD ONLINE;

-- T07: ONLINE inside an explicit transaction block (must error)
BEGIN;
ALTER INDEX idx_employees_val REBUILD ONLINE;
ROLLBACK;

-- T08: temp-table index ONLINE (auto-degrades to non-concurrent, no error)
CREATE TEMP TABLE temp_items (x int);
CREATE INDEX idx_temp_items_x ON temp_items(x);
INSERT INTO temp_items VALUES (1),(2),(3);
ALTER INDEX idx_temp_items_x REBUILD ONLINE;
DROP TABLE temp_items;

-- ============================================================
-- GROUP 3: REBUILD TABLESPACE
-- ============================================================

-- T09: move to default tablespace
ALTER INDEX idx_employees_val REBUILD TABLESPACE pg_default;
-- verify the index actually landed in pg_default (reltablespace = 0)
SELECT reltablespace = 0 AS in_default_tablespace
  FROM pg_class WHERE relname = 'idx_employees_val';

-- T10: index is still usable after REBUILD TABLESPACE
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT val FROM employees WHERE val = 'val100';
RESET enable_seqscan;

-- T11: non-existent tablespace (must error)
ALTER INDEX idx_employees_val REBUILD TABLESPACE no_such_tablespace;

-- T12: partitioned parent index TABLESPACE
ALTER INDEX idx_sales_uniq REBUILD TABLESPACE pg_default;
-- verify the partitioned index landed in pg_default (reltablespace = 0)
SELECT reltablespace = 0 AS in_default_tablespace
  FROM pg_class WHERE relname = 'idx_sales_uniq';

-- ============================================================
-- GROUP 4: REBUILD PARTITION
-- ============================================================

-- T13: rebuild first leaf partition
ALTER INDEX idx_sales_id REBUILD PARTITION sales_p1;

-- T14: rebuild second leaf partition
ALTER INDEX idx_sales_id REBUILD PARTITION sales_p2;

-- T15: unique partitioned index, one partition
ALTER INDEX idx_sales_uniq REBUILD PARTITION sales_p1;

-- T16: non-existent partition name (must error)
ALTER INDEX idx_sales_id REBUILD PARTITION no_such_partition;

-- T17: PARTITION on a non-partitioned index (must error)
ALTER INDEX idx_employees_val REBUILD PARTITION sales_p1;

-- T17b: PARTITION on a child (leaf) partition index must error
-- Leaf partition indexes are plain (non-partitioned) indexes; only the root
-- partitioned index supports the PARTITION option.
CREATE INDEX idx_sales_p1_leaf ON sales_p1(id);
ALTER INDEX idx_sales_p1_leaf REBUILD PARTITION sales_p1;
DROP INDEX idx_sales_p1_leaf;

-- T18: partition query still uses correct index after REBUILD PARTITION
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT id FROM sales WHERE id = 500;
RESET enable_seqscan;

-- ============================================================
-- GROUP 5: Option combinations (any order)
-- ============================================================

-- T19: ONLINE TABLESPACE
ALTER INDEX idx_products_a REBUILD ONLINE TABLESPACE pg_default;

-- T20: TABLESPACE ONLINE (reversed order, same effect)
ALTER INDEX idx_products_a REBUILD TABLESPACE pg_default ONLINE;

-- T21: PARTITION TABLESPACE
ALTER INDEX idx_sales_id REBUILD PARTITION sales_p1 TABLESPACE pg_default;

-- T22: PARTITION ONLINE
ALTER INDEX idx_sales_id REBUILD PARTITION sales_p2 ONLINE;

-- T23: all three options (ONLINE + TABLESPACE + PARTITION)
ALTER INDEX idx_sales_id
  REBUILD ONLINE TABLESPACE pg_default PARTITION sales_p1;

-- T24: all three options, different order (PARTITION + TABLESPACE + ONLINE)
ALTER INDEX idx_sales_id
  REBUILD PARTITION sales_p2 TABLESPACE pg_default ONLINE;

-- ============================================================
-- GROUP 6: Boundary and error cases
-- ============================================================

-- T25: non-existent index (must error)
ALTER INDEX no_such_index REBUILD;

-- T26: not an index (table name given) (must error)
ALTER INDEX employees REBUILD;

-- T27: REBUILD inside a read-only transaction (allowed, same as REINDEX)
BEGIN TRANSACTION READ ONLY;
ALTER INDEX idx_employees_val REBUILD;
COMMIT;

-- T28: primary key index still uses Index Only Scan after REBUILD
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT id FROM employees WHERE id = 42;
RESET enable_seqscan;

-- T29: unique constraint still enforced after REBUILD
INSERT INTO employees VALUES (1, 'duplicate_check');

-- T30: multiple consecutive REBUILDs (maintenance window scenario)
ALTER INDEX idx_products_a  REBUILD;
ALTER INDEX idx_products_b  REBUILD;
ALTER INDEX idx_products_ab REBUILD;

-- ============================================================
-- GROUP 7: Syntax compatibility (no interference with other ALTER INDEX)
-- ============================================================

-- T31: REBUILD does not affect RENAME
ALTER INDEX idx_products_a RENAME TO idx_products_a_renamed;
ALTER INDEX idx_products_a_renamed RENAME TO idx_products_a;

-- T32: REBUILD does not affect SET TABLESPACE
ALTER INDEX idx_products_b SET TABLESPACE pg_default;

-- T33: data integrity preserved across REBUILD (count must match)
SELECT count(*) FROM employees WHERE id BETWEEN 1 AND 100;
ALTER INDEX employees_pkey REBUILD;
SELECT count(*) FROM employees WHERE id BETWEEN 1 AND 100;

-- T34: PARALLEL + PARTITION
ALTER INDEX idx_sales_id REBUILD PARALLEL 2 PARTITION sales_p1;

-- T35: NOPARALLEL + PARTITION
ALTER INDEX idx_sales_id REBUILD NOPARALLEL PARTITION sales_p1;

-- ============================================================
-- Cleanup
-- ============================================================
DROP TABLE employees    CASCADE;
DROP TABLE products CASCADE;
DROP TABLE sales      CASCADE;

-- ============================================================
-- GROUP 8: REBUILD PARALLEL / NOPARALLEL
--
-- Tests are split into two categories:
--   A. Non-concurrent (no ONLINE): nworkers flows through reindex_index()
--      → index_build().  DEBUG1 output is deterministic and captured.
--   B. Combined with ONLINE: concurrent rebuild path does not consult
--      nworkers; a WARNING is issued instead.
-- ============================================================

SET client_min_messages TO 'warning';
DROP TABLE IF EXISTS rp_t CASCADE;
RESET client_min_messages;

CREATE TABLE rp_t (id int, val text);
INSERT INTO rp_t SELECT i, repeat('x', 100) FROM generate_series(1, 10000) i;
CREATE INDEX rp_idx ON rp_t(id);

-- ----------------------------------------------------------------
-- A. Non-concurrent path: verify nworkers routing in reindex_index()
-- ----------------------------------------------------------------

-- TP01: NOPARALLEL => nworkers=-1 => use_parallel=false => serial
-- index_build() is called with parallel=false and never consults the planner.
-- DEBUG1 must show "serially".
SET client_min_messages = DEBUG1;
SET max_parallel_maintenance_workers = 4;
ALTER INDEX rp_idx REBUILD NOPARALLEL;
RESET client_min_messages;
RESET max_parallel_maintenance_workers;

-- TP02: PARALLEL 1 => nworkers=-1 (same as NOPARALLEL) => serial
-- Oracle PARALLEL 1 = 1 PX Server, coordinator idle = 1 data-working process.
-- PG serial = leader only = 1 data-working process.  Must be truly serial,
-- not auto (nworkers=0 would let index_build() re-estimate and could launch
-- workers on a large table).
-- DEBUG1 must show "serially".
SET client_min_messages = DEBUG1;
ALTER INDEX rp_idx REBUILD PARALLEL 1;
RESET client_min_messages;

-- TP03: PARALLEL 4 => nworkers=3 => plan_create_index_workers(override=3)
-- Gate 4 (32 MB cap) is bypassed for an explicit override; result is
-- Min(override, max_parallel_maintenance_workers) = Min(3, 4) = 3.
-- DEBUG1 must show "with request for 3 parallel workers".
SET client_min_messages = DEBUG1;
SET max_parallel_maintenance_workers = 4;
SET log_temp_files = -1;
ALTER INDEX rp_idx REBUILD PARALLEL 4;
RESET log_temp_files;
RESET client_min_messages;
RESET max_parallel_maintenance_workers;

-- TP04: PARALLEL (no degree) => nworkers=0 => auto path
-- Worker count is planner-determined (table size, GUC, memory cap).
-- Exact count varies; we just verify no error occurs.
SET max_parallel_maintenance_workers = 4;
SET min_parallel_table_scan_size = 0;
ALTER INDEX rp_idx REBUILD PARALLEL;
RESET max_parallel_maintenance_workers;
RESET min_parallel_table_scan_size;

-- TP05: max_parallel_maintenance_workers=0 blocks even an explicit override
-- plan_create_index_workers() checks the GUC first and returns 0 immediately.
-- DEBUG1 must show "serially".
SET client_min_messages = DEBUG1;
SET max_parallel_maintenance_workers = 0;
ALTER INDEX rp_idx REBUILD PARALLEL 4;
RESET client_min_messages;
RESET max_parallel_maintenance_workers;

-- TP06: PARALLEL and NOPARALLEL together -- must error (mutually exclusive)
ALTER INDEX rp_idx REBUILD PARALLEL 2 NOPARALLEL;

-- TP07: PARALLEL 0 -- must error (degree must be >= 1, enforced in grammar)
ALTER INDEX rp_idx REBUILD PARALLEL 0;

-- ----------------------------------------------------------------
-- B. Combined with ONLINE: parallel hint is ignored; WARNING issued
-- ----------------------------------------------------------------

-- TP08: PARALLEL N + ONLINE -- WARNING: hint ignored; a non-blocking rebuild
-- is performed instead. ONLINE triggers REINDEX CONCURRENTLY path (index_concurrently_build()),
-- which does not consult params->nworkers.  A WARNING is always issued when
-- PARALLEL/NOPARALLEL is combined with ONLINE so the user is not misled.
ALTER INDEX rp_idx REBUILD PARALLEL 4 ONLINE;

-- TP09: NOPARALLEL + ONLINE -- WARNING: hint ignored; concurrent rebuild runs
ALTER INDEX rp_idx REBUILD NOPARALLEL ONLINE;

-- ----------------------------------------------------------------
-- C. Data integrity
-- ----------------------------------------------------------------

-- TP10: row count must be unchanged before and after PARALLEL REBUILD
SELECT count(*) FROM rp_t WHERE id BETWEEN 1 AND 5000;
ALTER INDEX rp_idx REBUILD PARALLEL 4;
SELECT count(*) FROM rp_t WHERE id BETWEEN 1 AND 5000;

-- TP11: PARALLEL + TABLESPACE
ALTER INDEX rp_idx REBUILD PARALLEL 2 TABLESPACE pg_default;

-- TP12: NOPARALLEL + TABLESPACE
ALTER INDEX rp_idx REBUILD NOPARALLEL TABLESPACE pg_default;

-- Cleanup GROUP 8
DROP TABLE rp_t CASCADE;

-- ============================================================
-- GROUP 9: ALTER INDEX ... UNUSABLE
--
-- Real Oracle has no USABLE clause -- REBUILD is the only documented path
-- back to a usable index, so that is the only recovery path tested here.
-- ============================================================

SET client_min_messages TO 'warning';
DROP TABLE IF EXISTS unusable_t CASCADE;
RESET client_min_messages;

CREATE TABLE unusable_t (id int PRIMARY KEY, val text);
INSERT INTO unusable_t SELECT g, 'val'||g FROM generate_series(1,200) g;
CREATE UNIQUE INDEX idx_unusable_val ON unusable_t(val);

-- U01: index is used by the planner before being marked unusable
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT val FROM unusable_t WHERE val = 'val100';
RESET enable_seqscan;

-- U02: mark it unusable
ALTER INDEX idx_unusable_val UNUSABLE;

-- U03: planner no longer chooses it, even with seqscan discouraged --
-- it falls back to the only plan left, a Seq Scan
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT val FROM unusable_t WHERE val = 'val100';
RESET enable_seqscan;

-- U04: DML no longer maintains the unusable index -- a value that would
-- violate uniqueness now succeeds silently (matches Oracle UNUSABLE semantics)
INSERT INTO unusable_t VALUES (201, 'val100');

-- U05: REBUILD fails while the table holds a value that violates uniqueness
-- (the duplicate inserted in U04) -- demonstrates that maintenance really
-- stopped while unusable, since REBUILD's physical build re-checks uniqueness
ALTER INDEX idx_unusable_val REBUILD;

-- U06: clean up the duplicate, then REBUILD succeeds
DELETE FROM unusable_t WHERE id = 201;
ALTER INDEX idx_unusable_val REBUILD;

-- U07: planner uses the index again
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT val FROM unusable_t WHERE val = 'val100';
RESET enable_seqscan;

-- U08: uniqueness is enforced again post-REBUILD
INSERT INTO unusable_t VALUES (202, 'val100');

-- U09: plain REINDEX also clears UNUSABLE (safety net beyond Oracle syntax)
ALTER INDEX idx_unusable_val UNUSABLE;
REINDEX INDEX idx_unusable_val;
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT val FROM unusable_t WHERE val = 'val100';
RESET enable_seqscan;

-- U10: UNUSABLE on a partitioned (parent) index -- must error (v1 only
-- supports plain/leaf indexes; PARTITION-level granularity is future work)
CREATE TABLE unusable_part (id int, region text) PARTITION BY RANGE (id);
CREATE TABLE unusable_part_p1 PARTITION OF unusable_part FOR VALUES FROM (1) TO (1001);
CREATE INDEX idx_unusable_part_id ON unusable_part(id);
ALTER INDEX idx_unusable_part_id UNUSABLE;
DROP TABLE unusable_part CASCADE;

-- U11: non-existent index (must error)
ALTER INDEX no_such_index UNUSABLE;

-- U12: not an index (table name given) (must error)
ALTER INDEX unusable_t UNUSABLE;

-- U13: data integrity preserved -- row count unaffected by UNUSABLE/REBUILD
SELECT count(*) FROM unusable_t;
ALTER INDEX idx_unusable_val UNUSABLE;
SELECT count(*) FROM unusable_t;
ALTER INDEX idx_unusable_val REBUILD;
SELECT count(*) FROM unusable_t;

-- U14: CLUSTER refuses to use an unusable index as the clustered index
-- (an unmaintained index may be missing rows changed since it was disabled;
-- clustering on it could silently drop or misorder those rows)
ALTER TABLE unusable_t CLUSTER ON idx_unusable_val;
ALTER INDEX idx_unusable_val UNUSABLE;
CLUSTER unusable_t;
ALTER INDEX idx_unusable_val REBUILD;
CLUSTER unusable_t;  -- succeeds again once rebuilt

-- U15: ON CONFLICT falls back to a clean planning-time error, not an
-- internal crash, when its only matching unique index is unusable
CREATE TABLE unusable_conflict (id int UNIQUE, val text);
INSERT INTO unusable_conflict VALUES (1, 'a');
INSERT INTO unusable_conflict VALUES (1, 'b')
  ON CONFLICT (id) DO UPDATE SET val = excluded.val;  -- baseline: works
ALTER INDEX unusable_conflict_id_key UNUSABLE;
INSERT INTO unusable_conflict VALUES (1, 'c')
  ON CONFLICT (id) DO UPDATE SET val = excluded.val;  -- must error cleanly
ALTER INDEX unusable_conflict_id_key REBUILD;
INSERT INTO unusable_conflict VALUES (1, 'd')
  ON CONFLICT (id) DO UPDATE SET val = excluded.val;  -- works again
SELECT * FROM unusable_conflict;
DROP TABLE unusable_conflict;

-- U16: UNUSABLE is rejected on a TOAST table's own index -- disabling it
-- would silently break lookups for newly-toasted values while leaving the
-- toast layer unaware anything changed
CREATE TABLE unusable_toast (id int, big text);
INSERT INTO unusable_toast VALUES (1, repeat('x', 100000));
SELECT indexrelid::regclass AS toast_index_name
  FROM pg_index
  WHERE indrelid = (SELECT reltoastrelid FROM pg_class WHERE relname = 'unusable_toast')
  \gset
ALTER INDEX :toast_index_name UNUSABLE;
DROP TABLE unusable_toast;

-- U17: an unusable leaf partition index must not let the parent partitioned
-- index be counted as fully valid (validatePartitionedIndex() must exclude
-- unusable children from its count, since the parent's indisvalid feeds
-- planner uniqueness proofs used for join removal -- see design doc 4.7/4.8)
CREATE TABLE unusable_part2 (id int, region text) PARTITION BY RANGE (id);
CREATE TABLE unusable_part2_p1 PARTITION OF unusable_part2 FOR VALUES FROM (1) TO (1001);
CREATE TABLE unusable_part2_p2 PARTITION OF unusable_part2 FOR VALUES FROM (1001) TO (2001);
CREATE INDEX idx_unusable_part2_id ON ONLY unusable_part2 (id);
SELECT indisvalid FROM pg_index WHERE indexrelid = 'idx_unusable_part2_id'::regclass;  -- f: no children attached
CREATE INDEX idx_unusable_part2_p1_id ON unusable_part2_p1 (id);
ALTER INDEX idx_unusable_part2_id ATTACH PARTITION idx_unusable_part2_p1_id;
SELECT indisvalid FROM pg_index WHERE indexrelid = 'idx_unusable_part2_id'::regclass;  -- f: 1 of 2 attached
ALTER INDEX idx_unusable_part2_p1_id UNUSABLE;
CREATE INDEX idx_unusable_part2_p2_id ON unusable_part2_p2 (id);
ALTER INDEX idx_unusable_part2_id ATTACH PARTITION idx_unusable_part2_p2_id;
-- must still be f: p1's leaf is unusable, so it must not count toward completeness
SELECT indisvalid FROM pg_index WHERE indexrelid = 'idx_unusable_part2_id'::regclass;
DROP TABLE unusable_part2;

-- U18: a new foreign key cannot be backed by an unusable primary key
-- (transformFkeyGetPrimaryKey) -- uniqueness is no longer enforced
CREATE TABLE unusable_fk_parent (id int PRIMARY KEY, val text);
ALTER INDEX unusable_fk_parent_pkey UNUSABLE;
CREATE TABLE unusable_fk_child (id int REFERENCES unusable_fk_parent);
ALTER INDEX unusable_fk_parent_pkey REBUILD;
CREATE TABLE unusable_fk_child (id int REFERENCES unusable_fk_parent);  -- works now
DROP TABLE unusable_fk_child, unusable_fk_parent;

-- U19: a new foreign key cannot be backed by a named unusable unique column
-- list (transformFkeyCheckAttrs)
CREATE TABLE unusable_fk_parent2 (id int, email text UNIQUE);
ALTER INDEX unusable_fk_parent2_email_key UNUSABLE;
CREATE TABLE unusable_fk_child2 (email text REFERENCES unusable_fk_parent2(email));
ALTER INDEX unusable_fk_parent2_email_key REBUILD;
CREATE TABLE unusable_fk_child2 (email text REFERENCES unusable_fk_parent2(email));  -- works now
DROP TABLE unusable_fk_child2, unusable_fk_parent2;

-- U20: ADD CONSTRAINT ... UNIQUE USING INDEX rejects an unusable index
CREATE TABLE unusable_using_idx (id int, val text);
CREATE UNIQUE INDEX idx_unusable_using_val ON unusable_using_idx(val);
ALTER INDEX idx_unusable_using_val UNUSABLE;
ALTER TABLE unusable_using_idx ADD CONSTRAINT uq_unusable_val UNIQUE USING INDEX idx_unusable_using_val;
ALTER INDEX idx_unusable_using_val REBUILD;
ALTER TABLE unusable_using_idx ADD CONSTRAINT uq_unusable_val UNIQUE USING INDEX idx_unusable_using_val;
DROP TABLE unusable_using_idx;

-- U21: amcheck refuses to check an unusable index -- it is expected to have
-- drifted from the heap by design, which would otherwise read as a false
-- positive corruption report
CREATE EXTENSION IF NOT EXISTS amcheck;
CREATE TABLE unusable_amcheck (id int PRIMARY KEY, val text);
INSERT INTO unusable_amcheck SELECT g, 'v'||g FROM generate_series(1,50) g;
SELECT bt_index_check('unusable_amcheck_pkey');  -- baseline: passes silently
ALTER INDEX unusable_amcheck_pkey UNUSABLE;
SELECT bt_index_check('unusable_amcheck_pkey');  -- must error, not report corruption
ALTER INDEX unusable_amcheck_pkey REBUILD;
SELECT bt_index_check('unusable_amcheck_pkey');  -- works again
DROP TABLE unusable_amcheck;

-- U22: ALTER TABLE ... ALTER COLUMN TYPE must not silently reuse an unusable
-- index's (possibly stale) physical storage -- CheckIndexCompatible() must
-- treat it as incompatible, forcing a fresh rebuild instead
CREATE TABLE unusable_altertype (id int, val int);
CREATE INDEX idx_unusable_altertype_val ON unusable_altertype(val);
SELECT indexrelid AS old_index_oid FROM pg_index
  WHERE indexrelid = 'idx_unusable_altertype_val'::regclass \gset
ALTER INDEX idx_unusable_altertype_val UNUSABLE;
ALTER TABLE unusable_altertype ALTER COLUMN val TYPE int;
-- must be a freshly built index (different OID, and not unusable)
SELECT indexrelid <> :old_index_oid AS storage_was_rebuilt, indisunusable
  FROM pg_index WHERE indrelid = 'unusable_altertype'::regclass;
DROP TABLE unusable_altertype;

-- Cleanup GROUP 9
DROP TABLE unusable_t CASCADE;
