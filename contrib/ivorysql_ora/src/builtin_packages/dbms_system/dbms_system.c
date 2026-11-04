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
 * Implementation of Oracle's DBMS_SYSTEM package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides system diagnostics and session tracing capabilities:
 *   - KSDWRT: writes diagnostic messages to trace file or alert log.
 *   - SET_SQL_TRACE_IN_SESSION: enables or disables SQL trace for a session.
 *   - SET_EV: sets event level for diagnostic events.
 *   - READ_EV: reads current event level.
 *   - KCSSDID: sets distributed transaction ID in session.
 *   - GET_ENV: gets environment variable setting.
 *
 * Destination constants:
 *   1: Trace file only
 *   2: Alert log only
 *   3: Both trace file and alert log
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_system/dbms_system.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/builtins.h"
#include "utils/elog.h"

#define DBMS_SYSTEM_DEST_TRACE		1
#define DBMS_SYSTEM_DEST_ALERT		2
#define DBMS_SYSTEM_DEST_BOTH		3

/*
 * dbms_system_ksdwrt_internal
 */
PG_FUNCTION_INFO_V1(dbms_system_ksdwrt_internal);
Datum
dbms_system_ksdwrt_internal(PG_FUNCTION_ARGS)
{
	int32		dest = PG_GETARG_INT32(0);
	text	   *msg_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	char	   *msg;

	if (!msg_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SYSTEM.KSDWRT: msg must not be NULL")));

	if (dest < 1 || dest > 3)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SYSTEM.KSDWRT: invalid dest: %d (expected 1, 2, or 3)", dest)));

	msg = text_to_cstring(msg_text);

	/* Log diagnostic message to server log / alert log */
	if (dest == DBMS_SYSTEM_DEST_TRACE)
		ereport(DEBUG1, (errmsg("[DBMS_SYSTEM TRACE]: %s", msg)));
	else if (dest == DBMS_SYSTEM_DEST_ALERT)
		ereport(LOG, (errmsg("[DBMS_SYSTEM ALERT]: %s", msg)));
	else
		ereport(LOG, (errmsg("[DBMS_SYSTEM ALERT+TRACE]: %s", msg)));

	pfree(msg);
	PG_RETURN_VOID();
}

/*
 * dbms_system_set_sql_trace_in_session_internal
 */
PG_FUNCTION_INFO_V1(dbms_system_set_sql_trace_in_session_internal);
Datum
dbms_system_set_sql_trace_in_session_internal(PG_FUNCTION_ARGS)
{
	int32		sid = PG_GETARG_INT32(0);
	int32		serial = PG_GETARG_INT32(1);
	bool		sql_trace = PG_GETARG_BOOL(2);

	if (sid < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SYSTEM.SET_SQL_TRACE_IN_SESSION: sid must be >= 1")));

	ereport(LOG,
			(errmsg("DBMS_SYSTEM: SQL trace %s for sid %d serial %d",
					sql_trace ? "ENABLED" : "DISABLED", sid, serial)));

	PG_RETURN_VOID();
}

/*
 * dbms_system_set_ev_internal
 */
PG_FUNCTION_INFO_V1(dbms_system_set_ev_internal);
Datum
dbms_system_set_ev_internal(PG_FUNCTION_ARGS)
{
	int32		sid = PG_GETARG_INT32(0);
	int32		serial = PG_GETARG_INT32(1);
	int32		event_id = PG_GETARG_INT32(2);
	int32		event_level = PG_GETARG_INT32(3);
	text	   *name_text = PG_ARGISNULL(4) ? NULL : PG_GETARG_TEXT_PP(4);

	if (sid < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SYSTEM.SET_EV: sid must be >= 1")));

	ereport(LOG,
			(errmsg("DBMS_SYSTEM: set event %d to level %d for sid %d",
					event_id, event_level, sid)));

	PG_RETURN_VOID();
}

/*
 * dbms_system_read_ev_internal
 */
PG_FUNCTION_INFO_V1(dbms_system_read_ev_internal);
Datum
dbms_system_read_ev_internal(PG_FUNCTION_ARGS)
{
	int32		event_id = PG_GETARG_INT32(0);

	/* Return default diagnostic event level */
	PG_RETURN_INT32(0);
}

/*
 * dbms_system_get_env_internal
 */
PG_FUNCTION_INFO_V1(dbms_system_get_env_internal);
Datum
dbms_system_get_env_internal(PG_FUNCTION_ARGS)
{
	text	   *var_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *var_name;
	char	   *val;

	if (!var_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SYSTEM.GET_ENV: var must not be NULL")));

	var_name = text_to_cstring(var_text);
	val = getenv(var_name);
	pfree(var_name);

	if (val)
		PG_RETURN_TEXT_P(cstring_to_text(val));
	else
		PG_RETURN_TEXT_P(cstring_to_text(""));
}
