--
-- ORA_KEYWORDS_PG
-- Test that Oracle-specific keywords have no special meaning in PostgreSQL mode.
-- In PostgreSQL mode, these should be treated as regular identifiers.
--
-- This test verifies that IvorySQL's Oracle-specific functionality
-- (ROWNUM, ROWID, etc.) does not leak into PostgreSQL mode.
--

-- Test 1: rownum as column name
CREATE TABLE rownum_test (
    id int,
    rownum int,  -- rownum is just a regular column name
    name text
);

INSERT INTO rownum_test VALUES (1, 100, 'Alice');
INSERT INTO rownum_test VALUES (2, 200, 'Bob');
INSERT INTO rownum_test VALUES (3, 300, 'Charlie');

SELECT id, rownum, name FROM rownum_test ORDER BY id;

-- Test 2: rownum as column alias (without AS)
SELECT id, name rownum FROM rownum_test ORDER BY id;

-- Test 3: rownum as column alias (with AS)
SELECT id, name AS rownum FROM rownum_test ORDER BY id;

-- Test 4: rownum as table alias
SELECT r.id, r.rownum, r.name FROM rownum_test rownum, rownum_test r WHERE rownum.id = r.id ORDER BY r.id;

-- Test 5: rownum as subquery alias
SELECT sub.id, sub.rownum FROM (SELECT * FROM rownum_test) rownum, (SELECT * FROM rownum_test) sub WHERE rownum.id = sub.id ORDER BY sub.id;

-- Test 6: Verify rownum column contains actual data, not row numbers
SELECT id, rownum FROM rownum_test WHERE rownum > 150 ORDER BY id;

-- Test 7: rownum in expressions (should use column value, not row number)
SELECT id, rownum, rownum * 2 AS doubled FROM rownum_test ORDER BY id;

-- Test 8: rownum as function parameter name (PL/pgSQL)
CREATE OR REPLACE FUNCTION test_rownum_param(rownum int) RETURNS int AS $$
BEGIN
    RETURN rownum * 10;
END;
$$ LANGUAGE plpgsql;

SELECT test_rownum_param(5);
SELECT test_rownum_param(rownum) FROM rownum_test ORDER BY id;

-- Test 9: rownum as variable in PL/pgSQL
DO $$
DECLARE
    rownum int := 42;
BEGIN
    RAISE NOTICE 'rownum variable value: %', rownum;
END;
$$;

-- Test 10: rownum in CTE
WITH rownum AS (
    SELECT id, name FROM rownum_test WHERE id <= 2
)
SELECT * FROM rownum ORDER BY id;

-- Test 11: ROWID as column name (also should have no special meaning)
CREATE TABLE rowid_test (
    rowid int,
    data text
);

INSERT INTO rowid_test VALUES (1, 'first');
INSERT INTO rowid_test VALUES (2, 'second');

SELECT rowid, data FROM rowid_test ORDER BY rowid;

-- Test 12: rowid as alias
SELECT data rowid FROM rowid_test ORDER BY rowid;

-- Cleanup
DROP FUNCTION test_rownum_param(int);
DROP TABLE rownum_test;
DROP TABLE rowid_test;
