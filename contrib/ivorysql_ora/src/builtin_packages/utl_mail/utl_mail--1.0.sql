/***************************************************************
 *
 * UTL_MAIL Package
 *
 * Oracle/EDB-compatible high-level email wrapper built on the
 * dependency-free SMTP client implemented in utl_mail.c.
 *
 * Oracle signature (23ai arpls UTL_MAIL):
 *
 *   PROCEDURE SEND(sender, recipients[, cc[, bcc[, subject[,
 *                  message[, mime_type[, priority[, replyto]]]]]]]);
 *   PROCEDURE SEND_ATTACH_RAW(..., attachment RAW, att_inline BOOLEAN,
 *                  att_mime_type VARCHAR2, att_filename VARCHAR2);
 *   PROCEDURE SEND_ATTACH_VARCHAR2(..., attachment VARCHAR2, ...);
 *
 * Notes:
 *   - unlike Oracle, priority is declared INTEGER (PLS_INTEGER is not a
 *     keyword in the current PL/iSQL engine); it is validated to 1..5
 *   - RAW is supported natively, so SEND_ATTACH_RAW takes the genuine
 *     Oracle RAW type (a bytea domain) and round-trips binary attachments
 *   - sending requires utl_mail.smtp_out_server and a matching entry in
 *     utl_mail.smtp_out_whitelist, both superuser-only (see utl_mail.c)
 *   - failures surface as UTL_MAIL.INVALID_MAILBOX /
 *     UTL_MAIL.EMAIL_SEND_FAILED (SQLSTATE P0001, catchable with
 *     "WHEN OTHERS", mirroring utl_file's exception convention)
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_mail/utl_mail--1.0.sql
 *
 ***************************************************************/

-- C function wrappers (parameter validation + MIME assembly + SMTP client)
CREATE FUNCTION sys.ora_utl_mail_send(
    sender text,
    recipients text,
    cc text,
    bcc text,
    subject text,
    message text,
    mime_type text,
    priority integer,
    replyto text)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_mail_send'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_mail_send_attach_raw(
    sender text,
    recipients text,
    cc text,
    bcc text,
    subject text,
    message text,
    mime_type text,
    priority integer,
    attachment bytea,
    att_inline boolean,
    att_mime_type text,
    att_filename text)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_mail_send_attach_raw'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_mail_send_attach_varchar2(
    sender text,
    recipients text,
    cc text,
    bcc text,
    subject text,
    message text,
    mime_type text,
    priority integer,
    attachment text,
    att_inline boolean,
    att_mime_type text,
    att_filename text)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_mail_send_attach_varchar2'
LANGUAGE C VOLATILE;

-- UTL_MAIL Package Header
CREATE OR REPLACE PACKAGE UTL_MAIL IS

    PROCEDURE SEND(
        sender IN VARCHAR2,
        recipients IN VARCHAR2,
        cc IN VARCHAR2 DEFAULT NULL,
        bcc IN VARCHAR2 DEFAULT NULL,
        subject IN VARCHAR2 DEFAULT NULL,
        message IN VARCHAR2 DEFAULT NULL,
        mime_type IN VARCHAR2 DEFAULT 'text/plain; charset=us-ascii',
        priority IN INTEGER DEFAULT 3,   -- 1..5, high..low
        replyto IN VARCHAR2 DEFAULT NULL
    );

    PROCEDURE SEND_ATTACH_RAW(
        sender IN VARCHAR2,
        recipients IN VARCHAR2,
        cc IN VARCHAR2 DEFAULT NULL,
        bcc IN VARCHAR2 DEFAULT NULL,
        subject IN VARCHAR2 DEFAULT NULL,
        message IN VARCHAR2 DEFAULT NULL,
        mime_type IN VARCHAR2 DEFAULT 'text/plain; charset=us-ascii',
        priority IN INTEGER DEFAULT 3,
        attachment IN RAW,
        att_inline IN BOOLEAN DEFAULT FALSE,
        att_mime_type IN VARCHAR2 DEFAULT 'application/octet',
        att_filename IN VARCHAR2 DEFAULT NULL
    );

    PROCEDURE SEND_ATTACH_VARCHAR2(
        sender IN VARCHAR2,
        recipients IN VARCHAR2,
        cc IN VARCHAR2 DEFAULT NULL,
        bcc IN VARCHAR2 DEFAULT NULL,
        subject IN VARCHAR2 DEFAULT NULL,
        message IN VARCHAR2 DEFAULT NULL,
        mime_type IN VARCHAR2 DEFAULT 'text/plain; charset=us-ascii',
        priority IN INTEGER DEFAULT 3,
        attachment IN VARCHAR2,
        att_inline IN BOOLEAN DEFAULT FALSE,
        att_mime_type IN VARCHAR2 DEFAULT 'application/octet',
        att_filename IN VARCHAR2 DEFAULT NULL
    );

END UTL_MAIL;

-- UTL_MAIL Package Body
CREATE OR REPLACE PACKAGE BODY UTL_MAIL IS

    PROCEDURE SEND(
        sender IN VARCHAR2,
        recipients IN VARCHAR2,
        cc IN VARCHAR2 DEFAULT NULL,
        bcc IN VARCHAR2 DEFAULT NULL,
        subject IN VARCHAR2 DEFAULT NULL,
        message IN VARCHAR2 DEFAULT NULL,
        mime_type IN VARCHAR2 DEFAULT 'text/plain; charset=us-ascii',
        priority IN INTEGER DEFAULT 3,
        replyto IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        PERFORM sys.ora_utl_mail_send(sender, recipients, cc, bcc,
                                      subject, message, mime_type,
                                      priority, replyto);
    END;

    PROCEDURE SEND_ATTACH_RAW(
        sender IN VARCHAR2,
        recipients IN VARCHAR2,
        cc IN VARCHAR2 DEFAULT NULL,
        bcc IN VARCHAR2 DEFAULT NULL,
        subject IN VARCHAR2 DEFAULT NULL,
        message IN VARCHAR2 DEFAULT NULL,
        mime_type IN VARCHAR2 DEFAULT 'text/plain; charset=us-ascii',
        priority IN INTEGER DEFAULT 3,
        attachment IN RAW,
        att_inline IN BOOLEAN DEFAULT FALSE,
        att_mime_type IN VARCHAR2 DEFAULT 'application/octet',
        att_filename IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        PERFORM sys.ora_utl_mail_send_attach_raw(
            sender, recipients, cc, bcc,
            subject, message, mime_type, priority,
            attachment, att_inline, att_mime_type, att_filename);
    END;

    PROCEDURE SEND_ATTACH_VARCHAR2(
        sender IN VARCHAR2,
        recipients IN VARCHAR2,
        cc IN VARCHAR2 DEFAULT NULL,
        bcc IN VARCHAR2 DEFAULT NULL,
        subject IN VARCHAR2 DEFAULT NULL,
        message IN VARCHAR2 DEFAULT NULL,
        mime_type IN VARCHAR2 DEFAULT 'text/plain; charset=us-ascii',
        priority IN INTEGER DEFAULT 3,
        attachment IN VARCHAR2,
        att_inline IN BOOLEAN DEFAULT FALSE,
        att_mime_type IN VARCHAR2 DEFAULT 'application/octet',
        att_filename IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        PERFORM sys.ora_utl_mail_send_attach_varchar2(
            sender, recipients, cc, bcc,
            subject, message, mime_type, priority,
            attachment, att_inline, att_mime_type, att_filename);
    END;

END UTL_MAIL;