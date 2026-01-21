-- insert few directory objects for testing
INSERT INTO sys.ora_utl_file_dir VALUES('/tmp/','TMP_DIR');

DECLARE
    ft sys.ORA_UTL_FILE_FILE_TYPE;
    dir_obj_name TEXT;
    file_status BOOLEAN;
BEGIN
    dir_obj_name := 'TMP_DIR';  -- a valid directory object name
    ft := UTL_FILE.FOPEN(dir_obj_name,'test_file1.txt','a',2048);

    IF ft.id IS NOT NULL THEN
        RAISE NOTICE 'File opened successfully with ID: %, directory name: %, file name: %', ft.id, dir_obj_name, 'test_file1.txt';
    END IF;

    SELECT UTL_FILE.IS_OPEN(ft) INTO STRICT file_status;
    RAISE NOTICE 'Is file with ID: % open? %', ft.id, file_status;

    UTL_FILE.FCLOSE(ft);
    RAISE NOTICE 'File with ID: % closed successfully.', ft.id;
END;
/

DECLARE
    ft sys.ORA_UTL_FILE_FILE_TYPE;
    dir_obj_name TEXT;
BEGIN
    dir_obj_name := 'RANDOM_DIR';  -- an invalid directory object name
    ft := UTL_FILE.FOPEN(dir_obj_name,'test_file2.txt','a',2048);

    IF ft.id IS NOT NULL THEN
        RAISE NOTICE 'File opened successfully with ID: %, directory name: %, file name: %', ft.id, dir_obj_name, 'test_file2.txt';
    END IF;
END;
/

DECLARE
    ft1 sys.ORA_UTL_FILE_FILE_TYPE;
    ft2 sys.ORA_UTL_FILE_FILE_TYPE;
    ft3 sys.ORA_UTL_FILE_FILE_TYPE;
    dir_obj_name TEXT;
BEGIN
    dir_obj_name := 'TMP_DIR';  -- a valid directory object name
    ft1 := UTL_FILE.FOPEN(dir_obj_name,'test_file2.txt','a',2048);
    IF ft1.id IS NOT NULL THEN
        RAISE NOTICE 'File opened successfully with ID: %, directory name: %, file name: %', ft1.id, dir_obj_name, 'test_file2.txt';
    END IF;
    ft2 := UTL_FILE.FOPEN(dir_obj_name,'test_file3.txt','a',2048);
    IF ft2.id IS NOT NULL THEN
        RAISE NOTICE 'File opened successfully with ID: %, directory name: %, file name: %', ft2.id, dir_obj_name, 'test_file3.txt';
    END IF;
    ft3 := UTL_FILE.FOPEN(dir_obj_name,'test_file4.txt','a',2048);
    IF ft3.id IS NOT NULL THEN
        RAISE NOTICE 'File opened successfully with ID: %, directory name: %, file name: %', ft3.id, dir_obj_name, 'test_file4.txt';
    END IF;

    UTL_FILE.FCLOSE_ALL();
    RAISE NOTICE 'All files closed successfully.';
END;
/
