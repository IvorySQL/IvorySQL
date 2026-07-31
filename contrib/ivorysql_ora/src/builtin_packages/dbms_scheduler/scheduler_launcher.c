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
 * scheduler_launcher.c
 *
 * DBMS_SCHEDULER background scheduling.
 *
 * A single launcher process (registered at shared_preload time) starts one
 * database scheduler worker for every database listed in
 * ivorysql_ora.scheduler_databases.  Each database scheduler polls
 * sys.scheduler_jobs for due jobs, advances their next run date, writes a
 * 'r' (running) log row and spawns a job worker per due job, capped by
 * ivorysql_ora.scheduler_max_job_workers.
 *
 * A database scheduler that stops on its own is reported and left stopped:
 * the reasons it stops for - no ivorysql_ora in that database, no such
 * database, a failure it could not work through - do not resolve themselves,
 * and restarting it on a timer would only repeat the reason until it is lost
 * in the repetitions.  Reloading the configuration retries every database
 * given up on this way, whether or not the GUC itself changed.
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_scheduler/scheduler_launcher.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "catalog/pg_extension.h"
#include "commands/extension.h"
#include "executor/spi.h"
#include "miscadmin.h"
#include "pgstat.h"
#include "postmaster/bgworker.h"
#include "postmaster/interrupt.h"
#include "storage/ipc.h"
#include "storage/latch.h"
#include "storage/proc.h"
#include "tcop/tcopprot.h"
#include "utils/acl.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/memutils.h"
#include "utils/resowner.h"
#include "utils/snapmgr.h"
#include "utils/timestamp.h"
#include "utils/varlena.h"

#include "dbms_scheduler.h"

/* GUC variables */
bool		scheduler_enabled = false;
char	   *scheduler_databases = NULL;
int			scheduler_poll_interval = 5;
int			scheduler_max_job_workers = 4;
int			scheduler_job_timeout = 0;
int			scheduler_max_failures = 0;

bool		scheduler_launcher_registered = false;

/*
 * Give up after this many consecutive polling cycles that all ended in an
 * error, on the grounds that the cause is not going to clear on its own.
 */
#define SCHED_MAX_CYCLE_FAILURES		10

/* Report a database we have given up on at most this often. */
#define SCHED_GIVEUP_REPORT_USEC		(60 * 60 * USECS_PER_SEC)

/* Launcher's view of one database scheduler worker */
typedef struct SchedDbWorker
{
	char		dbname[NAMEDATALEN];
	BackgroundWorkerHandle *handle;
	bool		active;			/* still listed in the GUC */
	bool		gave_up;		/* stopped on its own; not restarting it */
	TimestampTz last_report;	/* when we last said so; 0 = never */
} SchedDbWorker;

/*
 * SchedulerLauncherRegister
 *
 * Called from _PG_init.  Registers the launcher when the library is being
 * preloaded; otherwise scheduling is unavailable and ENABLE warns about it.
 */
void
SchedulerLauncherRegister(void)
{
	BackgroundWorker worker;

	if (!process_shared_preload_libraries_in_progress)
		return;
	if (!scheduler_enabled)
		return;

	MemSet(&worker, 0, sizeof(worker));
	worker.bgw_flags = BGWORKER_SHMEM_ACCESS;
	worker.bgw_start_time = BgWorkerStart_RecoveryFinished;
	worker.bgw_restart_time = 5;
	snprintf(worker.bgw_library_name, BGW_MAXLEN, "ivorysql_ora");
	snprintf(worker.bgw_function_name, BGW_MAXLEN, "SchedulerLauncherMain");
	snprintf(worker.bgw_name, BGW_MAXLEN, "ivorysql scheduler launcher");
	snprintf(worker.bgw_type, BGW_MAXLEN, "ivorysql scheduler launcher");
	worker.bgw_main_arg = (Datum) 0;
	worker.bgw_notify_pid = 0;

	RegisterBackgroundWorker(&worker);

	scheduler_launcher_registered = true;
}

/* ------------------------------------------------------------------
 * Launcher
 * ------------------------------------------------------------------
 */

static List *
scheduler_database_list(void)
{
	List	   *result = NIL;
	char	   *rawstring;
	List	   *elemlist;
	ListCell   *lc;

	if (scheduler_databases == NULL || scheduler_databases[0] == '\0')
		return NIL;

	rawstring = pstrdup(scheduler_databases);
	if (!SplitIdentifierString(rawstring, ',', &elemlist))
	{
		ereport(WARNING,
				(errmsg("invalid list syntax in ivorysql_ora.scheduler_databases")));
		list_free(elemlist);
		pfree(rawstring);
		return NIL;
	}

	foreach(lc, elemlist)
	{
		char	   *dbname = (char *) lfirst(lc);
		ListCell   *lc2;
		bool		dup = false;

		if (strlen(dbname) >= NAMEDATALEN)
		{
			ereport(WARNING,
					(errmsg("database name \"%s\" in ivorysql_ora.scheduler_databases is too long",
							dbname)));
			continue;
		}
		foreach(lc2, result)
		{
			if (strcmp((char *) lfirst(lc2), dbname) == 0)
			{
				dup = true;
				break;
			}
		}
		if (!dup)
			result = lappend(result, pstrdup(dbname));
	}

	list_free(elemlist);
	pfree(rawstring);
	return result;
}

static bool
scheduler_dbworker_alive(SchedDbWorker *dbw)
{
	pid_t		pid;
	BgwHandleStatus status;

	if (dbw->handle == NULL)
		return false;
	status = GetBackgroundWorkerPid(dbw->handle, &pid);
	return (status == BGWH_STARTED || status == BGWH_NOT_YET_STARTED);
}

static void
scheduler_start_dbworker(SchedDbWorker *dbw)
{
	BackgroundWorker worker;
	BackgroundWorkerHandle *handle;

	MemSet(&worker, 0, sizeof(worker));
	worker.bgw_flags = BGWORKER_SHMEM_ACCESS |
		BGWORKER_BACKEND_DATABASE_CONNECTION;
	worker.bgw_start_time = BgWorkerStart_RecoveryFinished;
	worker.bgw_restart_time = BGW_NEVER_RESTART;	/* launcher restarts it */
	snprintf(worker.bgw_library_name, BGW_MAXLEN, "ivorysql_ora");
	snprintf(worker.bgw_function_name, BGW_MAXLEN, "SchedulerDatabaseWorkerMain");
	snprintf(worker.bgw_name, BGW_MAXLEN, "ivorysql scheduler for \"%s\"",
			 dbw->dbname);
	snprintf(worker.bgw_type, BGW_MAXLEN, "ivorysql scheduler worker");
	strlcpy(worker.bgw_extra, dbw->dbname, BGW_EXTRALEN);
	worker.bgw_main_arg = (Datum) 0;
	worker.bgw_notify_pid = MyProcPid;

	{
		/* the handle must outlive the launcher's per-cycle memory context */
		MemoryContext oldcxt = MemoryContextSwitchTo(TopMemoryContext);
		bool		ok = RegisterDynamicBackgroundWorker(&worker, &handle);

		MemoryContextSwitchTo(oldcxt);

		if (!ok)
		{
			/*
			 * max_worker_processes cannot be raised without a restart, so
			 * there is nothing to gain from trying again every cycle.
			 */
			ereport(LOG,
					(errmsg("could not start scheduler worker for database \"%s\": out of background worker slots",
							dbw->dbname),
					 errhint("Consider increasing max_worker_processes.")));
			dbw->handle = NULL;
			dbw->gave_up = true;
			return;
		}
	}
	dbw->handle = handle;
}

void
SchedulerLauncherMain(Datum main_arg)
{
	List	   *dbworkers = NIL;
	MemoryContext launcher_ctx;

	pqsignal(SIGHUP, SignalHandlerForConfigReload);
	pqsignal(SIGTERM, SignalHandlerForShutdownRequest);
	BackgroundWorkerUnblockSignals();

	launcher_ctx = AllocSetContextCreate(TopMemoryContext,
										 "scheduler launcher",
										 ALLOCSET_DEFAULT_SIZES);

	ereport(LOG,
			(errmsg("ivorysql scheduler launcher started")));

	while (!ShutdownRequestPending)
	{
		List	   *wanted;
		ListCell   *lc;

		if (ConfigReloadPending)
		{
			ConfigReloadPending = false;
			ProcessConfigFile(PGC_SIGHUP);

			/*
			 * A reload is the administrator saying "I have dealt with it, try
			 * again", so retry every database we had given up on.  This has to
			 * happen whether or not scheduler_databases itself changed, and
			 * registry entries are never removed, so a database that was
			 * dropped from the GUC and later put back keeps its verdict until
			 * cleared here.
			 *
			 * last_report is deliberately left alone: it throttles what we say
			 * about a database across those retries, so clearing it here would
			 * defeat it.
			 */
			foreach(lc, dbworkers)
				((SchedDbWorker *) lfirst(lc))->gave_up = false;
		}

		/* per-cycle allocations (the worker registry lives in TopMemoryContext) */
		MemoryContextSwitchTo(launcher_ctx);
		MemoryContextReset(launcher_ctx);

		wanted = scheduler_database_list();

		/* mark all current workers inactive, reactivate listed ones */
		foreach(lc, dbworkers)
			((SchedDbWorker *) lfirst(lc))->active = false;

		foreach(lc, wanted)
		{
			char	   *dbname = (char *) lfirst(lc);
			ListCell   *lc2;
			SchedDbWorker *dbw = NULL;

			foreach(lc2, dbworkers)
			{
				SchedDbWorker *cand = (SchedDbWorker *) lfirst(lc2);

				if (strcmp(cand->dbname, dbname) == 0)
				{
					dbw = cand;
					break;
				}
			}

			if (dbw == NULL)
			{
				MemoryContext oldcxt = MemoryContextSwitchTo(TopMemoryContext);

				dbw = (SchedDbWorker *) palloc0(sizeof(SchedDbWorker));
				strlcpy(dbw->dbname, dbname, NAMEDATALEN);
				dbworkers = lappend(dbworkers, dbw);
				MemoryContextSwitchTo(oldcxt);
				dbw->active = true;
				scheduler_start_dbworker(dbw);
				continue;
			}

			dbw->active = true;

			if (dbw->gave_up)
				continue;		/* waiting to be told to try again */

			if (dbw->handle == NULL)
			{
				/* a reload cleared the earlier verdict; start over */
				scheduler_start_dbworker(dbw);
				continue;
			}

			/*
			 * A database scheduler polls forever, so its stopping on its own
			 * means something is wrong with that database: no ivorysql_ora
			 * installed, a database that does not exist, a persistent failure
			 * it could not work through.  None of that gets better by being
			 * restarted on a timer, and retrying would only bury the reason in
			 * repetitions of itself, so say so once and wait to be told to try
			 * again.
			 */
			if (!scheduler_dbworker_alive(dbw))
			{
				TimestampTz now = GetCurrentTimestamp();
				bool		report;

				/*
				 * Every reload retries this database, and a reload is not a
				 * signal aimed at the scheduler: the postmaster forwards SIGHUP
				 * to all of its children whatever the reload was for.  So the
				 * verdict can be reached again and again while the cause sits
				 * unchanged, and only the first of those is news.
				 *
				 * The elapsed time is the whole test.  It needs no notion of
				 * the worker having been healthy in between: a database that
				 * ran for a month before breaking was last reported a month
				 * ago, so it reports again.  Only a break within the hour after
				 * a previous report is quieted, and something breaking that
				 * often is flapping, where one line an hour is the right
				 * volume.  Asking instead whether the worker had been healthy
				 * cannot be answered here anyway - a worker that fails to
				 * connect still passes through BGWH_STARTED.
				 */
				report = (dbw->last_report == 0 ||
						  TimestampDifferenceExceeds(dbw->last_report, now,
													 SCHED_GIVEUP_REPORT_USEC / 1000));

				ereport(report ? LOG : DEBUG1,
						(errmsg("ivorysql scheduler for database \"%s\" stopped; not restarting it",
								dbw->dbname),
						 errhint("Address the cause reported above, then run"
								 " SELECT pg_reload_conf() to retry.")));
				if (report)
					dbw->last_report = now;
				pfree(dbw->handle);
				dbw->handle = NULL;
				dbw->gave_up = true;
			}
		}

		/* stop workers for databases no longer listed */
		foreach(lc, dbworkers)
		{
			SchedDbWorker *dbw = (SchedDbWorker *) lfirst(lc);

			if (!dbw->active && dbw->handle != NULL)
			{
				TerminateBackgroundWorker(dbw->handle);
				pfree(dbw->handle);
				dbw->handle = NULL;
			}
		}

		(void) WaitLatch(MyLatch,
						 WL_LATCH_SET | WL_TIMEOUT | WL_EXIT_ON_PM_DEATH,
						 10 * 1000L,
						 PG_WAIT_EXTENSION);
		ResetLatch(MyLatch);
	}

	ereport(LOG,
			(errmsg("ivorysql scheduler launcher shutting down")));
	proc_exit(0);
}

/* ------------------------------------------------------------------
 * Per-database scheduler worker
 * ------------------------------------------------------------------
 */

/* One due job picked up by the dispatch query */
typedef struct SchedDueJob
{
	int64		job_id;
	int64		log_id;
	char	   *job_owner;
	Oid			roloid;
} SchedDueJob;

/* Track the job workers this database scheduler has spawned. */
typedef struct SchedJobSlot
{
	BackgroundWorkerHandle *handle;
	bool		in_use;
} SchedJobSlot;

static SchedJobSlot *job_slots = NULL;

static int
scheduler_free_job_slots(void)
{
	int			free_count = 0;
	int			i;

	for (i = 0; i < scheduler_max_job_workers; i++)
	{
		if (job_slots[i].in_use)
		{
			pid_t		pid;
			BgwHandleStatus status;

			status = GetBackgroundWorkerPid(job_slots[i].handle, &pid);
			if (status == BGWH_STOPPED)
			{
				pfree(job_slots[i].handle);
				job_slots[i].handle = NULL;
				job_slots[i].in_use = false;
			}
		}
		if (!job_slots[i].in_use)
			free_count++;
	}
	return free_count;
}

static bool
scheduler_spawn_job_worker(Oid dboid, SchedDueJob *job)
{
	BackgroundWorker worker;
	BackgroundWorkerHandle *handle;
	SchedWorkerArgs args;
	MemoryContext oldcxt;
	int			i;

	for (i = 0; i < scheduler_max_job_workers; i++)
	{
		if (!job_slots[i].in_use)
			break;
	}
	if (i >= scheduler_max_job_workers)
		return false;

	args.dboid = dboid;
	args.roloid = job->roloid;
	args.job_id = job->job_id;
	args.log_id = job->log_id;

	MemSet(&worker, 0, sizeof(worker));
	worker.bgw_flags = BGWORKER_SHMEM_ACCESS |
		BGWORKER_BACKEND_DATABASE_CONNECTION;
	worker.bgw_start_time = BgWorkerStart_RecoveryFinished;
	worker.bgw_restart_time = BGW_NEVER_RESTART;
	snprintf(worker.bgw_library_name, BGW_MAXLEN, "ivorysql_ora");
	snprintf(worker.bgw_function_name, BGW_MAXLEN, "SchedulerJobWorkerMain");
	snprintf(worker.bgw_name, BGW_MAXLEN,
			 "ivorysql scheduler job " INT64_FORMAT, job->job_id);
	snprintf(worker.bgw_type, BGW_MAXLEN, "ivorysql scheduler job worker");
	StaticAssertStmt(sizeof(SchedWorkerArgs) <= BGW_EXTRALEN,
					 "SchedWorkerArgs must fit into bgw_extra");
	memcpy(worker.bgw_extra, &args, sizeof(args));
	worker.bgw_main_arg = (Datum) 0;
	worker.bgw_notify_pid = MyProcPid;

	oldcxt = MemoryContextSwitchTo(TopMemoryContext);
	if (!RegisterDynamicBackgroundWorker(&worker, &handle))
	{
		MemoryContextSwitchTo(oldcxt);
		ereport(LOG,
				(errmsg("could not start job worker for job " INT64_FORMAT ": out of background worker slots",
						job->job_id)));
		return false;
	}
	MemoryContextSwitchTo(oldcxt);

	job_slots[i].handle = handle;
	job_slots[i].in_use = true;
	return true;
}

/*
 * Is the error the polling loop just caught worth another cycle?
 *
 * Resource shortages and transaction rollbacks clear up on their own, so
 * waiting them out keeps a momentary shortage from taking this database's
 * scheduling down until someone reloads.  A renamed metadata table or a
 * revoked privilege does not clear up, and retrying it would only bury the
 * reason under copies of itself - the polling loop reports every failed cycle.
 *
 * Class 53 covers out of memory, disk full and the connection/program limits;
 * class 40 covers deadlocks and serialization failures.  Class 58 (I/O errors)
 * is deliberately not here: those tend to mean real trouble, where stopping to
 * be noticed beats retrying.
 */
static bool
sched_error_is_transient(int sqlerrcode)
{
	switch (ERRCODE_TO_CATEGORY(sqlerrcode))
	{
		case ERRCODE_TO_CATEGORY(ERRCODE_INSUFFICIENT_RESOURCES):
		case ERRCODE_TO_CATEGORY(ERRCODE_T_R_SERIALIZATION_FAILURE):
			return true;
	}

	/*
	 * Class 55 as a whole is not transient, but a lock timeout is.  Nothing
	 * here can raise this: none of the scheduler's statements use NOWAIT or
	 * FOR UPDATE, so it needs lock_timeout to have been set from outside.
	 * Unlike statement_timeout, which is never armed in a background worker,
	 * lock_timeout is armed by the lock manager in ProcSleep(), so it does
	 * reach us.  Listed for that case rather than for a known path.
	 */
	return sqlerrcode == ERRCODE_LOCK_NOT_AVAILABLE;
}

/*
 * Mark leftover 'r' log rows as failed.  They can only result from a crash
 * or shutdown while jobs were running (job workers write their outcome in a
 * separate transaction after the run).
 */
static void
scheduler_cleanup_orphans(void)
{
	int			rc;

	SetCurrentStatementStartTimestamp();
	StartTransactionCommand();
	PushActiveSnapshot(GetTransactionSnapshot());
	SPI_connect();

	rc = SPI_execute("UPDATE sys.scheduler_job_run_details"
					 " SET status = 'f',"
					 " error_message = 'job execution was interrupted (server or scheduler restart)'"
					 " WHERE status = 'r'",
					 false, 0);
	if (rc < 0)
		elog(ERROR, "orphan cleanup failed: %s", SPI_result_code_string(rc));
	if (SPI_processed > 0)
		ereport(LOG,
				(errmsg("ivorysql scheduler: marked " UINT64_FORMAT " interrupted job run(s) as failed",
						(uint64) SPI_processed)));

	/* jobs stuck in RUNNING revert to their scheduled/disabled state */
	rc = SPI_execute("UPDATE sys.scheduler_jobs"
					 " SET state = CASE WHEN enabled THEN 'SCHEDULED' ELSE 'DISABLED' END"
					 " WHERE state = 'RUNNING'",
					 false, 0);
	if (rc < 0)
		elog(ERROR, "orphan cleanup failed: %s", SPI_result_code_string(rc));

	SPI_finish();
	PopActiveSnapshot();
	CommitTransactionCommand();
}

/*
 * Find due jobs, advance their schedule and create their 'r' log rows in one
 * transaction, then hand back the list for dispatching.  Limited to "limit"
 * jobs (the number of free job worker slots).
 */
/* All fields of one due job, copied out of the SPI result */
typedef struct SchedDueRow
{
	int64		job_id;
	char	   *job_owner;
	char	   *job_name;
	TimestampTz req_start;
	TimestampTz start_date;
	bool		start_isnull;
	char	   *repeat_interval;
	TimestampTz end_date;
	bool		end_isnull;
} SchedDueRow;

/*
 * Take out a job whose stored definition cannot be used.  Mirrors what Oracle
 * would report as a BROKEN job; we have no such state, so the job is simply
 * disabled and removed from the schedule until someone fixes it and re-enables
 * it.
 */
static void
sched_disable_broken_job(const char *job_owner, const char *job_name)
{
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];

	values[0] = CStringGetTextDatum(job_owner);
	values[1] = CStringGetTextDatum(job_name);
	sched_meta_dml("UPDATE sys.scheduler_jobs SET enabled = false,"
				   " state = 'DISABLED', next_run_date = NULL"
				   " WHERE job_owner = $1 AND job_name = $2",
				   2, argtypes, values, NULL);
}

/*
 * Claim one due job: work out its following run, advance the schedule, mark it
 * running and write its 'r' log row.  On success the job is appended to *due,
 * allocated in caller_ctx.
 *
 * Raises an error on unusable job data (an unparsable calendar string, say).
 * The caller runs this inside a subtransaction and disables the job rather
 * than letting the error reach bgworker.c's top-level handler, which would
 * take down this whole worker.
 */
static void
sched_claim_one_job(SchedDueRow *row, MemoryContext caller_ctx, List **due)
{
	TimestampTz next = 0;
	bool		has_next = false;
	Oid			roloid;

	/* compute the following run, anchored at start_date */
	if (row->repeat_interval != NULL)
	{
		TimestampTz anchor = row->start_isnull ? row->req_start : row->start_date;

		has_next = sched_calendar_next(row->repeat_interval, anchor,
									   GetCurrentTimestamp(), &next);
		if (has_next && !row->end_isnull && next > row->end_date)
			has_next = false;
	}

	roloid = get_role_oid(row->job_owner, true);
	if (!OidIsValid(roloid))
	{
		ereport(LOG,
				(errmsg("disabling scheduler job \"%s\".\"%s\": owner role does not exist",
						row->job_owner, row->job_name)));
		sched_disable_broken_job(row->job_owner, row->job_name);
		return;
	}

	/* advance / exhaust the schedule and mark the job running */
	{
		Oid			at3[3] = {INT8OID, TIMESTAMPTZOID, BOOLOID};
		Datum		v3[3];
		char		n3[3];

		v3[0] = Int64GetDatum(row->job_id);
		v3[1] = TimestampTzGetDatum(next);
		v3[2] = BoolGetDatum(has_next);
		n3[0] = ' ';
		n3[1] = has_next ? ' ' : 'n';
		n3[2] = ' ';
		sched_meta_dml("UPDATE sys.scheduler_jobs SET"
					   " next_run_date = $2, enabled = $3,"
					   " state = 'RUNNING'"
					   " WHERE job_id = $1",
					   3, at3, v3, n3);
	}

	/* create the running-log row */
	{
		Oid			at4[4] = {TEXTOID, TEXTOID, INT8OID, TIMESTAMPTZOID};
		Datum		v4[4];
		bool		isnull;
		int64		log_id;
		SchedDueJob *job;
		MemoryContext oldcxt;

		v4[0] = CStringGetTextDatum(row->job_owner);
		v4[1] = CStringGetTextDatum(row->job_name);
		v4[2] = Int64GetDatum(row->job_id);
		v4[3] = TimestampTzGetDatum(row->req_start);
		if (sched_meta_dml("INSERT INTO sys.scheduler_job_run_details"
						   " (job_owner, job_name, job_id, status, req_start_date)"
						   " VALUES ($1, $2, $3, 'r', $4)"
						   " RETURNING log_id",
						   4, at4, v4, NULL) != 1)
			elog(ERROR, "could not insert job run log record");
		log_id = DatumGetInt64(SPI_getbinval(SPI_tuptable->vals[0],
											 SPI_tuptable->tupdesc,
											 1, &isnull));

		oldcxt = MemoryContextSwitchTo(caller_ctx);
		job = (SchedDueJob *) palloc0(sizeof(SchedDueJob));
		job->job_id = row->job_id;
		job->log_id = log_id;
		job->job_owner = pstrdup(row->job_owner);
		job->roloid = roloid;
		*due = lappend(*due, job);
		MemoryContextSwitchTo(oldcxt);
	}
}

static List *
scheduler_claim_due_jobs(int limit)
{
	List	   *due = NIL;
	Oid			argtypes[1] = {INT4OID};
	Datum		values[1] = {Int32GetDatum(limit)};
	uint64		nrows;
	uint64		i;
	SchedDueRow *rows;
	MemoryContext caller_ctx = CurrentMemoryContext;
	MemoryContext oldcxt;

	/*
	 * Without this, now() would stay frozen at this worker's start time
	 * (background workers do not go through the frontend statement loop).
	 */
	SetCurrentStatementStartTimestamp();
	StartTransactionCommand();
	PushActiveSnapshot(GetTransactionSnapshot());
	SPI_connect();

	/*
	 * Named-program jobs carry their calendar on the referenced schedule;
	 * inline jobs carry it themselves.
	 */
	nrows = sched_meta_select("SELECT j.job_id, j.job_owner, j.job_name,"
							  " j.next_run_date,"
							  " COALESCE(j.start_date, s.start_date),"
							  " COALESCE(j.repeat_interval, s.repeat_interval),"
							  " COALESCE(j.end_date, s.end_date)"
							  " FROM sys.scheduler_jobs j"
							  " LEFT JOIN sys.scheduler_schedules s"
							  "  ON s.schedule_owner = j.schedule_owner"
							  "  AND s.schedule_name = j.schedule_name"
							  " WHERE j.enabled AND j.next_run_date <= now()"
							  " ORDER BY j.next_run_date"
							  " LIMIT $1",
							  1, argtypes, values, NULL);

	/*
	 * Copy the result set before issuing any further SPI statement: those
	 * would replace SPI_tuptable under us.  The copy goes into the caller's
	 * context rather than the SPI procedure context so that it also outlives
	 * the per-job subtransaction rollbacks below.
	 */
	oldcxt = MemoryContextSwitchTo(caller_ctx);
	rows = (SchedDueRow *) palloc0(sizeof(SchedDueRow) * Max(nrows, 1));
	MemoryContextSwitchTo(oldcxt);
	for (i = 0; i < nrows; i++)
	{
		HeapTuple	tup = SPI_tuptable->vals[i];
		TupleDesc	desc = SPI_tuptable->tupdesc;
		bool		isnull;
		char	   *owner = SPI_getvalue(tup, desc, 2);
		char	   *name = SPI_getvalue(tup, desc, 3);
		char	   *interval = SPI_getvalue(tup, desc, 6);

		rows[i].job_id = DatumGetInt64(SPI_getbinval(tup, desc, 1, &isnull));
		rows[i].req_start = DatumGetTimestampTz(SPI_getbinval(tup, desc, 4, &isnull));
		rows[i].start_date = DatumGetTimestampTz(SPI_getbinval(tup, desc, 5,
															   &rows[i].start_isnull));
		rows[i].end_date = DatumGetTimestampTz(SPI_getbinval(tup, desc, 7,
															 &rows[i].end_isnull));

		oldcxt = MemoryContextSwitchTo(caller_ctx);
		rows[i].job_owner = pstrdup(owner);
		rows[i].job_name = pstrdup(name);
		rows[i].repeat_interval = interval ? pstrdup(interval) : NULL;
		MemoryContextSwitchTo(oldcxt);
	}

	for (i = 0; i < nrows; i++)
	{
		MemoryContext subcxt = CurrentMemoryContext;
		ResourceOwner oldowner = CurrentResourceOwner;

		/*
		 * Claim each job in its own subtransaction, so that unusable job data
		 * only costs that one job.
		 *
		 * A subtransaction rather than the abort-and-restart that
		 * do_autovacuum() uses for its per-table errors: all jobs of one cycle
		 * are claimed in a single transaction here, so aborting it outright
		 * would also roll back the rows already written for the jobs sitting
		 * in "due", whose log_id values are about to be handed to job workers.
		 */
		BeginInternalSubTransaction(NULL);
		MemoryContextSwitchTo(subcxt);

		PG_TRY();
		{
			sched_claim_one_job(&rows[i], caller_ctx, &due);

			ReleaseCurrentSubTransaction();
			MemoryContextSwitchTo(subcxt);
			CurrentResourceOwner = oldowner;
		}
		PG_CATCH();
		{
			ErrorData  *edata;

			/* the error data must outlive the subtransaction it was raised in */
			MemoryContextSwitchTo(caller_ctx);
			edata = CopyErrorData();
			FlushErrorState();

			RollbackAndReleaseCurrentSubTransaction();
			MemoryContextSwitchTo(subcxt);
			CurrentResourceOwner = oldowner;

			/*
			 * The rollback undid this job's claim and, incidentally, the
			 * metadata-owner privileges sched_meta_dml() may have been holding
			 * when the error hit (AbortSubTransaction restores the user ID).
			 * Take the job out of the schedule so the next cycle does not trip
			 * over it again.
			 */
			ereport(LOG,
					(errmsg("disabling scheduler job \"%s\".\"%s\": its schedule cannot be evaluated",
							rows[i].job_owner, rows[i].job_name),
					 errdetail_internal("%s", edata->message)));
			FreeErrorData(edata);
			sched_disable_broken_job(rows[i].job_owner, rows[i].job_name);
		}
		PG_END_TRY();
	}

	SPI_finish();
	PopActiveSnapshot();
	CommitTransactionCommand();

	return due;
}

void
SchedulerDatabaseWorkerMain(Datum main_arg)
{
	char		dbname[NAMEDATALEN];
	MemoryContext worker_ctx;
	volatile int cycle_failures = 0;

	strlcpy(dbname, MyBgworkerEntry->bgw_extra, NAMEDATALEN);

	pqsignal(SIGHUP, SignalHandlerForConfigReload);
	pqsignal(SIGTERM, die);
	BackgroundWorkerUnblockSignals();

	/* connect as the bootstrap superuser: sees and runs everyone's jobs */
	BackgroundWorkerInitializeConnection(dbname, NULL, 0);

	/* bail out quietly when this database has no scheduler metadata */
	SetCurrentStatementStartTimestamp();
	StartTransactionCommand();
	if (!OidIsValid(get_extension_oid("ivorysql_ora", true)))
	{
		CommitTransactionCommand();
		ereport(LOG,
				(errmsg("ivorysql scheduler: extension ivorysql_ora is not installed in database \"%s\", exiting",
						dbname),
				 errhint("Run CREATE EXTENSION ivorysql_ora in that database,"
						 " then SELECT pg_reload_conf().")));
		proc_exit(0);
	}
	CommitTransactionCommand();

	worker_ctx = AllocSetContextCreate(TopMemoryContext,
									   "scheduler database worker",
									   ALLOCSET_DEFAULT_SIZES);

	job_slots = (SchedJobSlot *)
		MemoryContextAllocZero(TopMemoryContext,
							   sizeof(SchedJobSlot) * scheduler_max_job_workers);

	ereport(LOG,
			(errmsg("ivorysql scheduler started for database \"%s\"", dbname)));

	scheduler_cleanup_orphans();

	for (;;)
	{
		List	   *due;
		ListCell   *lc;
		int			free_slots;

		CHECK_FOR_INTERRUPTS();

		if (ConfigReloadPending)
		{
			ConfigReloadPending = false;
			ProcessConfigFile(PGC_SIGHUP);
		}

		/* per-cycle allocations (job slots live in TopMemoryContext) */
		MemoryContextSwitchTo(worker_ctx);
		MemoryContextReset(worker_ctx);

		/*
		 * Keep going after an unforeseen error instead of letting it reach
		 * bgworker.c's top-level handler, which reports it and exits.
		 * Surviving a transient failure matters because the launcher no longer
		 * restarts a worker that quit.
		 *
		 * Only errors that can actually clear up earn that patience; see
		 * sched_error_is_transient().  Anything else exits on the first
		 * report.  Even a transient cause gives up eventually, since one that
		 * has not cleared in SCHED_MAX_CYCLE_FAILURES cycles is not going to.
		 * That last limit needs a persistent resource shortage to reach, which
		 * is why it is covered by inspection rather than by a test.
		 */
		PG_TRY();
		{
			free_slots = scheduler_free_job_slots();
			if (free_slots > 0)
			{
				due = scheduler_claim_due_jobs(free_slots);

				foreach(lc, due)
				{
					SchedDueJob *job = (SchedDueJob *) lfirst(lc);

					if (!scheduler_spawn_job_worker(MyDatabaseId, job))
					{
						/*
						 * Out of worker slots: the run was already claimed, so
						 * close its log row as failed rather than leaving it
						 * dangling.  The job itself stays scheduled for its
						 * next run date.
						 */
						SetCurrentStatementStartTimestamp();
						StartTransactionCommand();
						PushActiveSnapshot(GetTransactionSnapshot());
						SPI_connect();
						sched_log_finish(job->log_id, false, 0,
										 "no free background worker slots",
										 GetCurrentTimestamp());
						SPI_finish();
						PopActiveSnapshot();
						CommitTransactionCommand();
					}
				}
			}
			cycle_failures = 0;
		}
		PG_CATCH();
		{
			ErrorData  *edata;
			bool		transient;

			HOLD_INTERRUPTS();
			EmitErrorReport();	/* report it as raised, once */

			/* the code has to be read before the error state is flushed */
			MemoryContextSwitchTo(worker_ctx);
			edata = CopyErrorData();
			transient = sched_error_is_transient(edata->sqlerrcode);
			FreeErrorData(edata);

			AbortOutOfAnyTransaction();
			FlushErrorState();
			MemoryContextSwitchTo(worker_ctx);

			/*
			 * A cancel aimed at the statement we just abandoned would
			 * otherwise fire during the next cycle.
			 */
			QueryCancelPending = false;
			RESUME_INTERRUPTS();

			if (!transient)
			{
				ereport(LOG,
						(errmsg("ivorysql scheduler for database \"%s\" cannot continue, exiting",
								dbname)));
				proc_exit(1);
			}

			if (++cycle_failures >= SCHED_MAX_CYCLE_FAILURES)
			{
				ereport(LOG,
						(errmsg("ivorysql scheduler for database \"%s\" failed %d consecutive cycles, exiting",
								dbname, cycle_failures)));
				proc_exit(1);
			}
		}
		PG_END_TRY();

		(void) WaitLatch(MyLatch,
						 WL_LATCH_SET | WL_TIMEOUT | WL_EXIT_ON_PM_DEATH,
						 scheduler_poll_interval * 1000L,
						 PG_WAIT_EXTENSION);
		ResetLatch(MyLatch);
	}
}
