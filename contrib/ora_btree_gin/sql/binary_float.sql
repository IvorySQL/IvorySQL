-- binary_float check

CREATE TABLE binary_float_test (a binary_float);

\copy binary_float_test from 'data/binary_float.data'

SET enable_seqscan=on;

SELECT count(*) FROM binary_float_test WHERE a <  179.0;

SELECT count(*) FROM binary_float_test WHERE a <= 179.0;

SELECT count(*) FROM binary_float_test WHERE a  = 179.0;

SELECT count(*) FROM binary_float_test WHERE a >= 179.0;

SELECT count(*) FROM binary_float_test WHERE a >  179.0;

CREATE INDEX binary_floatidx ON binary_float_test USING gin ( a );

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_float_test WHERE a <  179.0::binary_float;
SELECT count(*) FROM binary_float_test WHERE a <  179.0::binary_float;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_float_test WHERE a <= 179.0::binary_float;
SELECT count(*) FROM binary_float_test WHERE a <= 179.0::binary_float;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_float_test WHERE a  = 179.0::binary_float;
SELECT count(*) FROM binary_float_test WHERE a  = 179.0::binary_float;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_float_test WHERE a >= 179.0::binary_float;
SELECT count(*) FROM binary_float_test WHERE a >= 179.0::binary_float;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_float_test WHERE a >  179.0::binary_float;
SELECT count(*) FROM binary_float_test WHERE a >  179.0::binary_float;

