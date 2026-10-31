--
-- tests for utl_file.frename overwrite semantics
--

-- insert a directory object for testing
insert into sys.utl_file_directory(dirname, dir)
select 'data_directory', current_setting('data_directory');

-- prepare both a source and an existing destination file
declare
    f UTL_FILE.FILE_TYPE;
begin
    f := utl_file.fopen('data_directory', 'frn_src.txt', 'w');
    utl_file.put_line(f, 'SRC');
    utl_file.fclose(f);

    f := utl_file.fopen('data_directory', 'frn_dst.txt', 'w');
    utl_file.put_line(f, 'DST');
    utl_file.fclose(f);
end;
/

-- overwrite => false against an existing destination must fail
declare
begin
    utl_file.frename('data_directory', 'frn_src.txt', 'data_directory', 'frn_dst.txt', false);
    raise notice 'UNEXPECTED: frename succeeded';
exception
    when others then
        raise notice 'frename raised: %', sqlerrm;
end;
/

-- the failed rename must have consumed neither file
declare
    fexists boolean;
    file_length number;
    block_size integer;
begin
    utl_file.fgetattr('data_directory', 'frn_src.txt', fexists, file_length, block_size);
    raise notice 'source still present = %', fexists;
    utl_file.fgetattr('data_directory', 'frn_dst.txt', fexists, file_length, block_size);
    raise notice 'destination still present = %', fexists;
end;
/

-- overwrite => true against an existing destination must succeed
declare
    fexists boolean;
    file_length number;
    block_size integer;
begin
    utl_file.frename('data_directory', 'frn_src.txt', 'data_directory', 'frn_dst.txt', true);
    utl_file.fgetattr('data_directory', 'frn_src.txt', fexists, file_length, block_size);
    raise notice 'after overwrite=true, source present = %', fexists;
    utl_file.fgetattr('data_directory', 'frn_dst.txt', fexists, file_length, block_size);
    raise notice 'after overwrite=true, destination present = %', fexists;
end;
/

-- overwrite => false against a fresh destination must succeed
declare
    f UTL_FILE.FILE_TYPE;
    fexists boolean;
    file_length number;
    block_size integer;
begin
    f := utl_file.fopen('data_directory', 'frn_src.txt', 'w');
    utl_file.put_line(f, 'SRC');
    utl_file.fclose(f);

    utl_file.frename('data_directory', 'frn_src.txt', 'data_directory', 'frn_dst2.txt', false);
    utl_file.fgetattr('data_directory', 'frn_src.txt', fexists, file_length, block_size);
    raise notice 'after fresh target, source present = %', fexists;
    utl_file.fgetattr('data_directory', 'frn_dst2.txt', fexists, file_length, block_size);
    raise notice 'after fresh target, destination present = %', fexists;
end;
/

-- clean up
declare
begin
    utl_file.fremove('data_directory', 'frn_dst.txt');
exception
    when others then
        raise notice 'cleanup frn_dst.txt: %', sqlerrm;
end;
/

declare
begin
    utl_file.fremove('data_directory', 'frn_dst2.txt');
exception
    when others then
        raise notice 'cleanup frn_dst2.txt: %', sqlerrm;
end;
/

delete from sys.utl_file_directory where dirname = 'data_directory';
/
