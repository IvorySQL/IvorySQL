-- timestamptz check

SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS.FF9';

CREATE TABLE timestamptztmp (a timestamp with time zone);

\copy timestamptztmp from 'data/timestamptz.data'

SET enable_seqscan=on;

SELECT count(*) FROM timestamptztmp WHERE a <  '2018-12-18 10:59:54';

SELECT count(*) FROM timestamptztmp WHERE a <= '2018-12-18 10:59:54';

SELECT count(*) FROM timestamptztmp WHERE a  = '2018-12-18 10:59:54';

SELECT count(*) FROM timestamptztmp WHERE a >= '2018-12-18 10:59:54';

SELECT count(*) FROM timestamptztmp WHERE a >  '2018-12-18 10:59:54';

SELECT count(*) FROM timestamptztmp WHERE a <> '2018-12-18 10:59:54';

SELECT a, a <-> '2018-12-18 10:59:54' FROM timestamptztmp ORDER BY a <-> '2018-12-18 10:59:54' LIMIT 3;

CREATE INDEX timestamptzidx ON timestamptztmp USING gist ( a );

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptztmp WHERE a <  '2018-12-18 10:59:54'::timestamp with time zone;
SELECT count(*) FROM timestamptztmp WHERE a <  '2018-12-18 10:59:54'::timestamp with time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptztmp WHERE a <= '2018-12-18 10:59:54'::timestamp with time zone;
SELECT count(*) FROM timestamptztmp WHERE a <= '2018-12-18 10:59:54'::timestamp with time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptztmp WHERE a  = '2018-12-18 10:59:54'::timestamp with time zone;
SELECT count(*) FROM timestamptztmp WHERE a  = '2018-12-18 10:59:54'::timestamp with time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptztmp WHERE a >= '2018-12-18 10:59:54'::timestamp with time zone;
SELECT count(*) FROM timestamptztmp WHERE a >= '2018-12-18 10:59:54'::timestamp with time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptztmp WHERE a >  '2018-12-18 10:59:54'::timestamp with time zone;
SELECT count(*) FROM timestamptztmp WHERE a >  '2018-12-18 10:59:54'::timestamp with time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestamptztmp WHERE a <> '2018-12-18 10:59:54'::timestamp with time zone;
SELECT count(*) FROM timestamptztmp WHERE a <> '2018-12-18 10:59:54'::timestamp with time zone;

EXPLAIN (COSTS OFF)
SELECT a, a <-> '2018-12-18 10:59:54' FROM timestamptztmp ORDER BY a <-> '2018-12-18 10:59:54' LIMIT 3;
SELECT a, a <-> '2018-12-18 10:59:54' FROM timestamptztmp ORDER BY a <-> '2018-12-18 10:59:54' LIMIT 3;
