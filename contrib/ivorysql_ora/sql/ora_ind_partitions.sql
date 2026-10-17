-- Oracle-compatible USER_IND_PARTITIONS regression test
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SHOW IVORYSQL.COMPATIBLE_MODE;

-- RANGE-partitioned table with a local index: one index partition per
-- table partition, positions in bound order.
CREATE TABLE ipn_tab (id int, dt date) PARTITION BY RANGE (dt);
CREATE TABLE ipn_p1 PARTITION OF ipn_tab
	FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE ipn_p2 PARTITION OF ipn_tab
	FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE INDEX ipn_dt_ix ON ipn_tab (dt);

INSERT INTO ipn_tab VALUES (1, '2023-02-01'), (2, '2024-02-01');

SELECT index_name, partition_name, composite, subpartition_count,
	partition_position, status, logging, interval, global_stats,
	orphaned_entries
FROM user_ind_partitions
ORDER BY partition_position;

-- HIGH_VALUE is the bound of the corresponding table partition.
SELECT partition_name, high_value
FROM user_ind_partitions
ORDER BY partition_position;

-- Indexes that are not attached partitions are not listed.
CREATE TABLE ipn_plain (id int);
CREATE INDEX ipn_plain_ix ON ipn_plain (id);
SELECT count(*) AS plain_present FROM user_ind_partitions
WHERE index_name = 'IPN_PLAIN_IX';

-- LIST partitioning renders its bound the same way.
CREATE TABLE ipn_list (id int, cat text) PARTITION BY LIST (cat);
CREATE TABLE ipn_l1 PARTITION OF ipn_list FOR VALUES IN ('a');
CREATE TABLE ipn_l2 PARTITION OF ipn_list FOR VALUES IN ('b');
CREATE INDEX ipn_cat_ix ON ipn_list (cat);
SELECT index_name, partition_name, high_value
FROM user_ind_partitions
WHERE index_name = 'IPN_CAT_IX'
ORDER BY partition_position;

-- Marking a leaf index unusable shows in the STATUS column.
ALTER INDEX ipn_p1_dt_idx UNUSABLE;
SELECT partition_name, status
FROM user_ind_partitions
WHERE index_name = 'IPN_DT_IX'
ORDER BY partition_position;
REINDEX INDEX ipn_p1_dt_idx;
SELECT partition_name, status
FROM user_ind_partitions
WHERE index_name = 'IPN_DT_IX'
ORDER BY partition_position;

-- Detaching a table partition removes its index partition row.
ALTER TABLE ipn_tab DETACH PARTITION ipn_p2;
SELECT count(*) AS ipn_rows FROM user_ind_partitions
WHERE index_name = 'IPN_DT_IX';

-- Visibility: other roles see nothing through USER_.
CREATE ROLE ipn_other LOGIN;
SET ROLE ipn_other;
SELECT count(*) AS user_rows FROM user_ind_partitions;
RESET ROLE;

DROP TABLE ipn_tab;
DROP TABLE ipn_list;
DROP TABLE ipn_plain;
DROP ROLE ipn_other;
