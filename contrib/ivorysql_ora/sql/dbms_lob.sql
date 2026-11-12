--
-- Tests for DBMS_LOB package
--
-- Every expected value was verified against Oracle 23ai Free (including the
-- boundary probes: amount > 32767 -> NULL, COMPARE's strcmp-style -1/0/+1
-- result, COPY gap padding, fractional-argument truncation, and the
-- ORA-21560-style argument errors).  IvorySQL models clob/nclob/blob as
-- value types (domains over text/bytea), so the locator-restricted error
-- paths of Oracle (ORA-22275 for uninitialized locators) do not apply;
-- documented deviations are exercised explicitly.
--

-- =============================================================================
-- GETLENGTH
-- =============================================================================

SELECT dbms_lob.getlength('abcde'::clob) AS gl_text;
SELECT dbms_lob.getlength('你好'::clob) AS gl_chars;
SELECT dbms_lob.getlength(NULL::clob) AS gl_null;
SELECT dbms_lob.getlength(hextoraw('aabbccddee')::blob) AS gl_blob;
SELECT dbms_lob.getlength(NULL::blob) AS gl_blob_null;

-- nclob values resolve to the text-family overload
DECLARE
    x nclob := 'abcd';
BEGIN
    RAISE NOTICE 'GL nclob: %', dbms_lob.getlength(x);
END;
/

-- =============================================================================
-- SUBSTR (amount first, offset second; opposite order of SQL SUBSTR)
-- =============================================================================

SELECT dbms_lob.substr('abcde'::clob, 3, 2) AS s_basic;
SELECT dbms_lob.substr('abcde'::clob, 100, 4) AS s_clamped;
SELECT dbms_lob.substr('abcde'::clob, 3) AS s_default_offset;
SELECT dbms_lob.substr('abcde'::clob) AS s_defaults;
SELECT dbms_lob.substr('abcde'::clob, 3, 0) AS s_offset_0;
SELECT dbms_lob.substr('abcde'::clob, 3, 10) AS s_offset_high;
SELECT dbms_lob.substr('abcde'::clob, 0, 1) AS s_amount_0;
SELECT dbms_lob.substr('abcde'::clob, -1, 1) AS s_amount_neg;
SELECT dbms_lob.substr('abcde'::clob, 32768, 1) AS s_amount_over_cap;
SELECT dbms_lob.substr('abcde'::clob, 2.7, 2.7) AS s_fractional_truncated;
SELECT dbms_lob.substr(NULL::clob, 1, 1) AS s_null;
SELECT dbms_lob.substr(hextoraw('aabbccddee')::blob, 2, 2) AS s_blob;
SELECT dbms_lob.substr(hextoraw('aabbccddee')::blob, 100, 4) AS s_blob_clamped;
SELECT dbms_lob.substr(hextoraw('aabbccddee')::blob, 2, 20) AS s_blob_offset_high;

-- =============================================================================
-- INSTR
-- =============================================================================

SELECT dbms_lob.instr('abcabc'::clob, 'bc') AS i_default;
SELECT dbms_lob.instr('abcabc'::clob, 'bc', 3) AS i_offset;
SELECT dbms_lob.instr('abcabc'::clob, 'bc', 1, 2) AS i_occurrence;
SELECT dbms_lob.instr('abcabc'::clob, 'bc', 100) AS i_offset_high;
SELECT dbms_lob.instr('abcabc'::clob, 'bc', 0) AS i_offset_0;
SELECT dbms_lob.instr('abcabc'::clob, 'bc', 1, 0) AS i_occurrence_0;
SELECT dbms_lob.instr('abcabc'::clob, 'zz') AS i_no_match;
SELECT dbms_lob.instr('abc'::clob, 'abcdef') AS i_pattern_longer;
SELECT dbms_lob.instr(NULL::clob, 'bc') AS i_null;

SELECT dbms_lob.instr(hextoraw('aabbccbbaa')::blob, hextoraw('bb')::raw) AS i_blob;
SELECT dbms_lob.instr(hextoraw('aabbccbbaa')::blob, hextoraw('bb')::raw, 3, 2) AS i_blob_occ;
SELECT dbms_lob.instr(hextoraw('aabbccbbaa')::blob, hextoraw('cc')::raw, 4) AS i_blob_none;

-- =============================================================================
-- COMPARE: strcmp-style -1/0/+1 (verified on Oracle 23ai, including the
-- 'abcde' vs 'abcXe' -> +1 and prefix/offset-beyond -> -1 cases); NULL for
-- invalid arguments.  An exhausted side counts as empty.
-- =============================================================================

SELECT dbms_lob.compare('abcde'::clob, 'abcde'::clob) AS c_equal;
SELECT dbms_lob.compare('abcde'::clob, 'abcXe'::clob, 5) AS c_greater;
SELECT dbms_lob.compare('Xbcde'::clob, 'abcde'::clob, 5) AS c_less;
SELECT dbms_lob.compare('abXde'::clob, 'abcde'::clob, 5) AS c_less_at_3;
SELECT dbms_lob.compare('abcde'::clob, 'abcde'::clob, 3) AS c_amount_limited;
SELECT dbms_lob.compare('abcde'::clob, 'abcde'::clob, 0) AS c_amount_0;
SELECT dbms_lob.compare('abcde'::clob, 'abcde'::clob, 1, 0, 1) AS c_offset_0;
SELECT dbms_lob.compare(NULL::clob, 'abcde'::clob) AS c_null;
SELECT dbms_lob.compare('abc'::clob, 'abcdef'::clob) AS c_prefix_is_less;
SELECT dbms_lob.compare('abc'::clob, 'abcde'::clob, 5, 100, 1) AS c_pos_beyond_one;
SELECT dbms_lob.compare('abc'::clob, 'abcde'::clob, 5, 100, 100) AS c_pos_beyond_both;

SELECT dbms_lob.compare(hextoraw('aabb')::blob, hextoraw('aabb')::blob) AS c_blob_equal;
SELECT dbms_lob.compare(hextoraw('aabb')::blob, hextoraw('aacc')::blob, 2) AS c_blob_less;

-- =============================================================================
-- APPEND
-- =============================================================================

DECLARE
    d clob;
    b blob;
BEGIN
    d := 'abc';
    dbms_lob.append(d, 'def');
    dbms_lob.append(d, 'ghi');
    RAISE NOTICE 'APPEND clob: %', d;

    dbms_lob.append(d, NULL);
    RAISE NOTICE 'APPEND clob null src (no-op): %', d;

    d := NULL;
    dbms_lob.append(d, 'q');
    RAISE NOTICE 'APPEND clob null dest: %', d;

    b := hextoraw('aabb');
    dbms_lob.append(b, hextoraw('ccdd')::raw);
    RAISE NOTICE 'APPEND blob: %', b;
END;
/

-- =============================================================================
-- COPY (overwrites from dest_offset, preserves the rest; a dest_offset
-- beyond the end pads the gap with spaces/zeros, as Oracle does)
-- =============================================================================

DECLARE
    d clob;
    b blob;
BEGIN
    d := 'ABCDEF';
    dbms_lob.copy(d, 'xy', 2, 3, 1);
    RAISE NOTICE 'COPY overwrite: %', d;

    d := 'ABCDEF';
    dbms_lob.copy(d, 'xyz', 100, 2, 2);
    RAISE NOTICE 'COPY clamped: %', d;

    d := 'ABCDEF';
    dbms_lob.copy(d, 'xy', 2, 7, 1);
    RAISE NOTICE 'COPY at end: %', d;

    d := 'ABCDEF';
    dbms_lob.copy(d, 'xy', 2, 100, 1);
    RAISE NOTICE 'COPY gap: len=% ends=%', length(d), substr(d, 100, 2);

    b := hextoraw('aabbcc');
    dbms_lob.copy(b, hextoraw('dd')::raw, 1, 2, 1);
    RAISE NOTICE 'COPY blob: %', b;

    b := hextoraw('aabb');
    dbms_lob.copy(b, hextoraw('dd')::raw, 1, 5, 1);
    RAISE NOTICE 'COPY blob gap: %', b;
END;
/

-- =============================================================================
-- TRIM
-- =============================================================================

DECLARE
    d clob;
    b blob;
BEGIN
    d := 'abcdef';
    dbms_lob.trim(d, 3);
    RAISE NOTICE 'TRIM clob: %', d;

    d := 'ABCDEF';
    dbms_lob.trim(d, 2.7);
    RAISE NOTICE 'TRIM fractional: %', d;

    b := hextoraw('aabbccdd');
    dbms_lob.trim(b, 2);
    RAISE NOTICE 'TRIM blob: %', b;

    BEGIN
        d := 'abc';
        dbms_lob.trim(d, 10);
        RAISE NOTICE 'TRIM over-length: no error';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'TRIM over-length raised: %', sqlerrm;
    END;

    BEGIN
        d := 'abc';
        dbms_lob.trim(d, -3);
        RAISE NOTICE 'TRIM negative: no error';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'TRIM negative raised: %', sqlerrm;
    END;
END;
/

-- =============================================================================
-- ERASE (spaces for CLOB/NCLOB, zero bytes for BLOB, IN OUT amount)
-- =============================================================================

DECLARE
    d clob;
    b blob;
    amt number;
BEGIN
    d := 'abcdef';
    amt := 2;
    dbms_lob.erase(d, amt, 2);
    RAISE NOTICE 'ERASE clob: [%] amt=%', d, amt;

    b := hextoraw('aabbccddee');
    amt := 2;
    dbms_lob.erase(b, amt, 2);
    RAISE NOTICE 'ERASE blob: % amt=%', b, amt;

    d := 'abcdef';
    amt := 10;
    dbms_lob.erase(d, amt, 4);
    RAISE NOTICE 'ERASE clamped: [%] amt=%', d, amt;

    d := 'abcdef';
    amt := 2;
    dbms_lob.erase(d, amt, 100);
    RAISE NOTICE 'ERASE offset high: [%] amt=%', d, amt;

    BEGIN
        d := 'abc';
        amt := -2;
        dbms_lob.erase(d, amt, 2);
        RAISE NOTICE 'ERASE negative: no error';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'ERASE negative raised: %', sqlerrm;
    END;
END;
/

-- =============================================================================
-- LOBMAXSIZE constant (package constants are usable in PL/iSQL, as in Oracle)
-- =============================================================================

DECLARE
BEGIN
    RAISE NOTICE 'lobmaxsize: %', dbms_lob.lobmaxsize;
END;
/

-- =============================================================================
-- Usage on a table column round-trip
-- =============================================================================

CREATE TABLE dbms_lob_test (id int, doc clob, payload blob);
INSERT INTO dbms_lob_test VALUES (1, 'hello world', hextoraw('aabbcc'));

DECLARE
    d clob;
BEGIN
    SELECT doc INTO d FROM dbms_lob_test WHERE id = 1;
    dbms_lob.append(d, ' from oracle');
    UPDATE dbms_lob_test SET doc = d WHERE id = 1;
END;
/

SELECT dbms_lob.getlength(doc) AS len, dbms_lob.substr(doc, 5, 13) AS tail
FROM dbms_lob_test WHERE id = 1;

SELECT dbms_lob.instr(doc, 'oracle') AS pos FROM dbms_lob_test WHERE id = 1;

DROP TABLE dbms_lob_test;
