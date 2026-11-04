/***************************************************************
 *
 * DBMS_PIPE Package
 *
 * Oracle-compatible inter-session communication using named pipes.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_pipe/dbms_pipe--1.0.sql
 *
 ***************************************************************/

-- Pipe catalog tables
CREATE TABLE IF NOT EXISTS sys.pipe_definitions (
    pipename        varchar2(128) PRIMARY KEY,
    maxsize         integer DEFAULT 4096,
    is_private      boolean DEFAULT false,
    owner           varchar2(128),
    created_time    timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sys.pipe_messages (
    message_id      serial PRIMARY KEY,
    pipename        varchar2(128),
    payload         text,
    sent_time       timestamptz DEFAULT now()
);

-- Internal C resolvers
CREATE FUNCTION sys.dbms_pipe_create_pipe_internal(pipename text,
                                                   maxsize integer,
                                                   is_private boolean)
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_pipe_create_pipe_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_pipe_pack_message_text_internal(item text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_pipe_pack_message_text_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_pipe_unpack_message_text_internal()
RETURNS text
AS 'MODULE_PATHNAME', 'dbms_pipe_unpack_message_text_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_pipe_send_message_internal(pipename text,
                                                    timeout integer,
                                                    maxsize integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_pipe_send_message_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_pipe_receive_message_internal(pipename text,
                                                       timeout integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_pipe_receive_message_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_pipe_reset_buffer_internal()
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_pipe_reset_buffer_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_pipe_purge_internal(pipename text)
RETURNS void
AS 'MODULE_PATHNAME', 'dbms_pipe_purge_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_pipe_remove_pipe_internal(pipename text)
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_pipe_remove_pipe_internal'
LANGUAGE C VOLATILE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_pipe_create_pipe_internal(text, integer, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_pipe_pack_message_text_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_pipe_unpack_message_text_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_pipe_send_message_internal(text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_pipe_receive_message_internal(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_pipe_reset_buffer_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_pipe_purge_internal(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_pipe_remove_pipe_internal(text) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_pipe AS

    -- Status return codes
    success     CONSTANT INTEGER := 0;
    timeout     CONSTANT INTEGER := 1;
    overflow    CONSTANT INTEGER := 2;
    interrupt   CONSTANT INTEGER := 3;

    /*
     * CREATE_PIPE
     * Explicitly creates a public or private named pipe.
     */
    FUNCTION create_pipe(pipename   IN VARCHAR2,
                         maxsize    IN INTEGER DEFAULT 4096,
                         "private"  IN BOOLEAN DEFAULT FALSE) RETURN INTEGER;

    /*
     * PACK_MESSAGE
     * Packs an item into the session's local message buffer.
     */
    PROCEDURE pack_message(item IN VARCHAR2);

    /*
     * UNPACK_MESSAGE
     * Unpacks the next item from the session's message buffer.
     */
    PROCEDURE unpack_message(item OUT VARCHAR2);

    /*
     * SEND_MESSAGE
     * Sends the contents of the session buffer into the specified pipe.
     */
    FUNCTION send_message(pipename IN VARCHAR2,
                          timeout  IN INTEGER DEFAULT 86400000,
                          maxsize  IN INTEGER DEFAULT 4096) RETURN INTEGER;

    /*
     * RECEIVE_MESSAGE
     * Copies a message from the named pipe into the session's unpack buffer.
     */
    FUNCTION receive_message(pipename IN VARCHAR2,
                             timeout  IN INTEGER DEFAULT 86400000) RETURN INTEGER;

    /*
     * RESET_BUFFER
     * Clears both pack and unpack local buffers.
     */
    PROCEDURE reset_buffer;

    /*
     * PURGE
     * Discards all pending messages in the named pipe.
     */
    PROCEDURE purge(pipename IN VARCHAR2);

    /*
     * REMOVE_PIPE
     * Destroys the pipe and removes all pending messages.
     */
    FUNCTION remove_pipe(pipename IN VARCHAR2) RETURN INTEGER;

END dbms_pipe;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_pipe AS

    FUNCTION create_pipe(pipename   IN VARCHAR2,
                         maxsize    IN INTEGER DEFAULT 4096,
                         "private"  IN BOOLEAN DEFAULT FALSE) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_pipe_create_pipe_internal(pipename::text, maxsize, "private");
    END;

    PROCEDURE pack_message(item IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_pipe_pack_message_text_internal(item::text);
    END;

    PROCEDURE unpack_message(item OUT VARCHAR2) IS
        res text;
    BEGIN
        res := sys.dbms_pipe_unpack_message_text_internal();
        item := res::varchar2;
    END;

    FUNCTION send_message(pipename IN VARCHAR2,
                          timeout  IN INTEGER DEFAULT 86400000,
                          maxsize  IN INTEGER DEFAULT 4096) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_pipe_send_message_internal(pipename::text, timeout, maxsize);
    END;

    FUNCTION receive_message(pipename IN VARCHAR2,
                             timeout  IN INTEGER DEFAULT 86400000) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_pipe_receive_message_internal(pipename::text, timeout);
    END;

    PROCEDURE reset_buffer IS
    BEGIN
        PERFORM sys.dbms_pipe_reset_buffer_internal();
    END;

    PROCEDURE purge(pipename IN VARCHAR2) IS
    BEGIN
        PERFORM sys.dbms_pipe_purge_internal(pipename::text);
    END;

    FUNCTION remove_pipe(pipename IN VARCHAR2) RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_pipe_remove_pipe_internal(pipename::text);
    END;

END dbms_pipe;
