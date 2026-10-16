-- Upgrade path for the new sys.to_char(number, ...) overloads.
-- New installs receive these functions directly from
-- builtin_functions--1.0.sql, while existing 1.0 installations do not have
-- them at all: this script creates them when applied with
-- ALTER EXTENSION ivorysql_ora UPDATE TO '1.1'.
-- Unlike the date/timestamp overloads migrated in PR #1701, these functions
-- never existed in version 1.0, so no expression-index guard is needed here.

--to_char(number, format)
CREATE OR REPLACE FUNCTION sys.to_char(number, text)
RETURNS sys.oravarcharchar
AS $$select pg_catalog.to_char($1::numeric, $2)$$
LANGUAGE SQL STABLE PARALLEL SAFE STRICT;

--to_char(number, format, nlsparam)
CREATE OR REPLACE FUNCTION sys.to_char(number, text, text)
RETURNS sys.oravarcharchar
AS $$select pg_catalog.to_char($1::numeric, $2)$$
LANGUAGE SQL STABLE PARALLEL SAFE STRICT;
