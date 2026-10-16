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

END utl_encode;
