/***************************************************************
 *
 * UTL_FILE Package
 *
 * Oracle-compatible file I/O functions.
 *
 ***************************************************************/

-- C function wrappers
CREATE FUNCTION sys.ora_utl_file_fopen(location text, filename text, open_mode text, max_linesize integer, encoding name)
RETURNS INTEGER
AS 'MODULE_PATHNAME','ora_utl_file_fopen'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_fopen(location text, filename text, open_mode text, max_linesize integer)
RETURNS INTEGER
AS 'MODULE_PATHNAME','ora_utl_file_fopen'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_fopen(location text, filename text, open_mode text)
RETURNS INTEGER
AS $$SELECT sys.ora_utl_file_fopen($1, $2, $3, 1024); $$
LANGUAGE SQL VOLATILE;

CREATE FUNCTION sys.ora_utl_file_is_open(file INTEGER)
RETURNS bool
AS 'MODULE_PATHNAME','ora_utl_file_is_open'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_fclose(file INTEGER)
RETURNS INTEGER
AS 'MODULE_PATHNAME','ora_utl_file_fclose'
LANGUAGE C VOLATILE;


-- for UTL_FILE Security Model compliance
/* table carry all safe directories */
CREATE TABLE sys.ora_utl_file_dir(dir text, dirname text unique);
/* allow only read on utl_file.utl_file_dir to unprivileged users */
REVOKE ALL ON sys.ora_utl_file_dir FROM PUBLIC;
GRANT SELECT ON TABLE sys.ora_utl_file_dir TO PUBLIC;

-- ORA_UTL_FILE_FILE_TYPE Definition
-- XXX - I could not find a way to define a type inside a package and use it
CREATE TYPE sys.ORA_UTL_FILE_FILE_TYPE AS(id INTEGER, datatype INTEGER, byte_mode BOOLEAN);

-- UTL_FILE Package Definition
-- UTL_FILE package Header
CREATE OR REPLACE PACKAGE UTL_FILE IS
    PROCEDURE FCLOSE(
        ft IN OUT ORA_UTL_FILE_FILE_TYPE
    );

    FUNCTION FOPEN(
        location IN VARCHAR2,
        filename IN VARCHAR2,
        open_mode IN VARCHAR2,
        max_linesize IN INTEGER DEFAULT 1024
    )
    RETURN ORA_UTL_FILE_FILE_TYPE;

    FUNCTION IS_OPEN(
        ft IN ORA_UTL_FILE_FILE_TYPE
    )
    RETURN BOOLEAN;
END UTL_FILE;

-- UTL_FILE package Body
CREATE OR REPLACE PACKAGE BODY UTL_FILE IS
    PROCEDURE FCLOSE(
        ft IN OUT ORA_UTL_FILE_FILE_TYPE
    ) IS
    BEGIN
        PERFORM sys.ora_utl_file_fclose(ft.id);
    END;

    FUNCTION FOPEN(
        location IN VARCHAR2,
        filename IN VARCHAR2,
        open_mode IN VARCHAR2,
        max_linesize IN INTEGER DEFAULT 1024
    )
    RETURN ORA_UTL_FILE_FILE_TYPE IS
    ft ORA_UTL_FILE_FILE_TYPE;
    BEGIN
        ft.id := sys.ora_utl_file_fopen(location, filename, open_mode, max_linesize);
        RETURN ft;
    END;

    FUNCTION IS_OPEN(
        ft IN ORA_UTL_FILE_FILE_TYPE
    )
    RETURN boolean IS
    BEGIN
        RETURN sys.ora_utl_file_is_open(ft.id);
    END;
END UTL_FILE;
