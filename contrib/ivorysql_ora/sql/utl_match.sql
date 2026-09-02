--
-- utl_match.sql
--
-- Tests for UTL_MATCH package
--
-- Golden values from Oracle PL/SQL Packages and Types Reference (UTL_MATCH),
-- plus values verified empirically against a real Oracle Database 19c
-- instance (AL32UTF8), which pins down behaviour the Oracle docs do not
-- specify:
--   * comparisons are BYTE-based, not character-based
--   * NULL results differ per function (no STRICT NULL propagation):
--       EDIT_DISTANCE -> -1, EDIT_DISTANCE_SIMILARITY -> 0 (100 if both
--       NULL), JARO_WINKLER / _SIMILARITY -> 0
--   * half-transpositions are truncated (integer t/2)
--   * Winkler prefix boost is unconditional (no 0.7 threshold), capped at 4
--   * Jaro match window is floor(max(len)/2) - 1
--   * similarities are rounded half-up
--

SET ivorysql.compatible_mode = oracle;
-- Use real empty strings (Oracle's '' is NULL, but we need empty-string
-- algorithm cases from the official golden table, so disable that mapping).
-- NOTE: the '' rows below exercise behaviour that is not observable in
-- Oracle itself, where '' is NULL.
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
-- NULL input: Oracle returns -1, not NULL (verified on 19c)
SELECT UTL_MATCH.EDIT_DISTANCE(NULL,'abc');
SELECT UTL_MATCH.EDIT_DISTANCE('abc',NULL);
SELECT UTL_MATCH.EDIT_DISTANCE(NULL,NULL);
-- NULL takes precedence over the empty-string algorithm path (not
-- observable in Oracle itself, where '' is NULL)
SELECT UTL_MATCH.EDIT_DISTANCE(NULL,'');
-- multi-byte: Oracle compares bytes, not characters (verified on 19c,
-- AL32UTF8): '试' vs 'a' differs in 3 bytes -> 1 substitution + 2 deletions
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
-- rounding boundary: (1 - 3/8) * 100 = 62.5 -> 63 (half-up, as in Oracle)
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('saturday','sunday');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('abc','abc');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('abc','xyz');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('','abc');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('a','b');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('a','aa');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('abc','abcd');
-- long common prefix
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('aaaaab','aaaaac');
-- NULL inputs: Oracle returns 0 if one input is NULL and 100 if both are
-- (verified on 19c)
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY(NULL,'abc');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('abc',NULL);
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY(NULL,NULL);
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY(NULL,'');
-- empty strings are 100% similar
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('','');
-- multi-byte: both the distance and the maximum length are in bytes
-- (verified on 19c, AL32UTF8): (1 - 3/12) * 100 = 75
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('中文测试','中文测试');
SELECT UTL_MATCH.EDIT_DISTANCE_SIMILARITY('中文测试','中文测a');

-- ============================================================
-- UTL_MATCH.JARO_WINKLER
-- ============================================================

-- Oracle example (rounded to 4 decimals to match the docs)
SELECT ROUND(UTL_MATCH.JARO_WINKLER('shackleford','shackelford')::numeric, 4);
-- classic Jaro-Winkler reference values
SELECT ROUND(UTL_MATCH.JARO_WINKLER('MARTHA','MARHTA')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('DWAYNE','DUANE')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('DIXON','DICKSONX')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('JELLYFISH','SMELLYFISH')::numeric, 4);
-- Oracle truncates half-transpositions (integer t/2): 0.9444, giving
-- JARO_WINKLER_SIMILARITY = 94, not the textbook fractional 92
-- (verified on 19c)
SELECT ROUND(UTL_MATCH.JARO_WINKLER('ABCDEF','BCADEF')::numeric, 4);
-- two swapped pairs (t=4, integer t/2 = 2): 0.8333
SELECT ROUND(UTL_MATCH.JARO_WINKLER('abcd','badc')::numeric, 4);
-- multi-byte transposition at byte level: two 3-byte characters swapped
SELECT ROUND(UTL_MATCH.JARO_WINKLER('中文测试','中文试测')::numeric, 4);
-- identical / totally different
SELECT ROUND(UTL_MATCH.JARO_WINKLER('abc','abc')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('abc','xyz')::numeric, 4);
-- empty strings
SELECT ROUND(UTL_MATCH.JARO_WINKLER('','abc')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('abc','')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('','')::numeric, 4);
-- single character against a longer string
SELECT ROUND(UTL_MATCH.JARO_WINKLER('a','aa')::numeric, 4);
-- Oracle applies the prefix boost unconditionally (no 0.7 threshold):
-- jaro = 0.4444 -> boosted to 0.5556 (verified on 19c)
SELECT ROUND(UTL_MATCH.JARO_WINKLER('ABCCCCCCCCCC','ABDDDDDDDDDD')::numeric, 4);
-- ... and caps the boosted prefix at 4: 0.9429 (verified on 19c)
SELECT ROUND(UTL_MATCH.JARO_WINKLER('AAAAAAB','AAAAAAC')::numeric, 4);
-- Jaro match window is floor(max(len)/2) - 1: distinguishes 0.8083
-- (window-1) from 0.9 (window) (verified on 19c)
SELECT ROUND(UTL_MATCH.JARO_WINKLER('aaaa','aaabbba')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('aaab','baaa')::numeric, 4);
-- case sensitivity
SELECT ROUND(UTL_MATCH.JARO_WINKLER('abc','ABC')::numeric, 4);
-- NULL input: Oracle returns 0, not NULL (verified on 19c)
SELECT UTL_MATCH.JARO_WINKLER(NULL,'abc');
SELECT UTL_MATCH.JARO_WINKLER('abc',NULL);
SELECT UTL_MATCH.JARO_WINKLER(NULL,NULL);
SELECT UTL_MATCH.JARO_WINKLER('',NULL);
-- multi-byte: Jaro-Winkler is byte-based as well (verified on 19c,
-- AL32UTF8): 0.93 byte-based, would be 0.8833 if character-based
SELECT ROUND(UTL_MATCH.JARO_WINKLER('中文测试','中文测试')::numeric, 4);
SELECT ROUND(UTL_MATCH.JARO_WINKLER('中文测试','中文测A')::numeric, 4);
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
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('abcd','badc');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('中文测试','中文试测');
-- integer half-transpositions (Oracle): 94, not the textbook 92
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('ABCDEF','BCADEF');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('abc','abc');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('abc','xyz');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('','abc');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('','');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('a','aa');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('aaaaab','aaaaac');
-- NULL input: Oracle returns 0 (verified on 19c)
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY(NULL,'abc');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('abc',NULL);
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY(NULL,NULL);
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('',NULL);
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('中文测试','中文测试');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('中文测试','中文测A');
SELECT UTL_MATCH.JARO_WINKLER_SIMILARITY('你好','您好');

-- ============================================================
-- Direct C function calls (sys.ora_utl_match_*)
-- ============================================================

SELECT sys.ora_utl_match_edit_distance('kitten','sitting');
SELECT sys.ora_utl_match_edit_distance_similarity('kitten','sitting');
SELECT ROUND(sys.ora_utl_match_jaro_winkler('MARTHA','MARHTA')::numeric, 4);
SELECT sys.ora_utl_match_jaro_winkler_similarity('MARTHA','MARHTA');
-- NULL in -> Oracle-verified sentinel values on the C level as well
SELECT sys.ora_utl_match_edit_distance(NULL,'abc');
SELECT sys.ora_utl_match_edit_distance_similarity(NULL,NULL);
SELECT sys.ora_utl_match_jaro_winkler(NULL,'abc');
SELECT sys.ora_utl_match_jaro_winkler_similarity('abc',NULL);
-- both-empty at the C level
SELECT sys.ora_utl_match_edit_distance('','');
SELECT sys.ora_utl_match_jaro_winkler('','');

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
    RAISE NOTICE 'null: ed=%, eds=%', UTL_MATCH.EDIT_DISTANCE(NULL, 'abc'),
                 UTL_MATCH.EDIT_DISTANCE_SIMILARITY(NULL, NULL);
    RAISE NOTICE 'jw null=%, jws null=%', UTL_MATCH.JARO_WINKLER(NULL, 'abc'),
                 UTL_MATCH.JARO_WINKLER_SIMILARITY('abc', NULL);
    RAISE NOTICE 'kitten vs sitting: ed=%', UTL_MATCH.EDIT_DISTANCE('kitten', 'sitting');
    RAISE NOTICE '中文 ed=% jws=%', UTL_MATCH.EDIT_DISTANCE('中文测试', '中文测a'),
                 UTL_MATCH.JARO_WINKLER_SIMILARITY('中文测试', '中文测试');
END;
$$;
