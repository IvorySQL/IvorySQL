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

-- Large values must retain their ordering in GiST keys and every strategy.
CREATE TABLE dsinterval_overflow(a interval day(9) to second(6));
INSERT INTO dsinterval_overflow VALUES
    (INTERVAL '-106751992 00:00:00' DAY(9) TO SECOND),
    (INTERVAL '0 00:00:00' DAY TO SECOND),
    (INTERVAL '106751992 00:00:00' DAY(9) TO SECOND);
CREATE INDEX dsinterval_overflow_idx ON dsinterval_overflow USING gist(a);
SET enable_seqscan=off;
SELECT count(*) FROM dsinterval_overflow WHERE a < INTERVAL '0 00:00:00' DAY TO SECOND;
SELECT count(*) FROM dsinterval_overflow WHERE a <= INTERVAL '0 00:00:00' DAY TO SECOND;
SELECT count(*) FROM dsinterval_overflow WHERE a = INTERVAL '0 00:00:00' DAY TO SECOND;
SELECT count(*) FROM dsinterval_overflow WHERE a >= INTERVAL '0 00:00:00' DAY TO SECOND;
SELECT count(*) FROM dsinterval_overflow WHERE a > INTERVAL '0 00:00:00' DAY TO SECOND;
SELECT count(*) FROM dsinterval_overflow WHERE a <> INTERVAL '0 00:00:00' DAY TO SECOND;
ALTER TABLE dsinterval_overflow
    ADD CONSTRAINT dsinterval_overflow_excl EXCLUDE USING gist (a WITH =);
INSERT INTO dsinterval_overflow VALUES
    (INTERVAL '213503982 08:01:49.551616' DAY(9) TO SECOND(6));
SELECT count(*) FROM dsinterval_overflow;
RESET enable_seqscan;

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
