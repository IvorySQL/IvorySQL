# ivorysql_ora

`ivorysql_ora` is the core Oracle-compatibility extension for IvorySQL. It
provides Oracle-compatible data types, built-in functions, built-in packages,
and SQL syntax extensions within the `sys` schema.

## Features

### Oracle-Compatible Data Types

| Type | Description |
|------|-------------|
| `oracharchar` / `oracharbyte` | CHAR with CHAR/BYTE semantics |
| `oravarcharchar` / `oravarcharbyte` | VARCHAR2 with CHAR/BYTE semantics |
| `oradate` | Oracle DATE (includes time component) |
| `oratimestamp` / `oratimestamptz` / `oratimestampltz` | TIMESTAMP variants |
| `yminterval` | INTERVAL YEAR TO MONTH |
| `dsinterval` | INTERVAL DAY TO SECOND |
| `binary_float` / `binary_double` | IEEE 754 floating-point types |
| `raw` / `long raw` | Binary data types |

### Built-in Functions

- **Character functions**: Oracle-compatible string manipulation functions
- **Datetime functions**: Oracle-compatible date/time arithmetic and formatting
- **Numeric functions**: Oracle-compatible numeric operations
- **XML functions**: Oracle-compatible XMLType operations (requires libxml2)
- **Miscellaneous functions**: DECODE, NVL, NVL2, SYS_GUID, etc.

### Built-in Packages

| Package | Description |
|---------|-------------|
| `DBMS_OUTPUT` | Buffered message output |
| `DBMS_UTILITY` | Utility procedures (FORMAT_ERROR_BACKTRACE, etc.) |
| `DBMS_LOCK` | Advisory lock wrappers |
| `DBMS_SESSION` | Session-level settings |
| `UTL_FILE` | Server-side file I/O |
| `UTL_ENCODE` | Encoding/decoding utilities (BASE64, QUOTED_PRINTABLE, etc.) |
| `UTL_RAW` | Raw data manipulation |

### SQL Extensions

- Oracle-compatible `MERGE` statement
- `LISTAGG` / `STRAGG` aggregate functions
- Oracle-compatible system views in the `sys` schema

## Building

### In-tree build (recommended)

From the IvorySQL source root:

```bash
./configure --prefix=/path/to/install
make -C contrib/ivorysql_ora
make -C contrib/ivorysql_ora install
```

If libxml2 is available, XML functions are built automatically.

### Using PGXS (standalone)

```bash
make USE_PGXS=1 PG_CONFIG=/path/to/pg_config
make USE_PGXS=1 PG_CONFIG=/path/to/pg_config install
```

## Installation

The extension requires superuser privileges and is installed in the `sys`
schema:

```sql
CREATE EXTENSION ivorysql_ora;
```

On server startup, `preload_ora_misc.sql` is loaded automatically to register
Oracle-compatible operators and casts.

## Regression Tests

Run the Oracle-compatibility regression suite:

```bash
make -C contrib/ivorysql_ora installcheck
```

This executes all test cases listed in `ORA_REGRESS` (character types,
datetime, intervals, numeric types, binary float/double, raw/long, built-in
functions, MERGE, system views, LIKE operator, XML functions, DBMS_OUTPUT,
DBMS_LOCK, DBMS_UTILITY, DBMS_SESSION, UTL_FILE, UTL_RAW, UTL_ENCODE,
STRAGG, and ASCII handling).

## Directory Layout

```
contrib/ivorysql_ora/
├── src/
│   ├── datatype/          Oracle-compatible type implementations
│   ├── builtin_functions/ Oracle-compatible function implementations
│   ├── builtin_packages/  DBMS_*/UTL_* package implementations
│   ├── merge/             Oracle MERGE statement support
│   ├── sysview/           Oracle-compatible system views
│   ├── xml_functions/     Oracle XMLType functions
│   └── guc/               Extension GUC parameters
├── sql/                   Regression test SQL scripts
├── expected/              Regression test expected output
├── gensql.pl              SQL generation script
├── ivorysql_ora.control   Extension control file
└── preload_ora_misc.sql   Startup preload script
```
