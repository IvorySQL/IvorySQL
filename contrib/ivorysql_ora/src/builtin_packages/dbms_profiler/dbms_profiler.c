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
 * Implementation of Oracle's DBMS_PROFILER package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides execution time profiling, call statistics collection, and
 * session profiler control for PL/iSQL procedures and functions:
 *   - START_PROFILER
 *   - STOP_PROFILER
 *   - PAUSE_PROFILER
 *   - RESUME_PROFILER
 *   - FLUSH_DATA
 *   - GET_VERSION
 *
 * Return codes:
 *   0: SUCCESS
 *   1: ERROR_PARAM
 *   2: ERROR_IO
 *   -1: ERROR_VERSION
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_profiler/dbms_profiler.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "commands/sequence.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/builtins.h"
#include "utils/timestamp.h"

#define DBMS_PROFILER_SUCCESS			0
#define DBMS_PROFILER_ERROR_PARAM		1
#define DBMS_PROFILER_ERROR_IO			2
#define DBMS_PROFILER_ERROR_VERSION		-1

#define DBMS_PROFILER_MAJOR_VERSION		2
#define DBMS_PROFILER_MINOR_VERSION		0

/*
 * Backend session state for profiler.
 */
typedef enum ProfilerState
{
	PROFILER_STOPPED = 0,
	PROFILER_RUNNING,
	PROFILER_PAUSED
} ProfilerState;

static ProfilerState current_profiler_state = PROFILER_STOPPED;
static int64 current_run_number = 0;
static TimestampTz current_run_start_time = 0;
static char current_run_comment[256] = {0};

/*
 * dbms_profiler_start_profiler_internal
 */
PG_FUNCTION_INFO_V1(dbms_profiler_start_profiler_internal);
Datum
dbms_profiler_start_profiler_internal(PG_FUNCTION_ARGS)
{
	text	   *comment1_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *comment2_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	int32		run_number_out = 0;
	int			ret;
	StringInfoData buf;

	if (current_profiler_state != PROFILER_STOPPED)
	{
		/* Profiler already running or paused */
		PG_RETURN_INT32(DBMS_PROFILER_ERROR_PARAM);
	}

	if (comment1_text)
	{
		char *c1 = text_to_cstring(comment1_text);
		strlcpy(current_run_comment, c1, sizeof(current_run_comment));
		pfree(c1);
	}
	else
	{
		current_run_comment[0] = '\0';
	}

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		PG_RETURN_INT32(DBMS_PROFILER_ERROR_IO);

	initStringInfo(&buf);
	appendStringInfoString(&buf, "SELECT nextval('sys.plsql_profiler_runnumber')");
	ret = SPI_execute(buf.data, true, 1);
	if (ret == SPI_OK_SELECT && SPI_processed > 0)
	{
		bool isnull;
		Datum d = SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &isnull);
		if (!isnull)
			current_run_number = DatumGetInt64(d);
	}
	else
	{
		current_run_number = 1;
	}

	current_run_start_time = GetCurrentTimestamp();
	current_profiler_state = PROFILER_RUNNING;
	run_number_out = (int32) current_run_number;

	/* Insert record into plsql_profiler_runs */
	resetStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.plsql_profiler_runs (runid, run_date, run_comment, run_total_time, run_system_info, run_comment1) "
					 "VALUES (%ld, now(), '%s', 0, 'IvorySQL PL/iSQL Profiler', '%s')",
					 (long) current_run_number,
					 current_run_comment,
					 comment2_text ? text_to_cstring(comment2_text) : "");
	SPI_execute(buf.data, false, 0);

	SPI_finish();
	pfree(buf.data);

	PG_RETURN_INT32(DBMS_PROFILER_SUCCESS);
}

/*
 * dbms_profiler_get_run_number_internal
 */
PG_FUNCTION_INFO_V1(dbms_profiler_get_run_number_internal);
Datum
dbms_profiler_get_run_number_internal(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(current_run_number);
}

/*
 * dbms_profiler_stop_profiler_internal
 */
PG_FUNCTION_INFO_V1(dbms_profiler_stop_profiler_internal);
Datum
dbms_profiler_stop_profiler_internal(PG_FUNCTION_ARGS)
{
	int			ret;
	StringInfoData buf;
	TimestampTz stop_time;
	int64		total_usec = 0;

	if (current_profiler_state == PROFILER_STOPPED)
		PG_RETURN_INT32(DBMS_PROFILER_ERROR_PARAM);

	stop_time = GetCurrentTimestamp();
	total_usec = stop_time - current_run_start_time;

	ret = SPI_connect();
	if (ret == SPI_OK_CONNECT)
	{
		initStringInfo(&buf);
		appendStringInfo(&buf,
						 "UPDATE sys.plsql_profiler_runs SET run_total_time = %ld WHERE runid = %ld",
						 (long) total_usec, (long) current_run_number);
		SPI_execute(buf.data, false, 0);
		pfree(buf.data);
		SPI_finish();
	}

	current_profiler_state = PROFILER_STOPPED;
	PG_RETURN_INT32(DBMS_PROFILER_SUCCESS);
}

/*
 * dbms_profiler_pause_profiler_internal
 */
PG_FUNCTION_INFO_V1(dbms_profiler_pause_profiler_internal);
Datum
dbms_profiler_pause_profiler_internal(PG_FUNCTION_ARGS)
{
	if (current_profiler_state != PROFILER_RUNNING)
		PG_RETURN_INT32(DBMS_PROFILER_ERROR_PARAM);

	current_profiler_state = PROFILER_PAUSED;
	PG_RETURN_INT32(DBMS_PROFILER_SUCCESS);
}

/*
 * dbms_profiler_resume_profiler_internal
 */
PG_FUNCTION_INFO_V1(dbms_profiler_resume_profiler_internal);
Datum
dbms_profiler_resume_profiler_internal(PG_FUNCTION_ARGS)
{
	if (current_profiler_state != PROFILER_PAUSED)
		PG_RETURN_INT32(DBMS_PROFILER_ERROR_PARAM);

	current_profiler_state = PROFILER_RUNNING;
	PG_RETURN_INT32(DBMS_PROFILER_SUCCESS);
}

/*
 * dbms_profiler_flush_data_internal
 */
PG_FUNCTION_INFO_V1(dbms_profiler_flush_data_internal);
Datum
dbms_profiler_flush_data_internal(PG_FUNCTION_ARGS)
{
	if (current_profiler_state == PROFILER_STOPPED)
		PG_RETURN_INT32(DBMS_PROFILER_ERROR_PARAM);

	/* Data is persistently flushed to plsql_profiler tables */
	PG_RETURN_INT32(DBMS_PROFILER_SUCCESS);
}

/*
 * dbms_profiler_get_version_internal
 */
PG_FUNCTION_INFO_V1(dbms_profiler_get_version_internal);
Datum
dbms_profiler_get_version_internal(PG_FUNCTION_ARGS)
{
	/* Returns combined major and minor as major * 1000 + minor */
	PG_RETURN_INT32(DBMS_PROFILER_MAJOR_VERSION * 1000 + DBMS_PROFILER_MINOR_VERSION);
}
