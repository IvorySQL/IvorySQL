--
-- SPLIT PARTITION
--
-- Oracle-compatible ALTER TABLE ... SPLIT PARTITION syntax, supported
-- through the Oracle parser and executed by the PostgreSQL partitioning
-- engine.
--

--
-- RANGE partitioning
--
CREATE TABLE sales_range (salesperson_id int, sales_date date)
  PARTITION BY RANGE (sales_date);
CREATE TABLE sales_jan2022 PARTITION OF sales_range
  FOR VALUES FROM ('2022-01-01') TO ('2022-02-01');
CREATE TABLE sales_feb_mar_apr2022 PARTITION OF sales_range
  FOR VALUES FROM ('2022-02-01') TO ('2022-05-01');
CREATE TABLE sales_others PARTITION OF sales_range DEFAULT;

INSERT INTO sales_range VALUES
  (1, '2022-01-31'),
  (2, '2022-02-10'),
  (3, '2022-04-30'),
  (4, '2022-04-13'),
  (5, '2022-02-11'),
  (6, '2022-03-08'),
  (7, '2022-03-11');

SELECT tableoid::regclass, * FROM sales_range ORDER BY 1, 2;

-- split an existing range partition into three new partitions
ALTER TABLE sales_range SPLIT PARTITION sales_feb_mar_apr2022 INTO
  (PARTITION sales_feb2022 FOR VALUES FROM ('2022-02-01') TO ('2022-03-01'),
   PARTITION sales_mar2022 FOR VALUES FROM ('2022-03-01') TO ('2022-04-01'),
   PARTITION sales_apr2022 FOR VALUES FROM ('2022-04-01') TO ('2022-05-01'));

SELECT relname FROM pg_class
  WHERE relname LIKE 'sales_%' ORDER BY 1;

-- rows are redistributed to the new partitions
SELECT tableoid::regclass, * FROM sales_range ORDER BY 1, 2;

DROP TABLE sales_range;

--
-- LIST partitioning
--
CREATE TABLE sales_list (salesperson_id int, region text)
  PARTITION BY LIST (region);
CREATE TABLE sales_east_west PARTITION OF sales_list
  FOR VALUES IN ('east', 'west');
CREATE TABLE sales_others PARTITION OF sales_list DEFAULT;

INSERT INTO sales_list VALUES
  (1, 'east'),
  (2, 'west'),
  (3, 'north');

SELECT tableoid::regclass, * FROM sales_list ORDER BY 1, 2;

-- split a list partition into two
ALTER TABLE sales_list SPLIT PARTITION sales_east_west INTO
  (PARTITION sales_east FOR VALUES IN ('east'),
   PARTITION sales_west FOR VALUES IN ('west'));

SELECT relname FROM pg_class
  WHERE relname LIKE 'sales_%' ORDER BY 1;

SELECT tableoid::regclass, * FROM sales_list ORDER BY 1, 2;

DROP TABLE sales_list;
