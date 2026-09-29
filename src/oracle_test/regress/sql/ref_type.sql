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
