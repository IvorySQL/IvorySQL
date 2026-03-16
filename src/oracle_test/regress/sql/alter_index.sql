--
-- ALTER_INDEX
-- Test Oracle-compatible ALTER INDEX ... REBUILD syntax (IvorySQL feature #1064)
-- Covers: REBUILD, REBUILD ONLINE, REBUILD TABLESPACE, REBUILD PARTITION
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

-- T10: index is still usable after REBUILD TABLESPACE
EXPLAIN (COSTS OFF) SELECT val FROM employees WHERE val = 'val100';

-- T11: non-existent tablespace (must error)
ALTER INDEX idx_employees_val REBUILD TABLESPACE no_such_tablespace;

-- T12: partitioned parent index TABLESPACE
ALTER INDEX idx_sales_uniq REBUILD TABLESPACE pg_default;

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

-- T18: partition query still uses correct index after REBUILD PARTITION
EXPLAIN (COSTS OFF) SELECT id FROM sales WHERE id = 500;

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
EXPLAIN (COSTS OFF) SELECT id FROM employees WHERE id = 42;

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
ALTER INDEX rp_idx REBUILD PARALLEL 4;
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

-- Cleanup GROUP 8
DROP TABLE rp_t CASCADE;
