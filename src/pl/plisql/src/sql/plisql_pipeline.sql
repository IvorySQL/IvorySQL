--
-- Tests for Oracle pipelined table functions (#1329): schema-level
-- nested-table collection types, PIPE ROW, TABLE() as a row source,
-- and the on-demand (streaming) execution contract.
--
-- Covers:
--   * CREATE TYPE ... AS TABLE OF <Typename> / IS TABLE OF
--   * RETURN <collection> PIPELINED functions with PIPE ROW(expr)
--   * SELECT ... FROM TABLE(f(...)) producing real ProjectSet plans
--   * non-pipelined collection-returning functions in TABLE()
--   * scalar and named-composite element types
--   * clean errors for out-of-scope syntax (0A000)
--

--
-- The #1329 example, end to end.
--
CREATE TYPE num_tab AS TABLE OF NUMBER;

CREATE OR REPLACE FUNCTION f_num_list(p_n NUMBER)
RETURN num_tab PIPELINED IS
BEGIN
  FOR i IN 1 .. p_n LOOP
    PIPE ROW(i);
  END LOOP;
  RETURN;
END;
/

SELECT column_value FROM TABLE(f_num_list(5)) ORDER BY column_value;

-- generation order must be preserved without ORDER BY (streaming proof:
-- a materializing implementation may still pass this, but a reordering
-- one cannot)
SELECT column_value FROM TABLE(f_num_list(4));

-- zero rows: empty collection, not an error
SELECT count(*) FROM TABLE(f_num_list(0));

SELECT column_value FROM TABLE(f_num_list(0));

-- NULL parameter: the loop bounds are NULL, so no rows are produced
SELECT count(*) FROM TABLE(f_num_list(NULL));

--
-- The same query twice in one statement must not share state between
-- the two invocations.
--
SELECT count(*) FROM TABLE(f_num_list(3)) a, TABLE(f_num_list(3)) b;

--
-- Nested loops and conditionals.
--
CREATE OR REPLACE FUNCTION f_grid(p_n NUMBER)
RETURN num_tab PIPELINED IS
BEGIN
  FOR i IN 1 .. p_n LOOP
    FOR j IN 1 .. i LOOP
      IF j = 2 THEN
        CONTINUE;
      END IF;
      PIPE ROW(i * 10 + j);
    END LOOP;
  END LOOP;
  RETURN;
END;
/

SELECT column_value FROM TABLE(f_grid(3));

--
-- EXIT with label, WHILE loop.
--
CREATE OR REPLACE FUNCTION f_exit_label(p_n NUMBER)
RETURN num_tab PIPELINED IS
BEGIN
  <<outer>>
  FOR i IN 1 .. p_n LOOP
    WHILE true LOOP
      PIPE ROW(i);
      EXIT outer WHEN i >= 3;
      EXIT;
    END LOOP;
  END LOOP;
  RETURN;
END;
/

SELECT column_value FROM TABLE(f_exit_label(5));

--
-- NULL elements: PIPE ROW(NULL) yields a SQL NULL element, not "no row".
--
CREATE OR REPLACE FUNCTION f_nulls(p_n NUMBER)
RETURN num_tab PIPELINED IS
BEGIN
  FOR i IN 1 .. p_n LOOP
    IF i = 2 THEN
      PIPE ROW(NULL);
    ELSE
      PIPE ROW(i);
    END IF;
  END LOOP;
  RETURN;
END;
/

SELECT column_value FROM TABLE(f_nulls(3));

--
-- Cursor FOR loop across yields.
--
CREATE TABLE pipeline_src (k NUMBER, v VARCHAR2(10));
--
-- Note: dual/connect-by support depends on Oracle mode DML; if unavailable
-- the inserts below are used instead.
--
TRUNCATE TABLE pipeline_src;
INSERT INTO pipeline_src VALUES (1, 'a');
INSERT INTO pipeline_src VALUES (2, 'b');
INSERT INTO pipeline_src VALUES (3, 'c');
INSERT INTO pipeline_src VALUES (4, 'd');

CREATE OR REPLACE FUNCTION f_cursor_for
RETURN num_tab PIPELINED IS
  total NUMBER := 0;
BEGIN
  FOR r IN (SELECT k FROM pipeline_src ORDER BY k) LOOP
    total := total + r.k;
    PIPE ROW(total);
  END LOOP;
  RETURN;
END;
/

SELECT column_value FROM TABLE(f_cursor_for());



--
-- Named composite element type: TABLE() expands the element fields.
--
CREATE TYPE pipeline_rec AS (a NUMBER, b VARCHAR2(10));

CREATE TYPE rec_tab AS TABLE OF pipeline_rec;

CREATE OR REPLACE FUNCTION f_recs(p_n NUMBER)
RETURN rec_tab PIPELINED IS
  r pipeline_rec;
BEGIN
  FOR i IN 1 .. p_n LOOP
    r.a := i;
    r.b := 'row ' || i;
    PIPE ROW(r);
  END LOOP;
  RETURN;
END;
/

SELECT * FROM TABLE(f_recs(3));

-- individual field qualification
SELECT t.a, t.b FROM TABLE(f_recs(2)) t ORDER BY t.a;

-- all-NULL fields
CREATE OR REPLACE FUNCTION f_recs_null
RETURN rec_tab PIPELINED IS
  r pipeline_rec;
BEGIN
  PIPE ROW(r);
  RETURN;
END;
/

SELECT * FROM TABLE(f_recs_null());

-- A PIPE ROW composite must match the declared element descriptor. A wider
-- value must raise an error instead of deforming into a smaller Datum array.
CREATE TYPE pipeline_wide_rec AS (a NUMBER, b VARCHAR2(10), c NUMBER);
CREATE OR REPLACE FUNCTION f_bad_rec
RETURN rec_tab PIPELINED IS
  r pipeline_wide_rec;
BEGIN
  r.a := 1;
  r.b := 'x';
  r.c := 2;
  PIPE ROW(r);
  RETURN;
END;
/
SELECT * FROM TABLE(f_bad_rec());

-- Composite TABLE() must also see preceding FROM items.
SELECT p.k, t.a FROM pipeline_src p, TABLE(f_recs(p.k)) t
WHERE p.k IN (1, 2) AND t.a = 1 ORDER BY p.k;

-- EXIT from nested query FOR loops must close both implicit portals.
CREATE OR REPLACE FUNCTION f_exit_cursors
RETURN num_tab PIPELINED IS
  open_cursors NUMBER;
BEGIN
  FOR r IN (SELECT k FROM pipeline_src) LOOP
    FOR s IN (SELECT k FROM pipeline_src) LOOP
      EXIT;
    END LOOP;
    EXIT;
  END LOOP;
  SELECT count(*) INTO open_cursors FROM pg_cursors;
  PIPE ROW(open_cursors);
  RETURN;
END;
/
SELECT column_value FROM TABLE(f_exit_cursors());
SELECT count(*) FROM pg_cursors;

-- Integer FOR bounds may reach int32's maximum without wrapping.
CREATE OR REPLACE FUNCTION f_max_loop
RETURN num_tab PIPELINED IS
BEGIN
  FOR i IN 2147483647 .. 2147483647 LOOP
    PIPE ROW(i);
  END LOOP;
  RETURN;
END;
/
SET statement_timeout = '2s';
SELECT column_value FROM TABLE(f_max_loop());
RESET statement_timeout;

-- FOUND reports whether a completed FOR loop ran at least once.
CREATE OR REPLACE FUNCTION f_loop_found
RETURN num_tab PIPELINED IS
BEGIN
  FOR i IN 1 .. 1 LOOP
    NULL;
  END LOOP;
  IF FOUND THEN
    PIPE ROW(1);
  ELSE
    PIPE ROW(0);
  END IF;
  RETURN;
END;
/
SELECT column_value FROM TABLE(f_loop_found());

--
-- Collection constructors.
--
SELECT num_tab(1, 2, 3);

-- empty collection differs from NULL collection
SELECT CASE WHEN num_tab() IS NULL THEN 'null' ELSE 'empty' END;
SELECT num_tab() IS NULL;

-- element coercion: strings converted to NUMBER per declared element type
SELECT num_tab('1', '2.5');

-- element too long / wrong type must fail cleanly
SELECT num_tab('abc');

-- nested-table type reference respects search_path
CREATE SCHEMA pipeline_schema;
CREATE TYPE pipeline_schema.limited_tab AS TABLE OF NUMBER(4,1);
SELECT pipeline_schema.limited_tab(1.5, 2.25);
SELECT pipeline_schema.limited_tab(12.34567);

--
-- Non-pipelined function returning a collection: TABLE() still expands
-- it (single evaluation, unnest semantics).
--
CREATE OR REPLACE FUNCTION f_materialized(p_n NUMBER)
RETURN num_tab IS
BEGIN
  -- collection methods (EXTEND etc.) are out of scope for #1329; build
  -- the collection with the constructor directly
  IF p_n = 4 THEN
    RETURN num_tab(1, 4, 9, 16);
  END IF;
  RETURN num_tab();
END;
/
SELECT column_value FROM TABLE(f_materialized(4));

--
-- Correlated (LATERAL) TABLE() calls.
--
SELECT p.k, c.column_value
FROM pipeline_src p,
     TABLE(f_num_list(p.k)) c
ORDER BY p.k, c.column_value;

--
-- Local variables must not leak between invocations: the running total
-- restarts for each call.
--
SELECT a.column_value, b.column_value
FROM TABLE(f_cursor_for()) a, TABLE(f_cursor_for()) b
WHERE a.column_value = 6 AND b.column_value = 6;

--
-- Streaming evidence: a sequence records PIPE ROW side effects. With
-- LIMIT 1, the function must not run to completion.
--
CREATE SEQUENCE pipeline_seq;

CREATE OR REPLACE FUNCTION f_counted(p_n NUMBER)
RETURN num_tab PIPELINED IS
BEGIN
  FOR i IN 1 .. p_n LOOP
    PERFORM nextval('pipeline_seq');
    PIPE ROW(i);
  END LOOP;
  PERFORM nextval('pipeline_seq');
  RETURN;
END;
/

SELECT setval('pipeline_seq', 1, false);
SELECT column_value FROM TABLE(f_counted(100)) LIMIT 1;
-- rows piped: 1 (one PERFORM before the first PIPE ROW); the tail
-- PERFORM must not have run
SELECT CASE WHEN currval('pipeline_seq') = 1 THEN 'on-demand' ELSE 'MATERIALIZED: ' || currval('pipeline_seq') END;

SELECT setval('pipeline_seq', 1, false);
SELECT count(*) FROM TABLE(f_counted(100));
-- 100 pre-PIPE increments + 1 tail increment
SELECT CASE WHEN currval('pipeline_seq') = 101 THEN 'full-run' ELSE 'unexpected: ' || currval('pipeline_seq') END;

--
-- Declaration-time checks (clean errors, no half-supported execution).
--
-- PIPELINED requires a collection return type
CREATE OR REPLACE FUNCTION f_bad_pipelined(p_n NUMBER)
RETURN NUMBER PIPELINED IS
BEGIN
  RETURN 1;

-- Oracle-mode deferred compilation: the DDL succeeds (prostatus
-- INVALID) and calling the function reports the error
SELECT f_bad_pipelined(1);
END;
/

-- PIPE ROW outside a pipelined function
CREATE OR REPLACE FUNCTION f_bad_pipe(p_n NUMBER)
RETURN num_tab IS
BEGIN
  PIPE ROW(1);
  RETURN num_tab(1);
END;
/

-- RETURN NEXT inside a pipelined function
CREATE OR REPLACE FUNCTION f_bad_returnnext(p_n NUMBER)
RETURN num_tab PIPELINED IS
BEGIN
  RETURN NEXT 1;
  RETURN;
END;
/

-- EXCEPTION handler inside a pipelined function
CREATE OR REPLACE FUNCTION f_bad_exception(p_n NUMBER)
RETURN num_tab PIPELINED IS
BEGIN
  PIPE ROW(1);
  RETURN;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

-- RETURN expression inside a pipelined function
CREATE OR REPLACE FUNCTION f_bad_returnexpr(p_n NUMBER)
RETURN num_tab PIPELINED IS
BEGIN
  RETURN num_tab(1, 2);
END;
/

-- missing RETURN still reports the standard end-of-function error
CREATE OR REPLACE FUNCTION f_no_return(p_n NUMBER)
RETURN num_tab PIPELINED IS
BEGIN
  PIPE ROW(1);
END;
/

-- VARRAY types are out of scope

SELECT column_value FROM TABLE(f_no_return(1));
CREATE TYPE v_tab AS VARRAY(5) OF NUMBER;

-- package-local collection types are out of scope (owned by #2184)
CREATE OR REPLACE PACKAGE pipeline_pkg AS
  TYPE pkg_tab IS TABLE OF NUMBER;
END pipeline_pkg;
/

--
-- Cleanup
--
DROP SEQUENCE pipeline_seq;
DROP TABLE pipeline_src;
DROP FUNCTION f_num_list;
DROP FUNCTION f_grid;
DROP FUNCTION f_exit_label;
DROP FUNCTION f_nulls;
DROP FUNCTION f_cursor_for;
DROP FUNCTION f_recs;
DROP FUNCTION f_recs_null;
DROP FUNCTION f_bad_rec;
DROP FUNCTION f_exit_cursors;
DROP FUNCTION f_max_loop;
DROP FUNCTION f_loop_found;
DROP FUNCTION f_materialized;
DROP FUNCTION f_counted;
DROP TYPE num_tab CASCADE;
DROP TYPE rec_tab;
DROP TYPE pipeline_rec;
DROP TYPE pipeline_wide_rec;
DROP TYPE pipeline_schema.limited_tab;
DROP SCHEMA pipeline_schema;
