-- Oracle object references, including recursive types and dangling REF values.
CREATE TYPE ref_reg_person AS OBJECT (
    name varchar2(10),
    parent REF ref_reg_person
);
CREATE OR REPLACE TYPE ref_reg_person AS OBJECT (
    name varchar2(10),
    parent REF ref_reg_person
);
CREATE TYPE ref_reg_other AS OBJECT (name varchar2(10));
-- Direct helper calls must reject scalars before reading a composite Datum.
SELECT sys.ora_deref_internal(1, NULL::ref_reg_person);
SELECT sys.ora_deref_internal('scalar'::text, NULL::ref_reg_person);
CREATE DOMAIN ref_reg_scalar AS integer;
SELECT sys.ora_deref_internal(1::ref_reg_scalar, NULL::ref_reg_person);
DROP DOMAIN ref_reg_scalar;
SELECT sys.ora_deref_internal(ROW(1, 2), NULL::ref_reg_person);
SELECT sys.ora_deref_internal(NULL::sys.object_ref,
                              NULL::ref_reg_person) IS NULL AS null_ref;

-- Reject the unsupported partition path, including ALTER TABLE ... OF.
CREATE TABLE ref_reg_partitioned OF ref_reg_person PARTITION BY RANGE (name);
CREATE TABLE ref_reg_partitioned (name varchar2(10), parent REF ref_reg_person)
    PARTITION BY RANGE (name);
ALTER TABLE ref_reg_partitioned OF ref_reg_person;
DROP TABLE ref_reg_partitioned;
CREATE TABLE ref_reg_people OF ref_reg_person;
CREATE TABLE ref_reg_others OF ref_reg_other;
CREATE TABLE ref_reg_holder (person REF ref_reg_person NOT NULL);

INSERT INTO ref_reg_people (name) VALUES ('root'), ('child');
INSERT INTO ref_reg_others (name) VALUES ('other');
UPDATE ref_reg_people p SET parent =
    (SELECT REF(r) FROM ref_reg_people r WHERE r.name = 'root')
    WHERE p.name = 'child';
INSERT INTO ref_reg_holder
    SELECT REF(p) FROM ref_reg_people p WHERE p.name = 'child';

SELECT p.name, (DEREF(p.parent)).name AS parent_name
  FROM ref_reg_people p ORDER BY p.name;
SELECT (DEREF(h.person)).name AS person_name FROM ref_reg_holder h;
SELECT (DEREF(REF(p))).name = p.name AS round_trip
  FROM ref_reg_people p ORDER BY p.name;

-- A REF to a different object type violates the generated domain constraint.
UPDATE ref_reg_people SET parent =
    (SELECT REF(o) FROM ref_reg_others o) WHERE name = 'child';

DELETE FROM ref_reg_people WHERE name = 'root';
SELECT p.name, DEREF(p.parent) IS NULL AS dangling
  FROM ref_reg_people p;
-- Reusing an object's ROWID could make a dangling REF point to another row.
TRUNCATE ref_reg_people RESTART IDENTITY;

DROP TABLE ref_reg_holder;
DROP TABLE ref_reg_people;
DROP TABLE ref_reg_others;
DROP TYPE ref_reg_person;
DROP TYPE ref_reg_other;

-- Transferring an object type must also transfer its generated REF type.
CREATE ROLE regress_ref_owner_old;
CREATE ROLE regress_ref_owner_new;
CREATE SCHEMA ref_owner_schema;
GRANT USAGE, CREATE ON SCHEMA ref_owner_schema
    TO regress_ref_owner_old, regress_ref_owner_new;
SET search_path = ref_owner_schema, sys, public;
SET ROLE regress_ref_owner_old;
CREATE TYPE ref_owned_object AS OBJECT (id integer);
RESET ROLE;
SET ivorysql.compatible_mode = pg;
ALTER TYPE ref_owner_schema.ref_owned_object OWNER TO regress_ref_owner_new;
SELECT pg_get_userbyid(t.typowner) AS ref_owner,
       pg_get_userbyid(a.typowner) AS ref_array_owner
FROM pg_type t JOIN pg_type a ON a.oid = t.typarray
WHERE t.typrefbase = 'ref_owner_schema.ref_owned_object'::regtype;
-- Cleaning up the former owner's objects must not remove the REF domain.
DROP OWNED BY regress_ref_owner_old;
SET ivorysql.compatible_mode = oracle;
SET ROLE regress_ref_owner_new;
CREATE TABLE ref_owned_people OF ref_owned_object;
CREATE TABLE ref_owned_holder (value REF ref_owned_object);
INSERT INTO ref_owned_people VALUES (1);
INSERT INTO ref_owned_holder SELECT REF(p) FROM ref_owned_people p;
SELECT (DEREF(h.value)).id AS retained_ref_target FROM ref_owned_holder h;
RESET ROLE;
DROP TABLE ref_owned_holder;
DROP TABLE ref_owned_people;
DROP TYPE ref_owned_object;
RESET search_path;
DROP SCHEMA ref_owner_schema;
DROP ROLE regress_ref_owner_old;
DROP ROLE regress_ref_owner_new;

-- An unused generated REF domain can be dropped independently of its type.
CREATE ROLE regress_ref_missing_owner;
CREATE TYPE ref_owner_missing_domain AS OBJECT (id integer);
SET ivorysql.compatible_mode = pg;
SELECT format('DROP DOMAIN %s', oid::regtype)
FROM pg_type WHERE typrefbase = 'ref_owner_missing_domain'::regtype
\gexec
ALTER TYPE ref_owner_missing_domain OWNER TO regress_ref_missing_owner;
SELECT typowner = 'regress_ref_missing_owner'::regrole AS owner_transferred
FROM pg_type WHERE oid = 'ref_owner_missing_domain'::regtype;
DROP TYPE ref_owner_missing_domain;
DROP ROLE regress_ref_missing_owner;
SET ivorysql.compatible_mode = oracle;

-- Self-referencing types must retain their REF domain after owner cleanup.
CREATE ROLE regress_ref_recursive_old;
CREATE ROLE regress_ref_recursive_new;
CREATE SCHEMA ref_recursive_owner_schema;
GRANT USAGE, CREATE ON SCHEMA ref_recursive_owner_schema
    TO regress_ref_recursive_old, regress_ref_recursive_new;
SET search_path = ref_recursive_owner_schema, sys, public;
SET ROLE regress_ref_recursive_old;
CREATE TYPE ref_recursive_owned AS OBJECT
    (id integer, parent REF ref_recursive_owned);
RESET ROLE;
SET ivorysql.compatible_mode = pg;
ALTER TYPE ref_recursive_owned OWNER TO regress_ref_recursive_new;
SELECT t.typowner = 'regress_ref_recursive_new'::regrole AS ref_owner_transferred,
       a.typowner = 'regress_ref_recursive_new'::regrole AS array_owner_transferred
FROM pg_type t JOIN pg_type a ON a.oid = t.typarray
WHERE t.typrefbase = 'ref_recursive_owned'::regtype;
DROP OWNED BY regress_ref_recursive_old;
SET ivorysql.compatible_mode = oracle;
SET ROLE regress_ref_recursive_new;
CREATE TABLE ref_recursive_people OF ref_recursive_owned;
INSERT INTO ref_recursive_people (id) VALUES (1), (2);
UPDATE ref_recursive_people p SET parent =
    (SELECT REF(r) FROM ref_recursive_people r WHERE r.id = 1) WHERE p.id = 2;
SELECT (DEREF(p.parent)).id AS retained_parent
FROM ref_recursive_people p WHERE p.id = 2;
RESET ROLE;
DROP TABLE ref_recursive_people;
DROP TYPE ref_recursive_owned;
RESET search_path;
DROP SCHEMA ref_recursive_owner_schema;
DROP ROLE regress_ref_recursive_old;
DROP ROLE regress_ref_recursive_new;
