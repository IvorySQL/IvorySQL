-- timestamp check

SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS.FF9';

CREATE TABLE timestamptest (a timestamp);

\copy timestamptest from 'data/timestamp.data'

SET enable_seqscan=on;

SELECT count(*) FROM timestamptest WHERE a <  '2004-10-26 08:55:08';

SELECT count(*) FROM timestamptest WHERE a <= '2004-10-26 08:55:08';

SELECT count(*) FROM timestamptest WHERE a  = '2004-10-26 08:55:08';

SELECT count(*) FROM timestamptest WHERE a >= '2004-10-26 08:55:08';

SELECT count(*) FROM timestamptest WHERE a >  '2004-10-26 08:55:08';

CREATE INDEX timestampidx ON timestamptest USING gin ( a );

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptest WHERE a <  '2004-10-26 08:55:08'::timestamp;
SELECT count(*) FROM timestamptest WHERE a <  '2004-10-26 08:55:08'::timestamp;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptest WHERE a <= '2004-10-26 08:55:08'::timestamp;
SELECT count(*) FROM timestamptest WHERE a <= '2004-10-26 08:55:08'::timestamp;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptest WHERE a  = '2004-10-26 08:55:08'::timestamp;
SELECT count(*) FROM timestamptest WHERE a  = '2004-10-26 08:55:08'::timestamp;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptest WHERE a >= '2004-10-26 08:55:08'::timestamp;
SELECT count(*) FROM timestamptest WHERE a >= '2004-10-26 08:55:08'::timestamp;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptest WHERE a >  '2004-10-26 08:55:08'::timestamp;
SELECT count(*) FROM timestamptest WHERE a >  '2004-10-26 08:55:08'::timestamp;
