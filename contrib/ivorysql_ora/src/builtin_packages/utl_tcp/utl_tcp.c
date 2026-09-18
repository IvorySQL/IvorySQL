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
 * utl_tcp.c
 *
 * C implementation of the Oracle-compatible UTL_TCP package: a bounded,
 * per-backend registry of plain outbound TCP sockets addressed through
 * opaque integer handles.
 *
 * Design notes:
 *
 * Registry.  Every live connection occupies one slot of a fixed
 * backend-local array (at most UTL_TCP_MAX_CONNECTIONS live sockets).  A
 * slot stores the pgsocket, a monotonic handle value that is never reused
 * within the backend's lifetime, the Oid of the role that opened the
 * connection, the on-the-wire encoding, the newline sequence registered
 * at open time (converted to the wire encoding and validated before any
 * resource is allocated), the transfer timeout and a bounded ordered
 * receive buffer for text and raw reads.  Connections deliberately
 * outlive transactions; a before_shmem_exit hook closes whatever is
 * still open when the backend ends.  Statements that fail after a socket
 * was created leave no leaked descriptor: OPEN closes a not-yet-
 * registered socket on any error path, and sockets that are already
 * registered survive statement errors.
 *
 * Authorization.  OPEN_CONNECTION requires a superuser, checked before any
 * name resolution or socket activity; this is a temporary release
 * condition until a shared invoking-user host/port ACL check exists.
 * Every handle-taking entry point re-validates the handle and requires
 * that the current effective user (GetUserId(), i.e. after SET ROLE) still
 * owns the connection, so a copied CONNECTION record grants no rights and
 * a directly GRANTed C function is still useless to a non-superuser.
 *
 * I/O.  Sockets are nonblocking.  A connect has a fixed 30 second
 * deadline that starts after address resolution; completion is verified
 * with SO_ERROR after the writable wait.  (The DNS phase uses the system
 * resolver and is not bounded by, or cancellable through, this deadline.)
 * The transfer timeout given at open time bounds each read or write
 * operation as a whole: -1 (NULL) waits indefinitely but interruptibly, 0
 * never waits (a single nonblocking receive is still attempted for bytes
 * that have already arrived), a positive value bounds the operation.
 * All waits go through WaitLatchOrSocket so that backend cancellation
 * and postmaster death are handled.  Partial send/recv, EINTR and
 * would-block are handled explicitly.
 *
 * Text conversion.  A NULL charset means the database encoding; an
 * explicit charset is resolved with pg_char_to_encoding and rejected if no
 * conversion to or from the database encoding exists.  Text lengths count
 * characters and raw lengths count bytes; multibyte characters are never
 * split.  Incomplete trailing bytes stay buffered until they form a
 * complete character; an incomplete final character at end of input
 * follows Oracle's PARTIAL_MULTIBYTE_CHAR rule.  At a transfer timeout,
 * GET_TEXT and GET_LINE follow Oracle's READ_TEXT/READ_LINE rules: while
 * a character is only partly received, TRANSFER_TIMEOUT is raised and
 * everything stays buffered for a retry; otherwise the text read so far
 * is returned.
 *
 * Error mapping (Oracle exception -> SQLSTATE):
 *   BAD_ARGUMENT           -> 22023 invalid_parameter_value
 *   NETWORK_ACCESS_DENIED  -> 42501 insufficient_privilege
 *   (invalid handle)       -> 08003 connection_does_not_exist
 *   NETWORK_ERROR (open)   -> 08001 sqlclient_unable_to_establish_sqlconnection
 *   NETWORK_ERROR (I/O)    -> 08006 connection_failure
 *   TRANSFER_TIMEOUT       -> 08006 connection_failure
 *   END_OF_INPUT           -> P0002 no_data_found
 *   PARTIAL_MULTIBYTE_CHAR -> 22021 character_not_in_repertoire
 *   (SQL value overflow)   -> 54000 program_limit_exceeded
 *   (unsupported option)   -> 0A000 feature_not_supported
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_tcp/utl_tcp.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <limits.h>
#include <sys/socket.h>
#include <netdb.h>
#include <netinet/in.h>
#include <unistd.h>

#include "catalog/namespace.h"
#include "common/ip.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "storage/ipc.h"
#include "storage/latch.h"
#include "utils/builtins.h"
#include "utils/memutils.h"
#include "utils/timestamp.h"
#include "utils/wait_event.h"
#include "varatt.h"

PG_FUNCTION_INFO_V1(ora_utl_tcp_open_connection);
PG_FUNCTION_INFO_V1(ora_utl_tcp_close_connection);
PG_FUNCTION_INFO_V1(ora_utl_tcp_close_all_connections);
PG_FUNCTION_INFO_V1(ora_utl_tcp_write_text);
PG_FUNCTION_INFO_V1(ora_utl_tcp_write_line);
PG_FUNCTION_INFO_V1(ora_utl_tcp_write_raw);
PG_FUNCTION_INFO_V1(ora_utl_tcp_get_text);
PG_FUNCTION_INFO_V1(ora_utl_tcp_get_line);
PG_FUNCTION_INFO_V1(ora_utl_tcp_get_raw);
PG_FUNCTION_INFO_V1(ora_utl_tcp_flush);

/* ---------------------------------------------------------------------
 * Constants
 * ---------------------------------------------------------------------
 */

/* Oracle allows 50 open connections per session */
#define UTL_TCP_MAX_CONNECTIONS		50

/* handle 0 marks a free slot; valid handles are positive */
#define UTL_TCP_HANDLE_FREE		0

/* documented deadline for the whole connect sequence */
#define UTL_TCP_CONNECT_TIMEOUT_MS	(30 * 1000)

/* Oracle's VARCHAR2/RAW SQL value limit */
#define UTL_TCP_MAX_VALUE_BYTES		32767

/* how much one recv() call may pull into the receive buffer */
#define UTL_TCP_RECV_CHUNK			8192

/* CRLF, the default newline sequence */
#define UTL_TCP_DEFAULT_NEWLINE		"\r\n"

/* ---------------------------------------------------------------------
 * Registry
 * ---------------------------------------------------------------------
 */

typedef struct UtlTcpConnection
{
	int32		handle;			/* opaque handle; 0 when the slot is free */
	pgsocket	sock;
	Oid			owner;			/* GetUserId() at open time */
	int			encoding;		/* on-the-wire encoding */
	char		newline[2];		/* newline sequence used by WRITE_LINE */
	int			newline_len;	/* 1 or 2 bytes */
	int			timeout_ms;		/* per operation: <0 infinite, 0 none, >0 bound */
	bool		eof;			/* peer closed; no further input will arrive */
	bool		pending_lf;		/* GET_LINE returned a lone CR; swallow a
								 * following LF as the same terminator */
	StringInfoData rxbuf;		/* ordered, not yet consumed input */
} UtlTcpConnection;

static UtlTcpConnection connections[UTL_TCP_MAX_CONNECTIONS];

static int32 next_handle = UTL_TCP_HANDLE_FREE;

static bool exit_hook_registered = false;

/* lazily allocated named wait event for WaitLatchOrSocket */
static uint32 utl_tcp_wait_event = 0;

/* result of one receive attempt */
typedef enum
{
	UTL_TCP_FILL_DATA,			/* new bytes were appended */
	UTL_TCP_FILL_EOF,			/* peer closed; buffer holds the tail */
	UTL_TCP_FILL_TIMEOUT,		/* deadline passed with the socket idle */
} UtlTcpFillResult;

/* ---------------------------------------------------------------------
 * Error helpers
 * ---------------------------------------------------------------------
 */

#define UTL_TCP_BAD_ARGUMENT(msg) \
	ereport(ERROR, \
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE), \
			 errmsg(msg)))

#define UTL_TCP_BAD_ARGUMENT_DETAIL(msg, detail) \
	ereport(ERROR, \
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE), \
			 errmsg(msg), \
			 errdetail("%s", detail)))

#define UTL_TCP_FEATURE(msg) \
	ereport(ERROR, \
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED), \
			 errmsg(msg)))

#define UTL_TCP_PROGRAM_LIMIT(msg) \
	ereport(ERROR, \
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED), \
			 errmsg(msg)))

#define UTL_TCP_END_OF_INPUT() \
	ereport(ERROR, \
			(errcode(ERRCODE_NO_DATA_FOUND), \
			 errmsg("UTL_TCP: end of input")))

#define UTL_TCP_PARTIAL_MULTIBYTE() \
	ereport(ERROR, \
			(errcode(ERRCODE_CHARACTER_NOT_IN_REPERTOIRE), \
			 errmsg("UTL_TCP: incomplete multibyte character at end of input")))

#define UTL_TCP_HANDLE_ERROR() \
	ereport(ERROR, \
			(errcode(ERRCODE_CONNECTION_DOES_NOT_EXIST), \
			 errmsg("invalid UTL_TCP connection handle"), \
			 errdetail("The handle does not refer to a connection opened " \
					   "by the current role in this backend.")))

/* ---------------------------------------------------------------------
 * Registry internals
 * ---------------------------------------------------------------------
 */

/*
 * Allocate the next handle value.  Handles increase monotonically and are
 * never reused; if the counter would wrap, the backend has to be
 * restarted (unreachable in practice).
 */
static int32
utl_tcp_next_handle(void)
{
	if (next_handle == PG_INT32_MAX)
		UTL_TCP_PROGRAM_LIMIT("UTL_TCP: connection handles exhausted in this backend");

	return ++next_handle;
}

/*
 * Find a free slot, or return NULL if UTL_TCP_MAX_CONNECTIONS connections
 * are already open.
 */
static UtlTcpConnection *
utl_tcp_free_slot(void)
{
	for (int i = 0; i < UTL_TCP_MAX_CONNECTIONS; i++)
	{
		if (connections[i].handle == UTL_TCP_HANDLE_FREE)
			return &connections[i];
	}

	return NULL;
}

/*
 * Look up a live connection by handle and require that the current
 * effective user still owns it.  A nonexistent and a foreign handle are
 * reported identically.
 */
static UtlTcpConnection *
utl_tcp_lookup(int32 handle)
{
	if (handle != UTL_TCP_HANDLE_FREE)
	{
		for (int i = 0; i < UTL_TCP_MAX_CONNECTIONS; i++)
		{
			UtlTcpConnection *conn = &connections[i];

			if (conn->handle == handle)
			{
				if (conn->owner != GetUserId())
					UTL_TCP_HANDLE_ERROR();

				return conn;
			}
		}
	}

	UTL_TCP_HANDLE_ERROR();
	return NULL;				/* keep the compiler quiet */
}

/* Release a slot and its resources; the caller closes the socket. */
static void
utl_tcp_release(UtlTcpConnection *conn)
{
	if (conn->rxbuf.data != NULL)
		pfree(conn->rxbuf.data);

	MemSet(conn, 0, sizeof(*conn));
}

/*
 * before_shmem_exit hook: close whatever the backend still has open.
 */
static void
utl_tcp_exit_hook(int code, Datum arg)
{
	for (int i = 0; i < UTL_TCP_MAX_CONNECTIONS; i++)
	{
		UtlTcpConnection *conn = &connections[i];

		if (conn->handle != UTL_TCP_HANDLE_FREE)
		{
			closesocket(conn->sock);
			utl_tcp_release(conn);
		}
	}
}

/* ---------------------------------------------------------------------
 * Socket helpers
 * ---------------------------------------------------------------------
 */

static uint32
utl_tcp_we(void)
{
	if (utl_tcp_wait_event == 0)
		utl_tcp_wait_event = WaitEventExtensionNew("UtlTcpIo");

	return utl_tcp_wait_event;
}

/*
 * Fetch the pending socket error after a nonblocking connect, ready to be
 * reported through errno and %m.  Returns 0 when the connect succeeded.
 */
static int
utl_tcp_so_error(pgsocket sock)
{
	int			optval = 0;
	socklen_t	optlen = sizeof(optval);

	if (getsockopt(sock, SOL_SOCKET, SO_ERROR, (char *) &optval, &optlen) < 0)
	{
#ifdef WIN32
		return WSAGetLastError();
#else
		return errno;
#endif
	}

	/*
	 * SO_ERROR carries a Winsock code on Windows, and PostgreSQL's
	 * strerror() understands Winsock codes, so both platforms can simply
	 * assign the value to errno for reporting.
	 */
	return optval;
}

/*
 * The operation deadline for conn: 0 when the operation waits
 * indefinitely, otherwise now + the configured transfer timeout.  A zero
 * timeout therefore produces a deadline that has already passed, i.e. the
 * operation never waits.
 */
static TimestampTz
utl_tcp_deadline(UtlTcpConnection *conn)
{
	if (conn->timeout_ms < 0)
		return 0;

	return TimestampTzPlusMilliseconds(GetCurrentTimestamp(),
									   conn->timeout_ms);
}

/*
 * Wait until the socket is ready for the requested event.  Returns false
 * when the operation's deadline passed while the socket stayed idle; the
 * caller decides whether that is fatal or returns partial data.
 */
static bool
utl_tcp_wait(UtlTcpConnection *conn, int waitfor, TimestampTz deadline_us)
{
	for (;;)
	{
		long		timeout_ms;
		int			wakeevents;
		int			rc;

		if (deadline_us == 0)
		{
			/*
			 * Wait indefinitely (but interruptibly): no WL_TIMEOUT, so the
			 * timeout argument is ignored.
			 */
			timeout_ms = -1;
			wakeevents = waitfor | WL_LATCH_SET | WL_EXIT_ON_PM_DEATH;
		}
		else
		{
			timeout_ms = TimestampDifferenceMilliseconds(GetCurrentTimestamp(),
														 deadline_us);
			if (timeout_ms <= 0)
				return false;

			wakeevents = waitfor | WL_LATCH_SET | WL_TIMEOUT |
				WL_EXIT_ON_PM_DEATH;
		}

		rc = WaitLatchOrSocket(MyLatch,
							   wakeevents,
							   conn->sock,
							   timeout_ms,
							   utl_tcp_we());

		if (rc & WL_SOCKET_MASK)
			return true;

		if (rc & WL_LATCH_SET)
		{
			ResetLatch(MyLatch);
			CHECK_FOR_INTERRUPTS();
		}

		/*
		 * WL_TIMEOUT only means this particular wait ran out; the next
		 * iteration rechecks the operation deadline.
		 */
	}
}

/*
 * Send len bytes, handling short writes, EINTR and would-block.
 */
static void
utl_tcp_send_all(UtlTcpConnection *conn, const char *buf, size_t len,
				 TimestampTz deadline_us)
{
	while (len > 0)
	{
		ssize_t		n;

		CHECK_FOR_INTERRUPTS();

		n = send(conn->sock, buf, len, 0);

		if (n > 0)
		{
			buf += n;
			len -= n;
			continue;
		}

		if (n == 0)
			ereport(ERROR,
					(errcode(ERRCODE_CONNECTION_FAILURE),
					 errmsg("UTL_TCP: could not send data: connection closed")));

		if (errno == EINTR)
			continue;

		if (errno == EWOULDBLOCK || errno == EAGAIN)
		{
			if (!utl_tcp_wait(conn, WL_SOCKET_WRITEABLE, deadline_us))
				ereport(ERROR,
						(errcode(ERRCODE_CONNECTION_FAILURE),
						 errmsg("UTL_TCP: transfer timed out after %d seconds",
								conn->timeout_ms / 1000)));
			continue;
		}

		ereport(ERROR,
				(errcode(ERRCODE_CONNECTION_FAILURE),
				 errmsg("UTL_TCP: could not send data: %m")));
	}
}

/*
 * Pull one recv() worth of data into the receive buffer.
 */
static UtlTcpFillResult
utl_tcp_fill(UtlTcpConnection *conn, TimestampTz deadline_us)
{
	char		chunk[UTL_TCP_RECV_CHUNK];

	for (;;)
	{
		ssize_t		n;

		CHECK_FOR_INTERRUPTS();

#ifdef WIN32
		pgwin32_noblock = true;
#endif
		n = recv(conn->sock, chunk, sizeof(chunk), 0);
#ifdef WIN32
		pgwin32_noblock = false;
#endif

		if (n > 0)
		{
			appendBinaryStringInfo(&conn->rxbuf, chunk, (int) n);
			return UTL_TCP_FILL_DATA;
		}

		if (n == 0)
		{
			conn->eof = true;
			return UTL_TCP_FILL_EOF;
		}

		if (errno == EINTR)
			continue;

		if (errno == EWOULDBLOCK || errno == EAGAIN)
		{
			if (!utl_tcp_wait(conn, WL_SOCKET_READABLE, deadline_us))
				return UTL_TCP_FILL_TIMEOUT;
			continue;
		}

		ereport(ERROR,
				(errcode(ERRCODE_CONNECTION_FAILURE),
				 errmsg("UTL_TCP: could not receive data: %m")));
	}
}

/*
 * Return the length in bytes of the character at the given offset in the
 * receive buffer, or 0 when more input is required first (*incomplete) or
 * the buffered bytes do not form a valid character (*invalid).
 */
static int
utl_tcp_char_len(UtlTcpConnection *conn, int offset,
				 bool *incomplete, bool *invalid)
{
	int			remaining = conn->rxbuf.len - offset;
	int			expected;

	*incomplete = false;
	*invalid = false;

	if (remaining <= 0)
	{
		*incomplete = true;
		return 0;
	}

	expected = pg_encoding_mblen_or_incomplete(conn->encoding,
											   conn->rxbuf.data + offset,
											   (size_t) remaining);

	if (expected == INT_MAX || expected > remaining)
	{
		*incomplete = true;
		return 0;
	}

	if (pg_encoding_verifymbchar(conn->encoding, conn->rxbuf.data + offset,
								 remaining) <= 0)
	{
		*invalid = true;
		return 0;
	}

	return expected;
}

/*
 * Return the buffer offset of the character with the given 0-based index
 * among the first limit bytes.  The caller guarantees that those bytes
 * form complete characters.
 */
static int
utl_tcp_char_offset(UtlTcpConnection *conn, int limit, int char_idx)
{
	int			off = 0;

	while (char_idx-- > 0)
	{
		int			clen = pg_encoding_mblen_or_incomplete(conn->encoding,
														   conn->rxbuf.data + off,
														   (size_t) (limit - off));

		Assert(clen != INT_MAX && clen > 0 && clen <= limit - off);
		off += clen;
	}

	return off;
}

/* Drop n consumed bytes from the front of the receive buffer. */
static void
utl_tcp_consume(UtlTcpConnection *conn, int n)
{
	Assert(n >= 0 && n <= conn->rxbuf.len);

	if (n > 0)
	{
		memmove(conn->rxbuf.data, conn->rxbuf.data + n, conn->rxbuf.len - n);
		conn->rxbuf.len -= n;
		conn->rxbuf.data[conn->rxbuf.len] = '\0';
	}
}

/*
 * True when the receive buffer holds at least one complete character and
 * ends on a character boundary, i.e. GET_LINE may return it as a partial
 * line when the transfer times out.
 */
static bool
utl_tcp_complete_chars_only(UtlTcpConnection *conn)
{
	int			off = 0;

	if (conn->rxbuf.len == 0)
		return false;

	while (off < conn->rxbuf.len)
	{
		bool		incomplete;
		bool		invalid;
		int			clen;

		clen = utl_tcp_char_len(conn, off, &incomplete, &invalid);

		if (incomplete)
			return false;	/* a trailing character is only partly here */

		if (invalid)
			return true;	/* invalid bytes are reported on conversion */

		off += clen;
	}

	return true;
}

/* ---------------------------------------------------------------------
 * Validation helpers for OPEN_CONNECTION
 * ---------------------------------------------------------------------
 */

static void
utl_tcp_validate_port(int port, const char *what)
{
	if (port < 1 || port > 65535)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_TCP: %s must be between 1 and 65535", what)));
}

static int
utl_tcp_resolve_charset(text *charset)
{
	int			encoding;

	encoding = pg_char_to_encoding(text_to_cstring(charset));
	if (encoding < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_TCP: unknown character set name \"%s\"",
						text_to_cstring(charset))));

	/*
	 * Reject charsets that cannot be converted to or from the database
	 * encoding; otherwise the mismatch would only surface on the first
	 * text operation.
	 */
	if (encoding != GetDatabaseEncoding() &&
		encoding != PG_SQL_ASCII &&
		GetDatabaseEncoding() != PG_SQL_ASCII)
	{
		if (!OidIsValid(FindDefaultConversionProc(GetDatabaseEncoding(),
												  encoding)) ||
			!OidIsValid(FindDefaultConversionProc(encoding,
												  GetDatabaseEncoding())))
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_TCP: no conversion between character set \"%s\" and the database encoding",
							text_to_cstring(charset))));
	}

	return encoding;
}

/*
 * Convert the newline sequence from the database encoding to the wire
 * encoding and validate the result: 1..2 bytes forming whole characters.
 * An unconvertible character raises an error here, before the caller has
 * allocated any socket or registry slot, and WRITE_LINE later sends the
 * bytes the peer expects instead of database-encoded bytes.
 */
static const char *
utl_tcp_convert_newline(const char *nl, int len, int wire_encoding,
						int *wire_len)
{
	const char *converted;
	const char *p;
	int			rem;

	if (len < 1)
		UTL_TCP_BAD_ARGUMENT("UTL_TCP: newline must be 1 or 2 bytes long");

	converted = (const char *) pg_do_encoding_conversion((unsigned char *) nl,
														 len,
														 GetDatabaseEncoding(),
														 wire_encoding);

	if (converted == nl)
		*wire_len = len;
	else
		*wire_len = strlen(converted);

	if (*wire_len < 1 || *wire_len > 2)
		UTL_TCP_BAD_ARGUMENT("UTL_TCP: newline must be 1 or 2 bytes long");

	/* the converted bytes must form whole characters */
	p = converted;
	rem = *wire_len;
	while (rem > 0)
	{
		int			clen = pg_encoding_mblen(wire_encoding, p);

		if (clen > rem)
			UTL_TCP_BAD_ARGUMENT_DETAIL("UTL_TCP: newline must not split a character",
										"the newline ends mid-character in the wire encoding");
		p += clen;
		rem -= clen;
	}

	return converted;
}

/* ---------------------------------------------------------------------
 * C entry points
 * ---------------------------------------------------------------------
 */

/*
 * sys.ora_utl_tcp_open_connection(remote_host, remote_port, local_host,
 *			local_port, in_buffer_size, out_buffer_size, charset,
 *			newline, tx_timeout, wallet_path, wallet_password)
 *
 * Returns the opaque handle to store in CONNECTION.private_sd.
 *
 * Not STRICT on purpose: NULL has defined meaning for most arguments
 * (local host, database encoding, indefinite timeout).  Authorization
 * happens before any name resolution or socket activity.
 */
Datum
ora_utl_tcp_open_connection(PG_FUNCTION_ARGS)
{
	const char *hostname = NULL;
	int			remote_port;
	int			encoding;
	const char *newline;
	int			newline_len;
	int			timeout_ms;
	struct addrinfo hint;
	struct addrinfo *volatile addrs = NULL;
	volatile pgsocket sock = PGINVALID_SOCKET;
	char	   *servname;
	UtlTcpConnection *conn;
	TimestampTz deadline;
	int			first_errno = 0;

	/*
	 * Temporary security policy: only superusers may open outbound TCP
	 * connections.  This is checked before any DNS or socket activity.
	 */
	if (!superuser())
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 errmsg("permission denied to open a UTL_TCP connection"),
				 errdetail("Only superusers can open outbound TCP connections "
						   "while network ACL support is not available.")));

	/* remote_host: NULL means the local host */
	if (!PG_ARGISNULL(0))
		hostname = text_to_cstring(PG_GETARG_TEXT_PP(0));

	if (PG_ARGISNULL(1))
		UTL_TCP_BAD_ARGUMENT("UTL_TCP: remote_port must not be NULL");
	remote_port = PG_GETARG_INT32(1);
	utl_tcp_validate_port(remote_port, "remote_port");

	/* local bind options: supported only as NULL (reject non-defaults) */
	if (!PG_ARGISNULL(2))
		UTL_TCP_FEATURE("UTL_TCP: binding to a local host is not supported");
	if (!PG_ARGISNULL(3))
		UTL_TCP_FEATURE("UTL_TCP: binding to a local port is not supported");

	/*
	 * Buffer sizes: NULL or 0 select the only mode available, unbuffered;
	 * negative sizes are invalid arguments.
	 */
	if (!PG_ARGISNULL(4))
	{
		int32		in_buffer_size = PG_GETARG_INT32(4);

		if (in_buffer_size < 0)
			UTL_TCP_BAD_ARGUMENT("UTL_TCP: in_buffer_size must not be negative");
		if (in_buffer_size > 0)
			UTL_TCP_FEATURE("UTL_TCP: a positive in_buffer_size is not supported; I/O is unbuffered");
	}
	if (!PG_ARGISNULL(5))
	{
		int32		out_buffer_size = PG_GETARG_INT32(5);

		if (out_buffer_size < 0)
			UTL_TCP_BAD_ARGUMENT("UTL_TCP: out_buffer_size must not be negative");
		if (out_buffer_size > 0)
			UTL_TCP_FEATURE("UTL_TCP: a positive out_buffer_size is not supported; I/O is unbuffered");
	}

	/* charset: NULL means the database encoding */
	if (!PG_ARGISNULL(6))
		encoding = utl_tcp_resolve_charset(PG_GETARG_TEXT_PP(6));
	else
		encoding = GetDatabaseEncoding();

	/*
	 * newline: NULL behaves like the SQL default.  Convert the sequence to
	 * the wire encoding now, so that an unconvertible or overlong value is
	 * rejected before any connection resource is allocated, and so that
	 * WRITE_LINE sends the bytes the peer expects.
	 */
	if (!PG_ARGISNULL(7))
	{
		text	   *nl = PG_GETARG_TEXT_PP(7);

		newline = utl_tcp_convert_newline(VARDATA_ANY(nl),
										  VARSIZE_ANY_EXHDR(nl),
										  encoding,
										  &newline_len);
	}
	else
	{
		newline = UTL_TCP_DEFAULT_NEWLINE;
		newline_len = strlen(UTL_TCP_DEFAULT_NEWLINE);
	}

	/* tx_timeout: NULL waits indefinitely, 0 never waits, else seconds */
	if (PG_ARGISNULL(8))
		timeout_ms = -1;
	else
	{
		int32		tx_timeout = PG_GETARG_INT32(8);

		if (tx_timeout < 0)
			UTL_TCP_BAD_ARGUMENT("UTL_TCP: tx_timeout must not be negative");

		timeout_ms = (tx_timeout > INT_MAX / 1000) ? INT_MAX : tx_timeout * 1000;
	}

	/* wallet options: TLS is not supported */
	if (!PG_ARGISNULL(9))
		UTL_TCP_FEATURE("UTL_TCP: wallet_path is not supported (no TLS)");
	if (!PG_ARGISNULL(10))
		UTL_TCP_FEATURE("UTL_TCP: wallet_password is not supported (no TLS)");

	/* ---- resolve ---- */
	MemSet(&hint, 0, sizeof(hint));
	hint.ai_family = AF_UNSPEC;
	hint.ai_socktype = SOCK_STREAM;

	servname = psprintf("%d", remote_port);

	PG_TRY();
	{
		struct addrinfo *resolved = NULL;
		int			rc;

		rc = pg_getaddrinfo_all(hostname, servname, &hint, &resolved);
		if (rc != 0)
			ereport(ERROR,
					(errcode(ERRCODE_SQLCLIENT_UNABLE_TO_ESTABLISH_SQLCONNECTION),
					 errmsg("UTL_TCP: could not translate host name \"%s\" to address: %s",
							hostname ? hostname : "(local)",
							gai_strerror(rc))));
		addrs = resolved;

		/* ---- connect, bounded by a fixed overall deadline ---- */
		deadline = TimestampTzPlusMilliseconds(GetCurrentTimestamp(),
											   UTL_TCP_CONNECT_TIMEOUT_MS);

		for (struct addrinfo *addr = addrs; addr != NULL; addr = addr->ai_next)
		{
			bool		connected = false;

			sock = socket(addr->ai_family, addr->ai_socktype,
						  addr->ai_protocol);
			if (sock == PGINVALID_SOCKET)
			{
				if (first_errno == 0)
					first_errno = errno;
				continue;
			}

			if (!pg_set_noblock(sock))
			{
				if (first_errno == 0)
					first_errno = errno;
				closesocket(sock);
				sock = PGINVALID_SOCKET;
				continue;
			}

			errno = 0;
			if (connect(sock, addr->ai_addr, addr->ai_addrlen) == 0)
			{
				connected = true;
			}
			else if (errno == EINPROGRESS || errno == EWOULDBLOCK)
			{
				/*
				 * Wait for connect completion and verify it with
				 * SO_ERROR, until the overall deadline runs out.
				 */
				while (!connected)
				{
					long		left_ms;
					int			waitrc;
					int			soerr;

					left_ms = TimestampDifferenceMilliseconds(GetCurrentTimestamp(),
															  deadline);
					if (left_ms <= 0)
						break;

					waitrc = WaitLatchOrSocket(MyLatch,
											   WL_SOCKET_WRITEABLE |
											   WL_LATCH_SET | WL_TIMEOUT |
											   WL_EXIT_ON_PM_DEATH,
											   sock,
											   left_ms,
											   utl_tcp_we());

					if (waitrc & WL_LATCH_SET)
					{
						ResetLatch(MyLatch);
						CHECK_FOR_INTERRUPTS();
						continue;
					}

					if (waitrc & WL_SOCKET_WRITEABLE)
					{
						soerr = utl_tcp_so_error(sock);
						if (soerr != 0)
						{
							if (first_errno == 0)
								first_errno = soerr;
							break;
						}
						connected = true;
					}

					/* WL_TIMEOUT: loop and recheck the deadline */
				}
			}
			else
			{
				if (first_errno == 0)
					first_errno = errno;
			}

			if (connected)
				break;

			closesocket(sock);
			sock = PGINVALID_SOCKET;
		}

		pg_freeaddrinfo_all(hint.ai_family, addrs);
		addrs = NULL;

		if (sock == PGINVALID_SOCKET)
		{
			if (first_errno == 0 &&
				TimestampDifferenceMilliseconds(GetCurrentTimestamp(),
												deadline) <= 0)
				ereport(ERROR,
						(errcode(ERRCODE_SQLCLIENT_UNABLE_TO_ESTABLISH_SQLCONNECTION),
						 errmsg("UTL_TCP: could not connect to \"%s\" port %d: connect timed out after %d seconds",
								hostname ? hostname : "(local)",
								remote_port,
								UTL_TCP_CONNECT_TIMEOUT_MS / 1000)));

			if (first_errno == 0)
				first_errno = ENOENT;	/* no address could be tried */

			errno = first_errno;
			ereport(ERROR,
					(errcode(ERRCODE_SQLCLIENT_UNABLE_TO_ESTABLISH_SQLCONNECTION),
					 errmsg("UTL_TCP: could not connect to \"%s\" port %d: %m",
							hostname ? hostname : "(local)",
							remote_port)));
		}
	}
	PG_CATCH();
	{
		/* a socket that is not registered yet must not leak */
		if (sock != PGINVALID_SOCKET)
			closesocket(sock);
		if (addrs != NULL)
			pg_freeaddrinfo_all(hint.ai_family, addrs);
		PG_RE_THROW();
	}
	PG_END_TRY();

	/* ---- register ---- */
	conn = utl_tcp_free_slot();
	if (conn == NULL)
	{
		closesocket(sock);
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("UTL_TCP: too many open connections"),
				 errdetail("A backend can have at most %d UTL_TCP connections open at the same time.",
						   UTL_TCP_MAX_CONNECTIONS)));
	}

	MemSet(conn, 0, sizeof(*conn));
	conn->handle = utl_tcp_next_handle();
	conn->sock = sock;
	conn->owner = GetUserId();
	conn->encoding = encoding;
	memcpy(conn->newline, newline, newline_len);
	conn->newline_len = newline_len;
	conn->timeout_ms = timeout_ms;
	conn->eof = false;

	/* the receive buffer must outlive transactions */
	{
		MemoryContext oldcontext = MemoryContextSwitchTo(TopMemoryContext);

		initStringInfo(&conn->rxbuf);
		MemoryContextSwitchTo(oldcontext);
	}

	if (!exit_hook_registered)
	{
		before_shmem_exit(utl_tcp_exit_hook, 0);
		exit_hook_registered = true;
	}

	PG_RETURN_INT32(conn->handle);
}

/*
 * sys.ora_utl_tcp_close_connection(sd)
 */
Datum
ora_utl_tcp_close_connection(PG_FUNCTION_ARGS)
{
	UtlTcpConnection *conn;

	if (PG_ARGISNULL(0))
		UTL_TCP_HANDLE_ERROR();

	conn = utl_tcp_lookup(PG_GETARG_INT32(0));

	closesocket(conn->sock);
	utl_tcp_release(conn);

	PG_RETURN_VOID();
}

/*
 * sys.ora_utl_tcp_close_all_connections()
 *
 * Closes only the connections owned by the current role in this backend.
 */
Datum
ora_utl_tcp_close_all_connections(PG_FUNCTION_ARGS)
{
	for (int i = 0; i < UTL_TCP_MAX_CONNECTIONS; i++)
	{
		UtlTcpConnection *conn = &connections[i];

		if (conn->handle != UTL_TCP_HANDLE_FREE &&
			conn->owner == GetUserId())
		{
			closesocket(conn->sock);
			utl_tcp_release(conn);
		}
	}

	PG_RETURN_VOID();
}

/*
 * sys.ora_utl_tcp_write_text(sd, data, len) returns the number of
 * characters transmitted.
 */
Datum
ora_utl_tcp_write_text(PG_FUNCTION_ARGS)
{
	UtlTcpConnection *conn;
	text	   *data;
	int32		len;
	int			total_chars;
	int			send_chars;
	const char *p;
	int			remaining;
	int			cut_bytes;
	char	   *encoded;
	Size		encoded_len;
	TimestampTz deadline;

	if (PG_ARGISNULL(0))
		UTL_TCP_HANDLE_ERROR();

	conn = utl_tcp_lookup(PG_GETARG_INT32(0));

	/* NULL data transmits nothing, per Oracle */
	if (PG_ARGISNULL(1))
		PG_RETURN_INT32(0);

	data = PG_GETARG_TEXT_PP(1);
	total_chars = pg_mbstrlen_with_len(VARDATA_ANY(data),
									   VARSIZE_ANY_EXHDR(data));

	if (PG_ARGISNULL(2))
		send_chars = total_chars;
	else
	{
		len = PG_GETARG_INT32(2);

		if (len < 0)
			UTL_TCP_BAD_ARGUMENT("UTL_TCP: len must not be negative");
		if (len > total_chars)
			UTL_TCP_BAD_ARGUMENT_DETAIL("UTL_TCP: len exceeds the length of data",
										"data is shorter than the requested number of characters");

		send_chars = len;
	}

	if (send_chars == 0)
		PG_RETURN_INT32(0);

	/* cut send_chars characters out of the database-encoded input */
	p = VARDATA_ANY(data);
	remaining = VARSIZE_ANY_EXHDR(data);
	cut_bytes = 0;
	for (int i = 0; i < send_chars; i++)
	{
		int			clen = pg_encoding_mblen_or_incomplete(GetDatabaseEncoding(),
														   p,
														   (size_t) remaining);

		Assert(clen != INT_MAX && clen <= remaining);
		p += clen;
		remaining -= clen;
		cut_bytes += clen;
	}

	encoded = (char *) pg_do_encoding_conversion((unsigned char *) VARDATA_ANY(data),
												 cut_bytes,
												 GetDatabaseEncoding(),
												 conn->encoding);
	if (encoded == VARDATA_ANY(data))
		encoded_len = cut_bytes;
	else
		encoded_len = strlen(encoded);

	deadline = utl_tcp_deadline(conn);
	utl_tcp_send_all(conn, encoded, encoded_len, deadline);

	PG_RETURN_INT32(send_chars);
}

/*
 * sys.ora_utl_tcp_write_line(sd, data) returns the number of characters
 * transmitted, the newline sequence included.
 */
Datum
ora_utl_tcp_write_line(PG_FUNCTION_ARGS)
{
	UtlTcpConnection *conn;
	text	   *data;
	const char *input;
	int			input_bytes;
	int			input_chars;
	char	   *encoded;
	Size		encoded_len;
	int			newline_chars;
	StringInfoData out;
	TimestampTz deadline;

	if (PG_ARGISNULL(0))
		UTL_TCP_HANDLE_ERROR();

	conn = utl_tcp_lookup(PG_GETARG_INT32(0));

	if (!PG_ARGISNULL(1))
	{
		data = PG_GETARG_TEXT_PP(1);
		input = VARDATA_ANY(data);
		input_bytes = VARSIZE_ANY_EXHDR(data);
	}
	else
	{
		/* a NULL data argument sends a blank line */
		input = "";
		input_bytes = 0;
	}

	encoded = (char *) pg_do_encoding_conversion((unsigned char *) input,
												 input_bytes,
												 GetDatabaseEncoding(),
												 conn->encoding);
	if (encoded == input)
		encoded_len = input_bytes;
	else
		encoded_len = strlen(encoded);

	input_chars = pg_mbstrlen_with_len(input, input_bytes);

	/* count the newline's characters in the wire encoding */
	{
		const char *np = conn->newline;
		int			nrem = conn->newline_len;

		newline_chars = 0;
		while (nrem > 0)
		{
			int			clen = pg_encoding_mblen_or_incomplete(conn->encoding,
															   np,
															   (size_t) nrem);

			Assert(clen != INT_MAX && clen <= nrem);
			np += clen;
			nrem -= clen;
			newline_chars++;
		}
	}

	deadline = utl_tcp_deadline(conn);

	/* send data and newline together whenever possible */
	if (encoded_len == 0)
	{
		utl_tcp_send_all(conn, conn->newline, conn->newline_len, deadline);
	}
	else
	{
		initStringInfo(&out);
		appendBinaryStringInfo(&out, encoded, (int) encoded_len);
		appendBinaryStringInfo(&out, conn->newline, conn->newline_len);

		utl_tcp_send_all(conn, out.data, out.len, deadline);
	}

	PG_RETURN_INT32(input_chars + newline_chars);
}

/*
 * sys.ora_utl_tcp_write_raw(sd, data, len) returns the number of bytes
 * transmitted.
 */
Datum
ora_utl_tcp_write_raw(PG_FUNCTION_ARGS)
{
	UtlTcpConnection *conn;
	bytea	   *data;
	int			total_bytes;
	int			send_bytes;
	TimestampTz deadline;

	if (PG_ARGISNULL(0))
		UTL_TCP_HANDLE_ERROR();

	conn = utl_tcp_lookup(PG_GETARG_INT32(0));

	/* NULL data transmits nothing */
	if (PG_ARGISNULL(1))
		PG_RETURN_INT32(0);

	data = PG_GETARG_BYTEA_PP(1);
	total_bytes = VARSIZE_ANY_EXHDR(data);

	if (PG_ARGISNULL(2))
		send_bytes = total_bytes;
	else
	{
		int32		len = PG_GETARG_INT32(2);

		if (len < 0)
			UTL_TCP_BAD_ARGUMENT("UTL_TCP: len must not be negative");
		if (len > total_bytes)
			UTL_TCP_BAD_ARGUMENT_DETAIL("UTL_TCP: len exceeds the length of data",
										"data is shorter than the requested number of bytes");

		send_bytes = len;
	}

	if (send_bytes == 0)
		PG_RETURN_INT32(0);

	deadline = utl_tcp_deadline(conn);
	utl_tcp_send_all(conn, VARDATA_ANY(data), (size_t) send_bytes, deadline);

	PG_RETURN_INT32(send_bytes);
}

/*
 * sys.ora_utl_tcp_get_text(sd, len, peek) returns up to len characters.
 *
 * Complete characters are staged in the receive buffer and converted to
 * the database encoding as a whole; the wire bytes are consumed only
 * after the return value has been built, so neither the 32767-byte SQL
 * value limit nor a conversion error can lose received data.  When the
 * converted value would exceed the limit, the longest prefix of whole
 * characters that fits is returned and the rest stays buffered for the
 * next call.
 */
Datum
ora_utl_tcp_get_text(PG_FUNCTION_ARGS)
{
	UtlTcpConnection *conn;
	int32		want;
	int			staged_bytes = 0;
	int			staged_chars = 0;
	int			take_bytes;
	TimestampTz deadline;
	unsigned char *converted;
	char	   *result;
	int			result_len;
	text	   *retval;

	if (PG_ARGISNULL(0))
		UTL_TCP_HANDLE_ERROR();

	conn = utl_tcp_lookup(PG_GETARG_INT32(0));

	if (!PG_ARGISNULL(2) && PG_GETARG_BOOL(2))
		UTL_TCP_FEATURE("UTL_TCP: peek is not supported");

	if (PG_ARGISNULL(1))
		UTL_TCP_BAD_ARGUMENT("UTL_TCP: len must not be NULL");

	want = PG_GETARG_INT32(1);
	if (want < 1 || want > UTL_TCP_MAX_VALUE_BYTES)
		UTL_TCP_BAD_ARGUMENT("UTL_TCP: len must be between 1 and 32767");

	deadline = utl_tcp_deadline(conn);

	/*
	 * Stage complete characters at staged_bytes without consuming them.
	 * Staging stops at the SQL value limit on the wire side; a limit hit
	 * through wire-to-database expansion is handled after conversion.
	 */
	while (staged_chars < want)
	{
		int			clen;
		bool		incomplete;
		bool		invalid;

		clen = utl_tcp_char_len(conn, staged_bytes, &incomplete, &invalid);

		if (invalid)
			ereport(ERROR,
					(errcode(ERRCODE_CHARACTER_NOT_IN_REPERTOIRE),
					 errmsg("UTL_TCP: invalid byte sequence for encoding \"%s\" in received data",
							pg_encoding_to_char(conn->encoding))));

		if (incomplete)
		{
			if (conn->eof)
			{
				/* an incomplete final character never leaves the buffer */
				if (staged_chars == 0 && conn->rxbuf.len == 0)
					UTL_TCP_END_OF_INPUT();
				if (staged_chars == 0 && conn->rxbuf.len > 0)
					UTL_TCP_PARTIAL_MULTIBYTE();

				break;			/* return the complete characters read */
			}

			if (deadline != 0 &&
				TimestampDifferenceMilliseconds(GetCurrentTimestamp(),
												deadline) <= 0)
			{
				int			fillrc;

				/*
				 * The deadline has passed, but bytes may already sit in
				 * the kernel buffer: make one nonblocking receive (a
				 * fill with an expired deadline never waits) before
				 * giving up.
				 */
				fillrc = utl_tcp_fill(conn, deadline);
				if (fillrc == UTL_TCP_FILL_DATA)
					continue;
				if (fillrc == UTL_TCP_FILL_EOF)
					continue;	/* loop rechecks; conn->eof is set */

				/*
				 * Oracle's READ_TEXT rule: a timeout while a character
				 * is only partly received raises TRANSFER_TIMEOUT and
				 * keeps everything buffered for a retry.
				 */
				ereport(ERROR,
						(errcode(ERRCODE_CONNECTION_FAILURE),
						 errmsg("UTL_TCP: transfer timed out after %d seconds",
								conn->timeout_ms / 1000)));
			}

			(void) utl_tcp_fill(conn, deadline);
			continue;
		}

		if (staged_bytes + clen > UTL_TCP_MAX_VALUE_BYTES)
			break;				/* wire staging cap; keep the rest */

		staged_bytes += clen;
		staged_chars++;
	}

	if (staged_chars == 0)
	{
		/* clean EOF with no complete character at all */
		if (conn->rxbuf.len == 0)
			UTL_TCP_END_OF_INPUT();

		UTL_TCP_PARTIAL_MULTIBYTE();
	}

	/* convert the staged characters as a whole */
	converted = pg_do_encoding_conversion((unsigned char *) conn->rxbuf.data,
										  staged_bytes,
										  conn->encoding,
										  GetDatabaseEncoding());

	if (converted == (unsigned char *) conn->rxbuf.data)
	{
		result = conn->rxbuf.data;
		result_len = staged_bytes;
	}
	else
	{
		result = (char *) converted;
		result_len = strlen(result);
	}

	take_bytes = staged_bytes;

	if (result_len > UTL_TCP_MAX_VALUE_BYTES)
	{
		/*
		 * The conversion expanded the text past the SQL value limit.
		 * Binary-search the largest whole-character prefix that fits; a
		 * single character always fits, so at least one is returned and
		 * the remainder stays buffered.
		 */
		int			lo = 1;
		int			hi = staged_chars;

		while (lo < hi)
		{
			int			mid = lo + (hi - lo + 1) / 2;
			int			off = utl_tcp_char_offset(conn, staged_bytes, mid);
			unsigned char *mid_converted;
			int			mid_len;

			mid_converted = pg_do_encoding_conversion(
				(unsigned char *) conn->rxbuf.data,
				off,
				conn->encoding,
				GetDatabaseEncoding());

			if (mid_converted == (unsigned char *) conn->rxbuf.data)
				mid_len = off;
			else
				mid_len = strlen((char *) mid_converted);

			if (mid_len <= UTL_TCP_MAX_VALUE_BYTES)
				lo = mid;
			else
				hi = mid - 1;
		}

		staged_chars = lo;
		take_bytes = utl_tcp_char_offset(conn, staged_bytes, lo);

		converted = pg_do_encoding_conversion((unsigned char *) conn->rxbuf.data,
											  take_bytes,
											  conn->encoding,
											  GetDatabaseEncoding());

		if (converted == (unsigned char *) conn->rxbuf.data)
		{
			result = conn->rxbuf.data;
			result_len = take_bytes;
		}
		else
		{
			result = (char *) converted;
			result_len = strlen(result);
		}
	}

	/* build the return value first; only then consume what it holds */
	retval = cstring_to_text_with_len(result, result_len);
	utl_tcp_consume(conn, take_bytes);

	PG_RETURN_TEXT_P(retval);
}

/*
 * sys.ora_utl_tcp_get_raw(sd, len, peek) returns up to len bytes.
 */
Datum
ora_utl_tcp_get_raw(PG_FUNCTION_ARGS)
{
	UtlTcpConnection *conn;
	int32		want;
	int			n;
	bytea	   *result;
	TimestampTz deadline;

	if (PG_ARGISNULL(0))
		UTL_TCP_HANDLE_ERROR();

	conn = utl_tcp_lookup(PG_GETARG_INT32(0));

	if (!PG_ARGISNULL(2) && PG_GETARG_BOOL(2))
		UTL_TCP_FEATURE("UTL_TCP: peek is not supported");

	if (PG_ARGISNULL(1))
		UTL_TCP_BAD_ARGUMENT("UTL_TCP: len must not be NULL");

	want = PG_GETARG_INT32(1);
	if (want < 1 || want > UTL_TCP_MAX_VALUE_BYTES)
		UTL_TCP_BAD_ARGUMENT("UTL_TCP: len must be between 1 and 32767");

	deadline = utl_tcp_deadline(conn);

	while (conn->rxbuf.len < want)
	{
		int			fillrc;

		if (conn->eof)
			break;

		if (deadline != 0 &&
			TimestampDifferenceMilliseconds(GetCurrentTimestamp(),
											deadline) <= 0)
		{
			/*
			 * The deadline has passed, but bytes may already sit in the
			 * kernel buffer: make one nonblocking receive before
			 * reporting the timeout.
			 */
			fillrc = utl_tcp_fill(conn, deadline);
			if (fillrc == UTL_TCP_FILL_TIMEOUT)
				break;

			continue;			/* DATA appends to the buffer; EOF sets
								 * conn->eof and the loop rechecks */
		}

		(void) utl_tcp_fill(conn, deadline);
	}

	n = Min(conn->rxbuf.len, want);

	if (n == 0)
	{
		if (conn->eof)
			UTL_TCP_END_OF_INPUT();

		ereport(ERROR,
				(errcode(ERRCODE_CONNECTION_FAILURE),
				 errmsg("UTL_TCP: transfer timed out after %d seconds",
						conn->timeout_ms / 1000)));
	}

	result = (bytea *) palloc(VARHDRSZ + n);
	SET_VARSIZE(result, VARHDRSZ + n);
	memcpy(VARDATA(result), conn->rxbuf.data, n);
	utl_tcp_consume(conn, n);

	PG_RETURN_BYTEA_P(result);
}

/*
 * sys.ora_utl_tcp_get_line(sd, remove_crlf, peek) returns one line,
 * terminated by LF, CR or CRLF (including a CRLF split across receives).
 * Per Oracle's READ_LINE rules, a lone CR terminates a line immediately;
 * if an LF arrives afterwards it is swallowed as part of the same
 * terminator instead of producing an empty line.  When no terminator has
 * arrived and the transfer times out, the buffered bytes are returned as
 * a partial line if they form whole characters, and TRANSFER_TIMEOUT is
 * raised (keeping everything buffered) when a character is incomplete.
 */
Datum
ora_utl_tcp_get_line(PG_FUNCTION_ARGS)
{
	UtlTcpConnection *conn;
	bool		remove_crlf;
	int			line_len = -1;
	int			term_len = 0;
	TimestampTz deadline;
	unsigned char *converted;
	char	   *result;
	int			result_len;
	int			take;
	text	   *retval;

	if (PG_ARGISNULL(0))
		UTL_TCP_HANDLE_ERROR();

	conn = utl_tcp_lookup(PG_GETARG_INT32(0));

	if (!PG_ARGISNULL(2) && PG_GETARG_BOOL(2))
		UTL_TCP_FEATURE("UTL_TCP: peek is not supported");

	if (PG_ARGISNULL(1))
		UTL_TCP_BAD_ARGUMENT("UTL_TCP: remove_crlf must not be NULL");

	remove_crlf = PG_GETARG_BOOL(1);
	deadline = utl_tcp_deadline(conn);

	/*
	 * Scan for a terminator, waiting for more input as needed.
	 */
	while (line_len < 0)
	{
		bool		found = false;

		/*
		 * An earlier call returned a lone CR as a complete line; an LF
		 * arriving afterwards belongs to that same CRLF terminator, so
		 * swallow it instead of reporting an empty line.  A deciding
		 * byte is required either way.
		 */
		if (conn->pending_lf && conn->rxbuf.len > 0)
		{
			if (conn->rxbuf.data[0] == '\n')
				utl_tcp_consume(conn, 1);

			conn->pending_lf = false;
			continue;
		}

		for (int i = 0; i < conn->rxbuf.len; i++)
		{
			char		ch = conn->rxbuf.data[i];

			if (ch == '\n')
			{
				line_len = i + 1;
				term_len = 1;
				found = true;
			}
			else if (ch == '\r')
			{
				if (i + 1 < conn->rxbuf.len)
				{
					if (conn->rxbuf.data[i + 1] == '\n')
					{
						line_len = i + 2;
						term_len = 2;
					}
					else
					{
						line_len = i + 1;
						term_len = 1;
					}
					found = true;
				}
				else
				{
					/*
					 * Nothing more is buffered: a lone CR is a complete
					 * line by itself.  Remember to swallow a matching
					 * LF should one arrive afterwards.
					 */
					line_len = i + 1;
					term_len = 1;
					found = true;
					conn->pending_lf = !conn->eof;
				}
			}

			if (found)
				break;
		}

		if (found)
			break;

		/* no terminator in the buffer yet */
		if (conn->rxbuf.len > UTL_TCP_MAX_VALUE_BYTES)
			UTL_TCP_PROGRAM_LIMIT("UTL_TCP: line exceeds the maximum value size of 32767 bytes");

		if (conn->eof)
		{
			if (conn->rxbuf.len == 0)
				UTL_TCP_END_OF_INPUT();

			/* unterminated final line: return what is buffered */
			line_len = conn->rxbuf.len;
			term_len = 0;
			break;
		}

		if (deadline != 0 &&
			TimestampDifferenceMilliseconds(GetCurrentTimestamp(),
											deadline) <= 0)
		{
			int			fillrc;

			/*
			 * The deadline has passed, but bytes may already sit in the
			 * kernel buffer: make one nonblocking receive before
			 * deciding between a partial line and a timeout.
			 */
			fillrc = utl_tcp_fill(conn, deadline);
			if (fillrc == UTL_TCP_FILL_DATA)
				continue;	/* rescan for a terminator */
			if (fillrc == UTL_TCP_FILL_EOF)
				continue;	/* loop rechecks; conn->eof is set */

			/*
			 * The transfer timed out.  Oracle returns the text read so
			 * far when it forms whole characters, and raises
			 * TRANSFER_TIMEOUT (keeping everything buffered) when a
			 * character is incomplete or nothing arrived at all.
			 */
			if (conn->pending_lf || !utl_tcp_complete_chars_only(conn))
				ereport(ERROR,
						(errcode(ERRCODE_CONNECTION_FAILURE),
						 errmsg("UTL_TCP: transfer timed out after %d seconds",
								conn->timeout_ms / 1000)));

			line_len = conn->rxbuf.len;
			term_len = 0;
			break;
		}

		(void) utl_tcp_fill(conn, deadline);
	}

	/*
	 * line_len is set: convert and return the line, terminator kept or
	 * dropped as requested.
	 */
	take = remove_crlf ? line_len - term_len : line_len;

	if (take == 0)
	{
		utl_tcp_consume(conn, line_len);
		PG_RETURN_TEXT_P(cstring_to_text_with_len("", 0));
	}

	converted = pg_do_encoding_conversion((unsigned char *) conn->rxbuf.data,
										  take,
										  conn->encoding,
										  GetDatabaseEncoding());

	if (converted == (unsigned char *) conn->rxbuf.data)
	{
		result = conn->rxbuf.data;
		result_len = take;
	}
	else
	{
		result = (char *) converted;
		result_len = strlen(result);
	}

	if (result_len > UTL_TCP_MAX_VALUE_BYTES)
		UTL_TCP_PROGRAM_LIMIT("UTL_TCP: line exceeds the maximum value size of 32767 bytes");

	retval = cstring_to_text_with_len(result, result_len);
	utl_tcp_consume(conn, line_len);

	PG_RETURN_TEXT_P(retval);
}

/*
 * sys.ora_utl_tcp_flush(sd)
 *
 * Output is unbuffered, so this only validates the handle.
 */
Datum
ora_utl_tcp_flush(PG_FUNCTION_ARGS)
{
	if (PG_ARGISNULL(0))
		UTL_TCP_HANDLE_ERROR();

	(void) utl_tcp_lookup(PG_GETARG_INT32(0));

	PG_RETURN_VOID();
}
