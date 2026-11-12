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
--
-- Comparisons must preserve the mathematical ordering across the whole
-- supported range.  Intervals are compared by converting them to a signed
-- 128-bit microsecond count; computing that count in int64 lets large but
-- perfectly valid intervals wrap around and change sign.
--
SELECT INTERVAL '106751992 00:00:00' DAY(9) TO SECOND > INTERVAL '0 00:00:00' DAY TO SECOND AS day_ovf_gt;

SELECT INTERVAL '106751992 00:00:00' DAY(9) TO SECOND > INTERVAL '1 00:00:00' DAY TO SECOND AS day_ovf_gt_small;

SELECT INTERVAL '-106751992 00:00:00' DAY(9) TO SECOND < INTERVAL '0 00:00:00' DAY TO SECOND AS day_ovf_lt;

SELECT INTERVAL '-106751992 00:00:00' DAY(9) TO SECOND < INTERVAL '-1 00:00:00' DAY TO SECOND AS day_ovf_lt_small;

-- 213503982 days plus 08:01:49.551616 is exactly 2^64 microseconds, which the
-- old int64 arithmetic reduced to zero.
SELECT INTERVAL '213503982 08:01:49.551616' DAY(9) TO SECOND(6) = INTERVAL '0 00:00:00' DAY TO SECOND AS day_2p64_eq_zero;

SELECT INTERVAL '1000000-0' YEAR(9) TO MONTH > INTERVAL '0-0' YEAR TO MONTH AS mon_ovf_gt;

SELECT INTERVAL '1000000-0' YEAR(9) TO MONTH > INTERVAL '1-0' YEAR TO MONTH AS mon_ovf_gt_small;

SELECT INTERVAL '-1000000-0' YEAR(9) TO MONTH < INTERVAL '0-0' YEAR TO MONTH AS mon_ovf_lt;

SELECT INTERVAL '-1000000-0' YEAR(9) TO MONTH < INTERVAL '-1-0' YEAR TO MONTH AS mon_ovf_lt_small;

-- MIN()/MAX() and ordered index scans must agree with the comparisons above.
CREATE TABLE test_interval_ovf(y interval year(9) to month, d interval day(9) to second(6));

INSERT INTO test_interval_ovf (y, d) VALUES
	('0-0', '0 00:00:00'),
	('1000000-0', '106751992 00:00:00'),
	('-1000000-0', '-106751992 00:00:00');

CREATE INDEX test_interval_ovf_y_btree ON test_interval_ovf(y);

CREATE INDEX test_interval_ovf_d_btree ON test_interval_ovf(d);

SELECT max(y) = INTERVAL '1000000-0' YEAR(9) TO MONTH AS mon_ovf_max FROM test_interval_ovf;

SELECT min(y) = INTERVAL '-1000000-0' YEAR(9) TO MONTH AS mon_ovf_min FROM test_interval_ovf;

SELECT max(d) = INTERVAL '106751992 00:00:00' DAY(9) TO SECOND AS day_ovf_max FROM test_interval_ovf;

SELECT min(d) = INTERVAL '-106751992 00:00:00' DAY(9) TO SECOND AS day_ovf_min FROM test_interval_ovf;

SET enable_seqscan = off;

SELECT count(*) = 2 AS mon_ovf_index_count FROM test_interval_ovf WHERE y >= INTERVAL '0-0' YEAR TO MONTH;

SELECT count(*) = 2 AS day_ovf_index_count FROM test_interval_ovf WHERE d >= INTERVAL '0 00:00:00' DAY TO SECOND;

RESET enable_seqscan;

DROP TABLE test_interval_ovf;
