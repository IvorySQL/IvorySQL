--
-- MERGE PARTITIONS
--
-- Oracle-compatible ALTER TABLE ... MERGE PARTITIONS syntax, supported
-- through the Oracle parser and executed by the PostgreSQL partitioning
-- engine.
--

--
-- RANGE partitioning
--
CREATE TABLE sales_range (salesperson_id int, sales_date date)
  PARTITION BY RANGE (sales_date);
CREATE TABLE sales_feb2022 PARTITION OF sales_range
  FOR VALUES FROM ('2022-02-01') TO ('2022-03-01');
CREATE TABLE sales_mar2022 PARTITION OF sales_range
  FOR VALUES FROM ('2022-03-01') TO ('2022-04-01');
CREATE TABLE sales_apr2022 PARTITION OF sales_range
  FOR VALUES FROM ('2022-04-01') TO ('2022-05-01');

INSERT INTO sales_range VALUES
  (1, '2022-02-10'),
  (2, '2022-04-30'),
  (3, '2022-04-13'),
  (4, '2022-02-11'),
  (5, '2022-03-08'),
  (6, '2022-03-11');

SELECT tableoid::regclass, * FROM sales_range ORDER BY 1, 2;

-- merge three range partitions into one
ALTER TABLE sales_range MERGE PARTITIONS
  (sales_feb2022, sales_mar2022, sales_apr2022) INTO sales_feb_mar_apr2022;

SELECT relname FROM pg_class
  WHERE relname LIKE 'sales_%' ORDER BY 1;

-- rows are redistributed to the merged partition
SELECT tableoid::regclass, * FROM sales_range ORDER BY 1, 2;

DROP TABLE sales_range;

--
-- LIST partitioning
--
CREATE TABLE sales_list (salesperson_id int, region text)
  PARTITION BY LIST (region);
CREATE TABLE sales_east PARTITION OF sales_list
  FOR VALUES IN ('east');
CREATE TABLE sales_west PARTITION OF sales_list
  FOR VALUES IN ('west');
CREATE TABLE sales_others PARTITION OF sales_list DEFAULT;

INSERT INTO sales_list VALUES
  (1, 'east'),
  (2, 'west'),
  (3, 'north');

SELECT tableoid::regclass, * FROM sales_list ORDER BY 1, 2;

-- merge two list partitions into one
ALTER TABLE sales_list MERGE PARTITIONS (sales_east, sales_west)
  INTO sales_east_west;

SELECT relname FROM pg_class
  WHERE relname LIKE 'sales_%' ORDER BY 1;

SELECT tableoid::regclass, * FROM sales_list ORDER BY 1, 2;

DROP TABLE sales_list;
