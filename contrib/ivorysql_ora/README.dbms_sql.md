# DBMS_SQL: scalar dynamic SQL cursors

This package provides a first scalar implementation of Oracle's `DBMS_SQL`
interface. It supports the complete parse/bind/execute/fetch/close workflow for
one SELECT or DML statement, using `NUMBER`, `VARCHAR2`, and `DATE` arguments.
It runs with the invoking user's privileges.

```sql
DECLARE
  c INTEGER;
  minimum_id NUMBER := 10;
  item_id NUMBER;
  item_name VARCHAR2(100);
  ignored INTEGER;
BEGIN
  c := dbms_sql.open_cursor();
  dbms_sql.parse(c,
    'SELECT id, name FROM items WHERE id >= :minimum_id ORDER BY id',
    dbms_sql.native);
  dbms_sql.bind_variable(c, ':minimum_id', minimum_id);
  dbms_sql.define_column(c, 1, item_id);
  dbms_sql.define_column(c, 2, item_name, 100);
  ignored := dbms_sql.execute(c);
  WHILE dbms_sql.fetch_rows(c) > 0 LOOP
    dbms_sql.column_value(c, 1, item_id);
    dbms_sql.column_value(c, 2, item_name);
    dbms_output.put_line(item_id || ': ' || item_name);
  END LOOP;
  dbms_sql.close_cursor(c);
EXCEPTION WHEN OTHERS THEN
  IF dbms_sql.is_open(c) THEN
    dbms_sql.close_cursor(c);
  END IF;
  RAISE;
END;
/
```

Create the `items` table and enable DBMS_OUTPUT display before running this
example. The PL/iSQL grammar accepts EXECUTE as a subprogram declaration name,
so applications use the ordinary `dbms_sql.execute(c)` spelling in every
identifier-case mode.

## Interfaces

| Subprogram | Behavior |
| --- | --- |
| `OPEN_CURSOR(security_level DEFAULT 1)` | Allocate a session-local integer handle; levels 1, 2, or NULL are accepted. |
| `IS_OPEN(c)` | False for NULL or closed/unknown handles; open handles require ownership. |
| `CLOSE_CURSOR(c IN OUT INTEGER)` | Close any result, free the handle and its memory, set `c` to NULL. |
| `PARSE(c, statement, language_flag)` | Accept one SELECT/INSERT/UPDATE/DELETE/MERGE; `NATIVE = 1` is the supported flag. |
| `BIND_VARIABLE(c, name, value)` | Bind a scalar by value, retaining its type even when NULL. |
| `DEFINE_COLUMN(c, position, value [, column_size])` | Set a 1-based output column's type; VARCHAR2 requires a byte size. |
| `EXECUTE(c)` | Execute DML and return affected rows; open a streaming SELECT portal and return 0. |
| `FETCH_ROWS(c)` | Fetch one row, returning 1, or return 0 at end of query. |
| `COLUMN_VALUE(c, position, value OUT ...)` | Convert a fetched value to the defined scalar type; preserve NULL. |
| `LAST_ROW_COUNT()` | Most recent DML affected count or cumulative rows fetched for the last query fetched. |

Binding/defining/reading columns has NUMBER, VARCHAR2 and DATE overloads. Use
typed variables to select the intended overload. An additional INTEGER binding
overload converts integer variables/literals to NUMBER. Character definitions are in
bytes, including multibyte encodings; overlong output raises an error rather
than silently truncating data. The output argument type must match its
definition. Source values are converted through the database type's output and
input functions, using the current type-formatting settings.

Names may include or omit a leading colon and are matched case-insensitively.
Repeated occurrences share one binding. Parser nodes identify placeholders:
colon-like strings inside SQL literals and comments are not modified. Binding
never interpolates values into SQL text. Rebinding affects the next execution;
an already-open query retains its own parameter values. Parsing a new statement
closes the old result and resets its binds/column definitions.

## Lifetimes, security and resource bounds

Handles and their parsed text, bound values and definitions persist across
transactions in one backend. Each SELECT result is a transaction-local portal:
fetch it before COMMIT/ROLLBACK. At transaction end or portal destruction, its
callback invalidates the result without destroying the handle. The handle can
be executed again. A new execution replaces the old result; fetching past EOF
invalidates the current row. Failed queries can be executed again after the
error has been handled or the transaction has been rolled back.

Results use the executor's streaming cursor interface and retain only the
current fetched row in package memory. The underlying SQL plan can still have
its own blocking operations such as sorting. Explicit close releases the
portal and all per-handle memory; backend exit releases remaining session
state. Limits are 1024 open handles, 1024 distinct binds per statement, and
the engine's maximum tuple attribute count for output column positions. IDs
are not reused during a session, so a stale ID cannot refer to a later handle.

Every handle operation verifies both the current user and the session user
against the identity that opened it, including fetch/close. This also applies
to superusers. Preparing and executing occurs as the invoking user with normal
table permissions and row security; no SECURITY DEFINER execution is used.
Sessions never share handles, bind values, portals or row data.

## Compatibility boundaries

This is a scalar subset, not full Oracle DBMS_SQL equivalence:

- PARSE checks raw syntax and supported statement shape. Name resolution,
  permissions, and bind-dependent semantic/type analysis occur at EXECUTE.
  There is no promise that an Oracle PARSE-time error occurs at the same call.
- SELECT results are transaction-local, unlike Oracle cursor behavior across
  commits. Session metadata remains available for reexecution.
- Unknown/closed `IS_OPEN` returns false and invalid cursor errors do not
  permanently disable the package for the session. PostgreSQL SQLSTATE errors
  are used; Oracle numeric error codes are not emulated.
- The identity check is stricter than Oracle's default for some operations.
  Oracle's container/security-level/role-set model is not reproduced; levels
  1 and 2 both use the same current/session-user check on every operation.
- DDL and its PARSE-time execution/implicit commit, anonymous blocks, transaction
  commands, SELECT INTO, data-modifying CTEs, DML RETURNING, array binds, LOB/LONG,
  bulk fetch, cursor conversion, output descriptors and OUT/IN OUT binds are
  unsupported. Unsupported statement shapes fail explicitly.
- DML counts must fit INTEGER, and columns use the supported scalar conversions.
  Arrays, arbitrary unknown output schemas and the full Method 4 interface are
  outside this first version.

The API contract was studied using the [Oracle 19c DBMS_SQL reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_SQL.html).
Tests verify the stated subset on IvorySQL; they do not claim live Oracle-instance
comparison.

## Build and tests

The module is included in Make, the SQL merge manifest, and Meson source lists.
Initialize a new Oracle-mode cluster with the newly installed extension SQL to
obtain the package; existing clusters do not acquire new SQL objects merely by
replacing the shared library.

```sh
make -C contrib/ivorysql_ora oracle-installcheck ORA_REGRESS=dbms_sql
make -C contrib/ivorysql_ora oracle-installcheck ORA_REGRESS= \
  PROVE_TESTS=t/003_dbms_sql.pl
```

Enable TAP tests when configuring to run the second command. SQL regression
coverage exercises public package calls, DML/rebinding, scalar output, Unicode,
error recovery, transaction boundaries and ownership. TAP adds independent
sessions, copied portal parameters, lazy fetch, ACL checks, resource limits,
memory-context cleanup and session exit with an active query.
