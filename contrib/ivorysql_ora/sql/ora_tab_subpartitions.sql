-- Oracle-compatible DBA/ALL/USER_TAB_SUBPARTITIONS regression test
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SHOW IVORYSQL.COMPATIBLE_MODE;

-- Multi-level (composite) partitioning: PostgreSQL models subpartitions
-- as partitions of partitions.
CREATE TABLE msp_root (id int, cat text, dt date) PARTITION BY RANGE (dt);
CREATE TABLE msp_p1 PARTITION OF msp_root
	FOR VALUES FROM ('2023-01-01') TO ('2024-01-01')
	PARTITION BY LIST (cat);
CREATE TABLE msp_p1a PARTITION OF msp_p1 FOR VALUES IN ('a');
CREATE TABLE msp_p1b PARTITION OF msp_p1 FOR VALUES IN ('b');
CREATE TABLE msp_p2 PARTITION OF msp_root
	FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

INSERT INTO msp_root VALUES (1, 'a', '2023-02-01'), (2, 'b', '2023-03-01'),
	(3, 'a', '2023-04-01'), (4, 'c', '2024-02-01');

-- Only the second-level partitions appear; the first-level partitions
-- msp_p1/msp_p2 do not.
SELECT table_name, partition_name, subpartition_name,
	subpartition_position, high_value
FROM user_tab_subpartitions
ORDER BY table_name, partition_name, subpartition_name;

-- Positions: partition position is shared by all subpartitions of the
-- same parent partition.
SELECT partition_name, subpartition_name, partition_position,
	subpartition_position
FROM user_tab_subpartitions
ORDER BY partition_position, subpartition_position;

-- USER_ view is scoped to the owning user, DBA_ sees every schema.
SELECT count(*) AS dba_rows FROM dba_tab_subpartitions;
SELECT count(*) AS all_rows FROM all_tab_subpartitions;

-- Unpartitioned and single-level partitioned tables contribute nothing.
CREATE TABLE msp_plain (id int);
CREATE TABLE msp_flat (id int, dt date) PARTITION BY RANGE (dt);
CREATE TABLE msp_flat_p1 PARTITION OF msp_flat
	FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
SELECT count(*) AS still_two FROM user_tab_subpartitions;

-- Visibility ladder: another role without privileges sees nothing.
CREATE ROLE msp_other LOGIN;
SET ROLE msp_other;
SELECT count(*) AS user_rows FROM user_tab_subpartitions;
SELECT count(*) AS all_rows FROM all_tab_subpartitions;
RESET ROLE;

-- Grant on the root table makes the subpartitions visible through ALL_.
GRANT SELECT ON msp_root TO msp_other;
SET ROLE msp_other;
SELECT count(*) AS all_rows FROM all_tab_subpartitions;
RESET ROLE;

-- Dropping a subpartition removes its row.
DROP TABLE msp_p1b;
SELECT subpartition_name FROM user_tab_subpartitions
ORDER BY subpartition_name;

DROP TABLE msp_root;
DROP TABLE msp_flat;
DROP TABLE msp_plain;
DROP ROLE msp_other;
