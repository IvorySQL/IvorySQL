-- timestamptz check

SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS.FF9';

CREATE TABLE timestamptztest (a timestamp with time zone);

\copy timestamptztest from 'data/timestamptz.data'

SET enable_seqscan=on;

SELECT count(*) FROM timestamptztest WHERE a <  '2018-12-18 10:59:54';

SELECT count(*) FROM timestamptztest WHERE a <= '2018-12-18 10:59:54';

SELECT count(*) FROM timestamptztest WHERE a  = '2018-12-18 10:59:54';

SELECT count(*) FROM timestamptztest WHERE a >= '2018-12-18 10:59:54';

SELECT count(*) FROM timestamptztest WHERE a >  '2018-12-18 10:59:54';

CREATE INDEX timestamptzidx ON timestamptztest USING gin ( a );

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptztest WHERE a <  '2018-12-18 10:59:54'::timestamp with time zone;
SELECT count(*) FROM timestamptztest WHERE a <  '2018-12-18 10:59:54'::timestamp with time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptztest WHERE a <= '2018-12-18 10:59:54'::timestamp with time zone;
SELECT count(*) FROM timestamptztest WHERE a <= '2018-12-18 10:59:54'::timestamp with time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptztest WHERE a  = '2018-12-18 10:59:54'::timestamp with time zone;
SELECT count(*) FROM timestamptztest WHERE a  = '2018-12-18 10:59:54'::timestamp with time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptztest WHERE a >= '2018-12-18 10:59:54'::timestamp with time zone;
SELECT count(*) FROM timestamptztest WHERE a >= '2018-12-18 10:59:54'::timestamp with time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptztest WHERE a >  '2018-12-18 10:59:54'::timestamp with time zone;
SELECT count(*) FROM timestamptztest WHERE a >  '2018-12-18 10:59:54'::timestamp with time zone;
