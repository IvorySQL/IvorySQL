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

CREATE FUNCTION sys.utl_encode_base64_decode(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ivorysql_utl_encode_base64_decode'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

-- QUOTED_PRINTABLE support (RFC 2045 section 6.7, 76-character lines)
CREATE FUNCTION sys.utl_encode_quoted_printable_encode(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_encode_qp_encode'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_encode_quoted_printable_decode(bytea)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_encode_qp_decode'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_encode_text_encode(s varchar2, charset varchar2 DEFAULT NULL, encoding integer DEFAULT NULL)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_encode_text_encode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sys.utl_encode_text_decode(r bytea, charset varchar2 DEFAULT NULL, encoding integer DEFAULT NULL)
RETURNS varchar2
AS 'MODULE_PATHNAME', 'ora_utl_encode_text_decode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sys.ora_utl_raw_cast_to_varchar2(bytea)
RETURNS varchar2
AS 'MODULE_PATHNAME', 'ora_utl_raw_cast_to_varchar2'
LANGUAGE C IMMUTABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sys.utl_encode_mimeheader_decode(buf varchar2)
RETURNS varchar2
AS 'MODULE_PATHNAME', 'ora_utl_encode_mimeheader_decode'
LANGUAGE C IMMUTABLE;

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
     * QUOTED_PRINTABLE_ENCODE
     * RFC 2045 quoted-printable; 76-character lines with '=' soft breaks.
     */
    FUNCTION quoted_printable_encode(r IN RAW) RETURN RAW;

    /*
     * QUOTED_PRINTABLE_DECODE
     * Decodes quoted-printable; strips soft line breaks.
     */
    FUNCTION quoted_printable_decode(r IN RAW) RETURN RAW;

    /*
     * TEXT_ENCODE
     * Convert a VARCHAR2 to the target character set and optionally apply
     * an encoding scheme: NULL = none, 1 = base64, 2 = quoted-printable.
     */
    FUNCTION text_encode(s IN VARCHAR2, charset IN VARCHAR2 DEFAULT NULL, encoding IN INTEGER DEFAULT NULL) RETURN RAW;

    /*
     * TEXT_DECODE
     * Inverse of TEXT_ENCODE.
     */
    FUNCTION text_decode(r IN RAW, charset IN VARCHAR2 DEFAULT NULL, encoding IN INTEGER DEFAULT NULL) RETURN VARCHAR2;
    -- Oracle encoding-scheme constants (see TEXT_ENCODE/MIMEHEADER_ENCODE)
    BASE64           CONSTANT INTEGER := 1;
    QUOTED_PRINTABLE CONSTANT INTEGER := 2;

    FUNCTION mimeheader_encode(buf IN VARCHAR2, encode_charset IN VARCHAR2 DEFAULT NULL, encoding IN INTEGER DEFAULT NULL) RETURN VARCHAR2;
    FUNCTION mimeheader_decode(buf IN VARCHAR2) RETURN VARCHAR2;

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

    FUNCTION quoted_printable_encode(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.utl_encode_quoted_printable_encode(r);
    END;

    FUNCTION quoted_printable_decode(r IN RAW) RETURN RAW IS
    BEGIN
        RETURN sys.utl_encode_quoted_printable_decode(r);
    END;

    FUNCTION text_encode(s IN VARCHAR2, charset IN VARCHAR2 DEFAULT NULL, encoding IN INTEGER DEFAULT NULL) RETURN RAW IS
    BEGIN
        RETURN sys.utl_encode_text_encode(s, charset, encoding);
    END;

    FUNCTION text_decode(r IN RAW, charset IN VARCHAR2 DEFAULT NULL, encoding IN INTEGER DEFAULT NULL) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_encode_text_decode(r, charset, encoding);
    END;

    FUNCTION mimeheader_encode(buf IN VARCHAR2, encode_charset IN VARCHAR2 DEFAULT NULL, encoding IN INTEGER DEFAULT NULL) RETURN VARCHAR2 IS
        v_enc VARCHAR2(1);
        v_charset VARCHAR2(100);
        v_raw RAW;
    BEGIN
        -- Oracle: encoding NULL defaults to quoted-printable; 1 = base64
        IF encoding = 1 THEN
            v_enc := 'B';
        ELSE
            v_enc := 'Q';
        END IF;
        v_charset := COALESCE(encode_charset, current_setting('server_encoding'));

        -- TEXT_ENCODE converts buf into v_charset and applies the scheme
        v_raw := sys.utl_encode_text_encode(buf, v_charset, NULL);

        IF v_enc = 'B' THEN
            RETURN '=?' || v_charset || '?B?' || RTRIM(sys.ora_utl_raw_cast_to_varchar2(sys.utl_encode_base64_encode(v_raw)), CHR(10)) || '?=';
        ELSE
            RETURN '=?' || v_charset || '?Q?' || sys.ora_utl_raw_cast_to_varchar2(sys.utl_encode_quoted_printable_encode(v_raw)) || '?=';
        END IF;
    END;

    FUNCTION mimeheader_decode(buf IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_encode_mimeheader_decode(buf);
    END;

END utl_encode;

