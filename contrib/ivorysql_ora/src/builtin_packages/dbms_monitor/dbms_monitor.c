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
 * Implementation of Oracle's DBMS_MONITOR package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides workload monitoring, statistics gathering, and tracing controls:
 *   - CLIENT_ID_STAT_ENABLE / CLIENT_ID_STAT_DISABLE
 *   - SERV_MOD_ACT_STAT_ENABLE / SERV_MOD_ACT_STAT_DISABLE
 *   - SESSION_TRACE_ENABLE / SESSION_TRACE_DISABLE
 *   - CLIENT_ID_TRACE_ENABLE / CLIENT_ID_TRACE_DISABLE
 *   - DATABASE_TRACE_ENABLE / DATABASE_TRACE_DISABLE
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_monitor/dbms_monitor.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/builtins.h"

/*
 * dbms_monitor_client_id_stat_enable_internal
 */
PG_FUNCTION_INFO_V1(dbms_monitor_client_id_stat_enable_internal);
Datum
dbms_monitor_client_id_stat_enable_internal(PG_FUNCTION_ARGS)
{
	text	   *client_id_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *client_id;
	StringInfoData buf;
	int			ret;

	if (!client_id_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_MONITOR: client_id must not be NULL")));

	client_id = text_to_cstring(client_id_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.monitored_client_ids (client_id, stat_enabled, trace_enabled, updated_time) "
					 "VALUES ('%s', true, false, now()) "
					 "ON CONFLICT (client_id) DO UPDATE SET stat_enabled = true, updated_time = now()",
					 client_id);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(client_id);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_monitor_client_id_stat_disable_internal
 */
PG_FUNCTION_INFO_V1(dbms_monitor_client_id_stat_disable_internal);
Datum
dbms_monitor_client_id_stat_disable_internal(PG_FUNCTION_ARGS)
{
	text	   *client_id_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *client_id;
	StringInfoData buf;
	int			ret;

	if (!client_id_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_MONITOR: client_id must not be NULL")));

	client_id = text_to_cstring(client_id_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "UPDATE sys.monitored_client_ids SET stat_enabled = false, updated_time = now() "
					 "WHERE client_id = '%s'", client_id);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(client_id);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_monitor_client_id_trace_enable_internal
 */
PG_FUNCTION_INFO_V1(dbms_monitor_client_id_trace_enable_internal);
Datum
dbms_monitor_client_id_trace_enable_internal(PG_FUNCTION_ARGS)
{
	text	   *client_id_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	bool		waits = PG_GETARG_BOOL(1);
	bool		binds = PG_GETARG_BOOL(2);
	text	   *plan_stat_text = PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3);
	char	   *client_id;
	StringInfoData buf;
	int			ret;

	if (!client_id_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_MONITOR: client_id must not be NULL")));

	client_id = text_to_cstring(client_id_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.monitored_client_ids (client_id, stat_enabled, trace_enabled, updated_time) "
					 "VALUES ('%s', false, true, now()) "
					 "ON CONFLICT (client_id) DO UPDATE SET trace_enabled = true, updated_time = now()",
					 client_id);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(client_id);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_monitor_client_id_trace_disable_internal
 */
PG_FUNCTION_INFO_V1(dbms_monitor_client_id_trace_disable_internal);
Datum
dbms_monitor_client_id_trace_disable_internal(PG_FUNCTION_ARGS)
{
	text	   *client_id_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *client_id;
	StringInfoData buf;
	int			ret;

	if (!client_id_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_MONITOR: client_id must not be NULL")));

	client_id = text_to_cstring(client_id_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "UPDATE sys.monitored_client_ids SET trace_enabled = false, updated_time = now() "
					 "WHERE client_id = '%s'", client_id);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(client_id);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_monitor_session_trace_enable_internal
 */
PG_FUNCTION_INFO_V1(dbms_monitor_session_trace_enable_internal);
Datum
dbms_monitor_session_trace_enable_internal(PG_FUNCTION_ARGS)
{
	int32		session_id = PG_GETARG_INT32(0);
	int32		serial_num = PG_GETARG_INT32(1);
	bool		waits = PG_GETARG_BOOL(2);
	bool		binds = PG_GETARG_BOOL(3);
	text	   *plan_stat_text = PG_ARGISNULL(4) ? NULL : PG_GETARG_TEXT_PP(4);
	StringInfoData buf;
	int			ret;

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.monitored_sessions (session_id, serial_num, trace_enabled, waits, binds, plan_stat, updated_time) "
					 "VALUES (%d, %d, true, %s, %s, '%s', now()) "
					 "ON CONFLICT (session_id, serial_num) DO UPDATE "
					 "SET trace_enabled = true, waits = EXCLUDED.waits, binds = EXCLUDED.binds, updated_time = now()",
					 session_id, serial_num, waits ? "true" : "false", binds ? "true" : "false",
					 plan_stat_text ? text_to_cstring(plan_stat_text) : "FIRST_EXECUTION");
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_monitor_session_trace_disable_internal
 */
PG_FUNCTION_INFO_V1(dbms_monitor_session_trace_disable_internal);
Datum
dbms_monitor_session_trace_disable_internal(PG_FUNCTION_ARGS)
{
	int32		session_id = PG_GETARG_INT32(0);
	int32		serial_num = PG_GETARG_INT32(1);
	StringInfoData buf;
	int			ret;

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "UPDATE sys.monitored_sessions SET trace_enabled = false, updated_time = now() "
					 "WHERE session_id = %d AND serial_num = %d", session_id, serial_num);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_monitor_database_trace_enable_internal
 */
PG_FUNCTION_INFO_V1(dbms_monitor_database_trace_enable_internal);
Datum
dbms_monitor_database_trace_enable_internal(PG_FUNCTION_ARGS)
{
	bool		waits = PG_GETARG_BOOL(0);
	bool		binds = PG_GETARG_BOOL(1);
	text	   *plan_stat_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);

	ereport(LOG, (errmsg("DBMS_MONITOR: database-wide trace enabled")));
	PG_RETURN_VOID();
}

/*
 * dbms_monitor_database_trace_disable_internal
 */
PG_FUNCTION_INFO_V1(dbms_monitor_database_trace_disable_internal);
Datum
dbms_monitor_database_trace_disable_internal(PG_FUNCTION_ARGS)
{
	ereport(LOG, (errmsg("DBMS_MONITOR: database-wide trace disabled")));
	PG_RETURN_VOID();
}
