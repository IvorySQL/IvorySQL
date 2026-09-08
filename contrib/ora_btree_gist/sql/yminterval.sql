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

-- Large values must retain their ordering in GiST keys and every strategy.
CREATE TABLE yminterval_overflow(a interval year(9) to month);
INSERT INTO yminterval_overflow VALUES
    (INTERVAL '-1000000-0' YEAR(9) TO MONTH),
    (INTERVAL '0-0' YEAR TO MONTH),
    (INTERVAL '1000000-0' YEAR(9) TO MONTH);
CREATE INDEX yminterval_overflow_idx ON yminterval_overflow USING gist(a);
SET enable_seqscan=off;
SELECT count(*) FROM yminterval_overflow WHERE a < INTERVAL '0-0' YEAR TO MONTH;
SELECT count(*) FROM yminterval_overflow WHERE a <= INTERVAL '0-0' YEAR TO MONTH;
SELECT count(*) FROM yminterval_overflow WHERE a = INTERVAL '0-0' YEAR TO MONTH;
SELECT count(*) FROM yminterval_overflow WHERE a >= INTERVAL '0-0' YEAR TO MONTH;
SELECT count(*) FROM yminterval_overflow WHERE a > INTERVAL '0-0' YEAR TO MONTH;
SELECT count(*) FROM yminterval_overflow WHERE a <> INTERVAL '0-0' YEAR TO MONTH;
RESET enable_seqscan;

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
