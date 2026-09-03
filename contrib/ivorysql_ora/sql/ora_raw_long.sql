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

-- Explicit LONG(n) casts retain only complete multibyte characters.
SELECT cast('中文' AS long(6)) = '中文'
       AND lengthb(cast('中文' AS long(6))) = 6;
SELECT cast('中文' AS long(5)) = '中'
       AND lengthb(cast('中文' AS long(5))) = 3;
SELECT coalesce(lengthb(cast('中文' AS long(2))), 0) = 0;
SELECT cast('abcdef' AS long(4)) = 'abcd';
SELECT cast('abc' AS long(4)) = 'abc';

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

