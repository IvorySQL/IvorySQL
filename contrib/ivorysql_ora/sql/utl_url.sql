--
-- utl_url.sql
--
-- Tests for the UTL_URL package (ESCAPE function)
--
-- The escaped form of a multibyte character depends on the character set the
-- character is converted to, so the multibyte cases below pass 'UTF8'
-- explicitly rather than relying on the database encoding.
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

-- Full reserved set: passed through by default, escaped on request
SELECT utl_url.escape(';/?:@&=+$%,#') AS reserved_default;
SELECT utl_url.escape(';/?:@&=+$%,#', TRUE) AS reserved_escaped;

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

-- An unrecognized character set is rejected
SELECT utl_url.escape('a b', FALSE, 'NO_SUCH_CHARSET');

-- A character with no representation in the target character set is rejected
SELECT utl_url.escape('中文', FALSE, 'LATIN1');

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
END;
/
