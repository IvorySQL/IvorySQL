-- binary_float check

CREATE TABLE binary_floattmp (a binary_float);

\copy binary_floattmp from 'data/binary_float.data'

SET enable_seqscan=on;

SELECT count(*) FROM binary_floattmp WHERE a <  -179.0;

SELECT count(*) FROM binary_floattmp WHERE a <= -179.0;

SELECT count(*) FROM binary_floattmp WHERE a  = -179.0;

SELECT count(*) FROM binary_floattmp WHERE a >= -179.0;

SELECT count(*) FROM binary_floattmp WHERE a >  -179.0;

SELECT count(*) FROM binary_floattmp WHERE a <> -179.0;

SELECT a, a <-> '-179.0' FROM binary_floattmp ORDER BY a <-> '-179.0' LIMIT 3;

CREATE INDEX binary_floatidx ON binary_floattmp USING gist ( a );

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_floattmp WHERE a <  -179.0::binary_float;
SELECT count(*) FROM binary_floattmp WHERE a <  -179.0::binary_float;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_floattmp WHERE a <= -179.0::binary_float;
SELECT count(*) FROM binary_floattmp WHERE a <= -179.0::binary_float;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_floattmp WHERE a  = -179.0::binary_float;
SELECT count(*) FROM binary_floattmp WHERE a  = -179.0::binary_float;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_floattmp WHERE a >= -179.0::binary_float;
SELECT count(*) FROM binary_floattmp WHERE a >= -179.0::binary_float;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_floattmp WHERE a >  -179.0::binary_float;
SELECT count(*) FROM binary_floattmp WHERE a >  -179.0::binary_float;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_floattmp WHERE a <> -179.0::binary_float;
SELECT count(*) FROM binary_floattmp WHERE a <> -179.0::binary_float;

EXPLAIN (COSTS OFF)
SELECT a, a <-> '-179.0' FROM binary_floattmp ORDER BY a <-> '-179.0' LIMIT 3;
SELECT a, a <-> '-179.0' FROM binary_floattmp ORDER BY a <-> '-179.0' LIMIT 3;
