/*-------------------------------------------------------------------------
 *
 * parsexlog.c
 *	  Functions for reading Write-Ahead-Log
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *-------------------------------------------------------------------------
 */

#include "postgres_fe.h"

#include <unistd.h>

#include "access/rmgr.h"
#include "access/xact.h"
#include "access/xlog_internal.h"
#include "access/xlogreader.h"
#include "catalog/pg_control.h"
#include "catalog/storage_xlog.h"
#include "commands/dbcommands_xlog.h"
#include "fe_utils/archive.h"
#include "filemap.h"
#include "pg_rewind.h"
#include "storage/standbydefs.h"
#include "access/transam.h"

/*
 * RmgrNames is an array of the built-in resource manager names, to make error
 * messages a bit nicer.
 */
#define PG_RMGR(symname,name,redo,desc,identify,startup,cleanup,mask,decode) \
  name,

static const char *const RmgrNames[RM_MAX_ID + 1] = {
#include "access/rmgrlist.h"
};

#define RmgrName(rmid) (((rmid) <= RM_MAX_BUILTIN_ID) ? \
						RmgrNames[rmid] : "custom")

static void extractPageInfo(XLogReaderState *record, bool backward);
static bool RewindTransactionIdPrecedes(TransactionId id1, TransactionId id2);

static int	xlogreadfd = -1;
static XLogSegNo xlogreadsegno = 0;
static char xlogfpath[MAXPGPATH];
static TransactionId min_commited_xid = InvalidTransactionId;
static TransactionId max_commited_xid = InvalidTransactionId;
static TransactionId base_xid = InvalidTransactionId;

typedef struct XLogPageReadPrivate
{
	const char *restoreCommand;
	int			tliIndex;
} XLogPageReadPrivate;

static int	SimpleXLogPageRead(XLogReaderState *xlogreader,
							   XLogRecPtr targetPagePtr,
							   int reqLen, XLogRecPtr targetRecPtr, char *readBuf);

/*
 * Read WAL from the datadir/pg_wal, starting from 'startpoint' on timeline
 * index 'tliIndex' in target timeline history, until 'endpoint'. Make note of
 * the data blocks touched by the WAL records, and return them in a page map.
 *
 * 'endpoint' is the end of the last record to read. The record starting at
 * 'endpoint' is the first one that is not read.
 */
void
extractPageMapForward(const char *datadir, XLogRecPtr startpoint, int tliIndex,
			   XLogRecPtr endpoint, const char *restoreCommand)
{
	XLogRecord *record;
	XLogReaderState *xlogreader;
	char	   *errormsg;
	XLogPageReadPrivate private;

	private.tliIndex = tliIndex;
	private.restoreCommand = restoreCommand;
	xlogreader = XLogReaderAllocate(WalSegSz, datadir,
									XL_ROUTINE(.page_read = &SimpleXLogPageRead),
									&private);
	if (xlogreader == NULL)
		pg_fatal("out of memory while allocating a WAL reading processor");

	XLogBeginRead(xlogreader, startpoint);
	do
	{
		record = XLogReadRecord(xlogreader, &errormsg);

		if (record == NULL)
		{
			XLogRecPtr	errptr = xlogreader->EndRecPtr;

			if (errormsg)
				pg_fatal("could not read WAL record at %X/%08X: %s",
						 LSN_FORMAT_ARGS(errptr),
						 errormsg);
			else
				pg_fatal("could not read WAL record at %X/%08X",
						 LSN_FORMAT_ARGS(errptr));
		}

		extractPageInfo(xlogreader, false);
	} while (xlogreader->EndRecPtr < endpoint);

	/*
	 * If 'endpoint' didn't point exactly at a record boundary, the caller
	 * messed up.
	 */
	if (xlogreader->EndRecPtr != endpoint)
		pg_fatal("end pointer %X/%08X is not a valid end point; expected %X/%08X",
				 LSN_FORMAT_ARGS(endpoint), LSN_FORMAT_ARGS(xlogreader->EndRecPtr));

	XLogReaderFree(xlogreader);
	if (xlogreadfd != -1)
	{
		close(xlogreadfd);
		xlogreadfd = -1;
	}
}

void
extractPageMapBackward(const char *datadir, XLogRecPtr startpoint, int tliIndex,
				   const char *restoreCommand)
{
	/* Walk backwards, starting from the given record */
	XLogRecord *record;
	XLogRecPtr	searchptr;
	XLogReaderState *xlogreader;
	char	   *errormsg;
	XLogPageReadPrivate private;

	/*
	 * The given fork pointer points to the end of the last common record,
	 * which is not necessarily the beginning of the next record, if the
	 * previous record happens to end at a page boundary. Skip over the page
	 * header in that case to find the next record.
	 */
	if (startpoint % XLOG_BLCKSZ == 0)
	{
		if (XLogSegmentOffset(startpoint, WalSegSz) == 0)
			startpoint += SizeOfXLogLongPHD;
		else
			startpoint += SizeOfXLogShortPHD;
	}

	private.tliIndex = tliIndex;
	private.restoreCommand = restoreCommand;
	xlogreader = XLogReaderAllocate(WalSegSz, datadir,
									XL_ROUTINE(.page_read = &SimpleXLogPageRead),
									&private);
	if (xlogreader == NULL)
		pg_fatal("out of memory while allocating a WAL reading processor");

	searchptr = startpoint;
	for (;;)
	{
		XLogBeginRead(xlogreader, searchptr);
		record = XLogReadRecord(xlogreader, &errormsg);

		if (record == NULL)
		{
			if (errormsg)
				pg_fatal("could not find previous WAL record at %X/%X: %s",
						 LSN_FORMAT_ARGS(searchptr),
						 errormsg);
			else
				pg_fatal("could not find previous WAL record at %X/%X",
						 LSN_FORMAT_ARGS(searchptr));
		}

		extractPageInfo(xlogreader, true);
		/* We can break if met a safety snapshot */
		if (base_xid <= min_commited_xid)
			break;
		/* Walk backwards to previous record. */
		searchptr = record->xl_prev;
	}

	XLogReaderFree(xlogreader);
	if (xlogreadfd != -1)
	{
		close(xlogreadfd);
		xlogreadfd = -1;
	}
}

/*
 * Reads one WAL record. Returns the end position of the record, without
 * doing anything with the record itself.
 */
XLogRecPtr
readOneRecord(const char *datadir, XLogRecPtr ptr, int tliIndex,
			  const char *restoreCommand)
{
	XLogRecord *record;
	XLogReaderState *xlogreader;
	char	   *errormsg;
	XLogPageReadPrivate private;
	XLogRecPtr	endptr;

	private.tliIndex = tliIndex;
	private.restoreCommand = restoreCommand;
	xlogreader = XLogReaderAllocate(WalSegSz, datadir,
									XL_ROUTINE(.page_read = &SimpleXLogPageRead),
									&private);
	if (xlogreader == NULL)
		pg_fatal("out of memory while allocating a WAL reading processor");

	XLogBeginRead(xlogreader, ptr);
	record = XLogReadRecord(xlogreader, &errormsg);
	if (record == NULL)
	{
		if (errormsg)
			pg_fatal("could not read WAL record at %X/%08X: %s",
					 LSN_FORMAT_ARGS(ptr), errormsg);
		else
			pg_fatal("could not read WAL record at %X/%08X",
					 LSN_FORMAT_ARGS(ptr));
	}
	endptr = xlogreader->EndRecPtr;

	XLogReaderFree(xlogreader);
	if (xlogreadfd != -1)
	{
		close(xlogreadfd);
		xlogreadfd = -1;
	}

	return endptr;
}

/*
 * Find the previous checkpoint preceding given WAL location.
 */
void
findLastCheckpoint(const char *datadir, XLogRecPtr forkptr, int tliIndex,
				   XLogRecPtr *lastchkptrec, TimeLineID *lastchkpttli,
				   XLogRecPtr *lastchkptredo, const char *restoreCommand)
{
	/* Walk backwards, starting from the given record */
	XLogRecord *record;
	XLogRecPtr	searchptr;
	XLogReaderState *xlogreader;
	char	   *errormsg;
	XLogPageReadPrivate private;
	XLogSegNo	current_segno = 0;
	TimeLineID	current_tli = 0;

	/*
	 * The given fork pointer points to the end of the last common record,
	 * which is not necessarily the beginning of the next record, if the
	 * previous record happens to end at a page boundary. Skip over the page
	 * header in that case to find the next record.
	 */
	if (forkptr % XLOG_BLCKSZ == 0)
	{
		if (XLogSegmentOffset(forkptr, WalSegSz) == 0)
			forkptr += SizeOfXLogLongPHD;
		else
			forkptr += SizeOfXLogShortPHD;
	}

	private.tliIndex = tliIndex;
	private.restoreCommand = restoreCommand;
	xlogreader = XLogReaderAllocate(WalSegSz, datadir,
									XL_ROUTINE(.page_read = &SimpleXLogPageRead),
									&private);
	if (xlogreader == NULL)
		pg_fatal("out of memory while allocating a WAL reading processor");

	searchptr = forkptr;
	for (;;)
	{
		uint8		info;

		XLogBeginRead(xlogreader, searchptr);
		record = XLogReadRecord(xlogreader, &errormsg);

		if (record == NULL)
		{
			if (errormsg)
				pg_fatal("could not find previous WAL record at %X/%08X: %s",
						 LSN_FORMAT_ARGS(searchptr),
						 errormsg);
			else
				pg_fatal("could not find previous WAL record at %X/%08X",
						 LSN_FORMAT_ARGS(searchptr));
		}

		/* Detect if a new WAL file has been opened */
		if (xlogreader->seg.ws_tli != current_tli ||
			xlogreader->seg.ws_segno != current_segno)
		{
			char		xlogfname[MAXFNAMELEN];

			snprintf(xlogfname, MAXFNAMELEN, XLOGDIR "/");

			/* update current values */
			current_tli = xlogreader->seg.ws_tli;
			current_segno = xlogreader->seg.ws_segno;

			XLogFileName(xlogfname + sizeof(XLOGDIR),
						 current_tli, current_segno, WalSegSz);

			/* Track this filename as one to not remove */
			keepwal_add_entry(xlogfname);
		}

		/*
		 * Check if it is a checkpoint record. This checkpoint record needs to
		 * be the latest checkpoint before WAL forked and not the checkpoint
		 * where the primary has been stopped to be rewound.
		 */
		info = XLogRecGetInfo(xlogreader) & ~XLR_INFO_MASK;
		if (searchptr < forkptr &&
			XLogRecGetRmid(xlogreader) == RM_XLOG_ID &&
			(info == XLOG_CHECKPOINT_SHUTDOWN ||
			 info == XLOG_CHECKPOINT_ONLINE))
		{
			CheckPoint	checkPoint;

			memcpy(&checkPoint, XLogRecGetData(xlogreader), sizeof(CheckPoint));
			*lastchkptrec = searchptr;
			*lastchkpttli = checkPoint.ThisTimeLineID;
			*lastchkptredo = checkPoint.redo;
			break;
		}

		/* Walk backwards to previous record. */
		searchptr = record->xl_prev;
	}

	XLogReaderFree(xlogreader);
	if (xlogreadfd != -1)
	{
		close(xlogreadfd);
		xlogreadfd = -1;
	}
}

bool check_rewind_safety(void)
{
	/* If no committed transactions, it's safe to rewind */
	if (min_commited_xid == InvalidTransactionId)
		return true;
	/* If base_xid is less than or equal to min_commited_xid, it's safe */
	if (base_xid <= min_commited_xid)
		return true;
	return false;
}

bool check_transaction_need_rewind(TransactionId xid)
{
	/*
	 * If no committed transactions, no need to rewind.
	 *
	 * We use this function only on backward reading phase which only
	 * pay attention to records with transaction.
	 */
	if (min_commited_xid == InvalidTransactionId ||
			max_commited_xid == InvalidTransactionId ||
			xid == InvalidTransactionId)
	{
		return false;
	}

	/*
	 * It's better if we generate the commited transaction ID list for a
	 * accurate copy. But we can not get a bitmapset or list support here
	 * and it seems no need to do that.
	 *
	 * So I think a filter by min and max committed transaction ID is
	 * good enough.
	 */
	if (RewindTransactionIdPrecedes(xid, min_commited_xid) ||
				RewindTransactionIdPrecedes(max_commited_xid, xid))
		return false;

	return true;
}

/* XLogReader callback function, to read a WAL page */
static int
SimpleXLogPageRead(XLogReaderState *xlogreader, XLogRecPtr targetPagePtr,
				   int reqLen, XLogRecPtr targetRecPtr, char *readBuf)
{
	XLogPageReadPrivate *private = (XLogPageReadPrivate *) xlogreader->private_data;
	uint32		targetPageOff;
	XLogRecPtr	targetSegEnd;
	XLogSegNo	targetSegNo;
	int			r;

	XLByteToSeg(targetPagePtr, targetSegNo, WalSegSz);
	XLogSegNoOffsetToRecPtr(targetSegNo + 1, 0, WalSegSz, targetSegEnd);
	targetPageOff = XLogSegmentOffset(targetPagePtr, WalSegSz);

	/*
	 * See if we need to switch to a new segment because the requested record
	 * is not in the currently open one.
	 */
	if (xlogreadfd >= 0 &&
		!XLByteInSeg(targetPagePtr, xlogreadsegno, WalSegSz))
	{
		close(xlogreadfd);
		xlogreadfd = -1;
	}

	XLByteToSeg(targetPagePtr, xlogreadsegno, WalSegSz);

	if (xlogreadfd < 0)
	{
		char		xlogfname[MAXFNAMELEN];

		/*
		 * Since incomplete segments are copied into next timelines, switch to
		 * the timeline holding the required segment. Assuming this scan can
		 * be done both forward and backward, consider also switching timeline
		 * accordingly.
		 */
		while (private->tliIndex < targetNentries - 1 &&
			   targetHistory[private->tliIndex].end < targetSegEnd)
			private->tliIndex++;
		while (private->tliIndex > 0 &&
			   targetHistory[private->tliIndex].begin >= targetSegEnd)
			private->tliIndex--;

		XLogFileName(xlogfname, targetHistory[private->tliIndex].tli,
					 xlogreadsegno, WalSegSz);

		snprintf(xlogfpath, MAXPGPATH, "%s/" XLOGDIR "/%s",
				 xlogreader->segcxt.ws_dir, xlogfname);

		xlogreadfd = open(xlogfpath, O_RDONLY | PG_BINARY, 0);

		if (xlogreadfd < 0)
		{
			/*
			 * If we have no restore_command to execute, then exit.
			 */
			if (private->restoreCommand == NULL)
			{
				pg_log_error("could not open file \"%s\": %m", xlogfpath);
				return -1;
			}

			/*
			 * Since we have restore_command, then try to retrieve missing WAL
			 * file from the archive.
			 */
			xlogreadfd = RestoreArchivedFile(xlogreader->segcxt.ws_dir,
											 xlogfname,
											 WalSegSz,
											 private->restoreCommand);

			if (xlogreadfd < 0)
				return -1;
			else
				pg_log_debug("using file \"%s\" restored from archive",
							 xlogfpath);
		}
	}

	/*
	 * At this point, we have the right segment open.
	 */
	Assert(xlogreadfd != -1);

	/* Read the requested page */
	if (lseek(xlogreadfd, (off_t) targetPageOff, SEEK_SET) < 0)
	{
		pg_log_error("could not seek in file \"%s\": %m", xlogfpath);
		return -1;
	}


	r = read(xlogreadfd, readBuf, XLOG_BLCKSZ);
	if (r != XLOG_BLCKSZ)
	{
		if (r < 0)
			pg_log_error("could not read file \"%s\": %m", xlogfpath);
		else
			pg_log_error("could not read file \"%s\": read %d of %zu",
						 xlogfpath, r, (Size) XLOG_BLCKSZ);

		return -1;
	}

	Assert(targetSegNo == xlogreadsegno);

	xlogreader->seg.ws_tli = targetHistory[private->tliIndex].tli;
	return XLOG_BLCKSZ;
}

static void
track_rewind_snapshot(XLogReaderState *record, bool backward)
{
	uint8		info = 0;
	RmgrId		rmid = XLogRecGetRmid(record);

	if (rmid != RM_XACT_ID && rmid != RM_STANDBY_ID)
		return;

	if (rmid == RM_XACT_ID)
	{
		xl_xact_commit *xlrec = (xl_xact_commit *) XLogRecGetData(record);
		xl_xact_parsed_commit parsed;
		TransactionId current_xid = InvalidTransactionId;

		/* We finished tracking during forward read phase */
		if (backward)
			return;

		info = XLogRecGetInfo(record) & XLOG_XACT_OPMASK;
		ParseCommitRecord(XLogRecGetInfo(record), xlrec, &parsed);
		if (info == XLOG_XACT_COMMIT)
		{
			current_xid = XLogRecGetXid(record);
		}
		else if (info == XLOG_XACT_COMMIT_PREPARED)
		{
			current_xid = parsed.twophase_xid;
		}

		if (min_commited_xid == InvalidTransactionId ||
		   RewindTransactionIdPrecedes(current_xid, min_commited_xid))
		{
			min_commited_xid = current_xid;
			if (showprogress)
				pg_log_info("Get min committed xid: %u", min_commited_xid);
		}

		if (max_commited_xid == InvalidTransactionId ||
		   RewindTransactionIdPrecedes(max_commited_xid, current_xid))
		{
			max_commited_xid = current_xid;
			if (showprogress)
				pg_log_info("Get max committed xid: %u", max_commited_xid);
		}
	}
	else if (rmid == RM_STANDBY_ID)
	{
		info = XLogRecGetInfo(record) & ~XLR_INFO_MASK;

		if (info == XLOG_RUNNING_XACTS)
		{
			xl_running_xacts *xlrec = (xl_running_xacts *) XLogRecGetData(record);

			if (base_xid == InvalidTransactionId || RewindTransactionIdPrecedes(xlrec->nextXid, base_xid))
			{
				base_xid = xlrec->nextXid;
				if (showprogress)
					pg_log_info("Get base xid: %u at %X/%X", base_xid, LSN_FORMAT_ARGS(record->ReadRecPtr));
			}
		}
	}
}

/*
 * Extract information on which blocks the current record modifies.
 */
static void
extractPageInfo(XLogReaderState *record, bool backward)
{
	int			block_id;
	RmgrId		rmid = XLogRecGetRmid(record);
	uint8		info = XLogRecGetInfo(record);
	uint8		rminfo = info & ~XLR_INFO_MASK;

	/* Is this a special record type that I recognize? */

	if (rmid == RM_DBASE_ID && rminfo == XLOG_DBASE_CREATE_FILE_COPY)
	{
		/*
		 * New databases can be safely ignored. It won't be present in the
		 * source system, so it will be deleted. There's one corner-case,
		 * though: if a new, different, database is also created in the source
		 * system, we'll see that the files already exist and not copy them.
		 * That's OK, though; WAL replay of creating the new database, from
		 * the source systems's WAL, will re-copy the new database,
		 * overwriting the database created in the target system.
		 */
	}
	else if (rmid == RM_DBASE_ID && rminfo == XLOG_DBASE_CREATE_WAL_LOG)
	{
		/*
		 * New databases can be safely ignored. It won't be present in the
		 * source system, so it will be deleted.
		 */
	}
	else if (rmid == RM_DBASE_ID && rminfo == XLOG_DBASE_DROP)
	{
		/*
		 * An existing database was dropped. We'll see that the files don't
		 * exist in the target data dir, and copy them in toto from the source
		 * system. No need to do anything special here.
		 */
	}
	else if (rmid == RM_SMGR_ID && rminfo == XLOG_SMGR_CREATE)
	{
		/*
		 * We can safely ignore these. The file will be removed from the
		 * target, if it doesn't exist in source system. If a file with same
		 * name is created in source system, too, there will be WAL records
		 * for all the blocks in it.
		 */
	}
	else if (rmid == RM_SMGR_ID && rminfo == XLOG_SMGR_TRUNCATE)
	{
		/*
		 * We can safely ignore these. When we compare the sizes later on,
		 * we'll notice that they differ, and copy the missing tail from
		 * source system.
		 */
	}
	else if (rmid == RM_XACT_ID &&
			 ((rminfo & XLOG_XACT_OPMASK) == XLOG_XACT_COMMIT ||
			  (rminfo & XLOG_XACT_OPMASK) == XLOG_XACT_COMMIT_PREPARED ||
			  (rminfo & XLOG_XACT_OPMASK) == XLOG_XACT_ABORT ||
			  (rminfo & XLOG_XACT_OPMASK) == XLOG_XACT_ABORT_PREPARED))
	{
		/*
		 * These records can include "dropped rels". We can safely ignore
		 * them, we will see that they are missing and copy them from the
		 * source.
		 */
	}
	else if (info & XLR_SPECIAL_REL_UPDATE)
	{
		/*
		 * This record type modifies a relation file in some special way, but
		 * we don't recognize the type. That's bad - we don't know how to
		 * track that change.
		 */
		pg_fatal("WAL record modifies a relation, but record type is not recognized:\n"
				 "lsn: %X/%08X, rmid: %d, rmgr: %s, info: %02X",
				 LSN_FORMAT_ARGS(record->ReadRecPtr),
				 rmid, RmgrName(rmid), info);
	}

	track_rewind_snapshot(record, backward);

	/*
	 * We will copy all changed blocks met in forward step, and just copy
	 * meaningful changed blocks met in backward step.
	 */
	if (backward)
	{
		bool need_rewind = false;
		TransactionId xid = XLogRecGetXid(record);

		need_rewind = check_transaction_need_rewind(xid);
		if (!need_rewind)
			return;
	}

	for (block_id = 0; block_id <= XLogRecMaxBlockId(record); block_id++)
	{
		RelFileLocator rlocator;
		ForkNumber	forknum;
		BlockNumber blkno;

		if (!XLogRecGetBlockTagExtended(record, block_id,
										&rlocator, &forknum, &blkno, NULL))
			continue;

		/* We only care about the main fork; others are copied in toto */
		if (forknum != MAIN_FORKNUM)
			continue;

		process_target_wal_block_change(forknum, rlocator, blkno);
	}
}

/*
 * RewindTransactionIdPrecedes --- is id1 logically < id2?
 */
static bool
RewindTransactionIdPrecedes(TransactionId id1, TransactionId id2)
{
	/*
	 * If either ID is a permanent XID then we can just do unsigned
	 * comparison.  If both are normal, do a modulo-2^32 comparison.
	 */
	int32		diff;

	if (!TransactionIdIsNormal(id1) || !TransactionIdIsNormal(id2))
		return (id1 < id2);

	diff = (int32) (id1 - id2);
	return (diff < 0);
}
