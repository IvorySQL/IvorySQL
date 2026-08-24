/***************************************************************
 *
 * UTL_URL Package
 *
 * Oracle-compatible URL escape utilities (RFC 2396).
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
     *     ;  /  ?  :  @  &  =  +  $  %  ,  #
     * Everything else, always escaped:
     *     space, control characters, " < > { } | \ ^ [ ] ` and every
     *     non-ASCII byte.
     *
     * Parameters:
     *   url                    IN VARCHAR2 - the original URL
     *   escape_reserved_chars  IN BOOLEAN   - also escape the reserved
     *                                         delimiters (default FALSE)
     *   url_charset            IN VARCHAR2  - character set the characters are
     *                                         converted to before being
     *                                         escaped.  NULL (the default)
     *                                         means the database encoding,
     *                                         with no conversion.
     * Returns:
     *   VARCHAR2 - the escaped URL, or NULL when url IS NULL
     */
    FUNCTION escape(url IN VARCHAR2,
                    escape_reserved_chars IN BOOLEAN DEFAULT FALSE,
                    url_charset IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

END utl_url;

CREATE OR REPLACE PACKAGE BODY utl_url AS

    FUNCTION escape(url IN VARCHAR2,
                    escape_reserved_chars IN BOOLEAN DEFAULT FALSE,
                    url_charset IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_url_escape(url, escape_reserved_chars, url_charset);
    END;

END utl_url;
