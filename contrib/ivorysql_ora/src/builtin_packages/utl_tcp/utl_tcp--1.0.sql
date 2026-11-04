/*-------------------------------------------------------------------------
 * Copyright 2026 IvorySQL Global Development Team
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * utl_tcp--1.0.sql
 *
 * Oracle-compatible UTL_TCP package: a plain, unbuffered outbound TCP
 * client.
 *
 * Coverage.  OPEN_CONNECTION, CLOSE_CONNECTION, CLOSE_ALL_CONNECTIONS,
 * WRITE_TEXT, WRITE_LINE, WRITE_RAW, GET_TEXT, GET_LINE, GET_RAW and FLUSH
 * are implemented.  Oracle argument names, order and defaults are kept,
 * including the parameters whose non-default values are not supported here
 * (local bind address/port, buffer sizes, wallets, peek): the C layer
 * rejects those explicitly instead of silently ignoring them.  Not
 * implemented in this version: AVAILABLE, the READ_* OUT-parameter forms,
 * the NCHAR variants, SECURE_CONNECTION/TLS and I/O buffering.
 *
 * Security.  Oracle gates UTL_TCP behind per-user network ACLs
 * (DBMS_NETWORK_ACL_ADMIN).  IvorySQL has no shared ACL evaluator yet, so
 * this version is deliberately restricted: OPEN_CONNECTION requires a
 * superuser, checked in C before any name resolution or socket activity,
 * and PUBLIC has no EXECUTE privilege on the package or on any
 * sys.ora_utl_tcp_* function.  The package is AUTHID CURRENT_USER, so the
 * body runs with the caller's privileges and a GRANT on the package alone
 * cannot bypass the checks performed in C.  Every handle is owned by the
 * role that opened it and is validated on each call.
 *
 * Deviations from Oracle's declaration on current PL/iSQL:
 *   - PLS_INTEGER is not available as a type; INTEGER (the same 32-bit
 *     signed range) stands in for every PLS_INTEGER field and parameter.
 *   - A package constant cannot be referenced from a parameter DEFAULT
 *     (the default expression is resolved in the caller's scope at call
 *     time), so OPEN_CONNECTION spells its newline default as
 *     CHR(13) || CHR(10), which is the value of UTL_TCP.CRLF.
 *
 * The CONNECTION record is descriptive: private_sd carries an opaque,
 * backend-local handle (never an OS descriptor) and editing the other
 * fields does not change the underlying socket.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_tcp/utl_tcp--1.0.sql
 *
 *-------------------------------------------------------------------------
 */

/*
 * C entry points.  All of them are VOLATILE and none is STRICT: NULL is a
 * meaningful argument value (default charset, timeout, length ...), and
 * every handle-taking function must reject a NULL handle itself instead of
 * silently returning NULL.
 */

-- Returns the opaque handle stored in CONNECTION.private_sd.
CREATE FUNCTION sys.ora_utl_tcp_open_connection(remote_host text,
                                                remote_port integer,
                                                local_host text,
                                                local_port integer,
                                                in_buffer_size integer,
                                                out_buffer_size integer,
                                                charset text,
                                                newline text,
                                                tx_timeout integer,
                                                wallet_path text,
                                                wallet_password text)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_utl_tcp_open_connection'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_tcp_close_connection(sd integer)
RETURNS void
AS 'MODULE_PATHNAME', 'ora_utl_tcp_close_connection'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_tcp_close_all_connections()
RETURNS void
AS 'MODULE_PATHNAME', 'ora_utl_tcp_close_all_connections'
LANGUAGE C VOLATILE;

-- Returns the number of characters transmitted.
CREATE FUNCTION sys.ora_utl_tcp_write_text(sd integer, data text, len integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_utl_tcp_write_text'
LANGUAGE C VOLATILE;

-- Appends the newline sequence given to OPEN_CONNECTION; returns the number
-- of characters transmitted including that newline.
CREATE FUNCTION sys.ora_utl_tcp_write_line(sd integer, data text)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_utl_tcp_write_line'
LANGUAGE C VOLATILE;

-- Returns the number of bytes transmitted.
CREATE FUNCTION sys.ora_utl_tcp_write_raw(sd integer, data bytea, len integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_utl_tcp_write_raw'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_tcp_get_text(sd integer, len integer, peek boolean)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_utl_tcp_get_text'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_tcp_get_line(sd integer, remove_crlf boolean, peek boolean)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_utl_tcp_get_line'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_tcp_get_raw(sd integer, len integer, peek boolean)
RETURNS bytea
AS 'MODULE_PATHNAME', 'ora_utl_tcp_get_raw'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_utl_tcp_flush(sd integer)
RETURNS void
AS 'MODULE_PATHNAME', 'ora_utl_tcp_flush'
LANGUAGE C VOLATILE;

-- UTL_TCP package specification
CREATE OR REPLACE PACKAGE utl_tcp AUTHID CURRENT_USER IS

    /*
     * Oracle's CONNECTION record, same eight fields in the same order.
     * private_sd holds an opaque backend-local handle, never a socket
     * descriptor.
     */
    TYPE connection IS RECORD (
        remote_host VARCHAR2(255),
        remote_port INTEGER,
        local_host  VARCHAR2(255),
        local_port  INTEGER,
        charset     VARCHAR2(30),
        newline     VARCHAR2(2),
        tx_timeout  INTEGER,
        private_sd  INTEGER
    );

    CRLF CONSTANT VARCHAR2(2) := CHR(13) || CHR(10);

    /*
     * OPEN_CONNECTION
     *   remote_host      NULL means the local host.
     *   remote_port      1 .. 65535.
     *   local_host,
     *   local_port       binding to a local address is not supported; any
     *                    non-NULL value is rejected.
     *   in_buffer_size,
     *   out_buffer_size  NULL or 0 select unbuffered I/O (the only mode
     *                    available); positive sizes are rejected.
     *   charset          on-the-wire character set for the text
     *                    operations; NULL means the database encoding.
     *   newline          1 or 2 bytes appended by WRITE_LINE; the default
     *                    is CRLF.
     *   tx_timeout       seconds each read or write may wait; NULL waits
     *                    indefinitely (but interruptibly), 0 never waits.
     *   wallet_path,
     *   wallet_password  TLS is not supported; any non-NULL value is
     *                    rejected.
     * Connecting itself is bounded by a fixed 30 second deadline.
     */
    FUNCTION open_connection(remote_host     IN VARCHAR2,
                             remote_port     IN INTEGER,
                             local_host      IN VARCHAR2 DEFAULT NULL,
                             local_port      IN INTEGER DEFAULT NULL,
                             in_buffer_size  IN INTEGER DEFAULT NULL,
                             out_buffer_size IN INTEGER DEFAULT NULL,
                             charset         IN VARCHAR2 DEFAULT NULL,
                             newline         IN VARCHAR2 DEFAULT CHR(13) || CHR(10),
                             tx_timeout      IN INTEGER DEFAULT NULL,
                             wallet_path     IN VARCHAR2 DEFAULT NULL,
                             wallet_password IN VARCHAR2 DEFAULT NULL)
    RETURN connection;

    -- Closes the connection and clears every field of c.
    PROCEDURE close_connection(c IN OUT NOCOPY connection);

    -- Closes the connections opened by the current role in this backend.
    PROCEDURE close_all_connections;

    -- Output is unbuffered, so this only validates the handle.
    PROCEDURE flush(c IN OUT NOCOPY connection);

    -- Sends len characters of data (all of it when len is NULL); returns
    -- the number of characters transmitted.
    FUNCTION write_text(c    IN OUT NOCOPY connection,
                        data IN VARCHAR2,
                        len  IN INTEGER DEFAULT NULL)
    RETURN INTEGER;

    -- Sends data followed by the connection's newline; returns the number
    -- of characters transmitted, newline included.
    FUNCTION write_line(c    IN OUT NOCOPY connection,
                        data IN VARCHAR2 DEFAULT NULL)
    RETURN INTEGER;

    -- Sends len bytes of data unchanged (all of it when len is NULL);
    -- returns the number of bytes transmitted.
    FUNCTION write_raw(c    IN OUT NOCOPY connection,
                       data IN RAW,
                       len  IN INTEGER DEFAULT NULL)
    RETURN INTEGER;

    -- Reads up to len characters, waiting for them, end of input or the
    -- transfer timeout.  peek = TRUE is not supported.
    FUNCTION get_text(c    IN OUT NOCOPY connection,
                      len  IN INTEGER DEFAULT 1,
                      peek IN BOOLEAN DEFAULT FALSE)
    RETURN VARCHAR2;

    -- Reads one line terminated by LF, CR or CRLF; the terminator is kept
    -- unless remove_crlf is TRUE.  peek = TRUE is not supported.
    FUNCTION get_line(c           IN OUT NOCOPY connection,
                      remove_crlf IN BOOLEAN DEFAULT FALSE,
                      peek        IN BOOLEAN DEFAULT FALSE)
    RETURN VARCHAR2;

    -- Reads up to len bytes.  peek = TRUE is not supported.
    FUNCTION get_raw(c    IN OUT NOCOPY connection,
                     len  IN INTEGER DEFAULT 1,
                     peek IN BOOLEAN DEFAULT FALSE)
    RETURN RAW;

END utl_tcp;

-- UTL_TCP package body: every subprogram is a thin wrapper that hands the
-- opaque handle to C; authorization and validation happen there.
CREATE OR REPLACE PACKAGE BODY utl_tcp IS

    FUNCTION open_connection(remote_host     IN VARCHAR2,
                             remote_port     IN INTEGER,
                             local_host      IN VARCHAR2 DEFAULT NULL,
                             local_port      IN INTEGER DEFAULT NULL,
                             in_buffer_size  IN INTEGER DEFAULT NULL,
                             out_buffer_size IN INTEGER DEFAULT NULL,
                             charset         IN VARCHAR2 DEFAULT NULL,
                             newline         IN VARCHAR2 DEFAULT CHR(13) || CHR(10),
                             tx_timeout      IN INTEGER DEFAULT NULL,
                             wallet_path     IN VARCHAR2 DEFAULT NULL,
                             wallet_password IN VARCHAR2 DEFAULT NULL)
    RETURN connection IS
        c connection;
    BEGIN
        -- Fill the descriptive fields first so that a value that does not
        -- fit the record fails before any socket is opened.
        c.remote_host := remote_host;
        c.remote_port := remote_port;
        c.local_host := local_host;
        c.local_port := local_port;
        c.charset := charset;
        c.newline := newline;
        c.tx_timeout := tx_timeout;
        c.private_sd := sys.ora_utl_tcp_open_connection(remote_host,
                                                        remote_port,
                                                        local_host,
                                                        local_port,
                                                        in_buffer_size,
                                                        out_buffer_size,
                                                        charset,
                                                        newline,
                                                        tx_timeout,
                                                        wallet_path,
                                                        wallet_password);
        RETURN c;
    END;

    PROCEDURE close_connection(c IN OUT NOCOPY connection) IS
    BEGIN
        PERFORM sys.ora_utl_tcp_close_connection(c.private_sd);
        c.remote_host := NULL;
        c.remote_port := NULL;
        c.local_host := NULL;
        c.local_port := NULL;
        c.charset := NULL;
        c.newline := NULL;
        c.tx_timeout := NULL;
        c.private_sd := NULL;
    END;

    PROCEDURE close_all_connections IS
    BEGIN
        PERFORM sys.ora_utl_tcp_close_all_connections();
    END;

    PROCEDURE flush(c IN OUT NOCOPY connection) IS
    BEGIN
        PERFORM sys.ora_utl_tcp_flush(c.private_sd);
    END;

    FUNCTION write_text(c    IN OUT NOCOPY connection,
                        data IN VARCHAR2,
                        len  IN INTEGER DEFAULT NULL)
    RETURN INTEGER IS
    BEGIN
        RETURN sys.ora_utl_tcp_write_text(c.private_sd, data, len);
    END;

    FUNCTION write_line(c    IN OUT NOCOPY connection,
                        data IN VARCHAR2 DEFAULT NULL)
    RETURN INTEGER IS
    BEGIN
        RETURN sys.ora_utl_tcp_write_line(c.private_sd, data);
    END;

    FUNCTION write_raw(c    IN OUT NOCOPY connection,
                       data IN RAW,
                       len  IN INTEGER DEFAULT NULL)
    RETURN INTEGER IS
    BEGIN
        RETURN sys.ora_utl_tcp_write_raw(c.private_sd, data, len);
    END;

    FUNCTION get_text(c    IN OUT NOCOPY connection,
                      len  IN INTEGER DEFAULT 1,
                      peek IN BOOLEAN DEFAULT FALSE)
    RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.ora_utl_tcp_get_text(c.private_sd, len, peek);
    END;

    FUNCTION get_line(c           IN OUT NOCOPY connection,
                      remove_crlf IN BOOLEAN DEFAULT FALSE,
                      peek        IN BOOLEAN DEFAULT FALSE)
    RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.ora_utl_tcp_get_line(c.private_sd, remove_crlf, peek);
    END;

    FUNCTION get_raw(c    IN OUT NOCOPY connection,
                     len  IN INTEGER DEFAULT 1,
                     peek IN BOOLEAN DEFAULT FALSE)
    RETURN RAW IS
    BEGIN
        RETURN sys.ora_utl_tcp_get_raw(c.private_sd, len, peek);
    END;

END utl_tcp;

/*
 * Temporary privilege policy (until a shared network ACL evaluator exists):
 * nothing here is executable by PUBLIC.  Plain functions grant EXECUTE to
 * PUBLIC by default, so every C entry point is revoked individually; the
 * package revocation is explicit even though packages start without PUBLIC
 * privileges.  The C code still requires a superuser to open a connection,
 * so a direct GRANT on a wrapper does not open the network to other roles.
 */
REVOKE ALL ON FUNCTION sys.ora_utl_tcp_open_connection(text, integer, text, integer, integer, integer, text, text, integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.ora_utl_tcp_close_connection(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.ora_utl_tcp_close_all_connections() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.ora_utl_tcp_write_text(integer, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.ora_utl_tcp_write_line(integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.ora_utl_tcp_write_raw(integer, bytea, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.ora_utl_tcp_get_text(integer, integer, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.ora_utl_tcp_get_line(integer, boolean, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.ora_utl_tcp_get_raw(integer, integer, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.ora_utl_tcp_flush(integer) FROM PUBLIC;
REVOKE ALL ON PACKAGE utl_tcp FROM PUBLIC;
