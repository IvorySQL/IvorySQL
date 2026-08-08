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
SELECT oracle_object_type(1, 'one');

-- An ordinary routine with the same name and arguments takes precedence.
CREATE FUNCTION oracle_object_type(integer, varchar)
RETURNS oracle_object_type
LANGUAGE SQL IMMUTABLE
AS 'SELECT ROW($1 + 100, $2)::oracle_object_type';
/
SELECT oracle_object_type(1, 'one');
DROP FUNCTION oracle_object_type(integer, varchar);

-- Without MAP or ORDER, object values support equality but not ordering.
SELECT oracle_object_type(1, 'one') = oracle_object_type(1, 'one');
SELECT oracle_object_type(1, 'one') < oracle_object_type(2, 'two');
SELECT v
FROM (VALUES (oracle_object_type(1, 'one'))) AS objects(v)
ORDER BY v;

-- Constructor arguments are coerced to their declared attribute types.
SELECT oracle_object_type('2', 'two');

-- An unrelated standalone function is not an object member method.
CREATE FUNCTION object_label(oracle_object_type)
RETURNS varchar
LANGUAGE SQL IMMUTABLE
AS 'SELECT ($1).label';
/

SELECT value.object_label()
FROM (VALUES (oracle_object_type(1, 'one'))) AS objects(value);

SELECT typisobject FROM pg_type WHERE typname = 'oracle_object_type';

DROP FUNCTION object_label(oracle_object_type);
DROP TYPE oracle_object_type;

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

SELECT p.full_name(), p.age_in(2026)
FROM (VALUES (person_object_type('Ada', 'Lovelace', 1815))) AS v(p);
SELECT p.age_in()
FROM (VALUES (person_object_type('Ada', 'Lovelace', 1815))) AS v(p);
SELECT p.age_in(p_year => 2020)
FROM (VALUES (person_object_type('Ada', 'Lovelace', 1815))) AS v(p);

-- Qualified object columns retain member-call semantics.
CREATE TABLE person_object_table (object_value person_object_type);
INSERT INTO person_object_table
VALUES (person_object_type('Grace', 'Hopper', 1906));
SELECT t.object_value.full_name() FROM person_object_table AS t;
SELECT public.person_object_table.object_value.full_name()
FROM public.person_object_table;
DROP TABLE person_object_table;

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
SELECT p.full_name()
FROM (VALUES (person_object_type('Ada', 'Lovelace', 1815))) AS v(p);

CREATE OR REPLACE TYPE person_object_type AS OBJECT
(
    first_name varchar2(30),
    last_name varchar2(20),
    birth_year integer,
    MEMBER FUNCTION full_name RETURN varchar2,
    MEMBER FUNCTION age_in(p_year integer DEFAULT 2026) RETURN integer
) NOT FINAL;
/

DROP TYPE person_object_type;

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
    STATIC PROCEDURE increment(p_value IN OUT integer)
);
/

CREATE TYPE BODY feature_object_type AS
    CONSTRUCTOR FUNCTION feature_object_type(p_value integer, p_label varchar2)
        RETURN SELF AS RESULT IS
    BEGIN
        self.value := p_value + 100;
        self.label := p_label;
        RETURN self;
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

    STATIC PROCEDURE increment(p_value IN OUT integer) IS
    BEGIN
        p_value := p_value + 1;
    END increment;
END;
/

SELECT feature_object_type(1, 'one'),
       feature_object_type.decorate('static');
SELECT feature_object_type(p_label => 'named', p_value => 8);
SELECT v.describe()
FROM (VALUES (feature_object_type(2, 'two'))) AS objects(v);

DO $$
DECLARE
    v feature_object_type := feature_object_type(3, 'three');
	n integer := 10;
BEGIN
    v.bump(4);
	feature_object_type.increment(n);
    IF v.value <> 107 THEN
        RAISE EXCEPTION 'unexpected member procedure result: %', v.value;
    END IF;
	IF n <> 11 THEN
		RAISE EXCEPTION 'unexpected static procedure result: %', n;
	END IF;
END;
$$;

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
		IF self IS NULL THEN
			RAISE EXCEPTION 'MAP method invoked for NULL SELF';
		END IF;
        RETURN self.value % 10;
    END sort_key;
END;
/

SELECT map_object_type(11, 'z') = map_object_type(1, 'a') AS map_equal,
       map_object_type(2, 'z') < map_object_type(9, 'a') AS map_less;
SELECT NULL::map_object_type < map_object_type(9, 'a') AS map_null;
SELECT (v).value
FROM (VALUES (map_object_type(2, 'two')),
             (map_object_type(11, 'eleven'))) AS objects(v)
ORDER BY v;
SELECT count(*) AS map_groups
FROM
(
    SELECT v
    FROM (VALUES (map_object_type(11, 'z')),
                 (map_object_type(1, 'a')),
                 (map_object_type(2, 'b'))) AS objects(v)
    GROUP BY v
) AS grouped_objects;
SELECT count(*) AS map_distinct
FROM
(
    SELECT DISTINCT v
    FROM (VALUES (map_object_type(11, 'z')),
                 (map_object_type(1, 'a')),
                 (map_object_type(2, 'b'))) AS objects(v)
) AS distinct_objects;
SELECT count(*) AS map_union
FROM
(
    SELECT map_object_type(11, 'z') AS v
    UNION
    SELECT map_object_type(1, 'a')
    UNION
    SELECT map_object_type(2, 'b')
) AS union_objects;
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
		IF self IS NULL OR other IS NULL THEN
			RAISE EXCEPTION 'ORDER method invoked for NULL object';
		END IF;
        RETURN (self.value % 10) - (other.value % 10);
    END compare;
END;
/

SELECT order_object_type(4, 'z') > order_object_type(2, 'a') AS order_greater,
       order_object_type(7, 'x') = order_object_type(7, 'y') AS order_equal;
SELECT NULL::order_object_type < order_object_type(1, 'one') AS order_null;
SELECT (v).value
FROM (VALUES (order_object_type(2, 'two')),
             (order_object_type(11, 'eleven'))) AS objects(v)
ORDER BY v;
SELECT count(*) AS order_groups
FROM
(
    SELECT v
    FROM (VALUES (order_object_type(7, 'x')),
                 (order_object_type(7, 'y')),
                 (order_object_type(8, 'z'))) AS objects(v)
    GROUP BY v
) AS grouped_objects;
SELECT count(*) AS order_distinct
FROM
(
    SELECT DISTINCT v
    FROM (VALUES (order_object_type(7, 'x')),
                 (order_object_type(7, 'y')),
                 (order_object_type(8, 'z'))) AS objects(v)
) AS distinct_objects;
SELECT count(*) AS order_union
FROM
(
    SELECT order_object_type(7, 'x') AS v
    UNION
    SELECT order_object_type(7, 'y')
    UNION
    SELECT order_object_type(8, 'z')
) AS union_objects;
DROP TYPE order_object_type;

-- NOT INSTANTIABLE object types reject construction and must be NOT FINAL.
CREATE TYPE invalid_empty_object_type AS OBJECT ();
CREATE TYPE invalid_abstract_type AS OBJECT (id integer) NOT INSTANTIABLE;
CREATE TYPE invalid_abstract_constructor AS OBJECT
(
    id integer,
    CONSTRUCTOR FUNCTION invalid_abstract_constructor(p_id integer)
        RETURN SELF AS RESULT
) NOT INSTANTIABLE NOT FINAL;
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
DROP TYPE abstract_modifier_order;
CREATE TYPE abstract_object_type AS OBJECT (id integer)
    NOT INSTANTIABLE NOT FINAL;
SELECT abstract_object_type(1);
DROP TYPE abstract_object_type;

-- Only types declared AS OBJECT have constructor and member semantics.
CREATE TABLE ordinary_object_table (id integer, label varchar(20));
CREATE VIEW ordinary_object_view AS
	SELECT 1 AS id, 'view'::varchar(20) AS label;

SELECT ordinary_object_table(1, 'table');
SELECT ordinary_object_view(1, 'view');
SELECT default_test_row('row', 42);

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
