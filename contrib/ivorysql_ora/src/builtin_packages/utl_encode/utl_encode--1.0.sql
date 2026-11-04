/***************************************************************
 *
 * UTL_ENCODE Package
 *
 * Oracle-compatible encoding/decoding utilities.
 *
 ***************************************************************
*/

/*
 * Register the C implementation in the sys schema.
 * Input/output use bytea (RAW maps to bytea in IvorySQL).
 * STRICT: returns NULL automatically when input is NULL.
 */
CREATE FUNCTION sys.utl_encode_base64_encode(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ivorysql_utl_encode_base64_encode'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

{anchor}
/*
 * TEXT_ENCODE / TEXT_DECODE: charset conversion (RAW <-> text).
 * enc_charset is optional; NULL means the database encoding.  Not STRICT:
 * a NULL enc_charset is the documented default, not a NULL result.
 */
CREATE FUNCTION sys.utl_encode_text_encode(text, text)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ivorysql_utl_encode_text_encode'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_encode_text_decode(bytea, text)
RETURNS text
AS 'MODULE_PATHNAME', 'ivorysql_utl_encode_text_decode'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

/*
 * UUENCODE / UUDECODE and QUOTED_PRINTABLE (RFC 2045).
 */
CREATE FUNCTION sys.utl_encode_uuencode(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ivorysql_utl_encode_uuencode'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_encode_uudecode(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ivorysql_utl_encode_uudecode'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_encode_quoted_printable_encode(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ivorysql_utl_encode_quoted_printable_encode'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_encode_quoted_printable_decode(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ivorysql_utl_encode_quoted_printable_decode'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

-- PL/iSQL package declaration
CREATE PACKAGE utl_encode AS

    /*
     * BASE64_ENCODE
     * Encodes binary RAW data to base64 format.
     * Each output line is 64 characters followed by a newline (RFC 1521).
     *
     * Parameters:
     *   r  IN RAW  - binary data to encode
     * Returns:
     *   RAW  - base64-encoded data as ASCII bytes with embedded newlines
     */
    FUNCTION base64_encode(r IN RAW) RETURN RAW;

    /*
     * BASE64_DECODE
     * Decodes base64-encoded RAW data back to binary.
     * Embedded whitespace (LF, CRLF, tab, space) is stripped before decoding.
     *
     * Parameters:
     *   r  IN RAW  - base64-encoded data to decode
     * Returns:
     *   RAW  - decoded binary data
     */
    FUNCTION base64_decode(r IN RAW) RETURN RAW;

    /*
     * TEXT_ENCODE / TEXT_DECODE
     * Charset conversion between the database encoding and the named
     * encoding (NULL enc_charset selects the database encoding).
     */
    FUNCTION text_encode(buf IN VARCHAR2, enc_charset IN VARCHAR2 DEFAULT NULL) RETURN RAW;
    FUNCTION text_decode(buf IN RAW, enc_charset IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

    /*
     * UUENCODE / UUDECODE
     * Classic uuencode body (length-prefixed 60-char lines), no envelope.
     */
    FUNCTION uuencode(r IN RAW) RETURN RAW;
    FUNCTION uudecode(r IN RAW) RETURN RAW;

    /*
     * QUOTED_PRINTABLE_ENCODE / QUOTED_PRINTABLE_DECODE
     * RFC 2045 quoted-printable ( =XX escapes, "=" soft line breaks ).
     */
    FUNCTION quoted_printable_encode(r IN RAW) RETURN RAW;
    FUNCTION quoted_printable_decode(r IN RAW) RETURN RAW;

END utl_encode;

CREATE PACKAGE BODY utl_encode AS

    FUNCTION base64_encode(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN utl_encode_base64_encode(r);
    END;

    FUNCTION base64_decode(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN utl_encode_base64_decode(r);
    END;

    FUNCTION text_encode(buf IN VARCHAR2, enc_charset IN VARCHAR2 DEFAULT NULL) RETURN RAW IS
    BEGIN
        RETURN utl_encode_text_encode(buf, enc_charset);
    END;

    FUNCTION text_decode(buf IN RAW, enc_charset IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    BEGIN
        RETURN utl_encode_text_decode(buf, enc_charset);
    END;

    FUNCTION uuencode(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN utl_encode_uuencode(r);
    END;

    FUNCTION uudecode(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN utl_encode_uudecode(r);
    END;

    FUNCTION quoted_printable_encode(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN utl_encode_quoted_printable_encode(r);
    END;

    FUNCTION quoted_printable_decode(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN utl_encode_quoted_printable_decode(r);
    END;

END utl_encode;
