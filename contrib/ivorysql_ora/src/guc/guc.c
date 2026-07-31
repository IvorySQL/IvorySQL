/*-------------------------------------------------------------------------
 * Copyright 2025 IvorySQL Global Development Team
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
 * guc.c
 *
 * Ivorysql_ora GUC variables define.
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/guc/guc.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <limits.h>

#include "utils/guc.h"

#include "../include/guc.h"
#include "../builtin_packages/dbms_scheduler/dbms_scheduler.h"


/*
 * Define various GUC.
 */
void
IvorysqlOraDefineGucs(void)
{
	/* DBMS_SCHEDULER background scheduling */
	DefineCustomBoolVariable("ivorysql_ora.scheduler",
							 "Enables the DBMS_SCHEDULER background launcher.",
							 NULL,
							 &scheduler_enabled,
							 false,
							 PGC_POSTMASTER,
							 0,
							 NULL, NULL, NULL);

	DefineCustomStringVariable("ivorysql_ora.scheduler_databases",
							   "Databases in which DBMS_SCHEDULER jobs are executed.",
							   "Comma-separated list of database names."
							   "  An empty list schedules jobs in no database.",
							   &scheduler_databases,
							   "",
							   PGC_SIGHUP,
							   GUC_LIST_INPUT,
							   NULL, NULL, NULL);

	DefineCustomIntVariable("ivorysql_ora.scheduler_poll_interval",
							"Interval between DBMS_SCHEDULER job polls, in seconds.",
							NULL,
							&scheduler_poll_interval,
							5,
							1,
							600,
							PGC_SIGHUP,
							GUC_UNIT_S,
							NULL, NULL, NULL);

	DefineCustomIntVariable("ivorysql_ora.scheduler_max_job_workers",
							"Maximum concurrent DBMS_SCHEDULER job workers per database.",
							NULL,
							&scheduler_max_job_workers,
							4,
							1,
							64,
							PGC_POSTMASTER,
							0,
							NULL, NULL, NULL);

	DefineCustomIntVariable("ivorysql_ora.scheduler_max_failures",
							"Disables a DBMS_SCHEDULER job after this many consecutive failed background runs.",
							"Zero disables the limit.  ENABLE clears a job's"
							" failure count, as it does in Oracle.",
							&scheduler_max_failures,
							0,
							0,
							INT_MAX,
							PGC_SIGHUP,
							0,
							NULL, NULL, NULL);

	DefineCustomIntVariable("ivorysql_ora.scheduler_job_timeout",
							"Cancels a background DBMS_SCHEDULER job that runs longer than this.",
							"Zero disables the limit.  Only background runs are"
							" affected; RUN_JOB obeys the calling session's"
							" statement_timeout instead.",
							&scheduler_job_timeout,
							0,
							0,
							INT_MAX,
							PGC_SIGHUP,
							GUC_UNIT_MS,
							NULL, NULL, NULL);
}
