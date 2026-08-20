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
 * scheduler_worker.c
 *
 * DBMS_SCHEDULER job execution.  sched_execute_job() renders and runs a
 * job's action and is shared between RUN_JOB (current session) and the
 * background job worker, which executes one due job as the job owner and
 * records the outcome in sys.scheduler_job_run_details.
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_scheduler/scheduler_worker.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "executor/spi.h"
#include "miscadmin.h"
#include "nodes/miscnodes.h"
#include "parser/parse_type.h"
#include "pgstat.h"
#include "postmaster/bgworker.h"
#include "postmaster/interrupt.h"
#include "storage/ipc.h"
#include "storage/latch.h"
#include "storage/proc.h"
#include "tcop/tcopprot.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/snapmgr.h"
#include "utils/timeout.h"
#include "utils/timestamp.h"

#include "dbms_scheduler.h"

/* SYS_CONTEXT('USERENV', ...) job identity */
int64		sched_bg_job_id = 0;
int64		sched_fg_job_id = 0;
char		sched_job_name[SCHED_MAX_NAME_LEN + 1] = "";

/*
 * sched_execute_job - render and execute a job action through SPI.
 *
 * The caller must be connected to SPI and inside a transaction.  The job
 * text is parsed with the oracle parser regardless of the current session
 * mode; the GUC change is scoped with a GUC nest level so it cannot leak.
 */
void
sched_execute_job(SchedJobDef *job)
{
	int			save_nestlevel;
	const char *sql;
	int			nparams = 0;
	Oid		   *paramtypes = NULL;
	Datum	   *paramvalues = NULL;
	char	   *paramnulls = NULL;
	int			rc;

	save_nestlevel = NewGUCNestLevel();
	(void) set_config_option("ivorysql.compatible_mode", "oracle",
							 PGC_USERSET, PGC_S_SESSION,
							 GUC_ACTION_SAVE, true, 0, false);

	if (strcmp(job->job_type, "STORED_PROCEDURE") == 0)
	{
		StringInfoData buf;
		int			i;

		if (job->number_of_arguments > 0)
		{
			paramtypes = palloc(sizeof(Oid) * job->number_of_arguments);
			paramvalues = palloc(sizeof(Datum) * job->number_of_arguments);
			paramnulls = palloc(sizeof(char) * job->number_of_arguments);
		}

		initStringInfo(&buf);
		appendStringInfo(&buf, "CALL %s(", job->job_action);
		for (i = 0; i < job->number_of_arguments; i++)
		{
			char	   *typename = job->arg_types ? job->arg_types[i] : NULL;
			ErrorSaveContext escontext = {T_ErrorSaveContext};
			Oid			typid = InvalidOid;
			int32		typmod = -1;

			if (i > 0)
				appendStringInfoString(&buf, ", ");

			/*
			 * Argument values are stored as text, so they have to be given a
			 * type on the way in.  The program's declared type is the right
			 * one: an untyped literal leaves the choice to the parser, which
			 * picks the wrong overload of a procedure that has several, and
			 * fails outright for a parameter type with no cast from unknown.
			 *
			 * The declared type is free text that nothing validated when it
			 * was recorded, so a name that does not resolve falls back to the
			 * literal form rather than failing the run.  parseTypeString is
			 * called under the oracle parser, so Oracle spellings such as
			 * NUMBER and VARCHAR2(10) resolve here.
			 */
			if (typename != NULL &&
				!parseTypeString(typename, &typid, &typmod,
								 (Node *) &escontext))
				typid = InvalidOid;

			if (!OidIsValid(typid))
			{
				if (job->arg_values[i] == NULL)
					appendStringInfoString(&buf, "NULL");
				else
					appendStringInfoString(&buf,
										   quote_literal_cstr(job->arg_values[i]));
				continue;
			}

			paramtypes[nparams] = typid;
			if (job->arg_values[i] == NULL)
			{
				paramvalues[nparams] = (Datum) 0;
				paramnulls[nparams] = 'n';
			}
			else
			{
				Oid			typinput;
				Oid			typioparam;

				getTypeInputInfo(typid, &typinput, &typioparam);
				paramvalues[nparams] = OidInputFunctionCall(typinput,
															job->arg_values[i],
															typioparam, typmod);
				paramnulls[nparams] = ' ';
			}
			nparams++;
			appendStringInfo(&buf, "$%d", nparams);
		}
		appendStringInfoChar(&buf, ')');
		sql = buf.data;
	}
	else
		sql = job->job_action;	/* PLSQL_BLOCK: anonymous block text */

	rc = SPI_execute_with_args(sql, nparams, paramtypes, paramvalues,
							   paramnulls, false, 0);
	if (rc < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("job \"%s\".\"%s\" execution failed: %s",
						job->job_owner, job->job_name,
						SPI_result_code_string(rc))));

	AtEOXact_GUC(true, save_nestlevel);
}

/* ------------------------------------------------------------------
 * Background job worker
 * ------------------------------------------------------------------
 */

/*
 * Execute one transaction's worth of metadata work in the worker.
 * Each helper below owns its transaction boundaries.
 */
static void
worker_finish_log(SchedWorkerArgs *args, bool success, int error_no,
				  const char *error_message, TimestampTz start_ts,
				  SchedJobDef *def)
{
	SetCurrentStatementStartTimestamp();
	StartTransactionCommand();
	PushActiveSnapshot(GetTransactionSnapshot());
	SPI_connect();

	sched_log_finish(args->log_id, success, error_no, error_message, start_ts);
	if (def != NULL)
		sched_update_job_stats(def, success, start_ts, true);

	SPI_finish();
	PopActiveSnapshot();
	CommitTransactionCommand();
}

void
SchedulerJobWorkerMain(Datum main_arg)
{
	SchedWorkerArgs args;
	SchedJobDef def;
	bool		found;
	TimestampTz start_ts;
	ErrorData  *edata = NULL;

	memcpy(&args, MyBgworkerEntry->bgw_extra, sizeof(args));

	pqsignal(SIGTERM, die);
	pqsignal(SIGHUP, SignalHandlerForConfigReload);
	BackgroundWorkerUnblockSignals();

	BackgroundWorkerInitializeConnectionByOid(args.dboid, args.roloid, 0);

	/* Job text is Oracle syntax; parse it with the oracle parser. */
	SetConfigOption("ivorysql.compatible_mode", "oracle",
					PGC_USERSET, PGC_S_SESSION);

	/* Transaction 1: load the job definition. */
	SetCurrentStatementStartTimestamp();
	StartTransactionCommand();
	PushActiveSnapshot(GetTransactionSnapshot());
	SPI_connect();
	found = false;
	PG_TRY();
	{
		/* let STOP_JOB find this process while the job runs */
		sched_log_set_worker_pid(args.log_id);

		found = sched_load_job_by_id(args.job_id, &def);
		if (found)
		{
			/* copy out of SPI memory before SPI_finish */
			MemoryContext oldcxt = MemoryContextSwitchTo(TopMemoryContext);
			SchedJobDef stable = def;
			int			i;

			stable.job_owner = pstrdup(def.job_owner);
			stable.job_name = pstrdup(def.job_name);
			stable.job_type = pstrdup(def.job_type);
			stable.job_action = pstrdup(def.job_action);
			if (def.number_of_arguments > 0)
			{
				stable.arg_values = palloc0(sizeof(char *) * def.number_of_arguments);
				stable.arg_types = palloc0(sizeof(char *) * def.number_of_arguments);
				for (i = 0; i < def.number_of_arguments; i++)
				{
					if (def.arg_values[i] != NULL)
						stable.arg_values[i] = pstrdup(def.arg_values[i]);
					if (def.arg_types != NULL && def.arg_types[i] != NULL)
						stable.arg_types[i] = pstrdup(def.arg_types[i]);
				}
			}
			def = stable;
			MemoryContextSwitchTo(oldcxt);
		}
		SPI_finish();
		PopActiveSnapshot();
		CommitTransactionCommand();
	}
	PG_CATCH();
	{
		MemoryContext oldcxt = MemoryContextSwitchTo(TopMemoryContext);

		edata = CopyErrorData();
		FlushErrorState();
		MemoryContextSwitchTo(oldcxt);

		AbortCurrentTransaction();
	}
	PG_END_TRY();

	if (edata != NULL)
	{
		/* e.g. the referenced program was dropped after dispatch */
		elog(LOG, "scheduler job worker: could not load job " INT64_FORMAT ": %s",
			 args.job_id, edata->message);
		worker_finish_log(&args, false, edata->sqlerrcode, edata->message,
						  GetCurrentTimestamp(), NULL);
		FreeErrorData(edata);
		proc_exit(0);
	}

	if (!found)
	{
		worker_finish_log(&args, false, ERRCODE_UNDEFINED_OBJECT,
						  "job was dropped before execution",
						  GetCurrentTimestamp(), NULL);
		proc_exit(0);
	}

	sched_bg_job_id = args.job_id;
	strlcpy(sched_job_name, def.job_name, sizeof(sched_job_name));

	elog(LOG, "scheduler job worker: running job \"%s\".\"%s\" (job_id " INT64_FORMAT ")",
		 def.job_owner, def.job_name, args.job_id);

	start_ts = GetCurrentTimestamp();

	/* Transaction 2: run the job. */
	SetCurrentStatementStartTimestamp();
	StartTransactionCommand();
	PushActiveSnapshot(GetTransactionSnapshot());
	SPI_connect();

	/*
	 * Bound the run time.  The STATEMENT_TIMEOUT handler is registered by
	 * InitPostgres, but what arms it for a regular backend is the frontend
	 * statement loop, which a background worker never enters -- so setting the
	 * statement_timeout GUC alone would have no effect and the timeout has to
	 * be armed here.  Firing it raises an ordinary query cancel, which the
	 * PG_CATCH below records like any other job failure.
	 */
	if (scheduler_job_timeout > 0)
		enable_timeout_after(STATEMENT_TIMEOUT, scheduler_job_timeout);

	PG_TRY();
	{
		sched_execute_job(&def);

		SPI_finish();
		PopActiveSnapshot();
		CommitTransactionCommand();
	}
	PG_CATCH();
	{
		MemoryContext oldcxt = MemoryContextSwitchTo(TopMemoryContext);

		edata = CopyErrorData();
		FlushErrorState();
		MemoryContextSwitchTo(oldcxt);

		AbortCurrentTransaction();
	}
	PG_END_TRY();

	if (scheduler_job_timeout > 0)
		disable_timeout(STATEMENT_TIMEOUT, false);

	/* Transaction 3: record the outcome. */
	if (edata == NULL)
		worker_finish_log(&args, true, 0, NULL, start_ts, &def);
	else
	{
		elog(LOG, "scheduler job \"%s\".\"%s\" failed: %s",
			 def.job_owner, def.job_name, edata->message);
		worker_finish_log(&args, false, edata->sqlerrcode, edata->message,
						  start_ts, &def);
		FreeErrorData(edata);
	}

	sched_bg_job_id = 0;
	sched_job_name[0] = '\0';

	proc_exit(0);
}
