-- DBA_INDEXES / ALL_INDEXES / USER_INDEXES
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SET IVORYSQL.IDENTIFIER_CASE_SWITCH = INTERCHANGE;

--
-- Oracle-compatible index metadata views: column parity with Oracle,
-- INDEX_TYPE classification (expression/descending keys are
-- FUNCTION-BASED), constraint-backing markers, analysis statistics and
-- the DBA/ALL/USER visibility ladder.
--

CREATE TABLE IV_T (ID INT PRIMARY KEY, CODE INT, NAME VARCHAR2(10));
INSERT INTO IV_T VALUES (1, 10, 'a'), (2, 20, 'b');

-- plain btree stays NORMAL
CREATE INDEX IV_IX ON IV_T (CODE);
-- unique index
CREATE UNIQUE INDEX IV_UX ON IV_T (NAME);
-- expression index is FUNCTION-BASED
CREATE INDEX IV_FX ON IV_T (UPPER(NAME));
-- descending key column is FUNCTION-BASED too
CREATE INDEX IV_DX ON IV_T (CODE DESC);
-- index on a partitioned parent is PARTITIONED
CREATE TABLE IV_PT (A INT) PARTITION BY RANGE (A);
CREATE INDEX IV_PX ON IV_PT (A);
-- index on an unlogged table is NOLOGGING
CREATE UNLOGGED TABLE IV_UL (X INT);
CREATE INDEX IV_ULX ON IV_UL (X);

-- the three views have Oracle's column counts (63/63/62)
SELECT count(*) AS dba_cols
FROM pg_attribute
WHERE attrelid = 'sys.dba_indexes'::regclass AND attnum > 0 AND NOT attisdropped;
SELECT count(*) AS all_cols
FROM pg_attribute
WHERE attrelid = 'sys.all_indexes'::regclass AND attnum > 0 AND NOT attisdropped;
SELECT count(*) AS user_cols
FROM pg_attribute
WHERE attrelid = 'sys.user_indexes'::regclass AND attnum > 0 AND NOT attisdropped;

-- USER_INDEXES column order matches Oracle (first and last six shown)
SELECT attname
FROM pg_attribute
WHERE attrelid = 'sys.user_indexes'::regclass AND attnum > 0 AND NOT attisdropped
ORDER BY attnum
LIMIT 6;
SELECT attname
FROM pg_attribute
WHERE attrelid = 'sys.user_indexes'::regclass AND attnum > 0 AND NOT attisdropped
ORDER BY attnum DESC
LIMIT 6;

-- index classification and constant markers; the primary-key index is
-- constraint-backed and system-generated
SELECT INDEX_NAME, INDEX_TYPE, UNIQUENESS, TABLE_NAME, STATUS,
	GENERATED, CONSTRAINT_INDEX, FUNCIDX_STATUS, VISIBILITY
FROM USER_INDEXES
WHERE TABLE_NAME = 'IV_T'
ORDER BY INDEX_NAME;

-- partitioned and persistence-related markers; the partitioned index
-- (relkind 'I' on the partitioned parent) is PARTITIONED, the unlogged
-- table's index is NOLOGGING
SELECT INDEX_NAME, PARTITIONED, LOGGING
FROM USER_INDEXES
WHERE INDEX_NAME LIKE 'IV\_P%' ESCAPE '\' OR INDEX_NAME LIKE 'IV\_UL%' ESCAPE '\'
ORDER BY INDEX_NAME;

-- NUM_ROWS follows the index reltuples: exact when CREATE INDEX built
-- the index, 0 for the primary-key index created before the inserts
SELECT INDEX_NAME, NUM_ROWS
FROM USER_INDEXES
WHERE TABLE_NAME = 'IV_T' AND INDEX_NAME IN ('IV_IX', 'IV_T_PKEY')
ORDER BY INDEX_NAME;

-- storage columns without a PostgreSQL counterpart stay NULL
SELECT INDEX_NAME, PCT_FREE IS NULL AND INI_TRANS IS NULL AND MAX_TRANS IS NULL
	AND INITIAL_EXTENT IS NULL AND NEXT_EXTENT IS NULL AND BLEVEL IS NULL
	AND LEAF_BLOCKS IS NULL AND DISTINCT_KEYS IS NULL AND CLUSTERING_FACTOR IS NULL
	AND PCT_DIRECT_ACCESS IS NULL AND PREFIX_LENGTH IS NULL
	AS storage_stats_null
FROM USER_INDEXES
WHERE TABLE_NAME = 'IV_T'
ORDER BY INDEX_NAME;

-- constant markers match the Oracle defaults
SELECT DEGREE, INSTANCES, COMPRESSION, TABLE_TYPE, JOIN_INDEX, DROPPED,
	INDEXING, AUTO, SEGMENT_CREATED, BUFFER_POOL, FLASH_CACHE,
	CELL_FLASH_CACHE, GLOBAL_STATS, USER_STATS, TEMPORARY, SECONDARY
FROM USER_INDEXES
WHERE TABLE_NAME = 'IV_T' AND INDEX_NAME = 'IV_IX';

-- statistics columns PostgreSQL does not track stay NULL
SELECT INDEX_NAME, SAMPLE_SIZE IS NULL AS sample_size_null,
	LAST_ANALYZED IS NULL AS last_analyzed_null,
	BLEVEL IS NULL AND LEAF_BLOCKS IS NULL AS btree_stats_null
FROM USER_INDEXES
WHERE TABLE_NAME = 'IV_T'
ORDER BY INDEX_NAME;

-- invalid indexes are UNUSABLE
ALTER INDEX IV_IX UNUSABLE;
SELECT STATUS FROM USER_INDEXES WHERE INDEX_NAME = 'IV_IX';
REINDEX INDEX IV_IX;
SELECT STATUS FROM USER_INDEXES WHERE INDEX_NAME = 'IV_IX';

-- DBA_INDEXES sees everything without grants
SELECT count(*) AS dba_count FROM DBA_INDEXES
WHERE INDEX_NAME LIKE 'IV\_%' ESCAPE '\' OR INDEX_NAME LIKE 'IV\_T\_%' ESCAPE '\';

CREATE ROLE IV_VIEWER NOLOGIN;
SET ROLE IV_VIEWER;

-- without table privileges nothing is visible through ALL_/USER_
SELECT count(*) AS all_count FROM ALL_INDEXES WHERE INDEX_NAME = 'IV_IX';
SELECT count(*) AS user_count FROM USER_INDEXES WHERE INDEX_NAME = 'IV_IX';

RESET ROLE;
GRANT SELECT ON IV_T TO IV_VIEWER;
SET ROLE IV_VIEWER;

-- with SELECT on the table the index is visible through ALL_ but not USER_
SELECT count(*) AS all_count FROM ALL_INDEXES WHERE INDEX_NAME = 'IV_IX';
SELECT count(*) AS user_count FROM USER_INDEXES WHERE INDEX_NAME = 'IV_IX';

RESET ROLE;
REVOKE SELECT ON IV_T FROM IV_VIEWER;
DROP ROLE IV_VIEWER;

DROP INDEX IV_ULX;
DROP TABLE IV_UL;
DROP INDEX IV_PX;
DROP TABLE IV_PT;
DROP INDEX IV_DX;
DROP INDEX IV_FX;
DROP INDEX IV_UX;
DROP INDEX IV_IX;
DROP TABLE IV_T;
