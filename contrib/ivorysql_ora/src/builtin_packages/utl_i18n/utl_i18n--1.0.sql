/***************************************************************
 *
 * UTL_I18N Package
 *
 * Oracle-compatible national language architecture and character
 * conversion utilities.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_i18n/utl_i18n--1.0.sql
 *
 ***************************************************************/

/*
 * Register the C implementation functions in sys schema.
 */
CREATE FUNCTION sys.utl_i18n_escape_reference(str text, page_cs_name text DEFAULT NULL)
RETURNS text
AS 'MODULE_PATHNAME', 'ivorysql_utl_i18n_escape_reference'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_i18n_unescape_reference(str text)
RETURNS text
AS 'MODULE_PATHNAME', 'ivorysql_utl_i18n_unescape_reference'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_i18n_string_to_raw(data text, dst_charset text DEFAULT NULL)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ivorysql_utl_i18n_string_to_raw'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_i18n_raw_to_char(data bytea, src_charset text DEFAULT NULL)
RETURNS text
AS 'MODULE_PATHNAME', 'ivorysql_utl_i18n_raw_to_char'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

/* Revoke PUBLIC execute on internal resolver functions (CWE-862 protection) */
REVOKE ALL ON FUNCTION sys.utl_i18n_escape_reference(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_i18n_unescape_reference(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_i18n_string_to_raw(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_i18n_raw_to_char(bytea, text) FROM PUBLIC;

-- PL/iSQL package declaration
CREATE OR REPLACE PACKAGE utl_i18n AS

    /*
     * ESCAPE_REFERENCE
     * Converts a string to its character reference counterparts (numeric or entity references)
     * for characters that fall outside the document character set.
     */
    FUNCTION escape_reference(str IN VARCHAR2,
                              page_cs_name IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

    /*
     * UNESCAPE_REFERENCE
     * Decodes character references in an input string back to their corresponding character values.
     */
    FUNCTION unescape_reference(str IN VARCHAR2) RETURN VARCHAR2;

    /*
     * STRING_TO_RAW
     * Converts a VARCHAR2 string to another valid Oracle character set, returning RAW data.
     */
    FUNCTION string_to_raw(data IN VARCHAR2,
                           dst_charset IN VARCHAR2 DEFAULT NULL) RETURN RAW;

    /*
     * RAW_TO_CHAR
     * Converts RAW data encoded in a specified Oracle character set into a VARCHAR2 string.
     */
    FUNCTION raw_to_char(data IN RAW,
                         src_charset IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

END utl_i18n;

CREATE OR REPLACE PACKAGE BODY utl_i18n AS

    FUNCTION escape_reference(str IN VARCHAR2,
                              page_cs_name IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_i18n_escape_reference(str, page_cs_name);
    END;

    FUNCTION unescape_reference(str IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_i18n_unescape_reference(str);
    END;

    FUNCTION string_to_raw(data IN VARCHAR2,
                           dst_charset IN VARCHAR2 DEFAULT NULL) RETURN RAW IS
    BEGIN
        RETURN sys.utl_i18n_string_to_raw(data, dst_charset);
    END;

    FUNCTION raw_to_char(data IN RAW,
                         src_charset IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_i18n_raw_to_char(data, src_charset);
    END;

END utl_i18n;
