-- Oracle-compatible NLS_CHARSET_ID and NLS_CHARSET_NAME
SELECT sys.nls_charset_id('US7ASCII') AS us7ascii_id,
       sys.nls_charset_id('WE8ISO8859P1') AS we8iso8859p1_id,
       sys.nls_charset_id('WE8DEC') AS we8dec_id,
       sys.nls_charset_id('WE8MSWIN1252') AS we8mswin1252_id,
       sys.nls_charset_id('ZHS16GBK') AS zhs16gbk_id,
       sys.nls_charset_id('UTF8') AS utf8_id,
       sys.nls_charset_id('UTFE') AS utfe_id,
       sys.nls_charset_id('AL32UTF8') AS al32utf8_id,
       sys.nls_charset_id('AL16UTF16') AS al16utf16_id,
       sys.nls_charset_id('AL16UTF16LE') AS al16utf16le_id;

SELECT sys.nls_charset_name(1) AS us7ascii_name,
       sys.nls_charset_name(31) AS we8iso8859p1_name,
       sys.nls_charset_name(37) AS we8dec_name,
       sys.nls_charset_name(178) AS we8mswin1252_name,
       sys.nls_charset_name(850) AS zhs16gbk_name,
       sys.nls_charset_name(871) AS utf8_name,
       sys.nls_charset_name(872) AS utfe_name,
       sys.nls_charset_name(873) AS al32utf8_name,
       sys.nls_charset_name(2000) AS al16utf16_name,
       sys.nls_charset_name(2002) AS al16utf16le_name;

-- Name matching is case-insensitive.
SELECT sys.nls_charset_id('al32utf8') AS lowercase_id,
       sys.nls_charset_name(850) AS canonical_name;

-- NULL is passed through by both functions.
SELECT sys.nls_charset_id(NULL) IS NULL AS null_id,
       sys.nls_charset_name(NULL) IS NULL AS null_name;

-- Unknown IDs are NULL; unknown names are errors.
SELECT sys.nls_charset_name(99999) AS unknown_id;
SELECT sys.nls_charset_id('NOT_A_CHARSET');
