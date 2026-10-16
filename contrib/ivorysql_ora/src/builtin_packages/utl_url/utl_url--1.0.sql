/***************************************************************
 *
 * UTL_URL Package
 *
 * Oracle-compatible URL escape/unescape utilities (RFC 2396).
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_url/utl_url--1.0.sql
 *
 ***************************************************************/

/*
 * Register the C implementation in the sys schema.
 *
 * NOT declared STRICT on purpose: url_charset is legitimately NULL whenever
 * the caller relies on the default, and a STRICT function would then return
 * NULL for every call.  NULL propagation for the url argument is handled in C.
 */
CREATE FUNCTION sys.utl_url_escape(url text, escape_reserved_chars boolean, url_charset text)
RETURNS text
AS 'MODULE_PATHNAME', 'ivorysql_utl_url_escape'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_url_unescape(url text, url_charset text)
RETURNS text
AS 'MODULE_PATHNAME', 'ivorysql_utl_url_unescape'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

-- PL/iSQL package declaration
CREATE OR REPLACE PACKAGE utl_url AS

    /*
     * ESCAPE
     * Returns a URL with the illegal characters (and optionally the reserved
     * characters) escaped using the %2-digit-hex-code format.
     *
     * Unreserved characters, never escaped:
     *     A-Z  a-z  0-9  -  _  .  !  ~  *  '  (  )
     * Reserved characters, escaped only when escape_reserved_chars is TRUE:
     *     ;  /  ?  :  @  &  =  +  $  ,
     * Everything else, always escaped:
     *     #, space, control characters, " < > { } | \ ^ [ ] ` , every
     *     non-ASCII byte, and a literal "%" (already-escaped input is
     *     double-escaped, matching Oracle).
     *
     * Parameters:
     *   url                    IN VARCHAR2 - the original URL
     *   escape_reserved_chars  IN BOOLEAN   - also escape the reserved
     *                                         delimiters (default FALSE)
     *   url_charset            IN VARCHAR2  - character set the characters are
     *                                         converted to before being
     *                                         escaped.  An omitted
     *                                         url_charset and an explicit
     *                                         NULL are equivalent here and
     *                                         both mean the database
     *                                         encoding, with no conversion.
     *                                         Oracle distinguishes the two
     *                                         forms: an omitted argument
     *                                         defaults to
     *                                         utl_http.body_charset
     *                                         (ISO-8859-1) while an explicit
     *                                         NULL selects the database
     *                                         character set.  Using the
     *                                         database encoding for both is
     *                                         a deliberate deviation:
     *                                         ISO-8859-1 cannot represent
     *                                         non-Latin text and UTL_HTTP
     *                                         is not available here.
     * Returns:
     *   VARCHAR2 - the escaped URL, or NULL when url IS NULL
     */
    FUNCTION escape(url IN VARCHAR2,
                    escape_reserved_chars IN BOOLEAN DEFAULT FALSE,
                    url_charset IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

    /*
     * UNESCAPE
     * Converts the %XX escape code sequences of a URL back to the original
     * characters.  Multibyte characters are reassembled from consecutive %XX
     * groups, so UNESCAPE(ESCAPE(x)) returns x.
     *
     * Parameters:
     *   url          IN VARCHAR2 - the URL to unescape
     *   url_charset  IN VARCHAR2 - character set the unescaped bytes are
     *                              assumed to be in; they are converted from
     *                              it to the database encoding.  An omitted
     *                              url_charset and an explicit NULL are
     *                              equivalent here and both mean the bytes
     *                              are already in the database encoding;
     *                              Oracle's omitted form defaults to
     *                              utl_http.body_charset (ISO-8859-1)
     *                              instead (declared deviation, see the
     *                              ESCAPE documentation above).
     * Returns:
     *   VARCHAR2 - the unescaped URL, or NULL when url IS NULL
     *
     * A "%" that is not followed by two hexadecimal digits raises an error
     * (Oracle raises UTL_URL.BAD_URL, ORA-29262).  A %00 escape is likewise
     * rejected, because a text value cannot contain a NUL byte (Oracle
     * instead returns a string containing a NUL byte).
     */
    FUNCTION unescape(url IN VARCHAR2,
                      url_charset IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

END utl_url;

CREATE OR REPLACE PACKAGE BODY utl_url AS

    FUNCTION escape(url IN VARCHAR2,
                    escape_reserved_chars IN BOOLEAN DEFAULT FALSE,
                    url_charset IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_url_escape(url, escape_reserved_chars, url_charset);
    END;

    FUNCTION unescape(url IN VARCHAR2,
                      url_charset IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_url_unescape(url, url_charset);
    END;

END utl_url;
