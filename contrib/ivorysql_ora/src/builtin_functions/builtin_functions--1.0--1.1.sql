-- Upgrade path for the new sys.soundex function.
-- New installs receive the function from builtin_functions--1.0.sql and,
-- because CREATE EXTENSION reaches version 1.1 by running the 1.0 script
-- followed by this one, re-execute this script right after creating it;
-- existing 1.0 installations, which do not have the function at all, run
-- it through ALTER EXTENSION ivorysql_ora UPDATE TO '1.1'.  The function
-- therefore uses CREATE OR REPLACE: harmless re-execution for fresh
-- installs, creation for upgraded ones.
-- The function is new in this version, so no guards against incompatible
-- pre-existing definitions are needed here.

CREATE OR REPLACE FUNCTION sys.soundex(str text)
RETURNS text
AS 'MODULE_PATHNAME','ora_soundex'
LANGUAGE C
STRICT
PARALLEL SAFE
IMMUTABLE;
COMMENT ON FUNCTION sys.soundex(text) IS 'Return the phonetic representation of the given string, following the algorithm documented in the Oracle SQL Language Reference';
