--
-- CREATE_TYPE
--

-- directory path and dlsuffix are passed to us in environment variables
\getenv libdir PG_LIBDIR
\getenv dlsuffix PG_DLSUFFIX

\set regresslib :libdir '/oraregress' :dlsuffix

--
-- Test the "old style" approach of making the I/O functions first,
-- with no explicit shell type creation.
--
CREATE FUNCTION widget_in(cstring)
   RETURNS widget
   AS :'regresslib'
   LANGUAGE C STRICT IMMUTABLE;
/

CREATE FUNCTION widget_out(widget)
   RETURNS cstring
   AS :'regresslib'
   LANGUAGE C STRICT IMMUTABLE;
/

CREATE FUNCTION int44in(cstring)
   RETURNS city_budget
   AS :'regresslib'
   LANGUAGE C STRICT IMMUTABLE;
/

CREATE FUNCTION int44out(city_budget)
   RETURNS cstring
   AS :'regresslib'
   LANGUAGE C STRICT IMMUTABLE;
/

CREATE TYPE widget (
   internallength = 24,
   input = widget_in,
   output = widget_out,
   typmod_in = numerictypmodin,
   typmod_out = numerictypmodout,
   alignment = double
);

CREATE TYPE city_budget (
   internallength = 16,
   input = int44in,
   output = int44out,
   element = int4,
   category = 'x',   -- just to verify the system will take it
   preferred = true  -- ditto
);

-- Test creation and destruction of shell types
CREATE TYPE shell;
CREATE TYPE shell;   -- fail, type already present
DROP TYPE shell;
DROP TYPE shell;     -- fail, type not exist

-- also, let's leave one around for purposes of pg_dump testing
CREATE TYPE myshell;

--
-- Test type-related default values (broken in releases before PG 7.2)
--
-- This part of the test also exercises the "new style" approach of making
-- a shell type and then filling it in.
--
CREATE TYPE int42;
CREATE TYPE text_w_default;

-- Make dummy I/O routines using the existing internal support for int4, text
CREATE FUNCTION int42_in(cstring)
   RETURNS int42
   AS 'int4in'
   LANGUAGE internal STRICT IMMUTABLE;
/
CREATE FUNCTION int42_out(int42)
   RETURNS cstring
   AS 'int4out'
   LANGUAGE internal STRICT IMMUTABLE;
/
CREATE FUNCTION text_w_default_in(cstring)
   RETURNS text_w_default
   AS 'textin'
   LANGUAGE internal STRICT IMMUTABLE;
/
CREATE FUNCTION text_w_default_out(text_w_default)
   RETURNS cstring
   AS 'textout'
   LANGUAGE internal STRICT IMMUTABLE;
/

CREATE TYPE int42 (
   internallength = 4,
   input = int42_in,
   output = int42_out,
   alignment = int4,
   default = 42,
   passedbyvalue
);

CREATE TYPE text_w_default (
   internallength = variable,
   input = text_w_default_in,
   output = text_w_default_out,
   alignment = int4,
   default = 'zippo'
);

CREATE TABLE default_test (f1 text_w_default, f2 int42);

INSERT INTO default_test DEFAULT VALUES;

SELECT * FROM default_test;

-- We need a shell type to test some CREATE TYPE failure cases with
CREATE TYPE bogus_type;

-- invalid: non-lowercase quoted identifiers
CREATE TYPE bogus_type (
	"Internallength" = 4,
	"Input" = int42_in,
	"Output" = int42_out,
	"Alignment" = int4,
	"Default" = 42,
	"Passedbyvalue"
);

-- invalid: input/output function incompatibility
CREATE TYPE bogus_type (INPUT = array_in,
    OUTPUT = array_out,
    ELEMENT = int,
    INTERNALLENGTH = 32);

DROP TYPE bogus_type;

-- It no longer is possible to issue CREATE TYPE without making a shell first
CREATE TYPE bogus_type (INPUT = array_in,
    OUTPUT = array_out,
    ELEMENT = int,
    INTERNALLENGTH = 32);

-- Test stand-alone composite type

CREATE TYPE default_test_row AS (f1 text_w_default, f2 int42);

-- Oracle-style AS OBJECT creates a composite-backed object type.
CREATE TYPE oracle_object_type AS OBJECT
(
	id integer,
	label varchar(20)
);

-- Oracle object types provide a system-defined attribute-value constructor.
SELECT oracle_object_type(1, 'one') FROM dual;

-- Standalone routines share Oracle's schema namespace with object types.
CREATE FUNCTION oracle_object_type(p_id integer, p_label varchar2)
RETURN oracle_object_type
IS
BEGIN
    RETURN NULL;
END;
/

-- Without MAP or ORDER, object values support equality but not ordering.
SELECT oracle_object_type(1, 'one') = oracle_object_type(1, 'one') FROM dual;
SELECT oracle_object_type(1, 'one') < oracle_object_type(2, 'two') FROM dual;
SELECT objects.v
FROM (SELECT oracle_object_type(1, 'one') v FROM dual) objects
ORDER BY objects.v;
SELECT objects.v
FROM
(
    SELECT oracle_object_type(1, 'one') v FROM dual
    UNION ALL
    SELECT oracle_object_type(2, 'two') v FROM dual
) objects
ORDER BY objects.v;

-- Constructor arguments are coerced to their declared attribute types.
SELECT oracle_object_type('2', 'two') FROM dual;

-- An unrelated standalone function is not an object member method.
CREATE FUNCTION object_label(p_value oracle_object_type)
RETURN varchar2
IS
BEGIN
    RETURN p_value.label;
END;
/

SELECT objects.value.object_label()
FROM (SELECT oracle_object_type(1, 'one') value FROM dual) objects;

-- IvorySQL catalog integration (not an Oracle data-dictionary query).
SELECT typisobject FROM pg_type WHERE typname = 'oracle_object_type';

DROP FUNCTION object_label;
DROP TYPE oracle_object_type;

-- The namespace conflict is symmetric when the standalone routine exists first.
CREATE FUNCTION object_type_name_conflict RETURN integer
IS
BEGIN
    RETURN 1;
END;
/
CREATE TYPE object_type_name_conflict AS OBJECT (id integer);
DROP FUNCTION object_type_name_conflict;

-- Object types and ordinary packages share the hidden method namespace.
CREATE PACKAGE object_type_package_conflict IS
END;
/
CREATE TYPE object_type_package_conflict AS OBJECT (id integer);
DROP PACKAGE object_type_package_conflict;

-- Object method specifications, bodies, implicit SELF, and attribute names.
CREATE OR REPLACE TYPE person_object_type AS OBJECT
(
    first_name varchar2(20),
    last_name varchar2(20),
    birth_year integer,
    MEMBER FUNCTION full_name RETURN varchar2,
    MEMBER FUNCTION age_in(p_year integer DEFAULT 2026) RETURN integer
) NOT FINAL;
/

CREATE OR REPLACE TYPE BODY person_object_type AS
    MEMBER FUNCTION full_name RETURN varchar2 AS
    BEGIN
        RETURN first_name || ' ' || last_name;
    END full_name;

    MEMBER FUNCTION age_in(p_year integer) RETURN integer IS
    BEGIN
        RETURN p_year - self.birth_year;
    END age_in;
END;
/

SELECT v.p.full_name(), v.p.age_in(2026)
FROM (SELECT person_object_type('Ada', 'Lovelace', 1815) p FROM dual) v;
SELECT v.p.age_in()
FROM (SELECT person_object_type('Ada', 'Lovelace', 1815) p FROM dual) v;
SELECT v.p.age_in(p_year => 2020)
FROM (SELECT person_object_type('Ada', 'Lovelace', 1815) p FROM dual) v;

-- Qualified object columns retain member-call semantics.
CREATE TABLE person_object_table (object_value person_object_type);
INSERT INTO person_object_table
VALUES (person_object_type('Grace', 'Hopper', 1906));
SELECT t.object_value.full_name() FROM person_object_table t;
-- IvorySQL-specific schema qualification through a relation name.
SELECT public.person_object_table.object_value.full_name()
FROM public.person_object_table;
DROP TABLE person_object_table;

-- IvorySQL catalog integration for the hidden method package.
SELECT pkgtypeoid = 'person_object_type'::regtype,
       pkginstantiable,
       pkgfinal
FROM pg_package
WHERE pkgname = 'person_object_type';

CREATE OR REPLACE TYPE person_object_type AS OBJECT
(
    first_name varchar2(20),
    last_name varchar2(20),
    birth_year integer,
    MEMBER FUNCTION full_name RETURN varchar2,
    MEMBER FUNCTION age_in(p_year integer DEFAULT 2026) RETURN integer
) NOT FINAL;
/
SELECT v.p.full_name()
FROM (SELECT person_object_type('Ada', 'Lovelace', 1815) p FROM dual) v;

CREATE OR REPLACE TYPE person_object_type AS OBJECT
(
    first_name varchar2(30),
    last_name varchar2(20),
    birth_year integer,
    MEMBER FUNCTION full_name RETURN varchar2,
    MEMBER FUNCTION age_in(p_year integer DEFAULT 2026) RETURN integer
) NOT FINAL;
/
SELECT v.p.full_name()
FROM (SELECT person_object_type('Ada', 'Lovelace', 1815) p FROM dual) v;

DROP TYPE person_object_type;

-- CREATE OR REPLACE can evolve attributes when stored dependencies allow it.
CREATE TYPE evolving_object_type AS OBJECT (id integer);
CREATE OR REPLACE TYPE evolving_object_type AS OBJECT
(
    id integer,
    label varchar2(10)
);
/
SELECT evolving_object_type(7, 'seven') FROM dual;
CREATE OR REPLACE TYPE evolving_object_type AS OBJECT
(
    renamed_id varchar2(20)
);
/
SELECT evolving_object_type('renamed') FROM dual;
DROP TYPE evolving_object_type;

-- Stored dependents prevent replacement, matching Oracle's ORA-02303 rule.
CREATE TYPE dependent_object_type AS OBJECT (id integer);
CREATE TABLE dependent_object_table (object_value dependent_object_type);
CREATE OR REPLACE TYPE dependent_object_type AS OBJECT (id integer);
/
CREATE OR REPLACE TYPE dependent_object_type AS OBJECT
(
    id integer,
    label varchar2(10)
);
/
DROP TABLE dependent_object_table;
DROP TYPE dependent_object_type;

-- Constructors, static functions, and mutating member procedures.
CREATE TYPE feature_object_type AS OBJECT
(
    value integer,
    label varchar2(20),
    CONSTRUCTOR FUNCTION feature_object_type(p_value integer, p_label varchar2)
        RETURN SELF AS RESULT,
    MEMBER FUNCTION describe RETURN varchar2,
    MEMBER PROCEDURE bump(delta integer),
    STATIC FUNCTION decorate(p_text varchar2) RETURN varchar2,
    STATIC PROCEDURE increment_value(p_value IN OUT integer)
);
/

CREATE TYPE BODY feature_object_type AS
    CONSTRUCTOR FUNCTION feature_object_type(p_value integer, p_label varchar2)
        RETURN SELF AS RESULT IS
    BEGIN
        self.value := p_value + 100;
        self.label := p_label;
        RETURN;
    END feature_object_type;

    MEMBER FUNCTION describe RETURN varchar2 IS
    BEGIN
        RETURN label || ':' || self.value;
    END describe;

    MEMBER PROCEDURE bump(delta integer) IS
    BEGIN
        self.value := self.value + delta;
    END bump;

    STATIC FUNCTION decorate(p_text varchar2) RETURN varchar2 IS
    BEGIN
        RETURN '[' || p_text || ']';
    END decorate;

    STATIC PROCEDURE increment_value(p_value IN OUT integer) IS
    BEGIN
        p_value := p_value + 1;
    END increment_value;
END;
/

SELECT feature_object_type(1, 'one'),
       feature_object_type.decorate('static')
FROM dual;
SELECT feature_object_type(p_label => 'named', p_value => 8) FROM dual;
SELECT objects.v.describe()
FROM (SELECT feature_object_type(2, 'two') v FROM dual) objects;

DECLARE
    v feature_object_type := feature_object_type(3, 'three');
	n integer := 10;
BEGIN
    v.bump(4);
	feature_object_type.increment_value(n);
    IF v.value <> 107 THEN
		RAISE EXCEPTION 'unexpected member procedure result';
    END IF;
	IF n <> 11 THEN
		RAISE EXCEPTION 'unexpected static procedure result';
	END IF;
END;
/

-- Keep a same-named STANDARD routine visible while compiling the object.  A
-- failed package-type probe must fall back to the schema object type.
BEGIN;
CREATE OR REPLACE PACKAGE sys.standard IS
    FUNCTION type_probe_function_collision() RETURN integer;
    PROCEDURE type_probe_procedure_collision();
    FUNCTION fallback_arity_probe(p_value integer) RETURN integer;
    fallback_kind_probe integer;
    type_probe_variable_collision integer;
END;
/

-- Optional STANDARD routine probes must continue into the schema namespace
-- when a same-named package item has the wrong signature or the wrong kind.
CREATE FUNCTION fallback_arity_probe(p_left integer, p_right integer)
RETURN integer
IS
BEGIN
    RETURN p_left + p_right;
END;
/

CREATE FUNCTION fallback_kind_probe(p_value integer)
RETURN integer
IS
BEGIN
    RETURN p_value;
END;
/

DECLARE
    value integer;
BEGIN
    value := fallback_arity_probe(10, 20);
    IF value <> 30 THEN
        RAISE EXCEPTION 'unexpected arity fallback result';
    END IF;

    value := fallback_kind_probe(40);
    IF value <> 40 THEN
        RAISE EXCEPTION 'unexpected kind fallback result';
    END IF;
END;
/

CREATE TYPE type_probe_function_collision AS OBJECT
(
    value integer,
    CONSTRUCTOR FUNCTION type_probe_function_collision RETURN SELF AS RESULT,
    STATIC FUNCTION new_instance RETURN type_probe_function_collision
);
/

CREATE TYPE type_probe_procedure_collision AS OBJECT
(
    value integer,
    CONSTRUCTOR FUNCTION type_probe_procedure_collision RETURN SELF AS RESULT,
    STATIC FUNCTION new_instance RETURN type_probe_procedure_collision
);
/

-- A same-named STANDARD variable is not the return datatype of an object
-- method; type resolution must continue into the schema namespace.
CREATE TYPE type_probe_variable_collision AS OBJECT
(
    value integer,
    STATIC FUNCTION new_instance(p_value integer)
        RETURN type_probe_variable_collision
);
/

CREATE TYPE BODY type_probe_variable_collision AS
    STATIC FUNCTION new_instance(p_value integer)
        RETURN type_probe_variable_collision IS
    BEGIN
        RETURN type_probe_variable_collision(p_value);
    END new_instance;
END;
/

SELECT type_probe_variable_collision.new_instance(42) FROM dual;

-- Explicit package qualification is not a fallback probe and must still
-- report that a routine is not a package type.
SAVEPOINT explicit_package_probe;
DECLARE
    value standard.type_probe_function_collision;
BEGIN
    NULL;
END;
/
ROLLBACK TO SAVEPOINT explicit_package_probe;

DECLARE
    value standard.type_probe_procedure_collision;
BEGIN
    NULL;
END;
/
ROLLBACK;

-- Object constructors remain callable from static methods.  The constructor's
-- hidden SELF argument must not participate in the source-level call.
CREATE TYPE factory_object_type AS OBJECT
(
    value integer,
    label varchar2(20),
    CONSTRUCTOR FUNCTION factory_object_type RETURN SELF AS RESULT,
    STATIC FUNCTION new_instance(p_value integer, p_label varchar2)
        RETURN factory_object_type
);
/

CREATE TYPE BODY factory_object_type AS
    CONSTRUCTOR FUNCTION factory_object_type RETURN SELF AS RESULT IS
    BEGIN
        self.value := -1;
        self.label := 'default';
        RETURN;
    END factory_object_type;

    STATIC FUNCTION new_instance(p_value integer, p_label varchar2)
        RETURN factory_object_type IS
        result factory_object_type;
    BEGIN
        result := factory_object_type();
        result.value := p_value;
        result.label := p_label;
        RETURN result;
    END new_instance;
END;
/

SELECT factory_object_type() FROM dual;
SELECT factory_object_type.new_instance(1, 'one') FROM dual;
DROP TYPE factory_object_type;

-- Constructor lookup remains correct for overloads, default arguments, and
-- named notation when invoked from a static method.
CREATE TYPE overloaded_constructor_type AS OBJECT
(
    value integer,
    label varchar2(20),
    CONSTRUCTOR FUNCTION overloaded_constructor_type RETURN SELF AS RESULT,
    CONSTRUCTOR FUNCTION overloaded_constructor_type(
        p_value integer, p_label varchar2 DEFAULT 'default')
        RETURN SELF AS RESULT,
    STATIC FUNCTION make_default(p_value integer)
        RETURN overloaded_constructor_type,
    STATIC FUNCTION make_named(p_value integer, p_label varchar2)
        RETURN overloaded_constructor_type
);
/

CREATE TYPE BODY overloaded_constructor_type AS
    CONSTRUCTOR FUNCTION overloaded_constructor_type RETURN SELF AS RESULT IS
    BEGIN
        self.value := -1;
        self.label := 'empty';
        RETURN;
    END overloaded_constructor_type;

    CONSTRUCTOR FUNCTION overloaded_constructor_type(
        p_value integer, p_label varchar2)
        RETURN SELF AS RESULT IS
    BEGIN
        self.value := p_value;
        self.label := p_label;
        RETURN;
    END overloaded_constructor_type;

    STATIC FUNCTION make_default(p_value integer)
        RETURN overloaded_constructor_type IS
    BEGIN
        RETURN overloaded_constructor_type(p_value);
    END make_default;

    STATIC FUNCTION make_named(p_value integer, p_label varchar2)
        RETURN overloaded_constructor_type IS
    BEGIN
        RETURN overloaded_constructor_type(
            p_label => p_label, p_value => p_value);
    END make_named;
END;
/

SELECT overloaded_constructor_type() FROM dual;
SELECT overloaded_constructor_type(7) FROM dual;
SELECT overloaded_constructor_type(
    p_label => 'named', p_value => 9) FROM dual;
SELECT overloaded_constructor_type.make_default(11) FROM dual;
SELECT overloaded_constructor_type.make_named(13, 'thirteen') FROM dual;
SELECT overloaded_constructor_type(1, 'one', 3) FROM dual;
DROP TYPE overloaded_constructor_type;

-- Quoted identifiers and schema-qualified object return types compile correctly.
CREATE SCHEMA object_type_corner;
CREATE TYPE object_type_corner."QuotedFactoryType" AS OBJECT
(
    value integer,
    CONSTRUCTOR FUNCTION "QuotedFactoryType" RETURN SELF AS RESULT,
    STATIC FUNCTION new_instance
        RETURN object_type_corner."QuotedFactoryType"
);
/
DROP TYPE object_type_corner."QuotedFactoryType";
DROP SCHEMA object_type_corner;

-- Oracle constructors reject RETURN expressions, including RETURN SELF.
CREATE TYPE invalid_constructor_return_type AS OBJECT
(
    value integer,
    CONSTRUCTOR FUNCTION invalid_constructor_return_type(p_value integer)
        RETURN SELF AS RESULT
);
/
CREATE TYPE BODY invalid_constructor_return_type AS
    CONSTRUCTOR FUNCTION invalid_constructor_return_type(p_value integer)
        RETURN SELF AS RESULT IS
    BEGIN
        self.value := p_value;
        RETURN self;
    END invalid_constructor_return_type;
END;
/
DROP TYPE invalid_constructor_return_type;

-- Object methods use TYPE privileges, not the hidden package ACL.
CREATE ROLE object_type_user;
REVOKE ALL ON TYPE feature_object_type FROM PUBLIC;
SET ROLE object_type_user;
SELECT feature_object_type.decorate('denied');
RESET ROLE;
GRANT USAGE ON TYPE feature_object_type TO object_type_user;
SET ROLE object_type_user;
SELECT feature_object_type.decorate('allowed');
RESET ROLE;
REVOKE USAGE ON TYPE feature_object_type FROM object_type_user;
DROP ROLE object_type_user;

-- The hidden method namespace follows type ownership.
CREATE ROLE object_type_owner;
ALTER TYPE feature_object_type OWNER TO object_type_owner;
SELECT t.typowner = p.pkgowner AS owners_match
FROM pg_type AS t
JOIN pg_package AS p ON p.pkgtypeoid = t.oid
WHERE t.typname = 'feature_object_type';
ALTER TYPE feature_object_type OWNER TO CURRENT_USER;
DROP ROLE object_type_owner;

-- PostgreSQL-only rename/schema moves are rejected rather than desynchronizing
-- the compiled Oracle method contract.
ALTER TYPE feature_object_type RENAME TO renamed_feature_object_type;
CREATE SCHEMA object_type_target;
ALTER TYPE feature_object_type SET SCHEMA object_type_target;
DROP SCHEMA object_type_target;

DROP TYPE feature_object_type;

-- MAP methods define equality and ordering through a scalar key.
CREATE TYPE map_object_type AS OBJECT
(
    value integer,
    label varchar2(20),
    MAP MEMBER FUNCTION sort_key RETURN integer
);
/

CREATE TYPE BODY map_object_type AS
    MAP MEMBER FUNCTION sort_key RETURN integer IS
    BEGIN
        RETURN mod(self.value, 10);
    END sort_key;
END;
/

SELECT map_object_type(11, 'z') = map_object_type(1, 'a') AS map_equal,
       map_object_type(2, 'z') < map_object_type(9, 'a') AS map_less
FROM dual;
CREATE TABLE map_object_index_test
(
    id integer,
    value map_object_type
);
INSERT INTO map_object_index_test VALUES
    (11, map_object_type(11, 'eleven')),
    (2, map_object_type(2, 'two')),
    (9, map_object_type(9, 'nine'));
CREATE INDEX map_object_value_idx ON map_object_index_test (value);
SET ivorysql.compatible_mode = pg;
SET enable_seqscan = off;
SELECT id
FROM map_object_index_test
WHERE value = ROW(1, 'probe')::map_object_type
ORDER BY id;
REINDEX INDEX map_object_value_idx;
SET ivorysql.compatible_mode = oracle;
SELECT id FROM map_object_index_test ORDER BY value;
RESET enable_seqscan;
DROP TABLE map_object_index_test;
SELECT CAST(NULL AS map_object_type) < map_object_type(9, 'a') AS map_null
FROM dual;
SELECT objects.v
FROM
(
    SELECT map_object_type(2, 'two') v FROM dual
    UNION ALL
    SELECT map_object_type(11, 'eleven') v FROM dual
) objects
ORDER BY objects.v;
SELECT count(*) AS map_groups
FROM
(
    SELECT objects.v
    FROM
    (
        SELECT map_object_type(11, 'z') v FROM dual
        UNION ALL
        SELECT map_object_type(1, 'a') v FROM dual
        UNION ALL
        SELECT map_object_type(2, 'b') v FROM dual
    ) objects
    GROUP BY objects.v
) grouped_objects;
SELECT count(*) AS map_distinct
FROM
(
    SELECT DISTINCT objects.v
    FROM
    (
        SELECT map_object_type(11, 'z') v FROM dual
        UNION ALL
        SELECT map_object_type(1, 'a') v FROM dual
        UNION ALL
        SELECT map_object_type(2, 'b') v FROM dual
    ) objects
) distinct_objects;
SELECT count(*) AS map_union
FROM
(
    SELECT map_object_type(11, 'z') v FROM dual
    UNION
    SELECT map_object_type(1, 'a') v FROM dual
    UNION
    SELECT map_object_type(2, 'b') v FROM dual
) union_objects;
DROP TYPE map_object_type;

-- ORDER methods compare SELF directly with another object value.
CREATE TYPE order_object_type AS OBJECT
(
    value integer,
    label varchar2(20),
    ORDER MEMBER FUNCTION compare(other order_object_type) RETURN integer
);
/

CREATE TYPE BODY order_object_type AS
    ORDER MEMBER FUNCTION compare(other order_object_type) RETURN integer IS
    BEGIN
        RETURN mod(self.value, 10) - mod(other.value, 10);
    END compare;
END;
/

SELECT order_object_type(4, 'z') > order_object_type(2, 'a') AS order_greater,
       order_object_type(7, 'x') = order_object_type(7, 'y') AS order_equal
FROM dual;
CREATE TABLE order_object_index_test
(
    id integer,
    value order_object_type
);
INSERT INTO order_object_index_test VALUES
    (7, order_object_type(7, 'seven')),
    (2, order_object_type(2, 'two')),
    (9, order_object_type(9, 'nine'));
CREATE INDEX order_object_value_idx ON order_object_index_test (value);
SET ivorysql.compatible_mode = pg;
SET enable_seqscan = off;
SELECT id
FROM order_object_index_test
WHERE value = ROW(17, 'probe')::order_object_type
ORDER BY id;
REINDEX INDEX order_object_value_idx;
SET ivorysql.compatible_mode = oracle;
SELECT id FROM order_object_index_test ORDER BY value;
RESET enable_seqscan;
DROP TABLE order_object_index_test;
SELECT CAST(NULL AS order_object_type) < order_object_type(1, 'one') AS order_null
FROM dual;
SELECT objects.v
FROM
(
    SELECT order_object_type(2, 'two') v FROM dual
    UNION ALL
    SELECT order_object_type(11, 'eleven') v FROM dual
) objects
ORDER BY objects.v;
SELECT count(*) AS order_groups
FROM
(
    SELECT objects.v
    FROM
    (
        SELECT order_object_type(7, 'x') v FROM dual
        UNION ALL
        SELECT order_object_type(7, 'y') v FROM dual
        UNION ALL
        SELECT order_object_type(8, 'z') v FROM dual
    ) objects
    GROUP BY objects.v
) grouped_objects;
SELECT count(*) AS order_distinct
FROM
(
    SELECT DISTINCT objects.v
    FROM
    (
        SELECT order_object_type(7, 'x') v FROM dual
        UNION ALL
        SELECT order_object_type(7, 'y') v FROM dual
        UNION ALL
        SELECT order_object_type(8, 'z') v FROM dual
    ) objects
) distinct_objects;
SELECT count(*) AS order_union
FROM
(
    SELECT order_object_type(7, 'x') v FROM dual
    UNION
    SELECT order_object_type(7, 'y') v FROM dual
    UNION
    SELECT order_object_type(8, 'z') v FROM dual
) union_objects;
DROP TYPE order_object_type;

-- NOT INSTANTIABLE object types reject construction and must be NOT FINAL.
CREATE TYPE invalid_empty_object_type AS OBJECT ();
CREATE TYPE invalid_abstract_type AS OBJECT (id integer) NOT INSTANTIABLE;
CREATE TYPE abstract_constructor_type AS OBJECT
(
    id integer,
    CONSTRUCTOR FUNCTION abstract_constructor_type(p_id integer)
        RETURN SELF AS RESULT
) NOT INSTANTIABLE NOT FINAL;
SELECT abstract_constructor_type(1) FROM dual;
DROP TYPE abstract_constructor_type;
CREATE TYPE invalid_order_type AS OBJECT
(
    id integer,
    ORDER MEMBER FUNCTION compare(other OUT invalid_order_type) RETURN integer
);
CREATE TYPE invalid_map_type AS OBJECT
(
    id integer,
    MAP MEMBER FUNCTION map_key(extra integer) RETURN integer
);
CREATE TYPE invalid_map_return_type AS OBJECT
(
    id integer,
    MAP MEMBER FUNCTION map_key RETURN json
);
CREATE TYPE invalid_comparison_type AS OBJECT
(
    id integer,
    MAP MEMBER FUNCTION map_key RETURN integer,
    ORDER MEMBER FUNCTION compare(other invalid_comparison_type) RETURN integer
);
CREATE TYPE abstract_modifier_order AS OBJECT ()
    NOT FINAL NOT INSTANTIABLE;
CREATE TYPE abstract_object_type AS OBJECT (id integer)
    NOT INSTANTIABLE NOT FINAL;
SELECT abstract_object_type(1) FROM dual;
DROP TYPE abstract_object_type;

-- Only types declared AS OBJECT have constructor and member semantics.
CREATE TABLE ordinary_object_table (id integer, label varchar(20));
CREATE VIEW ordinary_object_view AS
	SELECT 1 AS id, CAST('view' AS varchar(20)) AS label FROM dual;

SELECT ordinary_object_table(1, 'table') FROM dual;
SELECT ordinary_object_view(1, 'view') FROM dual;
-- PostgreSQL-compatible composite types still are not Oracle object types.
SELECT default_test_row('row', 42);

-- IvorySQL catalog integration (not an Oracle data-dictionary query).
SELECT typname, typisobject
FROM pg_type
WHERE typname IN ('ordinary_object_table', 'ordinary_object_view',
				  'default_test_row')
ORDER BY typname;

DROP VIEW ordinary_object_view;
DROP TABLE ordinary_object_table;

-- Method introducers remain usable as ordinary identifiers elsewhere.
CREATE TABLE object_keyword_compatibility
(
    constructor integer,
    member integer,
    static integer
);
INSERT INTO object_keyword_compatibility VALUES (1, 2, 3);
SELECT constructor, member, static FROM object_keyword_compatibility;
DROP TABLE object_keyword_compatibility;

CREATE FUNCTION get_default_test() RETURNS SETOF default_test_row AS '
  SELECT * FROM default_test;
' LANGUAGE SQL;
/

SELECT * FROM get_default_test();

-- Test comments
COMMENT ON TYPE bad IS 'bad comment';
COMMENT ON TYPE default_test_row IS 'good comment';
COMMENT ON TYPE default_test_row IS NULL;
COMMENT ON COLUMN default_test_row.nope IS 'bad comment';
COMMENT ON COLUMN default_test_row.f1 IS 'good comment';
COMMENT ON COLUMN default_test_row.f1 IS NULL;

-- Check shell type create for existing types
CREATE TYPE text_w_default;		-- should fail

DROP TYPE default_test_row CASCADE;

DROP TABLE default_test;

-- Check dependencies are established when creating a new type
CREATE TYPE base_type;
CREATE FUNCTION base_fn_in(cstring) RETURNS base_type AS 'boolin'
    LANGUAGE internal IMMUTABLE STRICT;
/
CREATE FUNCTION base_fn_out(base_type) RETURNS cstring AS 'boolout'
    LANGUAGE internal IMMUTABLE STRICT;
/
CREATE TYPE base_type(INPUT = base_fn_in, OUTPUT = base_fn_out);
DROP FUNCTION base_fn_in(cstring); -- error
DROP FUNCTION base_fn_out(base_type); -- error
DROP TYPE base_type; -- error
DROP TYPE base_type CASCADE;

-- Check usage of typmod with a user-defined type
-- (we have borrowed numeric's typmod functions)

CREATE TEMP TABLE mytab (foo widget(42,13,7));     -- should fail
CREATE TEMP TABLE mytab (foo widget(42,13));

SELECT format_type(atttypid,atttypmod) FROM pg_attribute
WHERE attrelid = 'mytab'::regclass AND attnum > 0;

-- might as well exercise the widget type while we're here
INSERT INTO mytab VALUES ('(1,2,3)'), ('(-44,5.5,12)');
TABLE mytab;

-- and test format_type() a bit more, too
select format_type('varchar'::regtype, 42);
select format_type('bpchar'::regtype, null);
-- this behavior difference is intentional
select format_type('bpchar'::regtype, -1);

-- Test non-error-throwing APIs using widget, which still throws errors
SELECT pg_input_is_valid('(1,2,3)', 'widget');
SELECT pg_input_is_valid('(1,2)', 'widget');  -- hard error expected
SELECT pg_input_is_valid('{"(1,2,3)"}', 'widget[]');
SELECT pg_input_is_valid('{"(1,2)"}', 'widget[]');  -- hard error expected
SELECT pg_input_is_valid('("(1,2,3)")', 'mytab');
SELECT pg_input_is_valid('("(1,2)")', 'mytab');  -- hard error expected

-- Test creation of an operator over a user-defined type

CREATE FUNCTION pt_in_widget(point, widget)
   RETURNS bool
   AS :'regresslib'
   LANGUAGE C STRICT;
/

CREATE OPERATOR <% (
   leftarg = point,
   rightarg = widget,
   procedure = pt_in_widget,
   commutator = >% ,
   negator = >=%
);

SELECT point '(1,2)' <% widget '(0,0,3)' AS t,
       point '(1,2)' <% widget '(0,0,1)' AS f;

-- exercise city_budget type
CREATE TABLE city (
	name		name,
	location 	box,
	budget 		city_budget
);

INSERT INTO city VALUES
('Podunk', '(1,2),(3,4)', '100,127,1000'),
('Gotham', '(1000,34),(1100,334)', '123456,127,-1000,6789');

TABLE city;

--
-- Test CREATE/ALTER TYPE using a type that's compatible with varchar,
-- so we can re-use those support functions
--
CREATE TYPE myvarchar;

CREATE FUNCTION myvarcharin(cstring, oid, integer) RETURNS myvarchar
LANGUAGE internal IMMUTABLE PARALLEL SAFE STRICT AS 'varcharin';
/

CREATE FUNCTION myvarcharout(myvarchar) RETURNS cstring
LANGUAGE internal IMMUTABLE PARALLEL SAFE STRICT AS 'varcharout';
/

CREATE FUNCTION myvarcharsend(myvarchar) RETURNS bytea
LANGUAGE internal STABLE PARALLEL SAFE STRICT AS 'varcharsend';
/

CREATE FUNCTION myvarcharrecv(internal, oid, integer) RETURNS myvarchar
LANGUAGE internal STABLE PARALLEL SAFE STRICT AS 'varcharrecv';
/

-- fail, it's still a shell:
ALTER TYPE myvarchar SET (storage = extended);

CREATE TYPE myvarchar (
    input = myvarcharin,
    output = myvarcharout,
    alignment = integer,
    storage = main
);

-- want to check updating of a domain over the target type, too
CREATE DOMAIN myvarchardom AS myvarchar;

ALTER TYPE myvarchar SET (storage = plain);  -- not allowed

ALTER TYPE myvarchar SET (storage = extended);

ALTER TYPE myvarchar SET (
    send = myvarcharsend,
    receive = myvarcharrecv,
    typmod_in = varchartypmodin,
    typmod_out = varchartypmodout,
    -- these are bogus, but it's safe as long as we don't use the type:
    analyze = ts_typanalyze,
    subscript = raw_array_subscript_handler
);

SELECT typinput, typoutput, typreceive, typsend, typmodin, typmodout,
       typanalyze, typsubscript, typstorage
FROM pg_type WHERE typname = 'myvarchar';

SELECT typinput, typoutput, typreceive, typsend, typmodin, typmodout,
       typanalyze, typsubscript, typstorage
FROM pg_type WHERE typname = '_myvarchar';

SELECT typinput, typoutput, typreceive, typsend, typmodin, typmodout,
       typanalyze, typsubscript, typstorage
FROM pg_type WHERE typname = 'myvarchardom';

SELECT typinput, typoutput, typreceive, typsend, typmodin, typmodout,
       typanalyze, typsubscript, typstorage
FROM pg_type WHERE typname = '_myvarchardom';

-- ensure dependencies are straight
DROP FUNCTION myvarcharsend(myvarchar);  -- fail
DROP TYPE myvarchar;  -- fail

DROP TYPE myvarchar CASCADE;
