-- number check

CREATE TABLE numbertmp (a number);

\copy numbertmp from 'data/int8.data'
\copy numbertmp from 'data/number.data'
\copy numbertmp from 'data/binary_float.data'

SET enable_seqscan=on;

SELECT count(*) FROM numbertmp WHERE a <  -1890.0;

SELECT count(*) FROM numbertmp WHERE a <= -1890.0;

SELECT count(*) FROM numbertmp WHERE a  = -1890.0;

SELECT count(*) FROM numbertmp WHERE a >= -1890.0;

SELECT count(*) FROM numbertmp WHERE a >  -1890.0;


SELECT count(*) FROM numbertmp WHERE a <  'NaN' ;

SELECT count(*) FROM numbertmp WHERE a <= 'NaN' ;

SELECT count(*) FROM numbertmp WHERE a  = 'NaN' ;

SELECT count(*) FROM numbertmp WHERE a >= 'NaN' ;

SELECT count(*) FROM numbertmp WHERE a >  'NaN' ;

SELECT count(*) FROM numbertmp WHERE a <  0 ;

SELECT count(*) FROM numbertmp WHERE a <= 0 ;

SELECT count(*) FROM numbertmp WHERE a  = 0 ;

SELECT count(*) FROM numbertmp WHERE a >= 0 ;

SELECT count(*) FROM numbertmp WHERE a >  0 ;


CREATE INDEX numberidx ON numbertmp USING gist ( a );

SET enable_seqscan=off;

SELECT count(*) FROM numbertmp WHERE a <  -1890.0;

SELECT count(*) FROM numbertmp WHERE a <= -1890.0;

SELECT count(*) FROM numbertmp WHERE a  = -1890.0;

SELECT count(*) FROM numbertmp WHERE a >= -1890.0;

SELECT count(*) FROM numbertmp WHERE a >  -1890.0;


SELECT count(*) FROM numbertmp WHERE a <  'NaN' ;

SELECT count(*) FROM numbertmp WHERE a <= 'NaN' ;

SELECT count(*) FROM numbertmp WHERE a  = 'NaN' ;

SELECT count(*) FROM numbertmp WHERE a >= 'NaN' ;

SELECT count(*) FROM numbertmp WHERE a >  'NaN' ;


SELECT count(*) FROM numbertmp WHERE a <  0 ;

SELECT count(*) FROM numbertmp WHERE a <= 0 ;

SELECT count(*) FROM numbertmp WHERE a  = 0 ;

SELECT count(*) FROM numbertmp WHERE a >= 0 ;

SELECT count(*) FROM numbertmp WHERE a >  0 ;

-- Test index-only scans
SET enable_bitmapscan=off;
EXPLAIN (COSTS OFF)
SELECT * FROM numbertmp WHERE a BETWEEN 1 AND 300 ORDER BY a;
SELECT * FROM numbertmp WHERE a BETWEEN 1 AND 300 ORDER BY a;
