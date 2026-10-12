-- PUT_RAW must respect the max_linesize selected by FOPEN.
insert into sys.utl_file_directory(dirname, dir)
select 'raw_limit_directory', current_setting('data_directory');

declare
    f UTL_FILE.FILE_TYPE;
    fexists boolean;
    file_length number;
    block_size integer;
begin
    f := utl_file.fopen('raw_limit_directory', 'regress_raw_limit.bin', 'w', 3);

    begin
        utl_file.put_raw(f, decode('00010203', 'hex'));
        raise notice 'oversized RAW accepted';
    exception
        when others then
            raise notice 'oversized RAW rejected: %', sqlerrm;
    end;

    utl_file.put_raw(f, decode('000102', 'hex'));
    utl_file.fclose(f);
    utl_file.fgetattr('raw_limit_directory', 'regress_raw_limit.bin',
                      fexists, file_length, block_size);
    raise notice 'file exists: %, bytes written: %', fexists, file_length;
end;
/

delete from sys.utl_file_directory where dirname = 'raw_limit_directory';
