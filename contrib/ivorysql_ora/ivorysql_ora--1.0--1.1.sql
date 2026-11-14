/* ivorysql_ora--1.0--1.1.sql
 *
 * Versioned upgrade path for clusters whose ivorysql_ora extension was
 * installed at 1.0 (including clusters preserved through pg_upgrade):
 * the script of an already-installed version is never re-executed, so
 * the 1.1 catalog markings are replayed here as ALTER FUNCTIONs.
 * Mirrors exactly the property changes the 1.1 install script makes.
 */
\echo Use "ALTER EXTENSION ivorysql_ora UPDATE" to load this file. \quit

-- builtin_functions: plpgsql to_date wrappers gain STRICT/IMMUTABLE (already PARALLEL SAFE)
ALTER FUNCTION sys.to_date(bigint) STRICT PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.to_date(bigint, text) STRICT PARALLEL SAFE IMMUTABLE;

-- datatype: cast/helper functions become PARALLEL SAFE
ALTER FUNCTION sys.bool_orachar(boolean) STRICT PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.orachar_oravarchar(sys.oracharchar) STRICT PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.orachar_oravarcharbyte(sys.oracharchar) STRICT PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.orachar_oravarchar(sys.oracharbyte) STRICT PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.orachar_oravarcharbyte(sys.oracharbyte) STRICT PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.oravarcharcat(sys.oravarcharchar, sys.oravarcharchar) PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.concat(sys.oravarcharchar, sys.oravarcharchar) PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.oradate_date(sys.oradate) STRICT PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.date_oradate(pg_catalog.date) STRICT PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.numeric_binary_double(numeric) STRICT PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.to_char(text) PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.generate_series(number, number) PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.generate_series(number, number, number) PARALLEL SAFE IMMUTABLE;
ALTER FUNCTION sys.round(number, integer) STRICT PARALLEL SAFE IMMUTABLE;
