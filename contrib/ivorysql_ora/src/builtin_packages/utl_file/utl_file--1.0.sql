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

CREATE FUNCTION sys.ora_utl_file_fclose_all()
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_file_fclose_all'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_fremove(location text, filename text)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_file_fremove'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_get_line(file integer)
RETURNS TEXT
AS 'MODULE_PATHNAME','ora_utl_file_get_line'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_get_line(file integer, len integer)
RETURNS TEXT
AS 'MODULE_PATHNAME','ora_utl_file_get_line'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_put(file integer, buffer text)
RETURNS bool
AS 'MODULE_PATHNAME','ora_utl_file_put'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_put(file integer, buffer anyelement)
RETURNS bool
AS $$SELECT sys.ora_utl_file_put($1, $2::text); $$
LANGUAGE SQL VOLATILE;

CREATE FUNCTION sys.ora_utl_file_put_line(file INTEGER, buffer text)
RETURNS bool
AS 'MODULE_PATHNAME','ora_utl_file_put_line'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_put_line(file INTEGER, buffer text, autoflush bool)
RETURNS bool
AS 'MODULE_PATHNAME','ora_utl_file_put_line'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_put_line(file INTEGER, buffer anyelement)
RETURNS bool
AS $$SELECT sys.ora_utl_file_put_line($1, $2::text); $$
LANGUAGE SQL VOLATILE;

CREATE FUNCTION sys.ora_utl_file_put_line(file INTEGER, buffer anyelement, autoflush bool)
RETURNS bool
AS $$SELECT sys.ora_utl_file_put_line($1, $2::text, autoflush); $$
LANGUAGE SQL VOLATILE;

CREATE FUNCTION sys.ora_utl_file_put_raw(file integer, buffer bytea, autoflush bool)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_file_put_raw'
LANGUAGE C VOLATILE;


-- for UTL_FILE Security Model compliance
/* table carry all safe directories */
CREATE TABLE IF NOT EXISTS sys.utl_file_directory(
    dirname name PRIMARY KEY,
    dir TEXT
);
/* allow only read on utl_file.utl_file_dir to unprivileged users */
REVOKE ALL ON sys.utl_file_directory FROM PUBLIC;
GRANT SELECT ON TABLE sys.utl_file_directory TO PUBLIC;

-- ORA_UTL_FILE_FILE_TYPE Definition
-- XXX - I could not find a way to define a type inside a package and use it
CREATE TYPE sys.ORA_UTL_FILE_FILE_TYPE AS(id INTEGER, datatype INTEGER, byte_mode BOOLEAN);

-- UTL_FILE Package Definition
-- UTL_FILE package Header
CREATE OR REPLACE PACKAGE UTL_FILE IS
    PROCEDURE FCLOSE(
        file IN OUT ORA_UTL_FILE_FILE_TYPE
    );

    PROCEDURE FCLOSE_ALL;

    FUNCTION FOPEN(
        location IN VARCHAR2,
        filename IN VARCHAR2,
        open_mode IN VARCHAR2,
        max_linesize IN INTEGER DEFAULT 1024
    )
    RETURN ORA_UTL_FILE_FILE_TYPE;

    FUNCTION FOPEN_NCHAR(
        location IN VARCHAR2,
        filename IN VARCHAR2,
        open_mode IN VARCHAR2,
        max_linesize IN INTEGER DEFAULT 1024
    )
    RETURN ORA_UTL_FILE_FILE_TYPE;

    PROCEDURE FREMOVE(
        location IN VARCHAR2,
        filename IN VARCHAR2
    );

    PROCEDURE GET_LINE(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer OUT TEXT,
        len IN INTEGER DEFAULT NULL
    );

    PROCEDURE GET_LINE_NCHAR(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer OUT TEXT,
        len IN INTEGER DEFAULT NULL
    );

    FUNCTION IS_OPEN(
        file IN ORA_UTL_FILE_FILE_TYPE
    )
    RETURN BOOLEAN;

    PROCEDURE PUT(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN VARCHAR2
    );

    PROCEDURE PUT_LINE(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN VARCHAR2,
        autoflush IN BOOLEAN DEFAULT FALSE
    );

    PROCEDURE PUT_LINE_NCHAR(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN TEXT -- use TEXT as NVARCHAR2 is not supported yet
    );

    PROCEDURE PUT_RAW(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN BYTEA, -- use BYTEA as RAW is not supported yet
        autoflush IN BOOLEAN DEFAULT FALSE
    );
END UTL_FILE;

-- UTL_FILE package Body
CREATE OR REPLACE PACKAGE BODY UTL_FILE IS
    PROCEDURE FCLOSE(
        file IN OUT ORA_UTL_FILE_FILE_TYPE
    ) IS
    BEGIN
        PERFORM sys.ora_utl_file_fclose(file.id);
    END;

    PROCEDURE FCLOSE_ALL IS
    BEGIN
        PERFORM sys.ora_utl_file_fclose_all();
    END;

    FUNCTION FOPEN(
        location IN VARCHAR2,
        filename IN VARCHAR2,
        open_mode IN VARCHAR2,
        max_linesize IN INTEGER DEFAULT 1024
    )
    RETURN ORA_UTL_FILE_FILE_TYPE IS
    file ORA_UTL_FILE_FILE_TYPE;
    BEGIN
        file.id := sys.ora_utl_file_fopen(location, filename, open_mode, max_linesize);
        RETURN file;
    END;

    FUNCTION FOPEN_NCHAR(
        location IN VARCHAR2,
        filename IN VARCHAR2,
        open_mode IN VARCHAR2,
        max_linesize IN INTEGER DEFAULT 1024
    )
    RETURN ORA_UTL_FILE_FILE_TYPE IS
    file ORA_UTL_FILE_FILE_TYPE;
    BEGIN
        file.id := sys.ora_utl_file_fopen(location, filename, open_mode, max_linesize, 'UTF8');
        RETURN file;
    END;

    PROCEDURE FREMOVE(
        location IN VARCHAR2,
        filename IN VARCHAR2
    ) IS
    BEGIN
        PERFORM sys.ora_utl_file_fremove(location, filename);
    END;

    PROCEDURE GET_LINE(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer OUT TEXT,
        len IN INTEGER DEFAULT NULL
    ) IS
    line TEXT;
    BEGIN
        SELECT * INTO line FROM sys.ora_utl_file_get_line(file.id, len);
        buffer := line;
    END;

    PROCEDURE GET_LINE_NCHAR(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer OUT TEXT,
        len IN INTEGER DEFAULT NULL
    ) IS
    line TEXT;
    BEGIN
        SELECT * INTO line FROM sys.ora_utl_file_get_line(file.id, len);
        buffer := line;
    END;


    FUNCTION IS_OPEN(
        file IN ORA_UTL_FILE_FILE_TYPE
    )
    RETURN boolean IS
    BEGIN
        RETURN sys.ora_utl_file_is_open(file.id);
    END;

    PROCEDURE PUT(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN VARCHAR2
    ) IS
    DECLARE
        status BOOLEAN;
    BEGIN
        SELECT sys.ora_utl_file_put(file.id, buffer) INTO status;
    END;

    PROCEDURE PUT_LINE(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN VARCHAR2,
        autoflush IN BOOLEAN DEFAULT FALSE
    ) IS
    DECLARE
        status BOOLEAN;
    BEGIN
        SELECT sys.ora_utl_file_put_line(file.id, buffer, autoflush) INTO status;
    END;

    PROCEDURE PUT_LINE_NCHAR(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN TEXT
    ) IS
    DECLARE
        status BOOLEAN;
    BEGIN
        SELECT sys.ora_utl_file_put_line(file.id, buffer, true) INTO status;
    END;

    PROCEDURE PUT_RAW(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN BYTEA,
        autoflush IN BOOLEAN DEFAULT FALSE
    ) IS
    BEGIN
        PERFORM sys.ora_utl_file_put_raw(file.id, buffer, autoflush);
    END;
END UTL_FILE;
