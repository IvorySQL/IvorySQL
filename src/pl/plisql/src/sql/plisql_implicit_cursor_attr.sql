--
-- Tests for PL/iSQL implicit SQL cursor attributes:
-- SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND and SQL%ISOPEN
--

CREATE TABLE implicit_cursor_test (id INT, name TEXT);

-- Before any implicit-cursor statement, %ROWCOUNT/%FOUND/%NOTFOUND are
-- NULL (Oracle semantics), while %ISOPEN is always false
DO $$
DECLARE
    v_rowcount BIGINT;
    v_found    BOOLEAN;
    v_notfound BOOLEAN;
    v_isopen   BOOLEAN;
    v_init     BIGINT := SQL%ROWCOUNT;  -- also NULL in DECLARE initializer
BEGIN
    RAISE NOTICE 'vars: % % % %', v_rowcount, v_found, v_notfound, v_isopen;
    RAISE NOTICE 'direct: % % % %',
        SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND, SQL%ISOPEN;
    RAISE NOTICE 'isopen=%', SQL%ISOPEN;
    RAISE NOTICE 'initializer=%', v_init;
END;
$$;

-- Each invocation starts over with the NULL state
CREATE FUNCTION implicit_cursor_attr_fresh() RETURNS void AS $$
BEGIN
    RAISE NOTICE 'fresh call: rowcount=%', SQL%ROWCOUNT;
    INSERT INTO implicit_cursor_test VALUES (1, 'one');
    RAISE NOTICE 'after insert: rowcount=% found=% notfound=%',
        SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND;
END;
$$ LANGUAGE plisql;
/

DO $$ BEGIN PERFORM implicit_cursor_attr_fresh(); END $$;
DO $$ BEGIN PERFORM implicit_cursor_attr_fresh(); END $$;

-- INSERT
DO $$
BEGIN
    INSERT INTO implicit_cursor_test VALUES (2, 'two');
    INSERT INTO implicit_cursor_test VALUES (3, 'three');
    RAISE NOTICE 'rowcount=% found=% notfound=%',
        SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND;
END;
$$;

-- UPDATE affecting several rows; attribute in an IF condition
DO $$
BEGIN
    UPDATE implicit_cursor_test SET name = name || '!' WHERE id <= 3;
    RAISE NOTICE 'after update: rowcount=%', SQL%ROWCOUNT;
    IF SQL%FOUND THEN
        RAISE NOTICE 'found is true';
    END IF;
    IF SQL%NOTFOUND THEN
        RAISE NOTICE 'notfound is true';
    ELSE
        RAISE NOTICE 'notfound is false';
    END IF;
END;
$$;

-- UPDATE affecting no rows
DO $$
BEGIN
    UPDATE implicit_cursor_test SET name = 'x' WHERE id > 999;
    RAISE NOTICE 'zero-row update: rowcount=% found=% notfound=%',
        SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND;
END;
$$;

-- DELETE affecting no rows
DO $$
BEGIN
    DELETE FROM implicit_cursor_test WHERE id > 999;
    RAISE NOTICE 'zero-row delete: rowcount=% found=% notfound=% isopen=%',
        SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND, SQL%ISOPEN;
END;
$$;

-- SELECT INTO hitting one row and no rows
DO $$
DECLARE
    v TEXT;
BEGIN
    SELECT name INTO v FROM implicit_cursor_test WHERE id = 1;
    RAISE NOTICE 'select into: v=% rowcount=% found=% notfound=%',
        v, SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND;

    SELECT name INTO v FROM implicit_cursor_test WHERE id > 999;
    RAISE NOTICE 'empty select into: v=% rowcount=% notfound=%',
        v, SQL%ROWCOUNT, SQL%NOTFOUND;
END;
$$;

-- SELECT INTO STRICT with no rows: the attributes must reflect the
-- failed statement inside the exception handler (NO_DATA_FOUND)
DO $$
DECLARE
    v TEXT;
BEGIN
    DELETE FROM implicit_cursor_test WHERE id = 42;
    RAISE NOTICE 'before strict: rowcount=% notfound=%',
        SQL%ROWCOUNT, SQL%NOTFOUND;
    BEGIN
        SELECT name INTO STRICT v FROM implicit_cursor_test WHERE id > 999;
        RAISE NOTICE 'unexpected: no exception';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE NOTICE 'in handler: rowcount=% found=% notfound=%',
                SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND;
    END;
    RAISE NOTICE 'after handler: rowcount=% notfound=%',
        SQL%ROWCOUNT, SQL%NOTFOUND;
END;
$$;

-- SELECT SQL%ROWCOUNT INTO a variable
DO $$
DECLARE
    v BIGINT;
BEGIN
    DELETE FROM implicit_cursor_test;
    SELECT SQL%ROWCOUNT INTO v;
    RAISE NOTICE 'deleted % rows', v;
END;
$$;

-- Attributes after INSERT ... RETURNING
DO $$
DECLARE
    v INT;
BEGIN
    INSERT INTO implicit_cursor_test VALUES (10, 'ten') RETURNING id INTO v;
    RAISE NOTICE 'returning: id=% rowcount=% found=%', v, SQL%ROWCOUNT, SQL%FOUND;
END;
$$;

-- Attributes inside expressions: CASE, arithmetic, boolean operators
DO $$
DECLARE
    v TEXT;
BEGIN
    INSERT INTO implicit_cursor_test VALUES (11, 'eleven');
    v := CASE WHEN SQL%FOUND THEN 'rows inserted' ELSE 'nothing' END;
    RAISE NOTICE '%', v;
    RAISE NOTICE 'double: %', SQL%ROWCOUNT + SQL%ROWCOUNT;
    RAISE NOTICE 'not found: %', NOT SQL%FOUND;
END;
$$;

-- Attribute names are matched case-insensitively and tolerate whitespace
DO $$
BEGIN
    UPDATE implicit_cursor_test SET name = name WHERE id = 10;
    RAISE NOTICE 'mixed case: %', SQL%RowCouNt;
    RAISE NOTICE 'spaced: %', SQL % ROWCOUNT;
    RAISE NOTICE 'spaced found: %', sql % found;
END;
$$;

-- EXIT WHEN with SQL%NOTFOUND
DO $$
DECLARE
    r RECORD;
    n INT := 0;
BEGIN
    FOR r IN SELECT id FROM implicit_cursor_test ORDER BY id LOOP
        n := n + 1;
        DELETE FROM implicit_cursor_test WHERE id = r.id;
        EXIT WHEN SQL%NOTFOUND;
    END LOOP;
    RAISE NOTICE 'looped % times', n;
    RAISE NOTICE 'final rowcount=%', SQL%ROWCOUNT;
END;
$$;

-- MERGE updates the attributes
DO $$
BEGIN
    MERGE INTO implicit_cursor_test t
    USING (SELECT 10 AS id, 'ten again' AS name) s
    ON (t.id = s.id)
    WHEN MATCHED THEN UPDATE SET name = s.name
    WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.name);
    RAISE NOTICE 'after merge: rowcount=% found=% notfound=%',
        SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND;
END;
$$;

-- Dynamic SQL updates the attributes as well
DO $$
DECLARE
    v BIGINT;
BEGIN
    EXECUTE 'DELETE FROM implicit_cursor_test';
    v := SQL%ROWCOUNT;
    RAISE NOTICE 'dynamic delete: %', v;
END;
$$;

-- A cursor FOR loop is an explicit cursor and leaves the attributes alone
DO $$
DECLARE
    r RECORD;
BEGIN
    INSERT INTO implicit_cursor_test VALUES (1, 'one');
    RAISE NOTICE 'after insert: rowcount=%', SQL%ROWCOUNT;
    FOR r IN SELECT id FROM implicit_cursor_test ORDER BY id LOOP
        NULL;
    END LOOP;
    RAISE NOTICE 'after for loop: rowcount=%', SQL%ROWCOUNT;
    SELECT count(*) INTO r.id FROM implicit_cursor_test;
    RAISE NOTICE 'after select into: rowcount=%', SQL%ROWCOUNT;
END;
$$;

-- Attributes in stored functions and procedures
CREATE FUNCTION implicit_cursor_attr_count() RETURNS BIGINT AS $$
BEGIN
    INSERT INTO implicit_cursor_test SELECT id + 100, name
        FROM implicit_cursor_test;
    RETURN SQL%ROWCOUNT;
END;
$$ LANGUAGE plisql;
/

DO $$
DECLARE
    n BIGINT;
BEGIN
    n := implicit_cursor_attr_count();
    RAISE NOTICE 'attr_count returned %', n;
END;
$$;

-- Attributes seen from an outer block after DML in an inner block
DO $$
BEGIN
    BEGIN
        UPDATE implicit_cursor_test SET name = name;
        RAISE NOTICE 'inner: rowcount=%', SQL%ROWCOUNT;
    END;
    RAISE NOTICE 'outer: rowcount=%', SQL%ROWCOUNT;
END;
$$;

-- Regression: %TYPE and %ROWTYPE declarations keep working
DO $$
DECLARE
    v_id implicit_cursor_test.id%TYPE;
    v_row implicit_cursor_test%ROWTYPE;
    v_id2 v_id%TYPE;
BEGIN
    v_id := 1;
    RAISE NOTICE 'type ok: v_id=%, v_id2 is null: %', v_id, v_id2 IS NULL;
END;
$$;

-- Regression: '%' still works as the modulo operator, and variables may
-- still be named like an attribute or like the implicit cursor
DO $$
DECLARE
    total    INT := 10;
    divisor  INT := 3;
    rest     INT;
    rowcount INT := 7;
    sql      INT := 5;
BEGIN
    rest := total % divisor;
    RAISE NOTICE '10 %% 3 = %', rest;
    rest := rowcount % 2;
    RAISE NOTICE 'rowcount %% 2 = %', rest;
    rest := sql + 1;
    RAISE NOTICE 'sql + 1 = %', rest;
    rest := SQL % 3;
    RAISE NOTICE 'sql %% 3 = %', rest;
END;
$$;

-- SQL%<attribute> keeps its meaning even when local variables named "sql"
-- and "rowcount" are in scope: it always denotes the implicit cursor
-- attribute, never the modulo of the two variables.  This mirrors Oracle and
-- matches how ROWNUM is handled here.  The declared values are chosen so
-- that the two readings differ: modulo would give 5 % 3 = 2, while the
-- attribute is the row count of the statement above, which is 1.
DO $$
DECLARE
    sql      INT := 5;
    rowcount INT := 3;
    x        INT;
BEGIN
    INSERT INTO implicit_cursor_test VALUES (20, 'precedence');
    x := sql % rowcount;
    RAISE NOTICE 'precedence: x=% (attribute 1, modulo 2)', x;
END;
$$;

--
-- Package routines: the implicit SQL cursor attributes are per-call state.
-- A package routine executes against the package's shared datum array, so
-- without an explicit reset a repeated or recursive call would observe the
-- values left behind by the previous one before running a statement of its
-- own.
--
CREATE OR REPLACE PACKAGE pkg_sql_attr AS
    PROCEDURE do_dml;
    FUNCTION  nested_rowcount(n INT) RETURN BIGINT;
    PROCEDURE other_dml;
END pkg_sql_attr;
/

CREATE OR REPLACE PACKAGE BODY pkg_sql_attr AS
    PROCEDURE do_dml IS
        v BIGINT;
    BEGIN
        RAISE NOTICE 'p1 entry: rowcount=% found=% notfound=% isopen=%',
            SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND, SQL%ISOPEN;
        INSERT INTO implicit_cursor_test VALUES (30, 'p1');
        v := SQL%ROWCOUNT;
        RAISE NOTICE 'p1 after insert: %', v;
    END;

    FUNCTION nested_rowcount(n INT) RETURN BIGINT IS
    BEGIN
        RAISE NOTICE 'nested entry(%): rowcount=%', n, SQL%ROWCOUNT;
        IF n = 0 THEN
            INSERT INTO implicit_cursor_test VALUES (40, 'outer');
            RAISE NOTICE 'outer after insert: rowcount=%', SQL%ROWCOUNT;
            PERFORM pkg_sql_attr.nested_rowcount(1);
            RAISE NOTICE 'outer after nested call: rowcount=%', SQL%ROWCOUNT;
            RETURN SQL%ROWCOUNT;
        ELSE
            UPDATE implicit_cursor_test SET name = name || '*' WHERE id <= 4;
            RAISE NOTICE 'inner after update: rowcount=%', SQL%ROWCOUNT;
            RETURN 0;
        END IF;
    END;

    PROCEDURE other_dml IS
    BEGIN
        RAISE NOTICE 'p2 entry: rowcount=% found=% notfound=%',
            SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND;
        DELETE FROM implicit_cursor_test WHERE id > 900;
        RAISE NOTICE 'p2 after delete: rowcount=% notfound=%',
            SQL%ROWCOUNT, SQL%NOTFOUND;
    END;
END pkg_sql_attr;
/

-- Start from a known state: ids 1..4 exist and are the only rows.
DELETE FROM implicit_cursor_test;
INSERT INTO implicit_cursor_test VALUES (1, 'a'), (2, 'b'), (3, 'c'), (4, 'd');

-- A second call to the same routine starts over from the NULL state, and a
-- different routine of the same package never sees the first one's values.
DO $$
BEGIN
    pkg_sql_attr.do_dml();
    pkg_sql_attr.do_dml();
    pkg_sql_attr.other_dml();
END;
$$;

-- Recursion: the nested call must not leak its own row count into the
-- caller, which still holds the count of its own INSERT.
DO $$
DECLARE
    n BIGINT;
BEGIN
    n := pkg_sql_attr.nested_rowcount(0);
    RAISE NOTICE 'nested_rowcount returned %', n;
END;
$$;

--
-- A subprocedure shares its parent's datum numbering, so the hidden
-- attribute variables have to be inherited along with FOUND: a subproc that
-- runs a statement must not write them into the wrong slot of its parent's
-- variables (which would corrupt FOUND, or the first argument).
--
CREATE FUNCTION subproc_attr_parent(p_text TEXT) RETURNS TEXT AS $$
DECLARE
    v_rowcount BIGINT;
    PROCEDURE inner_insert IS
    BEGIN
        INSERT INTO implicit_cursor_test VALUES (50, 'inner');
        RAISE NOTICE 'subproc inner: rowcount=%', SQL%ROWCOUNT;
    END;
BEGIN
    RAISE NOTICE 'parent entry: p_text=%, rowcount=%', p_text, SQL%ROWCOUNT;
    inner_insert();
    v_rowcount := SQL%ROWCOUNT;
    RAISE NOTICE 'parent after subproc: p_text=%, rowcount=%', p_text,
        v_rowcount;
    RETURN p_text;
END;
$$ LANGUAGE plisql;
/

DO $$
DECLARE
    r TEXT;
BEGIN
    r := subproc_attr_parent('intact');
    RAISE NOTICE 'subproc_attr_parent returned %', r;
END;
$$;

-- The same inside a package routine.
CREATE OR REPLACE PACKAGE pkg_subproc_attr AS
    FUNCTION do_it(p_text TEXT) RETURN TEXT;
END pkg_subproc_attr;
/

CREATE OR REPLACE PACKAGE BODY pkg_subproc_attr AS
    FUNCTION do_it(p_text TEXT) RETURN TEXT IS
        v_rowcount BIGINT;
        PROCEDURE inner_update IS
        BEGIN
            UPDATE implicit_cursor_test SET name = name WHERE id <= 4;
            RAISE NOTICE 'pkg subproc inner: rowcount=%', SQL%ROWCOUNT;
        END;
    BEGIN
        RAISE NOTICE 'pkg parent entry: rowcount=%', SQL%ROWCOUNT;
        inner_update();
        v_rowcount := SQL%ROWCOUNT;
        RAISE NOTICE 'pkg parent after subproc: p_text=%, rowcount=%',
            p_text, v_rowcount;
        RETURN p_text;
    END;
END pkg_subproc_attr;
/

DO $$
DECLARE
    r TEXT;
BEGIN
    r := pkg_subproc_attr.do_it('pkg intact');
    RAISE NOTICE 'pkg_subproc_attr.do_it returned %', r;
END;
$$;

DROP PACKAGE pkg_subproc_attr;
DROP PACKAGE pkg_sql_attr;
DROP FUNCTION subproc_attr_parent(TEXT);

-- SQL%ROWCOUNT is read-only
DO $$
BEGIN
    SQL%ROWCOUNT := 5;
END;
$$;

-- Unsupported attribute: SQL%BULK_ROWCOUNT is rejected cleanly
DO $$
DECLARE
    v BIGINT;
BEGIN
    v := SQL%BULK_ROWCOUNT(1);
END;
$$;
