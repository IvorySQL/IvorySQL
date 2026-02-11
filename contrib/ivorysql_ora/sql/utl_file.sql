--
-- tests for utl_file package
--

-- insert a few directory objects for testing
insert into sys.utl_file_directory(dirname, dir)
select 'data_directory', current_setting('data_directory');

-- test case for fopen with invalid directory object name
declare
    f sys.ora_utl_file_file_type;
begin
    -- an invalid directory object name
    f := utl_file.fopen('wrong_directory','regress.txt','a',1024);
end;
/

-- test fopen, put, putf, put_line, new_line, get_line, is_open, fclose, fclose_all
declare
    f sys.ora_utl_file_file_type;
    line text;
    i integer;
begin
    f := utl_file.fopen('data_directory', 'regress.txt', 'w');

    -- data writing
    utl_file.put_line(f, 'abc');
    utl_file.put_line(f, '123'::numeric);
    utl_file.put_line(f, '-----');
    utl_file.new_line(f);
    utl_file.put_line(f, '-----');
    utl_file.new_line(f, 0);
    utl_file.put_line(f, '-----');
    utl_file.new_line(f, 2);
    utl_file.put_line(f, '-----');
    utl_file.put(f, 'a');
    utl_file.put(f, 'b');
    utl_file.new_line(f);
    utl_file.putf(f, '[1=%s, 2=%s, 3=%s, 4=%s, 5=%s]', '1', '2', '3', '4', '5');
    utl_file.new_line(f);
    utl_file.put_line(f, '1234567890');
    utl_file.fclose(f);

    f := utl_file.fopen('data_directory', 'regress.txt', 'r');

    -- data reading
    i := 1;
    utl_file.get_line(f, line);
    while line is not null and i < 11 loop
        raise notice '[%] >>%<<', i, line;
        utl_file.get_line(f, line);
        i:=i+1;

    end loop;

    while line is not null loop
        raise notice '[%] >>%<<', i, line;
        utl_file.get_line(f, line, 3);
        i:=i+1;
    end loop;

    raise notice '>>%<<', line;
    utl_file.fclose(f);

    exception
        when others then
            raise notice 'exception: % ', sqlerrm;
            raise notice 'is_open(f) = %', utl_file.is_open(f);
            utl_file.fclose_all();
            raise notice 'is_open(f) = %', utl_file.is_open(f);
end;
/

-- test fgetattr, fcopy, fremove, frename
declare
    fexists boolean;
    file_length integer;
    block_size integer;
begin
    utl_file.fgetattr('data_directory', 'regress.txt', fexists, file_length, block_size);
    raise notice 'fexists = %, file_length = %, block_size = %', fexists, file_length, block_size;
    utl_file.fcopy('data_directory', 'regress.txt', 'data_directory', 'regress2.txt');
    utl_file.fgetattr('data_directory', 'regress2.txt', fexists, file_length, block_size);
    raise notice 'fexists = %, file_length = %, block_size = %', fexists, file_length, block_size;
    utl_file.fremove('data_directory', 'regress2.txt');
    utl_file.fgetattr('data_directory', 'regress2.txt', fexists, file_length, block_size);
    raise notice 'fexists = %, file_length = %, block_size = %', fexists, file_length, block_size;
    utl_file.frename('data_directory', 'regress.txt', 'data_directory', 'regress2.txt', true);
    utl_file.fgetattr('data_directory', 'regress2.txt', fexists, file_length, block_size);
    raise notice 'fexists = %, file_length = %, block_size = %', fexists, file_length, block_size;
end;
/

-- test fflush, fseek
declare
    f sys.ora_utl_file_file_type;
    f1 sys.ora_utl_file_file_type;
    line text;
    i integer;
    line2_pos integer;
begin
    f := utl_file.fopen('data_directory', 'regressflush.txt', 'w');
    f1 := utl_file.fopen('data_directory', 'regressflush.txt', 'r');

    -- data writing
    for i in 1..5 loop
        utl_file.put_line(f, 'line ' || i::text);
    end loop;

    -- data reading before fflush
    raise notice 'data read before fflush';
    utl_file.get_line(f1, line);
    while line is not null loop
        raise notice '>>%<<', line;
        utl_file.get_line(f1, line);
    end loop;
    raise notice '>>%<<', line;

    utl_file.fflush(f);

    -- data reading after fflush
    utl_file.fseek(f1); -- reset off_set to 0
    raise notice 'data read after fflush';
    utl_file.get_line(f1, line);
    line2_pos := utl_file.fgetpos(f1); -- after reading line 1, get position
    while line is not null loop
        raise notice '>>%<<', line;
        utl_file.get_line(f1, line);
    end loop;
    raise notice '>>%<<', line;
    raise notice 'lets print line#2 again';
    utl_file.fseek(f1, 0, line2_pos); -- seek to line 2 position
    utl_file.get_line(f1, line);
    raise notice '>>%<<', line;

    utl_file.fclose_all();

    exception
        when others then
            raise notice 'exception: % ', sqlerrm;
            raise notice 'is_open(f) = %', utl_file.is_open(f);
            raise notice 'is_open(f1) = %', utl_file.is_open(f1);
            utl_file.fclose_all();
            raise notice 'is_open(f) = %', utl_file.is_open(f);
            raise notice 'is_open(f1) = %', utl_file.is_open(f1);
end;
/

-- test cases for automatic file closing on session terminated/rollback etc
declare
    f sys.ora_utl_file_file_type;
begin
    f := utl_file.fopen('data_directory','regress.txt','a',1024);

    raise notice 'is_open = %', utl_file.is_open(f);
    commit;
    raise notice 'is_open = %', utl_file.is_open(f);
    rollback;
    raise notice 'is_open = %', utl_file.is_open(f);
end;
/

-- clean up
truncate sys.utl_file_directory;
/
