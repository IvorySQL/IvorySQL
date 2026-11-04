-- NaN ordering must agree between sequential and GiST scans.

CREATE TABLE special_binary_float (v binary_float);
INSERT INTO special_binary_float
SELECT v::binary_float
FROM (VALUES ('-Infinity'), ('-1'), ('0'), ('1'), ('Infinity'), ('NaN')) AS t(v),
     generate_series(1, 200);
SET enable_indexscan = off;
SET enable_bitmapscan = off;
SET enable_seqscan = on;

SELECT '<' AS op, count(*) FROM special_binary_float WHERE v < 'NaN'::binary_float
UNION ALL
SELECT '<=' AS op, count(*) FROM special_binary_float WHERE v <= 'NaN'::binary_float
UNION ALL
SELECT '=' AS op, count(*) FROM special_binary_float WHERE v = 'NaN'::binary_float
UNION ALL
SELECT '>=' AS op, count(*) FROM special_binary_float WHERE v >= 'NaN'::binary_float
UNION ALL
SELECT '>' AS op, count(*) FROM special_binary_float WHERE v > 'NaN'::binary_float
UNION ALL
SELECT '<>' AS op, count(*) FROM special_binary_float WHERE v <> 'NaN'::binary_float;

CREATE INDEX special_binary_float_idx ON special_binary_float USING gist(v);
SET enable_indexscan = on;
SET enable_seqscan = off;
EXPLAIN (COSTS OFF)
SELECT count(*) FROM special_binary_float WHERE v = 'NaN'::binary_float;

SELECT '<' AS op, count(*) FROM special_binary_float WHERE v < 'NaN'::binary_float
UNION ALL
SELECT '<=' AS op, count(*) FROM special_binary_float WHERE v <= 'NaN'::binary_float
UNION ALL
SELECT '=' AS op, count(*) FROM special_binary_float WHERE v = 'NaN'::binary_float
UNION ALL
SELECT '>=' AS op, count(*) FROM special_binary_float WHERE v >= 'NaN'::binary_float
UNION ALL
SELECT '>' AS op, count(*) FROM special_binary_float WHERE v > 'NaN'::binary_float
UNION ALL
SELECT '<>' AS op, count(*) FROM special_binary_float WHERE v <> 'NaN'::binary_float;

-- Exercise insertion/penalty as well as the initial index build/picksplit.
INSERT INTO special_binary_float SELECT * FROM special_binary_float;

SELECT '<' AS op, count(*) FROM special_binary_float WHERE v < 'NaN'::binary_float
UNION ALL
SELECT '<=' AS op, count(*) FROM special_binary_float WHERE v <= 'NaN'::binary_float
UNION ALL
SELECT '=' AS op, count(*) FROM special_binary_float WHERE v = 'NaN'::binary_float
UNION ALL
SELECT '>=' AS op, count(*) FROM special_binary_float WHERE v >= 'NaN'::binary_float
UNION ALL
SELECT '>' AS op, count(*) FROM special_binary_float WHERE v > 'NaN'::binary_float
UNION ALL
SELECT '<>' AS op, count(*) FROM special_binary_float WHERE v <> 'NaN'::binary_float;

-- NaNs and identical infinities have zero distance from themselves.
SELECT 'NaN'::binary_float <-> 'NaN'::binary_float AS nan_nan,
       'NaN'::binary_float <-> '0'::binary_float AS nan_zero,
       'Infinity'::binary_float <-> 'Infinity'::binary_float AS inf_inf,
       '-Infinity'::binary_float <-> '-Infinity'::binary_float AS neginf_neginf;
EXPLAIN (COSTS OFF)
SELECT v FROM special_binary_float ORDER BY v <-> 'NaN'::binary_float LIMIT 3;
SELECT v, v <-> 'NaN'::binary_float AS distance FROM special_binary_float
ORDER BY v <-> 'NaN'::binary_float LIMIT 3;
SELECT v, v <-> 'Infinity'::binary_float AS distance FROM special_binary_float
ORDER BY v <-> 'Infinity'::binary_float LIMIT 3;
CREATE TABLE exclude_binary_float (v binary_float, EXCLUDE USING gist(v WITH =));
INSERT INTO exclude_binary_float VALUES ('NaN');
INSERT INTO exclude_binary_float VALUES ('NaN'); -- must conflict
SELECT count(*) FROM exclude_binary_float;
DROP TABLE exclude_binary_float;
DROP TABLE special_binary_float;
RESET enable_indexscan;
RESET enable_bitmapscan;
RESET enable_seqscan;

CREATE TABLE special_binary_double (v binary_double);
INSERT INTO special_binary_double
SELECT v::binary_double
FROM (VALUES ('-Infinity'), ('-1'), ('0'), ('1'), ('Infinity'), ('NaN')) AS t(v),
     generate_series(1, 200);
SET enable_indexscan = off;
SET enable_bitmapscan = off;
SET enable_seqscan = on;

SELECT '<' AS op, count(*) FROM special_binary_double WHERE v < 'NaN'::binary_double
UNION ALL
SELECT '<=' AS op, count(*) FROM special_binary_double WHERE v <= 'NaN'::binary_double
UNION ALL
SELECT '=' AS op, count(*) FROM special_binary_double WHERE v = 'NaN'::binary_double
UNION ALL
SELECT '>=' AS op, count(*) FROM special_binary_double WHERE v >= 'NaN'::binary_double
UNION ALL
SELECT '>' AS op, count(*) FROM special_binary_double WHERE v > 'NaN'::binary_double
UNION ALL
SELECT '<>' AS op, count(*) FROM special_binary_double WHERE v <> 'NaN'::binary_double;

CREATE INDEX special_binary_double_idx ON special_binary_double USING gist(v);
SET enable_indexscan = on;
SET enable_seqscan = off;
EXPLAIN (COSTS OFF)
SELECT count(*) FROM special_binary_double WHERE v = 'NaN'::binary_double;

SELECT '<' AS op, count(*) FROM special_binary_double WHERE v < 'NaN'::binary_double
UNION ALL
SELECT '<=' AS op, count(*) FROM special_binary_double WHERE v <= 'NaN'::binary_double
UNION ALL
SELECT '=' AS op, count(*) FROM special_binary_double WHERE v = 'NaN'::binary_double
UNION ALL
SELECT '>=' AS op, count(*) FROM special_binary_double WHERE v >= 'NaN'::binary_double
UNION ALL
SELECT '>' AS op, count(*) FROM special_binary_double WHERE v > 'NaN'::binary_double
UNION ALL
SELECT '<>' AS op, count(*) FROM special_binary_double WHERE v <> 'NaN'::binary_double;

-- Exercise insertion/penalty as well as the initial index build/picksplit.
INSERT INTO special_binary_double SELECT * FROM special_binary_double;

SELECT '<' AS op, count(*) FROM special_binary_double WHERE v < 'NaN'::binary_double
UNION ALL
SELECT '<=' AS op, count(*) FROM special_binary_double WHERE v <= 'NaN'::binary_double
UNION ALL
SELECT '=' AS op, count(*) FROM special_binary_double WHERE v = 'NaN'::binary_double
UNION ALL
SELECT '>=' AS op, count(*) FROM special_binary_double WHERE v >= 'NaN'::binary_double
UNION ALL
SELECT '>' AS op, count(*) FROM special_binary_double WHERE v > 'NaN'::binary_double
UNION ALL
SELECT '<>' AS op, count(*) FROM special_binary_double WHERE v <> 'NaN'::binary_double;

-- NaNs and identical infinities have zero distance from themselves.
SELECT 'NaN'::binary_double <-> 'NaN'::binary_double AS nan_nan,
       'NaN'::binary_double <-> '0'::binary_double AS nan_zero,
       'Infinity'::binary_double <-> 'Infinity'::binary_double AS inf_inf,
       '-Infinity'::binary_double <-> '-Infinity'::binary_double AS neginf_neginf;
EXPLAIN (COSTS OFF)
SELECT v FROM special_binary_double ORDER BY v <-> 'NaN'::binary_double LIMIT 3;
SELECT v, v <-> 'NaN'::binary_double AS distance FROM special_binary_double
ORDER BY v <-> 'NaN'::binary_double LIMIT 3;
SELECT v, v <-> 'Infinity'::binary_double AS distance FROM special_binary_double
ORDER BY v <-> 'Infinity'::binary_double LIMIT 3;
CREATE TABLE exclude_binary_double (v binary_double, EXCLUDE USING gist(v WITH =));
INSERT INTO exclude_binary_double VALUES ('NaN');
INSERT INTO exclude_binary_double VALUES ('NaN'); -- must conflict
SELECT count(*) FROM exclude_binary_double;
DROP TABLE exclude_binary_double;
DROP TABLE special_binary_double;
RESET enable_indexscan;
RESET enable_bitmapscan;
RESET enable_seqscan;
