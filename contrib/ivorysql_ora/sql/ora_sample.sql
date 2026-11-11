--
-- SAMPLE clause
--
-- Oracle's SAMPLE clause restricts a scan to a random fraction of the
-- rows: FROM t SAMPLE (percentage) [SEED (seed)], with SAMPLE BLOCK
-- selecting whole blocks instead.  It is parsed as sugar over the
-- TABLESAMPLE machinery: the row-level default maps to the bernoulli
-- method, whose per-row selection probability matches Oracle's
-- documented SAMPLE semantics, SAMPLE BLOCK maps to the system method,
-- and SEED maps to REPEATABLE.  Only bounded assertions are made on
-- the counts of unseeded samples, because the sample itself is random.
CREATE TABLE sample_t (id int, val text);
INSERT INTO sample_t SELECT g, 'row ' || g FROM generate_series(1, 100) g;
-- the unseeded sample stays within a wide margin around its percentage
SELECT count(*) BETWEEN 1 AND 60 AS sample_bounded FROM sample_t SAMPLE(20);
-- the unsampled table keeps every row
SELECT count(*) AS no_sample FROM sample_t;
-- 0 percent samples nothing, 100 percent samples everything
SELECT count(*) AS zero_percent FROM sample_t SAMPLE(0);
SELECT count(*) AS full_percent FROM sample_t SAMPLE(100);
-- sampled rows are always a subset of the table
SELECT count(*) AS outside_rows FROM
  (SELECT id FROM sample_t SAMPLE(20) SEED(7)
   EXCEPT
   SELECT id FROM sample_t) outside;
-- the same seed reproduces the same sample
SELECT (SELECT count(*) FROM sample_t SAMPLE(20) SEED(42))
     = (SELECT count(*) FROM sample_t SAMPLE(20) SEED(42)) AS seed_reproducible;
-- seeded counts are recorded for two different seeds
SELECT (SELECT count(*) FROM sample_t SAMPLE(20) SEED(1)) AS seed_one,
       (SELECT count(*) FROM sample_t SAMPLE(20) SEED(2)) AS seed_two;
-- SAMPLE BLOCK maps to block-level sampling; the same seed reproduces it
SELECT (SELECT count(*) FROM sample_t SAMPLE BLOCK (10) SEED(5))
     = (SELECT count(*) FROM sample_t SAMPLE BLOCK (10) SEED(5)) AS block_seed_reproducible;
-- the alias follows the clause, Oracle spelling
SELECT count(*) BETWEEN 0 AND 100 AS alias_bound
FROM sample_t SAMPLE(10) s WHERE s.id > 0;
-- the percentage can be an expression
SELECT count(*) BETWEEN 1 AND 90 AS expr_percent FROM sample_t SAMPLE(10 + 20);
-- a percentage outside the range raises the sampling error
SELECT count(*) FROM sample_t SAMPLE(200);
-- the plain TABLESAMPLE spelling keeps working unchanged
SELECT count(*) BETWEEN 1 AND 60 AS tablesample_still_works
FROM sample_t TABLESAMPLE bernoulli (20);
DROP TABLE sample_t;
