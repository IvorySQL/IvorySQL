/*	contrib/pg_get_functiondef/pg_get_functiondef--1.0.sql */

CREATE FUNCTION pg_get_functiondef() RETURNS CSTRING
AS 'pg_get_functiondef', 'pg_get_functiondef_no_input'
LANGUAGE C;

CREATE FUNCTION pg_get_functiondef(OID, VARIADIC OID[]) RETURNS TABLE (oid OID, pg_get_functiondef CSTRING)
AS 'pg_get_functiondef', 'pg_get_functiondef_mul'
LANGUAGE C;

CREATE FUNCTION pg_get_functiondef(VARIADIC TEXT[]) RETURNS TABLE (name CSTRING, pg_get_functiondef CSTRING)
AS 'pg_get_functiondef', 'pg_get_functiondef_extend'
LANGUAGE C;
