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
 * Implementation of Oracle's DBMS_ALERT package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides asynchronous event notification across sessions:
 *   - REGISTER: registers session interest in an alert.
 *   - REMOVE: unregisters interest in an alert.
 *   - REMOVEALL: unregisters interest in all alerts for the session.
 *   - SIGNAL: signals an alert with a message.
 *   - WAITONE: waits for a specific alert.
 *   - WAITANY: waits for any registered alert.
 *
 * Status codes:
 *   0: Alert occurred
 *   1: Timeout occurred
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_alert/dbms_alert.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "utils/builtins.h"

#define DBMS_ALERT_SUCCESS		0
#define DBMS_ALERT_TIMEOUT		1

/*
 * dbms_alert_register_internal
 */
PG_FUNCTION_INFO_V1(dbms_alert_register_internal);
Datum
dbms_alert_register_internal(PG_FUNCTION_ARGS)
{
	text	   *name_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *name;
	StringInfoData buf;
	int			ret;

	if (!name_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_ALERT.REGISTER: alert name must not be NULL")));

	name = text_to_cstring(name_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.alert_registrations (alert_name, session_pid, registered_time) "
					 "VALUES ('%s', %d, now()) "
					 "ON CONFLICT (alert_name, session_pid) DO NOTHING",
					 name, MyProcPid);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_alert_remove_internal
 */
PG_FUNCTION_INFO_V1(dbms_alert_remove_internal);
Datum
dbms_alert_remove_internal(PG_FUNCTION_ARGS)
{
	text	   *name_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *name;
	StringInfoData buf;
	int			ret;

	if (!name_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_ALERT.REMOVE: alert name must not be NULL")));

	name = text_to_cstring(name_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "DELETE FROM sys.alert_registrations WHERE alert_name = '%s' AND session_pid = %d",
					 name, MyProcPid);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_alert_removeall_internal
 */
PG_FUNCTION_INFO_V1(dbms_alert_removeall_internal);
Datum
dbms_alert_removeall_internal(PG_FUNCTION_ARGS)
{
	StringInfoData buf;
	int			ret;

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "DELETE FROM sys.alert_registrations WHERE session_pid = %d",
					 MyProcPid);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_alert_signal_internal
 */
PG_FUNCTION_INFO_V1(dbms_alert_signal_internal);
Datum
dbms_alert_signal_internal(PG_FUNCTION_ARGS)
{
	text	   *name_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *msg_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	char	   *name;
	char	   *msg;
	StringInfoData buf;
	int			ret;

	if (!name_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_ALERT.SIGNAL: alert name must not be NULL")));

	name = text_to_cstring(name_text);
	msg = msg_text ? text_to_cstring(msg_text) : "";

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.alert_signals (alert_name, message, signaled_time) "
					 "VALUES ('%s', '%s', now()) "
					 "ON CONFLICT (alert_name) DO UPDATE SET message = EXCLUDED.message, signaled_time = now()",
					 name, msg);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(name);
	if (msg_text)
		pfree(msg);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_alert_waitone_internal
 * Returns composite: (message text, status integer)
 */
PG_FUNCTION_INFO_V1(dbms_alert_waitone_internal);
Datum
dbms_alert_waitone_internal(PG_FUNCTION_ARGS)
{
	text	   *name_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	float8		timeout_sec = PG_GETARG_FLOAT8(1);
	char	   *name;
	StringInfoData buf;
	int			ret;
	TupleDesc	tupdesc;
	Datum		values[2];
	bool		nulls[2];
	HeapTuple	tuple;
	char	   *found_msg = NULL;
	int32		status = DBMS_ALERT_TIMEOUT;

	if (!name_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_ALERT.WAITONE: alert name must not be NULL")));

	name = text_to_cstring(name_text);

	ret = SPI_connect();
	if (ret == SPI_OK_CONNECT)
	{
		initStringInfo(&buf);
		appendStringInfo(&buf,
						 "SELECT message FROM sys.alert_signals WHERE alert_name = '%s'",
						 name);
		ret = SPI_execute(buf.data, true, 1);
		if (ret == SPI_OK_SELECT && SPI_processed > 0)
		{
			bool isnull;
			Datum d = SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &isnull);
			if (!isnull)
			{
				found_msg = TextDatumGetCString(d);
				status = DBMS_ALERT_SUCCESS;
			}
		}
		pfree(buf.data);
		SPI_finish();
	}

	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function-returning composite type called in non-composite context")));

	tupdesc = BlessTupleDesc(tupdesc);

	memset(nulls, 0, sizeof(nulls));
	if (found_msg)
		values[0] = CStringGetTextDatum(found_msg);
	else
	{
		values[0] = CStringGetTextDatum("");
		nulls[0] = false;
	}
	values[1] = Int32GetDatum(status);

	tuple = heap_form_tuple(tupdesc, values, nulls);
	pfree(name);
	if (found_msg)
		pfree(found_msg);

	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}
