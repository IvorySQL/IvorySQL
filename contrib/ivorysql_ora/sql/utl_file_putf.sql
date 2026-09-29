--
-- UTL_FILE.PUTF must read its format string at character boundaries.
--
-- The format string is converted to the target file encoding before it is
-- scanned, and in encodings such as GB18030 the trailing byte of a multibyte
-- character can be 0x5c, the backslash, so a byte by byte scan read the last
-- byte of 衆 plus the following ASCII 'n' as the \n escape.
--
insert into sys.utl_file_directory(dirname, dir)
select 'putf_encoding', current_setting('data_directory');

select sys.ora_utl_file_fopen('putf_encoding', 'regress-putf-mb.dat',
                              'w', 1024, 'GB18030') as fd \gset
select sys.ora_utl_file_putf(:fd, '衆n');
select sys.ora_utl_file_fclose(:fd);

-- the escapes themselves must keep working; the backslash is built with chr()
-- so that the string literal does not depend on the escape settings
select sys.ora_utl_file_fopen('putf_encoding', 'regress-putf-esc.dat',
                              'w', 1024, 'GB18030') as fd \gset
select sys.ora_utl_file_putf(:fd, 'a' || chr(92) || 'nb%s%%c', 'Z');
select sys.ora_utl_file_fclose(:fd);

select encode(pg_read_binary_file('regress-putf-mb.dat'), 'hex') as putf_multibyte;

select encode(pg_read_binary_file('regress-putf-esc.dat'), 'hex') as putf_escapes;