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
 * dbms_scheduler.h
 *
 * Shared declarations for the Oracle-compatible DBMS_SCHEDULER package:
 * calendar syntax engine, job execution and the scheduler background
 * workers.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_scheduler/dbms_scheduler.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef DBMS_SCHEDULER_H
#define DBMS_SCHEDULER_H

#include "datatype/timestamp.h"
#include "postmaster/bgworker.h"

/*
 * Identifier length limit for scheduler object names.  The metadata tables
 * store names as type "name" (so the initdb-created indexes satisfy the
 * catalog sanity checks), which caps them at NAMEDATALEN - 1 like every
 * other IvorySQL identifier.
 */
#define SCHED_MAX_NAME_LEN		(NAMEDATALEN - 1)

/* Upper bound of program/job arguments (Oracle: 255) */
#define SCHED_MAX_ARGS			255

/*
 * scheduler_calendar.c
 */

/*
 * Compute the first timestamp that satisfies calendar string "calendar",
 * anchored at "start_date", that is strictly greater than "after" (and not
 * before "start_date").  Returns false when no such timestamp exists within
 * the search horizon (e.g. FREQ=MONTHLY;BYMONTH=2;BYMONTHDAY=31).
 * Malformed calendar strings raise an error.
 */
extern bool sched_calendar_next(const char *calendar, TimestampTz start_date,
								TimestampTz after, TimestampTz *next);

/* Validate calendar string syntax; raises an error when malformed. */
extern void sched_calendar_validate(const char *calendar);

/*
 * scheduler_worker.c - job execution shared by RUN_JOB and the background
 * job worker.
 */

typedef struct SchedJobDef
{
	int64		job_id;
	char	   *job_owner;
	char	   *job_name;
	char	   *job_type;		/* PLSQL_BLOCK or STORED_PROCEDURE */
	char	   *job_action;
	int			number_of_arguments;
	char	  **arg_values;		/* argument values (NULL element = no value) */
} SchedJobDef;

extern void sched_execute_job(SchedJobDef *job);

/* SYS_CONTEXT('USERENV', ...) job identity, set while a job is running */
extern int64 sched_bg_job_id;	/* <= 0: not inside a background job */
extern int64 sched_fg_job_id;	/* <= 0: not inside RUN_JOB */
extern char sched_job_name[SCHED_MAX_NAME_LEN + 1]; /* "" when unset */

/* Arguments passed to a job worker through bgw_extra */
typedef struct SchedWorkerArgs
{
	Oid			dboid;
	Oid			roloid;			/* job owner */
	int64		job_id;
	int64		log_id;			/* pre-created 'r' log row */
} SchedWorkerArgs;

/*
 * dbms_scheduler.c - metadata helpers shared with the background workers.
 * The _dml/_select variants run with the metadata tables' owner rights;
 * the caller must be connected to SPI.
 */
extern uint64 sched_meta_dml(const char *sql, int nargs, Oid *argtypes,
							 Datum *values, const char *nulls);
extern uint64 sched_meta_select(const char *sql, int nargs, Oid *argtypes,
								Datum *values, const char *nulls);
extern bool sched_load_job_by_id(int64 job_id, SchedJobDef *def);
extern void sched_log_finish(int64 log_id, bool success, int error_no,
							 const char *error_message,
							 TimestampTz actual_start);
extern void sched_update_job_stats(const SchedJobDef *def, bool success,
								   TimestampTz actual_start, bool background);

/*
 * scheduler_launcher.c
 */

/* GUC variables (defined in scheduler_launcher.c, registered in guc.c) */
extern bool scheduler_enabled;
extern char *scheduler_databases;
extern int	scheduler_poll_interval;
extern int	scheduler_max_job_workers;
extern int	scheduler_job_timeout;

extern void SchedulerLauncherRegister(void);

/* bgworker entry points, looked up by name in the shared library */
extern PGDLLEXPORT pg_noreturn void SchedulerLauncherMain(Datum main_arg);
extern PGDLLEXPORT pg_noreturn void SchedulerDatabaseWorkerMain(Datum main_arg);
extern PGDLLEXPORT pg_noreturn void SchedulerJobWorkerMain(Datum main_arg);

/* Set when the launcher was registered at shared_preload time */
extern bool scheduler_launcher_registered;

#endif							/* DBMS_SCHEDULER_H */
