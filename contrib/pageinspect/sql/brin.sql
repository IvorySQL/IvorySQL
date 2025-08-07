CREATE TABLE test1 (a int, b text);
INSERT INTO test1 VALUES (1, 'one');
CREATE INDEX test1_a_idx ON test1 USING brin (a);

SELECT brin_page_type(get_raw_page('test1_a_idx', 0));
SELECT brin_page_type(get_raw_page('test1_a_idx', 1));
SELECT brin_page_type(get_raw_page('test1_a_idx', 2));

SELECT * FROM brin_metapage_info(get_raw_page('test1_a_idx', 0));
SELECT * FROM brin_metapage_info(get_raw_page('test1_a_idx', 1));

SELECT * FROM brin_revmap_data(get_raw_page('test1_a_idx', 0)) LIMIT 5;
SELECT * FROM brin_revmap_data(get_raw_page('test1_a_idx', 1)) LIMIT 5;

SELECT * FROM brin_page_items(get_raw_page('test1_a_idx', 2), 'test1_a_idx')
    ORDER BY blknum, attnum LIMIT 5;

-- Mask DETAIL messages as these are not portable across architectures.
\set VERBOSITY terse

-- Failures for non-BRIN index.
CREATE INDEX test1_a_btree ON test1 (a);
SELECT brin_page_items(get_raw_page('test1_a_btree', 0), 'test1_a_btree');
SELECT brin_page_items(get_raw_page('test1_a_btree', 0), 'test1_a_idx');

-- Invalid special area size
SELECT brin_page_type(get_raw_page('test1', 0));
SELECT * FROM brin_metapage_info(get_raw_page('test1', 0));
SELECT * FROM brin_revmap_data(get_raw_page('test1', 0));
\set VERBOSITY default

-- Tests with all-zero pages.
SHOW block_size \gset
SELECT brin_page_type(decode(repeat('00', :block_size), 'hex'));
SELECT brin_page_items(decode(repeat('00', :block_size), 'hex'), 'test1_a_idx');
SELECT brin_metapage_info(decode(repeat('00', :block_size), 'hex'));
SELECT brin_revmap_data(decode(repeat('00', :block_size), 'hex'));

-- Test that partial indexes have all pages, including empty ones.
CREATE TABLE test2 (a int);
INSERT INTO test2 SELECT i FROM generate_series(1,1000) s(i);

-- No rows match the index predicate, make sure the index has the right number
-- of ranges (same as number of page ranges).
CREATE INDEX ON test2 USING brin (a) WITH (pages_per_range=1) WHERE (a IS NULL);

ANALYZE test2;

-- Does the index have one summary of the relation?
SELECT (COUNT(*) = (SELECT relpages FROM pg_class WHERE relname = 'test2')) AS ranges_do_match
 FROM generate_series((SELECT (lastrevmappage + 1) FROM brin_metapage_info(get_raw_page('test2_a_idx', 0))),
                      (SELECT (relpages - 1) FROM pg_class WHERE relname = 'test2_a_idx')) AS pages(p),
      LATERAL brin_page_items(get_raw_page('test2_a_idx', p), 'test2_a_idx') AS items;

DROP TABLE test1;
DROP TABLE test2;

-- Test that parallel index build produces the same BRIN index as serial build.
CREATE TABLE brin_parallel_test (a int, b text, c bigint) WITH (fillfactor=40);

-- Generate a table with a mix of NULLs and non-NULL values (and data suitable
-- for the different opclasses we build later).
INSERT INTO brin_parallel_test
SELECT (CASE WHEN (mod(i,231) = 0) OR (i BETWEEN 3500 AND 4000) THEN NULL ELSE i END),
       (CASE WHEN (mod(i,233) = 0) OR (i BETWEEN 3750 AND 4250) THEN NULL ELSE encode(sha256(i::text::bytea), 'hex') END),
       (CASE WHEN (mod(i,233) = 0) OR (i BETWEEN 3850 AND 4500) THEN NULL ELSE (i/100) + mod(i,8) END)
  FROM generate_series(1,5000) S(i);

-- Build an index with different opclasses - minmax, bloom and minmax-multi.
--
-- For minmax and opclass this is simple, but for minmax-multi we need to be
-- careful, because the result depends on the order in which values are added
-- to the summary, which in turn affects how are values merged etc. The order
-- of merging results from workers has similar effect. All those summaries
-- should produce correct query results, but it means we can't compare them
-- using equality (which is what EXCEPT does). To work around this issue, we
-- generated the data to only have very small number of distinct values per
-- range, so that no merging is needed. This makes the results deterministic.

-- build index without parallelism
SET max_parallel_maintenance_workers = 0;
CREATE INDEX brin_test_serial_idx ON brin_parallel_test
 USING brin (a int4_minmax_ops, a int4_bloom_ops, b, c int8_minmax_multi_ops)
  WITH (pages_per_range=7)
 WHERE NOT (a BETWEEN 1000 and 1500);

-- build index using parallelism
--
-- Set a couple parameters to force parallel build for small table. There's a
-- requirement for table size, so disable that. Also, plan_create_index_workers
-- assumes each worker will use work_mem=32MB for sorting (which works for btree,
-- but not really for BRIN), so we set maintenance_work_mem for 4 workers.
SET min_parallel_table_scan_size = 0;
SET max_parallel_maintenance_workers = 4;
SET maintenance_work_mem = '128MB';
CREATE INDEX brin_test_parallel_idx ON brin_parallel_test
 USING brin (a int4_minmax_ops, a int4_bloom_ops, b, c int8_minmax_multi_ops)
  WITH (pages_per_range=7)
 WHERE NOT (a BETWEEN 1000 and 1500);

SELECT relname, relpages
  FROM pg_class
 WHERE relname IN ('brin_test_serial_idx', 'brin_test_parallel_idx')
 ORDER BY relname;

-- Check that (A except B) and (B except A) is empty, which means the indexes
-- are the same.

SELECT * FROM brin_page_items(get_raw_page('brin_test_parallel_idx', 2), 'brin_test_parallel_idx')
EXCEPT
SELECT * FROM brin_page_items(get_raw_page('brin_test_serial_idx', 2), 'brin_test_serial_idx');

SELECT * FROM brin_page_items(get_raw_page('brin_test_serial_idx', 2), 'brin_test_serial_idx')
EXCEPT
SELECT * FROM brin_page_items(get_raw_page('brin_test_parallel_idx', 2), 'brin_test_parallel_idx');

DROP INDEX brin_test_parallel_idx;

-- force parallel build, but don't allow starting parallel workers to force
-- fallback to serial build, and repeat the checks

SET max_parallel_workers = 0;
CREATE INDEX brin_test_parallel_idx ON brin_parallel_test
 USING brin (a int4_minmax_ops, a int4_bloom_ops, b, c int8_minmax_multi_ops)
  WITH (pages_per_range=7)
 WHERE NOT (a BETWEEN 1000 and 1500);

SELECT relname, relpages
  FROM pg_class
 WHERE relname IN ('brin_test_serial_idx', 'brin_test_parallel_idx')
 ORDER BY relname;

SELECT * FROM brin_page_items(get_raw_page('brin_test_parallel_idx', 2), 'brin_test_parallel_idx')
EXCEPT
SELECT * FROM brin_page_items(get_raw_page('brin_test_serial_idx', 2), 'brin_test_serial_idx');

SELECT * FROM brin_page_items(get_raw_page('brin_test_serial_idx', 2), 'brin_test_serial_idx')
EXCEPT
SELECT * FROM brin_page_items(get_raw_page('brin_test_parallel_idx', 2), 'brin_test_parallel_idx');

DROP TABLE brin_parallel_test;
RESET min_parallel_table_scan_size;
RESET max_parallel_maintenance_workers;
RESET maintenance_work_mem;
