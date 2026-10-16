-- yminterval check

CREATE TABLE ymintervaltmp(a interval year(5) to month);

\copy ymintervaltmp from 'data/yminterval.data'

SET enable_seqscan=on;

SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a <  interval'12-3' year to month;

SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a <= interval'12-3' year to month;

SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a  = interval'12-3' year to month;

SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a >= interval'12-3' year to month;

SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a >  interval'12-3' year to month;

SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a <> interval'12-3' year to month;

SELECT a, a <-> interval'12-3' year to month FROM ymintervaltmp ORDER BY a <-> interval'12-3' year to month LIMIT 3;

CREATE INDEX ymintervalidx on ymintervaltmp USING gist(a);

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a <  interval'12-3' year to month;
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a <  interval'12-3' year to month;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a <= interval'12-3' year to month;
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a <= interval'12-3' year to month;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a  = interval'12-3' year to month;
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a  = interval'12-3' year to month;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a >= interval'12-3' year to month;
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a >= interval'12-3' year to month;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a >  interval'12-3' year to month;
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a >  interval'12-3' year to month;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a <> interval'12-3' year to month;
SELECT count(*) FROM ymintervaltmp WHERE ymintervaltmp.a <> interval'12-3' year to month;

EXPLAIN (COSTS OFF)
SELECT a, a <-> interval'12-3' year to month FROM ymintervaltmp ORDER BY a <-> interval'12-3' year to month LIMIT 3;
SELECT a, a <-> interval'12-3' year to month FROM ymintervaltmp ORDER BY a <-> interval'12-3' year to month LIMIT 3;
