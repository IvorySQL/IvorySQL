--
-- tests for utl_file.put_raw max_linesize enforcement
--

insert into sys.utl_file_directory(dirname, dir)
select 'test_dir', current_setting('data_directory');

-- oversized buffer: VALUE_ERROR, file not written
select sys.ora_utl_file_fopen('test_dir', 'putraw_over.dat', 'w', 4) as fd \gset
select sys.ora_utl_file_put_raw(:fd, '\x0102030405'::bytea, false);
select sys.ora_utl_file_fclose(:fd) as closed;
select pg_stat_file('putraw_over.dat') is null as not_created;

-- exact limit: accepted
select sys.ora_utl_file_fopen('test_dir', 'putraw_exact.dat', 'w', 4) as fd \gset
select sys.ora_utl_file_put_raw(:fd, '\x01020304'::bytea, false);
select sys.ora_utl_file_fclose(:fd) as closed;
select pg_stat_file('putraw_exact.dat')::text like '(4,%') as exact_ok;

-- default max_linesize (1024): accepted
select sys.ora_utl_file_fopen('test_dir', 'putraw_default.dat', 'w') as fd \gset
select sys.ora_utl_file_put_raw(:fd, '\x0102030405'::bytea, false);
select sys.ora_utl_file_fclose(:fd) as closed;
select pg_stat_file('putraw_default.dat')::text like '(5,%') as default_ok;

-- cleanup
select sys.ora_utl_file_fremove('test_dir', 'putraw_exact.dat') as removed1;
select sys.ora_utl_file_fremove('test_dir', 'putraw_default.dat') as removed2;
