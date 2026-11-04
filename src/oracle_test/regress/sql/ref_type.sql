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

-- Converting a table must preserve the ROWID requirement for object tables.
CREATE TYPE ref_rowid_object AS OBJECT (id integer);
CREATE TABLE ref_rowid_converted (id integer) WITHOUT ROWID;
INSERT INTO ref_rowid_converted VALUES (31);
SET ivorysql.compatible_mode = pg;
ALTER TABLE ref_rowid_converted OF ref_rowid_object;
\echo missing_rowid_sqlstate: :SQLSTATE
SELECT reloftype = 0 AS still_untyped, NOT relhasrowid AS still_without_rowid
FROM pg_class WHERE oid = 'ref_rowid_converted'::regclass;
SET ivorysql.compatible_mode = oracle;
ALTER TABLE ref_rowid_converted SET WITH ROWID;
SET ivorysql.compatible_mode = pg;
ALTER TABLE ref_rowid_converted OF ref_rowid_object;
SET ivorysql.compatible_mode = oracle;
INSERT INTO ref_rowid_converted VALUES (32);
SELECT p.id, (DEREF(REF(p))).id AS referenced_id
FROM ref_rowid_converted p ORDER BY p.id;
DROP TABLE ref_rowid_converted;
DROP TYPE ref_rowid_object;

-- Ordinary composite typed tables do not require ROWID.
SET ivorysql.compatible_mode = pg;
CREATE TYPE ref_rowid_plain AS (id integer);
SET ivorysql.compatible_mode = oracle;
CREATE TABLE ref_rowid_plain_table (id integer) WITHOUT ROWID;
SET ivorysql.compatible_mode = pg;
ALTER TABLE ref_rowid_plain_table OF ref_rowid_plain;
SELECT reloftype = 'ref_rowid_plain'::regtype AS plain_typed,
       NOT relhasrowid AS still_without_rowid
FROM pg_class WHERE oid = 'ref_rowid_plain_table'::regclass;
DROP TABLE ref_rowid_plain_table;
DROP TYPE ref_rowid_plain;
SET ivorysql.compatible_mode = oracle;
