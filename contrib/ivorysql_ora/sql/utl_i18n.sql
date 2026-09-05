--
-- UTL_I18N
--
-- Regression tests for Oracle-compatible UTL_I18N package:
--   - ESCAPE_REFERENCE
--   - UNESCAPE_REFERENCE
--   - STRING_TO_RAW
--   - RAW_TO_CHAR
--

-- Basic ESCAPE_REFERENCE: standard XML/HTML character entities
SELECT utl_i18n.escape_reference('a & b < c > d " e '' f');
SELECT utl_i18n.escape_reference('hello <b>world</b> & "test"');

-- ESCAPE_REFERENCE with page_cs_name 'us7ascii' (non-ASCII converted to &#x...;)
SELECT utl_i18n.escape_reference('hello < é', 'us7ascii');
SELECT utl_i18n.escape_reference('Chinese: 你好', 'us7ascii');

-- Basic UNESCAPE_REFERENCE: decoding entity references
SELECT utl_i18n.unescape_reference('a &amp; b &lt; c &gt; d &quot; e &apos; f');
SELECT utl_i18n.unescape_reference('hello &lt;b&gt;world&lt;/b&gt; &amp; &quot;test&quot;');

-- UNESCAPE_REFERENCE with hex and decimal character references
SELECT utl_i18n.unescape_reference('&#x61;&#x62;&#x63;');
SELECT utl_i18n.unescape_reference('&#97;&#98;&#99;');
SELECT utl_i18n.unescape_reference('hello &lt; &#xe9;');

-- Round-trip test: UNESCAPE_REFERENCE(ESCAPE_REFERENCE(str))
SELECT utl_i18n.unescape_reference(utl_i18n.escape_reference('a & b < c > d " e '' f')) = 'a & b < c > d " e '' f' AS roundtrip_matched;
SELECT utl_i18n.unescape_reference(utl_i18n.escape_reference('Chinese: 你好', 'us7ascii')) = 'Chinese: 你好' AS utf8_roundtrip_matched;

-- STRING_TO_RAW and RAW_TO_CHAR
SELECT utl_i18n.string_to_raw('hello');
SELECT utl_i18n.string_to_raw('ABC', 'utf8');
SELECT utl_i18n.raw_to_char(utl_i18n.string_to_raw('hello'));
SELECT utl_i18n.raw_to_char(utl_i18n.string_to_raw('你好世界', 'utf8'), 'utf8');

-- NULL and empty string handling (Oracle semantics)
SELECT utl_i18n.escape_reference(NULL) IS NULL;
SELECT utl_i18n.unescape_reference(NULL) IS NULL;
SELECT utl_i18n.string_to_raw(NULL) IS NULL;
SELECT utl_i18n.raw_to_char(NULL) IS NULL;
SELECT utl_i18n.escape_reference('');
SELECT utl_i18n.unescape_reference('');

-- Invalid character set name error handling
SELECT utl_i18n.escape_reference('abc', 'invalid_cs');
SELECT utl_i18n.string_to_raw('abc', 'invalid_cs');
SELECT utl_i18n.raw_to_char(E'\\x616263'::bytea, 'invalid_cs');

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('utl_i18n_escape_reference',
                     'utl_i18n_unescape_reference',
                     'utl_i18n_string_to_raw',
                     'utl_i18n_raw_to_char')
 ORDER BY p.proname;
