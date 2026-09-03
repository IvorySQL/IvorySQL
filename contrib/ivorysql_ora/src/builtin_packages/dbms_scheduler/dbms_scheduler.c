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
 * Implementation of Oracle's DBMS_SCHEDULER package (EDB-parity subset).
 * This module is part of ivorysql_ora extension.
 *
 * The metadata lives in ordinary sys.scheduler_* tables that carry no PUBLIC
 * privileges; users read their own objects through the USER_SCHEDULER_*
 * views.  Every write goes through these functions, which validate ownership
 * as the invoking user and then perform the DML with the rights of the
 * metadata tables' owner.
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_scheduler/dbms_scheduler.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "catalog/namespace.h"
#include "catalog/pg_class.h"
#include "catalog/pg_collation.h"
#include "catalog/pg_type.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "storage/latch.h"
#include "storage/proc.h"
#include "storage/procarray.h"
#include "utils/acl.h"
#include "utils/builtins.h"
#include "utils/fmgrprotos.h"
#include "utils/formatting.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/resowner.h"
#include "utils/syscache.h"
#include "utils/timestamp.h"
#include "utils/varlena.h"

#include "dbms_scheduler.h"

/* Scheduler object kinds, as stored in the metadata tables */
#define SCHED_KIND_NONE		'\0'
#define SCHED_KIND_JOB		'J'
#define SCHED_KIND_PROGRAM	'P'
#define SCHED_KIND_SCHEDULE	'S'

typedef struct SchedName
{
	char	   *owner;			/* role name (verified to exist) */
	char	   *name;			/* normalized object name */
} SchedName;

/* SQL-callable function declarations */
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_create_job_inline);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_create_job_named);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_create_program);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_create_schedule);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_define_program_argument);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_drop_program_argument_pos);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_drop_program_argument_name);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_enable);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_disable);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_drop_job);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_drop_program);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_drop_schedule);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_evaluate_calendar_string);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_purge_log);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_run_job);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_stop_job);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_set_job_argument_value_pos);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_set_job_argument_value_name);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_get_bg_job_id);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_get_fg_job_id);
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_get_scheduler_job);

/* ------------------------------------------------------------------
 * Small helpers
 * ------------------------------------------------------------------
 */

/*
 * Owner of the scheduler metadata tables (the role that created the
 * ivorysql_ora extension).  Metadata DML runs with this identity so plain
 * users need no direct table privileges.
 */
static Oid
sched_metadata_owner(void)
{
	Oid			nspoid;
	Oid			reloid;
	HeapTuple	tup;
	Oid			owner;

	nspoid = get_namespace_oid("sys", false);
	reloid = get_relname_relid("scheduler_jobs", nspoid);
	if (!OidIsValid(reloid))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_TABLE),
				 errmsg("scheduler metadata table \"sys.scheduler_jobs\" does not exist")));

	tup = SearchSysCache1(RELOID, ObjectIdGetDatum(reloid));
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for relation %u", reloid);
	owner = ((Form_pg_class) GETSTRUCT(tup))->relowner;
	ReleaseSysCache(tup);

	return owner;
}

static void
sched_escalate(Oid *save_userid, int *save_sec_context)
{
	GetUserIdAndSecContext(save_userid, save_sec_context);
	SetUserIdAndSecContext(sched_metadata_owner(),
						   *save_sec_context |
						   SECURITY_LOCAL_USERID_CHANGE |
						   SECURITY_RESTRICTED_OPERATION);
}

static void
sched_restore(Oid save_userid, int save_sec_context)
{
	SetUserIdAndSecContext(save_userid, save_sec_context);
}

/*
 * Execute one SPI statement with arguments under the metadata owner's
 * identity.  Returns the number of processed rows.
 */
uint64
sched_meta_dml(const char *sql, int nargs, Oid *argtypes, Datum *values,
		  const char *nulls)
{
	Oid			save_userid;
	int			save_sec_context;
	int			rc;
	uint64		processed;

	sched_escalate(&save_userid, &save_sec_context);

	rc = SPI_execute_with_args(sql, nargs, argtypes, values, nulls,
							   false, 0);
	if (rc < 0)
		elog(ERROR, "SPI_execute_with_args failed: %s", SPI_result_code_string(rc));
	processed = SPI_processed;

	sched_restore(save_userid, save_sec_context);

	return processed;
}

/*
 * Query variant; result rows stay valid until the next SPI call.
 *
 * Executed with read_only = false so that rows written earlier in the same
 * statement are visible (e.g. CREATE_JOB(enabled => TRUE) inserts the job
 * and then enables it).
 */
uint64
sched_meta_select(const char *sql, int nargs, Oid *argtypes, Datum *values,
			 const char *nulls)
{
	Oid			save_userid;
	int			save_sec_context;
	int			rc;

	sched_escalate(&save_userid, &save_sec_context);

	rc = SPI_execute_with_args(sql, nargs, argtypes, values, nulls,
							   false, 0);
	if (rc < 0)
		elog(ERROR, "SPI_execute_with_args failed: %s", SPI_result_code_string(rc));

	sched_restore(save_userid, save_sec_context);

	return SPI_processed;
}

/* Fetch a text column from the given SPI result row; NULL when SQL NULL. */
static char *
sched_getstring(int row, int col)
{
	return SPI_getvalue(SPI_tuptable->vals[row], SPI_tuptable->tupdesc, col);
}

static Datum
sched_getdatum(int row, int col, bool *isnull)
{
	return SPI_getbinval(SPI_tuptable->vals[row], SPI_tuptable->tupdesc,
						 col, isnull);
}

static char *
text_arg_or_null(FunctionCallInfo fcinfo, int argno)
{
	if (PG_ARGISNULL(argno))
		return NULL;
	return text_to_cstring(PG_GETARG_TEXT_PP(argno));
}

/* ------------------------------------------------------------------
 * Object name handling
 * ------------------------------------------------------------------
 */

/*
 * Extract one identifier part starting at *pp; advances *pp past the part.
 * Unquoted identifiers are upper-cased, double-quoted identifiers keep
 * their exact spelling.
 */
static char *
sched_parse_name_part(const char **pp, const char *raw, const char *what)
{
	const char *p = *pp;
	StringInfoData buf;

	initStringInfo(&buf);

	if (*p == '"')
	{
		p++;
		for (;;)
		{
			if (*p == '\0')
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_NAME),
						 errmsg("invalid %s name \"%s\"", what, raw),
						 errdetail("Unterminated quoted identifier.")));
			if (*p == '"')
			{
				if (p[1] == '"')	/* embedded doubled quote */
				{
					appendStringInfoChar(&buf, '"');
					p += 2;
					continue;
				}
				p++;
				break;
			}
			appendStringInfoChar(&buf, *p);
			p++;
		}
	}
	else
	{
		while (*p != '\0' && *p != '.')
		{
			appendStringInfoChar(&buf, pg_toupper((unsigned char) *p));
			p++;
		}

		/*
		 * Whitespace around an unquoted identifier is not part of it, the way
		 * Oracle reads "reg_job " and "owner . name".  Only the trailing side
		 * is handled here: the leading one was skipped before this part
		 * started.
		 */
		while (buf.len > 0 &&
			   (buf.data[buf.len - 1] == ' ' || buf.data[buf.len - 1] == '\t'))
			buf.data[--buf.len] = '\0';
	}

	if (buf.len == 0 || buf.len > SCHED_MAX_NAME_LEN)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_NAME),
				 errmsg("invalid %s name \"%s\"", what, raw)));

	*pp = p;
	return buf.data;
}

/*
 * Normalize a single identifier (no owner qualification allowed), e.g. an
 * argument name.
 */
static char *
sched_normalize_simple(const char *raw, const char *what)
{
	const char *p = raw;
	char	   *result;

	result = sched_parse_name_part(&p, raw, what);
	while (*p == ' ' || *p == '\t')
		p++;
	if (*p != '\0')
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_NAME),
				 errmsg("invalid %s name \"%s\"", what, raw)));
	return result;
}

/*
 * Parse an Oracle-style scheduler object name: NAME, OWNER.NAME, with either
 * part optionally double-quoted.  The owner defaults to the invoking user;
 * naming another user's objects requires superuser.
 */
static void
sched_parse_name(const char *raw, const char *what, SchedName *result)
{
	const char *p;
	char	   *part1;
	char	   *part2 = NULL;

	if (raw == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_NAME),
				 errmsg("%s name must not be null", what)));

	/* trim surrounding whitespace */
	while (*raw == ' ' || *raw == '\t')
		raw++;
	p = raw;

	part1 = sched_parse_name_part(&p, raw, what);
	if (*p == '.')
	{
		p++;
		while (*p == ' ' || *p == '\t')
			p++;
		part2 = sched_parse_name_part(&p, raw, what);
	}
	while (*p == ' ' || *p == '\t')
		p++;
	if (*p != '\0')
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_NAME),
				 errmsg("invalid %s name \"%s\"", what, raw)));

	if (part2 == NULL)
	{
		result->owner = GetUserNameFromId(GetUserId(), false);
		result->name = part1;
	}
	else
	{
		Oid			roleid;

		/*
		 * Resolve the owner as a role name.  Unquoted identifiers were
		 * upper-cased Oracle-style; fall back to the lower-case spelling
		 * that PostgreSQL roles conventionally use.
		 */
		roleid = get_role_oid(part1, true);
		if (!OidIsValid(roleid))
		{
			char	   *lower = str_tolower(part1, strlen(part1), DEFAULT_COLLATION_OID);

			roleid = get_role_oid(lower, true);
			if (OidIsValid(roleid))
				part1 = lower;
		}
		if (!OidIsValid(roleid))
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("user \"%s\" does not exist", part1)));

		if (roleid != GetUserId() && !superuser())
			ereport(ERROR,
					(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
					 errmsg("insufficient privileges to operate on scheduler objects owned by \"%s\"",
							part1)));

		result->owner = part1;
		result->name = part2;
	}
}

/*
 * What kind of scheduler object does (owner, name) denote?
 * Jobs, programs and schedules share one namespace, matching Oracle.
 */
static char
sched_object_kind(const SchedName *n)
{
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];
	char	   *kind;

	values[0] = CStringGetTextDatum(n->owner);
	values[1] = CStringGetTextDatum(n->name);

	if (sched_meta_select("SELECT CASE"
					 " WHEN EXISTS (SELECT 1 FROM sys.scheduler_jobs"
					 "   WHERE job_owner = $1 AND job_name = $2) THEN 'J'"
					 " WHEN EXISTS (SELECT 1 FROM sys.scheduler_programs"
					 "   WHERE program_owner = $1 AND program_name = $2) THEN 'P'"
					 " WHEN EXISTS (SELECT 1 FROM sys.scheduler_schedules"
					 "   WHERE schedule_owner = $1 AND schedule_name = $2) THEN 'S'"
					 " ELSE '' END",
					 2, argtypes, values, NULL) != 1)
		elog(ERROR, "scheduler object lookup failed");

	kind = sched_getstring(0, 1);
	return (kind && kind[0]) ? kind[0] : SCHED_KIND_NONE;
}

/*
 * Reject (owner, name) when any scheduler object already goes by it.
 *
 * The detail names the kind of the existing object: with one namespace for
 * all three kinds, the caller's own kind is not what the user is missing -
 * a CREATE_PROGRAM can fail because a job holds the name.
 */
static void
sched_check_name_free(const SchedName *n)
{
	char		kind = sched_object_kind(n);

	if (kind != SCHED_KIND_NONE)
		ereport(ERROR,
				(errcode(ERRCODE_DUPLICATE_OBJECT),
				 errmsg("scheduler object \"%s\".\"%s\" already exists",
						n->owner, n->name),
				 errdetail("A %s of that name already exists; jobs, programs and schedules share one namespace.",
						   kind == SCHED_KIND_JOB ? "job" :
						   kind == SCHED_KIND_PROGRAM ? "program" : "schedule")));
}

/* Validate commit_semantics; the value is accepted but has no effect. */
static void
sched_check_commit_semantics(const char *value)
{
	if (value == NULL)
		return;
	if (pg_strcasecmp(value, "STOP_ON_FIRST_ERROR") != 0 &&
		pg_strcasecmp(value, "TRANSACTIONAL") != 0 &&
		pg_strcasecmp(value, "ABSORB_ERRORS") != 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("invalid commit_semantics value \"%s\"", value),
				 errhint("Valid values are STOP_ON_FIRST_ERROR, TRANSACTIONAL and ABSORB_ERRORS.")));
}

/*
 * Normalize and validate PURGE_LOG's which_log.  All three Oracle values are
 * accepted; the window half of each has nothing to purge here, since this
 * implementation has no windows and so keeps no window log.
 */
static char *
sched_check_which_log(const char *value)
{
	if (value == NULL)
		return "JOB_AND_WINDOW_LOG";	/* as if it had been left out */

	if (pg_strcasecmp(value, "JOB_LOG") == 0)
		return "JOB_LOG";
	if (pg_strcasecmp(value, "WINDOW_LOG") == 0)
		return "WINDOW_LOG";
	if (pg_strcasecmp(value, "JOB_AND_WINDOW_LOG") == 0)
		return "JOB_AND_WINDOW_LOG";

	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("invalid which_log value \"%s\"", value),
			 errhint("Valid values are JOB_LOG, WINDOW_LOG and JOB_AND_WINDOW_LOG.")));
	return NULL;				/* keep compiler quiet */
}

/*
 * Normalize and validate a job/program type.  "PROCEDURE" is accepted as a
 * spelling of STORED_PROCEDURE for CREATE_PROGRAM compatibility.
 */
static char *
sched_check_type(const char *value, const char *what)
{
	if (value == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("%s must not be null", what)));

	if (pg_strcasecmp(value, "PLSQL_BLOCK") == 0)
		return "PLSQL_BLOCK";
	if (pg_strcasecmp(value, "STORED_PROCEDURE") == 0 ||
		pg_strcasecmp(value, "PROCEDURE") == 0)
		return "STORED_PROCEDURE";

	ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			 errmsg("%s \"%s\" is not supported", what, value),
			 errhint("Supported types are PLSQL_BLOCK and STORED_PROCEDURE.")));
	return NULL;				/* keep compiler quiet */
}

/* ------------------------------------------------------------------
 * next_run_date computation
 * ------------------------------------------------------------------
 */

/*
 * Compute the first run date for an enabled job.
 *
 * With no repeat_interval the job is a one-shot: it runs at start_date, or
 * immediately when no start_date was given.  With a repeat_interval the
 * first run is the first calendar match at or after both start_date and
 * "now".
 */
static TimestampTz
sched_first_run_date(const char *repeat_interval, TimestampTz start_date,
					 bool start_isnull, TimestampTz end_date, bool end_isnull,
					 const SchedName *job)
{
	TimestampTz now = GetCurrentTimestamp();
	TimestampTz next;

	if (repeat_interval == NULL)
		next = (!start_isnull && start_date > now) ? start_date : now;
	else
	{
		TimestampTz anchor = start_isnull ? now : start_date;

		/*
		 * sched_calendar_next returns the first match strictly after
		 * "after" and not before the anchor; back the probe off by one
		 * microsecond so an anchor exactly matching its own pattern
		 * qualifies as the first run.
		 */
		if (!sched_calendar_next(repeat_interval, anchor, now - 1, &next))
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("repeat_interval of job \"%s\".\"%s\" does not yield any future run date",
							job->owner, job->name)));
	}

	if (!end_isnull && next > end_date)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("cannot enable job \"%s\".\"%s\": next run date is later than end_date",
						job->owner, job->name)));

	return next;
}

/* ------------------------------------------------------------------
 * ENABLE / DISABLE internals
 * ------------------------------------------------------------------
 */

/* Verify all arguments 1..nargs have a value or a default. */
static void
sched_check_args_complete(const char *job_owner, const char *job_name,
						  const char *prog_owner, const char *prog_name,
						  int nargs)
{
	Oid			argtypes[5] = {TEXTOID, TEXTOID, TEXTOID, TEXTOID, INT4OID};
	Datum		values[5];
	char		nulls[5];
	uint64		missing;

	if (nargs <= 0)
		return;

	if (job_owner == NULL || job_name == NULL)
		elog(ERROR, "scheduler job owner or name is null");

	values[0] = CStringGetTextDatum(job_owner);
	values[1] = CStringGetTextDatum(job_name);
	nulls[0] = nulls[1] = ' ';
	if (prog_name != NULL)
	{
		/* the two program columns travel together */
		if (prog_owner == NULL)
			elog(ERROR, "job \"%s\".\"%s\" has an incomplete program reference",
				 job_owner, job_name);
		values[2] = CStringGetTextDatum(prog_owner);
		values[3] = CStringGetTextDatum(prog_name);
		nulls[2] = nulls[3] = ' ';
	}
	else
	{
		values[2] = values[3] = (Datum) 0;
		nulls[2] = nulls[3] = 'n';
	}
	values[4] = Int32GetDatum(nargs);
	nulls[4] = ' ';

	missing = sched_meta_select("SELECT pos FROM generate_series(1, $5) pos"
						   " WHERE NOT EXISTS (SELECT 1 FROM sys.scheduler_job_args"
						   "   WHERE job_owner = $1 AND job_name = $2"
						   "     AND argument_position = pos)"
						   " AND NOT EXISTS (SELECT 1 FROM sys.scheduler_program_args"
						   "   WHERE program_owner = $3 AND program_name = $4"
						   "     AND argument_position = pos AND has_default)"
						   " ORDER BY pos LIMIT 1",
						   5, argtypes, values, nulls);
	if (missing > 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("cannot enable job \"%s\".\"%s\": argument %s has no value and no default",
						job_owner, job_name, sched_getstring(0, 1))));
}

/*
 * Is the current database covered by ivorysql.scheduler_databases?
 *
 * Only used to warn about jobs that will never fire, so a malformed list
 * counts as "not covered"; the launcher reports the syntax error itself.
 */
static bool
sched_current_database_is_scheduled(void)
{
	char	   *rawstring;
	List	   *elemlist;
	ListCell   *lc;
	const char *dbname;
	bool		found = false;

	if (scheduler_databases == NULL || scheduler_databases[0] == '\0')
		return false;

	rawstring = pstrdup(scheduler_databases);
	if (!SplitIdentifierString(rawstring, ',', &elemlist))
	{
		list_free(elemlist);
		pfree(rawstring);
		return false;
	}

	dbname = get_database_name(MyDatabaseId);
	foreach(lc, elemlist)
	{
		if (dbname != NULL && strcmp((char *) lfirst(lc), dbname) == 0)
		{
			found = true;
			break;
		}
	}

	list_free(elemlist);
	pfree(rawstring);
	return found;
}

/*
 * Wake this database's scheduler after the current transaction commits.
 *
 * The scheduler sleeps until the earliest run date it knew of when it last
 * looked, so a job enabled while it sleeps would otherwise wait that sleep
 * out.  Oracle's job coordinator is woken the same way: it "wakes up when a
 * new job is about to be executed or a job was created using the CREATE_JOB
 * procedure".
 *
 * Which process to wake is read from pg_stat_activity rather than recorded in
 * the metadata: that view is derived from the process array, so it cannot go
 * stale, whereas a copy of who is scheduling what would be one more thing
 * needing to be cleaned up after a crash.
 *
 * It has to be two steps.  Signalling before the commit would wake the
 * scheduler onto a job it cannot see yet, and it would go back to sleep on
 * its old deadline -- worse than not signalling at all.  Signalling after the
 * commit means running in a transaction callback, which is past the point
 * where a query can be run.  So the pid is looked up here, where SPI still
 * works, and only the signal itself is left for the callback.
 */
static int32 sched_wakeup_pid = 0;

static void
sched_wakeup_at_commit(XactEvent event, void *arg)
{
	PGPROC	   *proc;
	int32		pid;

	switch (event)
	{
		case XACT_EVENT_COMMIT:
			break;
		case XACT_EVENT_ABORT:
		case XACT_EVENT_PARALLEL_ABORT:
			sched_wakeup_pid = 0;
			return;
		default:

			/*
			 * Anything else, XACT_EVENT_PRE_COMMIT above all, is not the end
			 * of the transaction: leave the request alone rather than dropping
			 * it before the commit it was made for arrives.
			 */
			return;
	}

	pid = sched_wakeup_pid;
	sched_wakeup_pid = 0;
	if (pid == 0)
		return;

	/*
	 * The pid was read before the commit, so by now the process may be gone
	 * or, worse, its pid reused.  Getting it wrong costs the other process a
	 * spurious latch set, which every process is written to tolerate, so the
	 * database check is as far as this needs to go -- unlike STOP_JOB, which
	 * cancels what it finds and therefore matches on the backend start time
	 * too.
	 */
	proc = BackendPidGetProc(pid);
	if (proc != NULL && proc->databaseId == MyDatabaseId)
		SetLatch(&proc->procLatch);
}

static void
sched_request_scheduler_wakeup(void)
{
	static bool registered = false;
	bool		isnull;
	Datum		d;

	if (!registered)
	{
		RegisterXactCallback(sched_wakeup_at_commit, NULL);
		registered = true;
	}

	/* one scheduler per database, so this database's is the one to wake */
	if (sched_meta_select("SELECT pid FROM pg_catalog.pg_stat_activity"
						  " WHERE backend_type = 'ivorysql scheduler worker'"
						  "  AND datname = pg_catalog.current_database()"
						  " LIMIT 1",
						  0, NULL, NULL, NULL) != 1)
		return;

	d = sched_getdatum(0, 1, &isnull);
	if (!isnull)
		sched_wakeup_pid = DatumGetInt32(d);
}

static void
sched_enable_job(const SchedName *job)
{
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];
	char	   *job_type;
	int			nargs = 0;
	char	   *prog_owner = NULL;
	char	   *prog_name = NULL;
	char	   *repeat_interval = NULL;
	TimestampTz start_date = 0;
	TimestampTz end_date = 0;
	bool		start_isnull = true;
	bool		end_isnull = true;
	TimestampTz next;
	bool		isnull;
	Datum		d;

	values[0] = CStringGetTextDatum(job->owner);
	values[1] = CStringGetTextDatum(job->name);

	if (sched_meta_select("SELECT job_type, number_of_arguments,"
					 " program_owner, program_name, schedule_owner, schedule_name,"
					 " start_date, repeat_interval, end_date"
					 " FROM sys.scheduler_jobs"
					 " WHERE job_owner = $1 AND job_name = $2",
					 2, argtypes, values, NULL) != 1)
		elog(ERROR, "job \"%s\".\"%s\" disappeared", job->owner, job->name);

	job_type = sched_getstring(0, 1);
	d = sched_getdatum(0, 2, &isnull);
	if (!isnull)
		nargs = DatumGetInt32(d);
	prog_owner = sched_getstring(0, 3);
	prog_name = sched_getstring(0, 4);

	d = sched_getdatum(0, 7, &start_isnull);
	if (!start_isnull)
		start_date = DatumGetTimestampTz(d);
	repeat_interval = sched_getstring(0, 8);
	d = sched_getdatum(0, 9, &end_isnull);
	if (!end_isnull)
		end_date = DatumGetTimestampTz(d);

	if (job_type == NULL)
	{
		/* named-program job: pull execution and schedule metadata */
		char	   *sched_owner = sched_getstring(0, 5);
		char	   *sched_name = sched_getstring(0, 6);
		Oid			at2[2] = {TEXTOID, TEXTOID};
		Datum		v2[2];

		if (prog_owner == NULL || prog_name == NULL)
			elog(ERROR, "job \"%s\".\"%s\" has an incomplete program reference",
				 job->owner, job->name);
		if (sched_owner == NULL || sched_name == NULL)
			elog(ERROR, "job \"%s\".\"%s\" has an incomplete schedule reference",
				 job->owner, job->name);

		v2[0] = CStringGetTextDatum(prog_owner);
		v2[1] = CStringGetTextDatum(prog_name);
		if (sched_meta_select("SELECT program_type, number_of_arguments, enabled"
						 " FROM sys.scheduler_programs"
						 " WHERE program_owner = $1 AND program_name = $2",
						 2, at2, v2, NULL) != 1)
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("program \"%s\".\"%s\" referenced by job \"%s\".\"%s\" does not exist",
							prog_owner, prog_name, job->owner, job->name)));
		job_type = sched_getstring(0, 1);
		d = sched_getdatum(0, 2, &isnull);
		nargs = isnull ? 0 : DatumGetInt32(d);

		/* a disabled program cannot run, so a job on it cannot be enabled */
		d = sched_getdatum(0, 3, &isnull);
		if (isnull || !DatumGetBool(d))
			ereport(ERROR,
					(errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
					 errmsg("cannot enable job \"%s\".\"%s\": program \"%s\".\"%s\" is disabled",
							job->owner, job->name, prog_owner, prog_name),
					 errhint("Enable the program first.")));

		v2[0] = CStringGetTextDatum(sched_owner);
		v2[1] = CStringGetTextDatum(sched_name);
		if (sched_meta_select("SELECT start_date, repeat_interval, end_date"
						 " FROM sys.scheduler_schedules"
						 " WHERE schedule_owner = $1 AND schedule_name = $2",
						 2, at2, v2, NULL) != 1)
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("schedule \"%s\".\"%s\" referenced by job \"%s\".\"%s\" does not exist",
							sched_owner, sched_name, job->owner, job->name)));
		d = sched_getdatum(0, 1, &start_isnull);
		if (!start_isnull)
			start_date = DatumGetTimestampTz(d);
		repeat_interval = sched_getstring(0, 2);
		d = sched_getdatum(0, 3, &end_isnull);
		if (!end_isnull)
			end_date = DatumGetTimestampTz(d);
	}

	if (strcmp(job_type, "STORED_PROCEDURE") == 0)
		sched_check_args_complete(job->owner, job->name, prog_owner, prog_name,
								  nargs);

	next = sched_first_run_date(repeat_interval, start_date, start_isnull,
								end_date, end_isnull, job);

	{
		Oid			at3[3] = {TEXTOID, TEXTOID, TIMESTAMPTZOID};
		Datum		v3[3];

		v3[0] = CStringGetTextDatum(job->owner);
		v3[1] = CStringGetTextDatum(job->name);
		v3[2] = TimestampTzGetDatum(next);
		/*
		 * Clear failure_count, as Oracle's ENABLE does: otherwise a job the
		 * scheduler_max_failures limit disabled would be back at the limit on
		 * its very next failure.
		 *
		 * A job that is running stays in the RUNNING state: that state is what
		 * keeps the scheduler from starting a second instance alongside the
		 * one already going, and the run in progress puts it back to SCHEDULED
		 * when it finishes.
		 */
		sched_meta_dml("UPDATE sys.scheduler_jobs SET enabled = true,"
				  " state = CASE WHEN state = 'RUNNING' THEN state"
				  "              ELSE 'SCHEDULED' END,"
				  " next_run_date = $3, failure_count = 0"
				  " WHERE job_owner = $1 AND job_name = $2",
				  3, at3, v3, NULL);
	}

	if (!scheduler_launcher_registered || !scheduler_enabled)
		ereport(WARNING,
				(errmsg("the scheduler background launcher is not running; job \"%s\".\"%s\" will not run automatically",
						job->owner, job->name),
				 errhint("Add ivorysql_ora to shared_preload_libraries and set ivorysql.scheduler = on.")));
	else if (!sched_current_database_is_scheduled())
		ereport(WARNING,
				(errmsg("database \"%s\" is not scheduled; job \"%s\".\"%s\" will not run automatically",
						get_database_name(MyDatabaseId), job->owner, job->name),
				 errhint("Add the database to ivorysql.scheduler_databases.")));
	else
		sched_request_scheduler_wakeup();
}

static void
sched_enable_program(const SchedName *prog)
{
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];
	char	   *ptype;
	int			nargs;
	bool		isnull;
	Datum		d;

	values[0] = CStringGetTextDatum(prog->owner);
	values[1] = CStringGetTextDatum(prog->name);
	if (sched_meta_select("SELECT program_type, number_of_arguments"
					 " FROM sys.scheduler_programs"
					 " WHERE program_owner = $1 AND program_name = $2",
					 2, argtypes, values, NULL) != 1)
		elog(ERROR, "program \"%s\".\"%s\" disappeared", prog->owner, prog->name);

	ptype = sched_getstring(0, 1);
	d = sched_getdatum(0, 2, &isnull);
	nargs = isnull ? 0 : DatumGetInt32(d);

	if (strcmp(ptype, "STORED_PROCEDURE") == 0 && nargs > 0)
	{
		Oid			at[3] = {TEXTOID, TEXTOID, INT4OID};
		Datum		v[3];

		v[0] = values[0];
		v[1] = values[1];
		v[2] = Int32GetDatum(nargs);
		if (sched_meta_select("SELECT pos FROM generate_series(1, $3) pos"
						 " WHERE NOT EXISTS (SELECT 1 FROM sys.scheduler_program_args"
						 "   WHERE program_owner = $1 AND program_name = $2"
						 "     AND argument_position = pos)"
						 " ORDER BY pos LIMIT 1",
						 3, at, v, NULL) > 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("cannot enable program \"%s\".\"%s\": argument %s is not defined",
							prog->owner, prog->name, sched_getstring(0, 1))));
	}

	sched_meta_dml("UPDATE sys.scheduler_programs SET enabled = true"
			  " WHERE program_owner = $1 AND program_name = $2",
			  2, argtypes, values, NULL);
}

/* ------------------------------------------------------------------
 * CREATE_JOB / CREATE_PROGRAM / CREATE_SCHEDULE
 * ------------------------------------------------------------------
 */

Datum
ora_dbms_scheduler_create_job_inline(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	char	   *job_type = text_arg_or_null(fcinfo, 1);
	char	   *job_action = text_arg_or_null(fcinfo, 2);
	int32		nargs = PG_ARGISNULL(3) ? 0 : PG_GETARG_INT32(3);
	bool		start_isnull = PG_ARGISNULL(4);
	TimestampTz start_date = start_isnull ? 0 : PG_GETARG_TIMESTAMPTZ(4);
	char	   *repeat_interval = text_arg_or_null(fcinfo, 5);
	bool		end_isnull = PG_ARGISNULL(6);
	TimestampTz end_date = end_isnull ? 0 : PG_GETARG_TIMESTAMPTZ(6);
	char	   *job_class = text_arg_or_null(fcinfo, 7);
	bool		enabled = PG_ARGISNULL(8) ? false : PG_GETARG_BOOL(8);
	bool		auto_drop = PG_ARGISNULL(9) ? true : PG_GETARG_BOOL(9);
	char	   *comments = text_arg_or_null(fcinfo, 10);
	SchedName	job;
	Oid			argtypes[11] = {TEXTOID, TEXTOID, TEXTOID, TEXTOID, INT4OID,
	TIMESTAMPTZOID, TEXTOID, TIMESTAMPTZOID, TEXTOID, BOOLOID, TEXTOID};
	Datum		values[11];
	char		nulls[11];

	SPI_connect();

	sched_parse_name(raw_name, "job", &job);
	sched_check_name_free(&job);

	job_type = sched_check_type(job_type, "job_type");
	if (job_action == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("job_action must not be null")));

	if (nargs < 0 || nargs > SCHED_MAX_ARGS)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("number_of_arguments must be between 0 and %d",
						SCHED_MAX_ARGS)));

	/*
	 * A PLSQL_BLOCK action is executed verbatim and has nowhere to put
	 * arguments, so the count is meaningless for it.  Ignore it rather than
	 * rejecting the call, which is what EDB Postgres Advanced Server does,
	 * but say so: passing arguments here usually means STORED_PROCEDURE was
	 * intended.
	 */
	if (strcmp(job_type, "PLSQL_BLOCK") == 0 && nargs != 0)
	{
		ereport(WARNING,
				(errmsg("number_of_arguments is ignored for a PLSQL_BLOCK job")));
		nargs = 0;
	}

	if (repeat_interval != NULL)
		sched_calendar_validate(repeat_interval);

	if (!start_isnull && !end_isnull && end_date <= start_date)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("end_date must be later than start_date")));

	values[0] = CStringGetTextDatum(job.owner);
	values[1] = CStringGetTextDatum(job.name);
	values[2] = CStringGetTextDatum(job_type);
	values[3] = CStringGetTextDatum(job_action);
	values[4] = Int32GetDatum(nargs);
	values[5] = TimestampTzGetDatum(start_date);
	values[6] = repeat_interval ? CStringGetTextDatum(repeat_interval) : (Datum) 0;
	values[7] = TimestampTzGetDatum(end_date);
	values[8] = job_class ? CStringGetTextDatum(job_class) : (Datum) 0;
	values[9] = BoolGetDatum(auto_drop);
	values[10] = comments ? CStringGetTextDatum(comments) : (Datum) 0;
	memset(nulls, ' ', sizeof(nulls));
	if (start_isnull)
		nulls[5] = 'n';
	if (repeat_interval == NULL)
		nulls[6] = 'n';
	if (end_isnull)
		nulls[7] = 'n';
	if (job_class == NULL)
		nulls[8] = 'n';
	if (comments == NULL)
		nulls[10] = 'n';

	sched_meta_dml("INSERT INTO sys.scheduler_jobs"
			  " (job_owner, job_name, job_type, job_action,"
			  "  number_of_arguments, start_date, repeat_interval, end_date,"
			  "  job_class, auto_drop, comments)"
			  " VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
			  11, argtypes, values, nulls);

	if (enabled)
		sched_enable_job(&job);

	SPI_finish();
	PG_RETURN_VOID();
}

Datum
ora_dbms_scheduler_create_job_named(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	char	   *raw_program = text_arg_or_null(fcinfo, 1);
	char	   *raw_schedule = text_arg_or_null(fcinfo, 2);
	char	   *job_class = text_arg_or_null(fcinfo, 3);
	bool		enabled = PG_ARGISNULL(4) ? false : PG_GETARG_BOOL(4);
	bool		auto_drop = PG_ARGISNULL(5) ? true : PG_GETARG_BOOL(5);
	char	   *comments = text_arg_or_null(fcinfo, 6);
	SchedName	job;
	SchedName	prog;
	SchedName	sched;
	Oid			argtypes[9] = {TEXTOID, TEXTOID, TEXTOID, TEXTOID, TEXTOID,
	TEXTOID, TEXTOID, BOOLOID, TEXTOID};
	Datum		values[9];
	char		nulls[9];

	SPI_connect();

	sched_parse_name(raw_name, "job", &job);
	sched_check_name_free(&job);

	if (raw_program == NULL || raw_schedule == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("program_name and schedule_name must not be null")));

	sched_parse_name(raw_program, "program", &prog);
	sched_parse_name(raw_schedule, "schedule", &sched);

	if (sched_object_kind(&prog) != SCHED_KIND_PROGRAM)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("program \"%s\".\"%s\" does not exist",
						prog.owner, prog.name)));
	if (sched_object_kind(&sched) != SCHED_KIND_SCHEDULE)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("schedule \"%s\".\"%s\" does not exist",
						sched.owner, sched.name)));

	values[0] = CStringGetTextDatum(job.owner);
	values[1] = CStringGetTextDatum(job.name);
	values[2] = CStringGetTextDatum(prog.owner);
	values[3] = CStringGetTextDatum(prog.name);
	values[4] = CStringGetTextDatum(sched.owner);
	values[5] = CStringGetTextDatum(sched.name);
	values[6] = job_class ? CStringGetTextDatum(job_class) : (Datum) 0;
	values[7] = BoolGetDatum(auto_drop);
	values[8] = comments ? CStringGetTextDatum(comments) : (Datum) 0;
	memset(nulls, ' ', sizeof(nulls));
	if (job_class == NULL)
		nulls[6] = 'n';
	if (comments == NULL)
		nulls[8] = 'n';

	sched_meta_dml("INSERT INTO sys.scheduler_jobs"
			  " (job_owner, job_name, program_owner, program_name,"
			  "  schedule_owner, schedule_name, job_class, auto_drop, comments)"
			  " VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
			  9, argtypes, values, nulls);

	if (enabled)
		sched_enable_job(&job);

	SPI_finish();
	PG_RETURN_VOID();
}

Datum
ora_dbms_scheduler_create_program(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	char	   *program_type = text_arg_or_null(fcinfo, 1);
	char	   *program_action = text_arg_or_null(fcinfo, 2);
	int32		nargs = PG_ARGISNULL(3) ? 0 : PG_GETARG_INT32(3);
	bool		enabled = PG_ARGISNULL(4) ? false : PG_GETARG_BOOL(4);
	char	   *comments = text_arg_or_null(fcinfo, 5);
	SchedName	prog;
	Oid			argtypes[6] = {TEXTOID, TEXTOID, TEXTOID, TEXTOID, INT4OID, TEXTOID};
	Datum		values[6];
	char		nulls[6];

	SPI_connect();

	sched_parse_name(raw_name, "program", &prog);
	sched_check_name_free(&prog);

	program_type = sched_check_type(program_type, "program_type");
	if (program_action == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("program_action must not be null")));
	if (nargs < 0 || nargs > SCHED_MAX_ARGS)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("number_of_arguments must be between 0 and %d",
						SCHED_MAX_ARGS)));

	/* see the matching comment in ora_dbms_scheduler_create_job_inline */
	if (strcmp(program_type, "PLSQL_BLOCK") == 0 && nargs != 0)
	{
		ereport(WARNING,
				(errmsg("number_of_arguments is ignored for a PLSQL_BLOCK program")));
		nargs = 0;
	}

	values[0] = CStringGetTextDatum(prog.owner);
	values[1] = CStringGetTextDatum(prog.name);
	values[2] = CStringGetTextDatum(program_type);
	values[3] = CStringGetTextDatum(program_action);
	values[4] = Int32GetDatum(nargs);
	values[5] = comments ? CStringGetTextDatum(comments) : (Datum) 0;
	memset(nulls, ' ', sizeof(nulls));
	if (comments == NULL)
		nulls[5] = 'n';

	sched_meta_dml("INSERT INTO sys.scheduler_programs"
			  " (program_owner, program_name, program_type, program_action,"
			  "  number_of_arguments, comments)"
			  " VALUES ($1, $2, $3, $4, $5, $6)",
			  6, argtypes, values, nulls);

	if (enabled)
		sched_enable_program(&prog);

	SPI_finish();
	PG_RETURN_VOID();
}

Datum
ora_dbms_scheduler_create_schedule(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	bool		start_isnull = PG_ARGISNULL(1);
	TimestampTz start_date = start_isnull ? 0 : PG_GETARG_TIMESTAMPTZ(1);
	char	   *repeat_interval = text_arg_or_null(fcinfo, 2);
	bool		end_isnull = PG_ARGISNULL(3);
	TimestampTz end_date = end_isnull ? 0 : PG_GETARG_TIMESTAMPTZ(3);
	char	   *comments = text_arg_or_null(fcinfo, 4);
	SchedName	sched;
	Oid			argtypes[6] = {TEXTOID, TEXTOID, TIMESTAMPTZOID, TEXTOID,
	TIMESTAMPTZOID, TEXTOID};
	Datum		values[6];
	char		nulls[6];

	SPI_connect();

	sched_parse_name(raw_name, "schedule", &sched);
	sched_check_name_free(&sched);

	if (start_isnull && repeat_interval == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("either start_date or repeat_interval must be specified")));
	if (repeat_interval != NULL)
		sched_calendar_validate(repeat_interval);
	if (!start_isnull && !end_isnull && end_date <= start_date)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("end_date must be later than start_date")));

	values[0] = CStringGetTextDatum(sched.owner);
	values[1] = CStringGetTextDatum(sched.name);
	values[2] = TimestampTzGetDatum(start_date);
	values[3] = repeat_interval ? CStringGetTextDatum(repeat_interval) : (Datum) 0;
	values[4] = TimestampTzGetDatum(end_date);
	values[5] = comments ? CStringGetTextDatum(comments) : (Datum) 0;
	memset(nulls, ' ', sizeof(nulls));
	if (start_isnull)
		nulls[2] = 'n';
	if (repeat_interval == NULL)
		nulls[3] = 'n';
	if (end_isnull)
		nulls[4] = 'n';
	if (comments == NULL)
		nulls[5] = 'n';

	sched_meta_dml("INSERT INTO sys.scheduler_schedules"
			  " (schedule_owner, schedule_name, start_date, repeat_interval,"
			  "  end_date, comments)"
			  " VALUES ($1, $2, $3, $4, $5, $6)",
			  6, argtypes, values, nulls);

	SPI_finish();
	PG_RETURN_VOID();
}

/* ------------------------------------------------------------------
 * Program arguments
 * ------------------------------------------------------------------
 */

/* Look up a program and return its number_of_arguments. */
static int
sched_program_nargs(const SchedName *prog)
{
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];
	bool		isnull;
	Datum		d;

	values[0] = CStringGetTextDatum(prog->owner);
	values[1] = CStringGetTextDatum(prog->name);
	if (sched_meta_select("SELECT number_of_arguments FROM sys.scheduler_programs"
					 " WHERE program_owner = $1 AND program_name = $2",
					 2, argtypes, values, NULL) != 1)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("program \"%s\".\"%s\" does not exist",
						prog->owner, prog->name)));
	d = sched_getdatum(0, 1, &isnull);
	return isnull ? 0 : DatumGetInt32(d);
}

Datum
ora_dbms_scheduler_define_program_argument(PG_FUNCTION_ARGS)
{
	char	   *raw_program = text_arg_or_null(fcinfo, 0);
	int32		position = PG_ARGISNULL(1) ? 0 : PG_GETARG_INT32(1);
	char	   *argument_name = text_arg_or_null(fcinfo, 2);
	char	   *argument_type = text_arg_or_null(fcinfo, 3);
	char	   *default_value = text_arg_or_null(fcinfo, 4);
	bool		has_default = PG_ARGISNULL(5) ? false : PG_GETARG_BOOL(5);
	bool		out_argument = PG_ARGISNULL(6) ? false : PG_GETARG_BOOL(6);
	SchedName	prog;
	int			nargs;
	Oid			argtypes[7] = {TEXTOID, TEXTOID, INT4OID, TEXTOID, TEXTOID,
	TEXTOID, BOOLOID};
	Datum		values[7];
	char		nulls[7];

	SPI_connect();

	if (out_argument)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("OUT arguments are not supported")));

	sched_parse_name(raw_program, "program", &prog);
	nargs = sched_program_nargs(&prog);

	if (position < 1 || position > nargs)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("argument_position %d is out of range for program \"%s\".\"%s\" (1 .. %d)",
						position, prog.owner, prog.name, nargs)));

	/* Oracle folds unquoted argument names too */
	if (argument_name != NULL)
		argument_name = sched_normalize_simple(argument_name, "argument");

	values[0] = CStringGetTextDatum(prog.owner);
	values[1] = CStringGetTextDatum(prog.name);
	values[2] = Int32GetDatum(position);
	values[3] = argument_name ? CStringGetTextDatum(argument_name) : (Datum) 0;
	values[4] = argument_type ? CStringGetTextDatum(argument_type) : (Datum) 0;
	values[5] = default_value ? CStringGetTextDatum(default_value) : (Datum) 0;
	values[6] = BoolGetDatum(has_default);
	memset(nulls, ' ', sizeof(nulls));
	if (argument_name == NULL)
		nulls[3] = 'n';
	if (argument_type == NULL)
		nulls[4] = 'n';
	if (default_value == NULL)
		nulls[5] = 'n';

	/* Re-defining an existing position replaces it, as Oracle does. */
	sched_meta_dml("INSERT INTO sys.scheduler_program_args"
			  " (program_owner, program_name, argument_position,"
			  "  argument_name, argument_type, default_value, has_default)"
			  " VALUES ($1, $2, $3, $4, $5, $6, $7)"
			  " ON CONFLICT (program_owner, program_name, argument_position)"
			  " DO UPDATE SET argument_name = $4, argument_type = $5,"
			  "  default_value = $6, has_default = $7",
			  7, argtypes, values, nulls);

	SPI_finish();
	PG_RETURN_VOID();
}

Datum
ora_dbms_scheduler_drop_program_argument_pos(PG_FUNCTION_ARGS)
{
	char	   *raw_program = text_arg_or_null(fcinfo, 0);
	int32		position = PG_ARGISNULL(1) ? 0 : PG_GETARG_INT32(1);
	SchedName	prog;
	Oid			argtypes[3] = {TEXTOID, TEXTOID, INT4OID};
	Datum		values[3];

	SPI_connect();

	sched_parse_name(raw_program, "program", &prog);
	(void) sched_program_nargs(&prog);	/* existence check */

	values[0] = CStringGetTextDatum(prog.owner);
	values[1] = CStringGetTextDatum(prog.name);
	values[2] = Int32GetDatum(position);
	if (sched_meta_dml("DELETE FROM sys.scheduler_program_args"
				  " WHERE program_owner = $1 AND program_name = $2"
				  " AND argument_position = $3",
				  3, argtypes, values, NULL) == 0)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("argument %d of program \"%s\".\"%s\" is not defined",
						position, prog.owner, prog.name)));

	SPI_finish();
	PG_RETURN_VOID();
}

Datum
ora_dbms_scheduler_drop_program_argument_name(PG_FUNCTION_ARGS)
{
	char	   *raw_program = text_arg_or_null(fcinfo, 0);
	char	   *argument_name = text_arg_or_null(fcinfo, 1);
	SchedName	prog;
	Oid			argtypes[3] = {TEXTOID, TEXTOID, TEXTOID};
	Datum		values[3];

	SPI_connect();

	sched_parse_name(raw_program, "program", &prog);
	(void) sched_program_nargs(&prog);	/* existence check */

	if (argument_name == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("argument_name must not be null")));
	argument_name = sched_normalize_simple(argument_name, "argument");

	values[0] = CStringGetTextDatum(prog.owner);
	values[1] = CStringGetTextDatum(prog.name);
	values[2] = CStringGetTextDatum(argument_name);
	if (sched_meta_dml("DELETE FROM sys.scheduler_program_args"
				  " WHERE program_owner = $1 AND program_name = $2"
				  " AND argument_name = $3",
				  3, argtypes, values, NULL) == 0)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("argument \"%s\" of program \"%s\".\"%s\" is not defined",
						argument_name, prog.owner, prog.name)));

	SPI_finish();
	PG_RETURN_VOID();
}

/* ------------------------------------------------------------------
 * Job argument values
 * ------------------------------------------------------------------
 */

/*
 * Resolve a job for argument operations, returning the effective argument
 * count and (for named-program jobs) the program identity.
 */
static int
sched_job_arg_context(const SchedName *job, char **prog_owner,
					  char **prog_name)
{
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];
	bool		isnull;
	Datum		d;
	char	   *jtype;

	*prog_owner = NULL;
	*prog_name = NULL;

	values[0] = CStringGetTextDatum(job->owner);
	values[1] = CStringGetTextDatum(job->name);
	if (sched_meta_select("SELECT job_type, number_of_arguments,"
					 " program_owner, program_name"
					 " FROM sys.scheduler_jobs"
					 " WHERE job_owner = $1 AND job_name = $2",
					 2, argtypes, values, NULL) != 1)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("job \"%s\".\"%s\" does not exist",
						job->owner, job->name)));

	jtype = sched_getstring(0, 1);
	if (jtype != NULL)
	{
		d = sched_getdatum(0, 2, &isnull);
		return isnull ? 0 : DatumGetInt32(d);
	}

	*prog_owner = sched_getstring(0, 3);
	*prog_name = sched_getstring(0, 4);
	if (*prog_owner == NULL || *prog_name == NULL)
		elog(ERROR, "job \"%s\".\"%s\" has an incomplete program reference",
			 job->owner, job->name);

	{
		SchedName	prog;

		prog.owner = *prog_owner;
		prog.name = *prog_name;
		return sched_program_nargs(&prog);
	}
}

static void
sched_set_job_argument(const SchedName *job, int position, const char *value)
{
	Oid			argtypes[4] = {TEXTOID, TEXTOID, INT4OID, TEXTOID};
	Datum		values[4];
	char		nulls[4];

	values[0] = CStringGetTextDatum(job->owner);
	values[1] = CStringGetTextDatum(job->name);
	values[2] = Int32GetDatum(position);
	values[3] = value ? CStringGetTextDatum(value) : (Datum) 0;
	memset(nulls, ' ', sizeof(nulls));
	if (value == NULL)
		nulls[3] = 'n';

	sched_meta_dml("INSERT INTO sys.scheduler_job_args"
			  " (job_owner, job_name, argument_position, argument_value)"
			  " VALUES ($1, $2, $3, $4)"
			  " ON CONFLICT (job_owner, job_name, argument_position)"
			  " DO UPDATE SET argument_value = $4",
			  4, argtypes, values, nulls);
}

Datum
ora_dbms_scheduler_set_job_argument_value_pos(PG_FUNCTION_ARGS)
{
	char	   *raw_job = text_arg_or_null(fcinfo, 0);
	int32		position = PG_ARGISNULL(1) ? 0 : PG_GETARG_INT32(1);
	char	   *value = text_arg_or_null(fcinfo, 2);
	SchedName	job;
	char	   *prog_owner;
	char	   *prog_name;
	int			nargs;

	SPI_connect();

	sched_parse_name(raw_job, "job", &job);
	nargs = sched_job_arg_context(&job, &prog_owner, &prog_name);

	if (position < 1 || position > nargs)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("argument_position %d is out of range for job \"%s\".\"%s\" (1 .. %d)",
						position, job.owner, job.name, nargs)));

	sched_set_job_argument(&job, position, value);

	SPI_finish();
	PG_RETURN_VOID();
}

Datum
ora_dbms_scheduler_set_job_argument_value_name(PG_FUNCTION_ARGS)
{
	char	   *raw_job = text_arg_or_null(fcinfo, 0);
	char	   *argument_name = text_arg_or_null(fcinfo, 1);
	char	   *value = text_arg_or_null(fcinfo, 2);
	SchedName	job;
	char	   *prog_owner;
	char	   *prog_name;
	int			position;
	Oid			argtypes[3] = {TEXTOID, TEXTOID, TEXTOID};
	Datum		values[3];
	bool		isnull;

	SPI_connect();

	sched_parse_name(raw_job, "job", &job);
	(void) sched_job_arg_context(&job, &prog_owner, &prog_name);

	if (argument_name == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("argument_name must not be null")));
	if (prog_name == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("job \"%s\".\"%s\" has no named arguments",
						job.owner, job.name),
				 errhint("Only jobs that reference a program have named arguments.")));

	argument_name = sched_normalize_simple(argument_name, "argument");

	values[0] = CStringGetTextDatum(prog_owner);
	values[1] = CStringGetTextDatum(prog_name);
	values[2] = CStringGetTextDatum(argument_name);
	if (sched_meta_select("SELECT argument_position FROM sys.scheduler_program_args"
					 " WHERE program_owner = $1 AND program_name = $2"
					 " AND argument_name = $3",
					 3, argtypes, values, NULL) != 1)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("program \"%s\".\"%s\" has no argument named \"%s\"",
						prog_owner, prog_name, argument_name)));
	position = DatumGetInt32(sched_getdatum(0, 1, &isnull));

	sched_set_job_argument(&job, position, value);

	SPI_finish();
	PG_RETURN_VOID();
}

/* ------------------------------------------------------------------
 * ENABLE / DISABLE
 * ------------------------------------------------------------------
 */

Datum
ora_dbms_scheduler_enable(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	char	   *commit_semantics = text_arg_or_null(fcinfo, 1);
	SchedName	obj;
	char		kind;

	SPI_connect();

	sched_check_commit_semantics(commit_semantics);
	sched_parse_name(raw_name, "scheduler object", &obj);

	kind = sched_object_kind(&obj);
	switch (kind)
	{
		case SCHED_KIND_JOB:
			sched_enable_job(&obj);
			break;
		case SCHED_KIND_PROGRAM:
			sched_enable_program(&obj);
			break;
		case SCHED_KIND_SCHEDULE:
			ereport(ERROR,
					(errcode(ERRCODE_WRONG_OBJECT_TYPE),
					 errmsg("schedule \"%s\".\"%s\" cannot be enabled",
							obj.owner, obj.name)));
			break;
		default:
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("scheduler object \"%s\".\"%s\" does not exist",
							obj.owner, obj.name)));
	}

	SPI_finish();
	PG_RETURN_VOID();
}

Datum
ora_dbms_scheduler_disable(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	char	   *commit_semantics = text_arg_or_null(fcinfo, 2);
	SchedName	obj;
	char		kind;
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];

	/* "force" (arg 1) is accepted for Oracle compatibility and ignored */

	SPI_connect();

	sched_check_commit_semantics(commit_semantics);
	sched_parse_name(raw_name, "scheduler object", &obj);

	values[0] = CStringGetTextDatum(obj.owner);
	values[1] = CStringGetTextDatum(obj.name);

	kind = sched_object_kind(&obj);
	switch (kind)
	{
		case SCHED_KIND_JOB:

			/*
			 * A job that is running keeps the RUNNING state: dropping it here
			 * would let a DISABLE followed by an ENABLE start a second run
			 * alongside the one still going.  The run in progress records its
			 * outcome as the job's state when it finishes, as it does for any
			 * job disabled under it.
			 */
			sched_meta_dml("UPDATE sys.scheduler_jobs SET enabled = false,"
					  " state = CASE WHEN state = 'RUNNING' THEN state"
					  "              ELSE 'DISABLED' END,"
					  " next_run_date = NULL"
					  " WHERE job_owner = $1 AND job_name = $2",
					  2, argtypes, values, NULL);
			break;
		case SCHED_KIND_PROGRAM:
			sched_meta_dml("UPDATE sys.scheduler_programs SET enabled = false"
					  " WHERE program_owner = $1 AND program_name = $2",
					  2, argtypes, values, NULL);
			break;
		case SCHED_KIND_SCHEDULE:
			ereport(ERROR,
					(errcode(ERRCODE_WRONG_OBJECT_TYPE),
					 errmsg("schedule \"%s\".\"%s\" cannot be disabled",
							obj.owner, obj.name)));
			break;
		default:
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("scheduler object \"%s\".\"%s\" does not exist",
							obj.owner, obj.name)));
	}

	SPI_finish();
	PG_RETURN_VOID();
}

/* ------------------------------------------------------------------
 * DROP_JOB / DROP_PROGRAM / DROP_SCHEDULE
 * ------------------------------------------------------------------
 */

Datum
ora_dbms_scheduler_drop_job(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	char	   *commit_semantics = text_arg_or_null(fcinfo, 3);
	SchedName	job;
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];

	/* "force" and "defer" are accepted for Oracle compatibility, ignored */

	SPI_connect();

	sched_check_commit_semantics(commit_semantics);
	sched_parse_name(raw_name, "job", &job);

	values[0] = CStringGetTextDatum(job.owner);
	values[1] = CStringGetTextDatum(job.name);
	if (sched_meta_dml("DELETE FROM sys.scheduler_jobs"
				  " WHERE job_owner = $1 AND job_name = $2",
				  2, argtypes, values, NULL) == 0)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("job \"%s\".\"%s\" does not exist",
						job.owner, job.name)));

	SPI_finish();
	PG_RETURN_VOID();
}

Datum
ora_dbms_scheduler_drop_program(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	bool		force = PG_ARGISNULL(1) ? false : PG_GETARG_BOOL(1);
	SchedName	prog;
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];
	uint64		dependents;

	SPI_connect();

	sched_parse_name(raw_name, "program", &prog);
	if (sched_object_kind(&prog) != SCHED_KIND_PROGRAM)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("program \"%s\".\"%s\" does not exist",
						prog.owner, prog.name)));

	values[0] = CStringGetTextDatum(prog.owner);
	values[1] = CStringGetTextDatum(prog.name);

	dependents = sched_meta_select("SELECT 1 FROM sys.scheduler_jobs"
							  " WHERE program_owner = $1 AND program_name = $2"
							  " LIMIT 1",
							  2, argtypes, values, NULL);
	if (dependents > 0)
	{
		if (!force)
			ereport(ERROR,
					(errcode(ERRCODE_DEPENDENT_OBJECTS_STILL_EXIST),
					 errmsg("program \"%s\".\"%s\" is referenced by jobs",
							prog.owner, prog.name),
					 errhint("Use force => true to disable the referencing jobs.")));

		/*
		 * A job that is running keeps the RUNNING state.  Only the run itself
		 * clears it, since that state is what holds the scheduler back from
		 * starting a second instance alongside the one already going.  No
		 * second run could be reached through here today in any case -- ENABLE
		 * refuses a job whose program is gone, so this one cannot go back in
		 * the schedule at all -- but the invariant is cheaper to keep in every
		 * writer than to re-establish by auditing them one at a time.
		 */
		sched_meta_dml("UPDATE sys.scheduler_jobs SET enabled = false,"
				  " state = CASE WHEN state = 'RUNNING' THEN state"
				  "              ELSE 'DISABLED' END,"
				  " next_run_date = NULL"
				  " WHERE program_owner = $1 AND program_name = $2",
				  2, argtypes, values, NULL);
	}

	sched_meta_dml("DELETE FROM sys.scheduler_programs"
			  " WHERE program_owner = $1 AND program_name = $2",
			  2, argtypes, values, NULL);

	SPI_finish();
	PG_RETURN_VOID();
}

Datum
ora_dbms_scheduler_drop_schedule(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	bool		force = PG_ARGISNULL(1) ? false : PG_GETARG_BOOL(1);
	SchedName	sched;
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];
	uint64		dependents;

	SPI_connect();

	sched_parse_name(raw_name, "schedule", &sched);
	if (sched_object_kind(&sched) != SCHED_KIND_SCHEDULE)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("schedule \"%s\".\"%s\" does not exist",
						sched.owner, sched.name)));

	values[0] = CStringGetTextDatum(sched.owner);
	values[1] = CStringGetTextDatum(sched.name);

	dependents = sched_meta_select("SELECT 1 FROM sys.scheduler_jobs"
							  " WHERE schedule_owner = $1 AND schedule_name = $2"
							  " LIMIT 1",
							  2, argtypes, values, NULL);
	if (dependents > 0)
	{
		if (!force)
			ereport(ERROR,
					(errcode(ERRCODE_DEPENDENT_OBJECTS_STILL_EXIST),
					 errmsg("schedule \"%s\".\"%s\" is referenced by jobs",
							sched.owner, sched.name),
					 errhint("Use force => true to disable the referencing jobs.")));

		/*
		 * A job that is running keeps the RUNNING state.  Only the run itself
		 * clears it, since that state is what holds the scheduler back from
		 * starting a second instance alongside the one already going.  No
		 * second run could be reached through here today in any case -- ENABLE
		 * refuses a job whose schedule is gone, so this one cannot go back in
		 * the schedule at all -- but the invariant is cheaper to keep in every
		 * writer than to re-establish by auditing them one at a time.
		 */
		sched_meta_dml("UPDATE sys.scheduler_jobs SET enabled = false,"
				  " state = CASE WHEN state = 'RUNNING' THEN state"
				  "              ELSE 'DISABLED' END,"
				  " next_run_date = NULL"
				  " WHERE schedule_owner = $1 AND schedule_name = $2",
				  2, argtypes, values, NULL);
	}

	sched_meta_dml("DELETE FROM sys.scheduler_schedules"
			  " WHERE schedule_owner = $1 AND schedule_name = $2",
			  2, argtypes, values, NULL);

	SPI_finish();
	PG_RETURN_VOID();
}

/* ------------------------------------------------------------------
 * EVALUATE_CALENDAR_STRING
 * ------------------------------------------------------------------
 */

Datum
ora_dbms_scheduler_evaluate_calendar_string(PG_FUNCTION_ARGS)
{
	char	   *calendar = text_arg_or_null(fcinfo, 0);
	TimestampTz start_date;
	TimestampTz after;
	TimestampTz next;

	if (calendar == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("calendar_string must not be null")));

	start_date = PG_ARGISNULL(1) ? GetCurrentTimestamp() : PG_GETARG_TIMESTAMPTZ(1);
	after = PG_ARGISNULL(2) ? GetCurrentTimestamp() : PG_GETARG_TIMESTAMPTZ(2);

	if (!sched_calendar_next(calendar, start_date, after, &next))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("calendar string \"%s\" does not yield a date after the given time",
						calendar)));

	PG_RETURN_TIMESTAMPTZ(next);
}

/* ------------------------------------------------------------------
 * RUN_JOB
 * ------------------------------------------------------------------
 */

/*
 * Load everything needed to execute a job.  Fills "def" (allocated by the
 * caller; strings are palloc'd in the current context).
 */
static void
sched_load_job_definition(const SchedName *job, SchedJobDef *def)
{
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];
	bool		isnull;
	Datum		d;
	char	   *prog_owner = NULL;
	char	   *prog_name = NULL;

	MemSet(def, 0, sizeof(SchedJobDef));
	def->job_owner = pstrdup(job->owner);
	def->job_name = pstrdup(job->name);

	values[0] = CStringGetTextDatum(job->owner);
	values[1] = CStringGetTextDatum(job->name);
	if (sched_meta_select("SELECT job_id, job_type, job_action,"
					 " number_of_arguments, program_owner, program_name"
					 " FROM sys.scheduler_jobs"
					 " WHERE job_owner = $1 AND job_name = $2",
					 2, argtypes, values, NULL) != 1)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("job \"%s\".\"%s\" does not exist",
						job->owner, job->name)));

	d = sched_getdatum(0, 1, &isnull);
	def->job_id = DatumGetInt64(d);
	def->job_type = sched_getstring(0, 2);
	def->job_action = sched_getstring(0, 3);
	d = sched_getdatum(0, 4, &isnull);
	def->number_of_arguments = isnull ? 0 : DatumGetInt32(d);
	prog_owner = sched_getstring(0, 5);
	prog_name = sched_getstring(0, 6);

	if (def->job_type == NULL)
	{
		Oid			at2[2] = {TEXTOID, TEXTOID};
		Datum		v2[2];

		if (prog_owner == NULL || prog_name == NULL)
			elog(ERROR, "job \"%s\".\"%s\" has an incomplete program reference",
				 job->owner, job->name);

		v2[0] = CStringGetTextDatum(prog_owner);
		v2[1] = CStringGetTextDatum(prog_name);
		if (sched_meta_select("SELECT program_type, program_action,"
						 " number_of_arguments, enabled"
						 " FROM sys.scheduler_programs"
						 " WHERE program_owner = $1 AND program_name = $2",
						 2, at2, v2, NULL) != 1)
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("program \"%s\".\"%s\" referenced by job \"%s\".\"%s\" does not exist",
							prog_owner, prog_name, job->owner, job->name)));
		def->job_type = sched_getstring(0, 1);
		def->job_action = sched_getstring(0, 2);
		d = sched_getdatum(0, 3, &isnull);
		def->number_of_arguments = isnull ? 0 : DatumGetInt32(d);

		/*
		 * ENABLE rejects a job whose program is disabled, but the program can
		 * be disabled afterwards; a run started from there has to fail rather
		 * than execute a program its owner took out of service.
		 */
		d = sched_getdatum(0, 4, &isnull);
		if (isnull || !DatumGetBool(d))
			ereport(ERROR,
					(errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
					 errmsg("program \"%s\".\"%s\" referenced by job \"%s\".\"%s\" is disabled",
							prog_owner, prog_name, job->owner, job->name)));
	}

	if (def->number_of_arguments > 0)
	{
		Oid			at5[5] = {TEXTOID, TEXTOID, TEXTOID, TEXTOID, INT4OID};
		Datum		v5[5];
		char		n5[5];
		uint64		nrows;
		uint64		row;

		def->arg_values = palloc0(sizeof(char *) * def->number_of_arguments);
		def->arg_types = palloc0(sizeof(char *) * def->number_of_arguments);

		v5[0] = CStringGetTextDatum(job->owner);
		v5[1] = CStringGetTextDatum(job->name);
		n5[0] = n5[1] = ' ';
		if (prog_name != NULL)
		{
			v5[2] = CStringGetTextDatum(prog_owner);
			v5[3] = CStringGetTextDatum(prog_name);
			n5[2] = n5[3] = ' ';
		}
		else
		{
			v5[2] = v5[3] = (Datum) 0;
			n5[2] = n5[3] = 'n';
		}
		v5[4] = Int32GetDatum(def->number_of_arguments);
		n5[4] = ' ';

		/* job-level values override program defaults */
		nrows = sched_meta_select("SELECT pos.pos,"
							 " COALESCE(ja.argument_value, pa.default_value),"
							 " (ja.argument_position IS NOT NULL"
							 "  OR COALESCE(pa.has_default, false)),"
							 " pa.argument_type"
							 " FROM generate_series(1, $5) pos(pos)"
							 " LEFT JOIN sys.scheduler_job_args ja"
							 "  ON ja.job_owner = $1 AND ja.job_name = $2"
							 "  AND ja.argument_position = pos.pos"
							 " LEFT JOIN sys.scheduler_program_args pa"
							 "  ON pa.program_owner = $3 AND pa.program_name = $4"
							 "  AND pa.argument_position = pos.pos"
							 " ORDER BY pos.pos",
							 5, at5, v5, n5);

		for (row = 0; row < nrows; row++)
		{
			bool		posnull;
			int			pos;
			Datum		dhas;
			bool		hasnull;

			pos = DatumGetInt32(sched_getdatum(row, 1, &posnull));
			if (pos < 1 || pos > def->number_of_arguments)
				continue;

			dhas = sched_getdatum(row, 3, &hasnull);
			if (hasnull || !DatumGetBool(dhas))
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
						 errmsg("argument %d of job \"%s\".\"%s\" has no value and no default",
								pos, job->owner, job->name)));

			def->arg_values[pos - 1] = sched_getstring(row, 2);
			def->arg_types[pos - 1] = sched_getstring(row, 4);
		}
	}
}

/*
 * Write one job run log record; returns the log_id.
 * "status" is 'r', 's' or 'f'.
 */
static int64
sched_log_start(const SchedJobDef *def, TimestampTz req_start,
				TimestampTz actual_start)
{
	Oid			argtypes[5] = {TEXTOID, TEXTOID, INT8OID, TIMESTAMPTZOID,
	TIMESTAMPTZOID};
	Datum		values[5];
	bool		isnull;
	Datum		d;

	values[0] = CStringGetTextDatum(def->job_owner);
	values[1] = CStringGetTextDatum(def->job_name);
	values[2] = Int64GetDatum(def->job_id);
	values[3] = TimestampTzGetDatum(req_start);
	values[4] = TimestampTzGetDatum(actual_start);

	if (sched_meta_dml("INSERT INTO sys.scheduler_job_run_details"
				  " (job_owner, job_name, job_id, status,"
				  "  req_start_date, actual_start_date, worker_pid,"
				  "  worker_backend_start)"
				  " VALUES ($1, $2, $3, 'r', $4, $5, pg_backend_pid(),"
				  "  (SELECT backend_start FROM pg_stat_activity"
				  "    WHERE pid = pg_backend_pid()))"
				  " RETURNING log_id",
				  5, argtypes, values, NULL) != 1)
		elog(ERROR, "could not insert job run log record");

	d = sched_getdatum(0, 1, &isnull);
	return DatumGetInt64(d);
}

/*
 * Publish the running process on a log row the launcher created, so STOP_JOB
 * can find the job worker.  Called by the worker once it is connected.
 */
void
sched_log_set_worker_pid(int64 log_id)
{
	Oid			argtypes[1] = {INT8OID};
	Datum		values[1];

	values[0] = Int64GetDatum(log_id);
	sched_meta_dml("UPDATE sys.scheduler_job_run_details"
			  " SET worker_pid = pg_backend_pid(),"
			  " worker_backend_start = (SELECT backend_start"
			  "   FROM pg_stat_activity WHERE pid = pg_backend_pid())"
			  " WHERE log_id = $1",
			  1, argtypes, values, NULL);
}

void
sched_log_finish(int64 log_id, bool success, int error_no,
				 const char *error_message, TimestampTz actual_start)
{
	Oid			argtypes[6] = {INT8OID, TEXTOID, INT4OID, TEXTOID, INTERVALOID,
	TIMESTAMPTZOID};
	Datum		values[6];
	char		nulls[6];
	Interval   *dur;
	TimestampTz now = GetCurrentTimestamp();

	dur = DatumGetIntervalP(DirectFunctionCall2(timestamp_mi,
												TimestampTzGetDatum(now),
												TimestampTzGetDatum(actual_start)));

	values[0] = Int64GetDatum(log_id);
	values[1] = CStringGetTextDatum(success ? "s" : "f");
	values[2] = Int32GetDatum(error_no);
	values[3] = error_message ? CStringGetTextDatum(error_message) : (Datum) 0;
	values[4] = IntervalPGetDatum(dur);
	values[5] = TimestampTzGetDatum(actual_start);
	memset(nulls, ' ', sizeof(nulls));
	if (error_message == NULL)
		nulls[3] = 'n';

	sched_meta_dml("UPDATE sys.scheduler_job_run_details"
			  " SET status = $2, error_no = $3, error_message = $4,"
			  " run_duration = $5, actual_start_date = $6"
			  " WHERE log_id = $1",
			  6, argtypes, values, nulls);
}

void
sched_update_job_stats(const SchedJobDef *def, bool success,
					   TimestampTz actual_start, bool background)
{
	Oid			argtypes[5] = {TEXTOID, TEXTOID, TIMESTAMPTZOID, TEXTOID, INT4OID};
	Datum		values[5];

	values[0] = CStringGetTextDatum(def->job_owner);
	values[1] = CStringGetTextDatum(def->job_name);
	values[2] = TimestampTzGetDatum(actual_start);
	values[3] = CStringGetTextDatum(success ? "SUCCEEDED" : "FAILED");
	values[4] = Int32GetDatum(scheduler_max_failures);

	/*
	 * Background runs return an enabled job to SCHEDULED (its next run date
	 * was already advanced when it was dispatched).  Manual runs leave the
	 * state of enabled jobs alone.  Jobs that ended up disabled (one-shot,
	 * end_date reached, or DISABLE while running) record the run outcome.
	 *
	 * failure_count counts *consecutive* failed background runs, as Oracle's
	 * max_failures does, so a successful one clears it.  Reaching the limit
	 * disables the job, which is Oracle's BROKEN state; we have no such state,
	 * so the run outcome is recorded instead.  Manual RUN_JOB failures still
	 * count, but never disable the job on their own -- the limit is about
	 * scheduled runs.
	 */
	if (background)
	{
		bool		hit_limit = false;

		/*
		 * Whether this failure is the one that crosses the limit has to be
		 * decided before the update: afterwards the previous enabled flag and
		 * failure count are gone, and a one-shot job -- already disabled when
		 * it was dispatched -- would look exactly the same.
		 */
		if (!success && scheduler_max_failures > 0)
		{
			Oid			at3[3] = {TEXTOID, TEXTOID, INT4OID};
			Datum		v3[3];
			bool		isnull;

			v3[0] = values[0];
			v3[1] = values[1];
			v3[2] = values[4];
			if (sched_meta_select("SELECT enabled AND failure_count + 1 >= $3"
								  " FROM sys.scheduler_jobs"
								  " WHERE job_owner = $1 AND job_name = $2",
								  3, at3, v3, NULL) == 1)
			{
				Datum		d = sched_getdatum(0, 1, &isnull);

				hit_limit = !isnull && DatumGetBool(d);
			}
		}

		sched_meta_dml("UPDATE sys.scheduler_jobs SET"
				  " run_count = run_count + 1,"
				  " failure_count = CASE WHEN $4 = 'FAILED' THEN failure_count + 1 ELSE 0 END,"
				  " last_start_date = $3, last_end_date = clock_timestamp(),"
				  " enabled = enabled AND NOT ($4 = 'FAILED' AND $5 > 0"
				  "                            AND failure_count + 1 >= $5),"
				  " next_run_date = CASE WHEN $4 = 'FAILED' AND $5 > 0"
				  "                       AND failure_count + 1 >= $5"
				  "                      THEN NULL ELSE next_run_date END,"
				  " state = CASE WHEN enabled AND NOT ($4 = 'FAILED' AND $5 > 0"
				  "                                   AND failure_count + 1 >= $5)"
				  "              THEN 'SCHEDULED' ELSE $4 END"
				  " WHERE job_owner = $1 AND job_name = $2",
				  5, argtypes, values, NULL);

		if (hit_limit)
			ereport(LOG,
					(errmsg("disabling scheduler job \"%s\".\"%s\" after %d consecutive failures",
							def->job_owner, def->job_name,
							scheduler_max_failures)));
	}
	else
		sched_meta_dml("UPDATE sys.scheduler_jobs SET"
				  " run_count = run_count + 1,"
				  " failure_count = failure_count + CASE WHEN $4 = 'FAILED' THEN 1 ELSE 0 END,"
				  " last_start_date = $3, last_end_date = clock_timestamp(),"
				  " state = CASE WHEN enabled THEN state ELSE $4 END"
				  " WHERE job_owner = $1 AND job_name = $2",
				  4, argtypes, values, NULL);
}

/*
 * Load a job definition by job_id, for the background job worker.
 * Returns false when the job no longer exists.
 */
bool
sched_load_job_by_id(int64 job_id, SchedJobDef *def)
{
	Oid			argtypes[1] = {INT8OID};
	Datum		values[1] = {Int64GetDatum(job_id)};
	SchedName	job;

	if (sched_meta_select("SELECT job_owner, job_name FROM sys.scheduler_jobs"
						  " WHERE job_id = $1",
						  1, argtypes, values, NULL) != 1)
		return false;

	job.owner = sched_getstring(0, 1);
	job.name = sched_getstring(0, 2);
	sched_load_job_definition(&job, def);
	return true;
}

/*
 * RUN_JOB runs the job in the calling session and leaves the job state alone,
 * so it is the one way a job can still be running twice at once here: the
 * scheduler holds a background run back while another background run is going,
 * but it has no way to see a foreground one.  Left as it is until there is
 * something to say what Oracle does with a RUN_JOB on a job that is already
 * running, rather than guessing at an error to raise.
 */
Datum
ora_dbms_scheduler_run_job(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	bool		use_current_session = PG_ARGISNULL(1) ? true : PG_GETARG_BOOL(1);
	SchedName	job;
	SchedJobDef def;
	TimestampTz start_ts;
	int64		log_id;
	int64		save_fg_job_id;
	char		save_job_name[sizeof(sched_job_name)];
	MemoryContext oldcontext;
	ResourceOwner oldowner;

	if (!use_current_session)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("use_current_session => false is not supported"),
				 errhint("Enable the job to have the scheduler run it in the background.")));

	SPI_connect();

	sched_parse_name(raw_name, "job", &job);
	sched_load_job_definition(&job, &def);

	start_ts = GetCurrentTimestamp();
	log_id = sched_log_start(&def, start_ts, start_ts);

	/*
	 * A job action is arbitrary SQL and may call RUN_JOB again, so the
	 * identity SYS_CONTEXT reports has to be saved and put back rather than
	 * cleared: otherwise the inner run would leave the outer one anonymous.
	 */
	save_fg_job_id = sched_fg_job_id;
	strlcpy(save_job_name, sched_job_name, sizeof(save_job_name));

	sched_fg_job_id = def.job_id;
	strlcpy(sched_job_name, def.job_name, sizeof(sched_job_name));

	oldcontext = CurrentMemoryContext;
	oldowner = CurrentResourceOwner;

	BeginInternalSubTransaction(NULL);
	MemoryContextSwitchTo(oldcontext);

	PG_TRY();
	{
		sched_execute_job(&def);

		ReleaseCurrentSubTransaction();
		MemoryContextSwitchTo(oldcontext);
		CurrentResourceOwner = oldowner;
	}
	PG_CATCH();
	{
		ErrorData  *edata;

		MemoryContextSwitchTo(oldcontext);
		edata = CopyErrorData();
		FlushErrorState();

		RollbackAndReleaseCurrentSubTransaction();
		MemoryContextSwitchTo(oldcontext);
		CurrentResourceOwner = oldowner;

		sched_fg_job_id = save_fg_job_id;
		strlcpy(sched_job_name, save_job_name, sizeof(sched_job_name));

		/*
		 * Record the failure and re-throw the job's error, matching Oracle:
		 * RUN_JOB surfaces the job error to the caller.  (If the caller's
		 * transaction subsequently aborts, the log record is lost with it;
		 * background runs do not have this limitation.)
		 */
		sched_log_finish(log_id, false, edata->sqlerrcode, edata->message,
						 start_ts);
		sched_update_job_stats(&def, false, start_ts, false);

		/*
		 * No SPI_finish() here: edata lives in the SPI procedure context,
		 * and transaction abort cleans the SPI stack up anyway.
		 */
		ReThrowError(edata);
	}
	PG_END_TRY();

	sched_fg_job_id = save_fg_job_id;
	strlcpy(sched_job_name, save_job_name, sizeof(sched_job_name));

	sched_log_finish(log_id, true, 0, NULL, start_ts);
	sched_update_job_stats(&def, true, start_ts, false);

	SPI_finish();
	PG_RETURN_VOID();
}

/*
 * STOP_JOB
 *
 * Signal the job worker recorded on the job's running log row.  Without
 * "force" the worker gets a query cancel, so it unwinds through its own
 * error handler and records the run as failed; with "force" it is terminated
 * outright, and the 'r' row it leaves behind is closed on the scheduler's
 * next cycle, when scheduler_reconcile_stopped() finds the worker gone.
 *
 * Unlike Oracle this cannot stop a job running in another database: the
 * dictionary is per-database, so a job is only visible where it lives.
 */
Datum
ora_dbms_scheduler_stop_job(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	bool		force = PG_ARGISNULL(1) ? false : PG_GETARG_BOOL(1);
	char	   *commit_semantics = text_arg_or_null(fcinfo, 2);
	SchedName	job;
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];
	Oid			pidtype[2] = {INT4OID, TIMESTAMPTZOID};
	Datum		pidvalue[2];
	int32		worker_pid;
	TimestampTz backend_start;
	bool		isnull;
	bool		startnull;
	Datum		signaled;

	SPI_connect();

	sched_check_commit_semantics(commit_semantics);
	sched_parse_name(raw_name, "job", &job);
	if (sched_object_kind(&job) != SCHED_KIND_JOB)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("job \"%s\".\"%s\" does not exist",
						job.owner, job.name)));

	values[0] = CStringGetTextDatum(job.owner);
	values[1] = CStringGetTextDatum(job.name);
	if (sched_meta_select("SELECT worker_pid, worker_backend_start"
					 " FROM sys.scheduler_job_run_details"
					 " WHERE job_owner = $1 AND job_name = $2 AND status = 'r'"
					 " ORDER BY log_id DESC LIMIT 1",
					 2, argtypes, values, NULL) != 1)
		ereport(ERROR,
				(errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
				 errmsg("job \"%s\".\"%s\" is not running",
						job.owner, job.name)));

	worker_pid = DatumGetInt32(sched_getdatum(0, 1, &isnull));
	backend_start = DatumGetTimestampTz(sched_getdatum(0, 2, &startnull));
	if (isnull || startnull)
		ereport(ERROR,
				(errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
				 errmsg("job \"%s\".\"%s\" has no recorded worker process",
						job.owner, job.name)));

	/*
	 * Signal the recorded process only while it is still the one that took
	 * this run.  A row that says 'r' does not prove that: a crash leaves the
	 * row behind, and the pid it names is then free to be reused.  Matching
	 * the start time as well identifies the backend exactly, so a stale row
	 * reports "not running" instead of cancelling somebody else's session
	 * with the metadata owner's rights.
	 */
	pidvalue[0] = Int32GetDatum(worker_pid);
	pidvalue[1] = TimestampTzGetDatum(backend_start);
	if (sched_meta_select(force ?
						  "SELECT pg_terminate_backend(pid)"
						  " FROM pg_stat_activity"
						  " WHERE pid = $1 AND backend_start = $2"
						  "   AND datname = current_database()" :
						  "SELECT pg_cancel_backend(pid)"
						  " FROM pg_stat_activity"
						  " WHERE pid = $1 AND backend_start = $2"
						  "   AND datname = current_database()",
						  2, pidtype, pidvalue, NULL) != 1)
		ereport(ERROR,
				(errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
				 errmsg("job \"%s\".\"%s\" is not running",
						job.owner, job.name),
				 errdetail("The process recorded for the run is gone; its log record is closed once the scheduler notices, or by orphan cleanup at the next scheduler start.")));

	signaled = sched_getdatum(0, 1, &isnull);
	if (isnull || !DatumGetBool(signaled))
		ereport(ERROR,
				(errcode(ERRCODE_SYSTEM_ERROR),
				 errmsg("could not signal process %d running job \"%s\".\"%s\"",
						worker_pid, job.owner, job.name)));

	SPI_finish();
	PG_RETURN_VOID();
}

/* ------------------------------------------------------------------
 * PURGE_LOG
 * ------------------------------------------------------------------
 */

/*
 * Delete job run history.  Shared by PURGE_LOG and by the scheduler's
 * automatic retention, which differ only in how they arrive at the arguments.
 *
 * A row goes when it is older than "cutoff" and matches "owner" and
 * "job_name", each of which is optional: a cutoff of DT_NOEND (+infinity,
 * under which every row is old) drops the age restriction, and a NULL owner
 * or job_name drops that one.  Only the restrictions that apply are built
 * into the statement, so purging one job's history can use
 * scheduler_job_run_details_job_idx rather than being flattened into a seq
 * scan by a "$n IS NULL OR col = $n" catch-all.  No argument value is ever
 * formatted into the text; only $n placeholders are.
 *
 * "batch_limit" above zero deletes at most that many rows, oldest first, so
 * that a first purge of a table that has been accumulating for months can be
 * driven in bounded transactions.  The subquery walks the primary key from
 * its low end and stops once it has enough, which is why no index on
 * log_date is needed - log_id and log_date rise together, and this table is
 * written on every job run, so it is the wrong place for a second index.
 *
 * Runs in progress are never deleted, whatever the arguments say: the worker
 * that owns an 'r' row is still going to update it by log_id, and what it
 * writes is the only record that the run happened at all.  ('r' rows do not
 * accumulate: scheduler_cleanup_orphans() closes the ones a crash leaves
 * behind at the next scheduler start.)
 *
 * Returns the number of rows deleted.  The caller must be SPI-connected.
 */
uint64
sched_purge_log(TimestampTz cutoff, const char *owner, const char *job_name,
				int batch_limit)
{
	StringInfoData pred;
	StringInfoData sql;
	Oid			argtypes[4];
	Datum		values[4];
	int			nargs = 0;

	initStringInfo(&pred);
	appendStringInfoString(&pred, "status <> 'r'");

	if (!TIMESTAMP_IS_NOEND(cutoff))
	{
		argtypes[nargs] = TIMESTAMPTZOID;
		values[nargs++] = TimestampTzGetDatum(cutoff);
		appendStringInfo(&pred, " AND log_date < $%d", nargs);
	}
	if (owner != NULL)
	{
		argtypes[nargs] = TEXTOID;
		values[nargs++] = CStringGetTextDatum(owner);
		appendStringInfo(&pred, " AND job_owner = $%d", nargs);
	}
	if (job_name != NULL)
	{
		argtypes[nargs] = TEXTOID;
		values[nargs++] = CStringGetTextDatum(job_name);
		appendStringInfo(&pred, " AND job_name = $%d", nargs);
	}

	initStringInfo(&sql);
	if (batch_limit > 0)
	{
		argtypes[nargs] = INT4OID;
		values[nargs++] = Int32GetDatum(batch_limit);
		appendStringInfo(&sql,
						 "DELETE FROM sys.scheduler_job_run_details"
						 " WHERE log_id IN (SELECT log_id"
						 "   FROM sys.scheduler_job_run_details"
						 "   WHERE %s ORDER BY log_id LIMIT $%d)",
						 pred.data, nargs);
	}
	else
		appendStringInfo(&sql,
						 "DELETE FROM sys.scheduler_job_run_details WHERE %s",
						 pred.data);

	return sched_meta_dml(sql.data, nargs, argtypes, values, NULL);
}

/*
 * PURGE_LOG
 *
 * Delete rows from the job run log.
 *
 * Oracle's which_log chooses between the job log and the window log; there
 * are no windows here, so only the job half of a value has anything to do and
 * WINDOW_LOG on its own purges nothing.
 *
 * A superuser purges whatever the arguments select.  For anyone else the
 * purge is confined to their own jobs, the way the USER_SCHEDULER_* views
 * show only their own rows: the call succeeds, it just cannot reach another
 * user's history.  That is a filter rather than a check, and it applies only
 * when no job is named - a job named as someone else's is refused outright by
 * sched_parse_name().
 */
Datum
ora_dbms_scheduler_purge_log(PG_FUNCTION_ARGS)
{
	int32		log_history;
	char	   *raw_which_log = text_arg_or_null(fcinfo, 1);
	char	   *raw_name = text_arg_or_null(fcinfo, 2);
	char	   *which_log;
	char	   *owner = NULL;
	char	   *job_name = NULL;
	TimestampTz cutoff;

	/*
	 * A null log_history is refused rather than read as the default of 0.
	 * Elsewhere in this file a null argument means "not supplied, use the
	 * default", and by that rule this one would be 0, which is also Oracle's
	 * default.  But 0 here is not a neutral default, it is the most
	 * destructive value the argument has, and the usual way to arrive at a
	 * null is purge_log(log_history => v_days) with v_days never assigned.
	 * Refusing it also leaves the choice open: accepting null as 0 later is a
	 * compatible relaxation, where the reverse would break callers.
	 */
	if (PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("log_history must not be null"),
				 errhint("Pass 0 to purge the whole log.")));
	log_history = PG_GETARG_INT32(0);

	/*
	 * A negative retention would put the cutoff in the future and so quietly
	 * behave as "delete everything", the same trap as the null above.
	 */
	if (log_history < 0 || log_history > SCHED_MAX_LOG_HISTORY)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("log_history %d is out of range (0 .. %d)",
						log_history, SCHED_MAX_LOG_HISTORY)));

	/*
	 * Oracle takes a comma-separated list of job or job class names here, as
	 * in PURGE_LOG(log_history => 10, job_name => 'job1, sys.class2').  Only
	 * a single job name is supported, and the list has to be turned away
	 * explicitly: sched_parse_name() reads an unquoted part up to the next
	 * '.' or the end of the string, so 'a,b' would come back as the one name
	 * A,B and the purge would match nothing at all.  A quoted name that
	 * really does contain a comma is refused along with it, which is the
	 * price of testing before parsing.
	 */
	if (raw_name != NULL && strchr(raw_name, ',') != NULL)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("purging the log of a list of jobs is not supported"),
				 errhint("Call PURGE_LOG once per job, or leave job_name out to purge every job's log.")));

	SPI_connect();

	which_log = sched_check_which_log(raw_which_log);

	if (raw_name != NULL)
	{
		SchedName	job;

		/*
		 * Resolves an unqualified name against the invoking user and refuses
		 * another user's name unless the caller is a superuser.  There is no
		 * check that the job still exists: the log has no foreign key to it
		 * precisely because history outlives its job, so the rows a purge is
		 * most often aimed at are those whose job is already gone.  A name
		 * that matches nothing deletes nothing, which also leaves a cleanup
		 * script safe to run twice.
		 */
		sched_parse_name(raw_name, "job", &job);
		owner = job.owner;
		job_name = job.name;
	}
	else if (!superuser())
	{
		/*
		 * Read the caller's name here, before the first sched_meta_dml():
		 * that escalates to the metadata tables' owner, so a current_user in
		 * the statement text would name the extension owner and the
		 * restriction would restrict nothing.
		 */
		owner = GetUserNameFromId(GetUserId(), false);
	}

	/* Oracle's reading of zero: keep no history */
	if (log_history == 0)
		cutoff = DT_NOEND;
	else
		cutoff = GetCurrentTimestamp() -
			(TimestampTz) log_history * USECS_PER_DAY;

	if (strcmp(which_log, "WINDOW_LOG") == 0)
		ereport(WARNING,
				(errmsg("there is no window log to purge"),
				 errhint("Use JOB_LOG or JOB_AND_WINDOW_LOG to purge the job run log.")));
	else
		(void) sched_purge_log(cutoff, owner, job_name, 0);

	SPI_finish();
	PG_RETURN_VOID();
}

/* ------------------------------------------------------------------
 * SYS_CONTEXT('USERENV', ...) readers
 * ------------------------------------------------------------------
 */

Datum
ora_dbms_scheduler_get_bg_job_id(PG_FUNCTION_ARGS)
{
	char		buf[32];

	if (sched_bg_job_id <= 0)
		PG_RETURN_NULL();
	snprintf(buf, sizeof(buf), INT64_FORMAT, sched_bg_job_id);
	PG_RETURN_TEXT_P(cstring_to_text(buf));
}

Datum
ora_dbms_scheduler_get_fg_job_id(PG_FUNCTION_ARGS)
{
	char		buf[32];

	if (sched_fg_job_id <= 0)
		PG_RETURN_NULL();
	snprintf(buf, sizeof(buf), INT64_FORMAT, sched_fg_job_id);
	PG_RETURN_TEXT_P(cstring_to_text(buf));
}

Datum
ora_dbms_scheduler_get_scheduler_job(PG_FUNCTION_ARGS)
{
	if (sched_job_name[0] == '\0')
		PG_RETURN_NULL();
	PG_RETURN_TEXT_P(cstring_to_text(sched_job_name));
}
