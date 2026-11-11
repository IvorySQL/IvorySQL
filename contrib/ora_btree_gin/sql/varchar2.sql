-- varcharbyte check

CREATE TABLE varchar2tmp (a varchar2(32 byte));

\copy varchar2tmp from 'data/varchar2.data'

SET enable_seqscan=on;

SELECT count(*) FROM varchar2tmp WHERE a <   '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a <=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a  =  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a >=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a >   '31b0'::varchar2(32);

CREATE INDEX varcharbyteidx ON varchar2tmp USING GIN (a);

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a <   '31b0'::varchar2(32 byte);
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a <   '31b0'::varchar2(32 char);

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a <=  '31b0'::varchar2(32 byte);
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a <=  '31b0'::varchar2(32 char);

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a  =  '31b0'::varchar2(32 byte);
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a  =  '31b0'::varchar2(32 char);

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a >=  '31b0'::varchar2(32 byte);
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a >=  '31b0'::varchar2(32 char);

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a >   '31b0'::varchar2(32 byte);
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a >   '31b0'::varchar2(32 char);

EXPLAIN (COSTS OFF)
SELECT * FROM varchar2tmp WHERE a BETWEEN '31a'::varchar2(32 byte) AND '31c'::varchar2(32 char);
SELECT * FROM varchar2tmp WHERE a BETWEEN '31a'::varchar2(32 byte) AND '31c'::varchar2(32 char);

-- varcharchar check

CREATE TABLE varchar2test (a varchar2(32 char));

\copy varchar2test from 'data/varchar2.data'

SET enable_seqscan=on;

SELECT count(*) FROM varchar2test WHERE a <   '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a <=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a  =  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a >=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a >   '31b0'::varchar2(32);

CREATE INDEX varcharcharidx ON varchar2test USING GIN (a);

SET enable_seqscan=off;

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a <   '31b0'::varchar2(32 byte);
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a <   '31b0'::varchar2(32 char);

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a <=  '31b0'::varchar2(32 byte);
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a <=  '31b0'::varchar2(32 char);

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a  =  '31b0'::varchar2(32 byte);
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a  =  '31b0'::varchar2(32 char);

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a >=  '31b0'::varchar2(32 byte);
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a >=  '31b0'::varchar2(32 char);

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a >   '31b0'::varchar2(32 byte);
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a >   '31b0'::varchar2(32 char);

EXPLAIN (COSTS OFF)
SELECT * FROM varchar2test WHERE a BETWEEN '31a'::varchar2(32 byte) AND '31c'::varchar2(32 char);
SELECT * FROM varchar2test WHERE a BETWEEN '31a'::varchar2(32 byte) AND '31c'::varchar2(32 char);

-- CHAR and BYTE length semantics use the same bytewise ordering in "C".
-- A VARCHAR2 value with a trailing blank must remain a distinct index key.
CREATE TABLE varchar2_edges (
    id integer,
    c varchar2(8 char) COLLATE "C",
    b varchar2(8 byte) COLLATE "C"
);
INSERT INTO varchar2_edges VALUES
    (1, 'a', 'a '), (2, 'a ', 'a'),
    (3, '中', '中 '), (4, '中 ', '中'), (5, NULL, NULL);

-- Check the results before building the indexes.
SET enable_seqscan = on;
SELECT array_agg(id ORDER BY id) FROM varchar2_edges
WHERE c = 'a'::varchar2(8 byte);
SELECT array_agg(id ORDER BY id) FROM varchar2_edges
WHERE b > '中'::varchar2(8 char);

CREATE INDEX varchar2_edges_char_idx ON varchar2_edges USING gin (c);
CREATE INDEX varchar2_edges_byte_idx ON varchar2_edges USING gin (b);
SET enable_seqscan = off;
EXPLAIN (COSTS OFF)
SELECT id FROM varchar2_edges WHERE c = 'a'::varchar2(8 byte);
SELECT array_agg(id ORDER BY id) FROM varchar2_edges
WHERE c = 'a'::varchar2(8 byte);
EXPLAIN (COSTS OFF)
SELECT id FROM varchar2_edges WHERE b > '中'::varchar2(8 char);
SELECT array_agg(id ORDER BY id) FROM varchar2_edges
WHERE b > '中'::varchar2(8 char);
DROP TABLE varchar2_edges;

