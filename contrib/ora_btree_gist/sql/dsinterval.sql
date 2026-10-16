-- dsinterval check

CREATE TABLE dsintervaltmp(a interval day(4) to second(6));

\copy dsintervaltmp from 'data/dsinterval.data'

SET enable_seqscan=on;

SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a <  interval'12 1:1:1.123456' day to second;

SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a <= interval'12 1:1:1.123456' day to second;

SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a  = interval'12 1:1:1.123456' day to second;

SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a >= interval'12 1:1:1.123456' day to second;

SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a >  interval'12 1:1:1.123456' day to second;

SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a <> interval'12 1:1:1.123456' day to second;

SELECT a, a <-> interval'12 1:1:1.123456' day to second FROM dsintervaltmp ORDER BY a <-> interval'12 1:1:1.123456' day to second LIMIT 3;

CREATE INDEX dsintervalidx on dsintervaltmp USING gist(a);

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a <  interval'12 1:1:1.123456' day to second;
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a <  interval'12 1:1:1.123456' day to second;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a <= interval'12 1:1:1.123456' day to second;
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a <= interval'12 1:1:1.123456' day to second;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a  = interval'12 1:1:1.123456' day to second;
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a  = interval'12 1:1:1.123456' day to second;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a >= interval'12 1:1:1.123456' day to second;
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a >= interval'12 1:1:1.123456' day to second;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a >  interval'12 1:1:1.123456' day to second;
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a >  interval'12 1:1:1.123456' day to second;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a <> interval'12 1:1:1.123456' day to second;
SELECT count(*) FROM dsintervaltmp WHERE dsintervaltmp.a <> interval'12 1:1:1.123456' day to second;

EXPLAIN (COSTS OFF)
SELECT a, a <-> interval'12 1:1:1.123456' day to second FROM dsintervaltmp ORDER BY a <-> interval'12 1:1:1.123456' day to second LIMIT 3;
SELECT a, a <-> interval'12 1:1:1.123456' day to second FROM dsintervaltmp ORDER BY a <-> interval'12 1:1:1.123456' day to second LIMIT 3;
