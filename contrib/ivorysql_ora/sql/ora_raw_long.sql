CREATE TABLE RW_TEXT(a raw(32768));
CREATE TABLE RW_TEXT(II INT, a raw(32767));
INSERT INTO RW_TEXT VALUES(1,'\xFFFF');
INSERT INTO RW_TEXT VALUES(2,'\xFFFFFF');
INSERT INTO RW_TEXT VALUES(3,'\xFF');
INSERT INTO RW_TEXT VALUES(4,'\xFFFF');
INSERT INTO RW_TEXT VALUES(5,'\xFFFF');
INSERT INTO RW_TEXT VALUES(6,'\xFFFE');
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


-- TO_BLOB accepts binary RAW input without text encoding conversion.
SELECT encode(sys.to_blob(sys.hextoraw('00ff7d80')), 'hex') = '00ff7d80' AS blob_ok;
SELECT pg_typeof(sys.to_blob(sys.hextoraw('ff'))) = 'sys.blob'::regtype AS blob_ok;
SELECT sys.to_blob(NULL::bytea) IS NULL AS blob_ok;
SELECT octet_length(sys.to_blob('\x'::bytea)) = 0 AS blob_ok;
SELECT encode(sys.to_blob(CAST(sys.hextoraw('ff') AS raw(1))), 'hex') = 'ff' AS blob_ok;
SELECT encode(sys.to_blob(CAST(sys.hextoraw('7d') AS long raw)), 'hex') = '7d' AS blob_ok;
SELECT sys.to_blob('abc') = sys.to_blob('abc'::varchar2) AS blob_ok;
SELECT encode(sys.to_blob('abc'::varchar2), 'hex') = '616263' AS blob_ok;
