/*
 * Copyright 2026 IvorySQL Global Development Team
 * Licensed under the Apache License, Version 2.0. See LICENSE.
 * A database-local, explicitly started collector; no shared preload required.
 */
#include "postgres.h"

#include "access/xact.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "pgstat.h"
#include "postmaster/bgworker.h"
#include "storage/ipc.h"
#include "storage/latch.h"
#include "tcop/tcopprot.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/snapmgr.h"
#include "utils/timeout.h"
#include "utils/wait_event.h"

PG_MODULE_MAGIC;
PG_FUNCTION_INFO_V1(ivorysql_perf_start);
pg_noreturn PGDLLEXPORT void ivorysql_perf_main(Datum main_arg);

Datum
ivorysql_perf_start(PG_FUNCTION_ARGS)
{
	BackgroundWorker worker = {0};
	BackgroundWorkerHandle *handle;
	Oid			database = MyDatabaseId;
	Oid			role = GetUserId();
	pid_t		pid;

	/* SQL EXECUTE privileges restrict this entry point to pg_monitor. */
	if (SPI_connect() != SPI_OK_CONNECT)
		elog(ERROR, "could not connect to SPI");
	SPI_execute("SELECT pg_catalog.pg_advisory_xact_lock(496751,1)", false, 0);
	SPI_execute("SELECT pg_catalog.pg_stat_clear_snapshot()", false, 0);
	SPI_execute("SELECT pid FROM pg_catalog.pg_stat_activity WHERE "
				"datname = pg_catalog.current_database() AND "
				"backend_type = 'ivorysql perf collector'", true, 1);
	if (SPI_processed != 0)
	{
		SPI_finish();
		PG_RETURN_VOID();
	}
	SPI_finish();
	worker.bgw_flags = BGWORKER_SHMEM_ACCESS | BGWORKER_BACKEND_DATABASE_CONNECTION;
	worker.bgw_start_time = BgWorkerStart_RecoveryFinished;
	worker.bgw_restart_time = BGW_NEVER_RESTART;
	worker.bgw_notify_pid = MyProcPid;
	snprintf(worker.bgw_name, BGW_MAXLEN, "ivorysql perf collector %u", database);
	strlcpy(worker.bgw_type, "ivorysql perf collector", BGW_MAXLEN);
	strlcpy(worker.bgw_library_name, "ivorysql_perf", BGW_MAXLEN);
	strlcpy(worker.bgw_function_name, "ivorysql_perf_main", BGW_MAXLEN);
	memcpy(worker.bgw_extra, &database, sizeof(Oid));
	memcpy(worker.bgw_extra + sizeof(Oid), &role, sizeof(Oid));
	if (!RegisterDynamicBackgroundWorker(&worker, &handle))
		ereport(ERROR, (errcode(ERRCODE_INSUFFICIENT_RESOURCES),
						errmsg("no background worker slot available"),
						errhint("Increase max_worker_processes.")));
	if (WaitForBackgroundWorkerStartup(handle, &pid) != BGWH_STARTED)
		ereport(ERROR, (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
						errmsg("performance collector could not start")));
	PG_RETURN_VOID();
}

void
ivorysql_perf_main(Datum main_arg)
{
	Oid			database;
	Oid			role;
	bool		isnull;
	bool		locked;
	uint32		event;

	memcpy(&database, MyBgworkerEntry->bgw_extra, sizeof(Oid));
	memcpy(&role, MyBgworkerEntry->bgw_extra + sizeof(Oid), sizeof(Oid));
	pqsignal(SIGTERM, die);
	BackgroundWorkerUnblockSignals();
	/* SET ROLE may legitimately select a NOLOGIN monitoring role. */
	BackgroundWorkerInitializeConnectionByOid(database, role, BGWORKER_BYPASS_ROLELOGINCHECK);
	SetConfigOption("ivorysql.compatible_mode", "pg", PGC_USERSET, PGC_S_SESSION);
	SetConfigOption("ivorysql.identifier_case_switch", "normal", PGC_USERSET, PGC_S_SESSION);
	SetConfigOption("search_path", "pg_catalog", PGC_USERSET, PGC_S_SESSION);
	SetConfigOption("application_name", "ivorysql_perf", PGC_USERSET, PGC_S_SESSION);
	SetConfigOption("statement_timeout", "5s", PGC_USERSET, PGC_S_SESSION);

	SetCurrentStatementStartTimestamp();
	StartTransactionCommand();
	PushActiveSnapshot(GetTransactionSnapshot());
	SPI_connect();
	SPI_execute("SELECT pg_catalog.pg_try_advisory_lock(496751,2)", false, 1);
	locked = DatumGetBool(SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &isnull));
	SPI_finish();
	PopActiveSnapshot();
	CommitTransactionCommand();
	if (!locked)
		proc_exit(0);

	event = WaitEventExtensionNew("IvorySQLPerfCollector");
	for (;;)
	{
		int			interval_ms;

		CHECK_FOR_INTERRUPTS();
		SetCurrentStatementStartTimestamp();
		StartTransactionCommand();
		PushActiveSnapshot(GetTransactionSnapshot());
		SPI_connect();
		enable_timeout_after(STATEMENT_TIMEOUT, 5000);
		pgstat_report_activity(STATE_RUNNING, "SELECT ivorysql_perf.collect_tick()");
		if (SPI_execute("SELECT ivorysql_perf.collect_tick()", false, 1) != SPI_OK_SELECT ||
			SPI_processed != 1)
			elog(ERROR, "performance collector did not return settings");
		interval_ms = DatumGetInt32(SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &isnull));
		if (isnull || interval_ms < 100 || interval_ms > 60000)
			elog(ERROR, "invalid performance collector interval");
		SPI_finish();
		disable_timeout(STATEMENT_TIMEOUT, false);
		PopActiveSnapshot();
		CommitTransactionCommand();
		pgstat_report_activity(STATE_IDLE, NULL);
		(void) WaitLatch(MyLatch, WL_LATCH_SET | WL_TIMEOUT | WL_EXIT_ON_PM_DEATH,
						 interval_ms, event);
		ResetLatch(MyLatch);
	}
}
