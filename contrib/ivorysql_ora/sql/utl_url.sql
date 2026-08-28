--
-- utl_url.sql
--
-- Tests for the UTL_URL package (ESCAPE and UNESCAPE functions)
--
-- The escaped form of a multibyte character depends on the character set the
-- character is converted to, so the multibyte cases below pass 'UTF8'
-- explicitly rather than relying on the database encoding.  The round-trip
-- cases that omit url_charset work in any database encoding that can hold the
-- literal.
--

-- ============================================================
-- Tests for UTL_URL.ESCAPE
-- ============================================================

-- NULL input returns NULL
SELECT utl_url.escape(NULL) IS NULL AS escape_null;

-- Empty input
SELECT utl_url.escape('') AS escape_empty, utl_url.escape('') IS NULL AS empty_is_null;

-- Unreserved characters are never escaped
SELECT utl_url.escape('AZaz09-_.!~*''()') AS unreserved;

-- Space and the other illegal characters are escaped, reserved ones are not
SELECT utl_url.escape('a b/c?d=e&f') AS default_mode;

-- With escape_reserved_chars = TRUE the delimiters are escaped as well
SELECT utl_url.escape('a b/c?d=e&f', TRUE) AS reserved_mode;

-- The reserved delimiters: passed through by default, escaped on request.
-- '%' and '#' are not passthrough delimiters and are escaped even in the
-- default mode.
SELECT utl_url.escape(';/?:@&=+$%,#') AS reserved_default;
SELECT utl_url.escape(';/?:@&=+$%,#', TRUE) AS reserved_escaped;

-- A literal '%' is always escaped, even in default mode, so that
-- already-escaped input is double-escaped (matching Oracle)
SELECT utl_url.escape('a%b') AS pct_default;
SELECT utl_url.escape('a%b', TRUE) AS pct_reserved;
SELECT utl_url.escape('a%20b') AS preescaped_default;
SELECT utl_url.escape('a%20b', TRUE) AS preescaped_reserved;

-- '#' is always escaped, including default mode, matching Oracle.
SELECT utl_url.escape('a#b') AS hash_default;
SELECT utl_url.escape('a#b', TRUE) AS hash_reserved;

-- A real-world URL with a pre-escaped component and a fragment
SELECT utl_url.escape('http://h/p?q=a%20b#frag') AS url_default;

-- '#' alone
SELECT utl_url.escape('#') AS hash_only_default;
SELECT utl_url.escape('#', TRUE) AS hash_only_reserved;

-- a fragment/query-like string in both modes
SELECT utl_url.escape('a#b?c=d', FALSE) AS hash_query_default;
SELECT utl_url.escape('a#b?c=d', TRUE) AS hash_query_reserved;

-- Illegal ASCII characters are always escaped
SELECT utl_url.escape('<>"{}|\\^[]`') AS illegal_ascii;

-- Control characters are escaped
SELECT utl_url.escape('a' || chr(9) || 'b' || chr(10) || 'c') AS control_chars;

-- Examples from the Oracle documentation
SELECT utl_url.escape('http://www.acme.com/a url with space.html') AS doc_escape;
SELECT utl_url.escape('http://oracle-base.com/my page.html', TRUE) AS doc_escape_reserved;
SELECT utl_url.escape('Is the use of the "$" sign okay?', TRUE) AS doc_escape_value;

-- Multibyte characters: each byte of the converted character gets its own %XX
SELECT utl_url.escape('中文测试', FALSE, 'UTF8') AS cjk_utf8;

-- Explicit character set conversion: the same characters in GB18030
SELECT utl_url.escape('中文', FALSE, 'GB18030') AS cjk_gb18030;

-- The charset name may be spelled the IANA way or the PostgreSQL way
SELECT utl_url.escape('a b', FALSE, 'ISO-8859-1') AS iana_name,
       utl_url.escape('a b', FALSE, 'LATIN1') AS pg_name;

-- The url_charset contract: omitting the argument and passing an explicit
-- NULL are the same thing here -- both mean "the database encoding, do not
-- convert".  Oracle makes them different: an omitted url_charset defaults
-- to utl_http.body_charset (ISO-8859-1) while an explicit NULL selects the
-- database character set.  Defaulting to the database encoding instead of
-- ISO-8859-1 is the declared deviation of this port (ISO-8859-1 cannot
-- represent non-Latin text; see the package documentation), and this case
-- pins the contract so the difference stays visible.
SELECT utl_url.escape('é') AS default_charset,
       utl_url.escape('é', FALSE, NULL) AS explicit_null_charset;

-- An unrecognized character set is rejected
SELECT utl_url.escape('a b', FALSE, 'NO_SUCH_CHARSET');

-- A character with no representation in the target character set is rejected
SELECT utl_url.escape('中文', FALSE, 'LATIN1');

-- ============================================================
-- Tests for UTL_URL.UNESCAPE
-- ============================================================

-- NULL input returns NULL
SELECT utl_url.unescape(NULL) IS NULL AS unescape_null;

-- Basic decoding
SELECT utl_url.unescape('a%20b%2Fc') AS basic;

-- Lower case hex digits are accepted on input
SELECT utl_url.unescape('a%2fb%2Fc') AS lower_hex;

-- The empty string round-trips to the empty string
SELECT utl_url.unescape('') AS unescape_empty;

-- A '%' produced by ESCAPE decodes back to a literal '%': double-escaped
-- input collapses one level, as on Oracle
SELECT utl_url.unescape('a%25b') AS pct_literal;
SELECT utl_url.unescape('a%2520b') AS double_escaped;

-- Unescaped characters are passed through untouched
SELECT utl_url.unescape('http://oracle-base.com/my%20page.html') AS doc_unescape;
SELECT utl_url.unescape('http%3A%2F%2Foracle-base.com%2Fmy%20page.html') AS doc_unescape_reserved;

-- Multibyte: consecutive %XX groups are reassembled into one character
SELECT utl_url.unescape('%E4%B8%AD%E6%96%87', 'UTF8') AS cjk_utf8;

-- GBK bytes are converted from the named charset (the IANA/PostgreSQL
-- spelling; Oracle writes ZHS16GBK)
SELECT utl_url.unescape('%D6%D0%CE%C4', 'GBK') AS cjk_gbk;

-- Mixed literal (database encoding) and %XX (url_charset): literal
-- characters are preserved as-is; only the %XX bytes are converted from
-- url_charset (a UTF-8 literal must not be re-interpreted through the
-- url_charset)
SELECT utl_url.unescape('café%21', 'LATIN1') AS mixed_literal_pct;

-- An unrecognized character set is rejected (Oracle reports ORA-01482)
SELECT utl_url.unescape('a%20b', 'NO_SUCH_CHARSET');

-- ============================================================
-- Round-trip identity: UNESCAPE(ESCAPE(x)) = x
-- ============================================================

SELECT utl_url.unescape(utl_url.escape('a b/中文')) = 'a b/中文' AS roundtrip_default;
SELECT utl_url.unescape(utl_url.escape('a b/中文', TRUE)) = 'a b/中文' AS roundtrip_reserved;
SELECT utl_url.unescape(utl_url.escape('中文测试', FALSE, 'UTF8'), 'UTF8') = '中文测试' AS roundtrip_charset;
SELECT utl_url.unescape(utl_url.escape('中文', FALSE, 'GB18030'), 'GB18030') = '中文' AS roundtrip_gb18030;

-- '%' and '#' are always escaped (including the default mode), so every
-- literal round-trips in either mode
SELECT utl_url.unescape(utl_url.escape(';/?:@&=+$%,# <>"')) = ';/?:@&=+$%,# <>"' AS roundtrip_all_default;
SELECT utl_url.unescape(utl_url.escape(';/?:@&=+$%,# <>"', TRUE)) = ';/?:@&=+$%,# <>"' AS roundtrip_all_reserved;

-- ============================================================
-- Error cases: badly formed escape code sequences
-- Oracle raises UTL_URL.BAD_URL (ORA-29262) for these
-- ============================================================

-- '%' at the end of the string
SELECT utl_url.unescape('bad%');

-- '%' followed by non-hexadecimal characters
SELECT utl_url.unescape('%ZZ');

-- '%' followed by only one hexadecimal digit
SELECT utl_url.unescape('a%2');

-- A literal '%' in the middle of an otherwise valid URL
SELECT utl_url.unescape('100%20%pure');

-- %00 cannot be represented in a text value
SELECT utl_url.unescape('a%00b');

-- A %XX group that does not form a valid character in the source charset
SELECT utl_url.unescape('%E4%B8', 'UTF8');

-- ============================================================
-- PL/iSQL package interface
-- ============================================================

DECLARE
    v_url     VARCHAR2(200) := 'http://example.com/a b/中文?x=1&y=2';
    v_escaped VARCHAR2(400);
    line      TEXT;
    status    INTEGER;
BEGIN
    dbms_output.enable();
    v_escaped := utl_url.escape(v_url);
    dbms_output.put_line('escaped=' || v_escaped);
    dbms_output.get_line(line, status);
    RAISE NOTICE '%', line;
    dbms_output.put_line('roundtrip=' ||
        CASE WHEN utl_url.unescape(v_escaped) = v_url THEN 't' ELSE 'f' END);
    dbms_output.get_line(line, status);
    RAISE NOTICE '%', line;
END;
/

-- All three arguments through the package
DECLARE
    v_escaped VARCHAR2(400);
    line      TEXT;
    status    INTEGER;
BEGIN
    dbms_output.enable();
    v_escaped := utl_url.escape('a b$c', TRUE, 'UTF8');
    dbms_output.put_line('escaped=' || v_escaped);
    dbms_output.get_line(line, status);
    RAISE NOTICE '%', line;
    dbms_output.put_line('unescaped=' || utl_url.unescape(v_escaped, 'UTF8'));
    dbms_output.get_line(line, status);
    RAISE NOTICE '%', line;
END;
/

-- BAD_URL surfaces as an error inside PL/iSQL too
DECLARE
    v_out VARCHAR2(400);
BEGIN
    v_out := utl_url.unescape('bad%');
    RAISE NOTICE 'should not get here: %', v_out;
END;
/
