# DBMS_UTILITY Implementation Proposal

## Summary

This proposal describes an implementation approach for `DBMS_UTILITY.FORMAT_ERROR_BACKTRACE` that follows IvorySQL's built-in package convention while addressing the cross-module dependency challenge.

## Background

Oracle's `DBMS_UTILITY.FORMAT_ERROR_BACKTRACE` returns the call stack at the point where an exception was raised. This requires access to exception context information that is internal to PL/iSQL's execution state.

## The Challenge

IvorySQL has two independent modules:

```
src/pl/plisql/src/     → plisql.so    (PL/iSQL language runtime)
contrib/ivorysql_ora/  → ivorysql_ora.so (Oracle compatibility extension)
```

The built-in package convention places packages in `contrib/ivorysql_ora/src/builtin_packages/`. However, `FORMAT_ERROR_BACKTRACE` needs access to PL/iSQL's exception context (`edata->context`), which is only available inside PL/iSQL's `exec_stmt_block()` during exception handling.

## Proposed Solution

Split the implementation between modules with a minimal API boundary:

### 1. Minimal API in `plisql` (5-10 lines)

Add a single accessor function to expose the exception context:

```c
// src/pl/plisql/src/pl_exec.c

static PLiSQL_execstate *exception_handling_estate = NULL;

const char *
plisql_get_current_exception_context(void)
{
    if (exception_handling_estate != NULL &&
        exception_handling_estate->cur_error != NULL)
        return exception_handling_estate->cur_error->context;
    return NULL;
}
```

Track `exception_handling_estate` when entering/exiting exception handlers:

```c
// In exec_stmt_block(), when entering exception handler:
exception_handling_estate = estate;
rc = exec_stmts(estate, exception->action);
exception_handling_estate = save_exception_handling_estate;
```

Export in header:

```c
// src/pl/plisql/src/plisql.h
extern PGDLLEXPORT const char *plisql_get_current_exception_context(void);
```

### 2. DBMS_UTILITY Package in `ivorysql_ora`

```
contrib/ivorysql_ora/
├── src/builtin_packages/
│   └── dbms_utility/
│       ├── dbms_utility.c           ← C code (format transformation)
│       └── dbms_utility--1.0.sql    ← Package definition
├── sql/dbms_utility.sql             ← Regression tests
├── expected/dbms_utility.out
├── Makefile                         ← Add dbms_utility.o
└── ivorysql_ora_merge_sqls          ← Add entry
```

The C code calls the plisql API and transforms the output:

```c
// contrib/ivorysql_ora/src/builtin_packages/dbms_utility/dbms_utility.c

#include "plisql.h"  // For plisql_get_current_exception_context()

Datum
ora_format_error_backtrace(PG_FUNCTION_ARGS)
{
    const char *pg_context = plisql_get_current_exception_context();
    if (pg_context == NULL)
        PG_RETURN_NULL();

    // Transform PostgreSQL format to Oracle format:
    // "PL/iSQL function foo() line 3 at RAISE"
    // → "ORA-06512: at \"PUBLIC.FOO\", line 3"
    ...
}
```

## File Changes Summary

### `plisql` Changes (Minimal)

| File | Change |
|------|--------|
| `src/pl/plisql/src/pl_exec.c` | Add `exception_handling_estate` tracking + API function (~20 lines) |
| `src/pl/plisql/src/plisql.h` | Add API declaration (1 line) |

### `ivorysql_ora` Changes (Main Implementation)

| File | Change |
|------|--------|
| `contrib/ivorysql_ora/src/builtin_packages/dbms_utility/dbms_utility.c` | New - C implementation |
| `contrib/ivorysql_ora/src/builtin_packages/dbms_utility/dbms_utility--1.0.sql` | New - Package definition |
| `contrib/ivorysql_ora/sql/dbms_utility.sql` | New - Regression tests |
| `contrib/ivorysql_ora/expected/dbms_utility.out` | New - Expected output |
| `contrib/ivorysql_ora/Makefile` | Add `dbms_utility.o` |
| `contrib/ivorysql_ora/ivorysql_ora_merge_sqls` | Add entry |

## Why This Approach?

1. **Follows convention**: DBMS_UTILITY lives in `contrib/ivorysql_ora/src/builtin_packages/`
2. **Minimal plisql changes**: Only a small API (~20 lines), no package code
3. **Clean API boundary**: `plisql_get_current_exception_context()` is a stable interface
4. **Uses existing data**: Leverages `estate->cur_error` which PL/iSQL already maintains
5. **No new struct fields**: Uses existing `ErrorData.context` field

## Alternative Considered

Implement everything in `plisql`:
- Simpler (no cross-module coordination)
- But doesn't follow built-in package convention
- Future DBMS packages would be inconsistent

## Questions for IvorySQL Team

1. Is adding a minimal API to `plisql` acceptable for packages that need PL/iSQL internals?
2. Should this API pattern be documented as the standard approach for such packages?
3. Are there any concerns about the `PGDLLEXPORT` approach for cross-module calls?

## References

- [Oracle DBMS_UTILITY.FORMAT_ERROR_BACKTRACE](https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_UTILITY.html#GUID-D72B928F-C353-461D-B098-83865F295C55)
- Existing IvorySQL built-in packages: `contrib/ivorysql_ora/src/builtin_functions/`

---

**Author:** [Your Name]
**Date:** 2025-12-02
**Status:** Proposal
