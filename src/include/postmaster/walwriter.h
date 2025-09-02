/*-------------------------------------------------------------------------
 *
 * walwriter.h
 *	  Exports from postmaster/walwriter.c.
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 *
 * src/include/postmaster/walwriter.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef _WALWRITER_H
#define _WALWRITER_H

#define DEFAULT_WAL_WRITER_FLUSH_AFTER ((1024 * 1024) / XLOG_BLCKSZ)

/* GUC options */
extern PGDLLIMPORT int WalWriterDelay;
extern PGDLLIMPORT int WalWriterFlushAfter;

pg_noreturn extern void WalWriterMain(const void *startup_data, size_t startup_data_len);

#endif							/* _WALWRITER_H */
