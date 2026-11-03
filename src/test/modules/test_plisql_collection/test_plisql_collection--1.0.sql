/* src/test/modules/test_plisql_collection/test_plisql_collection--1.0.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION test_plisql_collection" to load this file. \quit

--
-- Thin wrappers over the plisql collection runtime.  These are a test
-- harness private to this extension, not an API: the runtime's real callers
-- are compiler-generated, and these exist only so the runtime contract can
-- be exercised from SQL before the compiler is switched over to it.
--
-- A "handle" is an integer naming a collection held in a session-lifetime
-- slot, so a test can script an arbitrary sequence of operations.
--

-- construction / import -----------------------------------------------

CREATE FUNCTION coll_new(elemtype regtype, kind text, varray_limit int DEFAULT NULL)
RETURNS int
AS 'MODULE_PATHNAME', 'test_coll_new'
LANGUAGE C CALLED ON NULL INPUT;

-- arr may be NULL, meaning an atomically NULL collection; hence the
-- separate elemtype argument and CALLED ON NULL INPUT.
CREATE FUNCTION coll_import(arr anyarray, elemtype regtype, kind text,
							varray_limit int DEFAULT NULL)
RETURNS int
AS 'MODULE_PATHNAME', 'test_coll_import'
LANGUAGE C CALLED ON NULL INPUT;

CREATE FUNCTION coll_is_null(handle int) RETURNS bool
AS 'MODULE_PATHNAME', 'test_coll_is_null' LANGUAGE C STRICT;

-- datum boundaries ----------------------------------------------------

CREATE FUNCTION coll_roundtrip_expanded(handle int) RETURNS int
AS 'MODULE_PATHNAME', 'test_coll_roundtrip_expanded' LANGUAGE C STRICT;

CREATE FUNCTION coll_roundtrip_flat(handle int) RETURNS int
AS 'MODULE_PATHNAME', 'test_coll_roundtrip_flat' LANGUAGE C STRICT;

CREATE FUNCTION coll_flatten(handle int) RETURNS text
AS 'MODULE_PATHNAME', 'test_coll_flatten' LANGUAGE C STRICT;

-- operations ----------------------------------------------------------

CREATE FUNCTION coll_set(handle int, idx int, val anyelement) RETURNS void
AS 'MODULE_PATHNAME', 'test_coll_set' LANGUAGE C CALLED ON NULL INPUT;

CREATE FUNCTION coll_get(handle int, idx int) RETURNS text
AS 'MODULE_PATHNAME', 'test_coll_get' LANGUAGE C STRICT;

CREATE FUNCTION coll_exists(handle int, idx int) RETURNS bool
AS 'MODULE_PATHNAME', 'test_coll_exists' LANGUAGE C STRICT;

CREATE FUNCTION coll_delete(handle int, idx int) RETURNS void
AS 'MODULE_PATHNAME', 'test_coll_delete' LANGUAGE C STRICT;

CREATE FUNCTION coll_delete_all(handle int) RETURNS void
AS 'MODULE_PATHNAME', 'test_coll_delete_all' LANGUAGE C STRICT;

CREATE FUNCTION coll_count(handle int) RETURNS int
AS 'MODULE_PATHNAME', 'test_coll_count' LANGUAGE C STRICT;

CREATE FUNCTION coll_first(handle int) RETURNS int
AS 'MODULE_PATHNAME', 'test_coll_first' LANGUAGE C STRICT;

CREATE FUNCTION coll_last(handle int) RETURNS int
AS 'MODULE_PATHNAME', 'test_coll_last' LANGUAGE C STRICT;

CREATE FUNCTION coll_next(handle int, idx int) RETURNS int
AS 'MODULE_PATHNAME', 'test_coll_next' LANGUAGE C STRICT;

CREATE FUNCTION coll_prior(handle int, idx int) RETURNS int
AS 'MODULE_PATHNAME', 'test_coll_prior' LANGUAGE C STRICT;

CREATE FUNCTION coll_extend(handle int, n int DEFAULT 1) RETURNS void
AS 'MODULE_PATHNAME', 'test_coll_extend' LANGUAGE C STRICT;

CREATE FUNCTION coll_trim(handle int, n int DEFAULT 1) RETURNS void
AS 'MODULE_PATHNAME', 'test_coll_trim' LANGUAGE C STRICT;

-- type boundary ------------------------------------------------------
--
-- These use the REAL internal type, pg_catalog.plisql_collection, now that
-- it exists.  The point they prove is unchanged: PostgreSQL's array code
-- reaches an expanded object on the strength of its declared type alone
-- (arrayfuncs.c casts to ExpandedArrayHeader without consulting
-- eoh_methods), so a collection typed elem[] is always one expression away
-- from being mis-cast.  Given its own non-array type, the array machinery
-- cannot name it at all.
--
-- hand the runtime's expanded object to SQL under the dedicated type
CREATE FUNCTION coll_as_type(handle int) RETURNS pg_catalog.plisql_collection
AS 'MODULE_PATHNAME', 'test_coll_as_type' LANGUAGE C STRICT;

-- a collection-aware operation taking the dedicated type: the shape the
-- compiler's expression-position calls would have after cutover
CREATE FUNCTION coll_type_count(pg_catalog.plisql_collection) RETURNS int
AS 'MODULE_PATHNAME', 'test_coll_type_count' LANGUAGE C STRICT;

-- the explicit conversion boundary to the SQL-visible elem[] form
CREATE FUNCTION coll_type_flatten(pg_catalog.plisql_collection) RETURNS text
AS 'MODULE_PATHNAME', 'test_coll_type_flatten' LANGUAGE C STRICT;

-- the internal flat form: implicit flattening must not change the value
CREATE FUNCTION coll_roundtrip_internal_flat(handle int) RETURNS int
AS 'MODULE_PATHNAME', 'test_coll_roundtrip_internal_flat' LANGUAGE C STRICT;

CREATE FUNCTION coll_corrupt_internal(handle int, field text) RETURNS void
AS 'MODULE_PATHNAME', 'test_coll_corrupt_internal' LANGUAGE C STRICT;
