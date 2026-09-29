-- PUTF must scan complete characters in the target file encoding.
-- The test database is UTF8 (see ENCODING in Makefile), so the explicit
-- file encodings also exercise database-to-file conversion.
\pset format unaligned
\pset tuples_only on
INSERT INTO sys.utl_file_directory(dirname, dir)
SELECT 'putf_multibyte', current_setting('data_directory');

-- gb18030
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_gb18030.dat', 'w', 1024, 'GB18030') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, '衆n') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'gb18030=' || encode(pg_read_binary_file('utl_file_putf_gb18030.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_gb18030.dat') AS removed \gset

-- gbk
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_gbk.dat', 'w', 1024, 'GBK') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, '衆n') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'gbk=' || encode(pg_read_binary_file('utl_file_putf_gbk.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_gbk.dat') AS removed \gset

-- sjis
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_sjis.dat', 'w', 1024, 'SJIS') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, 'ソn') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'sjis=' || encode(pg_read_binary_file('utl_file_putf_sjis.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_sjis.dat') AS removed \gset

-- big5
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_big5.dat', 'w', 1024, 'BIG5') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, 'αn') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'big5=' || encode(pg_read_binary_file('utl_file_putf_big5.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_big5.dat') AS removed \gset

-- utf8
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_utf8.dat', 'w', 1024, 'UTF8') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, '衆n') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'utf8=' || encode(pg_read_binary_file('utl_file_putf_utf8.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_utf8.dat') AS removed \gset

-- gb18030_tokens
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_gb18030_tokens.dat', 'w', 1024, 'GB18030') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, '衆n\n%s%%', 'OK') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'gb18030_tokens=' || replace(encode(pg_read_binary_file('utl_file_putf_gb18030_tokens.dat'), 'hex'), '0d0a', '0a');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_gb18030_tokens.dat') AS removed \gset

-- gb18030_argument
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_gb18030_argument.dat', 'w', 1024, 'GB18030') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, '%s|衆n', '衆n') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'gb18030_argument=' || encode(pg_read_binary_file('utl_file_putf_gb18030_argument.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_gb18030_argument.dat') AS removed \gset

-- percent_multibyte
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_percent_multibyte.dat', 'w', 1024, 'GB18030') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, '%衆n') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'percent_multibyte=' || encode(pg_read_binary_file('utl_file_putf_percent_multibyte.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_percent_multibyte.dat') AS removed \gset

-- four_byte
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_four_byte.dat', 'w', 1024, 'GB18030') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, '😀n') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'four_byte=' || encode(pg_read_binary_file('utl_file_putf_four_byte.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_four_byte.dat') AS removed \gset

-- latin1
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_latin1.dat', 'w', 1024, 'LATIN1') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, 'én') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'latin1=' || encode(pg_read_binary_file('utl_file_putf_latin1.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_latin1.dat') AS removed \gset

-- exact_limit
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_exact_limit.dat', 'w', 3, 'GB18030') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, '衆n') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'exact_limit=' || encode(pg_read_binary_file('utl_file_putf_exact_limit.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_exact_limit.dat') AS removed \gset

-- ascii_tokens
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_ascii_tokens.dat', 'w', 1024, 'UTF8') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, '%s|%%|tail\', 'OK') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'ascii_tokens=' || encode(pg_read_binary_file('utl_file_putf_ascii_tokens.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_ascii_tokens.dat') AS removed \gset

-- null_argument
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_null_argument.dat', 'w', 1024, 'UTF8') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, '%s|%s', 'OK') AS wrote \gset
SELECT sys.ora_utl_file_fclose(:fd) AS closed \gset
SELECT 'null_argument=' || encode(pg_read_binary_file('utl_file_putf_null_argument.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_null_argument.dat') AS removed \gset

-- Enforce the byte limit, not the number of characters.  An error aborts
-- this statement and closes its file handle; the next statement removes it.
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_limit.dat', 'w', 2, 'GB18030') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, '衆n');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_limit.dat') AS removed \gset

-- A character that exceeds the remaining budget must not be half written.
SELECT sys.ora_utl_file_fopen('putf_multibyte', 'utl_file_putf_partial.dat', 'w', 2, 'GB18030') AS fd \gset
SELECT sys.ora_utl_file_putf(:fd, 'a衆');
SELECT 'partial=' || encode(pg_read_binary_file('utl_file_putf_partial.dat'), 'hex');
SELECT sys.ora_utl_file_fremove('putf_multibyte', 'utl_file_putf_partial.dat') AS removed \gset
DELETE FROM sys.utl_file_directory WHERE dirname = 'putf_multibyte';
\pset tuples_only off
\pset format aligned
