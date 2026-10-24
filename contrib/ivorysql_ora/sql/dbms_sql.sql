-- Session handles, named scalar binds and streaming query results.
SET timezone TO 'UTC';
SET ivorysql.identifier_case_switch TO normal;
CREATE ROLE regress_dbms_sql SUPERUSER;
SET SESSION AUTHORIZATION regress_dbms_sql;
CREATE TABLE dbms_sql_data (id integer PRIMARY KEY, note varchar2(100), happened date);
CREATE TABLE dbms_sql_handles (c integer, label text);

DECLARE
  c INTEGER;
  n NUMBER := 1;
  s VARCHAR2(100) := 'one';
  d DATE := DATE '2026-01-02';
  affected INTEGER;
BEGIN
  c := dbms_sql.open_cursor();
  dbms_sql.parse(c, 'INSERT INTO dbms_sql_data VALUES (:id, :note, :day)', dbms_sql.native);
  dbms_sql.bind_variable(c, ':ID', n);
  dbms_sql.bind_variable(c, 'note', s);
  dbms_sql.bind_variable(c, 'day', d);
  affected := dbms_sql.execute(c);
  RAISE NOTICE 'insert rows: %, count: %', affected, dbms_sql.last_row_count();
  n := 2;
  s := 'x''; DELETE FROM dbms_sql_data; --';
  d := NULL;
  dbms_sql.bind_variable(c, 'id', n);
  dbms_sql.bind_variable(c, 'note', s);
  dbms_sql.bind_variable(c, 'day', d);
  affected := dbms_sql.execute(c);
  RAISE NOTICE 'repeat rows: %', affected;
  dbms_sql.close_cursor(c);
  RAISE NOTICE 'closed handle NULL: %, is_open: %', c IS NULL, dbms_sql.is_open(c);
END;
/
SELECT id, note, happened FROM dbms_sql_data ORDER BY id;

-- Integer literals choose a numeric binding without overload ambiguity.
DECLARE
  c INTEGER := dbms_sql.open_cursor();
  n NUMBER;
  ignored INTEGER;
BEGIN
  dbms_sql.parse(c, 'SELECT :v FROM dual', dbms_sql.native);
  dbms_sql.bind_variable(c, 'v', 12);
  dbms_sql.define_column(c, 1, n);
  ignored := dbms_sql.execute(c);
  ignored := dbms_sql.fetch_rows(c);
  dbms_sql.column_value(c, 1, n);
  RAISE NOTICE 'integer literal binding: %', n;
  dbms_sql.close_cursor(c);
END;
/

DECLARE
  c INTEGER := dbms_sql.open_cursor(2);
  n NUMBER;
  s VARCHAR2(100);
  d DATE;
  affected INTEGER;
BEGIN
  dbms_sql.parse(c, 'SELECT id, note, happened FROM dbms_sql_data WHERE id >= :low OR id = :LOW ORDER BY id', dbms_sql.native);
  n := 1;
  dbms_sql.bind_variable(c, 'low', n);
  dbms_sql.define_column(c, 1, n);
  dbms_sql.define_column(c, 2, s, 100);
  dbms_sql.define_column(c, 3, d);
  affected := dbms_sql.execute(c);
  RAISE NOTICE 'SELECT execute: %', affected;
  WHILE dbms_sql.fetch_rows(c) > 0 LOOP
    dbms_sql.column_value(c, 1, n);
    dbms_sql.column_value(c, 2, s);
    dbms_sql.column_value(c, 3, d);
    RAISE NOTICE 'row: %, %, day NULL: %', n, s, d IS NULL;
  END LOOP;
  RAISE NOTICE 'fetched count: %, repeat EOF: %', dbms_sql.last_row_count(), dbms_sql.fetch_rows(c);
  n := 2;
  dbms_sql.bind_variable(c, 'low', n);
  affected := dbms_sql.execute(c);
  affected := dbms_sql.fetch_rows(c);
  dbms_sql.column_value(c, 1, n);
  RAISE NOTICE 'reexecute first id: %', n;
  dbms_sql.close_cursor(c);
END;
/

-- Bind detection uses parser nodes, not replacement inside quotes/comments.
DECLARE
  c INTEGER := dbms_sql.open_cursor();
  s VARCHAR2(100) := 'bound';
  result VARCHAR2(100);
  n INTEGER;
BEGIN
  dbms_sql.parse(c, 'SELECT '':not_a_bind'' || :v || :V /* :ignored */ FROM dual', dbms_sql.native);
  dbms_sql.bind_variable(c, 'v', s);
  dbms_sql.define_column(c, 1, result, 100);
  n := dbms_sql.execute(c);
  n := dbms_sql.fetch_rows(c);
  dbms_sql.column_value(c, 1, result);
  RAISE NOTICE 'literal and repeated bind: %', result;
  dbms_sql.parse(c, 'UPDATE dbms_sql_data SET note = :v WHERE id = 1', dbms_sql.native);
  s := 'changed';
  dbms_sql.bind_variable(c, 'v', s);
  n := dbms_sql.execute(c);
  RAISE NOTICE 'update rows: %', n;
  dbms_sql.parse(c, 'DELETE FROM dbms_sql_data WHERE id = 2', dbms_sql.native);
  n := dbms_sql.execute(c);
  RAISE NOTICE 'delete rows: %', n;
  dbms_sql.close_cursor(c);
END;
/
SELECT id, note FROM dbms_sql_data ORDER BY id;

DECLARE
  c INTEGER := dbms_sql.open_cursor();
  s VARCHAR2(100) := 'merged';
  affected INTEGER;
BEGIN
  dbms_sql.parse(c, 'MERGE INTO dbms_sql_data t USING (SELECT 1 id, :v note FROM dual) s ON (t.id = s.id) WHEN MATCHED THEN UPDATE SET note = s.note WHEN NOT MATCHED THEN INSERT (id,note) VALUES(s.id,s.note)', dbms_sql.native);
  dbms_sql.bind_variable(c, 'v', s);
  affected := dbms_sql.execute(c);
  RAISE NOTICE 'MERGE rows: %', affected;
  dbms_sql.close_cursor(c);
END;
/
SELECT id, note FROM dbms_sql_data ORDER BY id;

-- Two handles have separate binds and result positions.
DECLARE
  a INTEGER := dbms_sql.open_cursor();
  b INTEGER := dbms_sql.open_cursor();
  n NUMBER := 7;
  outval NUMBER;
  ignored INTEGER;
BEGIN
  dbms_sql.parse(a, 'SELECT :n FROM dual', dbms_sql.native);
  dbms_sql.parse(b, 'SELECT :n FROM dual', dbms_sql.native);
  dbms_sql.bind_variable(a, 'n', n);
  n := 9;
  dbms_sql.bind_variable(b, 'n', n);
  dbms_sql.define_column(a, 1, outval);
  dbms_sql.define_column(b, 1, outval);
  ignored := dbms_sql.execute(a);
  ignored := dbms_sql.execute(b);
  ignored := dbms_sql.fetch_rows(a);
  dbms_sql.column_value(a, 1, outval);
  RAISE NOTICE 'handle a: %', outval;
  ignored := dbms_sql.fetch_rows(b);
  dbms_sql.column_value(b, 1, outval);
  RAISE NOTICE 'handle b: %', outval;
  -- Rebinding must not change the already-open portal's copied parameter.
  n := 99;
  dbms_sql.bind_variable(a, 'n', n);
  ignored := dbms_sql.fetch_rows(a);
  RAISE NOTICE 'handle a EOF after rebind: %', ignored;
  dbms_sql.close_cursor(a);
  dbms_sql.close_cursor(b);
END;
/

-- Conversion, Unicode byte limits, missing defines and output type checking.
DECLARE
  c INTEGER := dbms_sql.open_cursor();
  n NUMBER;
  s VARCHAR2(100);
  ignored INTEGER;
BEGIN
  dbms_sql.parse(c, 'SELECT 123456789012345678901234567890.125, ''数据库'', NULL FROM dual', dbms_sql.native);
  dbms_sql.define_column(c, 1, n);
  dbms_sql.define_column(c, 2, s, 8);
  ignored := dbms_sql.execute(c);
  ignored := dbms_sql.fetch_rows(c);
  dbms_sql.column_value(c, 1, n);
  RAISE NOTICE 'exact NUMBER: %', n;
  BEGIN
    dbms_sql.column_value(c, 2, s);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'byte limit caught: %', SQLSTATE;
  END;
  dbms_sql.define_column(c, 2, s, 9);
  dbms_sql.column_value(c, 2, s);
  RAISE NOTICE 'Unicode: %', s;
  BEGIN
    dbms_sql.column_value(c, 1, s);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'type mismatch caught: %', SQLSTATE;
  END;
  BEGIN
    dbms_sql.column_value(c, 3, n);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'missing define caught: %', SQLSTATE;
  END;
  dbms_sql.define_column(c, 3, n);
  dbms_sql.column_value(c, 3, n);
  RAISE NOTICE 'NULL output: %', n IS NULL;
  dbms_sql.close_cursor(c);
END;
/

-- Input validation must not turn NULL pointers into backend crashes.
SELECT sys.ora_dbms_sql_is_open(NULL);
SELECT sys.ora_dbms_sql_open_cursor(0);
SELECT sys.ora_dbms_sql_execute(NULL);
SELECT sys.ora_dbms_sql_close_cursor(2147483647);
INSERT INTO dbms_sql_handles VALUES (sys.ora_dbms_sql_open_cursor(1), 'validation');
SELECT sys.ora_dbms_sql_parse(c, NULL, 1) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_parse(c, 'SELECT 1 FROM dual', 0) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_parse(c, 'SELECT 1 FROM dual; SELECT 2 FROM dual', 1) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_parse(c, 'CREATE TABLE dbms_sql_bad (id int)', 1) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_parse(c, 'COMMIT', 1) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_parse(c, 'INSERT INTO dbms_sql_data(id) VALUES(2) RETURNING id', 1) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_parse(c, 'SELECT $1 FROM dual', 1) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_parse(c, 'SELECT :v FROM dual', 1) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_execute(c) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_bind_variable(c, NULL, 1::numeric) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_bind_variable(c, 'missing', 1::numeric) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_define_column(c, 0, 1::numeric, NULL) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_define_column(c, 1, ''::text, 0) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_column_value(c, 1, 1::numeric) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_close_cursor(c) FROM dbms_sql_handles;
TRUNCATE dbms_sql_handles;

-- Results from an aborted transaction are invalidated; handles can execute again.
INSERT INTO dbms_sql_handles VALUES (sys.ora_dbms_sql_open_cursor(1), 'rollback');
SELECT sys.ora_dbms_sql_parse(c, 'SELECT 123 FROM dual', 1) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_define_column(c, 1, 1::numeric, NULL) FROM dbms_sql_handles;
BEGIN;
SELECT sys.ora_dbms_sql_execute(c) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_fetch_rows(c) FROM dbms_sql_handles;
SELECT 1 / 0;
ROLLBACK;
SELECT sys.ora_dbms_sql_fetch_rows(c) FROM dbms_sql_handles;
BEGIN;
SELECT sys.ora_dbms_sql_execute(c) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_fetch_rows(c) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_column_value(c, 1, 1::numeric) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_close_cursor(c) FROM dbms_sql_handles;
COMMIT;
TRUNCATE dbms_sql_handles;

-- A failed execution can be rebound and executed again in an exception block.
DECLARE
  c INTEGER := dbms_sql.open_cursor();
  n NUMBER := 0;
  result NUMBER;
  ignored INTEGER;
BEGIN
  dbms_sql.parse(c, 'SELECT 10 / :n FROM dual', dbms_sql.native);
  dbms_sql.bind_variable(c, 'n', n);
  dbms_sql.define_column(c, 1, result);
  BEGIN
    ignored := dbms_sql.execute(c);
    ignored := dbms_sql.fetch_rows(c);
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'query failure caught: %', SQLSTATE;
  END;
  n := 2;
  dbms_sql.bind_variable(c, 'n', n);
  ignored := dbms_sql.execute(c);
  ignored := dbms_sql.fetch_rows(c);
  dbms_sql.column_value(c, 1, result);
  RAISE NOTICE 'recovered result: %', result;
  dbms_sql.close_cursor(c);
END;
/

-- Metadata survives transactions; active result portals do not.
INSERT INTO dbms_sql_handles VALUES (sys.ora_dbms_sql_open_cursor(1), 'transaction');
SELECT sys.ora_dbms_sql_parse(c, 'SELECT 42 FROM dual', 1) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_define_column(c, 1, 1::numeric, NULL) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_execute(c) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_fetch_rows(c) FROM dbms_sql_handles;
BEGIN;
SELECT sys.ora_dbms_sql_execute(c) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_fetch_rows(c) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_column_value(c, 1, 1::numeric) FROM dbms_sql_handles;
COMMIT;
SELECT sys.ora_dbms_sql_column_value(c, 1, 1::numeric) FROM dbms_sql_handles;
SELECT sys.ora_dbms_sql_close_cursor(c) FROM dbms_sql_handles;
TRUNCATE dbms_sql_handles;

-- Even a superuser may not consume a different user's handle.
INSERT INTO dbms_sql_handles VALUES (sys.ora_dbms_sql_open_cursor(1), 'owner');
RESET SESSION AUTHORIZATION;
SELECT sys.ora_dbms_sql_is_open(c) FROM dbms_sql_handles;
SET SESSION AUTHORIZATION regress_dbms_sql;
SELECT sys.ora_dbms_sql_close_cursor(c) FROM dbms_sql_handles;
DROP TABLE dbms_sql_handles;
DROP TABLE dbms_sql_data;
RESET SESSION AUTHORIZATION;
DROP ROLE regress_dbms_sql;
RESET ivorysql.identifier_case_switch;
RESET timezone;
