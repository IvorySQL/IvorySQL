--
-- utl_mail.sql
--
-- Regression tests for the UTL_MAIL package.
--
-- Design: everything here is deterministic and needs no external SMTP
-- server - every test either stops at the configuration/whitelist gate,
-- at argument validation (which happens before any network I/O), or at
-- the TCP connect to a port that nothing listens on (127.0.0.1:65534,
-- whose failure message is identical whether refused or timed out).
-- The real end-to-end SMTP dialogue (EHLO/MAIL/RCPT/DATA, MIME bodies,
-- base64 attachments, 550 rejection, timeouts) is exercised by the TAP
-- test t/002_utl_mail.pl against an in-test mock SMTP server.
--

SET ivorysql.compatible_mode = oracle;

-- =====================================================================
-- 1. Not configured: UTL_MAIL is disabled until a superuser sets
--    utl_mail.smtp_out_server (default = empty).
-- =====================================================================
SELECT sys.ora_utl_mail_send('sender@example.com', 'alice@example.com',
                             NULL, NULL, 'hello', 'body', NULL, 3, NULL);

-- the error is raised before any argument validation, so even a bogus
-- envelope cannot reach the network when UTL_MAIL is not configured
SELECT sys.ora_utl_mail_send('bogus', 'no-at-sign',
                             NULL, NULL, NULL, NULL, NULL, 0, NULL);

-- =====================================================================
-- 2. Configured but whitelist empty: "deny all outbound mail" default.
-- =====================================================================
SET utl_mail.smtp_out_server = '127.0.0.1:65534';
SELECT sys.ora_utl_mail_send('sender@example.com', 'alice@example.com',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);

-- =====================================================================
-- 3. Server host not listed in the whitelist (exact + parent matching).
-- =====================================================================
SET utl_mail.smtp_out_whitelist = 'example.com, mail.example.org';
SET utl_mail.smtp_out_server = '127.0.0.1:65534';
SELECT sys.ora_utl_mail_send('sender@example.com', 'alice@example.com',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);

-- parent-domain entries allow subdomains of the entry only; the mock host
-- set below is neither exact nor a subdomain of the entries above
SET utl_mail.smtp_out_server = 'smtp.example.net:25';
SELECT sys.ora_utl_mail_send('sender@example.com', 'alice@example.com',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);

-- =====================================================================
-- 4. GUC syntax validation (no transaction involved, plain errors).
-- =====================================================================
SET utl_mail.smtp_out_server = 'host with spaces:25';
SET utl_mail.smtp_out_server = ':2525';
SET utl_mail.smtp_out_server = '127.0.0.1:';
SET utl_mail.timeout = 0;
SET utl_mail.timeout = 4000000;

-- =====================================================================
-- 5. Argument validation - with a valid server+whitelist configuration,
--    so every failure below is a pure parameter error (no network I/O).
-- =====================================================================
SET utl_mail.smtp_out_whitelist = '*';
SET utl_mail.smtp_out_server = '127.0.0.1:65534';
SET utl_mail.timeout = 1000;

-- NULL sender
SELECT sys.ora_utl_mail_send(NULL, 'alice@example.com',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);
-- NULL recipients (required)
SELECT sys.ora_utl_mail_send('sender@example.com', NULL,
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);
-- empty recipients (required)
SELECT sys.ora_utl_mail_send('sender@example.com', '',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);
-- empty list member between commas
SELECT sys.ora_utl_mail_send('sender@example.com', 'a@example.com,,b@example.com',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);
-- sender without '@'
SELECT sys.ora_utl_mail_send('not-an-address', 'alice@example.com',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);
-- recipient with whitespace (would break SMTP commands)
SELECT sys.ora_utl_mail_send('sender@example.com', 'bad address@example.com',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);
-- double '@'
SELECT sys.ora_utl_mail_send('sender@example.com', 'alice@bob@example.com',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);
-- recipient with angle brackets / command separators
SELECT sys.ora_utl_mail_send('sender@example.com', '<alice@example.com>',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);
SELECT sys.ora_utl_mail_send('sender@example.com', 'alice@example.com;quit',
                             NULL, NULL, NULL, NULL, NULL, 3, NULL);
-- invalid cc / bcc members
SELECT sys.ora_utl_mail_send('sender@example.com', 'alice@example.com',
                             'carol@example.com, nope', NULL, NULL, NULL, NULL, 3, NULL);
SELECT sys.ora_utl_mail_send('sender@example.com', 'alice@example.com',
                             NULL, 'bob@example.com,,', NULL, NULL, NULL, 3, NULL);
-- priority out of the documented 1..5 range
SELECT sys.ora_utl_mail_send('sender@example.com', 'alice@example.com',
                             NULL, NULL, NULL, NULL, NULL, 0, NULL);
SELECT sys.ora_utl_mail_send('sender@example.com', 'alice@example.com',
                             NULL, NULL, NULL, NULL, NULL, 6, NULL);

-- =====================================================================
-- 6. With valid arguments the pipeline reaches the TCP connect; against
--    a closed local port this fails fast with EMAIL_SEND_FAILED (both
--    "connection refused" and "timeout" report the same message).
-- =====================================================================
SELECT sys.ora_utl_mail_send('sender@example.com',
                             'alice@example.com, bob@example.com',
                             'carol@example.com', 'dave@example.com',
                             'hello subject', 'hello body', NULL, 3,
                             'reply@example.com');

-- package-level call path (PL/iSQL -> sys.ora_utl_mail_send), caught
-- as WHEN OTHERS like Oracle users would handle UTL_MAIL failures
BEGIN
  utl_mail.send('sender@example.com', 'alice@example.com',
                subject => 'subj', message => 'msg', priority => 2);
  RAISE NOTICE 'unexpected success';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'caught: %', SQLERRM;
END;
/

-- SEND_ATTACH_RAW and SEND_ATTACH_VARCHAR2 reach the same connect stage
BEGIN
  utl_mail.send_attach_raw('sender@example.com', 'alice@example.com',
                           attachment => decode('a1b2c3', 'hex'),
                           att_filename => 'data.bin');
  RAISE NOTICE 'unexpected success';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'caught: %', SQLERRM;
END;
/

BEGIN
  utl_mail.send_attach_varchar2('sender@example.com', 'alice@example.com',
                                attachment => 'text attachment contents',
                                att_inline => TRUE);
  RAISE NOTICE 'unexpected success';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'caught: %', SQLERRM;
END;
/

-- =====================================================================
-- cleanup: restore defaults so later tests in the same installcheck run
-- start from the "not configured / deny all" posture
-- =====================================================================
RESET utl_mail.smtp_out_server;
RESET utl_mail.smtp_out_whitelist;
RESET utl_mail.timeout;