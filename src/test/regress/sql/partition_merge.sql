--
-- PARTITIONS_MERGE
-- Tests for "ALTER TABLE ... MERGE PARTITIONS ..." command
--

CREATE SCHEMA partitions_merge_schema;
CREATE SCHEMA partitions_merge_schema2;
SET search_path = partitions_merge_schema, public;

--
-- BY RANGE partitioning
--

--
-- Test for error codes
--
CREATE TABLE sales_range (salesperson_id INT, salesperson_name VARCHAR(30), sales_amount INT, sales_date DATE) PARTITION BY RANGE (sales_date);
CREATE TABLE sales_dec2021 PARTITION OF sales_range FOR VALUES FROM ('2021-12-01') TO ('2021-12-31');
CREATE TABLE sales_jan2022 PARTITION OF sales_range FOR VALUES FROM ('2022-01-01') TO ('2022-02-01');
CREATE TABLE sales_feb2022 PARTITION OF sales_range FOR VALUES FROM ('2022-02-01') TO ('2022-03-01');
CREATE TABLE sales_mar2022 PARTITION OF sales_range FOR VALUES FROM ('2022-03-01') TO ('2022-04-01');

CREATE TABLE sales_apr2022 (salesperson_id INT, salesperson_name VARCHAR(30), sales_amount INT, sales_date DATE) PARTITION BY RANGE (sales_date);
CREATE TABLE sales_apr_1 PARTITION OF sales_apr2022 FOR VALUES FROM ('2022-04-01') TO ('2022-04-15');
CREATE TABLE sales_apr_2 PARTITION OF sales_apr2022 FOR VALUES FROM ('2022-04-15') TO ('2022-05-01');
ALTER TABLE sales_range ATTACH PARTITION sales_apr2022 FOR VALUES FROM ('2022-04-01') TO ('2022-05-01');

CREATE TABLE sales_others PARTITION OF sales_range DEFAULT;

-- ERROR:  partition with name "sales_feb2022" is already used
ALTER TABLE sales_range MERGE PARTITIONS (sales_feb2022, sales_mar2022, sales_feb2022) INTO sales_feb_mar_apr2022;
-- ERROR:  "sales_apr2022" is not a table
ALTER TABLE sales_range MERGE PARTITIONS (sales_feb2022, sales_mar2022, sales_apr2022) INTO sales_feb_mar_apr2022;
-- ERROR:  lower bound of partition "sales_mar2022" conflicts with upper bound of previous partition "sales_jan2022"
-- (space between sections sales_jan2022 and sales_mar2022)
ALTER TABLE sales_range MERGE PARTITIONS (sales_jan2022, sales_mar2022) INTO sales_jan_mar2022;
-- ERROR:  lower bound of partition "sales_jan2022" conflicts with upper bound of previous partition "sales_dec2021"
-- (space between sections sales_dec2021 and sales_jan2022)
ALTER TABLE sales_range MERGE PARTITIONS (sales_dec2021, sales_jan2022, sales_feb2022) INTO sales_dec_jan_feb2022;

-- NO ERROR: test for custom partitions order, source partitions not in the search_path
SET search_path = partitions_merge_schema2, public;
ALTER TABLE partitions_merge_schema.sales_range MERGE PARTITIONS (
  partitions_merge_schema.sales_feb2022,
  partitions_merge_schema.sales_mar2022,
  partitions_merge_schema.sales_jan2022) INTO sales_jan_feb_mar2022;
SET search_path = partitions_merge_schema, public;

SELECT c.oid::pg_catalog.regclass, c.relkind, inhdetachpending, pg_catalog.pg_get_expr(c.relpartbound, c.oid)
  FROM pg_catalog.pg_class c, pg_catalog.pg_inherits i
  WHERE c.oid = i.inhrelid AND i.inhparent = 'sales_range'::regclass
  ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;

DROP TABLE sales_range;

--
-- Add rows into partitioned table, then merge partitions
--
CREATE TABLE sales_range (salesperson_id INT, salesperson_name VARCHAR(30), sales_amount INT, sales_date DATE) PARTITION BY RANGE (sales_date);
CREATE TABLE sales_jan2022 PARTITION OF sales_range FOR VALUES FROM ('2022-01-01') TO ('2022-02-01');
CREATE TABLE sales_feb2022 PARTITION OF sales_range FOR VALUES FROM ('2022-02-01') TO ('2022-03-01');
CREATE TABLE sales_mar2022 PARTITION OF sales_range FOR VALUES FROM ('2022-03-01') TO ('2022-04-01');
CREATE TABLE sales_apr2022 PARTITION OF sales_range FOR VALUES FROM ('2022-04-01') TO ('2022-05-01');
CREATE TABLE sales_others PARTITION OF sales_range DEFAULT;
CREATE INDEX sales_range_sales_date_idx ON sales_range USING btree (sales_date);

INSERT INTO sales_range VALUES (1,  'May',      1000, '2022-01-31');
INSERT INTO sales_range VALUES (2,  'Smirnoff', 500,  '2022-02-10');
INSERT INTO sales_range VALUES (3,  'Ford',     2000, '2022-04-30');
INSERT INTO sales_range VALUES (4,  'Ivanov',   750,  '2022-04-13');
INSERT INTO sales_range VALUES (5,  'Deev',     250,  '2022-04-07');
INSERT INTO sales_range VALUES (6,  'Poirot',   150,  '2022-02-11');
INSERT INTO sales_range VALUES (7,  'Li',       175,  '2022-03-08');
INSERT INTO sales_range VALUES (8,  'Ericsson', 185,  '2022-02-23');
INSERT INTO sales_range VALUES (9,  'Muller',   250,  '2022-03-11');
INSERT INTO sales_range VALUES (10, 'Halder',   350,  '2022-01-28');
INSERT INTO sales_range VALUES (11, 'Trump',    380,  '2022-04-06');
INSERT INTO sales_range VALUES (12, 'Plato',    350,  '2022-03-19');
INSERT INTO sales_range VALUES (13, 'Gandi',    377,  '2022-01-09');
INSERT INTO sales_range VALUES (14, 'Smith',    510,  '2022-05-04');

SELECT pg_catalog.pg_get_partkeydef('sales_range'::regclass);

-- show partitions with conditions:
SELECT c.oid::pg_catalog.regclass, c.relkind, inhdetachpending, pg_catalog.pg_get_expr(c.relpartbound, c.oid)
  FROM pg_catalog.pg_class c, pg_catalog.pg_inherits i
  WHERE c.oid = i.inhrelid AND i.inhparent = 'sales_range'::regclass
  ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;

-- check schema-qualified name of the new partition
ALTER TABLE sales_range MERGE PARTITIONS (sales_feb2022, sales_mar2022, sales_apr2022) INTO partitions_merge_schema2.sales_feb_mar_apr2022;

-- show partitions with conditions:
SELECT c.oid::pg_catalog.regclass, c.relkind, inhdetachpending, pg_catalog.pg_get_expr(c.relpartbound, c.oid)
  FROM pg_catalog.pg_class c, pg_catalog.pg_inherits i
  WHERE c.oid = i.inhrelid AND i.inhparent = 'sales_range'::regclass
  ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;

SELECT * FROM pg_indexes WHERE tablename = 'sales_feb_mar_apr2022' and schemaname = 'partitions_merge_schema2';

SELECT * FROM sales_range;
SELECT * FROM sales_jan2022;
SELECT * FROM partitions_merge_schema2.sales_feb_mar_apr2022;
SELECT * FROM sales_others;

-- Use indexscan for testing indexes
SET enable_seqscan = OFF;

SELECT * FROM partitions_merge_schema2.sales_feb_mar_apr2022 where sales_date > '2022-01-01';

RESET enable_seqscan;

DROP TABLE sales_range;

--
-- Merge some partitions into DEFAULT partition
--
CREATE TABLE sales_range (salesperson_id INT, salesperson_name VARCHAR(30), sales_amount INT, sales_date DATE) PARTITION BY RANGE (sales_date);
CREATE TABLE sales_jan2022 PARTITION OF sales_range FOR VALUES FROM ('2022-01-01') TO ('2022-02-01');
CREATE TABLE sales_feb2022 PARTITION OF sales_range FOR VALUES FROM ('2022-02-01') TO ('2022-03-01');
CREATE TABLE sales_mar2022 PARTITION OF sales_range FOR VALUES FROM ('2022-03-01') TO ('2022-04-01');
CREATE TABLE sales_apr2022 PARTITION OF sales_range FOR VALUES FROM ('2022-04-01') TO ('2022-05-01');
CREATE TABLE sales_others PARTITION OF sales_range DEFAULT;
CREATE INDEX sales_range_sales_date_idx ON sales_range USING btree (sales_date);

INSERT INTO sales_range VALUES (1,  'May',      1000, '2022-01-31');
INSERT INTO sales_range VALUES (2,  'Smirnoff', 500,  '2022-02-10');
INSERT INTO sales_range VALUES (3,  'Ford',     2000, '2022-04-30');
INSERT INTO sales_range VALUES (4,  'Ivanov',   750,  '2022-04-13');
INSERT INTO sales_range VALUES (5,  'Deev',     250,  '2022-04-07');
INSERT INTO sales_range VALUES (6,  'Poirot',   150,  '2022-02-11');
INSERT INTO sales_range VALUES (7,  'Li',       175,  '2022-03-08');
INSERT INTO sales_range VALUES (8,  'Ericsson', 185,  '2022-02-23');
INSERT INTO sales_range VALUES (9,  'Muller',   250,  '2022-03-11');
INSERT INTO sales_range VALUES (10, 'Halder',   350,  '2022-01-28');
INSERT INTO sales_range VALUES (11, 'Trump',    380,  '2022-04-06');
INSERT INTO sales_range VALUES (12, 'Plato',    350,  '2022-03-19');
INSERT INTO sales_range VALUES (13, 'Gandi',    377,  '2022-01-09');
INSERT INTO sales_range VALUES (14, 'Smith',    510,  '2022-05-04');

-- Merge partitions (include DEFAULT partition) into partition with the same
-- name
ALTER TABLE sales_range MERGE PARTITIONS
  (sales_jan2022, sales_mar2022, partitions_merge_schema.sales_others) INTO sales_others;

select * from sales_others;

-- show partitions with conditions:
SELECT c.oid::pg_catalog.regclass, c.relkind, inhdetachpending, pg_catalog.pg_get_expr(c.relpartbound, c.oid)
  FROM pg_catalog.pg_class c, pg_catalog.pg_inherits i
  WHERE c.oid = i.inhrelid AND i.inhparent = 'sales_range'::regclass
  ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;

DROP TABLE sales_range;

--
-- Test for:
--   * composite partition key;
--   * GENERATED column;
--   * column with DEFAULT value.
--
CREATE TABLE sales_date (salesperson_name VARCHAR(30), sales_year INT, sales_month INT, sales_day INT,
  sales_date VARCHAR(10) GENERATED ALWAYS AS
    (LPAD(sales_year::text, 4, '0') || '.' || LPAD(sales_month::text, 2, '0') || '.' || LPAD(sales_day::text, 2, '0')) STORED,
  sales_department VARCHAR(30) DEFAULT 'Sales department')
  PARTITION BY RANGE (sales_year, sales_month, sales_day);

CREATE TABLE sales_dec2022 PARTITION OF sales_date FOR VALUES FROM (2021, 12, 1) TO (2022, 1, 1);
CREATE TABLE sales_jan2022 PARTITION OF sales_date FOR VALUES FROM (2022, 1, 1) TO (2022, 2, 1);
CREATE TABLE sales_feb2022 PARTITION OF sales_date FOR VALUES FROM (2022, 2, 1) TO (2022, 3, 1);
CREATE TABLE sales_other PARTITION OF sales_date FOR VALUES FROM (2022, 3, 1) TO (MAXVALUE, MAXVALUE, MAXVALUE);

INSERT INTO sales_date(salesperson_name, sales_year, sales_month, sales_day) VALUES ('Manager1', 2021, 12, 7);
INSERT INTO sales_date(salesperson_name, sales_year, sales_month, sales_day) VALUES ('Manager2', 2021, 12, 8);
INSERT INTO sales_date(salesperson_name, sales_year, sales_month, sales_day) VALUES ('Manager3', 2022, 1, 1);
INSERT INTO sales_date(salesperson_name, sales_year, sales_month, sales_day) VALUES ('Manager1', 2022, 2, 4);
INSERT INTO sales_date(salesperson_name, sales_year, sales_month, sales_day) VALUES ('Manager2', 2022, 1, 2);
INSERT INTO sales_date(salesperson_name, sales_year, sales_month, sales_day) VALUES ('Manager3', 2022, 2, 1);
INSERT INTO sales_date(salesperson_name, sales_year, sales_month, sales_day) VALUES ('Manager1', 2022, 3, 3);
INSERT INTO sales_date(salesperson_name, sales_year, sales_month, sales_day) VALUES ('Manager2', 2022, 3, 4);
INSERT INTO sales_date(salesperson_name, sales_year, sales_month, sales_day) VALUES ('Manager3', 2022, 5, 1);

SELECT * FROM sales_date;
SELECT * FROM sales_dec2022;
SELECT * FROM sales_jan2022;
SELECT * FROM sales_feb2022;
SELECT * FROM sales_other;

ALTER TABLE sales_date MERGE PARTITIONS (sales_jan2022, sales_feb2022) INTO sales_jan_feb2022;

INSERT INTO sales_date(salesperson_name, sales_year, sales_month, sales_day) VALUES ('Manager1', 2022, 1, 10);
INSERT INTO sales_date(salesperson_name, sales_year, sales_month, sales_day) VALUES ('Manager2', 2022, 2, 10);

SELECT * FROM sales_date;
SELECT * FROM sales_dec2022;
SELECT * FROM sales_jan_feb2022;
SELECT * FROM sales_other;

DROP TABLE sales_date;

--
-- Test: merge partitions of partitioned table with triggers
--
CREATE TABLE salespeople(salesperson_id INT PRIMARY KEY, salesperson_name VARCHAR(30)) PARTITION BY RANGE (salesperson_id);

CREATE TABLE salespeople01_10 PARTITION OF salespeople FOR VALUES FROM (1) TO (10);
CREATE TABLE salespeople10_20 PARTITION OF salespeople FOR VALUES FROM (10) TO (20);
CREATE TABLE salespeople20_30 PARTITION OF salespeople FOR VALUES FROM (20) TO (30);
CREATE TABLE salespeople30_40 PARTITION OF salespeople FOR VALUES FROM (30) TO (40);

INSERT INTO salespeople VALUES (1,  'Poirot');

CREATE OR REPLACE FUNCTION after_insert_row_trigger() RETURNS trigger LANGUAGE 'plpgsql' AS $BODY$
BEGIN
	RAISE NOTICE 'trigger(%) called: action = %, when = %, level = %', TG_ARGV[0], TG_OP, TG_WHEN, TG_LEVEL;
    RETURN NULL;
END;
$BODY$;

CREATE TRIGGER salespeople_after_insert_statement_trigger
    AFTER INSERT
    ON salespeople
    FOR EACH STATEMENT
    EXECUTE PROCEDURE after_insert_row_trigger('salespeople');

CREATE TRIGGER salespeople_after_insert_row_trigger
    AFTER INSERT
    ON salespeople
    FOR EACH ROW
    EXECUTE PROCEDURE after_insert_row_trigger('salespeople');

-- 2 triggers should fire here (row + statement):
INSERT INTO salespeople VALUES (10, 'May');
-- 1 trigger should fire here (row):
INSERT INTO salespeople10_20 VALUES (19, 'Ivanov');

ALTER TABLE salespeople MERGE PARTITIONS (salespeople10_20, salespeople20_30, salespeople30_40) INTO salespeople10_40;

-- 2 triggers should fire here (row + statement):
INSERT INTO salespeople VALUES (20, 'Smirnoff');
-- 1 trigger should fire here (row):
INSERT INTO salespeople10_40 VALUES (30, 'Ford');

SELECT * FROM salespeople01_10;
SELECT * FROM salespeople10_40;

DROP TABLE salespeople;
DROP FUNCTION after_insert_row_trigger();

--
-- Test: merge partitions with deleted columns
--
CREATE TABLE salespeople(salesperson_id INT PRIMARY KEY, salesperson_name VARCHAR(30)) PARTITION BY RANGE (salesperson_id);

CREATE TABLE salespeople01_10 PARTITION OF salespeople FOR VALUES FROM (1) TO (10);
-- Create partitions with some deleted columns:
CREATE TABLE salespeople10_20(d1 VARCHAR(30), salesperson_id INT PRIMARY KEY, salesperson_name VARCHAR(30));
CREATE TABLE salespeople20_30(salesperson_id INT PRIMARY KEY, d2 INT,  salesperson_name VARCHAR(30));
CREATE TABLE salespeople30_40(salesperson_id INT PRIMARY KEY, d3 DATE, salesperson_name VARCHAR(30));

INSERT INTO salespeople10_20 VALUES ('dummy value 1', 19, 'Ivanov');
INSERT INTO salespeople20_30 VALUES (20, 101, 'Smirnoff');
INSERT INTO salespeople30_40 VALUES (31, now(), 'Popov');

ALTER TABLE salespeople10_20 DROP COLUMN d1;
ALTER TABLE salespeople20_30 DROP COLUMN d2;
ALTER TABLE salespeople30_40 DROP COLUMN d3;

ALTER TABLE salespeople ATTACH PARTITION salespeople10_20 FOR VALUES FROM (10) TO (20);
ALTER TABLE salespeople ATTACH PARTITION salespeople20_30 FOR VALUES FROM (20) TO (30);
ALTER TABLE salespeople ATTACH PARTITION salespeople30_40 FOR VALUES FROM (30) TO (40);

INSERT INTO salespeople VALUES (1, 'Poirot');
INSERT INTO salespeople VALUES (10, 'May');
INSERT INTO salespeople VALUES (30, 'Ford');

ALTER TABLE salespeople MERGE PARTITIONS (salespeople10_20, salespeople20_30, salespeople30_40) INTO salespeople10_40;

select * from salespeople;
select * from salespeople01_10;
select * from salespeople10_40;

DROP TABLE salespeople;

--
-- Test: merge sub-partitions
--
CREATE TABLE sales_range (salesperson_id INT, salesperson_name VARCHAR(30), sales_amount INT, sales_date DATE) PARTITION BY RANGE (sales_date);
CREATE TABLE sales_jan2022 PARTITION OF sales_range FOR VALUES FROM ('2022-01-01') TO ('2022-02-01');
CREATE TABLE sales_feb2022 PARTITION OF sales_range FOR VALUES FROM ('2022-02-01') TO ('2022-03-01');
CREATE TABLE sales_mar2022 PARTITION OF sales_range FOR VALUES FROM ('2022-03-01') TO ('2022-04-01');

CREATE TABLE sales_apr2022 (salesperson_id INT, salesperson_name VARCHAR(30), sales_amount INT, sales_date DATE) PARTITION BY RANGE (sales_date);
CREATE TABLE sales_apr2022_01_10 PARTITION OF sales_apr2022 FOR VALUES FROM ('2022-04-01') TO ('2022-04-10');
CREATE TABLE sales_apr2022_10_20 PARTITION OF sales_apr2022 FOR VALUES FROM ('2022-04-10') TO ('2022-04-20');
CREATE TABLE sales_apr2022_20_30 PARTITION OF sales_apr2022 FOR VALUES FROM ('2022-04-20') TO ('2022-05-01');
ALTER TABLE sales_range ATTACH PARTITION sales_apr2022 FOR VALUES FROM ('2022-04-01') TO ('2022-05-01');

CREATE TABLE sales_others PARTITION OF sales_range DEFAULT;

CREATE INDEX sales_range_sales_date_idx ON sales_range USING btree (sales_date);

INSERT INTO sales_range VALUES (1,  'May',      1000, '2022-01-31');
INSERT INTO sales_range VALUES (2,  'Smirnoff', 500,  '2022-02-10');
INSERT INTO sales_range VALUES (3,  'Ford',     2000, '2022-04-30');
INSERT INTO sales_range VALUES (4,  'Ivanov',   750,  '2022-04-13');
INSERT INTO sales_range VALUES (5,  'Deev',     250,  '2022-04-07');
INSERT INTO sales_range VALUES (6,  'Poirot',   150,  '2022-02-11');
INSERT INTO sales_range VALUES (7,  'Li',       175,  '2022-03-08');
INSERT INTO sales_range VALUES (8,  'Ericsson', 185,  '2022-02-23');
INSERT INTO sales_range VALUES (9,  'Muller',   250,  '2022-03-11');
INSERT INTO sales_range VALUES (10, 'Halder',   350,  '2022-01-28');
INSERT INTO sales_range VALUES (11, 'Trump',    380,  '2022-04-06');
INSERT INTO sales_range VALUES (12, 'Plato',    350,  '2022-03-19');
INSERT INTO sales_range VALUES (13, 'Gandi',    377,  '2022-01-09');
INSERT INTO sales_range VALUES (14, 'Smith',    510,  '2022-05-04');

SELECT * FROM sales_range;
SELECT * FROM sales_apr2022;
SELECT * FROM sales_apr2022_01_10;
SELECT * FROM sales_apr2022_10_20;
SELECT * FROM sales_apr2022_20_30;

ALTER TABLE sales_apr2022 MERGE PARTITIONS (sales_apr2022_01_10, sales_apr2022_10_20, sales_apr2022_20_30) INTO sales_apr_all;

SELECT * FROM sales_range;
SELECT * FROM sales_apr2022;
SELECT * FROM sales_apr_all;

DROP TABLE sales_range;

--
-- BY LIST partitioning
--

--
-- Test: specific errors for BY LIST partitioning
--
CREATE TABLE sales_list
(salesperson_id INT GENERATED ALWAYS AS IDENTITY,
 salesperson_name VARCHAR(30),
 sales_state VARCHAR(20),
 sales_amount INT,
 sales_date DATE)
PARTITION BY LIST (sales_state);
CREATE TABLE sales_nord PARTITION OF sales_list FOR VALUES IN ('Oslo', 'St. Petersburg', 'Helsinki');
CREATE TABLE sales_west PARTITION OF sales_list FOR VALUES IN ('Lisbon', 'New York', 'Madrid');
CREATE TABLE sales_east PARTITION OF sales_list FOR VALUES IN ('Bejing', 'Delhi', 'Vladivostok');
CREATE TABLE sales_central PARTITION OF sales_list FOR VALUES IN ('Warsaw', 'Berlin', 'Kyiv');
CREATE TABLE sales_others PARTITION OF sales_list DEFAULT;


CREATE TABLE sales_list2 (LIKE sales_list) PARTITION BY LIST (sales_state);
CREATE TABLE sales_nord2 PARTITION OF sales_list2 FOR VALUES IN ('Oslo', 'St. Petersburg', 'Helsinki');
CREATE TABLE sales_others2 PARTITION OF sales_list2 DEFAULT;


CREATE TABLE sales_external (LIKE sales_list);
CREATE TABLE sales_external2 (vch VARCHAR(5));

-- ERROR:  "sales_external" is not a partition
ALTER TABLE sales_list MERGE PARTITIONS (sales_west, sales_east, sales_external) INTO sales_all;
-- ERROR:  "sales_external2" is not a partition
ALTER TABLE sales_list MERGE PARTITIONS (sales_west, sales_east, sales_external2) INTO sales_all;
-- ERROR:  relation "sales_nord2" is not a partition of relation "sales_list"
ALTER TABLE sales_list MERGE PARTITIONS (sales_west, sales_nord2, sales_east) INTO sales_all;

DROP TABLE sales_external2;
DROP TABLE sales_external;
DROP TABLE sales_list2;
DROP TABLE sales_list;

--
-- Test: BY LIST partitioning, MERGE PARTITIONS with data
--
CREATE TABLE sales_list
(salesperson_id INT GENERATED ALWAYS AS IDENTITY,
 salesperson_name VARCHAR(30),
 sales_state VARCHAR(20),
 sales_amount INT,
 sales_date DATE)
PARTITION BY LIST (sales_state);

CREATE INDEX sales_list_salesperson_name_idx ON sales_list USING btree (salesperson_name);
CREATE INDEX sales_list_sales_state_idx ON sales_list USING btree (sales_state);

CREATE TABLE sales_nord PARTITION OF sales_list FOR VALUES IN ('Oslo', 'St. Petersburg', 'Helsinki');
CREATE TABLE sales_west PARTITION OF sales_list FOR VALUES IN ('Lisbon', 'New York', 'Madrid');
CREATE TABLE sales_east PARTITION OF sales_list FOR VALUES IN ('Bejing', 'Delhi', 'Vladivostok');
CREATE TABLE sales_central PARTITION OF sales_list FOR VALUES IN ('Warsaw', 'Berlin', 'Kyiv');
CREATE TABLE sales_others PARTITION OF sales_list DEFAULT;

INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Trump',    'Bejing',         1000, '2022-03-01');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Smirnoff', 'New York',        500, '2022-03-03');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Ford',     'St. Petersburg', 2000, '2022-03-05');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Ivanov',   'Warsaw',          750, '2022-03-04');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Deev',     'Lisbon',          250, '2022-03-07');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Poirot',   'Berlin',         1000, '2022-03-01');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('May',      'Helsinki',       1200, '2022-03-06');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Li',       'Vladivostok',    1150, '2022-03-09');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('May',      'Helsinki',       1200, '2022-03-11');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Halder',   'Oslo',            800, '2022-03-02');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Muller',   'Madrid',          650, '2022-03-05');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Smith',    'Kyiv',            350, '2022-03-10');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Gandi',    'Warsaw',          150, '2022-03-08');
INSERT INTO sales_list (salesperson_name, sales_state, sales_amount, sales_date) VALUES ('Plato',    'Lisbon',          950, '2022-03-05');

-- show partitions with conditions:
SELECT c.oid::pg_catalog.regclass, c.relkind, inhdetachpending, pg_catalog.pg_get_expr(c.relpartbound, c.oid)
  FROM pg_catalog.pg_class c, pg_catalog.pg_inherits i
  WHERE c.oid = i.inhrelid AND i.inhparent = 'sales_list'::regclass
  ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;

ALTER TABLE sales_list MERGE PARTITIONS (sales_west, sales_east, sales_central) INTO sales_all;

-- show partitions with conditions:
SELECT c.oid::pg_catalog.regclass, c.relkind, inhdetachpending, pg_catalog.pg_get_expr(c.relpartbound, c.oid)
  FROM pg_catalog.pg_class c, pg_catalog.pg_inherits i
  WHERE c.oid = i.inhrelid AND i.inhparent = 'sales_list'::regclass
  ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;

SELECT * FROM sales_list;
SELECT * FROM sales_nord;
SELECT * FROM sales_all;

-- Use indexscan for testing indexes after merging partitions
SET enable_seqscan = OFF;

SELECT * FROM sales_all WHERE sales_state = 'Warsaw';
SELECT * FROM sales_list WHERE sales_state = 'Warsaw';
SELECT * FROM sales_list WHERE salesperson_name = 'Ivanov';

RESET enable_seqscan;

DROP TABLE sales_list;

--
-- Try to MERGE partitions of another table.
--
CREATE TABLE t1 (i int, a int, b int, c int) PARTITION BY RANGE (a, b);
CREATE TABLE t1p1 PARTITION OF t1 FOR VALUES FROM (1, 1) TO (1, 2);
CREATE TABLE t2 (i int, t text) PARTITION BY RANGE (t);
CREATE TABLE t2pa PARTITION OF t2 FOR VALUES FROM ('A') TO ('C');
CREATE TABLE t3 (i int, t text);

-- ERROR:  relation "t1p1" is not a partition of relation "t2"
ALTER TABLE t2 MERGE PARTITIONS (t1p1, t2pa) INTO t2p;
-- ERROR:  "t3" is not a partition
ALTER TABLE t2 MERGE PARTITIONS (t2pa, t3) INTO t2p;

DROP TABLE t3;
DROP TABLE t2;
DROP TABLE t1;

--
-- Try to MERGE partitions of temporary table.
--
CREATE TEMP TABLE t (i int) PARTITION BY RANGE (i);
CREATE TEMP TABLE tp_0_1 PARTITION OF t FOR VALUES FROM (0) TO (1);
CREATE TEMP TABLE tp_1_2 PARTITION OF t FOR VALUES FROM (1) TO (2);

SELECT c.oid::pg_catalog.regclass, pg_catalog.pg_get_expr(c.relpartbound, c.oid), c.relpersistence
  FROM pg_catalog.pg_class c, pg_catalog.pg_inherits i
  WHERE c.oid = i.inhrelid AND i.inhparent = 't'::regclass
  ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;

ALTER TABLE t MERGE PARTITIONS (tp_0_1, tp_1_2) INTO tp_0_2;

-- Partition should be temporary.
SELECT c.oid::pg_catalog.regclass, pg_catalog.pg_get_expr(c.relpartbound, c.oid), c.relpersistence
  FROM pg_catalog.pg_class c, pg_catalog.pg_inherits i
  WHERE c.oid = i.inhrelid AND i.inhparent = 't'::regclass
  ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;

DROP TABLE t;

--
-- Check the partition index name if the partition name is the same as one
-- of the merged partitions.
--
CREATE TABLE t (i int, PRIMARY KEY(i)) PARTITION BY RANGE (i);

CREATE TABLE tp_0_1 PARTITION OF t FOR VALUES FROM (0) TO (1);
CREATE TABLE tp_1_2 PARTITION OF t FOR VALUES FROM (1) TO (2);

CREATE INDEX tidx ON t(i);
ALTER TABLE t MERGE PARTITIONS (tp_1_2, tp_0_1) INTO tp_1_2;

-- Indexname values should be 'tp_1_2_pkey' and 'tp_1_2_i_idx'.
-- Not-null constraint name should be 'tp_1_2_i_not_null'.
\d+ tp_1_2

DROP TABLE t;

--
-- Try mixing permanent and temporary partitions.
--
SET search_path = partitions_merge_schema, pg_temp, public;
CREATE TABLE t (i int) PARTITION BY RANGE (i);
CREATE TABLE tp_0_1 PARTITION OF t FOR VALUES FROM (0) TO (1);
CREATE TABLE tp_1_2 PARTITION OF t FOR VALUES FROM (1) TO (2);

SELECT c.oid::pg_catalog.regclass, c.relpersistence FROM pg_catalog.pg_class c WHERE c.oid = 't'::regclass;
SELECT c.oid::pg_catalog.regclass, pg_catalog.pg_get_expr(c.relpartbound, c.oid), c.relpersistence
  FROM pg_catalog.pg_class c, pg_catalog.pg_inherits i
  WHERE c.oid = i.inhrelid AND i.inhparent = 't'::regclass
  ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;

SET search_path = pg_temp, partitions_merge_schema, public;

-- Can't merge persistent partitions into a temporary partition
ALTER TABLE t MERGE PARTITIONS (tp_0_1, tp_1_2) INTO tp_0_2;

SET search_path = partitions_merge_schema, public;

-- Can't merge persistent partitions into a temporary partition
ALTER TABLE t MERGE PARTITIONS (tp_0_1, tp_1_2) INTO pg_temp.tp_0_2;
DROP TABLE t;

SET search_path = pg_temp, partitions_merge_schema, public;

BEGIN;
CREATE TABLE t (i int) PARTITION BY RANGE (i);
CREATE TABLE tp_0_1 PARTITION OF t FOR VALUES FROM (0) TO (1);
CREATE TABLE tp_1_2 PARTITION OF t FOR VALUES FROM (1) TO (2);

SELECT c.oid::pg_catalog.regclass, c.relpersistence FROM pg_catalog.pg_class c WHERE c.oid = 't'::regclass;
SELECT c.oid::pg_catalog.regclass, pg_catalog.pg_get_expr(c.relpartbound, c.oid), c.relpersistence
  FROM pg_catalog.pg_class c, pg_catalog.pg_inherits i
  WHERE c.oid = i.inhrelid AND i.inhparent = 't'::regclass
  ORDER BY pg_catalog.pg_get_expr(c.relpartbound, c.oid) = 'DEFAULT', c.oid::pg_catalog.regclass::pg_catalog.text;

SET search_path = partitions_merge_schema, pg_temp, public;

-- Can't merge temporary partitions into a persistent partition
ALTER TABLE t MERGE PARTITIONS (tp_0_1, tp_1_2) INTO tp_0_2;
ROLLBACK;

-- Check the new partition inherits parent's tablespace
SET search_path = partitions_merge_schema, public;
CREATE TABLE t (i int PRIMARY KEY USING INDEX TABLESPACE regress_tblspace)
  PARTITION BY RANGE (i) TABLESPACE regress_tblspace;
CREATE TABLE tp_0_1 PARTITION OF t FOR VALUES FROM (0) TO (1);
CREATE TABLE tp_1_2 PARTITION OF t FOR VALUES FROM (1) TO (2);
ALTER TABLE t MERGE PARTITIONS (tp_0_1, tp_1_2) INTO tp_0_2;
SELECT tablename, tablespace FROM pg_tables
  WHERE tablename IN ('t', 'tp_0_2') AND schemaname = 'partitions_merge_schema'
  ORDER BY tablename, tablespace;
SELECT tablename, indexname, tablespace FROM pg_indexes
  WHERE tablename IN ('t', 'tp_0_2') AND schemaname = 'partitions_merge_schema'
  ORDER BY tablename, indexname, tablespace;
DROP TABLE t;

-- Check the new partition inherits parent's table access method
SET search_path = partitions_merge_schema, public;
CREATE ACCESS METHOD partitions_merge_heap TYPE TABLE HANDLER heap_tableam_handler;
CREATE TABLE t (i int) PARTITION BY RANGE (i) USING partitions_merge_heap;
CREATE TABLE tp_0_1 PARTITION OF t FOR VALUES FROM (0) TO (1);
CREATE TABLE tp_1_2 PARTITION OF t FOR VALUES FROM (1) TO (2);
ALTER TABLE t MERGE PARTITIONS (tp_0_1, tp_1_2) INTO tp_0_2;
SELECT c.relname, a.amname
FROM pg_class c JOIN pg_am a ON c.relam = a.oid
WHERE c.oid IN ('t'::regclass, 'tp_0_2'::regclass)
ORDER BY c.relname;
DROP TABLE t;
DROP ACCESS METHOD partitions_merge_heap;

-- Test permission checks.  The user needs to own the parent table and all
-- the merging partitions to do the merge.
CREATE ROLE regress_partition_merge_alice;
CREATE ROLE regress_partition_merge_bob;
GRANT ALL ON SCHEMA partitions_merge_schema TO regress_partition_merge_alice;
GRANT ALL ON SCHEMA partitions_merge_schema TO regress_partition_merge_bob;

SET SESSION AUTHORIZATION regress_partition_merge_alice;
CREATE TABLE t (i int) PARTITION BY RANGE (i);
CREATE TABLE tp_0_1 PARTITION OF t FOR VALUES FROM (0) TO (1);
CREATE TABLE tp_1_2 PARTITION OF t FOR VALUES FROM (1) TO (2);

SET SESSION AUTHORIZATION regress_partition_merge_bob;
ALTER TABLE t MERGE PARTITIONS (tp_0_1, tp_1_2) INTO tp_0_2;
RESET SESSION AUTHORIZATION;

ALTER TABLE t OWNER TO regress_partition_merge_bob;
SET SESSION AUTHORIZATION regress_partition_merge_bob;
ALTER TABLE t MERGE PARTITIONS (tp_0_1, tp_1_2) INTO tp_0_2;
RESET SESSION AUTHORIZATION;

ALTER TABLE tp_0_1 OWNER TO regress_partition_merge_bob;
SET SESSION AUTHORIZATION regress_partition_merge_bob;
ALTER TABLE t MERGE PARTITIONS (tp_0_1, tp_1_2) INTO tp_0_2;
RESET SESSION AUTHORIZATION;

ALTER TABLE tp_1_2 OWNER TO regress_partition_merge_bob;
SET SESSION AUTHORIZATION regress_partition_merge_bob;
ALTER TABLE t MERGE PARTITIONS (tp_0_1, tp_1_2) INTO tp_0_2;
RESET SESSION AUTHORIZATION;

DROP TABLE t;
REVOKE ALL ON SCHEMA partitions_merge_schema FROM regress_partition_merge_alice;
REVOKE ALL ON SCHEMA partitions_merge_schema FROM regress_partition_merge_bob;
DROP ROLE regress_partition_merge_alice;
DROP ROLE regress_partition_merge_bob;

RESET search_path;

--
DROP SCHEMA partitions_merge_schema;
DROP SCHEMA partitions_merge_schema2;
