# `ivorysql_ora`

`ivorysql_ora` provides the SQL objects and server hooks used by IvorySQL's
Oracle compatibility mode. It includes Oracle-compatible data types,
functions, catalog views, XML helpers, and a tested subset of commonly used
built-in packages.

This extension is designed for IvorySQL and is not a portable PostgreSQL
extension. It depends on IvorySQL catalog entries, parser hooks, and PL/iSQL.
It also does not imply complete Oracle compatibility: verify every feature
required by an application against the target IvorySQL release.

## Installation

### New Oracle-compatible cluster

The simplest setup is to build and install IvorySQL, then initialize the
cluster in Oracle mode:

```sh
./configure --prefix=/path/to/ivorysql
make -j
make install

/path/to/ivorysql/bin/initdb --dbmode=oracle -D /path/to/data
```

`initdb --dbmode=oracle` configures `liboracle_parser` and `ivorysql_ora` in
`shared_preload_libraries`, and installs both `plisql` and `ivorysql_ora` in
the initial databases.

### Existing cluster

For an existing cluster, first add the libraries to
`shared_preload_libraries`, preserving any libraries already configured:

```conf
shared_preload_libraries = 'liboracle_parser, ivorysql_ora'
```

Restart the server after changing this setting. Then install the extensions
as a superuser in each database that needs Oracle compatibility:

```sql
SET ivorysql.compatible_mode = oracle;
CREATE EXTENSION plisql;
CREATE EXTENSION ivorysql_ora;
```

`plisql` must be installed first because `ivorysql_ora` creates package
specifications and bodies implemented in PL/iSQL. The extension is fixed to
the `sys` schema and is not relocatable.

Verify the resulting setup with:

```sql
SHOW ivorysql.compatible_mode;

SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('plisql', 'ivorysql_ora')
ORDER BY extname;
```

## Feature groups

The extension currently installs the following groups of compatibility
objects:

| Group | Examples |
| --- | --- |
| Data types and operators | `NUMBER`, Oracle character types, `DATE`, timestamp variants, year-to-month and day-to-second intervals, `BINARY_FLOAT`, `BINARY_DOUBLE`, `RAW`, `LONG RAW`, `BLOB`, and `CLOB` |
| Character and regular-expression functions | `ASCIISTR`, `LENGTHB`, `SUBSTRB`, `INSTR`, `INSTRB`, `REGEXP_COUNT`, `REGEXP_INSTR`, `REGEXP_LIKE`, `REGEXP_REPLACE`, and `REGEXP_SUBSTR` |
| Date, time, interval, and numeric functions | `SYSDATE`, `SYSTIMESTAMP`, `ADD_MONTHS`, `LAST_DAY`, `MONTHS_BETWEEN`, `NEXT_DAY`, `TO_DATE`, `TO_TIMESTAMP`, `TO_TIMESTAMP_TZ`, `TO_NUMBER`, and interval conversion functions |
| Other SQL compatibility | Oracle-style `MERGE` behavior, `SYS_CONTEXT`, `USERENV`, `UID`, `HEXTORAW`, `RAWTOHEX`, `LISTAGG` support, and Oracle-compatible system views |
| XML | `XMLTYPE` and helpers including `EXISTSNODE`, `EXTRACT`, `EXTRACTVALUE`, and XML update functions |
| Built-in packages | `DBMS_LOCK`, `DBMS_OUTPUT`, `DBMS_SESSION`, `DBMS_UTILITY`, `UTL_ENCODE`, `UTL_FILE`, and `UTL_RAW` |

Most public compatibility objects live in the `sys` schema. Oracle mode
resolves their SQL-facing names as expected; use `sys.` qualification when
inspecting the underlying objects or when name resolution is ambiguous.

## Built-in package coverage

Package coverage is intentionally narrower than the corresponding Oracle
packages. The implemented interfaces are summarized below; the package SQL
files linked in the last column are the authoritative API definitions for
this source tree.

| Package | Implemented subset | Definition |
| --- | --- | --- |
| `DBMS_OUTPUT` | `ENABLE`, `DISABLE`, `PUT`, `PUT_LINE`, `NEW_LINE`, `GET_LINE`, and `GET_LINES` | [`dbms_output--1.0.sql`](src/builtin_packages/dbms_output/dbms_output--1.0.sql) |
| `DBMS_SESSION` | `SET_CONTEXT`, `CLEAR_CONTEXT`, `CLEAR_ALL_CONTEXT`, and `RESET_PACKAGE`; context enumeration is exposed as `sys.dbms_session_list_context()` | [`dbms_session--1.0.sql`](src/builtin_packages/dbms_session/dbms_session--1.0.sql) |
| `DBMS_UTILITY` | `FORMAT_ERROR_BACKTRACE`, `FORMAT_ERROR_STACK`, and `FORMAT_CALL_STACK` | [`dbms_utility--1.0.sql`](src/builtin_packages/dbms_utility/dbms_utility--1.0.sql) |
| `DBMS_LOCK` | `ALLOCATE_UNIQUE`, `REQUEST`, `RELEASE`, and `SLEEP`; only shared and exclusive lock modes are supported | [`dbms_lock--1.0.sql`](src/builtin_packages/dbms_lock/dbms_lock--1.0.sql) |
| `UTL_ENCODE` | `BASE64_ENCODE` and `BASE64_DECODE` | [`utl_encode--1.0.sql`](src/builtin_packages/utl_encode/utl_encode--1.0.sql) |
| `UTL_FILE` | Text and raw file open, close, read, write, seek, flush, copy, rename, remove, and attribute operations | [`utl_file--1.0.sql`](src/builtin_packages/utl_file/utl_file--1.0.sql) |
| `UTL_RAW` | `CAST_TO_RAW`, plus endian constants for source compatibility | [`utl_raw--1.0.sql`](src/builtin_packages/utl_raw/utl_raw--1.0.sql) |

Functions whose names begin with `sys.ora_` are implementation entry points
for package bodies. Applications should call the package API unless a source
file explicitly documents a standalone public interface.

## Examples

### Buffered output

`DBMS_OUTPUT` stores output in the current server session. A client must fetch
the buffer; writing a line does not automatically print it on the client.

```sql
DECLARE
  v_line   TEXT;
  v_status INTEGER;
BEGIN
  dbms_output.enable();
  dbms_output.put_line('hello');
  dbms_output.get_line(v_line, v_status);
  RAISE NOTICE 'line=%, status=%', v_line, v_status;
END;
/
```

The default buffer size is 20,000 bytes, the minimum requested size is 2,000
bytes, and each line is limited to 32,767 bytes. Calling `ENABLE(NULL)` selects
an unlimited total buffer. Buffer state is cleared by `DISCARD PACKAGE` and
`DISCARD ALL`.

### Application context

Custom `DBMS_SESSION` context values are session-local and can be read through
`SYS_CONTEXT`. Namespace and attribute names are case-insensitive.

```sql
CALL dbms_session.set_context('app_ctx', 'user_id', '42');

SELECT sys_context('APP_CTX', 'USER_ID');

CALL dbms_session.clear_context('app_ctx', 'user_id');
```

This can support row-level-security predicates, but the application must set
and clear context values at trusted connection boundaries. `DISCARD PACKAGE`
and `DISCARD ALL` clear the custom context store, while
`DBMS_SESSION.RESET_PACKAGE` resets PL/iSQL packages without clearing custom
application contexts.

### Server-side files

`UTL_FILE` maps logical directory names to server filesystem directories with
the `sys.utl_file_directory` table:

```sql
INSERT INTO sys.utl_file_directory(dirname, dir)
VALUES ('APP_EXPORT', '/srv/ivorysql/exports');
```

The database server operating-system account must have the required filesystem
permissions. Grant write access to `sys.utl_file_directory` only to trusted
administrators: changing a mapping changes which server-side path package
users can access. `utl_file.umask` controls the file-creation mask and defaults
to `0077`.

```sql
DECLARE
  v_file sys.ora_utl_file_file_type;
BEGIN
  v_file := utl_file.fopen('APP_EXPORT', 'example.txt', 'w');
  utl_file.put_line(v_file, 'generated by IvorySQL');
  utl_file.fclose(v_file);
EXCEPTION
  WHEN OTHERS THEN
    utl_file.fclose_all();
    RAISE;
END;
/
```

Directory mappings do not grant operating-system permissions and should not
be treated as a substitute for filesystem isolation.

## Session reset and connection pools

The extension maintains session-local state for packages, `DBMS_OUTPUT`,
`DBMS_SESSION`, `UTL_FILE`, and some other compatibility facilities. A pooled
connection can therefore retain state from a previous logical user.

Use `DISCARD PACKAGE` or `DISCARD ALL` at an appropriate pool reset boundary.
`DBMS_SESSION.RESET_PACKAGE` is useful when only PL/iSQL package state should
be reinitialized. Test the chosen reset command with the pooler and application
because `DISCARD ALL` also resets ordinary PostgreSQL session settings and
prepared state.

## Security notes

- Treat `UTL_FILE` directory mappings as privileged configuration and keep
  mapped directories narrowly scoped.
- Review `DBMS_LOCK` use for denial-of-service risks caused by long lock waits
  or inconsistent application lock ordering.
- Do not accept arbitrary context namespaces or attributes from untrusted
  clients when `SYS_CONTEXT` values drive authorization or row-level security.
- Review PL/iSQL package and routine ownership. Oracle-style routines default
  to definer rights unless `AUTHID CURRENT_USER` is specified.
- Schema-qualify trusted objects and parameterize dynamic SQL in
  security-sensitive stored code.

## Development and tests

From a configured IvorySQL source tree:

```sh
make -C contrib/ivorysql_ora
make -C contrib/ivorysql_ora install
```

The generated `ivorysql_ora--1.0.sql` file is assembled from the component
files listed in [`ivorysql_ora_merge_sqls`](ivorysql_ora_merge_sqls). Edit the
component SQL file rather than the generated output.

Run the extension's Oracle-mode regression suite with:

```sh
make -C contrib/ivorysql_ora oracle-check
```

To test against an installed server instead of the temporary test instance,
use:

```sh
make -C contrib/ivorysql_ora oracle-installcheck
```

The tests under [`sql/`](sql/) are also useful as executable examples of the
currently supported behavior.
