/*------------------------------------------------------------------------
 *
 * Query cancellation support for frontend code
 *
 * This module provides SIGINT/Ctrl-C handling for frontend tools that need to
 * cancel queries or interrupt other operations.  It provides three
 * independent mechanisms, any combination of which can be used by an
 * application:
 *
 * 1. Server cancel query request -- When a query is running and the main
 *    thread is waiting for the result of that query in a blocking manner, we
 *    want SIGINT/Ctrl-C to cancel that query.  This can be achieved by
 *    calling SetCancelConn() to register the connection that is (or will be)
 *    running the query, prior to waiting for the result.  When SIGINT/Ctrl-C
 *    is received, a cancel request for this connection will then be sent from
 *    the signal handler (on Windows, from a separate thread).  That in turn
 *    will then (assuming a co-operating server) cause the server to cancel
 *    the query and send an error to the waiting client on the main thread.
 *    The cancel connection is a process-wide global, so only one connection
 *    can be the cancel target at a time.  ResetCancelConn() should be called
 *    to disarm the mechanism again after the blocking wait has completed.
 *
 * 2. CancelRequested flag -- The CancelRequested flag is set to true whenever
 *    SIGINT is received, and can be checked by the application at appropriate
 *    times.  The primary use case for this is when the application code is
 *    not blocked (indefinitely), but needs to take an action when Ctrl-C is
 *    pressed, such as break out of a long running loop.
 *
 * 3. Signal handler callback -- A callback function can be registered with
 *    setup_cancel_handler(), which will then be called directly from the
 *    signal handler whenever SIGINT is received.  Because it is called from a
 *    signal handler, the callback function must be async-signal-safe.  On
 *    Windows, it is called from a separate signal-handling thread.  NOTE: The
 *    callback is called AFTER setting CancelRequested but BEFORE sending the
 *    cancel request to the server (if armed by SetCancelConn).  This means
 *    that if the callback exits or longjmps, no cancel request will be sent
 *    to the server.
 *
 * Portions Copyright (c) 1996-2026, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/fe_utils/cancel.c
 *
 *------------------------------------------------------------------------
 */

#include "postgres_fe.h"

#include <unistd.h>

#include "common/connect.h"
#include "fe_utils/cancel.h"
#include "fe_utils/string_utils.h"


/*
 * Write a simple string to stderr --- must be safe in a signal handler.
 * We ignore the write() result since there's not much we could do about it.
 * Certain compilers make that harder than it ought to be.
 */
#define write_stderr(str) \
	do { \
		const char *str_ = (str); \
		int		rc_; \
		rc_ = write(fileno(stderr), str_, strlen(str_)); \
		(void) rc_; \
	} while (0)

/*
 * Contains all the information needed to cancel a query issued from
 * a database connection to the backend.
 */
static PGcancel *volatile cancelConn = NULL;

/*
 * Predetermined localized error strings --- needed to avoid trying
 * to call gettext() from a signal handler.
 */
static const char *cancel_sent_msg = NULL;
static const char *cancel_not_sent_msg = NULL;

/*
 * CancelRequested is set when we receive SIGINT (or local equivalent).
 * There is no provision in this module for resetting it; but applications
 * might choose to clear it after successfully recovering from a cancel.
 * Note that there is no guarantee that we successfully sent a Cancel request,
 * or that the request will have any effect if we did send it.
 */
volatile sig_atomic_t CancelRequested = false;

#ifdef WIN32
static CRITICAL_SECTION cancelConnLock;
#endif

/*
 * Additional callback for cancellations.
 */
static void (*cancel_callback) (void) = NULL;


/*
 * SetCancelConn
 *
 * Set cancelConn to point to the current database connection.
 */
void
SetCancelConn(PGconn *conn)
{
	PGcancel   *oldCancelConn;

#ifdef WIN32
	EnterCriticalSection(&cancelConnLock);
#endif

	/* Free the old one if we have one */
	oldCancelConn = cancelConn;

	/* be sure handle_sigint doesn't use pointer while freeing */
	cancelConn = NULL;

	if (oldCancelConn != NULL)
		PQfreeCancel(oldCancelConn);

	cancelConn = PQgetCancel(conn);

#ifdef WIN32
	LeaveCriticalSection(&cancelConnLock);
#endif
}

/*
 * ResetCancelConn
 *
 * Free the current cancel connection, if any, and set to NULL.
 */
void
ResetCancelConn(void)
{
	PGcancel   *oldCancelConn;

#ifdef WIN32
	EnterCriticalSection(&cancelConnLock);
#endif

	oldCancelConn = cancelConn;

	/* be sure handle_sigint doesn't use pointer while freeing */
	cancelConn = NULL;

	if (oldCancelConn != NULL)
		PQfreeCancel(oldCancelConn);

#ifdef WIN32
	LeaveCriticalSection(&cancelConnLock);
#endif
}


/*
 * Code to support query cancellation
 *
 * Note that sending the cancel directly from the signal handler is safe
 * because PQcancel() is written to make it so.  We use write() to report
 * to stderr because it's better to use simple facilities in a signal
 * handler.
 *
 * On Windows, the signal canceling happens on a separate thread, because
 * that's how SetConsoleCtrlHandler works.  The PQcancel function is safe
 * for this (unlike PQrequestCancel).  However, a CRITICAL_SECTION is required
 * to protect the PGcancel structure against being changed while the signal
 * thread is using it.
 */

#ifndef WIN32

/*
 * handle_sigint
 *
 * Handle interrupt signals by canceling the current command, if cancelConn
 * is set.
 */
static void
handle_sigint(SIGNAL_ARGS)
{
	char		errbuf[256];

	CancelRequested = true;

	if (cancel_callback != NULL)
		cancel_callback();

	/* Send QueryCancel if we are processing a database query */
	if (cancelConn != NULL)
	{
		if (PQcancel(cancelConn, errbuf, sizeof(errbuf)))
		{
			write_stderr(cancel_sent_msg);
		}
		else
		{
			write_stderr(cancel_not_sent_msg);
			write_stderr(errbuf);
		}
	}
}

/*
 * setup_cancel_handler
 *
 * Register query cancellation callback for SIGINT.
 */
void
setup_cancel_handler(void (*query_cancel_callback) (void))
{
	cancel_callback = query_cancel_callback;
	cancel_sent_msg = _("Cancel request sent\n");
	cancel_not_sent_msg = _("Could not send cancel request: ");

	pqsignal(SIGINT, handle_sigint);
}

#else							/* WIN32 */

static BOOL WINAPI
consoleHandler(DWORD dwCtrlType)
{
	char		errbuf[256];

	if (dwCtrlType == CTRL_C_EVENT ||
		dwCtrlType == CTRL_BREAK_EVENT)
	{
		CancelRequested = true;

		if (cancel_callback != NULL)
			cancel_callback();

		/* Send QueryCancel if we are processing a database query */
		EnterCriticalSection(&cancelConnLock);
		if (cancelConn != NULL)
		{
			if (PQcancel(cancelConn, errbuf, sizeof(errbuf)))
			{
				write_stderr(cancel_sent_msg);
			}
			else
			{
				write_stderr(cancel_not_sent_msg);
				write_stderr(errbuf);
			}
		}

		LeaveCriticalSection(&cancelConnLock);

		return TRUE;
	}
	else
		/* Return FALSE for any signals not being handled */
		return FALSE;
}

void
setup_cancel_handler(void (*callback) (void))
{
	cancel_callback = callback;
	cancel_sent_msg = _("Cancel request sent\n");
	cancel_not_sent_msg = _("Could not send cancel request: ");

	InitializeCriticalSection(&cancelConnLock);

	SetConsoleCtrlHandler(consoleHandler, TRUE);
}

#endif							/* WIN32 */
