-- compatible_mode
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SHOW IVORYSQL.COMPATIBLE_MODE;

SET IVORYSQL.IDENTIFIER_CASE_SWITCH = INTERCHANGE;
SHOW IVORYSQL.IDENTIFIER_CASE_SWITCH;

-- create a procedure
CREATE TABLE TB_TODEL(ID INT);
CREATE OR REPLACE PROCEDURE PROC_DEL_TB(I INT) IS
BEGIN
	DROP TABLE TB_TODEL;
END;
/

-- create a function with security definer
CREATE OR REPLACE FUNCTION FUNC_AUTHID(P VARCHAR2)
RETURN INT DETERMINISTIC IS
BEGIN
	RETURN 123;
END;
/
-- select ... from all_procedures
SELECT OBJECT_NAME, OBJECT_TYPE, DETERMINISTIC, PARALLEL, AUTHID
FROM ALL_PROCEDURES
WHERE OBJECT_NAME = 'PROC_DEL_TB' OR OBJECT_NAME = 'FUNC_AUTHID';

-- create a function with all-lowercase name
CREATE OR REPLACE FUNCTION "func_quotes_lower"(ID INT)
RETURN VARCHAR2 IS
BEGIN
	RETURN 'func_quotes_lower'::VARCHAR2;
END;
/
-- select ... from all_source
SELECT NAME, LINE, TEXT FROM ALL_SOURCE WHERE NAME = 'func_quotes_lower';

-- data_type and pls_type in all_arguments
CREATE OR REPLACE FUNCTION FUNC_22_ARG_TYPES
(
	T1 CHAR, T2 NCHAR, T3 VARCHAR2, T4 INTEGER, T5 NUMBER, T6 NUMERIC,
	T7 BINARY_FLOAT, T8 BINARY_DOUBLE, T9 REAL, T10 FLOAT, T11 DOUBLE PRECISION,
	T12 DATE, T13 TIMESTAMP, T14 TIMESTAMP WITH TIME ZONE,
	T15 TIMESTAMP WITH LOCAL TIME ZONE,
	T16 CLOB, T17 BLOB, T18 NCLOB, T19 LONG, T20 LONG RAW, T21 BOOLEAN
)
RETURN RAW IS
BEGIN
	RETURN CAST('FUNC_22_ARG_TYPES' AS RAW);
END;
/

-- select ... from all_arguments
SELECT
	ARGUMENT_NAME || ',' || POSITION || ',' || SEQUENCE || ',' || 
	IN_OUT || ',' || DATA_TYPE || ',' || PLS_TYPE
FROM ALL_ARGUMENTS WHERE OBJECT_NAME = 'FUNC_22_ARG_TYPES'
ORDER BY OBJECT_ID, POSITION;

-- clean data
DROP TABLE IF EXISTS TB_TODEL;
DROP PROCEDURE IF EXISTS PROC_DEL_TB;
DROP FUNCTION IF EXISTS FUNC_AUTHID;
DROP FUNCTION IF EXISTS "func_quotes_lower";
DROP FUNCTION IF EXISTS FUNC_22_ARG_TYPES;
-- create a function with arguments defaulted
CREATE OR REPLACE FUNCTION FUNC_WITH_DEFAULT
(
	ARG1 IN INT DEFAULT 10,
	ARG2 OUT INT,
	ARG3 IN OUT INT,
	ARG4 IN VARCHAR2(10) DEFAULT NULL
)
RETURN void IS
BEGIN
	ARG2 := ARG1 + 10;
	ARG3 := ARG1 / 2;
END;
/
-- check arguments with default value
SELECT ARGUMENT_NAME, IN_OUT, POSITION, DEFAULTED FROM ALL_ARGUMENTS
WHERE OBJECT_NAME = 'FUNC_WITH_DEFAULT';
-- clean data
DROP FUNCTION IF EXISTS FUNC_WITH_DEFAULT;

-- Oracle dynamic views
\d SYS.V$SESSION
\d SYS.V$PROCESS
SELECT * 
FROM SYS.V$PARAMETER 
WHERE NAME IN ('listen_addresses','application_name','archive_command','archive_mode','block_size')
ORDER BY NAME;

CREATE TABLE t_pk_single (id NUMBER PRIMARY KEY, name VARCHAR2(50));
CREATE TABLE t_pk_composite (id1 NUMBER, id2 NUMBER, CONSTRAINT pk_composite PRIMARY KEY (id1, id2));

CREATE TABLE t_unique (col1 INT, col2 VARCHAR2(20), CONSTRAINT uk_col1 UNIQUE (col1));

CREATE TABLE t_parent (pid INT PRIMARY KEY, pname VARCHAR2(50));
CREATE TABLE t_child (cid INT, pid INT, CONSTRAINT fk_child_parent FOREIGN KEY (pid) REFERENCES t_parent(pid));

CREATE TABLE t_check (
    age INT,
    salary NUMERIC(10,2),
    CONSTRAINT chk_age CHECK (age >= 0),
    CONSTRAINT chk_salary_range CHECK (salary BETWEEN 1000 AND 100000)
);

-- t_partitioned removed as unnecessary

CREATE VIEW v_dummy AS SELECT 1 AS col FROM DUAL;

CREATE MATERIALIZED VIEW mv_dummy AS SELECT 2 AS col FROM DUAL;

CREATE TABLE t_data_types (
    c_varchar VARCHAR2(100),
    c_char CHAR(10),
    c_number NUMBER,
    c_int INT,
    c_numeric NUMERIC,
    c_float FLOAT,
    c_double DOUBLE PRECISION,
    c_date DATE,
    c_ts TIMESTAMP,
    c_tstz TIMESTAMP WITH TIME ZONE,
    c_text TEXT,
    CONSTRAINT pk_data_types PRIMARY KEY (c_varchar, c_char)
);

-- Convert CURRENT_USER to varchar2 then uppercase to match view's owner
SELECT table_name, constraint_name, column_name, position
FROM all_cons_columns
WHERE owner = SYS.ORA_CASE_TRANS(CURRENT_USER::VARCHAR2)
ORDER BY table_name, constraint_name, position;

SELECT constraint_name, COUNT(*) AS column_count
FROM all_cons_columns
WHERE owner = SYS.ORA_CASE_TRANS(CURRENT_USER::VARCHAR2)
GROUP BY constraint_name
ORDER BY constraint_name;

DROP VIEW IF EXISTS v_dummy;
DROP MATERIALIZED VIEW IF EXISTS mv_dummy;
DROP TABLE IF EXISTS t_child;
DROP TABLE IF EXISTS t_parent;
DROP TABLE IF EXISTS t_pk_single;
DROP TABLE IF EXISTS t_pk_composite;
DROP TABLE IF EXISTS t_unique;
DROP TABLE IF EXISTS t_check;
DROP TABLE IF EXISTS t_data_types;
-- USER_CONS_COLUMNS
CREATE TABLE TEST_USER_CONS_COLUMNS (
    ID INT NOT NULL,
    NAME VARCHAR2(30) NOT NULL,
    AGE INT NOT NULL,
    EMAIL VARCHAR2(50),
    CONSTRAINT PK_TEST PRIMARY KEY (ID, NAME),
    CONSTRAINT UQ_EMAIL UNIQUE (EMAIL)
);

SELECT TABLE_NAME, CONSTRAINT_NAME, COLUMN_NAME, POSITION
FROM SYS.USER_CONS_COLUMNS
WHERE TABLE_NAME = 'TEST_USER_CONS_COLUMNS'
AND CONSTRAINT_NAME LIKE '%NOT_NULL%'
ORDER BY CONSTRAINT_NAME, COLUMN_NAME;

SELECT TABLE_NAME, CONSTRAINT_NAME, COLUMN_NAME, POSITION
FROM SYS.USER_CONS_COLUMNS
WHERE TABLE_NAME = 'TEST_USER_CONS_COLUMNS'
AND CONSTRAINT_NAME = 'PK_TEST'
ORDER BY CONSTRAINT_NAME, POSITION;


SELECT TABLE_NAME, CONSTRAINT_NAME, COLUMN_NAME, POSITION
FROM SYS.USER_CONS_COLUMNS
WHERE TABLE_NAME = 'TEST_USER_CONS_COLUMNS'
AND CONSTRAINT_NAME = 'UQ_EMAIL'
ORDER BY CONSTRAINT_NAME, COLUMN_NAME;

-- Clean
DROP TABLE IF EXISTS TEST_USER_CONS_COLUMNS;

-- Test NOT NULL constraint in all_cons_columns
CREATE TABLE t_notnull_test (
    id INT,
    name VARCHAR2(50) NOT NULL,
    age INT
);

SELECT table_name, constraint_name, column_name, position
FROM all_cons_columns
WHERE table_name = 'T_NOTNULL_TEST'
ORDER BY constraint_name, column_name;

DROP TABLE IF EXISTS t_notnull_test;
-- Test DBA_CONS_COLUMNS view
SELECT count(*) > 0 AS view_exists
FROM information_schema.views
WHERE table_schema = 'sys' AND table_name = 'dba_cons_columns';

-- Restricted to tables this test owns: the unrestricted form reported
-- whichever rows happened to sort first in the whole cluster, so any new
-- catalog or test table anywhere rewrote the expected output.
CREATE TABLE t_dba_cons_cols (
    id INT,
    code VARCHAR2(10),
    CONSTRAINT pk_dba_cons_cols PRIMARY KEY (id),
    CONSTRAINT uq_dba_cons_cols UNIQUE (code)
);

SELECT constraint_name, table_name, column_name, position
FROM sys.dba_cons_columns
WHERE table_name = 'T_DBA_CONS_COLS'
AND constraint_name IN ('PK_DBA_CONS_COLS', 'UQ_DBA_CONS_COLS')
ORDER BY constraint_name, table_name, column_name;

DROP TABLE t_dba_cons_cols;

-- ALL_TAB_COLUMNS
DROP TABLE IF EXISTS TEST_ALL_TAB_COLUMNS;

CREATE TABLE TEST_ALL_TAB_COLUMNS (
    ID INT PRIMARY KEY,
    NAME VARCHAR2(50) NOT NULL,
    AGE NUMERIC(5,2),
    CREATE_TIME DATE
);

ANALYZE TEST_ALL_TAB_COLUMNS;

SELECT 
    TABLE_NAME,
    COLUMN_NAME,
    COLUMN_ID,
    DATA_TYPE,
    DATA_TYPE_MOD,
    DATA_LENGTH,
    DATA_PRECISION,
    DATA_SCALE,
    NULLABLE,
    DATA_DEFAULT,
    NUM_DISTINCT,
    LOW_VALUE,
    HIGH_VALUE,
    DENSITY,
    NUM_NULLS,
    NUM_BUCKETS,
    SAMPLE_SIZE,
    CHARACTER_SET_NAME,
    CHAR_COL_DECL_LENGTH,
    GLOBAL_STATS,
    USER_STATS,
    AVG_COL_LEN,
    CHAR_LENGTH,
    CHAR_USED,
    V80_FMT_IMAGE,
    DATA_UPGRADED,
    HISTOGRAM,
    DEFAULT_LENGTH,
    "COLLATION",
    IDENTITY_COLUMN,
    DEFAULT_ON_NULL
FROM SYS.ALL_TAB_COLUMNS
WHERE TABLE_NAME = 'TEST_ALL_TAB_COLUMNS'
AND OWNER = SYS.ORA_CASE_TRANS(CURRENT_SCHEMA::VARCHAR2)
ORDER BY COLUMN_ID;

\set ON_ERROR_STOP off
SELECT COLLATION_NAME FROM SYS.ALL_TAB_COLUMNS WHERE TABLE_NAME = 'TEST_ALL_TAB_COLUMNS';
\set ON_ERROR_STOP on

DROP TABLE IF EXISTS TEST_ALL_TAB_COLUMNS;

-- V$PARAMETER must expose Oracle's documented column list and order
\d SYS.V$PARAMETER

-- NUM and ORDINAL are a dense 1..N numbering in name order
SELECT COUNT(*) = COUNT(DISTINCT NUM) AS num_dense,
       COUNT(*) = COUNT(DISTINCT ORDINAL) AS ordinal_dense,
       MIN(NUM) = 1 AS num_starts_at_one
FROM SYS.V$PARAMETER;

-- DISPLAY_VALUE renders booleans the Oracle way and passes other values
-- through unchanged; the unsupported columns stay NULL/FALSE
SELECT NAME, DISPLAY_VALUE, ISPDB_MODIFIABLE, ISADJUSTED, ISBASIC,
       HASH IS NULL AS hash_null, UPDATE_COMMENT IS NULL AS comment_null
FROM SYS.V$PARAMETER
WHERE NAME = 'enable_seqscan';

SELECT NAME, DISPLAY_VALUE = VALUE AS display_matches_value
FROM SYS.V$PARAMETER
WHERE NAME = 'max_connections';

-- V$INSTANCE / V$VERSION
SELECT INSTANCE_NUMBER, STATUS, DATABASE_STATUS, INSTANCE_ROLE, ACTIVE_STATE, LOGINS
FROM SYS.V$INSTANCE;
SELECT INSTANCE_NAME IS NOT NULL AS has_instance_name,
       HOST_NAME IS NOT NULL AS has_host_name,
       VERSION IS NOT NULL AS has_version,
       STARTUP_TIME IS NOT NULL AS has_startup_time
FROM SYS.V$INSTANCE;
SELECT BANNER IS NOT NULL AS has_banner,
       BANNER_FULL IS NOT NULL AS has_banner_full
FROM SYS.V$VERSION;

-- Oracle-compatible lock and wait runtime views
DROP TABLE IF EXISTS t_lock_test;
CREATE TABLE t_lock_test (id INT);
INSERT INTO t_lock_test VALUES (1);

BEGIN;
SELECT id FROM t_lock_test WHERE id = 1 FOR UPDATE;

-- The session's own relation lock has to show up as a TM lock in mode 2
SELECT COUNT(*) > 0 AS has_tm_lock
FROM SYS.V$LOCK
WHERE SID = PG_BACKEND_PID() AND TYPE = 'TM' AND LMODE = 2;

SELECT MIN(LOCKED_MODE) AS locked_mode
FROM SYS.V$LOCKED_OBJECT
WHERE SESSION_ID = PG_BACKEND_PID();

COMMIT;

SELECT COUNT(*) = (SELECT COUNT(*) FROM PG_STAT_ACTIVITY) AS all_sessions
FROM SYS.V$SESSION_WAIT;

DROP TABLE t_lock_test;

-- Oracle-compatible instance and database runtime views
SELECT NAME = CURRENT_DATABASE() AS is_current,
       OPEN_MODE, DATABASE_ROLE,
       LOG_MODE IN ('ARCHIVELOG', 'NOARCHIVELOG') AS log_mode_ok,
       CURRENT_SCN > 0 AS scn_positive
FROM SYS.V$DATABASE;

SELECT COUNT(*) = 5 AS five_rows FROM SYS.V$SGA;

SELECT VALUE = PG_SIZE_BYTES(CURRENT_SETTING('shared_buffers')) AS buffers_match
FROM SYS.V$SGA WHERE NAME = 'Database Buffers';

SELECT A.VALUE = SUM(B.VALUE) AS total_matches
FROM SYS.V$SGA A, SYS.V$SGA B
WHERE A.NAME = 'Total System Global Area'
  AND B.NAME <> 'Total System Global Area'
GROUP BY A.VALUE;

SELECT COUNT(*) = (SELECT COUNT(*) FROM PG_STAT_ACTIVITY
                    WHERE BACKEND_TYPE <> 'client backend') AS all_bg
FROM SYS.V$BGPROCESS;

SELECT COUNT(*) > 0 AS has_bg FROM SYS.V$BGPROCESS;

-- Oracle-compatible NLS parameter views
SELECT PARAMETER, VALUE
FROM SYS.NLS_SESSION_PARAMETERS
WHERE PARAMETER IN ('NLS_DATE_FORMAT', 'NLS_TERRITORY', 'NLS_LENGTH_SEMANTICS')
ORDER BY PARAMETER;

-- A session-level change is visible in the session view only
SET nls_date_format = 'YYYY/MM/DD';
SELECT VALUE AS session_value FROM SYS.NLS_SESSION_PARAMETERS
WHERE PARAMETER = 'NLS_DATE_FORMAT';
SELECT VALUE AS instance_value FROM SYS.NLS_INSTANCE_PARAMETERS
WHERE PARAMETER = 'NLS_DATE_FORMAT';
RESET nls_date_format;

SELECT VALUE AS restored_value FROM SYS.NLS_SESSION_PARAMETERS
WHERE PARAMETER = 'NLS_DATE_FORMAT';

SELECT PARAMETER, VALUE
FROM SYS.NLS_DATABASE_PARAMETERS
WHERE PARAMETER IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET', 'NLS_DATE_FORMAT')
ORDER BY PARAMETER;

-- Oracle-compatible V$SYSSTAT view
SELECT COUNT(*) = 8 AS eight_rows FROM SYS.V$SYSSTAT;
SELECT MIN(VALUE) >= 0 AS values_non_negative FROM SYS.V$SYSSTAT;
SELECT COUNT(*) = 1 AS has_commits FROM SYS.V$SYSSTAT WHERE NAME = 'user commits';
SELECT COUNT(*) = COUNT(DISTINCT NAME) AS names_unique FROM SYS.V$SYSSTAT;

-- Oracle-compatible V$SYSTEM_PARAMETER view
SELECT COUNT(*) = (SELECT COUNT(*) FROM PG_SETTINGS) AS matches_pg_settings
FROM SYS.V$SYSTEM_PARAMETER;

SELECT VALUE = CURRENT_SETTING('shared_buffers') AS value_matches,
       DEFAULT_VALUE IS NOT NULL AS has_default
FROM SYS.V$SYSTEM_PARAMETER
WHERE NAME = 'shared_buffers';

SELECT COUNT(*) = COUNT(DISTINCT NAME) AS names_unique FROM SYS.V$SYSTEM_PARAMETER;

-- Oracle-compatible V$TRANSACTION view
DROP TABLE IF EXISTS t_txn_test;
CREATE TABLE t_txn_test (id INT);
BEGIN;
INSERT INTO t_txn_test VALUES (1);
SELECT COUNT(*) = 1 AS has_transaction
FROM SYS.V$TRANSACTION
WHERE SID = PG_BACKEND_PID() AND STATUS = 'ACTIVE';
SELECT COUNT(*) > 0 AS xid_visible
FROM SYS.V$TRANSACTION
WHERE SID = PG_BACKEND_PID() AND XID IS NOT NULL;
COMMIT;
DROP TABLE t_txn_test;

-- Oracle-compatible V$CONTROLFILE view
SELECT NAME = CURRENT_SETTING('data_directory') || '/global/pg_control' AS matches_data_dir,
       STATUS
FROM SYS.V$CONTROLFILE;

-- Oracle-compatible V$SPPARAMETER view
SELECT COUNT(*) > 0 AS has_entries FROM SYS.V$SPPARAMETER;

SELECT COUNT(*) = COUNT(DISTINCT NAME) AS names_unique FROM SYS.V$SPPARAMETER;

SELECT COUNT(*) = 0 AS all_names_valid
FROM SYS.V$SPPARAMETER
WHERE NAME NOT IN (SELECT NAME FROM PG_SETTINGS);

SELECT COUNT(*) = 1 AS one_shared_buffers
FROM SYS.V$SPPARAMETER WHERE NAME = 'shared_buffers';

-- Oracle-compatible V$DIAG_INFO view
SELECT COUNT(*) = 5 AS five_rows FROM SYS.V$DIAG_INFO;

SELECT VALUE = CURRENT_SETTING('data_directory') AS data_dir_matches
FROM SYS.V$DIAG_INFO WHERE NAME = 'Data Directory';

SELECT COUNT(*) = COUNT(DISTINCT NAME) AS names_unique FROM SYS.V$DIAG_INFO;

-- V$SESSION now reports the Oracle columns USER#, PROCESS and LAST_CALL_ET
SELECT COUNT(*) = 1 AS has_me
FROM SYS.V$SESSION WHERE SID = PG_BACKEND_PID();

SELECT COUNT(*) = 1 AS user_number_present
FROM SYS.V$SESSION WHERE SID = PG_BACKEND_PID() AND "USER#" > 0;

SELECT PROCESS = PG_BACKEND_PID()::TEXT AS process_matches
FROM SYS.V$SESSION WHERE SID = PG_BACKEND_PID();

SELECT LAST_CALL_ET >= 0 AS last_call_et_sane
FROM SYS.V$SESSION WHERE SID = PG_BACKEND_PID();

-- Oracle-compatible V$THREAD view
SELECT COUNT(*) = 1 AS one_thread, MIN(THREAD_NO) = 1 AS thread_no,
       MIN(STATUS) = 'OPEN' AS open, MIN(GROUPS) = 1 AS one_group
FROM SYS.V$THREAD;

-- V$PROCESS now reports Oracle's PID column
SELECT PID = SPID AS pid_matches_spid
FROM SYS.V$PROCESS WHERE SPID = PG_BACKEND_PID();

-- Oracle-compatible V$SEGSTAT_NAME / V$SEGSTAT
SELECT COUNT(*) = 3 AS three_statistics FROM SYS.V$SEGSTAT_NAME;
DROP TABLE IF EXISTS t_segstat_test;
CREATE TABLE t_segstat_test (id INT);
INSERT INTO t_segstat_test SELECT GENERATE_SERIES(1, 10);
SELECT id FROM t_segstat_test WHERE id = 1;
SELECT COUNT(*) = 3 AS three_values_per_segment
FROM SYS.V$SEGSTAT
WHERE OBJ# = 't_segstat_test'::REGCLASS::INT8;
SELECT COUNT(*) = 3 * (SELECT COUNT(*) FROM PG_STATIO_ALL_TABLES ST
                        JOIN PG_CLASS C ON C.OID = ST.RELID
                        JOIN PG_NAMESPACE N ON N.OID = C.RELNAMESPACE
                       WHERE N.NSPNAME NOT IN ('pg_catalog', 'information_schema', 'pg_toast')) AS total_rows
FROM SYS.V$SEGSTAT;

-- Oracle-compatible V$NLS_PARAMETERS
SELECT COUNT(*) = 7 AS seven_rows FROM SYS.V$NLS_PARAMETERS;
SELECT VALUE = CURRENT_SETTING('nls_date_format') AS date_format_matches
FROM SYS.V$NLS_PARAMETERS WHERE PARAMETER = 'NLS_DATE_FORMAT';

-- Oracle-compatible V$EVENT_NAME
SELECT COUNT(*) = (SELECT COUNT(*) FROM PG_CATALOG.PG_WAIT_EVENTS) AS all_events
FROM SYS.V$EVENT_NAME;
SELECT COUNT(*) > 0 AS has_io_class FROM SYS.V$EVENT_NAME WHERE WAIT_CLASS = 'IO';

-- Oracle-compatible V$TIMER
SELECT COUNT(*) = 1 AS one_row, MIN(HMSECS) > 0 AS positive FROM SYS.V$TIMER;

-- Oracle-compatible V$LOCK_TYPE
SELECT COUNT(*) = 7 AS seven_types FROM SYS.V$LOCK_TYPE;
SELECT COUNT(*) = 1 AS tm_present FROM SYS.V$LOCK_TYPE WHERE TYPE = 'TM';

-- V$TIMEZONE_NAMES lists the server's time zones with Oracle-shaped offsets
SELECT COUNT(*) > 100 AS has_zones FROM SYS.V$TIMEZONE_NAMES;
SELECT TIMEZONE_ID, TZ_ABBREV, TZ_OFFSET
FROM SYS.V$TIMEZONE_NAMES
WHERE TIMEZONE_ID = 'UTC';
SELECT COUNT(*) = 0 AS offsets_well_formed
FROM SYS.V$TIMEZONE_NAMES
WHERE TZ_OFFSET NOT LIKE '+__:__' AND TZ_OFFSET NOT LIKE '-__:__';
SELECT COUNT(*) > 0 AS has_nonzero_offsets
FROM SYS.V$TIMEZONE_NAMES
WHERE TZ_OFFSET <> '+00:00';

-- V$OBJECT_USAGE reports index usage the way Oracle's monitoring view does:
-- an index is USED once it has been scanned since the statistics were reset
CREATE TABLE t_obj_usage (a INT);
CREATE INDEX idx_obj_usage ON t_obj_usage (a);
INSERT INTO t_obj_usage VALUES (1), (2);
ANALYZE t_obj_usage;
SELECT INDEX_NAME, TABLE_NAME, MONITORING, USED, END_MONITORING IS NULL AS monitoring_open
FROM SYS.V$OBJECT_USAGE
WHERE INDEX_NAME = 'IDX_OBJ_USAGE';
SET enable_seqscan = off;
SELECT count(*) AS scanned FROM t_obj_usage WHERE a = 1;
RESET enable_seqscan;
SELECT pg_stat_force_next_flush();
SELECT INDEX_NAME, USED
FROM SYS.V$OBJECT_USAGE
WHERE INDEX_NAME = 'IDX_OBJ_USAGE';
DROP TABLE t_obj_usage;

-- USER_OBJECT_USAGE lists only the current user's indexes, DBA_OBJECT_USAGE all
-- of them; both expose the same columns as V$OBJECT_USAGE
DROP ROLE IF EXISTS ora_idx_other;
CREATE ROLE ora_idx_other;
CREATE TABLE t_idx_usage (a INT);
CREATE INDEX idx_usage_probe ON t_idx_usage (a);
GRANT SELECT ON t_idx_usage TO ora_idx_other;

SELECT COUNT(*) = 1 AS owner_sees_own
FROM SYS.USER_OBJECT_USAGE WHERE INDEX_NAME = 'IDX_USAGE_PROBE';

SET ROLE ora_idx_other;
SELECT COUNT(*) = 0 AS other_user_hidden
FROM SYS.USER_OBJECT_USAGE WHERE INDEX_NAME = 'IDX_USAGE_PROBE';
SELECT COUNT(*) = 1 AS other_sees_dba
FROM SYS.DBA_OBJECT_USAGE WHERE INDEX_NAME = 'IDX_USAGE_PROBE';
SET ROLE NONE;

SELECT COUNT(*) = 1 AS dba_sees_all
FROM SYS.DBA_OBJECT_USAGE WHERE INDEX_NAME = 'IDX_USAGE_PROBE';

DROP INDEX idx_usage_probe;
DROP TABLE t_idx_usage;
DROP ROLE ora_idx_other;
