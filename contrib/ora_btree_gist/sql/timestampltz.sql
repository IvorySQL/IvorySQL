-- timestampltz check

SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS.FF9';

CREATE TABLE timestampltztmp (a timestamp with local time zone);

\copy timestampltztmp from 'data/timestamptz.data'

SET enable_seqscan=on;

SELECT count(*) FROM timestampltztmp WHERE a <  '2018-12-18 10:59:54';

SELECT count(*) FROM timestampltztmp WHERE a <= '2018-12-18 10:59:54';

SELECT count(*) FROM timestampltztmp WHERE a  = '2018-12-18 10:59:54';

SELECT count(*) FROM timestampltztmp WHERE a >= '2018-12-18 10:59:54';

SELECT count(*) FROM timestampltztmp WHERE a >  '2018-12-18 10:59:54';

SELECT count(*) FROM timestampltztmp WHERE a <> '2018-12-18 10:59:54'::timestamp with local time zone;

SELECT a, a <-> '2018-12-18 10:59:54' FROM timestampltztmp ORDER BY a <-> '2018-12-18 10:59:54' LIMIT 3;

CREATE INDEX timestampltzidx ON timestampltztmp USING gist ( a );

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestampltztmp WHERE a <  '2018-12-18 10:59:54'::timestamp with local time zone;
SELECT count(*) FROM timestampltztmp WHERE a <  '2018-12-18 10:59:54'::timestamp with local time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestampltztmp WHERE a <= '2018-12-18 10:59:54'::timestamp with local time zone;
SELECT count(*) FROM timestampltztmp WHERE a <= '2018-12-18 10:59:54'::timestamp with local time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestampltztmp WHERE a  = '2018-12-18 10:59:54'::timestamp with local time zone;
SELECT count(*) FROM timestampltztmp WHERE a  = '2018-12-18 10:59:54'::timestamp with local time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestampltztmp WHERE a >= '2018-12-18 10:59:54'::timestamp with local time zone;
SELECT count(*) FROM timestampltztmp WHERE a >=  '2018-12-18 10:59:54'::timestamp with local time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestampltztmp WHERE a >  '2018-12-18 10:59:54'::timestamp with local time zone;
SELECT count(*) FROM timestampltztmp WHERE a >  '2018-12-18 10:59:54'::timestamp with local time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestampltztmp WHERE a <> '2018-12-18 10:59:54'::timestamp with local time zone;
SELECT count(*) FROM timestampltztmp WHERE a <> '2018-12-18 10:59:54'::timestamp with local time zone;

EXPLAIN (COSTS OFF)
SELECT a, a <-> '2018-12-18 10:59:54' FROM timestampltztmp ORDER BY a <-> '2018-12-18 10:59:54' LIMIT 3;
SELECT a, a <-> '2018-12-18 10:59:54' FROM timestampltztmp ORDER BY a <-> '2018-12-18 10:59:54' LIMIT 3;
