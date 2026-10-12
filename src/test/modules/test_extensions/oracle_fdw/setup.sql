--
-- Fixture schema for the IvorySQL oracle_fdw TAP test
-- (src/test/modules/test_extensions/t/002_oracle_fdw.pl, IvorySQL #1307).
--
-- This file is mounted into /container-entrypoint-initdb.d by compose.yaml
-- and is executed by the gvenzl/oracle-free image on first initialization,
-- connected as SYS.  The dedicated test user itself is created by the image
-- from the APP_USER / APP_USER_PASSWORD environment variables, so no
-- credentials appear in this file.  The test user's schema is used for the
-- fixture objects via CURRENT_SCHEMA.
--
-- The TAP test reseeds both tables before every run; the seed rows below are
-- the canonical initial state shared by the fixture and the documentation.

WHENEVER SQLERROR EXIT SQL.SQLCODE

-- The image runs this script connected as SYS.  Depending on the image
-- version the session starts in the CDB root or in FREEPDB1; switch to the
-- application PDB when possible and stay put otherwise.
BEGIN
	EXECUTE IMMEDIATE 'ALTER SESSION SET CONTAINER = FREEPDB1';
EXCEPTION
	WHEN OTHERS THEN NULL;  -- already inside a PDB
END;
/

ALTER SESSION SET CURRENT_SCHEMA = IV1307;

-- EXPLAIN VERBOSE in oracle_fdw reads the remote plan from these views.
GRANT SELECT ON SYS.V_$SQL TO IV1307;
GRANT SELECT ON SYS.V_$SQL_PLAN TO IV1307;
GRANT SELECT ON SYS.V_$TRANSACTION TO IV1307;

CREATE TABLE IV1307_TYPES (
	ID      NUMBER(10)      NOT NULL,
	AMOUNT  NUMBER(18,4),
	TXT     VARCHAR2(100 CHAR),
	D       DATE,
	TS      TIMESTAMP(6),
	PAYLOAD RAW(16),
	NOTE    CLOB,
	CONSTRAINT IV1307_TYPES_PK PRIMARY KEY (ID)
);

CREATE TABLE IV1307_LOOKUP (
	ID    NUMBER(10)     NOT NULL,
	CODE  VARCHAR2(20 CHAR),
	LABEL VARCHAR2(50 CHAR),
	CONSTRAINT IV1307_LOOKUP_PK PRIMARY KEY (ID)
);

INSERT INTO IV1307_TYPES (id, amount, txt, d, ts, payload, note) VALUES
	(1, 12345.6789, '中文数据测试',
	 TO_DATE('2024-02-29 10:20:30','YYYY-MM-DD HH24:MI:SS'),
	 TO_TIMESTAMP('2024-02-29 23:59:59.123456','YYYY-MM-DD HH24:MI:SS.FF6'),
	 HEXTORAW('0123456789ABCDEF0123456789ABCDEF'), '中文CLOB内容 first line');
INSERT INTO IV1307_TYPES (id, amount, txt, d, ts, payload, note) VALUES
	(2, -999999999999.9999, 'English text',
	 TO_DATE('2023-01-01 00:00:00','YYYY-MM-DD HH24:MI:SS'),
	 TO_TIMESTAMP('2023-06-15 12:34:56.000001','YYYY-MM-DD HH24:MI:SS.FF6'),
	 HEXTORAW('FF'), NULL);
INSERT INTO IV1307_TYPES (id) VALUES (3);
INSERT INTO IV1307_TYPES (id, amount, txt) VALUES (4, 7, '');
INSERT INTO IV1307_TYPES (id, amount, txt) VALUES (5, 0.0001, 'row five');

INSERT INTO IV1307_LOOKUP (id, code, label) VALUES (1, 'C1', 'label one 中文');
INSERT INTO IV1307_LOOKUP (id, code, label) VALUES (2, 'C2', 'label two');
INSERT INTO IV1307_LOOKUP (id, code, label) VALUES (5, 'C1', 'label five');

COMMIT
/
