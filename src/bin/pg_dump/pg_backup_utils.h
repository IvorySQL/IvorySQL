/*-------------------------------------------------------------------------
 *
 * pg_backup_utils.h
 *	Utility routines shared by pg_dump and pg_restore.
 *
 *
 * Portions Copyright (c) 1996-2026, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/bin/pg_dump/pg_backup_utils.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef PG_BACKUP_UTILS_H
#define PG_BACKUP_UTILS_H

#include "common/logging.h"

/* bits returned by set_dump_section */
#define DUMP_PRE_DATA		0x01
#define DUMP_DATA			0x02
#define DUMP_POST_DATA		0x04
#define DUMP_UNSECTIONED	0xff

typedef void (*on_exit_nicely_callback) (int code, void *arg);

extern const char *progname;

extern void set_dump_section(const char *arg, int *dumpSections);
extern void on_exit_nicely(on_exit_nicely_callback function, void *arg);
pg_noreturn extern void exit_nicely(int code);

/*
 * On Windows the parallel workers are threads inside the leader process.
 * When a cancel is processed there, the leader sends cancels to the workers'
 * in-flight queries; without this flag each worker would then report the
 * resulting "canceling statement due to user request" error and clutter the
 * screen in the brief window before the whole process exits.  The cancel
 * thread sets this flag before sending any cancel, and worker threads check
 * it before reporting a query failure.
 *
 * On other platforms the workers are separate processes that just _exit()
 * when cancelled, so they never reach the error-reporting code; there the
 * check is compiled out to a constant false and the underlying flag doesn't
 * exist.
 */
#ifdef WIN32
extern void set_cancel_in_progress(void);
extern bool is_cancel_in_progress(void);
#else
#define is_cancel_in_progress() false
#endif

/* In pg_dump, we modify pg_fatal to call exit_nicely instead of exit */
#undef pg_fatal
#define pg_fatal(...) do { \
		pg_log_generic(PG_LOG_ERROR, PG_LOG_PRIMARY, __VA_ARGS__); \
		exit_nicely(1); \
	} while(0)

#endif							/* PG_BACKUP_UTILS_H */
