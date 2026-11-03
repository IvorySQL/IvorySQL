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


-- drop table
DROP TABLE TEST_YMINTERVAL;

DROP TABLE TEST_DSINTERVAL;

-- Day counts above 106751991 overflow an int64 microsecond count.  Such counts
-- are legal in Oracle mode (INTERVAL DAY(9)), so comparisons, ordering and
-- hashing must still agree for them.
SELECT interval '106751992 0:0:0' day(9) to second > interval '1 0:0:0' day(9) to second AS above_int64;

SELECT interval '999999999 0:0:0' day(9) to second > interval '0 0:0:0' day(9) to second AS max_day_gt_zero;

SELECT interval '0 0:0:0' day(9) to second > interval '999999999 0:0:0' day(9) to second AS zero_gt_max_day;

SELECT interval '999999999 0:0:0' day(9) to second = interval '0 0:0:0' day(9) to second AS max_day_eq_zero;

SELECT MIN(x), MAX(x) FROM (VALUES (interval '999999999 0:0:0' day(9) to second),
                                   (interval '0 0:0:0' day(9) to second),
                                   (interval '1 0:0:0' day(9) to second)) t(x);

SELECT x FROM (VALUES (interval '999999999 0:0:0' day(9) to second),
                      (interval '0 0:0:0' day(9) to second),
                      (interval '1 0:0:0' day(9) to second)) t(x) ORDER BY x;

-- The same day-to-microseconds scaling also feeds the '-' operator and
-- in_range(), which computes the RANGE frame boundary.  Both must handle day
-- counts above the INT64 boundary too.
SELECT interval '999999999 0:0:0' day(9) to second - interval '1 0:0:0' day(9) to second;

SELECT interval '106751992 0:0:0' day(9) to second - interval '1 0:0:0' day(9) to second;

-- The borrow and carry between the day and time fields must keep working when
-- the day count is above the INT64 boundary and the time fields differ.
SELECT interval '999999999 1:1:1' day(9) to second - interval '1 2:2:2' day(9) to second;

SELECT interval '999999999 23:59:59' day(9) to second - interval '1 0:0:0' day(9) to second;

-- subtracting and adding back must return the original value
SELECT (interval '999999999 1:1:1' day(9) to second - interval '1 2:2:2' day(9) to second)
       + interval '1 2:2:2' day(9) to second AS roundtrip;

-- Reversing the operands takes the other normalization branch (day_diff < 0
-- with time_diff > 0), and the two results must be exact opposites.
SELECT interval '1 2:2:2' day(9) to second - interval '999999999 1:1:1' day(9) to second;

SELECT (interval '999999999 1:1:1' day(9) to second - interval '1 2:2:2' day(9) to second)
     + (interval '1 2:2:2' day(9) to second - interval '999999999 1:1:1' day(9) to second) AS sum_is_zero;

SELECT id, count(*) OVER (ORDER BY d
                          RANGE BETWEEN interval '106751992 0:0:0' day(9) to second PRECEDING
                                    AND CURRENT ROW)
FROM (VALUES (1, interval '0 0:0:0' day(9) to second),
             (2, interval '1 0:0:0' day(9) to second),
             (3, interval '999999999 0:0:0' day(9) to second)) t(id, d)
ORDER BY id;

-- Indexed access must agree with the comparison above the INT64 boundary.
CREATE TABLE TEST_DSINTERVAL_BIG (a dsinterval);

INSERT INTO TEST_DSINTERVAL_BIG VALUES
  (interval '0 0:0:0' day(9) to second),
  (interval '999999998 0:0:0' day(9) to second),
  (interval '999999999 0:0:0' day(9) to second);

CREATE INDEX test_dsinterval_big_btree ON TEST_DSINTERVAL_BIG (a);

SET enable_seqscan = off;

SELECT a FROM TEST_DSINTERVAL_BIG WHERE a = interval '999999999 0:0:0' day(9) to second;

SELECT a FROM TEST_DSINTERVAL_BIG WHERE a > interval '999999998 0:0:0' day(9) to second;

SELECT a FROM TEST_DSINTERVAL_BIG ORDER BY a;

RESET enable_seqscan;

-- only the hash index may answer the equality lookups below
DROP INDEX test_dsinterval_big_btree;

CREATE INDEX test_dsinterval_big_hash ON TEST_DSINTERVAL_BIG USING hash (a);

SET enable_seqscan = off;

-- equal values must hash to the same value the index holds
SELECT count(*) FROM TEST_DSINTERVAL_BIG WHERE a = interval '0 0:0:0' day(9) to second;

SELECT count(*) FROM TEST_DSINTERVAL_BIG WHERE a = interval '999999999 0:0:0' day(9) to second;

SELECT count(*) FROM TEST_DSINTERVAL_BIG WHERE a = interval '999999997 0:0:0' day(9) to second;

RESET enable_seqscan;

DROP TABLE TEST_DSINTERVAL_BIG;
