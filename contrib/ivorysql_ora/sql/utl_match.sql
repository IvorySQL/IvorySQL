--
-- utl_match.sql
--
-- Tests for UTL_MATCH package
-- Golden values from Oracle PL/SQL Packages and Types Reference (UTL_MATCH),
-- plus textbook reference values (Wikipedia Jaro-Winkler examples, classic
-- Levenshtein cases) and boundary/edge cases.
--

SET ivorysql.compatible_mode = oracle;
-- Use real empty strings (Oracle's '' is NULL, but we need empty-string
-- algorithm cases from the official golden table, so disable that mapping).
SET ivorysql.enable_emptystring_to_NULL = off;

-- ============================================================
-- UTL_MATCH.EDIT_DISTANCE
-- ============================================================

-- Oracle example: shackleford vs shackelford
SELECT UTL_MATCH.EDIT_DISTANCE('shackleford','shackelford');
-- classic Levenshtein examples
SELECT UTL_MATCH.EDIT_DISTANCE('kitten','sitting');
SELECT UTL_MATCH.EDIT_DISTANCE('saturday','sunday');
SELECT UTL_MATCH.EDIT_DISTANCE('flaw','lawn');
-- identical / totally different
SELECT UTL_MATCH.EDIT_DISTANCE('abc','abc');
SELECT UTL_MATCH.EDIT_DISTANCE('abc','xyz');
-- empty strings
SELECT UTL_MATCH.EDIT_DISTANCE('','abc');
SELECT UTL_MATCH.EDIT_DISTANCE('abc','');
SELECT UTL_MATCH.EDIT_DISTANCE('','');
-- single character / length mismatch
SELECT UTL_MATCH.EDIT_DISTANCE('a','b');
SELECT UTL_MATCH.EDIT_DISTANCE('a','aa');
SELECT UTL_MATCH.EDIT_DISTANCE('abc','abcd');
-- case sensitivity (Oracle comparison is case-sensitive)
SELECT UTL_MATCH.EDIT_DISTANCE('abc','ABC');
-- whitespace is an ordinary character
SELECT UTL_MATCH.EDIT_DISTANCE('a b c','a b c');
SELECT UTL_MATCH.EDIT_DISTANCE('a b','ab');
-- long common prefix: only the last character differs
SELECT UTL_MATCH.EDIT_DISTANCE('aaaaab','aaaaac');
-- NULL input returns NULL
SELECT UTL_MATCH.EDIT_DISTANCE(NULL,'abc') IS NULL;
SELECT UTL_MATCH.EDIT_DISTANCE('abc',NULL) IS NULL;
SELECT UTL_MATCH.EDIT_DISTANCE(NULL,NULL) IS NULL;
-- multi-byte characters (character-based, not byte-based)
SELECT UTL_MATCH.EDIT_DISTANCE('中文测试','中文测试');
SELECT UTL_MATCH.EDIT_DISTANCE('中文测试','中文测a');
SELECT UTL_MATCH.EDIT_DISTANCE('你好','您好');
SELECT UTL_MATCH.EDIT_DISTANCE('中文测试','中文');
SELECT UTL_MATCH.EDIT_DISTANCE('abc中文','abc中文');
-- large input (length 3000, all chars differ)
SELECT UTL_MATCH.EDIT_DISTANCE(repeat('a',3000), repeat('b',3000));

-- ============================================================
-- UTL_MATCH.EDIT_DISTANCE_SIMILARITY
-- ============================================================

SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('shackleford','shackelford');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('kitten','sitting');
-- rounding boundary: (1 - 3/8) * 100 = 62.5 -> 63
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('saturday','sunday');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('abc','abc');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('abc','xyz');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('','abc');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('a','b');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('a','aa');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('abc','abcd');
-- long common prefix
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('aaaaab','aaaaac');
-- NULL input returns NULL
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY(NULL,'abc') IS NULL;
-- empty strings are 100% similar
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('','');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('中文测试','中文测试');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('中文测试','中文测a');

-- ============================================================
-- UTL_MATCH.JARO_WINKLER
-- ============================================================

-- Oracle example (rounded to 4 decimals to match the docs)
SELECT ROUND(UTL_MATCH.JARO_WINKLER('shackleford','shackelford')::numeric, 4);
-- Wikipedia Jaro-Winkler examples
SELECT ROUND(UTL_MATCH.JARO_WINKLER('MARTHA','MARHTA')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('DWAYNE','DUANE')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('DIXON','DICKSONX')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('JELLYFISH','SMELLYFISH')::numeric, 4);
-- fractional transpositions: 3 displaced chars -> t/2 = 1.5 (standard Jaro)
SELECT ROUND(UTL_MATCH.JARO_WINKLER('abcdef','bcadef')::numeric, 4);
-- identical / totally different
SELECT ROUND(UTL_MATCH.JARO_WINKLER('abc','abc')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('abc','xyz')::numeric, 4);
-- empty strings
SELECT ROUND(UTL_MATCH.JARO_WINKLER('','abc')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('abc','')::numeric, 4);
-- single character against a longer string
SELECT ROUND(UTL_MATCH.JARO_WINKLER('a','aa')::numeric, 4);
-- common-prefix boost (scaled by up to 4 prefix chars)
SELECT ROUND(UTL_MATCH.JARO_WINKLER('abcde','abfgh')::numeric, 4);
-- boost with a capped 4-char common prefix, raw Jaro above the 0.7 threshold
SELECT ROUND(UTL_MATCH.JARO_WINKLER('aaaaab','aaaaac')::numeric, 4);
-- case sensitivity
SELECT ROUND(UTL_MATCH.JARO_WINKLER('abc','ABC')::numeric, 4);
-- NULL input returns NULL
SELECT UTL_MATCH.JARO_WINKLER(NULL,'abc') IS NULL;
SELECT UTL_MATCH.JARO_WINKLER('abc',NULL) IS NULL;
-- multi-byte
SELECT ROUND(UTL_MATCH.JARO_WINKLER('中文测试','中文测试')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('你好','您好')::numeric, 4);
-- full precision (BINARY_DOUBLE return value, unrounded)
SELECT UTL_MATCH.JARO_WINKLER('MARTHA','MARHTA');

-- ============================================================
-- UTL_MATCH.JARO_WINKLER_SIMILARITY
-- ============================================================

SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('shackleford','shackelford');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('MARTHA','MARHTA');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('DWAYNE','DUANE');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('DIXON','DICKSONX');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('JELLYFISH','SMELLYFISH');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('abcdef','bcadef');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('abc','abc');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('abc','xyz');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('','abc');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('a','aa');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('aaaaab','aaaaac');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY(NULL,'abc') IS NULL;
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('中文测试','中文测试');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('你好','您好');

-- ============================================================
-- Direct C function calls (sys.ora_utl_match_*)
-- ============================================================

SELECT sys.ora_utl_match_edit_distance('kitten','sitting');
SELECT sys.ora_utl_match_edit_distance_similarity('kitten','sitting');
SELECT ROUND(sys.ora_utl_match_jaro_winkler('MARTHA','MARHTA')::numeric, 4);
SELECT sys.ora_utl_match_jaro_winkler_similarity('MARTHA','MARHTA');
-- NULL in -> NULL out on the C level as well
SELECT sys.ora_utl_match_edit_distance(NULL,'abc') IS NULL;
SELECT sys.ora_utl_match_jaro_winkler(NULL,'abc') IS NULL;

-- ============================================================
-- PL/iSQL package interface tests
-- ============================================================

DO $$
DECLARE
    v_ed  INTEGER;
    v_eds INTEGER;
    v_jw  BINARY_DOUBLE;
    v_jws INTEGER;
    s1    VARCHAR2(100);
    s2    VARCHAR2(100);
BEGIN
    s1 := 'shackleford';
    s2 := 'shackelford';
    v_ed  := UTL_MATCH.EDIT_DISTANCE(s1, s2);
    v_eds := UTL_MATCH.EDIT_DISTANCE_SIMILARITY(s1, s2);
    v_jw  := UTL_MATCH.JARO_WINKLER(s1, s2);
    v_jws := UTL_MATCH.JARO_WINKLER_SIMILARITY(s1, s2);
    RAISE NOTICE 'ed=%, eds=%, jw=%, jws=%', v_ed, v_eds, v_jw, v_jws;
    RAISE NOTICE 'null in -> null out: %', UTL_MATCH.EDIT_DISTANCE(NULL, 'abc') IS NULL;
    RAISE NOTICE 'kitten vs sitting: ed=%', UTL_MATCH.EDIT_DISTANCE('kitten', 'sitting');
    RAISE NOTICE '中文 ed=% jws=%', UTL_MATCH.EDIT_DISTANCE('中文测试', '中文测a'),
                 UTL_MATCH.JARO_WINKLER_SIMILARITY('中文测试', '中文测试');
END;
$$;