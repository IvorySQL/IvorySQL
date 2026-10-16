-- date check

SET NLS_date_FORMAT='YYYY-MM-DD HH24:MI:SS.FF9';

CREATE TABLE datetmp(a DATE);

\copy datetmp from 'data/date.data'

SET enable_seqscan=on;

SELECT count(*) FROM datetmp WHERE a <  '2016-11-27';

SELECT count(*) FROM datetmp WHERE a <= '2016-11-27';

SELECT count(*) FROM datetmp WHERE a  = '2016-11-27';

SELECT count(*) FROM datetmp WHERE a >= '2016-11-27';

SELECT count(*) FROM datetmp WHERE a >  '2016-11-27';

SELECT count(*) FROM datetmp WHERE a <> '2016-11-27';

SELECT a, a <-> '2016-11-27' FROM datetmp ORDER BY a <-> '2016-11-27' LIMIT 3;

CREATE INDEX dateidx on datetmp USING gist(a);

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM datetmp WHERE a <  '2016-11-27'::date;
SELECT count(*) FROM datetmp WHERE a <  '2016-11-27'::date;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM datetmp WHERE a <= '2016-11-27'::date;
SELECT count(*) FROM datetmp WHERE a <= '2016-11-27'::date;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM datetmp WHERE a  = '2016-11-27'::date;
SELECT count(*) FROM datetmp WHERE a  = '2016-11-27'::date;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM datetmp WHERE a >= '2016-11-27'::date;
SELECT count(*) FROM datetmp WHERE a >= '2016-11-27'::date;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM datetmp WHERE a >  '2016-11-27'::date;
SELECT count(*) FROM datetmp WHERE a >  '2016-11-27'::date;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM datetmp WHERE a <> '2016-11-27';
SELECT count(*) FROM datetmp WHERE a <> '2016-11-27'::date;

EXPLAIN (COSTS OFF)
SELECT a, a <-> '2016-11-27' FROM datetmp ORDER BY a <-> '2016-11-27' LIMIT 3;
SELECT a, a <-> '2016-11-27' FROM datetmp ORDER BY a <-> '2016-11-27' LIMIT 3;
