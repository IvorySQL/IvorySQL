-- 'nls_length_semantics' parameter
SET nls_length_semantics to char;
SET nls_length_semantics to byte;

-- Only values of 'char' and 'byte' is valid
SET nls_length_semantics to other;

-- invalid range
CREATE TABLE TEST_ORACHAR(a char(32768 byte));

CREATE TABLE TEST_ORACHAR(a char(32768 char));

CREATE TABLE TEST_ORACHAR(a varchar2(32768 byte));

CREATE TABLE TEST_ORACHAR(a varchar2(32768 char));

-- valid range
CREATE TABLE TEST_ORACHAR(a char(5 byte), b char(5 char));

CREATE TABLE TEST_ORAVARCHAR(a varchar2(5 char), b varchar2(5 byte));

INSERT INTO TEST_ORACHAR SELECT generate_series(1,10), generate_series(1,10);

INSERT INTO TEST_ORAVARCHAR SELECT generate_series(1,10), generate_series(1,10);


-- Comparison operator
--char
SELECT * FROM TEST_ORACHAR WHERE a = '5';

SELECT * FROM TEST_ORACHAR WHERE a <> '5';

SELECT * FROM TEST_ORACHAR WHERE a > '5';

SELECT * FROM TEST_ORACHAR WHERE a >= '5';

SELECT * FROM TEST_ORACHAR WHERE a < '5';

SELECT * FROM TEST_ORACHAR WHERE a <= '5';


--varchar2
SELECT * FROM TEST_ORAVARCHAR WHERE a = '5';

SELECT * FROM TEST_ORAVARCHAR WHERE a <> '5';

SELECT * FROM TEST_ORAVARCHAR WHERE a > '5';

SELECT * FROM TEST_ORAVARCHAR WHERE a >= '5';

SELECT * FROM TEST_ORAVARCHAR WHERE a < '5';

SELECT * FROM TEST_ORAVARCHAR WHERE a <= '5';


-- Arithmetic operator
-- char/char
SELECT '123'::char(3) + '123'::char(3);

SELECT '123'::char(3) - '123'::char(3);

SELECT '123'::char(3) * '123'::char(3);

SELECT '123'::char(3) / '123'::char(3);


-- char/varchar2
SELECT '123'::char(3) + '123'::varchar2(3);

SELECT '123'::char(3) - '123'::varchar2(3);

SELECT '123'::char(3) * '123'::varchar2(3);

SELECT '123'::char(3) / '123'::varchar2(3);


-- char/unknown
SELECT '123'::char(3) + '123';

SELECT '123'::char(3) - '123';

SELECT '123'::char(3) * '123';

SELECT '123'::char(3) / '123';


-- varchar2/varchar2
SELECT '123'::varchar2(3) + '123'::varchar2(3);

SELECT '123'::varchar2(3) - '123'::varchar2(3);

SELECT '123'::varchar2(3) * '123'::varchar2(3);

SELECT '123'::varchar2(3) / '123'::varchar2(3);


-- varchar2/char
SELECT '123'::varchar2(3) + '123'::char(3);

SELECT '123'::varchar2(3) - '123'::char(3);

SELECT '123'::varchar2(3) * '123'::char(3);

SELECT '123'::varchar2(3) / '123'::char(3);


-- varchar2/unknown
SELECT '123'::varchar2(3) + '123';

SELECT '123'::varchar2(3) - '123';

SELECT '123'::varchar2(3) * '123';

SELECT '123'::varchar2(3) / '123';


-- unknown/unknown	 
SELECT '123' + '123';

SELECT '123' - '123';

SELECT '123' * '123';

SELECT '123' / '123';


-- Spaces are ignored when CHAR compared with CHAR
SELECT * FROM TEST_ORACHAR WHERE a = '5   ';

-- Spaces are not ignored when VARCHAR2 compared with VARCHAR2
SELECT * FROM TEST_ORAVARCHAR WHERE a = '5   ';

-- AGGREGATE
--CHAR
SELECT max(a), min(b) FROM TEST_ORACHAR;

SELECT min(a), max(b) FROM TEST_ORACHAR;

--VARCHAR2
SELECT max(a), min(b) from TEST_ORAVARCHAR;

SELECT min(a), max(b) from TEST_ORAVARCHAR;

-- index 
-- CHAR
DELETE FROM TEST_ORACHAR;

CREATE INDEX test_orachar_btree ON TEST_ORACHAR(a);

CREATE INDEX test_orachar_hash ON TEST_ORACHAR USING HASH (a);

CREATE INDEX test_orachar_brin ON TEST_ORACHAR USING BRIN (a);

INSERT INTO TEST_ORACHAR SELECT generate_series(1,10000), generate_series(1,10000);

SELECT * FROM TEST_ORACHAR WHERE a='111';
VACUUM ANALYZE TEST_ORACHAR;
explain (costs off) SELECT * FROM TEST_ORACHAR WHERE a='111';

--VARCHAR2
--DELETE FROM TEST_ORAVARCHAR;
TRUNCATE TEST_ORAVARCHAR;

CREATE INDEX test_oravarchar_a ON TEST_ORAVARCHAR (a);

CREATE INDEX test_oravarchar_b ON TEST_ORAVARCHAR USING HASH (a);

INSERT INTO TEST_ORAVARCHAR SELECT generate_series(1,10000), generate_series(1,10000);

SELECT * FROM TEST_ORAVARCHAR WHERE a='111';

VACUUM ANALYZE TEST_ORAVARCHAR;
--SET enable_bitmapscan = off;

explain (costs off) SELECT * FROM TEST_ORAVARCHAR WHERE a='111';

-- drop table
DROP TABLE TEST_ORACHAR;
DROP TABLE TEST_ORAVARCHAR;

-- Nondeterministic collations keep CHAR(n BYTE) equality and hashing aligned
DO $$
DECLARE
    result boolean;
    matches integer;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_collation WHERE collprovider = 'i') THEN
        EXECUTE 'CREATE COLLATION ora_char_byte_ci '
                '(provider = icu, locale = ''und-u-ks-level2'', deterministic = false)';

        EXECUTE 'SELECT ''a''::char(1 byte) COLLATE ora_char_byte_ci = '
                '''A''::char(1 byte) COLLATE ora_char_byte_ci'
           INTO result;
        IF NOT result THEN
            RAISE EXCEPTION 'CHAR(n BYTE) equality ignored its nondeterministic collation';
        END IF;

        EXECUTE 'SELECT NOT (''a''::char(1 byte) COLLATE ora_char_byte_ci <> '
                '''A''::char(1 byte) COLLATE ora_char_byte_ci)'
           INTO result;
        IF NOT result THEN
            RAISE EXCEPTION 'CHAR(n BYTE) inequality ignored its nondeterministic collation';
        END IF;

        EXECUTE 'SELECT sys.oracharbytehash('
                '''a''::char(1 byte) COLLATE ora_char_byte_ci) = '
                'sys.oracharbytehash('
                '''A''::char(1 byte) COLLATE ora_char_byte_ci)'
           INTO result;
        IF NOT result THEN
            RAISE EXCEPTION 'equal CHAR(n BYTE) values produced different hashes';
        END IF;

        EXECUTE 'CREATE TEMP TABLE ora_char_byte_ci_test '
                '(v char(1 byte) COLLATE ora_char_byte_ci)';
        EXECUTE 'INSERT INTO ora_char_byte_ci_test VALUES (''a''), (''A'')';
        PERFORM set_config('enable_sort', 'off', true);
        EXECUTE 'SELECT count(DISTINCT v) FROM ora_char_byte_ci_test'
           INTO matches;
        IF matches <> 1 THEN
            RAISE EXCEPTION 'DISTINCT did not combine equal CHAR(n BYTE) values';
        END IF;

        EXECUTE 'TRUNCATE ora_char_byte_ci_test';
        EXECUTE 'INSERT INTO ora_char_byte_ci_test VALUES (''a'')';
        EXECUTE 'CREATE INDEX ora_char_byte_ci_hash_idx '
                'ON ora_char_byte_ci_test USING hash (v)';
        PERFORM set_config('enable_seqscan', 'off', true);
        EXECUTE 'SELECT count(*) FROM ora_char_byte_ci_test WHERE v = ''A'''
           INTO matches;
        IF matches <> 1 THEN
            RAISE EXCEPTION 'hash index lookup missed an equal CHAR(n BYTE) value';
        END IF;

        EXECUTE 'DROP TABLE ora_char_byte_ci_test';
        EXECUTE 'DROP COLLATION ora_char_byte_ci';
    END IF;
END
$$;
