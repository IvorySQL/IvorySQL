-- date check

SET NLS_date_FORMAT='YYYY-MM-DD HH24:MI:SS.FF9';

CREATE TABLE datetest(a DATE);

\copy datetest from 'data/date.data'

SET enable_seqscan=on;

SELECT count(*) FROM datetest WHERE a <  '2016-11-27';

SELECT count(*) FROM datetest WHERE a <= '2016-11-27';

SELECT count(*) FROM datetest WHERE a  = '2016-11-27';

SELECT count(*) FROM datetest WHERE a >= '2016-11-27';

SELECT count(*) FROM datetest WHERE a >  '2016-11-27';

CREATE INDEX dateidx on datetest USING gin(a);

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM datetest WHERE a <  '2016-11-27'::date;
SELECT count(*) FROM datetest WHERE a <  '2016-11-27'::date;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM datetest WHERE a <= '2016-11-27'::date;
SELECT count(*) FROM datetest WHERE a <= '2016-11-27'::date;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM datetest WHERE a  = '2016-11-27'::date;
SELECT count(*) FROM datetest WHERE a  = '2016-11-27'::date;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM datetest WHERE a >= '2016-11-27'::date;
SELECT count(*) FROM datetest WHERE a >= '2016-11-27'::date;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM datetest WHERE a >  '2016-11-27'::date;
SELECT count(*) FROM datetest WHERE a >  '2016-11-27'::date;
