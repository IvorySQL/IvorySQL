--
-- Tests for auto-rebuild of dependent views on ALTER TABLE ... ALTER COLUMN TYPE
--

-- Setup
CREATE SCHEMA atvr;
SET search_path = atvr, public;

-- ===========================================================================
-- Test 1: Basic single view rebuild
-- ===========================================================================
CREATE TABLE t1 (a int, b text);
INSERT INTO t1 VALUES (1, 'hello'), (2, 'world');
CREATE VIEW v1 AS SELECT a, b FROM t1;

SELECT a, pg_typeof(a) FROM v1 ORDER BY a;

ALTER TABLE t1 ALTER COLUMN a TYPE bigint;

-- View should still exist and work, column type should be bigint now
SELECT a, pg_typeof(a) FROM v1 ORDER BY a;

-- Table column type changed
SELECT pg_typeof(a) FROM t1 LIMIT 1;

DROP VIEW v1;
DROP TABLE t1;

-- ===========================================================================
-- Test 2: View with expression on altered column
-- ===========================================================================
CREATE TABLE t2 (a int, b text);
INSERT INTO t2 VALUES (10, 'foo'), (20, 'bar');
CREATE VIEW v2 AS SELECT a * 2 AS double_a, b FROM t2;

SELECT double_a, pg_typeof(double_a) FROM v2 ORDER BY double_a;

ALTER TABLE t2 ALTER COLUMN a TYPE bigint;

SELECT double_a, pg_typeof(double_a) FROM v2 ORDER BY double_a;

DROP VIEW v2;
DROP TABLE t2;

-- ===========================================================================
-- Test 3: View with WHERE clause on altered column
-- ===========================================================================
CREATE TABLE t3 (a int, b text);
INSERT INTO t3 VALUES (1, 'a'), (2, 'b'), (3, 'c');
CREATE VIEW v3 AS SELECT a, b FROM t3 WHERE a > 1;

SELECT * FROM v3 ORDER BY a;

ALTER TABLE t3 ALTER COLUMN a TYPE bigint;

SELECT * FROM v3 ORDER BY a;

DROP VIEW v3;
DROP TABLE t3;

-- ===========================================================================
-- Test 4: View with GROUP BY and aggregates
-- ===========================================================================
CREATE TABLE t4 (a int, b text, c int);
INSERT INTO t4 VALUES (1, 'x', 10), (1, 'y', 20), (2, 'x', 30);
CREATE VIEW v4 AS SELECT a, sum(c) AS total FROM t4 GROUP BY a;

SELECT a, total, pg_typeof(a) FROM v4 ORDER BY a;

ALTER TABLE t4 ALTER COLUMN a TYPE bigint;

SELECT a, total, pg_typeof(a) FROM v4 ORDER BY a;

DROP VIEW v4;
DROP TABLE t4;

-- ===========================================================================
-- Test 5: Cascading views (v5b depends on v5a depends on t5)
-- ===========================================================================
CREATE TABLE t5 (a int, b text);
INSERT INTO t5 VALUES (1, 'alpha'), (2, 'beta');
CREATE VIEW v5a AS SELECT a, b FROM t5;
CREATE VIEW v5b AS SELECT a * 10 AS aa, b FROM v5a;

SELECT aa, pg_typeof(aa) FROM v5b ORDER BY aa;

ALTER TABLE t5 ALTER COLUMN a TYPE bigint;

-- Both views should be rebuilt
SELECT a, pg_typeof(a) FROM v5a ORDER BY a;
SELECT aa, pg_typeof(aa) FROM v5b ORDER BY aa;

DROP VIEW v5b;
DROP VIEW v5a;
DROP TABLE t5;

-- ===========================================================================
-- Test 6: Deep view chain (v6c -> v6b -> v6a -> t6)
-- ===========================================================================
CREATE TABLE t6 (a int, b text);
INSERT INTO t6 VALUES (5, 'deep');
CREATE VIEW v6a AS SELECT a, b FROM t6;
CREATE VIEW v6b AS SELECT a + 1 AS a1, b FROM v6a;
CREATE VIEW v6c AS SELECT a1 + 1 AS a2, b FROM v6b;

SELECT a2, pg_typeof(a2) FROM v6c;

ALTER TABLE t6 ALTER COLUMN a TYPE bigint;

SELECT a, pg_typeof(a) FROM v6a;
SELECT a1, pg_typeof(a1) FROM v6b;
SELECT a2, pg_typeof(a2) FROM v6c;

DROP VIEW v6c;
DROP VIEW v6b;
DROP VIEW v6a;
DROP TABLE t6;

-- ===========================================================================
-- Test 7: Multiple views on same table, all rebuilt
-- ===========================================================================
CREATE TABLE t7 (a int, b text, c float);
INSERT INTO t7 VALUES (1, 'one', 1.1), (2, 'two', 2.2);
CREATE VIEW v7a AS SELECT a, b FROM t7;
CREATE VIEW v7b AS SELECT a, c FROM t7;
CREATE VIEW v7c AS SELECT a, b, c FROM t7 WHERE a = 1;

SELECT pg_typeof(a) FROM v7a LIMIT 1;
SELECT pg_typeof(a) FROM v7b LIMIT 1;
SELECT pg_typeof(a) FROM v7c LIMIT 1;

ALTER TABLE t7 ALTER COLUMN a TYPE bigint;

SELECT pg_typeof(a) FROM v7a LIMIT 1;
SELECT pg_typeof(a) FROM v7b LIMIT 1;
SELECT pg_typeof(a) FROM v7c LIMIT 1;

-- All views still return correct data
SELECT * FROM v7a ORDER BY a;
SELECT * FROM v7b ORDER BY a;
SELECT * FROM v7c ORDER BY a;

DROP VIEW v7c;
DROP VIEW v7b;
DROP VIEW v7a;
DROP TABLE t7;

-- ===========================================================================
-- Test 8: security_barrier option preserved
-- ===========================================================================
CREATE TABLE t8 (a int, b text);
INSERT INTO t8 VALUES (1, 'secret'), (2, 'public');
CREATE VIEW v8 WITH (security_barrier = true) AS SELECT a, b FROM t8;

SELECT relname, reloptions FROM pg_class WHERE relname = 'v8';

ALTER TABLE t8 ALTER COLUMN a TYPE bigint;

-- security_barrier option preserved after rebuild
SELECT relname, reloptions FROM pg_class WHERE relname = 'v8';
SELECT a, pg_typeof(a) FROM v8 ORDER BY a;

DROP VIEW v8;
DROP TABLE t8;

-- ===========================================================================
-- Test 9: WITH LOCAL CHECK OPTION preserved
-- ===========================================================================
CREATE TABLE t9 (a int, b text);
INSERT INTO t9 VALUES (1, 'a'), (5, 'b');
CREATE VIEW v9 AS SELECT a, b FROM t9 WHERE a < 10 WITH LOCAL CHECK OPTION;

-- Verify check option is set (stored in reloptions)
SELECT relname, reloptions FROM pg_class WHERE relname = 'v9';

ALTER TABLE t9 ALTER COLUMN a TYPE bigint;

-- Check option should be preserved
SELECT relname, reloptions FROM pg_class WHERE relname = 'v9';

-- Insert should still be checked
INSERT INTO v9 VALUES (3, 'ok');
SELECT * FROM t9 ORDER BY a;
-- This should fail due to check option
INSERT INTO v9 VALUES (20, 'fail');

DROP VIEW v9;
DROP TABLE t9;

-- ===========================================================================
-- Test 10: WITH CASCADED CHECK OPTION preserved
-- ===========================================================================
CREATE TABLE t10 (a int, b text);
INSERT INTO t10 VALUES (1, 'a');
CREATE VIEW v10 AS SELECT a, b FROM t10 WHERE a < 100 WITH CASCADED CHECK OPTION;

SELECT relname, reloptions FROM pg_class WHERE relname = 'v10';

ALTER TABLE t10 ALTER COLUMN a TYPE bigint;

SELECT relname, reloptions FROM pg_class WHERE relname = 'v10';

DROP VIEW v10;
DROP TABLE t10;

-- ===========================================================================
-- Test 11: USING clause with view rebuild
-- ===========================================================================
CREATE TABLE t11 (a text, b int);
INSERT INTO t11 VALUES ('10', 1), ('20', 2);
CREATE VIEW v11 AS SELECT a, b FROM t11;

SELECT a, pg_typeof(a) FROM v11 ORDER BY b;

ALTER TABLE t11 ALTER COLUMN a TYPE int USING a::int;

SELECT a, pg_typeof(a) FROM v11 ORDER BY a;

DROP VIEW v11;
DROP TABLE t11;

-- ===========================================================================
-- Test 12: Failure case - view uses operator not defined for new type
-- ALTER TABLE should roll back, original types preserved
-- ===========================================================================
CREATE TABLE t12 (a int, b text);
INSERT INTO t12 VALUES (1, 'test'), (2, 'data');
CREATE VIEW v12 AS SELECT a + 1 AS ap1 FROM t12;  -- + not defined for bool

SELECT a, pg_typeof(a) FROM t12;
SELECT ap1, pg_typeof(ap1) FROM v12 ORDER BY ap1;

-- This should fail: int + 1 cannot be re-expressed as bool + 1
ALTER TABLE t12 ALTER COLUMN a TYPE bool USING (a > 0);

-- Table and view should be unchanged (rolled back)
SELECT a, pg_typeof(a) FROM t12 ORDER BY a;
SELECT ap1, pg_typeof(ap1) FROM v12 ORDER BY ap1;

DROP VIEW v12;
DROP TABLE t12;

-- ===========================================================================
-- Test 13: Non-view rule still errors (original behavior preserved)
-- ===========================================================================
CREATE TABLE t13 (a int, b text);
CREATE TABLE t13_log (a int, b text);
CREATE RULE t13_insert_rule AS ON INSERT TO t13
    DO ALSO INSERT INTO t13_log VALUES (NEW.a, NEW.b);

-- Should still error: non-view rule depends on column a
ALTER TABLE t13 ALTER COLUMN a TYPE bigint;

DROP RULE t13_insert_rule ON t13;
DROP TABLE t13_log;
DROP TABLE t13;

-- ===========================================================================
-- Test 14: ALTER multiple columns in single statement, views rebuilt once
-- ===========================================================================
CREATE TABLE t14 (a int, b int, c text);
INSERT INTO t14 VALUES (1, 10, 'x'), (2, 20, 'y');
CREATE VIEW v14 AS SELECT a, b, c FROM t14;

SELECT a, pg_typeof(a), b, pg_typeof(b) FROM v14 ORDER BY a;

ALTER TABLE t14 ALTER COLUMN a TYPE bigint, ALTER COLUMN b TYPE bigint;

SELECT a, pg_typeof(a), b, pg_typeof(b) FROM v14 ORDER BY a;

DROP VIEW v14;
DROP TABLE t14;

-- ===========================================================================
-- Test 15: View not referencing altered column - should still work
-- (view depends on relation, not column, via different rules)
-- ===========================================================================
CREATE TABLE t15 (a int, b text, c int);
INSERT INTO t15 VALUES (1, 'hello', 100);
CREATE VIEW v15 AS SELECT b, c FROM t15;  -- does not use column a

SELECT * FROM v15;

ALTER TABLE t15 ALTER COLUMN a TYPE bigint;

-- View on non-altered columns is unaffected
SELECT * FROM v15;

DROP VIEW v15;
DROP TABLE t15;

-- ===========================================================================
-- Test 16: View in non-default schema
-- ===========================================================================
CREATE SCHEMA atvr2;
CREATE TABLE atvr.t16 (a int, b text);
INSERT INTO atvr.t16 VALUES (1, 'one'), (2, 'two');
CREATE VIEW atvr2.v16 AS SELECT a, b FROM atvr.t16;

SELECT a, pg_typeof(a) FROM atvr2.v16 ORDER BY a;

ALTER TABLE atvr.t16 ALTER COLUMN a TYPE bigint;

SELECT a, pg_typeof(a) FROM atvr2.v16 ORDER BY a;

DROP VIEW atvr2.v16;
DROP TABLE atvr.t16;
DROP SCHEMA atvr2;

-- ===========================================================================
-- Cleanup
-- ===========================================================================
SET search_path = public;
DROP SCHEMA atvr CASCADE;
