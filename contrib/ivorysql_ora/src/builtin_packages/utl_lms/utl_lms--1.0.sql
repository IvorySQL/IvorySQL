/***************************************************************
 *
 * UTL_LMS Package
 *
 * Oracle-compatible Language and Message Services formatting utilities.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_lms/utl_lms--1.0.sql
 *
 ***************************************************************/

-- Internal C resolvers
CREATE FUNCTION sys.utl_lms_format_message_internal(format text,
                                                    p1 text DEFAULT NULL,
                                                    p2 text DEFAULT NULL,
                                                    p3 text DEFAULT NULL,
                                                    p4 text DEFAULT NULL)
RETURNS text
AS 'MODULE_PATHNAME', 'utl_lms_format_message_internal'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_lms_format_message_extended_internal(format text,
                                                             p1 text DEFAULT NULL,
                                                             p2 text DEFAULT NULL,
                                                             p3 text DEFAULT NULL,
                                                             p4 text DEFAULT NULL,
                                                             p5 text DEFAULT NULL,
                                                             p6 text DEFAULT NULL,
                                                             p7 text DEFAULT NULL,
                                                             p8 text DEFAULT NULL)
RETURNS text
AS 'MODULE_PATHNAME', 'utl_lms_format_message_extended_internal'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_lms_get_message_internal(errnum integer,
                                                 product text DEFAULT 'rdbms',
                                                 facility text DEFAULT 'ora',
                                                 language text DEFAULT 'american')
RETURNS text
AS 'MODULE_PATHNAME', 'utl_lms_get_message_internal'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_lms_get_message_extended_internal(errnum integer,
                                                          product text,
                                                          facility text,
                                                          language text)
RETURNS text
AS 'MODULE_PATHNAME', 'utl_lms_get_message_extended_internal'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.utl_lms_format_message_internal(text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_lms_format_message_extended_internal(text, text, text, text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_lms_get_message_internal(integer, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_lms_get_message_extended_internal(integer, text, text, text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE utl_lms AS

    /*
     * FORMAT_MESSAGE
     * Replaces '%s' and '%d' format specifiers in template string with input arguments.
     */
    FUNCTION format_message(format IN VARCHAR2,
                            p1     IN VARCHAR2 DEFAULT NULL,
                            p2     IN VARCHAR2 DEFAULT NULL,
                            p3     IN VARCHAR2 DEFAULT NULL,
                            p4     IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

    FUNCTION format_message(format IN VARCHAR2,
                            p1     IN VARCHAR2,
                            p2     IN VARCHAR2,
                            p3     IN VARCHAR2,
                            p4     IN VARCHAR2,
                            p5     IN VARCHAR2,
                            p6     IN VARCHAR2 DEFAULT NULL,
                            p7     IN VARCHAR2 DEFAULT NULL,
                            p8     IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

    /*
     * GET_MESSAGE
     * Retrieves error message text for a specific error number.
     */
    PROCEDURE get_message(errnum   IN  INTEGER,
                          product  IN  VARCHAR2,
                          facility IN  VARCHAR2,
                          language IN  VARCHAR2,
                          message  OUT VARCHAR2);

END utl_lms;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY utl_lms AS

    FUNCTION format_message(format IN VARCHAR2,
                            p1     IN VARCHAR2 DEFAULT NULL,
                            p2     IN VARCHAR2 DEFAULT NULL,
                            p3     IN VARCHAR2 DEFAULT NULL,
                            p4     IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_lms_format_message_internal(format::text,
                                                   p1::text,
                                                   p2::text,
                                                   p3::text,
                                                   p4::text)::varchar2;
    END;

    FUNCTION format_message(format IN VARCHAR2,
                            p1     IN VARCHAR2,
                            p2     IN VARCHAR2,
                            p3     IN VARCHAR2,
                            p4     IN VARCHAR2,
                            p5     IN VARCHAR2,
                            p6     IN VARCHAR2 DEFAULT NULL,
                            p7     IN VARCHAR2 DEFAULT NULL,
                            p8     IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_lms_format_message_extended_internal(format::text,
                                                            p1::text,
                                                            p2::text,
                                                            p3::text,
                                                            p4::text,
                                                            p5::text,
                                                            p6::text,
                                                            p7::text,
                                                            p8::text)::varchar2;
    END;

    PROCEDURE get_message(errnum   IN  INTEGER,
                          product  IN  VARCHAR2,
                          facility IN  VARCHAR2,
                          language IN  VARCHAR2,
                          message  OUT VARCHAR2) IS
        res text;
    BEGIN
        res := sys.utl_lms_get_message_internal(errnum,
                                                product::text,
                                                facility::text,
                                                language::text);
        message := res::varchar2;
    END;

END utl_lms;
