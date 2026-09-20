-- Oracle-compatible USER_PART_INDEXES regression test
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SHOW IVORYSQL.COMPATIBLE_MODE;

-- RANGE-partitioned table with one prefixed and one non-prefixed index.
CREATE TABLE ipi_tab (id int, dt date, cat text) PARTITION BY RANGE (dt);
CREATE TABLE ipi_p1 PARTITION OF ipi_tab
	FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE ipi_p2 PARTITION OF ipi_tab
	FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE INDEX ipi_dt_ix ON ipi_tab (dt);
CREATE INDEX ipi_id_ix ON ipi_tab (id);

INSERT INTO ipi_tab VALUES (1, '2023-02-01', 'a'), (2, '2024-02-01', 'b');

-- Both partitioned indexes appear with their type/count/keys.
SELECT index_name, table_name, partitioning_type, subpartitioning_type,
	partition_count, partitioning_key_count, subpartitioning_key_count,
	locality, alignment
FROM user_part_indexes
ORDER BY index_name;

-- Composite (nested) partitioning: the sub-strategy columns cannot be
-- represented for a table with nested partitions.
CREATE TABLE ipi_comp (id int, dt date, cat text) PARTITION BY RANGE (dt);
CREATE TABLE ipi_comp_p1 PARTITION OF ipi_comp
	FOR VALUES FROM ('2023-01-01') TO ('2024-01-01')
	PARTITION BY LIST (cat);
CREATE TABLE ipi_comp_p1a PARTITION OF ipi_comp_p1 FOR VALUES IN ('a');
CREATE TABLE ipi_comp_p1b PARTITION OF ipi_comp_p1 FOR VALUES IN ('b');
CREATE INDEX ipi_comp_ix ON ipi_comp (id);

SELECT index_name, partitioning_type, subpartitioning_type,
	subpartitioning_key_count, partition_count, alignment
FROM user_part_indexes
WHERE index_name = 'IPI_COMP_IX';

-- HASH partitioning maps to HASH.
CREATE TABLE ipi_hash (id int, k int) PARTITION BY HASH (k);
CREATE TABLE ipi_h1 PARTITION OF ipi_hash
	FOR VALUES WITH (MODULUS 2, REMAINDER 0);
CREATE TABLE ipi_h2 PARTITION OF ipi_hash
	FOR VALUES WITH (MODULUS 2, REMAINDER 1);
CREATE INDEX ipi_hash_kx ON ipi_hash (k);

SELECT index_name, partitioning_type, partition_count
FROM user_part_indexes
WHERE index_name = 'IPI_HASH_KX';

-- Plain (non-partitioned) indexes and child indexes on partitions are
-- not rows of this view.
CREATE TABLE ipi_plain (id int);
CREATE INDEX ipi_plain_ix ON ipi_plain (id);
-- Still exactly four partitioned indexes: the plain index, and the
-- per-partition child indexes, are not rows of this view.
SELECT count(*) AS all_rows FROM user_part_indexes;

-- Dropping a partition drops its child index and decreases the count.
ALTER TABLE ipi_tab DETACH PARTITION ipi_p2;
SELECT partition_count FROM user_part_indexes
WHERE index_name = 'IPI_DT_IX';

-- Visibility: other roles see nothing through USER_.
CREATE ROLE ipi_other LOGIN;
SET ROLE ipi_other;
SELECT count(*) AS user_rows FROM user_part_indexes;
RESET ROLE;

DROP TABLE ipi_tab;
DROP TABLE ipi_comp;
DROP TABLE ipi_hash;
DROP TABLE ipi_plain;
DROP ROLE ipi_other;
