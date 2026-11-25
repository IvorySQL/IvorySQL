CREATE TABLE RW_TEXT(a raw(32768));
CREATE TABLE RW_TEXT(II INT, a raw(32767));
INSERT INTO RW_TEXT VALUES(1,'\xFFFF');
INSERT INTO RW_TEXT VALUES(2,'\xFFFFFF');
INSERT INTO RW_TEXT VALUES(3,'\xFF');
INSERT INTO RW_TEXT VALUES(4,'\xFFFF');
INSERT INTO RW_TEXT VALUES(5,'\xFFFF');
INSERT INTO RW_TEXT VALUES(6,'\xFFFE');

-- TO_BLOB accepts binary input and keeps the VARCHAR2 overload.
\pset format unaligned
SELECT TO_BLOB(HEXTORAW('ff')) FROM dual;
SELECT pg_typeof(TO_BLOB(HEXTORAW('00ff80'))) AS result_type,
       pg_catalog.encode(TO_BLOB(HEXTORAW('00ff80'))::bytea, 'hex') AS binary_value;
SELECT pg_catalog.encode(TO_BLOB(a)::bytea, 'hex') AS raw_column FROM RW_TEXT WHERE ii = 1;
SELECT TO_BLOB(NULL::bytea) IS NULL AS null_result,
       pg_catalog.encode(TO_BLOB('ff')::bytea, 'hex') AS literal_value,
       pg_catalog.encode(TO_BLOB('ff'::varchar2)::bytea, 'hex') AS varchar2_value;
\pset format aligned

SELECT * FROM RW_TEXT WHERE a = '\xFFFF';
SELECT * FROM RW_TEXT WHERE a <> '\xFFFF';
SELECT * FROM RW_TEXT WHERE a > '\xFFFF';
SELECT * FROM RW_TEXT WHERE a >= '\xFFFF';
SELECT * FROM RW_TEXT WHERE a < '\xFFFF';
SELECT * FROM RW_TEXT WHERE a <= '\xFFFF';
SELECT *FROM RW_TEXT;
-- Arithmetic operator
SELECT '123'::raw(3) + '123'::raw(3);
SELECT '123'::bytea + '123'::bytea;
SELECT '123'::raw(3) - '123'::raw(3);
SELECT '123'::bytea - '123'::bytea;
SELECT '123'::raw(3) * '123'::raw(3);
SELECT '123'::bytea * '123'::bytea;
SELECT '123'::raw(3) / '123'::raw(3);
SELECT '123'::bytea / '123'::bytea;
select '123'::raw = '123'::bytea;
select '123'::raw(2) = '123'::bytea;
select '\xff'::bytea = '\xff'::raw(2);
select 'ff'::text = 'ff'::long(2);
DELETE FROM RW_TEXT;
CREATE INDEX test_orachar_btree ON RW_TEXT(a);
INSERT INTO RW_TEXT VALUES(3,'\xFF');
INSERT INTO RW_TEXT SELECT generate_series(1,10000), md5( generate_series(1,10000)::text)::bytea;
SELECT * FROM RW_TEXT WHERE a='\xFF';
VACUUM ANALYZE RW_TEXT;
set enable_seqscan = false;
explain (costs off) SELECT * FROM RW_TEXT WHERE a='\xFF';
-- drop table
DROP TABLE RW_TEXT;
CREATE TABLE LONG_TEXT(II INT, INAME LONG);
INSERT INTO LONG_TEXT VALUES(1,'ABCDEFGH');
INSERT INTO LONG_TEXT VALUES(2,'ABCDE');
INSERT INTO LONG_TEXT VALUES(3,repeat('ABCDEFGH',10));
SELECT * FROM LONG_TEXT ORDER BY II DESC;

DROP TABLE LONG_TEXT;

-- rawtohex
SELECT sys.rawtohex('\xDEADBEEF'::bytea);
SELECT sys.rawtohex('\xFF'::raw);
SELECT sys.rawtohex('hello'::text);
SELECT sys.rawtohex('hello'::varchar2);
SELECT sys.rawtohex(sys.hextoraw('DEADBEEF'));
SELECT sys.rawtohex(NULL) IS NULL;
SELECT sys.rawtohex('') IS NULL;
SELECT sys.rawtohex('\x'::bytea) IS NULL;

