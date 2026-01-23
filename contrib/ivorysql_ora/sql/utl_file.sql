-- insert a few directory objects for testing
INSERT INTO sys.utl_file_directory(dirname, dir)
SELECT 'data_directory', current_setting('data_directory');

-- test cases for UTL_FILE.FOPEN, UTL_FILE.FCLOSE, UTL_FILE.IS_OPEN
DECLARE
    ft sys.ORA_UTL_FILE_FILE_TYPE;
    file_status BOOLEAN;
BEGIN
    -- a valid directory object name
    ft := UTL_FILE.FOPEN('data_directory','test_file1.txt','a',2048);

    IF ft.id IS NOT NULL THEN
        RAISE NOTICE 'File opened successfully with ID: %, directory name: %, file name: %', ft.id, 'data_directory', 'test_file1.txt';
    END IF;

    SELECT UTL_FILE.IS_OPEN(ft) INTO STRICT file_status;
    RAISE NOTICE 'Is file still open? file ID: % - (%)', ft.id, file_status;
    UTL_FILE.FCLOSE(ft);
    SELECT UTL_FILE.IS_OPEN(ft) INTO STRICT file_status;
    RAISE NOTICE 'Is file still open? file ID: % - (%)', ft.id, file_status;
END;
/

-- test case for UTL_FILE.FOPEN with invalid directory object name
DECLARE
    ft sys.ORA_UTL_FILE_FILE_TYPE;
BEGIN
    -- an invalid directory object name
    ft := UTL_FILE.FOPEN('RANDOM_DIR','test_file1.txt','a',2048);
END;
/

-- test case for UTL_FILE.FCLOSE_ALL
DECLARE
    ft1 sys.ORA_UTL_FILE_FILE_TYPE;
    ft2 sys.ORA_UTL_FILE_FILE_TYPE;
    ft3 sys.ORA_UTL_FILE_FILE_TYPE;
    file_status1 BOOLEAN;
    file_status2 BOOLEAN;
    file_status3 BOOLEAN;
BEGIN
    ft1 := UTL_FILE.FOPEN('data_directory','test_file1.txt','a',2048);
    ft2 := UTL_FILE.FOPEN('data_directory','test_file2.txt','a',2048);
    ft3 := UTL_FILE.FOPEN('data_directory','test_file3.txt','a',2048);

    SELECT UTL_FILE.IS_OPEN(ft1), UTL_FILE.IS_OPEN(ft2), UTL_FILE.IS_OPEN(ft3) INTO STRICT file_status1, file_status2, file_status3;
    RAISE NOTICE 'Check if files are still open? file ID: % - (%), file ID: % - (%), file ID: % - (%)', ft1.id, file_status1, ft2.id, file_status2, ft3.id, file_status3;
    UTL_FILE.FCLOSE_ALL();
    SELECT UTL_FILE.IS_OPEN(ft1), UTL_FILE.IS_OPEN(ft2), UTL_FILE.IS_OPEN(ft3) INTO STRICT file_status1, file_status2, file_status3;
    RAISE NOTICE 'Check if files are still open? file ID: % - (%), file ID: % - (%), file ID: % - (%)', ft1.id, file_status1, ft2.id, file_status2, ft3.id, file_status3;
END;
/

-- test cases for automatic file closing on session abnormally closing session or COMMIT/ROLLBACK/ABORT
DECLARE
    ft1 sys.ORA_UTL_FILE_FILE_TYPE;
    ft2 sys.ORA_UTL_FILE_FILE_TYPE;
    file_status1 BOOLEAN;
    file_status2 BOOLEAN;
BEGIN
    ft1 := UTL_FILE.FOPEN('data_directory','test_file1.txt','a',2048);
    ft2 := UTL_FILE.FOPEN('data_directory','test_file2.txt','a',2048);

    SELECT UTL_FILE.IS_OPEN(ft1), UTL_FILE.IS_OPEN(ft2) INTO STRICT file_status1, file_status2;
    RAISE NOTICE 'Check if files are still open? file ID: % - (%), file ID: % - (%)', ft1.id, file_status1, ft2.id, file_status2;
    COMMIT;
    SELECT UTL_FILE.IS_OPEN(ft1), UTL_FILE.IS_OPEN(ft2) INTO STRICT file_status1, file_status2;
    RAISE NOTICE 'Check if files are still open? file ID: % - (%), file ID: % - (%)', ft1.id, file_status1, ft2.id, file_status2;
END;
/

DECLARE
    ft1 sys.ORA_UTL_FILE_FILE_TYPE;
    ft2 sys.ORA_UTL_FILE_FILE_TYPE;
    file_status1 BOOLEAN;
    file_status2 BOOLEAN;
BEGIN
    ft1 := UTL_FILE.FOPEN('data_directory','test_file1.txt','a',2048);
    ft2 := UTL_FILE.FOPEN('data_directory','test_file2.txt','a',2048);

    SELECT UTL_FILE.IS_OPEN(ft1), UTL_FILE.IS_OPEN(ft2) INTO STRICT file_status1, file_status2;
    RAISE NOTICE 'Check if files are still open? file ID: % - (%), file ID: % - (%)', ft1.id, file_status1, ft2.id, file_status2;
    ROLLBACK;
    SELECT UTL_FILE.IS_OPEN(ft1), UTL_FILE.IS_OPEN(ft2) INTO STRICT file_status1, file_status2;
    RAISE NOTICE 'Check if files are still open? file ID: % - (%), file ID: % - (%)', ft1.id, file_status1, ft2.id, file_status2;

    RAISE NOTICE 'All files closed automatically by resource_cleanup_callback.';
END;
/

BEGIN;
SELECT UTL_FILE.FOPEN('data_directory','test_file1.txt','a',2048);
ABORT;
/

-- test case for UTL_FILE.PUT_LINE
DECLARE
    ft sys.ORA_UTL_FILE_FILE_TYPE;
    directory TEXT;
    content TEXT;
BEGIN
    ft := UTL_FILE.FOPEN('data_directory','test_file1.txt','a',2048);

    -- Write few lines to the file
    UTL_FILE.PUT_LINE(ft,'line 1.', true);
    UTL_FILE.PUT_LINE(ft,'line 2.', true);
    UTL_FILE.PUT_LINE(ft,'line 3.', true);

    -- Verify file content
    SELECT current_setting('data_directory') INTO STRICT directory;
    SELECT pg_read_file(directory || '/test_file1.txt') INTO STRICT content;

    UTL_FILE.FCLOSE(ft);

    RAISE INFO '%', content;
END;
/

-- clean up
TRUNCATE sys.utl_file_directory;
