-- DBA_CONSTRAINTS / ALL_CONSTRAINTS / USER_CONSTRAINTS
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SET IVORYSQL.IDENTIFIER_CASE_SWITCH = INTERCHANGE;

--
-- Oracle-compatible constraint metadata views: constraint-type mapping
-- (P/U/R/C, with PostgreSQL NOT NULL constraints surfaced as C rows with
-- a synthesized search condition), foreign-key resolution to the
-- referenced constraint, deferrability, backing indexes and the
-- DBA/ALL/USER visibility ladder.
--

CREATE TABLE CV_P (PID INT PRIMARY KEY);
CREATE TABLE CV_T (ID INT PRIMARY KEY, NAME VARCHAR2(30) NOT NULL,
	CODE INT DEFAULT 7,
	CONSTRAINT CV_CK CHECK (ID > 0),
	CONSTRAINT CV_FK FOREIGN KEY (ID) REFERENCES CV_P (PID)
		ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED);

-- a second foreign key with the default NO ACTION rule
CREATE TABLE CV_T2 (ID INT REFERENCES CV_P (PID));

-- the three views have Oracle's column counts (26 each, OWNER included)
SELECT count(*) AS dba_cols
FROM pg_attribute
WHERE attrelid = 'sys.dba_constraints'::regclass AND attnum > 0 AND NOT attisdropped;
SELECT count(*) AS all_cols
FROM pg_attribute
WHERE attrelid = 'sys.all_constraints'::regclass AND attnum > 0 AND NOT attisdropped;
SELECT count(*) AS user_cols
FROM pg_attribute
WHERE attrelid = 'sys.user_constraints'::regclass AND attnum > 0 AND NOT attisdropped;

-- USER_CONSTRAINTS column order matches Oracle (first and last six)
SELECT attname
FROM pg_attribute
WHERE attrelid = 'sys.user_constraints'::regclass AND attnum > 0 AND NOT attisdropped
ORDER BY attnum
LIMIT 6;
SELECT attname
FROM pg_attribute
WHERE attrelid = 'sys.user_constraints'::regclass AND attnum > 0 AND NOT attisdropped
ORDER BY attnum DESC
LIMIT 6;

-- constraint-type mapping across P/U/R/C (NOT NULL surfaces as C)
SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM USER_CONSTRAINTS
WHERE TABLE_NAME IN ('CV_P', 'CV_T')
ORDER BY CONSTRAINT_TYPE, CONSTRAINT_NAME;

-- the NOT NULL constraint carries a synthesized search condition like
-- Oracle; the check constraint shows its expression
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE, SEARCH_CONDITION_VC
FROM USER_CONSTRAINTS
WHERE TABLE_NAME = 'CV_T' AND CONSTRAINT_TYPE = 'C'
ORDER BY CONSTRAINT_NAME;

-- foreign keys resolve to the referenced primary-key constraint
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE, R_OWNER,
	R_CONSTRAINT_NAME, DELETE_RULE, STATUS, DEFERRABLE, DEFERRED, VALIDATED
FROM USER_CONSTRAINTS
WHERE CONSTRAINT_TYPE = 'R'
ORDER BY TABLE_NAME;

-- primary-key and unique constraints report their backing index
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE, INDEX_OWNER, INDEX_NAME
FROM USER_CONSTRAINTS
WHERE TABLE_NAME = 'CV_T' AND CONSTRAINT_TYPE IN ('P', 'U')
ORDER BY CONSTRAINT_NAME;

-- constant markers for an ordinary check constraint
SELECT STATUS, DEFERRABLE, DEFERRED, VALIDATED, GENERATED, BAD, RELY,
	PRECHECK, LAST_CHANGE, INVALID, VIEW_RELATED, ORIGIN_CON_ID
FROM USER_CONSTRAINTS
WHERE CONSTRAINT_NAME = 'CV_CK';

-- DBA_ sees every constraint without grants
SELECT count(*) AS dba_count
FROM DBA_CONSTRAINTS
WHERE TABLE_NAME LIKE 'CV\_T%' ESCAPE '\' OR TABLE_NAME = 'CV_P';

CREATE ROLE CV_VIEWER NOLOGIN;
SET ROLE CV_VIEWER;

-- without table privileges nothing is visible through ALL_/USER_
SELECT count(*) AS all_count FROM ALL_CONSTRAINTS WHERE TABLE_NAME = 'CV_T';
SELECT count(*) AS user_count FROM USER_CONSTRAINTS WHERE TABLE_NAME = 'CV_T';

RESET ROLE;
GRANT SELECT ON CV_T TO CV_VIEWER;
SET ROLE CV_VIEWER;

-- with SELECT on the table its constraints are visible through ALL_
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM ALL_CONSTRAINTS
WHERE TABLE_NAME = 'CV_T'
ORDER BY CONSTRAINT_TYPE, CONSTRAINT_NAME;
SELECT count(*) AS user_count FROM USER_CONSTRAINTS WHERE TABLE_NAME = 'CV_T';

RESET ROLE;
REVOKE SELECT ON CV_T FROM CV_VIEWER;
DROP ROLE CV_VIEWER;

DROP TABLE CV_T2;
DROP TABLE CV_T;
DROP TABLE CV_P;
