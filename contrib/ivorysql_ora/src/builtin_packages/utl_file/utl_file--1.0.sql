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

CREATE FUNCTION sys.ora_utl_file_fcopy(src_location text, src_filename text, dest_location text, dest_filename text)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_file_fcopy'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_fcopy(src_location text, src_filename text, dest_location text, dest_filename text, start_line integer)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_file_fcopy'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_fcopy(src_location text, src_filename text, dest_location text, dest_filename text, start_line integer, end_line integer)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_file_fcopy'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_fflush(file integer)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_file_fflush'
LANGUAGE C VOLATILE;

-- Create composite types for ora_utl_file_fgetattr return values
CREATE TYPE sys.ora_utl_file_fgetattr_result AS (fexists bool, file_length number, block_size integer);

CREATE FUNCTION sys.ora_utl_file_fgetattr(location text, filename text)
RETURNS sys.ora_utl_file_fgetattr_result
AS 'MODULE_PATHNAME','ora_utl_file_fgetattr'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_fremove(location text, filename text)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_file_fremove'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_frename(location text, filename text, dest_dir text, dest_file text, overwrite boolean)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_file_frename'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_frename(location text, filename text, dest_dir text, dest_file text)
RETURNS void
AS $$SELECT sys.ora_utl_file_frename($1, $2, $3, $4, false);$$
LANGUAGE SQL VOLATILE;

CREATE FUNCTION sys.ora_utl_file_fseek(file integer, absolute_offset integer, relative_offset integer)
RETURNS void
AS 'MODULE_PATHNAME','ora_utl_file_fseek'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_ftell(file INTEGER)
RETURNS INTEGER
AS 'MODULE_PATHNAME','ora_utl_file_ftell'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_get_line(file integer)
RETURNS TEXT
AS 'MODULE_PATHNAME','ora_utl_file_get_line'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_get_line(file integer, len integer)
RETURNS TEXT
AS 'MODULE_PATHNAME','ora_utl_file_get_line'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_get_raw(file integer, len integer DEFAULT NULL)
RETURNS bytea
AS 'MODULE_PATHNAME','ora_utl_file_get_raw'
LANGUAGE C VOLATILE;

-- Composite result type for ora_utl_file_fgets: (partial, buffer)
CREATE TYPE sys.ora_utl_file_fgets_result AS (partial bool, buffer text);

CREATE FUNCTION sys.ora_utl_file_fgets(file integer, len integer DEFAULT NULL)
RETURNS sys.ora_utl_file_fgets_result
AS 'MODULE_PATHNAME','ora_utl_file_fgets'
LANGUAGE C VOLATILE;


CREATE FUNCTION sys.ora_utl_file_new_line(file integer)
RETURNS bool
AS 'MODULE_PATHNAME','ora_utl_file_new_line'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_new_line(file integer, lines int)
RETURNS bool
AS 'MODULE_PATHNAME','ora_utl_file_new_line'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_put(file integer, buffer text)
RETURNS bool
AS 'MODULE_PATHNAME','ora_utl_file_put'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_put(file integer, buffer anyelement)
RETURNS bool
AS $$SELECT sys.ora_utl_file_put($1, $2::text); $$
LANGUAGE SQL VOLATILE;

CREATE FUNCTION sys.ora_utl_file_putf(file integer, format text, arg1 text, arg2 text, arg3 text, arg4 text, arg5 text)
RETURNS bool
AS 'MODULE_PATHNAME','ora_utl_file_putf'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_file_putf(file integer, format text, arg1 text, arg2 text, arg3 text, arg4 text)
RETURNS bool
AS $$SELECT sys.ora_utl_file_putf($1, $2, $3, $4, $5, $6, NULL); $$
LANGUAGE SQL VOLATILE;

CREATE FUNCTION sys.ora_utl_file_putf(file integer, format text, arg1 text, arg2 text, arg3 text)
RETURNS bool
AS $$SELECT sys.ora_utl_file_putf($1, $2, $3, $4, $5, NULL, NULL); $$
LANGUAGE SQL VOLATILE;

CREATE FUNCTION sys.ora_utl_file_putf(file integer, format text, arg1 text, arg2 text)
RETURNS bool
AS $$SELECT sys.ora_utl_file_putf($1, $2, $3, $4, NULL, NULL, NULL); $$
LANGUAGE SQL VOLATILE;

CREATE FUNCTION sys.ora_utl_file_putf(file integer, format text, arg1 text)
RETURNS bool
AS $$SELECT sys.ora_utl_file_putf($1, $2, $3, NULL, NULL, NULL, NULL); $$
LANGUAGE SQL VOLATILE;

CREATE FUNCTION sys.ora_utl_file_putf(file integer, format text)
RETURNS bool
AS $$SELECT sys.ora_utl_file_putf($1, $2, NULL, NULL, NULL, NULL, NULL); $$
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
AS $$SELECT sys.ora_utl_file_put_line($1, $2::text, $3); $$
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

-- XXX - role 'utl_file_set_umask' causing failures in pg_dump regression tests, 
-- so we skip it till we find a viable solution.
-- DO $$
-- BEGIN
--   IF NOT EXISTS(SELECT * FROM pg_roles where rolname = 'utl_file_set_umask') THEN
--     CREATE ROLE utl_file_set_umask INHERIT NOLOGIN;
--   END IF;
-- END;
-- $$;

-- UTL_FILE Package Definition
-- UTL_FILE package Header
CREATE OR REPLACE PACKAGE UTL_FILE IS
    PROCEDURE FCLOSE(
        file IN OUT ORA_UTL_FILE_FILE_TYPE
    );

    PROCEDURE FCLOSE_ALL;

    PROCEDURE FCOPY(
        location IN VARCHAR2,
        filename IN VARCHAR2,
        dest_dir IN VARCHAR2,
        dest_file IN VARCHAR2,
        start_line IN INTEGER DEFAULT 1,
        end_line IN INTEGER DEFAULT 2147483647
    );

    PROCEDURE FFLUSH(
        file IN ORA_UTL_FILE_FILE_TYPE
    );

    PROCEDURE FGETATTR(
        location     IN VARCHAR2,
        filename     IN VARCHAR2,
        fexists      OUT BOOLEAN,
        file_length  OUT NUMBER,
        block_size   OUT INTEGER
    );

    FUNCTION FOPEN(
        location IN VARCHAR2,
        filename IN VARCHAR2,
        open_mode IN VARCHAR2,
        max_linesize IN INTEGER DEFAULT 1024,
        encoding IN VARCHAR2 DEFAULT NULL
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

    PROCEDURE FRENAME(
        src_location IN VARCHAR2,
        src_filename IN VARCHAR2,
        dest_location IN VARCHAR2,
        dest_filename IN VARCHAR2,
        overwrite IN BOOLEAN DEFAULT FALSE
    );

    PROCEDURE FSEEK(
        file IN OUT  ORA_UTL_FILE_FILE_TYPE,
        absolute_offset IN INTEGER DEFAULT NULL,
        relative_offset IN INTEGER DEFAULT NULL
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

    PROCEDURE GET_RAW(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer OUT BYTEA, -- use BYTEA as RAW is not supported yet
        len IN INTEGER DEFAULT NULL
    );

    FUNCTION FGETS(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN OUT VARCHAR2,
        len IN INTEGER DEFAULT NULL
    )
    RETURN BOOLEAN;

    FUNCTION FGETS_NCHAR(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN OUT VARCHAR2,
        len IN INTEGER DEFAULT NULL
    )
    RETURN BOOLEAN;

    FUNCTION FGETPOS(
        file IN ORA_UTL_FILE_FILE_TYPE
    )
    RETURN INTEGER;

    FUNCTION IS_OPEN(
        file IN ORA_UTL_FILE_FILE_TYPE
    )
    RETURN BOOLEAN;

    PROCEDURE NEW_LINE(
        file IN ORA_UTL_FILE_FILE_TYPE,
        lines IN INTEGER DEFAULT 1
    );

    PROCEDURE PUT(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN VARCHAR2
    );

    PROCEDURE PUTF(
        file IN ORA_UTL_FILE_FILE_TYPE,
        format IN VARCHAR2,
        arg1 IN VARCHAR2 DEFAULT NULL,
        arg2 IN VARCHAR2 DEFAULT NULL,
        arg3 IN VARCHAR2 DEFAULT NULL,
        arg4 IN VARCHAR2 DEFAULT NULL,
        arg5 IN VARCHAR2 DEFAULT NULL
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

    PROCEDURE FCOPY(
        location IN VARCHAR2,
        filename IN VARCHAR2,
        dest_dir IN VARCHAR2,
        dest_file IN VARCHAR2,
        start_line IN INTEGER DEFAULT 1,
        end_line IN INTEGER DEFAULT 2147483647
    ) IS
    BEGIN
        PERFORM sys.ora_utl_file_fcopy(location, filename, dest_dir, dest_file, start_line, end_line);
    END;

    PROCEDURE FFLUSH(
        file IN ORA_UTL_FILE_FILE_TYPE
    ) IS
    BEGIN
        PERFORM sys.ora_utl_file_fflush(file.id);
    END;

    PROCEDURE FGETATTR(
        location     IN VARCHAR2,
        filename     IN VARCHAR2,
        fexists      OUT BOOLEAN,
        file_length  OUT NUMBER,
        block_size   OUT INTEGER
    ) IS
    result sys.ora_utl_file_fgetattr_result;
    BEGIN
        SELECT * INTO result FROM sys.ora_utl_file_fgetattr(location, filename);
        fexists := result.fexists;
        file_length := result.file_length;
        block_size := result.block_size;
    END;

    FUNCTION FOPEN(
        location IN VARCHAR2,
        filename IN VARCHAR2,
        open_mode IN VARCHAR2,
        max_linesize IN INTEGER DEFAULT 1024,
        encoding IN VARCHAR2 DEFAULT NULL
    )
    RETURN ORA_UTL_FILE_FILE_TYPE IS
    file ORA_UTL_FILE_FILE_TYPE;
    BEGIN
        file.id := sys.ora_utl_file_fopen(location, filename, open_mode, max_linesize, encoding::name);
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

    PROCEDURE FRENAME(
        src_location IN VARCHAR2,
        src_filename IN VARCHAR2,
        dest_location IN VARCHAR2,
        dest_filename IN VARCHAR2,
        overwrite IN BOOLEAN DEFAULT FALSE
    ) IS
    BEGIN
        PERFORM sys.ora_utl_file_frename(src_location, src_filename, dest_location, dest_filename, overwrite);
    END;

    PROCEDURE FSEEK(
        file IN OUT  ORA_UTL_FILE_FILE_TYPE,
        absolute_offset IN INTEGER DEFAULT NULL,
        relative_offset IN INTEGER DEFAULT NULL
    ) IS
    BEGIN
        PERFORM sys.ora_utl_file_fseek(file.id, absolute_offset, relative_offset);
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

    PROCEDURE GET_RAW(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer OUT BYTEA,
        len IN INTEGER DEFAULT NULL
    ) IS
    BEGIN
        SELECT * INTO buffer FROM sys.ora_utl_file_get_raw(file.id, len);
    END;

    FUNCTION FGETS(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN OUT VARCHAR2,
        len IN INTEGER DEFAULT NULL
    )
    RETURN BOOLEAN IS
    r sys.ora_utl_file_fgets_result;
    BEGIN
        SELECT * INTO r FROM sys.ora_utl_file_fgets(file.id, len);
        -- At end of file nothing was read: keep the caller's buffer
        -- unchanged, matching Oracle FGETS (which never raises
        -- NO_DATA_FOUND and returns FALSE instead).
        IF r.buffer IS NOT NULL THEN
            buffer := r.buffer;
        END IF;
        -- TRUE means only part of the line was stored (the line is longer
        -- than len / max_linesize); FALSE means a complete line or EOF.
        RETURN r.partial;
    END;

    FUNCTION FGETS_NCHAR(
        file IN ORA_UTL_FILE_FILE_TYPE,
        buffer IN OUT VARCHAR2,
        len IN INTEGER DEFAULT NULL
    )
    RETURN BOOLEAN IS
    r sys.ora_utl_file_fgets_result;
    BEGIN
        SELECT * INTO r FROM sys.ora_utl_file_fgets(file.id, len);
        -- Same rules as FGETS; the buffer is only overwritten when data
        -- was actually read into it.
        IF r.buffer IS NOT NULL THEN
            buffer := r.buffer;
        END IF;
        RETURN r.partial;
    END;

    FUNCTION FGETPOS(
        file IN ORA_UTL_FILE_FILE_TYPE
    )
    RETURN INTEGER IS
    BEGIN
        RETURN sys.ora_utl_file_ftell(file.id);
    END;


    FUNCTION IS_OPEN(
        file IN ORA_UTL_FILE_FILE_TYPE
    )
    RETURN boolean IS
    BEGIN
        RETURN sys.ora_utl_file_is_open(file.id);
    END;

    PROCEDURE NEW_LINE(
        file IN ORA_UTL_FILE_FILE_TYPE,
        lines IN INTEGER DEFAULT 1
    ) IS
    DECLARE
        status BOOLEAN;
    BEGIN
        SELECT sys.ora_utl_file_new_line(file.id, lines) INTO status;
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

    PROCEDURE PUTF(
        file IN ORA_UTL_FILE_FILE_TYPE,
        format IN VARCHAR2,
        arg1 IN VARCHAR2 DEFAULT NULL,
        arg2 IN VARCHAR2 DEFAULT NULL,
        arg3 IN VARCHAR2 DEFAULT NULL,
        arg4 IN VARCHAR2 DEFAULT NULL,
        arg5 IN VARCHAR2 DEFAULT NULL
    ) IS
    DECLARE
        status BOOLEAN;
    BEGIN
        SELECT sys.ora_utl_file_putf(file.id, format, arg1, arg2, arg3, arg4, arg5) INTO status;
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
