-- varchar2 GiST index checks on multibyte (UTF8) values
--
-- The regression database is pinned to ENCODING = UTF8 (see the Makefile), so
-- pg_database_encoding_max_length() is greater than one and the byte-ahead
-- logic in gbt_var_node_cp_len() is exercised while the index is built and
-- probed.  All of the values share an ASCII prefix and then diverge inside
-- multibyte characters, so the common-prefix computation has to stop at a
-- character boundary instead of reading past the end of the key.  The values
-- also include pairs such as 'é' and 'ē' that have the same encoded length but
-- a different leading byte, which is where the old formula returned a bogus
-- (negative) prefix length.

CREATE TABLE varchar2utf8b (a varchar2(32 byte));

\copy varchar2utf8b from 'data/varchar2_utf8.data'

SET enable_seqscan=on;

SELECT count(*) FROM varchar2utf8b WHERE a <   'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8b WHERE a <=  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8b WHERE a  =  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8b WHERE a >=  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8b WHERE a >   'aab'::varchar2(32);

CREATE INDEX utf8bidx ON varchar2utf8b USING GIST (a);

SET enable_seqscan=off;

SELECT count(*) FROM varchar2utf8b WHERE a <   'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8b WHERE a <=  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8b WHERE a  =  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8b WHERE a >=  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8b WHERE a >   'aab'::varchar2(32);

-- Test index-only scans
SET enable_bitmapscan=off;
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2utf8b WHERE a BETWEEN 'aab' AND 'aac';
SELECT count(*) FROM varchar2utf8b WHERE a BETWEEN 'aab' AND 'aac';

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2utf8b WHERE a <> 'aab';
SELECT count(*) FROM varchar2utf8b WHERE a <> 'aab';

-- varcharchar check

CREATE TABLE varchar2utf8c (a varchar2(32 char));

\copy varchar2utf8c from 'data/varchar2_utf8.data'

SET enable_seqscan=on;

SELECT count(*) FROM varchar2utf8c WHERE a <   'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8c WHERE a <=  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8c WHERE a  =  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8c WHERE a >=  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8c WHERE a >   'aab'::varchar2(32);

CREATE INDEX utf8cidx ON varchar2utf8c USING GIST (a);

SET enable_seqscan=off;

SELECT count(*) FROM varchar2utf8c WHERE a <   'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8c WHERE a <=  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8c WHERE a  =  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8c WHERE a >=  'aab'::varchar2(32);

SELECT count(*) FROM varchar2utf8c WHERE a >   'aab'::varchar2(32);

-- Test index-only scans
SET enable_bitmapscan=off;
EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2utf8c WHERE a BETWEEN 'aab' AND 'aac';
SELECT count(*) FROM varchar2utf8c WHERE a BETWEEN 'aab' AND 'aac';

EXPLAIN (COSTS OFF)
SELECT count(*) FROM varchar2utf8c WHERE a <> 'aab';
SELECT count(*) FROM varchar2utf8c WHERE a <> 'aab';
