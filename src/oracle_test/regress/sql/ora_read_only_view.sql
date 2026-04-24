--
-- Tests for WITH READ ONLY views (Oracle compatibility)
--

CREATE TABLE t_ro (a int, b text);
INSERT INTO t_ro VALUES (1, 'hello'), (2, 'world');

-- 1. Basic WITH READ ONLY view: SELECT succeeds, DML fails
CREATE VIEW ro_view AS SELECT * FROM t_ro WITH READ ONLY;
SELECT * FROM ro_view ORDER BY a;

INSERT INTO ro_view VALUES (3, 'fail');
UPDATE ro_view SET b = 'fail' WHERE a = 1;
DELETE FROM ro_view WHERE a = 1;

-- 2. CREATE OR REPLACE behaviour across the read-only boundary
-- 2a. Column-compatible replace WITH READ ONLY: DML is still blocked
CREATE OR REPLACE VIEW ro_view AS SELECT a, b FROM t_ro WITH READ ONLY;
INSERT INTO ro_view VALUES (3, 'fail');

-- 2b. Replacing WITHOUT WITH READ ONLY clears read_only reloption: view becomes writable
CREATE OR REPLACE VIEW ro_view AS SELECT a, b FROM t_ro;
INSERT INTO ro_view VALUES (3, 'now_writable');
SELECT * FROM ro_view ORDER BY a;
DELETE FROM t_ro WHERE a = 3;

-- Restore ro_view as read-only for subsequent tests
CREATE OR REPLACE VIEW ro_view AS SELECT a, b FROM t_ro WITH READ ONLY;

-- 3. Plain view (no WITH READ ONLY) remains updatable
CREATE VIEW writable_view AS SELECT * FROM t_ro;
INSERT INTO writable_view VALUES (3, 'ok');
SELECT * FROM writable_view ORDER BY a;

-- 4. WITH READ ONLY and WITH CHECK OPTION are mutually exclusive
CREATE VIEW bad_view AS SELECT * FROM t_ro WITH CHECK OPTION WITH READ ONLY;
CREATE VIEW bad_view AS SELECT * FROM t_ro WITH READ ONLY WITH CHECK OPTION;

-- 5. WITH READ ONLY on RECURSIVE VIEW is allowed
CREATE RECURSIVE VIEW ro_recursive_view (a) AS
    SELECT 1
    UNION ALL
    SELECT a + 1 FROM ro_recursive_view WHERE a < 3
WITH READ ONLY;
SELECT * FROM ro_recursive_view ORDER BY a;
INSERT INTO ro_recursive_view VALUES (99);

-- 6. FORCE VIEW with WITH READ ONLY
-- Create while base table does not yet exist
CREATE FORCE VIEW force_ro_view AS SELECT * FROM nonexistent_for_ro WITH READ ONLY;
-- Create the base table and compile the force view
CREATE TABLE nonexistent_for_ro (a int, b text);
ALTER VIEW force_ro_view COMPILE;
-- DML must be blocked after compilation
INSERT INTO force_ro_view VALUES (1, 'fail');

-- 7. Verify reloptions stores read_only (including force view)
SELECT relname, reloptions
FROM pg_class
WHERE relname IN ('ro_view', 'writable_view', 'ro_recursive_view', 'force_ro_view')
ORDER BY relname;

-- 8. MERGE with INSERT action against WITH READ ONLY view must fail
MERGE INTO ro_view USING (SELECT 4 AS a, 'merge_ins' AS b) AS src
ON (ro_view.a = src.a)
WHEN NOT MATCHED THEN INSERT VALUES (src.a, src.b);

-- 9. MERGE with UPDATE action against WITH READ ONLY view must fail
MERGE INTO ro_view USING (SELECT 1 AS a, 'merge_upd' AS b) AS src
ON (ro_view.a = src.a)
WHEN MATCHED THEN UPDATE SET b = src.b;

-- 10. MERGE with both UPDATE and INSERT against WITH READ ONLY view must fail
MERGE INTO ro_view USING (SELECT 1 AS a, 'test' AS b) AS src
ON (ro_view.a = src.a)
WHEN MATCHED THEN UPDATE SET b = src.b
WHEN NOT MATCHED THEN INSERT VALUES (src.a, src.b);

-- Cleanup
DROP VIEW IF EXISTS ro_view;
DROP VIEW IF EXISTS writable_view;
DROP VIEW IF EXISTS ro_recursive_view;
DROP VIEW IF EXISTS force_ro_view;
DROP TABLE IF EXISTS nonexistent_for_ro;
DROP TABLE t_ro;
