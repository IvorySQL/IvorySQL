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
 * The metadata lives in ordinary sys.scheduler_* tables protected by row
 * level security; every write goes through these functions, which validate
 * ownership as the invoking user and then perform the DML with the rights
 * of the metadata tables' owner.
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
PG_FUNCTION_INFO_V1(ora_dbms_scheduler_run_job);
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

static void
sched_check_name_free(const SchedName *n, const char *what)
{
	if (sched_object_kind(n) != SCHED_KIND_NONE)
		ereport(ERROR,
				(errcode(ERRCODE_DUPLICATE_OBJECT),
				 errmsg("scheduler object \"%s\".\"%s\" already exists",
						n->owner, n->name),
				 errdetail("Jobs, programs and schedules share one namespace.")));

	(void) what;
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

	values[0] = CStringGetTextDatum(job_owner);
	values[1] = CStringGetTextDatum(job_name);
	nulls[0] = nulls[1] = ' ';
	if (prog_name != NULL)
	{
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
 * Is the current database covered by ivorysql_ora.scheduler_databases?
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
		sched_meta_dml("UPDATE sys.scheduler_jobs SET enabled = true,"
				  " state = 'SCHEDULED', next_run_date = $3"
				  " WHERE job_owner = $1 AND job_name = $2",
				  3, at3, v3, NULL);
	}

	if (!scheduler_launcher_registered || !scheduler_enabled)
		ereport(WARNING,
				(errmsg("the scheduler background launcher is not running; job \"%s\".\"%s\" will not run automatically",
						job->owner, job->name),
				 errhint("Add ivorysql_ora to shared_preload_libraries and set ivorysql_ora.scheduler = on.")));
	else if (!sched_current_database_is_scheduled())
		ereport(WARNING,
				(errmsg("database \"%s\" is not scheduled; job \"%s\".\"%s\" will not run automatically",
						get_database_name(MyDatabaseId), job->owner, job->name),
				 errhint("Add the database to ivorysql_ora.scheduler_databases.")));
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
	Oid			argtypes[10] = {TEXTOID, TEXTOID, TEXTOID, TEXTOID, INT4OID,
	TIMESTAMPTZOID, TEXTOID, TIMESTAMPTZOID, TEXTOID, BOOLOID};
	Datum		values[10];
	char		nulls[10];

	SPI_connect();

	sched_parse_name(raw_name, "job", &job);
	sched_check_name_free(&job, "job");

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
	memset(nulls, ' ', sizeof(nulls));
	if (start_isnull)
		nulls[5] = 'n';
	if (repeat_interval == NULL)
		nulls[6] = 'n';
	if (end_isnull)
		nulls[7] = 'n';
	if (job_class == NULL)
		nulls[8] = 'n';

	sched_meta_dml("INSERT INTO sys.scheduler_jobs"
			  " (job_owner, job_name, job_type, job_action,"
			  "  number_of_arguments, start_date, repeat_interval, end_date,"
			  "  job_class, auto_drop, comments)"
			  " VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NULL)",
			  10, argtypes, values, nulls);

	if (comments != NULL)
	{
		Oid			at[3] = {TEXTOID, TEXTOID, TEXTOID};
		Datum		v[3];

		v[0] = values[0];
		v[1] = values[1];
		v[2] = CStringGetTextDatum(comments);
		sched_meta_dml("UPDATE sys.scheduler_jobs SET comments = $3"
				  " WHERE job_owner = $1 AND job_name = $2",
				  3, at, v, NULL);
	}

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
	sched_check_name_free(&job, "job");

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
	sched_check_name_free(&prog, "program");

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
	Oid			argtypes[5] = {TEXTOID, TEXTOID, TIMESTAMPTZOID, TEXTOID, TIMESTAMPTZOID};
	Datum		values[5];
	char		nulls[5];

	SPI_connect();

	sched_parse_name(raw_name, "schedule", &sched);
	sched_check_name_free(&sched, "schedule");

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
	memset(nulls, ' ', sizeof(nulls));
	if (start_isnull)
		nulls[2] = 'n';
	if (repeat_interval == NULL)
		nulls[3] = 'n';
	if (end_isnull)
		nulls[4] = 'n';

	sched_meta_dml("INSERT INTO sys.scheduler_schedules"
			  " (schedule_owner, schedule_name, start_date, repeat_interval,"
			  "  end_date)"
			  " VALUES ($1, $2, $3, $4, $5)",
			  5, argtypes, values, nulls);

	if (comments != NULL)
	{
		Oid			at[3] = {TEXTOID, TEXTOID, TEXTOID};
		Datum		v[3];

		v[0] = values[0];
		v[1] = values[1];
		v[2] = CStringGetTextDatum(comments);
		sched_meta_dml("UPDATE sys.scheduler_schedules SET comments = $3"
				  " WHERE schedule_owner = $1 AND schedule_name = $2",
				  3, at, v, NULL);
	}

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
	const char *p;
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

	p = argument_name;
	argument_name = sched_parse_name_part(&p, argument_name, "argument");

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
			sched_meta_dml("UPDATE sys.scheduler_jobs SET enabled = false,"
					  " state = 'DISABLED', next_run_date = NULL"
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

		sched_meta_dml("UPDATE sys.scheduler_jobs SET enabled = false,"
				  " state = 'DISABLED', next_run_date = NULL"
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

		sched_meta_dml("UPDATE sys.scheduler_jobs SET enabled = false,"
				  " state = 'DISABLED', next_run_date = NULL"
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

		v2[0] = CStringGetTextDatum(prog_owner);
		v2[1] = CStringGetTextDatum(prog_name);
		if (sched_meta_select("SELECT program_type, program_action,"
						 " number_of_arguments"
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
	}

	if (def->number_of_arguments > 0)
	{
		Oid			at5[5] = {TEXTOID, TEXTOID, TEXTOID, TEXTOID, INT4OID};
		Datum		v5[5];
		char		n5[5];
		uint64		nrows;
		uint64		row;

		def->arg_values = palloc0(sizeof(char *) * def->number_of_arguments);

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
							 "  OR COALESCE(pa.has_default, false))"
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
				  "  req_start_date, actual_start_date)"
				  " VALUES ($1, $2, $3, 'r', $4, $5)"
				  " RETURNING log_id",
				  5, argtypes, values, NULL) != 1)
		elog(ERROR, "could not insert job run log record");

	d = sched_getdatum(0, 1, &isnull);
	return DatumGetInt64(d);
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
	Oid			argtypes[4] = {TEXTOID, TEXTOID, TIMESTAMPTZOID, TEXTOID};
	Datum		values[4];

	values[0] = CStringGetTextDatum(def->job_owner);
	values[1] = CStringGetTextDatum(def->job_name);
	values[2] = TimestampTzGetDatum(actual_start);
	values[3] = CStringGetTextDatum(success ? "SUCCEEDED" : "FAILED");

	/*
	 * Background runs return an enabled job to SCHEDULED (its next run date
	 * was already advanced when it was dispatched).  Manual runs leave the
	 * state of enabled jobs alone.  Jobs that ended up disabled (one-shot,
	 * end_date reached, or DISABLE while running) record the run outcome.
	 */
	if (background)
		sched_meta_dml("UPDATE sys.scheduler_jobs SET"
				  " run_count = run_count + 1,"
				  " failure_count = failure_count + CASE WHEN $4 = 'FAILED' THEN 1 ELSE 0 END,"
				  " last_start_date = $3, last_end_date = clock_timestamp(),"
				  " state = CASE WHEN enabled THEN 'SCHEDULED' ELSE $4 END"
				  " WHERE job_owner = $1 AND job_name = $2",
				  4, argtypes, values, NULL);
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

Datum
ora_dbms_scheduler_run_job(PG_FUNCTION_ARGS)
{
	char	   *raw_name = text_arg_or_null(fcinfo, 0);
	bool		use_current_session = PG_ARGISNULL(1) ? true : PG_GETARG_BOOL(1);
	SchedName	job;
	SchedJobDef def;
	TimestampTz start_ts;
	int64		log_id;
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

		sched_fg_job_id = 0;
		sched_job_name[0] = '\0';

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

	sched_fg_job_id = 0;
	sched_job_name[0] = '\0';

	sched_log_finish(log_id, true, 0, NULL, start_ts);
	sched_update_job_stats(&def, true, start_ts, false);

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
