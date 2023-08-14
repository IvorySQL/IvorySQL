-- binary_double check

CREATE TABLE binary_double_test (a binary_double);

\copy binary_double_test from 'data/binary_double.data'

SET enable_seqscan=on;

SELECT count(*) FROM binary_double_test WHERE a <  -1890.0;

SELECT count(*) FROM binary_double_test WHERE a <= -1890.0;

SELECT count(*) FROM binary_double_test WHERE a  = -1890.0;

SELECT count(*) FROM binary_double_test WHERE a >= -1890.0;

SELECT count(*) FROM binary_double_test WHERE a >  -1890.0;

CREATE INDEX binary_doubleidx ON binary_double_test USING gin ( a );

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_double_test WHERE a <  -1890.0::binary_double;
SELECT count(*) FROM binary_double_test WHERE a <  -1890.0::binary_double;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_double_test WHERE a <= -1890.0::binary_double;
SELECT count(*) FROM binary_double_test WHERE a <= -1890.0::binary_double;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_double_test WHERE a  = -1890.0::binary_double;
SELECT count(*) FROM binary_double_test WHERE a  = -1890.0::binary_double;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_double_test WHERE a >= -1890.0::binary_double;
SELECT count(*) FROM binary_double_test WHERE a >= -1890.0::binary_double;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_double_test WHERE a >  -1890.0::binary_double;
SELECT count(*) FROM binary_double_test WHERE a >  -1890.0::binary_double;
