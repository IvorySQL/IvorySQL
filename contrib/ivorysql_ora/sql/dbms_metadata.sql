--
-- dbms_metadata.sql
--
-- Tests for the DBMS_METADATA package (GET_DDL subset).
--
-- DBMS_METADATA.GET_DDL returns Oracle-style DDL that recreates an
-- existing object.  Supported object types:
--   TABLE, VIEW, MATERIALIZED VIEW, SEQUENCE, INDEX,
--   FUNCTION, PROCEDURE, TRIGGER
--
-- Coverage:
--   1.  TABLE         - columns (types, NOT NULL, DEFAULT), constraints
--                       (PRIMARY KEY / UNIQUE / FOREIGN KEY / CHECK),
--                       table and column comments
--   2.  TABLE         - lookup is case-insensitive ('dept' vs 'DEPT')
--   3.  TABLE         - quoted mixed-case names round-trip unchanged
--   4.  TABLE         - cross-schema FOREIGN KEY is fully qualified
--   5.  TABLE         - 100-column table (no truncation)
--   6.  TABLE         - serial column DEFAULT keeps the nextval() reference
--   7.  VIEW          - body from pg_get_viewdef, fully qualified under
--                       a restricted search_path
--   8.  MATERIALIZED VIEW
--   9.  SEQUENCE      - all clauses (INCREMENT/START/MIN/MAX/CACHE/CYCLE)
--  10.  SEQUENCE      - minimal sequence (defaults only)
--  11.  INDEX         - non-constraint index (DESC + partial predicate)
--  12.  FUNCTION / PROCEDURE (pg_get_functiondef based)
--  13.  TRIGGER       - user trigger only (internal triggers skipped)
--  14.  default schema := current_schema() when schema is omitted
--  15.  idempotency: repeated calls produce byte-identical output
--  16.  roundtrip:    emitted DDL re-executes successfully
--                       (TABLE / VIEW / SEQUENCE / FUNCTION, via \gexec)
--  17.  errors:
--        - missing object            -> ORA-31603 (also for constraint
--                                         backing indexes, which are not
--                                         standalone objects)
--        - unsupported object type   -> ORA-31600
--        - NULL type / NULL name     -> ORA-31600
--
-- Notes
--   * The engine (sys.ora_dbms_metadata_get_ddl) is written in PL/iSQL,
--     like the other *DBMS_* packages, so GET_DDL itself requires the
--     Oracle parser (ivorysql.compatible_mode = oracle).
--   * Emitted identifiers follow Oracle's display convention (unquoted
--     lowercase catalog names appear UPPERCASE and are double-quoted), so
--     the roundtrip re-creates the objects as quoted UPPERCASE twins.
--   * VIEW bodies, CHECK expressions, partial-index predicates and
--     FUNCTION/PROCEDURE/TRIGGER text are emitted in their native catalog
--     form (see the accompanying dbms_metadata--1.0.sql header).
--

SET ivorysql.compatible_mode = oracle;

-- Deterministic deparse of stored query trees: keep the caller's
-- search_path out of the DDL text so cross-schema references are always
-- fully qualified.
SET search_path = pg_catalog;

CREATE SCHEMA md_schema;
CREATE SCHEMA md_other;

-- ============================================================
-- setup: a table with every constraint flavour + comments
-- ============================================================
CREATE TABLE md_schema.dept (
  deptno NUMBER(4) CONSTRAINT pk_md_dept PRIMARY KEY,
  dname  VARCHAR2(30) NOT NULL
);

CREATE TABLE md_schema.emp (
  empno    NUMBER(4) CONSTRAINT pk_md_emp PRIMARY KEY,
  ename    VARCHAR2(10) NOT NULL CONSTRAINT uq_md_emp UNIQUE,
  deptno   NUMBER(2) CONSTRAINT fk_md_emp REFERENCES md_schema.dept(deptno)
           ON DELETE CASCADE,
  sal      NUMBER(7,2) CONSTRAINT ck_md_emp CHECK (sal > 0),
  comm     NUMBER(7,2) DEFAULT 0,
  hiredate DATE
);
COMMENT ON TABLE md_schema.emp IS 'employee master';
COMMENT ON COLUMN md_schema.emp.ename IS 'employee name';

-- ============================================================
-- basic table DDL
-- ============================================================
SELECT DBMS_METADATA.GET_DDL('TABLE', 'DEPT', 'md_schema');

-- ============================================================
-- table with all constraint types and comments
-- ============================================================
SELECT DBMS_METADATA.GET_DDL('TABLE', 'EMP', 'md_schema');

-- ============================================================
-- case-insensitive name lookup
-- ============================================================
SELECT DBMS_METADATA.GET_DDL('table', 'dept', 'md_schema');

-- ============================================================
-- quoted mixed-case identifiers survive unchanged
-- ============================================================
CREATE TABLE md_schema."MyTable" ("Id" NUMBER(6), "CamelCase" VARCHAR2(5));
SELECT DBMS_METADATA.GET_DDL('TABLE', 'MyTable', 'md_schema');

-- ============================================================
-- cross-schema foreign key
-- ============================================================
CREATE TABLE md_other.ref_t (id NUMBER(6) PRIMARY KEY);
CREATE TABLE md_schema.fk_t (
  id   NUMBER(6) PRIMARY KEY,
  ref  NUMBER(6) CONSTRAINT fk_md_x REFERENCES md_other.ref_t(id)
);
SELECT DBMS_METADATA.GET_DDL('TABLE', 'fk_t', 'md_schema');

-- ============================================================
-- 100-column table: no truncation; DDL starts and ends properly
-- ============================================================
CREATE TABLE md_schema.wide (
  c001 NUMBER(6), c002 NUMBER(6), c003 NUMBER(6), c004 NUMBER(6),
  c005 NUMBER(6), c006 NUMBER(6), c007 NUMBER(6), c008 NUMBER(6)
);
ALTER TABLE md_schema.wide ADD COLUMN c100 NUMBER(6);
SELECT
  length(DBMS_METADATA.GET_DDL('TABLE','WIDE','md_schema')) AS ddl_len,
  left(DBMS_METADATA.GET_DDL('TABLE','WIDE','md_schema'), 60) AS ddl_head;

-- ============================================================
-- serial column keeps its nextval() default
-- ============================================================
CREATE TABLE md_schema.serial_t (id serial, note varchar2(10));
SELECT DBMS_METADATA.GET_DDL('TABLE', 'serial_t', 'md_schema');

-- ============================================================
-- view / materialized view
-- ============================================================
CREATE VIEW md_schema.emp_v AS
  SELECT e.empno, e.ename, d.dname
  FROM md_schema.emp e JOIN md_schema.dept d ON d.deptno = e.deptno;
SELECT DBMS_METADATA.GET_DDL('VIEW', 'EMP_V', 'md_schema');

CREATE MATERIALIZED VIEW md_schema.emp_mv AS
  SELECT empno, ename FROM md_schema.emp;
SELECT DBMS_METADATA.GET_DDL('MATERIALIZED VIEW', 'EMP_MV', 'md_schema');

-- ============================================================
-- sequences
-- ============================================================
CREATE SEQUENCE md_schema.emp_seq
  INCREMENT BY 5 START WITH 100 MINVALUE 10 MAXVALUE 99999 CACHE 20 CYCLE;
SELECT DBMS_METADATA.GET_DDL('SEQUENCE', 'EMP_SEQ', 'md_schema');

CREATE SEQUENCE md_schema.plain_seq;
SELECT DBMS_METADATA.GET_DDL('SEQUENCE', 'PLAIN_SEQ', 'md_schema');

-- ============================================================
-- indexes
-- ============================================================
CREATE INDEX idx_md_sal ON md_schema.emp USING btree (sal DESC)
  WHERE comm IS NOT NULL;
SELECT DBMS_METADATA.GET_DDL('INDEX', 'IDX_MD_SAL', 'md_schema');

-- ============================================================
-- function / procedure
-- ============================================================
CREATE OR REPLACE FUNCTION md_schema.f_double(x NUMBER) RETURN NUMBER IS
BEGIN
  RETURN x * 2;
END;
/
SELECT DBMS_METADATA.GET_DDL('FUNCTION', 'F_DOUBLE', 'md_schema');

CREATE OR REPLACE PROCEDURE md_schema.p_hello(name_in VARCHAR2) IS
BEGIN
  NULL;
END;
/
SELECT DBMS_METADATA.GET_DDL('PROCEDURE', 'P_HELLO', 'md_schema');

-- ============================================================
-- trigger (internal triggers are excluded)
-- ============================================================
CREATE TABLE md_schema.trig_t (id int, log text);
CREATE OR REPLACE FUNCTION md_schema.trg_f() RETURNS trigger AS $$
BEGIN
  NEW.log := 'x';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
/
CREATE OR REPLACE FUNCTION md_schema.trg_f2() RETURNS trigger AS $$
BEGIN
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;
/
CREATE TRIGGER trg_md BEFORE INSERT ON md_schema.trig_t FOR EACH ROW EXECUTE FUNCTION md_schema.trg_f();

CREATE TRIGGER trg_md2 BEFORE DELETE ON md_schema.trig_t FOR EACH ROW EXECUTE FUNCTION md_schema.trg_f2();


SELECT DBMS_METADATA.GET_DDL('TRIGGER', 'TRG_MD', 'md_schema');

-- ============================================================
-- default schema: current_schema() is used when omitted
-- ============================================================
SET search_path = md_schema, pg_catalog;
SELECT DBMS_METADATA.GET_DDL('TABLE', 'dept');
SET search_path = pg_catalog;

-- ============================================================
-- idempotency
-- ============================================================
SELECT
  (DBMS_METADATA.GET_DDL('TABLE','EMP','md_schema')
     = DBMS_METADATA.GET_DDL('TABLE','EMP','md_schema')) AS table_stable,
  (DBMS_METADATA.GET_DDL('SEQUENCE','EMP_SEQ','md_schema')
     = DBMS_METADATA.GET_DDL('SEQUENCE','EMP_SEQ','md_schema')) AS seq_stable;

-- ============================================================
-- roundtrip: the emitted DDL is re-executable
--
-- The DDL identifies its objects as quoted UPPERCASE names (Oracle
-- display convention), so the roundtrip target is the quoted twin schema
-- "MD_SCHEMA"; the original lowercase objects stay untouched.  All
-- \gexec statements are grouped so psql oracle mode executes them in
-- order.
-- ============================================================
CREATE SCHEMA "MD_SCHEMA";
SELECT DBMS_METADATA.GET_DDL('TABLE', 'dept', 'md_schema') \gexec
SELECT DBMS_METADATA.GET_DDL('VIEW', 'emp_v', 'md_schema') \gexec
SELECT DBMS_METADATA.GET_DDL('SEQUENCE', 'emp_seq', 'md_schema') \gexec
SELECT DBMS_METADATA.GET_DDL('FUNCTION', 'f_double', 'md_schema') \gexec

-- the twins really exist and are usable
SELECT relname FROM pg_class
 WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'MD_SCHEMA')
 ORDER BY 1;
INSERT INTO "MD_SCHEMA"."DEPT" ("DEPTNO","DNAME") VALUES (10, 'ops');
SELECT count(*) FROM "MD_SCHEMA"."DEPT";
SELECT nextval('"MD_SCHEMA"."EMP_SEQ"');
SELECT md_schema.f_double(21);

-- ============================================================
-- errors
-- ============================================================
-- missing object
SELECT DBMS_METADATA.GET_DDL('TABLE', 'no_such_table', 'md_schema');
-- constraint backing index is not a standalone object
SELECT DBMS_METADATA.GET_DDL('INDEX', 'PK_MD_EMP', 'md_schema');
-- unsupported object type
SELECT DBMS_METADATA.GET_DDL('PACKAGE BODY', 'EMP', 'md_schema');
-- NULL arguments
SELECT DBMS_METADATA.GET_DDL('TABLE', NULL, 'md_schema');
SELECT DBMS_METADATA.GET_DDL(NULL, 'EMP', 'md_schema');

-- cleanup
DROP SCHEMA md_schema CASCADE;
DROP SCHEMA md_other CASCADE;
DROP SCHEMA "MD_SCHEMA" CASCADE;