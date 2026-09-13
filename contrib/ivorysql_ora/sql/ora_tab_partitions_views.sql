-- DBA_TAB_PARTITIONS / ALL_TAB_PARTITIONS / USER_TAB_PARTITIONS
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SET IVORYSQL.IDENTIFIER_CASE_SWITCH = INTERCHANGE;

--
-- Oracle-compatible partition metadata views: one row per partition,
-- bound rendering, per-partition statistics, composite detection and
-- the DBA/ALL/USER visibility ladder.
--

CREATE TABLE TP_T (A INT, B VARCHAR2(10)) PARTITION BY RANGE (A);
CREATE TABLE TP_P1 PARTITION OF TP_T FOR VALUES FROM (MINVALUE) TO (10);
CREATE TABLE TP_P2 PARTITION OF TP_T FOR VALUES FROM (10) TO (20);

-- a sub-partitioned partition reports COMPOSITE = YES
CREATE TABLE TP_P3 PARTITION OF TP_T FOR VALUES FROM (20) TO (MAXVALUE)
	PARTITION BY RANGE (B);
CREATE TABLE TP_P3_S1 PARTITION OF TP_P3 FOR VALUES FROM (MINVALUE) TO ('m');

INSERT INTO TP_T VALUES (1, 'x'), (11, 'y');
ANALYZE TP_P1;

-- the three views have Oracle's column counts (56/56/55)
SELECT count(*) AS dba_cols
FROM pg_attribute
WHERE attrelid = 'sys.dba_tab_partitions'::regclass AND attnum > 0 AND NOT attisdropped;
SELECT count(*) AS all_cols
FROM pg_attribute
WHERE attrelid = 'sys.all_tab_partitions'::regclass AND attnum > 0 AND NOT attisdropped;
SELECT count(*) AS user_cols
FROM pg_attribute
WHERE attrelid = 'sys.user_tab_partitions'::regclass AND attnum > 0 AND NOT attisdropped;

-- USER_TAB_PARTITIONS column order matches Oracle (first and last six)
SELECT attname
FROM pg_attribute
WHERE attrelid = 'sys.user_tab_partitions'::regclass AND attnum > 0 AND NOT attisdropped
ORDER BY attnum
LIMIT 6;
SELECT attname
FROM pg_attribute
WHERE attrelid = 'sys.user_tab_partitions'::regclass AND attnum > 0 AND NOT attisdropped
ORDER BY attnum DESC
LIMIT 6;

-- one row per partition with bound text, position and markers
-- (INTERVAL is a keyword in oracle mode, so qualify the column)
SELECT TABLE_NAME, PARTITION_NAME, COMPOSITE, SUBPARTITION_COUNT,
	PARTITION_POSITION, LOGGING, COMPRESSION, GLOBAL_STATS, USER_STATS,
	IS_NESTED, UP.INTERVAL, INDEXING, READ_ONLY
FROM USER_TAB_PARTITIONS UP
WHERE TABLE_NAME LIKE 'TP\_T' ESCAPE '\' OR TABLE_NAME LIKE 'TP\_P3' ESCAPE '\'
ORDER BY TABLE_NAME, PARTITION_NAME;

-- HIGH_VALUE renders the partition bound; its length follows
SELECT PARTITION_NAME, HIGH_VALUE, HIGH_VALUE_LENGTH = LENGTH(HIGH_VALUE) AS len_ok
FROM USER_TAB_PARTITIONS
WHERE TABLE_NAME = 'TP_T'
ORDER BY PARTITION_NAME;

-- statistics per partition: analyzed partition reports rows, others NULL
SELECT PARTITION_NAME, NUM_ROWS, BLOCKS IS NOT NULL AS blocks_ok,
	LAST_ANALYZED IS NOT NULL AS analyzed
FROM USER_TAB_PARTITIONS
WHERE TABLE_NAME = 'TP_T'
ORDER BY PARTITION_NAME;

-- storage columns without a PostgreSQL counterpart stay NULL
SELECT PCT_FREE IS NULL AND PCT_USED IS NULL AND INI_TRANS IS NULL
	AND MAX_TRANS IS NULL AND MIN_EXTENT IS NULL AND MAX_EXTENT IS NULL
	AND MAX_SIZE IS NULL AND FREELISTS IS NULL AND EMPTY_BLOCKS IS NULL
	AS storage_cols_null
FROM USER_TAB_PARTITIONS
WHERE TABLE_NAME = 'TP_T' AND PARTITION_NAME = 'TP_P1';

-- segment tracking follows whether the partition has storage
SELECT PARTITION_NAME, SEGMENT_CREATED
FROM USER_TAB_PARTITIONS
WHERE TABLE_NAME = 'TP_T'
ORDER BY PARTITION_NAME;

-- DBA_ sees everything without grants
SELECT count(*) AS dba_count FROM DBA_TAB_PARTITIONS
WHERE TABLE_NAME LIKE 'TP\_%' ESCAPE '\';

CREATE ROLE TP_VIEWER NOLOGIN;
SET ROLE TP_VIEWER;

-- without table privileges nothing is visible through ALL_/USER_
SELECT count(*) AS all_count FROM ALL_TAB_PARTITIONS WHERE TABLE_NAME = 'TP_T';
SELECT count(*) AS user_count FROM USER_TAB_PARTITIONS WHERE TABLE_NAME = 'TP_T';

RESET ROLE;
GRANT SELECT ON TP_T TO TP_VIEWER;
SET ROLE TP_VIEWER;

-- with SELECT on the parent the partitions are visible through ALL_
SELECT count(*) AS all_count FROM ALL_TAB_PARTITIONS WHERE TABLE_NAME = 'TP_T';
SELECT count(*) AS user_count FROM USER_TAB_PARTITIONS WHERE TABLE_NAME = 'TP_T';

RESET ROLE;
REVOKE SELECT ON TP_T FROM TP_VIEWER;
DROP ROLE TP_VIEWER;

DROP TABLE TP_P3_S1;
DROP TABLE TP_P3;
DROP TABLE TP_P2;
DROP TABLE TP_P1;
DROP TABLE TP_T;
