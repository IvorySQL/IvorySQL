--
-- Tests for "TYPE ... IS TABLE OF" / "TYPE ... IS VARRAY(n) OF"
-- collection type declarations (Phase 1).
--
-- Phase 1 represents such a type as an ordinary PostgreSQL array type
-- (elem[]); a variable of the type is therefore just an array-typed
-- scalar.  These tests cover declaration, bare and package-qualified
-- reference (including from a different package), use as a local
-- variable / return type / IN and OUT parameters, and the compile-time
-- checks that reject the parts this first cut does not implement
-- (INDEX BY, element NOT NULL, non-array element types, nested
-- collections, bad VARRAY limits).
--
-- Oracle surface syntax -- coll(i) subscripting, the coll_t(...)
-- constructor and the collection methods -- is added in Phase 2 (see the
-- second half of this file, below the Phase 1 tests).
--

--
-- Basic nested-table declaration in a package spec, used as a bare
-- (unqualified) return type and as a local variable.  Element access
-- uses array subscripting.
--
CREATE OR REPLACE PACKAGE test_pkgtab AS
    TYPE num_tab IS TABLE OF NUMBER;

    FUNCTION make_tab(a NUMBER, b NUMBER, c NUMBER) RETURN num_tab;
    FUNCTION third(t num_tab) RETURN NUMBER;
END test_pkgtab;
/

CREATE OR REPLACE PACKAGE BODY test_pkgtab AS
    FUNCTION make_tab(a NUMBER, b NUMBER, c NUMBER) RETURN num_tab IS
        res num_tab;
    BEGIN
        res := ARRAY[a, b, c]::NUMBER[];
        res[2] := res[2] + 100;
        RETURN res;
    END;

    FUNCTION third(t num_tab) RETURN NUMBER IS
    BEGIN
        RETURN t[3];
    END;
END test_pkgtab;
/

SELECT test_pkgtab.make_tab(1, 2, 3);
SELECT test_pkgtab.third(test_pkgtab.make_tab(10, 20, 30));
-- the composite/array return type resolves without a column alias list
SELECT * FROM test_pkgtab.make_tab(1, 2, 3);

DROP PACKAGE test_pkgtab;

--
-- The declaration is also allowed directly in a package BODY (a type
-- private to the package).
--
CREATE OR REPLACE PACKAGE test_bodyonly_tab AS
    FUNCTION sum_first_two RETURN NUMBER;
END test_bodyonly_tab;
/

CREATE OR REPLACE PACKAGE BODY test_bodyonly_tab AS
    TYPE int_tab IS TABLE OF INTEGER;

    FUNCTION sum_first_two RETURN NUMBER IS
        v int_tab;
    BEGIN
        v := ARRAY[7, 35]::int[];
        RETURN v[1] + v[2];
    END;
END test_bodyonly_tab;
/

SELECT test_bodyonly_tab.sum_first_two();

DROP PACKAGE test_bodyonly_tab;

--
-- Package-qualified and cross-package references: the collection type of
-- one package used from another, as a local variable and as a parameter.
--
CREATE OR REPLACE PACKAGE test_tabtypes AS
    TYPE str_tab IS TABLE OF VARCHAR2(20);
END test_tabtypes;
/

CREATE OR REPLACE PACKAGE test_tabuser AS
    FUNCTION join_two(a VARCHAR2, b VARCHAR2) RETURN VARCHAR2;
    FUNCTION nelems(t test_tabtypes.str_tab) RETURN INT;
END test_tabuser;
/

CREATE OR REPLACE PACKAGE BODY test_tabuser AS
    FUNCTION join_two(a VARCHAR2, b VARCHAR2) RETURN VARCHAR2 IS
        v test_tabtypes.str_tab;
    BEGIN
        v := ARRAY[a, b]::varchar[];
        RETURN v[1] || ',' || v[2];
    END;

    FUNCTION nelems(t test_tabtypes.str_tab) RETURN INT IS
    BEGIN
        RETURN cardinality(t);
    END;
END test_tabuser;
/

SELECT test_tabuser.join_two('foo', 'bar');
SELECT test_tabuser.nelems(ARRAY['a', 'b', 'c']::varchar[]);

DROP PACKAGE test_tabuser;
DROP PACKAGE test_tabtypes;

--
-- IN and OUT parameters of a collection type.
--
CREATE OR REPLACE PACKAGE test_tab_params AS
    TYPE num_tab IS TABLE OF NUMBER;

    PROCEDURE reverse3(src IN num_tab, dst OUT num_tab);
END test_tab_params;
/

CREATE OR REPLACE PACKAGE BODY test_tab_params AS
    PROCEDURE reverse3(src IN num_tab, dst OUT num_tab) IS
    BEGIN
        dst := ARRAY[src[3], src[2], src[1]]::NUMBER[];
    END;
END test_tab_params;
/

DECLARE
    a test_tab_params.num_tab;
    b test_tab_params.num_tab;
BEGIN
    a := ARRAY[1, 2, 3]::NUMBER[];
    test_tab_params.reverse3(a, b);
    RAISE NOTICE 'b = [%, %, %]', b[1], b[2], b[3];
END;
/

DROP PACKAGE test_tab_params;

--
-- VARRAY declaration and basic use.  The declared size limit is stored
-- but not yet enforced at runtime (that is a later phase).
--
CREATE OR REPLACE PACKAGE test_varray AS
    TYPE num_arr IS VARRAY(5) OF NUMBER;

    FUNCTION first_plus_last(v num_arr) RETURN NUMBER;
END test_varray;
/

CREATE OR REPLACE PACKAGE BODY test_varray AS
    FUNCTION first_plus_last(v num_arr) RETURN NUMBER IS
    BEGIN
        RETURN v[1] + v[array_upper(v, 1)];
    END;
END test_varray;
/

SELECT test_varray.first_plus_last(ARRAY[10, 20, 30, 40]::NUMBER[]);

DROP PACKAGE test_varray;

--
-- Nested table of a *named* composite type (which has a catalog array
-- type) works.
--
CREATE TYPE test_point_t AS (x INT, y INT);

CREATE OR REPLACE PACKAGE test_tab_of_composite AS
    TYPE point_tab IS TABLE OF test_point_t;

    FUNCTION second_x(t point_tab) RETURN INT;
END test_tab_of_composite;
/

CREATE OR REPLACE PACKAGE BODY test_tab_of_composite AS
    FUNCTION second_x(t point_tab) RETURN INT IS
    BEGIN
        RETURN (t[2]).x;
    END;
END test_tab_of_composite;
/

SELECT test_tab_of_composite.second_x(
    ARRAY[ROW(1, 2), ROW(3, 4)]::test_point_t[]);

DROP PACKAGE test_tab_of_composite;
DROP TYPE test_point_t;

--
-- Standalone (non-package) function with a collection type in its
-- DECLARE section.
--
CREATE OR REPLACE FUNCTION test_local_tab() RETURN NUMBER IS
    TYPE num_tab IS TABLE OF NUMBER;
    v num_tab;
BEGIN
    v := ARRAY[3, 4]::NUMBER[];
    RETURN v[1] * v[2];
END;
/

SELECT test_local_tab();

DROP FUNCTION test_local_tab();

--
-- Rejections (compile-time), each with a clean error and no crash.
--

-- INDEX BY (associative arrays) is not supported yet
CREATE OR REPLACE PACKAGE test_reject_indexby AS
    TYPE assoc_t IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
END test_reject_indexby;
/

-- element NOT NULL cannot be enforced yet
CREATE OR REPLACE PACKAGE test_reject_notnull AS
    TYPE nn_t IS TABLE OF NUMBER NOT NULL;
END test_reject_notnull;
/

-- VARRAY size limit must be positive
CREATE OR REPLACE PACKAGE test_reject_varray0 AS
    TYPE bad_t IS VARRAY(0) OF NUMBER;
END test_reject_varray0;
/

-- nested collection: element type is itself a collection/array type
CREATE OR REPLACE PACKAGE test_reject_nested AS
    TYPE inner_t IS TABLE OF NUMBER;
    TYPE outer_t IS TABLE OF inner_t;
END test_reject_nested;
/

-- element type has no array type: a package RECORD type is RECORDOID + typmod
CREATE OR REPLACE PACKAGE test_reject_recordelem AS
    TYPE rec_t IS RECORD(a NUMBER, b NUMBER);
    TYPE rec_tab IS TABLE OF rec_t;
END test_reject_recordelem;
/

--
-- Type-vs-variable confusion: using the collection type name where a
-- value/variable is expected must raise a normal error, not crash, and
-- the session must stay usable afterwards.
--
CREATE OR REPLACE PACKAGE test_tab_confusion AS
    TYPE num_tab IS TABLE OF NUMBER;
    FUNCTION bad_ref RETURN NUMBER;
END test_tab_confusion;
/

CREATE OR REPLACE PACKAGE BODY test_tab_confusion AS
    FUNCTION bad_ref RETURN NUMBER IS
    BEGIN
        RETURN num_tab[1];
    END;
END test_tab_confusion;
/

SELECT test_tab_confusion.bad_ref();

-- "num_tab%TYPE" where num_tab names the declaration itself does not resolve
CREATE OR REPLACE PACKAGE BODY test_tab_confusion AS
    FUNCTION bad_ref RETURN NUMBER IS
        v num_tab%TYPE;
    BEGIN
        v := ARRAY[1]::NUMBER[];
        RETURN v[1];
    END;
END test_tab_confusion;
/

SELECT test_tab_confusion.bad_ref();

-- session and package cache must stay usable after those errors
SELECT 1 AS session_still_usable_after_tab_type_errors;

DROP PACKAGE test_tab_confusion;

--
-- Phase 2: Oracle collection surface syntax on top of the Phase 1 array
-- representation -- coll(i) indexing (read and assignment target), the
-- read-only pseudo-attributes .COUNT/.FIRST/.LAST, .EXISTS(i), the
-- type_name(...) constructor, and the mutating pseudo-procedures
-- .EXTEND/.TRIM/.DELETE.
--

--
-- .COUNT/.FIRST/.LAST on an empty and a populated collection; coll(i)
-- read (including out-of-range); coll(i) as an assignment target
-- (including growing the array); .EXISTS(i); the constructor used both
-- as a direct return value and as a function argument.
--
CREATE OR REPLACE PACKAGE test_coll_methods AS
    TYPE num_tab IS TABLE OF NUMBER;

    FUNCTION describe_empty RETURN VARCHAR2;
    FUNCTION describe_full RETURN VARCHAR2;
    FUNCTION element_at(t num_tab, i INTEGER) RETURN NUMBER;
    FUNCTION assign_via_paren RETURN num_tab;
    FUNCTION exists_check(t num_tab, i INTEGER) RETURN BOOLEAN;
    FUNCTION build_via_constructor RETURN num_tab;
    FUNCTION build_empty_via_constructor RETURN VARCHAR2;
    FUNCTION accepts_tab(t num_tab) RETURN NUMBER;
END test_coll_methods;
/

CREATE OR REPLACE PACKAGE BODY test_coll_methods AS
    FUNCTION describe_empty RETURN VARCHAR2 IS
        t num_tab;
    BEGIN
        RETURN 'count=' || t.count || ' first=' || t.first || ' last=' || t.last;
    END;

    FUNCTION describe_full RETURN VARCHAR2 IS
        t num_tab := ARRAY[10, 20, 30]::NUMBER[];
    BEGIN
        RETURN 'count=' || t.count || ' first=' || t.first || ' last=' || t.last;
    END;

    FUNCTION element_at(t num_tab, i INTEGER) RETURN NUMBER IS
    BEGIN
        RETURN t(i);
    END;

    FUNCTION assign_via_paren RETURN num_tab IS
        t num_tab := ARRAY[1, 2, 3]::NUMBER[];
    BEGIN
        t(2) := 200;
        -- "t(5) := 500" on a three-element collection raises: Oracle
        -- requires EXTEND before a subscript exists.  See the dedicated
        -- beyond-count tests below.
        t.extend(2);
        t(5) := 500;
        RETURN t;
    END;

    FUNCTION exists_check(t num_tab, i INTEGER) RETURN BOOLEAN IS
    BEGIN
        RETURN t.exists(i);
    END;

    FUNCTION build_via_constructor RETURN num_tab IS
    BEGIN
        RETURN num_tab(1, 2, 3);
    END;

    -- the zero-argument constructor, e.g. "v tab_t := tab_t();", is a
    -- separate case from build_via_constructor above: it can't be
    -- resolved as an ordinary polymorphic VARIADIC call (there are no
    -- arguments to infer the element type from), so it needs its own
    -- coverage
    FUNCTION build_empty_via_constructor RETURN VARCHAR2 IS
        t num_tab := num_tab();
    BEGIN
        RETURN 'count=' || t.count;
    END;

    FUNCTION accepts_tab(t num_tab) RETURN NUMBER IS
    BEGIN
        RETURN t.count;
    END;
END test_coll_methods;
/

SELECT test_coll_methods.describe_empty();
SELECT test_coll_methods.describe_full();
SELECT test_coll_methods.element_at(ARRAY[10,20,30]::NUMBER[], 2);
-- out-of-range coll(i) read raises a clear error, not a silent NULL
SELECT test_coll_methods.element_at(ARRAY[10,20,30]::NUMBER[], 5);
SELECT test_coll_methods.assign_via_paren();
SELECT test_coll_methods.exists_check(ARRAY[10,20,30]::NUMBER[], 2);
SELECT test_coll_methods.exists_check(ARRAY[10,20,30]::NUMBER[], 5);
SELECT test_coll_methods.build_via_constructor();
SELECT test_coll_methods.build_empty_via_constructor();
-- the constructor used directly as a function argument
SELECT test_coll_methods.accepts_tab(test_coll_methods.build_via_constructor());

DROP PACKAGE test_coll_methods;

--
-- The type_name(...) constructor for a VARRAY(n) rejects more than n
-- arguments with a clear error.
--
CREATE OR REPLACE PACKAGE test_varray_construct AS
    TYPE small_arr IS VARRAY(3) OF NUMBER;
    FUNCTION too_many RETURN small_arr;
END test_varray_construct;
/

CREATE OR REPLACE PACKAGE BODY test_varray_construct AS
    FUNCTION too_many RETURN small_arr IS
    BEGIN
        RETURN small_arr(1, 2, 3, 4);
    END;
END test_varray_construct;
/

SELECT test_varray_construct.too_many();

DROP PACKAGE test_varray_construct;

--
-- .EXTEND / .EXTEND(n) / .TRIM / .TRIM(n) / .DELETE() / .DELETE(i)
-- mutating pseudo-procedures.
--
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.extend();
    RAISE NOTICE 'after extend(): % (count=%)', t, t.count;
    t.extend(2);
    RAISE NOTICE 'after extend(2): % (count=%)', t, t.count;
    t.trim();
    RAISE NOTICE 'after trim(): % (count=%)', t, t.count;
    t.trim(2);
    RAISE NOTICE 'after trim(2): % (count=%)', t, t.count;
    t.delete(t.last);
    RAISE NOTICE 'after delete(last): % (count=%)', t, t.count;
    t.delete();
    RAISE NOTICE 'after delete(): % (count=%)', t, t.count;
END;
$$;

-- DELETE of a non-last, in-range index removes just that element and
-- leaves a hole: the surviving subscripts keep their own numbers, which is
-- the defining behavior of an Oracle nested table.  See the sparse sequence
-- at the end of this file for the full traversal.
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(2);
    RAISE NOTICE 'after delete(2): count=% first=% last=% exists(2)=%',
                 t.count, t.first, t.last, t.exists(2);
END;
$$;

--
-- An explicit NULL argument is a distinct case from an omitted argument
-- and must be rejected, not silently treated as if nothing were passed
-- (e.g. EXTEND(NULL) must not quietly behave like EXTEND()).
--
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.extend(NULL);
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.trim(NULL);
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(NULL);
END;
$$;

-- .EXTEND on a VARRAY enforces the declared limit
DO $$
DECLARE
    TYPE small_arr IS VARRAY(3) OF NUMBER;
    v small_arr := ARRAY[1, 2]::NUMBER[];
BEGIN
    v.extend();
    RAISE NOTICE 'v=%', v;
    v.extend();
END;
$$;

-- collection methods also accept the argument-less form without
-- parentheses, Oracle-style: "t.extend;" means "t.extend();"
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.extend;
    RAISE NOTICE 'count=%', t.count;
END;
$$;

-- an argument still requires parentheses to hold it
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.extend 2;
END;
$$;

-- the bare argument-less form works for .trim and .delete too
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.trim;
    RAISE NOTICE 'count after bare trim=%', t.count;
    t.delete;
    RAISE NOTICE 'count after bare delete=%', t.count;
END;
$$;

--
-- A collection value is one-dimensional.  A multidimensional array can
-- reach a collection variable by assignment (the variable's SQL type,
-- elem[], does not constrain dimensionality), and every operation must
-- reject it rather than describing or rebuilding it from its first
-- dimension alone -- COUNT would be 2, not 4, and EXTEND/TRIM/DELETE would
-- silently flatten it.
--
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    RAISE NOTICE 't.count=%', t.count;
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    RAISE NOTICE 't.first=%', t.first;
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    RAISE NOTICE 't.last=%', t.last;
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    RAISE NOTICE 't(1)=%', t(1);
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    RAISE NOTICE 't.exists(1)=%', t.exists(1);
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    t.extend();
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    t.trim();
END;
$$;

-- DELETE is the most dangerous of these: the index it accepts is the last
-- index of the first dimension, not of the collection
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    t.delete(2);
END;
$$;

--
-- A collection subscript starts at 1.  Indexed assignment has not yet
-- migrated to the collection runtime, so it would otherwise extend the
-- backing array downwards and leave the variable holding a value the
-- (already migrated) read path cannot import.  The assignment itself must
-- therefore fail, rather than succeeding and breaking a later read.
--
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t(0) := 5;
    RAISE NOTICE 'should not get here: t=%', t;
END;
$$;

-- a valid subscript still assigns, and reads back through the runtime
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t(2) := 200;
    RAISE NOTICE 't=% first=% last=% count=%', t, t.first, t.last, t.count;
    t.extend();
    RAISE NOTICE 'after extend: t=% last=% count=%', t, t.last, t.count;
END;
$$;

-- session and package cache must stay usable after those errors
SELECT 1 AS session_still_usable_after_tab_type_errors;

DROP PACKAGE test_tab_confusion;

--
-- Phase 2: Oracle collection surface syntax on top of the Phase 1 array
-- representation -- coll(i) indexing (read and assignment target), the
-- read-only pseudo-attributes .COUNT/.FIRST/.LAST, .EXISTS(i), the
-- type_name(...) constructor, and the mutating pseudo-procedures
-- .EXTEND/.TRIM/.DELETE.
--

--
-- .COUNT/.FIRST/.LAST on an empty and a populated collection; coll(i)
-- read (including out-of-range); coll(i) as an assignment target
-- (including growing the array); .EXISTS(i); the constructor used both
-- as a direct return value and as a function argument.
--
CREATE OR REPLACE PACKAGE test_coll_methods AS
    TYPE num_tab IS TABLE OF NUMBER;

    FUNCTION describe_empty RETURN VARCHAR2;
    FUNCTION describe_full RETURN VARCHAR2;
    FUNCTION element_at(t num_tab, i INTEGER) RETURN NUMBER;
    FUNCTION assign_via_paren RETURN num_tab;
    FUNCTION exists_check(t num_tab, i INTEGER) RETURN BOOLEAN;
    FUNCTION build_via_constructor RETURN num_tab;
    FUNCTION build_empty_via_constructor RETURN VARCHAR2;
    FUNCTION accepts_tab(t num_tab) RETURN NUMBER;
END test_coll_methods;
/

CREATE OR REPLACE PACKAGE BODY test_coll_methods AS
    FUNCTION describe_empty RETURN VARCHAR2 IS
        t num_tab;
    BEGIN
        RETURN 'count=' || t.count || ' first=' || t.first || ' last=' || t.last;
    END;

    FUNCTION describe_full RETURN VARCHAR2 IS
        t num_tab := ARRAY[10, 20, 30]::NUMBER[];
    BEGIN
        RETURN 'count=' || t.count || ' first=' || t.first || ' last=' || t.last;
    END;

    FUNCTION element_at(t num_tab, i INTEGER) RETURN NUMBER IS
    BEGIN
        RETURN t(i);
    END;

    FUNCTION assign_via_paren RETURN num_tab IS
        t num_tab := ARRAY[1, 2, 3]::NUMBER[];
    BEGIN
        t(2) := 200;
        -- "t(5) := 500" on a three-element collection raises: Oracle
        -- requires EXTEND before a subscript exists.  See the dedicated
        -- beyond-count tests below.
        t.extend(2);
        t(5) := 500;
        RETURN t;
    END;

    FUNCTION exists_check(t num_tab, i INTEGER) RETURN BOOLEAN IS
    BEGIN
        RETURN t.exists(i);
    END;

    FUNCTION build_via_constructor RETURN num_tab IS
    BEGIN
        RETURN num_tab(1, 2, 3);
    END;

    -- the zero-argument constructor, e.g. "v tab_t := tab_t();", is a
    -- separate case from build_via_constructor above: it can't be
    -- resolved as an ordinary polymorphic VARIADIC call (there are no
    -- arguments to infer the element type from), so it needs its own
    -- coverage
    FUNCTION build_empty_via_constructor RETURN VARCHAR2 IS
        t num_tab := num_tab();
    BEGIN
        RETURN 'count=' || t.count;
    END;

    FUNCTION accepts_tab(t num_tab) RETURN NUMBER IS
    BEGIN
        RETURN t.count;
    END;
END test_coll_methods;
/

SELECT test_coll_methods.describe_empty();
SELECT test_coll_methods.describe_full();
SELECT test_coll_methods.element_at(ARRAY[10,20,30]::NUMBER[], 2);
-- out-of-range coll(i) read raises a clear error, not a silent NULL
SELECT test_coll_methods.element_at(ARRAY[10,20,30]::NUMBER[], 5);
SELECT test_coll_methods.assign_via_paren();
SELECT test_coll_methods.exists_check(ARRAY[10,20,30]::NUMBER[], 2);
SELECT test_coll_methods.exists_check(ARRAY[10,20,30]::NUMBER[], 5);
SELECT test_coll_methods.build_via_constructor();
SELECT test_coll_methods.build_empty_via_constructor();
-- the constructor used directly as a function argument
SELECT test_coll_methods.accepts_tab(test_coll_methods.build_via_constructor());

DROP PACKAGE test_coll_methods;

--
-- The type_name(...) constructor for a VARRAY(n) rejects more than n
-- arguments with a clear error.
--
CREATE OR REPLACE PACKAGE test_varray_construct AS
    TYPE small_arr IS VARRAY(3) OF NUMBER;
    FUNCTION too_many RETURN small_arr;
END test_varray_construct;
/

CREATE OR REPLACE PACKAGE BODY test_varray_construct AS
    FUNCTION too_many RETURN small_arr IS
    BEGIN
        RETURN small_arr(1, 2, 3, 4);
    END;
END test_varray_construct;
/

SELECT test_varray_construct.too_many();

DROP PACKAGE test_varray_construct;

--
-- .EXTEND / .EXTEND(n) / .TRIM / .TRIM(n) / .DELETE() / .DELETE(i)
-- mutating pseudo-procedures.
--
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.extend();
    RAISE NOTICE 'after extend(): % (count=%)', t, t.count;
    t.extend(2);
    RAISE NOTICE 'after extend(2): % (count=%)', t, t.count;
    t.trim();
    RAISE NOTICE 'after trim(): % (count=%)', t, t.count;
    t.trim(2);
    RAISE NOTICE 'after trim(2): % (count=%)', t, t.count;
    t.delete(t.last);
    RAISE NOTICE 'after delete(last): % (count=%)', t, t.count;
    t.delete();
    RAISE NOTICE 'after delete(): % (count=%)', t, t.count;
END;
$$;

-- DELETE of a non-last, in-range index removes just that element and
-- leaves a hole
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(2);
    RAISE NOTICE 'after delete(2): count=% first=% last=% exists(2)=%',
                 t.count, t.first, t.last, t.exists(2);
END;
$$;

--
-- An explicit NULL argument is a distinct case from an omitted argument
-- and must be rejected, not silently treated as if nothing were passed
-- (e.g. EXTEND(NULL) must not quietly behave like EXTEND()).
--
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.extend(NULL);
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.trim(NULL);
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(NULL);
END;
$$;

-- .EXTEND on a VARRAY enforces the declared limit
DO $$
DECLARE
    TYPE small_arr IS VARRAY(3) OF NUMBER;
    v small_arr := ARRAY[1, 2]::NUMBER[];
BEGIN
    v.extend();
    RAISE NOTICE 'v=%', v;
    v.extend();
END;
$$;

-- collection methods also accept the argument-less form without
-- parentheses, Oracle-style: "t.extend;" means "t.extend();"
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.extend;
    RAISE NOTICE 'count=%', t.count;
END;
$$;

-- an argument still requires parentheses to hold it
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.extend 2;
END;
$$;

-- the bare argument-less form works for .trim and .delete too
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.trim;
    RAISE NOTICE 'count after bare trim=%', t.count;
    t.delete;
    RAISE NOTICE 'count after bare delete=%', t.count;
END;
$$;

--
-- A collection value is one-dimensional.  A multidimensional array can
-- reach a collection variable by assignment (the variable's SQL type,
-- elem[], does not constrain dimensionality), and every operation must
-- reject it rather than describing or rebuilding it from its first
-- dimension alone -- COUNT would be 2, not 4, and EXTEND/TRIM/DELETE would
-- silently flatten it.
--
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    RAISE NOTICE 't.count=%', t.count;
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    RAISE NOTICE 't.first=%', t.first;
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    RAISE NOTICE 't.last=%', t.last;
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    RAISE NOTICE 't(1)=%', t(1);
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    RAISE NOTICE 't.exists(1)=%', t.exists(1);
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    t.extend();
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    t.trim();
END;
$$;

-- DELETE is the most dangerous of these: the index it accepts is the last
-- index of the first dimension, not of the collection
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '{{1,2},{3,4}}'::NUMBER[];
BEGIN
    t.delete(2);
END;
$$;

--
-- A subscript below 1 is rejected by parenthesized indexed assignment
-- outright, regardless of the collection's own current bounds: collection
-- subscripts start at 1, and this syntax has no way to construct one that
-- doesn't.
--
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t(0) := 5;
END;
$$;

--
-- A collection imported from a SQL array with a non-1 lower bound keeps
-- that lower bound rather than being silently renumbered from 1:
-- coll(i)/EXISTS/COUNT/FIRST/LAST/DELETE all read it back, and
-- EXTEND/TRIM/DELETE operate relative to the high-water mark it
-- establishes rather than re-indexing every element.
--
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := '[5:7]={10,20,30}'::NUMBER[];
BEGIN
    RAISE NOTICE 't=% first=% last=% count=%', t, t.first, t.last, t.count;
    t.extend();
    RAISE NOTICE 'after extend: t=% first=% last=% t(8)=%', t, t.first, t.last, t(8);
    t.trim();
    RAISE NOTICE 'after trim:   t=% first=% last=% count=%', t, t.first, t.last, t.count;
    t.delete(t.last);
    RAISE NOTICE 'after delete: t=% first=% last=% count=%', t, t.first, t.last, t.count;
END;
$$;

--
-- Storage ownership.
--
-- A collection variable's authoritative value is an expanded collection
-- held beside var->value, which keeps a densified elem[] cache of it.  The
-- hazards that representation introduces are all about lifetime: one object
-- reachable from two variables, or freed while still referenced.  These
-- cases exercise each of them.  They are ordinary-looking programs on
-- purpose -- a leak or a double free shows up as a crash or as garbage in
-- the output, not as a special-cased error message.
--

-- Self-assignment.  The incoming value is derived from the variable's own
-- collection, so the import has to finish before the old object is freed.
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];
BEGIN
    t := t;
    RAISE NOTICE 'self-assign: t=% count=%', t, t.count;
    t := t;
    RAISE NOTICE 'twice:       t=% count=%', t, t.count;
END;
$$;

-- Assignment from another collection variable must copy, not alias:
-- mutating the source afterwards must not disturb the target.
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    src num_tab := ARRAY[1, 2, 3]::NUMBER[];
    dst num_tab;
BEGIN
    dst := src;
    src(1) := 99;
    src.extend();
    RAISE NOTICE 'src=% count=%', src, src.count;
    RAISE NOTICE 'dst=% count=%', dst, dst.count;
END;
$$;

-- Re-entering a block re-initializes its collection variable.  The previous
-- iteration's object must be released and not carried forward.
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
BEGIN
    FOR i IN 1 .. 3 LOOP
        DECLARE
            t num_tab := ARRAY[i]::NUMBER[];
        BEGIN
            t.extend();
            t(2) := i * 10;
            RAISE NOTICE 'iteration %: t=% count=%', i, t, t.count;
        END;
    END LOOP;
END;
$$;

-- Recursion: each execution gets its own copy of the variable, so each must
-- own its own collection.  Inheriting the caller's pointer would have the
-- inner frame's exit free an object the outer frame still holds, and the
-- outer frame reads its collection again after the recursive call returns.
--
-- A standalone function on purpose: a recursive PACKAGE function with an
-- array-typed local corrupts its frame, which reproduces on f190ad6b072
-- (phase 1) with a plain NUMBER[] local and no collection type in sight.
-- Using a package here would exercise that unrelated bug instead of this
-- one.
CREATE OR REPLACE FUNCTION test_tab_recurse(n NUMBER) RETURN NUMBER IS
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[]::NUMBER[];
    s NUMBER := 0;
BEGIN
    IF n <= 0 THEN
        RETURN 0;
    END IF;
    FOR i IN 1 .. n LOOP
        t.extend();
        t(t.last) := i;
    END LOOP;
    s := test_tab_recurse(n - 1);
    -- read our own collection back after the inner frame has finished
    FOR i IN 1 .. t.count LOOP
        s := s + t(i);
    END LOOP;
    RETURN s;
END;
/

-- 15 + 10 + 6 + 3 + 1
SELECT test_tab_recurse(5);

DROP FUNCTION test_tab_recurse(NUMBER);

-- A package-level collection variable is shared by reference across calls
-- rather than copied per execution, so its object is owned by the package
-- context and must survive between calls.
CREATE OR REPLACE PACKAGE test_tab_pkgvar AS
    TYPE num_tab IS TABLE OF NUMBER;
    acc num_tab := ARRAY[]::NUMBER[];
    PROCEDURE push(v NUMBER);
    FUNCTION dump RETURN num_tab;
END test_tab_pkgvar;
/

CREATE OR REPLACE PACKAGE BODY test_tab_pkgvar AS
    PROCEDURE push(v NUMBER) IS
    BEGIN
        acc.extend();
        acc(acc.last) := v;
    END;

    FUNCTION dump RETURN num_tab IS
    BEGIN
        RETURN acc;
    END;
END test_tab_pkgvar;
/

CALL test_tab_pkgvar.push(1);
CALL test_tab_pkgvar.push(2);
CALL test_tab_pkgvar.push(3);
SELECT test_tab_pkgvar.dump();

DROP PACKAGE test_tab_pkgvar;

-- An IN collection argument is bound by value: the callee gets its own
-- collection, so mutating the parameter must not reach the caller's
-- variable.  Before argument binding was migrated the callee held a bare
-- elem[] here, which happened to give the same answer; now it holds its own
-- object, and this is what says so.
CREATE OR REPLACE FUNCTION test_tab_arg_isolated(t NUMBER[]) RETURN NUMBER IS
    TYPE num_tab IS TABLE OF NUMBER;
    local num_tab := t;
BEGIN
    local(1) := 99;
    local.extend();
    RETURN local.count;
END;
/

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    caller num_tab := ARRAY[1, 2, 3]::NUMBER[];
    n NUMBER;
BEGIN
    n := test_tab_arg_isolated(caller);
    RAISE NOTICE 'callee count=% caller=% count=%', n, caller, caller.count;
END;
$$;

DROP FUNCTION test_tab_arg_isolated(NUMBER[]);

-- Resetting package state must release a package collection variable, not
-- leave the old object attached to a variable that now reads as NULL.
CREATE OR REPLACE PACKAGE test_tab_reset AS
    TYPE num_tab IS TABLE OF NUMBER;
    acc num_tab := ARRAY[7, 8]::NUMBER[];
    FUNCTION peek RETURN NUMBER;
    PROCEDURE bump;
END test_tab_reset;
/

CREATE OR REPLACE PACKAGE BODY test_tab_reset AS
    FUNCTION peek RETURN NUMBER IS
    BEGIN
        RETURN acc.count;
    END;

    PROCEDURE bump IS
    BEGIN
        acc.extend();
    END;
END test_tab_reset;
/

SELECT test_tab_reset.peek() AS before_reset;
CALL test_tab_reset.bump();
SELECT test_tab_reset.peek() AS after_bump;
CALL DBMS_SESSION.RESET_PACKAGE();
SELECT test_tab_reset.peek() AS after_reset;

DROP PACKAGE test_tab_reset;

--
-- Indexed assignment, "coll(i) := value".
--
-- This writes one element through the collection runtime rather than
-- evaluating a whole new elem[] and storing it, so the cases below are
-- about which subscripts it accepts and what it leaves behind when it
-- refuses.
--

-- Updating an index that exists; and the element NULL / index absent
-- distinction that EXTEND creates.
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];
BEGIN
    t(2) := 200;
    RAISE NOTICE 'update:  t=% count=%', t, t.count;

    t.extend();
    RAISE NOTICE 'extended: count=% last=% exists(4)=% t(4) is null=%',
                 t.count, t.last, t.exists(4), t(4) IS NULL;
    -- index 5 is absent, which is not the same as index 4 being NULL
    RAISE NOTICE 'exists(5)=%', t.exists(5);

    t(4) := 400;
    RAISE NOTICE 'filled:  t=% count=%', t, t.count;
END;
$$;

-- Beyond LAST: a nested table cannot be grown by assigning to a subscript
-- it does not have.  Oracle requires EXTEND first.  This also keeps the
-- representation dense, so the still array-backed EXTEND/TRIM adapters
-- cannot silently renumber subscripts around a hole.
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];
BEGIN
    t(5) := 500;
END;
$$;

-- ... and the collection is untouched by the refusal
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];
BEGIN
    BEGIN
        t(5) := 500;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'refused, t=% count=%', t, t.count;
    END;
END;
$$;

-- After DELETE() clears the collection, every subscript is beyond count
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];
BEGIN
    t.delete();
    RAISE NOTICE 'cleared: count=%', t.count;
    t(1) := 1;
END;
$$;

-- Invalid subscripts are rejected as such, ahead of the beyond-count rule
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];
BEGIN
    t(0) := 5;
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];
BEGIN
    t(-1) := 5;
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];
BEGIN
    t(NULL) := 5;
END;
$$;

-- A whole-variable assignment with no right-hand side at all must report a
-- clear error against the source it captured ("t := "), not silently
-- compile an empty expression
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];
BEGIN
    t := ;
END;
$$;

-- coll(i) has no named parameter to address by name; named-argument syntax
-- must fall through to ordinary function resolution and fail cleanly rather
-- than being redirected into a helper whose signature knows nothing about it
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];
    v NUMBER;
BEGIN
    v := t(i => 1);
END;
$$;

-- An uninitialized collection has no element to assign to, whatever the
-- subscript
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab;
BEGIN
    t(1) := 5;
END;
$$;

-- VARRAY: the declared limit bounds the subscript, and is reported as a
-- limit rather than as a count
DO $$
DECLARE
    TYPE num_arr IS VARRAY(3) OF NUMBER;
    v num_arr := ARRAY[1, 2, 3]::NUMBER[];
BEGIN
    v(2) := 20;
    RAISE NOTICE 'varray update: v=%', v;
    v(4) := 40;
END;
$$;

-- A VARRAY subscript can be within the declared limit but still beyond the
-- count, so the two errors have to be distinguishable and correctly
-- ordered: the limit is a property of the type and outranks the count.
DO $$
DECLARE
    TYPE num_arr IS VARRAY(5) OF NUMBER;
    v num_arr := ARRAY[1, 2, 3]::NUMBER[];
BEGIN
    BEGIN
        v(4) := 40;             -- within the limit, past the count
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'v(4): %', SQLERRM;
    END;
    BEGIN
        v(6) := 60;             -- past the limit AND past the count
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'v(6): %', SQLERRM;
    END;
    RAISE NOTICE 'unchanged: v=% count=%', v, v.count;
END;
$$;

-- Failure atomicity.
--
-- Every reachable way for an indexed assignment to fail must leave both
-- COUNT and EXISTS exactly as they were -- including for the subscript that
-- was being written, which must not come into existence as a side effect of
-- the failure.  The three below are the whole reachable set: coercion fails
-- before the runtime is entered, and the subscript and VARRAY-limit checks
-- fail inside it before anything is touched.
--
-- The remaining failure inside plisql_collection_set() is datumCopy()
-- running out of memory, which cannot be provoked from SQL.  It is covered
-- by construction instead: the copy is taken before the entries vector is
-- touched, so that failure cannot leave an element behind either.
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];

    PROCEDURE report(what VARCHAR2) IS
    BEGIN
        RAISE NOTICE '%: t=% count=% exists(2)=% exists(4)=%',
                     what, t, t.count, t.exists(2), t.exists(4);
    END;
BEGIN
    BEGIN
        t(2) := 'not a number';         -- coercion
    EXCEPTION WHEN OTHERS THEN
        report('coercion failed');
    END;

    BEGIN
        t(0) := 5;                      -- invalid subscript
    EXCEPTION WHEN OTHERS THEN
        report('bad subscript');
    END;

    BEGIN
        t(4) := 44;                     -- beyond count
    EXCEPTION WHEN OTHERS THEN
        report('beyond count');
    END;

    -- and the variable is still fully usable afterwards
    t(2) := 22;
    report('after success');
END;
$$;

-- The subscript and the value are ordinary expressions, including ones
-- that read the same collection
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t(t.count) := t(1) + t(2);
    t(t.first + 1) := t(t.last);
    RAISE NOTICE 'self-referencing: t=%', t;
END;
$$;

-- Indexed assignment to a package collection variable persists across calls
CREATE OR REPLACE PACKAGE test_tab_idx_pkg AS
    TYPE num_tab IS TABLE OF NUMBER;
    acc num_tab := ARRAY[0, 0, 0]::NUMBER[];
    PROCEDURE put(i NUMBER, v NUMBER);
    FUNCTION dump RETURN num_tab;
END test_tab_idx_pkg;
/

CREATE OR REPLACE PACKAGE BODY test_tab_idx_pkg AS
    PROCEDURE put(i NUMBER, v NUMBER) IS
    BEGIN
        acc(i) := v;
    END;

    FUNCTION dump RETURN num_tab IS
    BEGIN
        RETURN acc;
    END;
END test_tab_idx_pkg;
/

CALL test_tab_idx_pkg.put(1, 11);
CALL test_tab_idx_pkg.put(3, 33);
SELECT test_tab_idx_pkg.dump();

DROP PACKAGE test_tab_idx_pkg;

--
-- Indexed assignment deliberately leaves the variable's SQL-visible elem[]
-- cache stale, so that a fill loop does not re-densify on every element.
-- Every reader therefore has to refresh it.  These are the distinct reader
-- paths, each exercised after SEVERAL writes so that a reader refreshing
-- only the first one would show up.
--
CREATE OR REPLACE FUNCTION test_idx_sum(t NUMBER[]) RETURN NUMBER IS
BEGIN
    RETURN (SELECT COALESCE(sum(x), 0) FROM unnest(t) AS x);
END;
/

CREATE OR REPLACE FUNCTION test_idx_readers RETURN NUMBER[] IS
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[0, 0, 0, 0]::NUMBER[];
    n NUMBER;
BEGIN
    t(1) := 10;
    t(2) := 20;
    t(3) := 30;
    t(4) := 40;

    -- the whole variable, interpolated
    RAISE NOTICE 'whole:     %', t;
    -- an element read, through the collection path
    RAISE NOTICE 'element:   t(3)=%', t(3);
    -- a collection method
    RAISE NOTICE 'method:    count=% first=% last=%', t.count, t.first, t.last;
    -- an ordinary SQL expression over the variable
    RAISE NOTICE 'sql:       cardinality=%', cardinality(t);
    -- passed to another function as an ordinary array argument
    n := test_idx_sum(t);
    RAISE NOTICE 'argument:  sum=%', n;

    -- more writes, then read again: a cache refreshed once and then left
    -- alone would report the values above
    t(2) := 200;
    t(4) := 400;
    RAISE NOTICE 'rewritten: % sum=%', t, test_idx_sum(t);

    -- and the RETURN path
    RETURN t;
END;
/

SELECT test_idx_readers();

DROP FUNCTION test_idx_readers();
DROP FUNCTION test_idx_sum(NUMBER[]);

-- A field of a composite element is not this statement's shape; it still
-- takes the general assignment path
CREATE TYPE test_idx_point AS (x NUMBER, y NUMBER);

DO $$
DECLARE
    TYPE pt_tab IS TABLE OF test_idx_point;
    t pt_tab := ARRAY[ROW(1, 2)::test_idx_point,
                      ROW(3, 4)::test_idx_point]::test_idx_point[];
BEGIN
    t(1).x := 99;
    RAISE NOTICE 'composite field: t=%', t;
    -- ... and a plain indexed assignment on the same variable still takes
    -- the collection path
    t(2) := ROW(7, 8)::test_idx_point;
    RAISE NOTICE 'whole element:   t=% count=%', t, t.count;
END;
$$;

DROP TYPE test_idx_point;

--
-- EXTEND, TRIM and DELETE() now call the runtime directly rather than
-- compiling to "coll := helper(coll, n)".  The count is therefore an
-- ordinary PL/iSQL expression evaluated on its own, which it was not
-- before -- including when it reads the very collection about to be
-- mutated.  It is evaluated to completion first, so it sees the collection
-- as it was.
--
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3]::NUMBER[];
    n NUMBER := 2;
BEGIN
    t.extend(t.count);          -- 3 -> 6
    RAISE NOTICE 'extend(count):  count=% last=% t=%', t.count, t.last, t;

    t.trim(t.count - n * 2);    -- trim 2 -> 4
    RAISE NOTICE 'trim(expr):     count=% last=% t=%', t.count, t.last, t;

    t.extend(n);                -- a plain variable
    RAISE NOTICE 'extend(var):    count=% last=%', t.count, t.last;

    t.trim(t.count);            -- trims everything, leaving it initialized
    RAISE NOTICE 'trim(count):    count=% t=%', t.count, t;

    -- still initialized, so EXTEND works and COUNT does not raise
    t.extend();
    RAISE NOTICE 'after empty:    count=% t(1) is null=%', t.count, t(1) IS NULL;
END;
$$;

-- Reading the collection inside a subscript expression, while holding a
-- borrowed read-only reference to it
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    RAISE NOTICE 'nested reads: t(t.count)=% t(t.first)=% exists(t.last)=%',
                 t(t.count), t(t.first), t.exists(t.last);
END;
$$;

-- Every mutation on an uninitialized collection raises the same error,
-- whichever method and whether or not a count was written.  The DETAIL
-- names the method that actually touched the collection, which for a count
-- expression that reads the collection itself is that read -- it is
-- evaluated first, and it genuinely is what referenced the uninitialized
-- value.  The condition raised is the same either way.
DO $$ DECLARE TYPE nt IS TABLE OF NUMBER; t nt; BEGIN t.extend(); END; $$;
DO $$ DECLARE TYPE nt IS TABLE OF NUMBER; t nt; BEGIN t.extend(2); END; $$;
DO $$ DECLARE TYPE nt IS TABLE OF NUMBER; t nt; BEGIN t.trim(); END; $$;
DO $$ DECLARE TYPE nt IS TABLE OF NUMBER; t nt; BEGIN t.trim(2); END; $$;
DO $$ DECLARE TYPE nt IS TABLE OF NUMBER; t nt; BEGIN t.delete(); END; $$;
DO $$ DECLARE TYPE nt IS TABLE OF NUMBER; t nt; BEGIN t.extend(t.count); END; $$;
DO $$ DECLARE TYPE nt IS TABLE OF NUMBER; t nt; BEGIN t.trim(t.count); END; $$;
DO $$ DECLARE TYPE nt IS TABLE OF NUMBER; t nt; BEGIN t(1) := 5; END; $$;

-- ... and they are all the same SQLSTATE, so a handler catches them alike
DO $$
DECLARE
    TYPE nt IS TABLE OF NUMBER;
    t nt;
    caught INTEGER := 0;
BEGIN
    BEGIN t.extend();       EXCEPTION WHEN OTHERS THEN caught := caught + 1; END;
    BEGIN t.trim();         EXCEPTION WHEN OTHERS THEN caught := caught + 1; END;
    BEGIN t.delete();       EXCEPTION WHEN OTHERS THEN caught := caught + 1; END;
    BEGIN t.extend(t.count);EXCEPTION WHEN OTHERS THEN caught := caught + 1; END;
    BEGIN t(1) := 5;        EXCEPTION WHEN OTHERS THEN caught := caught + 1; END;
    RAISE NOTICE 'caught % of 5, t is still null=%', caught, t IS NULL;
END;
$$;

--
-- Sparse nested tables: DELETE(i), NEXT and PRIOR.
--
-- This is the defining behavior of an Oracle nested table and the reason
-- the collection runtime is a sorted entry vector rather than an array.
-- DELETE(i) removes one element and leaves a HOLE; the surviving elements
-- keep their own subscripts rather than being renumbered, and NEXT/PRIOR
-- traverse across the gap.
--
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(2);

    RAISE NOTICE 'exists: 1=% 2=% 3=%', t.exists(1), t.exists(2), t.exists(3);
    RAISE NOTICE 'count=% first=% last=%', t.count, t.first, t.last;
    RAISE NOTICE 'next:  next(1)=% next(2)=%', t.next(1), t.next(2);
    RAISE NOTICE 'prior: prior(3)=% prior(2)=%', t.prior(3), t.prior(2);

    -- the surviving elements keep their values at their original subscripts
    RAISE NOTICE 'values: t(1)=% t(3)=%', t(1), t(3);
END;
$$;

-- Boundaries: NEXT off the end and PRIOR off the front are NULL, not errors
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    RAISE NOTICE 'next(3)=% prior(1)=%',
                 COALESCE(t.next(3)::TEXT, 'NULL'),
                 COALESCE(t.prior(1)::TEXT, 'NULL');
    -- and off the ends of the subscript range entirely
    RAISE NOTICE 'next(99)=% prior(0)=%',
                 COALESCE(t.next(99)::TEXT, 'NULL'),
                 COALESCE(t.prior(0)::TEXT, 'NULL');
END;
$$;

-- An initialized but empty collection: traversal yields NULL, and that is
-- still distinct from an atomically NULL one, which raises
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := num_tab();
BEGIN
    RAISE NOTICE 'empty: count=% first=% next(1)=% prior(1)=%',
                 t.count,
                 COALESCE(t.first::TEXT, 'NULL'),
                 COALESCE(t.next(1)::TEXT, 'NULL'),
                 COALESCE(t.prior(1)::TEXT, 'NULL');
END;
$$;

DO $$ DECLARE TYPE nt IS TABLE OF NUMBER; t nt; BEGIN
    RAISE NOTICE '%', t.next(1); END; $$;

DO $$ DECLARE TYPE nt IS TABLE OF NUMBER; t nt; BEGIN
    RAISE NOTICE '%', t.prior(1); END; $$;

-- Walking a collection with several holes, which is what NEXT is for
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[1, 2, 3, 4, 5, 6]::NUMBER[];
    i INTEGER;
    acc VARCHAR2(100) := '';
BEGIN
    t.delete(2);
    t.delete(3);
    t.delete(5);

    i := t.first;
    WHILE i IS NOT NULL LOOP
        acc := acc || i || '=' || t(i) || ' ';
        i := t.next(i);
    END LOOP;
    RAISE NOTICE 'forward:  % (count=%)', acc, t.count;

    acc := '';
    i := t.last;
    WHILE i IS NOT NULL LOOP
        acc := acc || i || '=' || t(i) || ' ';
        i := t.prior(i);
    END LOOP;
    RAISE NOTICE 'backward: %', acc;
END;
$$;

-- Reading a deleted element is NO_DATA_FOUND, not NULL: an absent index is
-- not the same as an element whose value is NULL.  This has to hold for the
-- FIRST and LAST elements too, not just an interior one -- the surviving
-- entries cannot tell a deleted boundary element from one that was never
-- there, which is what the collection's high-water mark records.
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(2);
    RAISE NOTICE 'reading t(2)';
    RAISE NOTICE '%', t(2);
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(1);                        -- the first element
    RAISE NOTICE 'after delete(1): count=% first=% exists(1)=%',
                 t.count, t.first, t.exists(1);
    RAISE NOTICE '%', t(1);
END;
$$;

DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(3);                        -- the last element
    RAISE NOTICE 'after delete(3): count=% last=% exists(3)=%',
                 t.count, t.last, t.exists(3);
    RAISE NOTICE '%', t(3);
END;
$$;

-- A subscript that was never allocated is out of bounds, not a hole --
-- that is the distinction the high-water mark exists to preserve
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(3);
    RAISE NOTICE 'reading t(4), never allocated';
    RAISE NOTICE '%', t(4);
END;
$$;

-- TRIM puts subscripts back out of bounds; DELETE(i) does not
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.trim();                           -- 3 is gone, and beyond the collection
    RAISE NOTICE 'after trim: count=%', t.count;
    RAISE NOTICE '%', t(3);
END;
$$;

-- ... and clearing it puts every subscript back out of bounds
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(2);
    t.delete();
    RAISE NOTICE 'after delete(): count=%', t.count;
    RAISE NOTICE '%', t(2);
END;
$$;

-- The distinction survives a transfer to another collection variable
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    src num_tab := ARRAY[10, 20, 30]::NUMBER[];
    dst num_tab;
BEGIN
    src.delete(3);
    dst := src;
    RAISE NOTICE 'copied, reading dst(3)';
    RAISE NOTICE '%', dst(3);
END;
$$;

-- EXTEND appends after the high-water mark, not after the last survivor
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(3);
    t.extend();
    RAISE NOTICE 'extend after boundary delete: count=% exists(3)=% exists(4)=% next(2)=%',
                 t.count, t.exists(3), t.exists(4), t.next(2);
END;
$$;

-- Assigning into a hole is refused, and distinguishably from a subscript
-- that is merely beyond the count: EXTEND appends after the allocated
-- range, deleted elements included, so it can never make a deleted
-- subscript assignable again and must not be suggested here.
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(2);
    t(2) := 5;
END;
$$;

-- the interior hole is refused above; a subscript past the end still gets
-- the EXTEND advice, because there it does work
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(2);
    t(4) := 5;
END;
$$;

-- and EXTEND really does work for that one, landing past the hole
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(2);
    t.extend();
    t(4) := 44;
    RAISE NOTICE 'count=% exists(2)=% t(4)=% next(1)=%',
                 t.count, t.exists(2), t(4), t.next(1);
END;
$$;

-- a deleted LAST element is likewise not reusable, which is the case the
-- surviving entries alone could not tell from "beyond the count"
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(3);
    t(3) := 5;
END;
$$;

-- DELETE(i) of an index that is not present is a no-op, including one
-- already deleted
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(2);
    t.delete(2);                -- again
    RAISE NOTICE 'count=% first=% last=%', t.count, t.first, t.last;
END;
$$;

-- DELETE(i) is not allowed on a VARRAY: it is dense by definition and has
-- no way to represent the hole
DO $$
DECLARE
    TYPE num_arr IS VARRAY(5) OF NUMBER;
    v num_arr := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    v.delete(2);
END;
$$;

-- ... but the argument-less DELETE clears one, and TRIM still works
DO $$
DECLARE
    TYPE num_arr IS VARRAY(5) OF NUMBER;
    v num_arr := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    v.trim();
    RAISE NOTICE 'varray trim:   count=%', v.count;
    v.delete();
    RAISE NOTICE 'varray delete: count=% v=%', v.count, v;
END;
$$;

-- Holes survive the operations that used to densify them away: EXTEND and
-- TRIM no longer round-trip the collection through elem[]
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(2);
    t.extend();
    RAISE NOTICE 'after extend: count=% last=% exists(2)=% next(1)=%',
                 t.count, t.last, t.exists(2), t.next(1);
    t.trim();
    RAISE NOTICE 'after trim:   count=% last=% exists(2)=%',
                 t.count, t.last, t.exists(2);
END;
$$;

-- A hole also survives assignment to another collection variable, and the
-- SQL-visible form densifies (which is the documented boundary behavior)
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    src num_tab := ARRAY[10, 20, 30]::NUMBER[];
    dst num_tab;
BEGIN
    src.delete(2);
    dst := src;
    RAISE NOTICE 'copy:  count=% exists(2)=% next(1)=%',
                 dst.count, dst.exists(2), dst.next(1);
    RAISE NOTICE 'as sql: %', dst;
END;
$$;

-- Self-assignment of a collection holding a hole: the copy has to be taken
-- while the source is still intact, because for "t := t" the source IS the
-- object about to be replaced
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    t num_tab := ARRAY[10, 20, 30]::NUMBER[];
BEGIN
    t.delete(2);
    t := t;
    RAISE NOTICE 'self:  count=% exists(2)=% next(1)=% t(3)=%',
                 t.count, t.exists(2), t.next(1), t(3);
    t := t;
    RAISE NOTICE 'twice: count=% exists(2)=%', t.count, t.exists(2);
END;
$$;

-- The copy is a copy: mutating the source afterwards must not disturb the
-- target, including the holes
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    src num_tab := ARRAY[10, 20, 30]::NUMBER[];
    dst num_tab;
BEGIN
    src.delete(2);
    dst := src;
    src.delete(3);
    RAISE NOTICE 'src: count=% exists(3)=%', src.count, src.exists(3);
    RAISE NOTICE 'dst: count=% exists(3)=% next(1)=%',
                 dst.count, dst.exists(3), dst.next(1);
END;
$$;

-- An assignment whose source is not simply another collection variable is
-- a SQL value, and densifying it there is the documented boundary
DO $$
DECLARE
    TYPE num_tab IS TABLE OF NUMBER;
    src num_tab := ARRAY[10, 20, 30]::NUMBER[];
    dst num_tab;
BEGIN
    src.delete(2);
    dst := src || ARRAY[40]::NUMBER[];   -- an expression, not a transfer
    RAISE NOTICE 'expr: count=% exists(2)=% dst=%',
                 dst.count, dst.exists(2), dst;
END;
$$;

-- Transfer into and out of a package collection variable keeps the hole
CREATE OR REPLACE PACKAGE test_tab_sparse_pkg AS
    TYPE num_tab IS TABLE OF NUMBER;
    acc num_tab := ARRAY[10, 20, 30]::NUMBER[];
    PROCEDURE punch;
    FUNCTION shape RETURN VARCHAR2;
END test_tab_sparse_pkg;
/

CREATE OR REPLACE PACKAGE BODY test_tab_sparse_pkg AS
    PROCEDURE punch IS
    BEGIN
        acc.delete(2);
    END;

    FUNCTION shape RETURN VARCHAR2 IS
        local num_tab;
    BEGIN
        local := acc;
        RETURN 'count=' || local.count ||
               ' exists(2)=' || CASE WHEN local.exists(2) THEN 'y' ELSE 'n' END ||
               ' next(1)=' || local.next(1);
    END;
END test_tab_sparse_pkg;
/

CALL test_tab_sparse_pkg.punch();
SELECT test_tab_sparse_pkg.shape();

DROP PACKAGE test_tab_sparse_pkg;

-- session and package cache must stay usable after all of the above errors
SELECT 1 AS session_still_usable_after_phase2_errors;
