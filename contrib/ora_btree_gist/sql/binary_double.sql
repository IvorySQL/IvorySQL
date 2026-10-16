-- binary_double check

CREATE TABLE binary_doubletmp (a binary_double);

\copy binary_doubletmp from 'data/binary_double.data'

SET enable_seqscan=on;

SELECT count(*) FROM binary_doubletmp WHERE a <  -1890.0;

SELECT count(*) FROM binary_doubletmp WHERE a <= -1890.0;

SELECT count(*) FROM binary_doubletmp WHERE a  = -1890.0;

SELECT count(*) FROM binary_doubletmp WHERE a >= -1890.0;

SELECT count(*) FROM binary_doubletmp WHERE a >  -1890.0;

SELECT count(*) FROM binary_doubletmp WHERE a <> -1890.0;

SELECT a, a <-> '-1890.0' FROM binary_doubletmp ORDER BY a <-> '-1890.0' LIMIT 3;

CREATE INDEX binary_doubleidx ON binary_doubletmp USING gist ( a );

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_doubletmp WHERE a <  -1890.0::binary_double;
SELECT count(*) FROM binary_doubletmp WHERE a <  -1890.0::binary_double;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_doubletmp WHERE a <= -1890.0::binary_double;
SELECT count(*) FROM binary_doubletmp WHERE a <= -1890.0::binary_double;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_doubletmp WHERE a  = -1890.0::binary_double;
SELECT count(*) FROM binary_doubletmp WHERE a  = -1890.0::binary_double;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_doubletmp WHERE a >= -1890.0::binary_double;
SELECT count(*) FROM binary_doubletmp WHERE a >= -1890.0::binary_double;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_doubletmp WHERE a >  -1890.0::binary_double;
SELECT count(*) FROM binary_doubletmp WHERE a >  -1890.0::binary_double;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM binary_doubletmp WHERE a <> -1890.0::binary_double;
SELECT count(*) FROM binary_doubletmp WHERE a <> -1890.0::binary_double;

EXPLAIN (COSTS OFF)
SELECT a, a <-> '-1890.0' FROM binary_doubletmp ORDER BY a <-> '-1890.0' LIMIT 3;
SELECT a, a <-> '-1890.0' FROM binary_doubletmp ORDER BY a <-> '-1890.0' LIMIT 3;
