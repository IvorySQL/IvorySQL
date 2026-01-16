-- insert few directory objects for testing
INSERT INTO sys.ora_utl_file_dir VALUES('/tmp/','TMP_DIR');

DECLARE
    ft sys.ORA_UTL_FILE_FILE_TYPE;
    dir_obj_name TEXT;
BEGIN
    dir_obj_name := 'TMP_DIR';  -- a valid directory object name
    ft := UTL_FILE.FOPEN(dir_obj_name,'test_file2.txt','a',2048);

    IF ft.id IS NOT NULL THEN
        RAISE NOTICE 'File opened successfully with ID: %, dir_obj_name: %', ft.id, dir_obj_name;
    END IF;

    dir_obj_name := 'RANDOM_DIR';  -- an invalid directory object name
    ft := UTL_FILE.FOPEN(dir_obj_name,'test_file.txt','a',2048);

    IF ft.id IS NOT NULL THEN
        RAISE NOTICE 'File opened successfully with ID: %, dir_obj_name: %', ft.id, dir_obj_name;
    END IF;

    UTL_FILE.FCLOSE(ft);
END;
/
