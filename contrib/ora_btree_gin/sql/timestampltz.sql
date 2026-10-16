-- timestampltz check

SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS.FF9';

CREATE TABLE timestampltztest (a timestamp with local time zone);

\copy timestampltztest from 'data/timestamptz.data'

SET enable_seqscan=on;

SELECT count(*) FROM timestampltztest WHERE a <  '2018-12-18 10:59:54';

SELECT count(*) FROM timestampltztest WHERE a <= '2018-12-18 10:59:54';

SELECT count(*) FROM timestampltztest WHERE a  = '2018-12-18 10:59:54';

SELECT count(*) FROM timestampltztest WHERE a >= '2018-12-18 10:59:54';

SELECT count(*) FROM timestampltztest WHERE a >  '2018-12-18 10:59:54';

CREATE INDEX timestampltzidx ON timestampltztest USING gin ( a );

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestampltztest WHERE a <  '2018-12-18 10:59:54'::timestamp with local time zone;
SELECT count(*) FROM timestampltztest WHERE a <  '2018-12-18 10:59:54'::timestamp with local time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestampltztest WHERE a <= '2018-12-18 10:59:54'::timestamp with local time zone;
SELECT count(*) FROM timestampltztest WHERE a <= '2018-12-18 10:59:54'::timestamp with local time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestampltztest WHERE a  = '2018-12-18 10:59:54'::timestamp with local time zone;
SELECT count(*) FROM timestampltztest WHERE a  = '2018-12-18 10:59:54'::timestamp with local time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestampltztest WHERE a >= '2018-12-18 10:59:54'::timestamp with local time zone;
SELECT count(*) FROM timestampltztest WHERE a >=  '2018-12-18 10:59:54'::timestamp with local time zone;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM timestampltztest WHERE a >  '2018-12-18 10:59:54'::timestamp with local time zone;
SELECT count(*) FROM timestampltztest WHERE a >  '2018-12-18 10:59:54'::timestamp with local time zone;
