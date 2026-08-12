--
-- FOREIGN KEY ... PERIOD (temporal foreign keys)
--
-- Oracle-compatible temporal foreign key syntax, supported through the
-- Oracle parser and executed by the PostgreSQL foreign key engine.
--

-- referenced table needs a WITHOUT OVERLAPS unique constraint
CREATE TABLE parent (id int4range, valid_at daterange,
  PRIMARY KEY (id, valid_at WITHOUT OVERLAPS));

CREATE TABLE child (
  id int4range, valid_at daterange, parent_id int4range,
  FOREIGN KEY (parent_id, PERIOD valid_at) REFERENCES parent (id, PERIOD valid_at)
);
\d child

-- PERIOD only on the referencing side is rejected
CREATE TABLE child_bad (
  id int4range, valid_at daterange, parent_id int4range,
  FOREIGN KEY (parent_id, PERIOD valid_at) REFERENCES parent (id)
);

-- PERIOD only on the referenced side is rejected
CREATE TABLE child_bad2 (
  id int4range, valid_at daterange, parent_id int4range,
  FOREIGN KEY (parent_id, valid_at) REFERENCES parent (id, PERIOD valid_at)
);

-- data
INSERT INTO parent VALUES ('[1,2)', '[2020-01-01,2021-01-01)');
INSERT INTO parent VALUES ('[2,3)', '[2021-01-01,2022-01-01)');

-- valid inserts
INSERT INTO child VALUES ('[10,11)', '[2020-06-01,2020-07-01)', '[1,2)');
INSERT INTO child VALUES ('[20,21)', '[2021-06-01,2021-07-01)', '[2,3)');

-- violation: parent_id not present in parent
INSERT INTO child VALUES ('[30,31)', '[2020-06-01,2020-07-01)', '[99,100)');

SELECT * FROM child ORDER BY 1;

DROP TABLE child;
DROP TABLE parent;
