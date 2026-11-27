# What is ivorysql_ora?

TODO 

# How do I build the extensions?

TODO

# Updating NUMBER default output

Version 1.1 removes insignificant fractional trailing zeros from the default
text output of `sys.number`. Column precision, scale, rounding and binary output
are unchanged. Explicit number format models still control `TO_CHAR` output.

After installing the updated library and SQL scripts, restart the server to
load the new library, then run this command in each existing database:

```sql
ALTER EXTENSION ivorysql_ora UPDATE TO '1.1';
```

New clusters automatically install the default version, 1.1. Existing expression
indexes or persisted expressions that depend on NUMBER's old text representation
need to be rebuilt or refreshed when upgrading.

# Updating Oracle character matching compatibility

Version 1.1 adds text overloads of `sys.regexp_like` and padding-preserving
`sys.like_escape` overloads for CHAR, and default `TO_CHAR` overloads for
`BINARY_FLOAT` and `BINARY_DOUBLE`. Oracle mode's default
search path resolves ordinary calls to these overloads; PostgreSQL mode keeps
the native PostgreSQL functions. Explicit schema names and search paths retain
their usual meaning.

After installing the updated library and SQL scripts, restart the server and
run this command in each existing database:

```sql
ALTER EXTENSION ivorysql_ora UPDATE TO '1.1';
```

New clusters automatically install version 1.1. The Oracle implementation
accepts only `i`, `c`, `n`, `m` and `x`, applies Oracle newline defaults and treats
a NULL match parameter as the default options. Invalid options report
`illegal argument for function`.

Oracle `LIKE` and `NOT LIKE` retain the padding of `CHAR` values, patterns and
escape arguments during expression analysis. Ordinary casts from `CHAR` to
`text` keep their existing behavior. Install the updated server binary as well
as the extension before restarting the server.
Recreate affected views or other stored expressions from their original SQL
if they were analyzed before the CHAR padding fix.

Oracle binary floating-point output and default `TO_CHAR` use scientific
notation with 9 significant digits for `BINARY_FLOAT` and 17 for
`BINARY_DOUBLE`, a three-digit exponent and the special values `0`, `Inf`,
`-Inf` and `Nan`. PostgreSQL mode retains its existing type output and
`extra_float_digits` behavior. Explicit numeric format models are unchanged.
Exact native numeric `TO_CHAR` overloads preserve their existing NUMBER path;
integer `LENGTH` overloads avoid an unintended BINARY_DOUBLE conversion.
The server emits the full conversion precision. SQL*Plus can round this
further for display according to its `NUMWIDTH` setting.

Oracle `GREATEST` and `LEAST` use the first argument to select numeric or
character comparison. Numeric arguments follow `NUMBER < BINARY_FLOAT <
BINARY_DOUBLE` precedence; character comparisons retain CHAR padding and
return VARCHAR2. A NULL argument makes the result NULL and skips later
arguments. PostgreSQL expressions retain their original behavior, including
when a saved expression is read from a session using the other parser.
Recreate stored Oracle expressions analyzed before this fix to apply the
updated comparison and NULL rules.

# Updating ALL_SEQUENCES

Version 1.1 grants read access to `ALL_SEQUENCES` and limits its rows to
sequences accessible to the current user.

# Protecting SYS.DUAL

New Oracle-mode clusters and databases upgraded from extension version 1.0
install a trigger that rejects writes to `SYS.DUAL`, including writes by
superusers.

For a database already using an earlier build of version 1.1, apply the guard
as a superuser in that database using the SQL fragment from this source tree.

```sh
psql -X -v ON_ERROR_STOP=1 --single-transaction -d "$database" \
  -f contrib/ivorysql_ora/src/sysview/dual--1.0--1.1.sql \
  -c 'ALTER EXTENSION ivorysql_ora ADD FUNCTION sys._ora_dual_read_only()'
```
