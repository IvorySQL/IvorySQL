--
-- INTERVAL YEAR TO MONTH
--

-- Valid Interval Literals
SELECT INTERVAL'1-1' YEAR TO MONTH;

SELECT INTERVAL '123-2' YEAR(3) TO MONTH;

SELECT INTERVAL'11' YEAR;

SELECT INTERVAL'356' YEAR(3);

SELECT INTERVAL'12' MONTH;

SELECT INTERVAL'1200' MONTH(3);


-- If the leading field is YEAR and the trailing field is MONTH, 
-- then the range of integer values for the month field is 0 to 11.
SELECT INTERVAL'1-11' YEAR TO MONTH;

SELECT INTERVAL'1-12' YEAR TO MONTH;	

CREATE TABLE TEST_YMINTERVAL(a interval year(4) to month);

INSERT INTO TEST_YMINTERVAL (a) VALUES ('0-1');

INSERT INTO TEST_YMINTERVAL (a) VALUES ('1-2');

INSERT INTO TEST_YMINTERVAL (a) VALUES ('12-3');

INSERT INTO TEST_YMINTERVAL (a) VALUES ('123-4');

INSERT INTO TEST_YMINTERVAL (a) VALUES ('1234-5');

-- Precision out of range
INSERT INTO TEST_YMINTERVAL (a) VALUES ('12345-6');


-- Comparison operator
SELECT * FROM TEST_YMINTERVAL WHERE TEST_YMINTERVAL.a = interval'12-3' year to month;

SELECT * FROM TEST_YMINTERVAL WHERE TEST_YMINTERVAL.a <> interval'12-3' year to month;

SELECT * FROM TEST_YMINTERVAL WHERE TEST_YMINTERVAL.a > interval'12-3' year to month;

SELECT * FROM TEST_YMINTERVAL WHERE TEST_YMINTERVAL.a >= interval'12-3' year to month;

SELECT * FROM TEST_YMINTERVAL WHERE TEST_YMINTERVAL.a < interval'12-3' year to month;

SELECT * FROM TEST_YMINTERVAL WHERE TEST_YMINTERVAL.a <= interval'12-3' year to month;


-- "+" operator
SELECT TEST_YMINTERVAL.a + interval'1-1' year to month FROM TEST_YMINTERVAL;

-- "-" operator
SELECT TEST_YMINTERVAL.a - interval'1-1' year to month FROM TEST_YMINTERVAL;


-- AGGREGATE
SELECT MAX(a) FROM TEST_YMINTERVAL;

SELECT MIN(a) FROM TEST_YMINTERVAL;


-- index 
CREATE INDEX test_yminterval_btree on TEST_YMINTERVAL(a);

CREATE INDEX test_yminterval_hash on TEST_YMINTERVAL USING hash (a);

CREATE INDEX test_yminterval_brin on TEST_YMINTERVAL USING brin (a);


--
-- INTERVAL DAY TO SECOND
--

-- Valid Interval Literals
SELECT INTERVAL '4 5:12:10.222' DAY TO SECOND(3);

SELECT INTERVAL '4 5:12' DAY TO MINUTE;

SELECT INTERVAL '400 5' DAY(3) TO HOUR;

SELECT INTERVAL '400' DAY(3);

SELECT INTERVAL '11:12:10.2222222' HOUR TO SECOND(7);

SELECT INTERVAL '11:20' HOUR TO MINUTE;

SELECT INTERVAL '10' HOUR;

SELECT INTERVAL '10:22' MINUTE TO SECOND;

SELECT INTERVAL '10' MINUTE;

SELECT INTERVAL '4' DAY;

SELECT INTERVAL '25' HOUR;

SELECT INTERVAL '40' MINUTE;

SELECT INTERVAL '120' HOUR(3);

SELECT INTERVAL '30.12345' SECOND(2,4);


-- The valid range of values for the trailing field are as follows:
-- HOUR: 0 to 23
-- MINUTE: 0 to 59
-- SECOND: 0 to 59.999999999
SELECT INTERVAL '400 24' DAY(3) TO HOUR;	--ERROR

SELECT INTERVAL '4 5:60' DAY TO MINUTE;		--ERROR

SELECT INTERVAL '4 5:12:60' DAY TO SECOND(3);	--ERROR	


CREATE TABLE TEST_DSINTERVAL(a interval day(4) to second(6));

INSERT INTO TEST_DSINTERVAL (a) VALUES ('0 0:0:0');

INSERT INTO TEST_DSINTERVAL (a) VALUES ('1 1:1:1.123');

INSERT INTO TEST_DSINTERVAL (a) VALUES ('12 1:1:1.123456');

INSERT INTO TEST_DSINTERVAL (a) VALUES ('123 1:1:1.123456789');

INSERT INTO TEST_DSINTERVAL (a) VALUES ('1234 1:1:1.123456789');

-- Precision out of range
INSERT INTO TEST_DSINTERVAL (a) VALUES ('12345 1:1:1.123456');


-- Comparison operator
SELECT * FROM TEST_DSINTERVAL WHERE TEST_DSINTERVAL.a = interval'12 1:1:1.123456' day to second;

SELECT * FROM TEST_DSINTERVAL WHERE TEST_DSINTERVAL.a <> interval'12 1:1:1.123456' day to second;

SELECT * FROM TEST_DSINTERVAL WHERE TEST_DSINTERVAL.a > interval'12 1:1:1.123456' day to second;

SELECT * FROM TEST_DSINTERVAL WHERE TEST_DSINTERVAL.a >= interval'12 1:1:1.123456' day to second;

SELECT * FROM TEST_DSINTERVAL WHERE TEST_DSINTERVAL.a < interval'12 1:1:1.123456' day to second;

SELECT * FROM TEST_DSINTERVAL WHERE TEST_DSINTERVAL.a <= interval'12 1:1:1.123456' day to second;


-- "+" operator
SELECT TEST_DSINTERVAL.a + interval'1 1:1:1' day to second FROM TEST_DSINTERVAL;

-- "-" operator
SELECT TEST_DSINTERVAL.a - interval'1 1:1:1' day to second FROM TEST_DSINTERVAL;

-- AGGREGATE
SELECT MAX(a) FROM TEST_DSINTERVAL;

SELECT MIN(a) FROM TEST_DSINTERVAL;


-- index
CREATE INDEX test_dsinterval_btree on TEST_DSINTERVAL(a);

CREATE INDEX test_dsinterval_hash on TEST_DSINTERVAL USING hash (a);

CREATE INDEX test_dsinterval_brin on TEST_DSINTERVAL USING brin (a);


-- Large values must retain their mathematical ordering after their linear
-- microsecond representation exceeds int64.
WITH intervals AS (
    SELECT INTERVAL '106751992 00:00:00' DAY(9) TO SECOND AS ds_positive,
           INTERVAL '-106751992 00:00:00' DAY(9) TO SECOND AS ds_negative,
           INTERVAL '213503982 08:01:49.551616' DAY(9) TO SECOND(6) AS ds_wrap,
           INTERVAL '0 00:00:00' DAY TO SECOND AS ds_zero,
           INTERVAL '1000000-0' YEAR(9) TO MONTH AS ym_positive,
           INTERVAL '0-0' YEAR TO MONTH AS ym_zero
)
SELECT ds_positive > ds_zero AS ds_positive_gt_zero,
       ds_negative < ds_zero AS ds_negative_lt_zero,
       ym_positive > ym_zero AS ym_positive_gt_zero,
       ds_wrap = ds_zero AS ds_wraps_to_zero
FROM intervals;

WITH intervals AS (
    SELECT INTERVAL '106751992 00:00:00' DAY(9) TO SECOND AS ds_positive,
           INTERVAL '0 00:00:00' DAY TO SECOND AS ds_zero
)
SELECT ds_positive < ds_zero AS lt,
       ds_positive <= ds_zero AS le,
       ds_positive = ds_zero AS eq,
       ds_positive >= ds_zero AS ge,
       ds_positive > ds_zero AS gt,
       ds_positive <> ds_zero AS ne
FROM intervals;

-- RANGE support must use the wide comparison value for offset sign and bounds.
SELECT sys.dsin_range(INTERVAL '0 00:00:00' DAY TO SECOND,
                       INTERVAL '0 00:00:00' DAY TO SECOND,
                       INTERVAL '106751992 00:00:00' DAY(9) TO SECOND,
                       true, true) AS sub_less,
       sys.dsin_range(INTERVAL '0 00:00:00' DAY TO SECOND,
                       INTERVAL '0 00:00:00' DAY TO SECOND,
                       INTERVAL '106751992 00:00:00' DAY(9) TO SECOND,
                       true, false) AS sub_greater,
       sys.dsin_range(INTERVAL '0 00:00:00' DAY TO SECOND,
                       INTERVAL '0 00:00:00' DAY TO SECOND,
                       INTERVAL '106751992 00:00:00' DAY(9) TO SECOND,
                       false, true) AS add_less,
       sys.dsin_range(INTERVAL '0 00:00:00' DAY TO SECOND,
                       INTERVAL '0 00:00:00' DAY TO SECOND,
                       INTERVAL '106751992 00:00:00' DAY(9) TO SECOND,
                       false, false) AS add_greater;

SELECT sys.ymin_range(INTERVAL '0-0' YEAR TO MONTH,
                      INTERVAL '0-0' YEAR TO MONTH,
                      INTERVAL '1000000-0' YEAR(9) TO MONTH,
                      false, true) AS ym_range_accepted;

CREATE TEMP TABLE interval_overflow_ds_window(a interval day(9) to second(6));
INSERT INTO interval_overflow_ds_window VALUES
    (INTERVAL '0 00:00:00' DAY TO SECOND),
    (INTERVAL '106751992 00:00:00' DAY(9) TO SECOND);
SELECT count(*) OVER (ORDER BY a RANGE BETWEEN
                      INTERVAL '106751992 00:00:00' DAY(9) TO SECOND PRECEDING
                      AND CURRENT ROW) AS preceding_count,
       count(*) OVER (ORDER BY a RANGE BETWEEN CURRENT ROW AND
                      INTERVAL '106751992 00:00:00' DAY(9) TO SECOND FOLLOWING) AS following_count
FROM interval_overflow_ds_window ORDER BY a;

CREATE TEMP TABLE interval_overflow_ym_window(a interval year(9) to month);
INSERT INTO interval_overflow_ym_window VALUES
    (INTERVAL '178956970-06' YEAR(9) TO MONTH),
    (INTERVAL '178956970-07' YEAR(9) TO MONTH);
SELECT count(*) OVER (ORDER BY a RANGE BETWEEN CURRENT ROW AND
                      INTERVAL '0-01' YEAR TO MONTH FOLLOWING) AS following_count
FROM interval_overflow_ym_window ORDER BY a;

-- Preserve low-64-bit hashes while equality distinguishes these values.
SELECT sys.dsinterval_hash(INTERVAL '213503982 08:01:49.551616' DAY(9) TO SECOND(6)) =
       sys.dsinterval_hash(INTERVAL '0 00:00:00' DAY TO SECOND) AS hash_low64_preserved,
       sys.dsinterval_hash_extended(INTERVAL '213503982 08:01:49.551616' DAY(9) TO SECOND(6), 42) =
       sys.dsinterval_hash_extended(INTERVAL '0 00:00:00' DAY TO SECOND, 42) AS extended_hash_low64_preserved;

CREATE TEMP TABLE interval_overflow_ds_unique(
    a interval day(9) to second(6) UNIQUE
);
INSERT INTO interval_overflow_ds_unique VALUES
    (INTERVAL '0 00:00:00' DAY TO SECOND),
    (INTERVAL '213503982 08:01:49.551616' DAY(9) TO SECOND(6));
SELECT a FROM interval_overflow_ds_unique ORDER BY a;
SELECT count(DISTINCT a) AS distinct_count, min(a), max(a)
FROM interval_overflow_ds_unique;


-- drop table
DROP TABLE TEST_YMINTERVAL;

DROP TABLE TEST_DSINTERVAL;
