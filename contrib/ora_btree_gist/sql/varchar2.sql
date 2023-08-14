-- varcharbyte check

CREATE TABLE varchar2tmp (a varchar2(32 byte));

\copy varchar2tmp from 'data/varchar2.data'

SET enable_seqscan=on;

SELECT count(*) FROM varchar2tmp WHERE a <   '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a <=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a  =  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a >=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a >   '31b0'::varchar2(32);

CREATE INDEX varcharbyteidx ON varchar2tmp USING GIST (a);

SET enable_seqscan=off;

SELECT count(*) FROM varchar2tmp WHERE a <   '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a <=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a  =  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a >=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2tmp WHERE a >   '31b0'::varchar2(32);

-- Test index-only scans
SET enable_bitmapscan=off;
EXPLAIN (COSTS OFF)
SELECT * FROM varchar2tmp WHERE a BETWEEN '31a' AND '31c';
SELECT * FROM varchar2tmp WHERE a BETWEEN '31a' AND '31c';

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a <> '31a';

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2tmp WHERE a <> '31a'::varchar2(32 char);

-- varcharchar check

CREATE TABLE varchar2test (a varchar2(32 char));

\copy varchar2test from 'data/varchar2.data'

SET enable_seqscan=on;

SELECT count(*) FROM varchar2test WHERE a <   '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a <=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a  =  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a >=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a >   '31b0'::varchar2(32);

CREATE INDEX varcharcharidx ON varchar2test USING GIST (a);

SET enable_seqscan=off;

SELECT count(*) FROM varchar2test WHERE a <   '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a <=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a  =  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a >=  '31b0'::varchar2(32);

SELECT count(*) FROM varchar2test WHERE a >   '31b0'::varchar2(32);

-- Test index-only scans
SET enable_bitmapscan=off;
EXPLAIN (COSTS OFF)
SELECT * FROM varchar2test WHERE a BETWEEN '31a' AND '31c';
SELECT * FROM varchar2test WHERE a BETWEEN '31a' AND '31c';

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a <> '31a';

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2test WHERE a <> '31a'::varchar2(32 byte);
