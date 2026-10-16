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

