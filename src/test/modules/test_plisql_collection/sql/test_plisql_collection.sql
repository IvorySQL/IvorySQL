--
-- Contract tests for the plisql sparse collection runtime.
--
-- These lock down the RUNTIME's semantics, which intentionally differ in
-- places from the phase-2 plisql_coll_* catalog shims still in use by the
-- compiler (see the header comment in pl_collection_runtime.c).  Do not
-- "reconcile" these with the shim tests in src/pl/plisql/src/expected/ --
-- the shims are what go away.
--
CREATE EXTENSION test_plisql_collection;

--
-- Atomically NULL versus initialized-but-empty.  These are different values
-- in Oracle and most methods treat them differently.
--
SELECT coll_is_null(coll_import(NULL::int[], 'int4', 'table')) AS null_is_null,
       coll_is_null(coll_new('int4', 'table'))                AS empty_is_not_null;

-- an initialized empty collection answers; an uninitialized one raises
SELECT coll_count(coll_new('int4', 'table')) AS empty_count;
SELECT coll_first(coll_new('int4', 'table')) IS NULL AS empty_first_is_null;
SELECT coll_last(coll_new('int4', 'table')) IS NULL AS empty_last_is_null;

SELECT coll_count(coll_import(NULL::int[], 'int4', 'table'));
SELECT coll_first(coll_import(NULL::int[], 'int4', 'table'));
SELECT coll_get(coll_import(NULL::int[], 'int4', 'table'), 1);
SELECT coll_extend(coll_import(NULL::int[], 'int4', 'table'), 1);
SELECT coll_trim(coll_import(NULL::int[], 'int4', 'table'), 1);
SELECT coll_delete(coll_import(NULL::int[], 'int4', 'table'), 1);

-- EXISTS is the deliberate exception: never raises, on either
SELECT coll_exists(coll_import(NULL::int[], 'int4', 'table'), 1) AS exists_on_null,
       coll_exists(coll_new('int4', 'table'), 1)                 AS exists_on_empty;

--
-- Flat-array import: the array's own lower bound becomes the collection's
-- subscript origin, and is not silently renumbered.
--
SELECT coll_first(h) AS first, coll_last(h) AS last, coll_count(h) AS count
FROM coll_import('{10,20,30}'::int[], 'int4', 'table') AS h;

SELECT coll_first(h) AS first, coll_last(h) AS last, coll_count(h) AS count,
       coll_get(h, 3) AS at_3, coll_get(h, 5) AS at_5
FROM coll_import('[3:5]={10,20,30}'::int[], 'int4', 'table') AS h;

-- a lower bound below 1 is not a legal collection subscript
SELECT coll_import('[0:2]={10,20,30}'::int[], 'int4', 'table');

-- multidimensional input is rejected at the one import boundary
SELECT coll_import('{{1,2},{3,4}}'::int[], 'int4', 'table');

--
-- The defining behavior: DELETE(i) leaves a hole that COUNT, EXISTS, NEXT
-- and PRIOR all see.
--
CREATE TEMP TABLE h AS SELECT coll_import('{10,20,30,40,50}'::int[], 'int4', 'table') AS c;

SELECT coll_delete(c, 2), coll_delete(c, 4) FROM h;

SELECT coll_count(c)  AS count,          -- 3, not LAST - FIRST + 1 = 5
       coll_first(c)  AS first,
       coll_last(c)   AS last
FROM h;

SELECT coll_exists(c, 1) AS e1, coll_exists(c, 2) AS e2_deleted,
       coll_exists(c, 3) AS e3, coll_exists(c, 4) AS e4_deleted,
       coll_exists(c, 5) AS e5
FROM h;

-- NEXT/PRIOR traverse across holes, and idx itself need not be present
SELECT coll_next(c, 1) AS next_from_1, coll_next(c, 2) AS next_from_hole,
       coll_prior(c, 5) AS prior_from_5, coll_prior(c, 4) AS prior_from_hole
FROM h;

-- boundaries: no NEXT past LAST, no PRIOR before FIRST
SELECT coll_next(c, 5) IS NULL AS no_next_past_last,
       coll_prior(c, 1) IS NULL AS no_prior_before_first,
       coll_next(c, 99) IS NULL AS no_next_beyond_range,
       coll_prior(c, 0) IS NULL AS no_prior_below_range
FROM h;

-- reading a deleted element inside FIRST..LAST is NO_DATA_FOUND, distinct
-- from a subscript that was never in range
SELECT coll_get(c, 2) FROM h;
SELECT coll_get(c, 99) FROM h;

--
-- Flattening drops holes, in ascending index order, producing a dense
-- 1-based array.
--
SELECT coll_flatten(c) AS flattened FROM h;

-- and importing that back gives a dense collection: holes do not survive
-- boundary (2), by design
SELECT coll_count(f) AS count, coll_first(f) AS first, coll_last(f) AS last,
       coll_exists(f, 2) AS hole_is_gone
FROM (SELECT coll_roundtrip_flat(c) AS f FROM h) s;

-- whereas the expanded boundary preserves them
SELECT coll_count(e) AS count, coll_first(e) AS first, coll_last(e) AS last,
       coll_exists(e, 2) AS hole_preserved_as_absent,
       coll_exists(e, 3) AS present_preserved
FROM (SELECT coll_roundtrip_expanded(c) AS e FROM h) s;

-- an atomically NULL collection survives both boundaries as NULL
SELECT coll_is_null(coll_roundtrip_expanded(coll_import(NULL::int[], 'int4', 'table'))) AS expanded_null,
       coll_is_null(coll_roundtrip_flat(coll_import(NULL::int[], 'int4', 'table')))     AS flat_null;

-- an empty collection flattens to an empty array, not to NULL
SELECT coll_flatten(coll_new('int4', 'table')) AS empty_flattens_to;

--
-- set: duplicate insertion updates in place rather than inserting twice
--
CREATE TEMP TABLE d AS SELECT coll_new('int4', 'table') AS c;
SELECT coll_set(c, 1, 100), coll_set(c, 1, 200) FROM d;
SELECT coll_count(c) AS count_after_duplicate, coll_get(c, 1) AS value FROM d;

-- set at a subscript beyond LAST is PERMITTED by the current contract.
-- Oracle would require EXTEND first (ORA-06533); see the note on
-- plisql_collection_set() in pl_collection.h.  This test exists so that
-- tightening the behavior announces itself here.
SELECT coll_set(c, 10, 999) FROM d;
SELECT coll_count(c) AS count, coll_first(c) AS first, coll_last(c) AS last,
       coll_exists(c, 5) AS gap_is_absent
FROM d;

-- set into a deleted subscript restores it (same open question)
SELECT coll_delete(c, 10) FROM d;
SELECT coll_exists(c, 10) AS deleted FROM d;
SELECT coll_set(c, 10, 111) FROM d;
SELECT coll_exists(c, 10) AS restored, coll_get(c, 10) AS value FROM d;

-- invalid subscripts raise from set/get/delete but never from exists
SELECT coll_set(c, 0, 1) FROM d;
SELECT coll_set(c, -1, 1) FROM d;
SELECT coll_get(c, 0) FROM d;
SELECT coll_delete(c, 0) FROM d;
SELECT coll_exists(c, 0) AS exists_zero, coll_exists(c, -5) AS exists_negative FROM d;

-- deleting an absent but valid subscript is a no-op, not an error
SELECT coll_delete(c, 7) FROM d;

--
-- TRIM works off the collection's internal size (every subscript ever
-- allocated), not the count of PRESENT entries, so it can trim away
-- subscripts that DELETE(i) already punched holes in.
--
CREATE TEMP TABLE t AS SELECT coll_import('{1,2,3,4,5}'::int[], 'int4', 'table') AS c;
SELECT coll_delete(c, 2), coll_delete(c, 4) FROM t;   -- present: 1,3,5; internal size still 5
SELECT coll_trim(c, 2) FROM t;                        -- internal size 5 -> 3; drops subscript 4 (already a hole) and 5
SELECT coll_count(c) AS count, coll_first(c) AS first, coll_last(c) AS last FROM t;

SELECT coll_trim(c, 99) FROM t;     -- more than the collection's internal size
SELECT coll_trim(c, -1) FROM t;

--
-- EXTEND appends after the current highest subscript, including across a
-- preceding DELETE, and honors the VARRAY limit.
--
CREATE TEMP TABLE e AS SELECT coll_import('{1,2,3}'::int[], 'int4', 'table') AS c;
SELECT coll_delete(c, 1) FROM e;    -- present: 2,3
SELECT coll_extend(c, 2) FROM e;
SELECT coll_count(c) AS count, coll_first(c) AS first, coll_last(c) AS last,
       coll_flatten(c) AS flattened
FROM e;
SELECT coll_extend(c, -1) FROM e;

--
-- VARRAY: dense and bounded.  DELETE(i) has no meaning on one.
--
-- an oversized initial import is rejected too, not just a subsequent EXTEND
SELECT coll_import('{1,2,3,4}'::int[], 'int4', 'varray', 3);

-- a VARRAY is dense and 1-based by definition, so a foreign array whose
-- lower bound isn't 1 must be rejected on import rather than silently
-- adopted with an off-by-N origin
SELECT coll_import('[2:4]={1,2,3}'::int[], 'int4', 'varray', 5);

CREATE TEMP TABLE v AS SELECT coll_import('{1,2}'::int[], 'int4', 'varray', 3) AS c;
SELECT coll_extend(c, 1) FROM v;        -- to the limit: allowed
SELECT coll_count(c) AS at_limit FROM v;
SELECT coll_extend(c, 1) FROM v;        -- past the limit: rejected
SELECT coll_delete(c, 1) FROM v;        -- individual DELETE: rejected
SELECT coll_delete_all(c) FROM v;       -- argument-less DELETE: allowed
SELECT coll_count(c) AS after_delete_all FROM v;

-- a subscript beyond the declared limit is invalid for a VARRAY
SELECT coll_set(c, 99, 1) FROM v;

--
-- Pass-by-reference elements must be copied into the collection's own
-- context, not retained by pointer.  Values set from a per-statement
-- temporary must still read back correctly in later statements.
--
CREATE TEMP TABLE s AS SELECT coll_new('text', 'table') AS c;
SELECT coll_set(c, 1, repeat('abc', 100)), coll_set(c, 2, 'short'::text) FROM s;
SELECT length(coll_get(c, 1)) AS long_len, coll_get(c, 2) AS short_val FROM s;
SELECT coll_delete(c, 1) FROM s;
SELECT coll_count(c) AS count, coll_get(c, 2) AS survivor FROM s;
SELECT coll_flatten(c) AS flattened FROM s;

-- Overwriting a pass-by-reference element reclaims the discarded copy
-- rather than leaking it; the new value must still read back correctly.
SELECT coll_set(c, 2, repeat('xyz', 50)) FROM s;
SELECT length(coll_get(c, 2)) AS after_overwrite_len FROM s;

-- DELETE_ALL and TRIM must reclaim pass-by-reference elements too, not just
-- pass-by-value ones.
CREATE TEMP TABLE s2 AS SELECT coll_import('{aa,bb,cc}'::text[], 'text', 'table') AS c;
SELECT coll_delete_all(c) FROM s2;
SELECT coll_count(c) AS count_after_delete_all FROM s2;

CREATE TEMP TABLE s3 AS SELECT coll_import('{aa,bb,cc}'::text[], 'text', 'table') AS c;
SELECT coll_trim(c, 2) FROM s3;
SELECT coll_count(c) AS count, coll_get(c, 1) AS survivor FROM s3;

-- NULL elements are distinct from absent ones
CREATE TEMP TABLE n AS SELECT coll_new('int4', 'table') AS c;
SELECT coll_set(c, 1, NULL::int), coll_set(c, 2, 5) FROM n;
SELECT coll_count(c) AS count,
       coll_exists(c, 1) AS null_element_exists,
       coll_get(c, 1) IS NULL AS null_element_reads_null
FROM n;
SELECT coll_flatten(c) AS flattened FROM n;

--
-- Type-boundary proof.
--
-- The compiler cutover was stopped by PostgreSQL's array code casting our
-- expanded object to ExpandedArrayHeader on the strength of its declared
-- type alone (arrayfuncs.c:1960, Assert(eah->ea_magic == EA_MAGIC)).  These
-- cases show that a dedicated non-array type removes that reach entirely:
-- the array machinery cannot even name the value, so the mis-cast is
-- unreachable by construction rather than by discipline.
--
CREATE TEMP TABLE p AS SELECT coll_import('{10,20,30,40,50}'::int[], 'int4', 'table') AS c;
SELECT coll_delete(c, 2), coll_delete(c, 4) FROM p;   -- present: 1,3,5

-- the same expanded object, handed to SQL as the dedicated type
SELECT coll_as_type(c)::text AS as_dedicated_type FROM p;

-- array machinery cannot reach it: no cast, no subscript, no array function
SELECT array_length(coll_as_type(c), 1) FROM p;
SELECT (coll_as_type(c))[1] FROM p;
SELECT cardinality(coll_as_type(c)) FROM p;
SELECT coll_as_type(c)::int[] FROM p;

-- meanwhile collection-aware operations still see the sparse value, which is
-- exactly what option 2 (flatten before every expression) would have lost
SELECT coll_type_count(coll_as_type(c)) AS count_sees_holes FROM p;

-- and the explicit conversion boundary still produces the elem[] form
SELECT coll_type_flatten(coll_as_type(c)) AS flattened FROM p;

--
-- The INTERNAL flat form, which the core may produce implicitly whenever it
-- wants a flat datum.  Unlike the explicit SQL boundary it must preserve
-- holes: an implicit flattening that silently densified would change the
-- value behind the program's back.
--
CREATE TEMP TABLE i AS SELECT coll_import('{10,20,30,40,50}'::int[], 'int4', 'table') AS c;
SELECT coll_delete(c, 2), coll_delete(c, 4) FROM i;   -- present: 1,3,5

SELECT coll_count(r) AS count, coll_first(r) AS first, coll_last(r) AS last,
       coll_exists(r, 2) AS hole_still_absent,
       coll_exists(r, 5) AS last_still_present,
       coll_flatten(r)   AS flattens_same
FROM (SELECT coll_roundtrip_internal_flat(c) AS r FROM i) s;

-- non-default subscript origin and NULL elements survive it too
CREATE TEMP TABLE i2 AS SELECT coll_import('[3:5]={10,20,30}'::int[], 'int4', 'table') AS c;
SELECT coll_set(c, 4, NULL::int) FROM i2;
SELECT coll_first(r) AS first, coll_last(r) AS last,
       coll_get(r, 4) IS NULL AS null_element_preserved,
       coll_get(r, 5) AS at_5
FROM (SELECT coll_roundtrip_internal_flat(c) AS r FROM i2) s;

-- an atomically NULL collection stays NULL through it
SELECT coll_is_null(coll_roundtrip_internal_flat(coll_import(NULL::int[], 'int4', 'table'))) AS still_null;

-- A malformed internal value must raise, never be reinterpreted -- and in
-- particular never be read as a dense array, which is how these same bytes
-- would decode if the internal and elem[] encodings were ever confused.
SELECT coll_corrupt_internal(c, 'version')   FROM i;
SELECT coll_corrupt_internal(c, 'count')     FROM i;
SELECT coll_corrupt_internal(c, 'count_high') FROM i;
SELECT coll_corrupt_internal(c, 'kind')      FROM i;
SELECT coll_corrupt_internal(c, 'elemtype')  FROM i;
SELECT coll_corrupt_internal(c, 'order')     FROM i;
SELECT coll_corrupt_internal(c, 'duplicate') FROM i;
SELECT coll_corrupt_internal(c, 'subscript') FROM i;
SELECT coll_corrupt_internal(c, 'truncate')  FROM i;

-- coll_corrupt_internal on an atomically NULL collection must raise a clear
-- error rather than dereferencing a NULL collection pointer
SELECT coll_corrupt_internal(coll_import(NULL::int[], 'int4', 'table'), 'version');

-- 'order' and 'duplicate' need at least 2 entries to be meaningful (and, for
-- 'duplicate', to stay in bounds); 'subscript' needs at least 1.  Too few
-- entries must raise a clear error instead of reading or writing past the
-- allocated subscript vector.
SELECT coll_corrupt_internal(coll_new('int4', 'table'), 'subscript');
SELECT coll_corrupt_internal(coll_new('int4', 'table'), 'order');
SELECT coll_corrupt_internal(coll_import('{10}'::int[], 'int4', 'table'), 'duplicate');

DROP EXTENSION test_plisql_collection CASCADE;
