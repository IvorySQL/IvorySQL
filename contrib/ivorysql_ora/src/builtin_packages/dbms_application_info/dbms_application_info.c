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
 * dbms_application_info.c
 *
 * Oracle-compatible DBMS_APPLICATION_INFO package.
 *
 * Registers module/action/client_info strings for the current session.
 * State is per-backend and persists for the session lifetime. Values are
 * truncated to Oracle's documented byte limits: module 48, action 32,
 * client_info 64 (clipped on multibyte boundaries via pg_mbcliplen).
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_application_info/dbms_application_info.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "funcapi.h"
#include "mb/pg_wchar.h"
#include "utils/builtins.h"

#include "../../include/ivorysql_ora.h"

/*
 * Oracle documented limits (VARCHAR2 BYTE semantics). READ_* returns the
 * stored values; unset values read back as NULL.
 */
#define DAI_MAX_MODULE_LEN		48
#define DAI_MAX_ACTION_LEN		32
#define DAI_MAX_CLIENT_INFO_LEN 64

typedef struct DbmsAppInfo
{
	char	   *module;
	char	   *action;
	char	   *client_info;
	MemoryContext mcxt;
} DbmsAppInfo;

static DbmsAppInfo *app_info = NULL;

PG_FUNCTION_INFO_V1(ora_dbms_application_info_set_module);
PG_FUNCTION_INFO_V1(ora_dbms_application_info_set_action);
PG_FUNCTION_INFO_V1(ora_dbms_application_info_set_client_info);
PG_FUNCTION_INFO_V1(ora_dbms_application_info_read_module);
PG_FUNCTION_INFO_V1(ora_dbms_application_info_read_client_info);

/*
 * dai_ensure_context
 *
 * Make sure the per-session storage exists and that allocations for it
 * happen in its dedicated memory context.
 */
static void
dai_ensure_context(void)
{
	MemoryContext oldcontext;

	/* Already initialized */
	if (app_info != NULL)
		return;

	/*
	 * The state struct must live in TopMemoryContext: allocating it in the
	 * caller's (possibly short-lived) context leaves a dangling pointer and
	 * crashes the backend on the next SET/READ call.
	 */
	oldcontext = MemoryContextSwitchTo(TopMemoryContext);
	app_info = (DbmsAppInfo *) palloc0(sizeof(DbmsAppInfo));
	app_info->mcxt = AllocSetContextCreate(TopMemoryContext,
										   "DBMS_APPLICATION_INFO",
										   ALLOCSET_DEFAULT_SIZES);
	MemoryContextSwitchTo(oldcontext);
}

/*
 * dai_set_field
 *
 * Store a session field, truncating to the Oracle byte limit. NULL input
 * stores NULL (read back as NULL, matching READ_* on an unset session).
 */
static char *
dai_set_field(const char *value)
{
	MemoryContext oldcontext;
	char	   *stored;
	int			len;

	if (app_info->mcxt)
		oldcontext = MemoryContextSwitchTo(app_info->mcxt);
	else
		oldcontext = MemoryContextSwitchTo(TopMemoryContext);

	if (value == NULL)
		stored = NULL;
	else
	{
		len = (int) strlen(value);
		stored = (char *) palloc(len + 1);
		memcpy(stored, value, len + 1);
	}

	MemoryContextSwitchTo(oldcontext);
	return stored;
}

/*
 * dai_clip
 *
 * Copy src into a palloc'd string clipped to max_len bytes without
 * splitting a multibyte character.
 */
static char *
dai_clip(const char *src, int max_len)
{
	int			clip_len;

	clip_len = pg_mbcliplen(src, (int) strlen(src), max_len);
	return pnstrdup(src, clip_len);
}

/*
 * ora_dbms_application_info_set_module
 *
 * SET_MODULE(module_name, action_name): sets both fields at once; a NULL
 * argument clears the corresponding field.
 */
Datum
ora_dbms_application_info_set_module(PG_FUNCTION_ARGS)
{
	char	   *module = NULL;
	char	   *action = NULL;

	dai_ensure_context();

	if (!PG_ARGISNULL(0))
	{
		char	   *src = text_to_cstring(PG_GETARG_TEXT_PP(0));
		char	   *clipped = dai_clip(src, DAI_MAX_MODULE_LEN);

		module = dai_set_field(clipped);
		pfree(clipped);
	}
	else
		module = dai_set_field(NULL);

	if (!PG_ARGISNULL(1))
	{
		char	   *src = text_to_cstring(PG_GETARG_TEXT_PP(1));
		char	   *clipped = dai_clip(src, DAI_MAX_ACTION_LEN);

		action = dai_set_field(clipped);
		pfree(clipped);
	}
	else
		action = dai_set_field(NULL);

	app_info->module = module;
	app_info->action = action;

	PG_RETURN_VOID();
}

/*
 * ora_dbms_application_info_set_action
 *
 * SET_ACTION(action_name): sets only the action field.
 */
Datum
ora_dbms_application_info_set_action(PG_FUNCTION_ARGS)
{
	char	   *action = NULL;

	dai_ensure_context();

	if (!PG_ARGISNULL(0))
	{
		char	   *src = text_to_cstring(PG_GETARG_TEXT_PP(0));
		char	   *clipped = dai_clip(src, DAI_MAX_ACTION_LEN);

		action = dai_set_field(clipped);
		pfree(clipped);
	}
	else
		action = dai_set_field(NULL);

	app_info->action = action;

	PG_RETURN_VOID();
}

/*
 * ora_dbms_application_info_set_client_info
 *
 * SET_CLIENT_INFO(client_info): sets only the client_info field.
 */
Datum
ora_dbms_application_info_set_client_info(PG_FUNCTION_ARGS)
{
	char	   *client_info = NULL;

	dai_ensure_context();

	if (!PG_ARGISNULL(0))
	{
		char	   *src = text_to_cstring(PG_GETARG_TEXT_PP(0));
		char	   *clipped = dai_clip(src, DAI_MAX_CLIENT_INFO_LEN);

		client_info = dai_set_field(clipped);
		pfree(clipped);
	}
	else
		client_info = dai_set_field(NULL);

	app_info->client_info = client_info;

	PG_RETURN_VOID();
}

/*
 * ora_dbms_application_info_read_module
 *
 * READ_MODULE(module_name OUT, action_name OUT): returns the composite
 * (module_name, action_name) as registered by SET_MODULE/SET_ACTION.
 */
Datum
ora_dbms_application_info_read_module(PG_FUNCTION_ARGS)
{
	TupleDesc	tupdesc;
	HeapTuple	tuple;
	Datum		values[2];
	bool		nulls[2] = {false, false};

	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function returning record called in context that cannot accept type record")));

	tupdesc = BlessTupleDesc(tupdesc);

	if (app_info != NULL && app_info->module != NULL)
		values[0] = PointerGetDatum(cstring_to_text(app_info->module));
	else
		nulls[0] = true;

	if (app_info != NULL && app_info->action != NULL)
		values[1] = PointerGetDatum(cstring_to_text(app_info->action));
	else
		nulls[1] = true;

	tuple = heap_form_tuple(tupdesc, values, nulls);
	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}

/*
 * ora_dbms_application_info_read_client_info
 *
 * READ_CLIENT_INFO(client_info OUT): returns the composite
 * (client_info) as registered by SET_CLIENT_INFO.
 */
Datum
ora_dbms_application_info_read_client_info(PG_FUNCTION_ARGS)
{
	TupleDesc	tupdesc;
	HeapTuple	tuple;
	Datum		values[1];
	bool		nulls[1] = {false};

	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function returning record called in context that cannot accept type record")));

	tupdesc = BlessTupleDesc(tupdesc);

	if (app_info != NULL && app_info->client_info != NULL)
		values[0] = PointerGetDatum(cstring_to_text(app_info->client_info));
	else
		nulls[0] = true;

	tuple = heap_form_tuple(tupdesc, values, nulls);
	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}
