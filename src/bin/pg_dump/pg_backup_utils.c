/*-------------------------------------------------------------------------
 *
 * pg_backup_utils.c
 *	Utility routines shared by pg_dump and pg_restore
 *
 *
 * Portions Copyright (c) 1996-2026, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/bin/pg_dump/pg_backup_utils.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres_fe.h"

#ifdef WIN32
#include "parallel.h"
#endif
#include "pg_backup_utils.h"

/* Globals exported by this file */
const char *progname = NULL;

#ifdef WIN32

/*
 * Flag telling worker threads to stay quiet about query failures because
 * we're cancelling their queries as part of tearing down the process.  See
 * the comment in pg_backup_utils.h.
 *
 * The cancel thread writes it while worker threads read it, so it's marked
 * volatile to keep the compiler from caching the value.  A plain volatile
 * bool isn't a memory barrier, but it's good enough here.  A lot of things
 * happen between set_cancel_in_progress() in the cancel thread and the other
 * threads calling is_cancel_in_progress(), including network operations,
 * which implicitly act as memory barriers.  Furthermore, the flag is only
 * ever flipped one way (false to true) and a worker briefly observing the
 * stale false just means it would print one error before the process dies.
 * The only goal of this flag is to make sure workers don't log "query
 * cancelled" errors during the shutdown process.
 *
 * XXX: This should be swapped out for a proper atomic when we have those in
 * the frontend code, so that we wouldn't need to rationalizee all of the
 * above.
 */
static volatile bool cancelInProgress = false;

void
set_cancel_in_progress(void)
{
	cancelInProgress = true;
}

bool
is_cancel_in_progress(void)
{
	return cancelInProgress;
}

#endif							/* WIN32 */

#define MAX_ON_EXIT_NICELY				20

static struct
{
	on_exit_nicely_callback function;
	void	   *arg;
}			on_exit_nicely_list[MAX_ON_EXIT_NICELY];

static int	on_exit_nicely_index;

/*
 * Parse a --section=foo command line argument.
 *
 * Set or update the bitmask in *dumpSections according to arg.
 * dumpSections is initialised as DUMP_UNSECTIONED by pg_dump and
 * pg_restore so they can know if this has even been called.
 */
void
set_dump_section(const char *arg, int *dumpSections)
{
	/* if this is the first call, clear all the bits */
	if (*dumpSections == DUMP_UNSECTIONED)
		*dumpSections = 0;

	if (strcmp(arg, "pre-data") == 0)
		*dumpSections |= DUMP_PRE_DATA;
	else if (strcmp(arg, "data") == 0)
		*dumpSections |= DUMP_DATA;
	else if (strcmp(arg, "post-data") == 0)
		*dumpSections |= DUMP_POST_DATA;
	else
	{
		pg_log_error("unrecognized section name: \"%s\"", arg);
		pg_log_error_hint("Try \"%s --help\" for more information.", progname);
		exit_nicely(1);
	}
}


/* Register a callback to be run when exit_nicely is invoked. */
void
on_exit_nicely(on_exit_nicely_callback function, void *arg)
{
	if (on_exit_nicely_index >= MAX_ON_EXIT_NICELY)
		pg_fatal("out of on_exit_nicely slots");
	on_exit_nicely_list[on_exit_nicely_index].function = function;
	on_exit_nicely_list[on_exit_nicely_index].arg = arg;
	on_exit_nicely_index++;
}

/*
 * Run accumulated on_exit_nicely callbacks in reverse order and then exit
 * without printing any message.
 *
 * If running in a parallel worker thread on Windows, we only exit the thread,
 * not the whole process.
 *
 * Note that in parallel operation on Windows, the callback(s) will be run
 * by each thread since the list state is necessarily shared by all threads;
 * each callback must contain logic to ensure it does only what's appropriate
 * for its thread.  On Unix, callbacks are also run by each process, but only
 * for callbacks established before we fork off the child processes.  (It'd
 * be cleaner to reset the list after fork(), and let each child establish
 * its own callbacks; but then the behavior would be completely inconsistent
 * between Windows and Unix.  For now, just be sure to establish callbacks
 * before forking to avoid inconsistency.)
 */
void
exit_nicely(int code)
{
	int			i;

	for (i = on_exit_nicely_index - 1; i >= 0; i--)
		on_exit_nicely_list[i].function(code,
										on_exit_nicely_list[i].arg);

#ifdef WIN32
	if (parallel_init_done && GetCurrentThreadId() != mainThreadId)
		_endthreadex(code);
#endif

	exit(code);
}
