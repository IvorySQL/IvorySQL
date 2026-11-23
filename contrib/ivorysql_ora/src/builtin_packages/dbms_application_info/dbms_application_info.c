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
#include "miscadmin.h"
#include "funcapi.h"
#include "mb/pg_wchar.h"
#include "utils/timestamp.h"
#include "utils/builtins.h"

#include "../../include/ivorysql_ora.h"

/*
 * Oracle documented limits (VARCHAR2 BYTE semantics). READ_* returns the
 * stored values; unset values read back as NULL.
 */
#define DAI_MAX_MODULE_LEN		48
#define DAI_MAX_ACTION_LEN		32
#define DAI_MAX_CLIENT_INFO_LEN 64
#define DAI_MAX_OPNAME_LEN		64
#define DAI_MAX_UNITS_LEN		32

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
 * dai_free_stored
 *
 * Free a string previously stored in the session memory context by
 * dai_set_field/dai_lstr. Callers must allocate the replacement first;
 * dai_set_field/dai_lstr can raise out-of-memory, and the stored pointer
 * would then point to freed memory if released before the replacement
 * exists.
 */
static void
dai_free_stored(char *old)
{
	MemoryContext oldcontext;

	if (old == NULL)
		return;

	if (app_info->mcxt)
		oldcontext = MemoryContextSwitchTo(app_info->mcxt);
	else
		oldcontext = MemoryContextSwitchTo(TopMemoryContext);

	pfree(old);
	MemoryContextSwitchTo(oldcontext);
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

	dai_free_stored(app_info->module);
	dai_free_stored(app_info->action);
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

	dai_free_stored(app_info->action);
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

	dai_free_stored(app_info->client_info);
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
 * SET_SESSION_LONGOPS support: per-backend progress rows. Rows live in
 * the dedicated memory context (session lifetime); rindex 0 allocates a
 * new row, an existing rindex updates it and bumps slno.
 */
typedef struct DaiLongopsRow
{
	int			rindex;
	int			slno;
	char	   *op_name;
	int			target;
	int			context;
	double		sofar;
	double		totalwork;
	char	   *target_desc;
	char	   *units;
	TimestampTz start_time;
} DaiLongopsRow;

static DaiLongopsRow *dai_lrows = NULL;
static int	dai_lrows_n = 0;
static int	dai_lrows_cap = 0;
static int	dai_lrows_next_rindex = 0;

PG_FUNCTION_INFO_V1(ora_set_session_longops);
PG_FUNCTION_INFO_V1(ora_session_longops);

static char *
dai_lstr(const char *src, int max_len)
{
	char	   *clipped = dai_clip(src, max_len);
	int			len = (int) strlen(clipped);
	char	   *dst = (char *) palloc(len + 1);

	memcpy(dst, clipped, len + 1);
	pfree(clipped);
	return dst;
}

/*
 * ora_set_session_longops
 *
 * Oracle SET_SESSION_LONGOPS(rindex IN OUT, slno IN OUT, ...): rindex = 0
 * allocates a row; an existing rindex updates it and bumps slno. Returns
 * the composite (rindex, slno) so the PL/iSQL wrapper can write the OUT
 * parameters back.
 */
Datum
ora_set_session_longops(PG_FUNCTION_ARGS)
{
	int			rindex = PG_GETARG_INT32(0);
	int			slno;
	char	   *op_name = PG_ARGISNULL(2) ? NULL : text_to_cstring(PG_GETARG_TEXT_PP(2));
	int			target = PG_ARGISNULL(3) ? 0 : PG_GETARG_INT32(3);
	int			context = PG_ARGISNULL(4) ? 0 : PG_GETARG_INT32(4);
	double		sofar = PG_ARGISNULL(5) ? 0 : PG_GETARG_FLOAT8(5);
	double		totalwork = PG_ARGISNULL(6) ? 0 : PG_GETARG_FLOAT8(6);
	char	   *target_desc = PG_ARGISNULL(7) ? NULL : text_to_cstring(PG_GETARG_TEXT_PP(7));
	char	   *units = PG_ARGISNULL(8) ? NULL : text_to_cstring(PG_GETARG_TEXT_PP(8));
	DaiLongopsRow *row = NULL;
	int			i;
	MemoryContext oldcontext;
	TupleDesc	tupdesc;
	HeapTuple	tuple;
	Datum		values[2];
	bool		nulls[2] = {false, false};
	char	   *new_op;
	char	   *new_units;
	char	   *new_target_desc;

	dai_ensure_context();

	/* Find or allocate the row */
	if (rindex > 0)
	{
		for (i = 0; i < dai_lrows_n; i++)
		{
			if (dai_lrows[i].rindex == rindex)
			{
				row = &dai_lrows[i];
				break;
			}
		}
	}

	oldcontext = MemoryContextSwitchTo(app_info->mcxt);

	if (row == NULL)
	{
		/* Allocate a new row */
		if (dai_lrows_n >= dai_lrows_cap)
		{
			int			newcap = dai_lrows_cap ? dai_lrows_cap * 2 : 8;
			DaiLongopsRow *newrows;

			if (dai_lrows == NULL)
				newrows = (DaiLongopsRow *) palloc(newcap * sizeof(DaiLongopsRow));
			else
				newrows = (DaiLongopsRow *) repalloc(dai_lrows,
													 newcap * sizeof(DaiLongopsRow));
			dai_lrows = newrows;
			dai_lrows_cap = newcap;
		}
		row = &dai_lrows[dai_lrows_n++];
		row->rindex = ++dai_lrows_next_rindex;
		row->slno = 0;
		row->op_name = NULL;
		row->target_desc = NULL;
		row->units = NULL;
		row->start_time = GetCurrentTimestamp();
	}

	if (row->slno < INT_MAX)
		row->slno++;

	new_op = op_name ? dai_lstr(op_name, DAI_MAX_OPNAME_LEN) : NULL;
	new_target_desc = target_desc ? dai_lstr(target_desc, DAI_MAX_OPNAME_LEN) : NULL;
	new_units = units ? dai_lstr(units, DAI_MAX_UNITS_LEN) : NULL;

	if (row->op_name)
		pfree(row->op_name);
	row->op_name = new_op;
	row->target = target;
	row->context = context;
	row->sofar = sofar;
	row->totalwork = totalwork;
	if (row->target_desc)
		pfree(row->target_desc);
	row->target_desc = new_target_desc;
	if (row->units)
		pfree(row->units);
	row->units = new_units;

	MemoryContextSwitchTo(oldcontext);

	slno = row->slno;

	/* Return the composite (rindex, slno) */
	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function returning record called in context that cannot accept type record")));
	tupdesc = BlessTupleDesc(tupdesc);
	values[0] = Int32GetDatum(row->rindex);
	values[1] = Int32GetDatum(row->slno);
	tuple = heap_form_tuple(tupdesc, values, nulls);
	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}

/*
 * ora_session_longops
 *
 * Set-returning function listing all progress rows of the current
 * session; backs the compatibility view sys.v$session_longops.
 */
Datum
ora_session_longops(PG_FUNCTION_ARGS)
{
	FuncCallContext *funcctx;
	int			i;

	if (SRF_IS_FIRSTCALL())
	{
		MemoryContext oldcontext;
		TupleDesc	tupdesc;

		funcctx = SRF_FIRSTCALL_INIT();
		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
		tupdesc = CreateTemplateTupleDesc(13);
		TupleDescInitEntry(tupdesc, (AttrNumber) 1, "sid", INT8OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 2, "rindex", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 3, "slno", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 4, "opname", TEXTOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 5, "target", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 6, "context", INT4OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 7, "sofar", FLOAT8OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 8, "totalwork", FLOAT8OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 9, "target_desc", TEXTOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 10, "units", TEXTOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 11, "start_time", TIMESTAMPTZOID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 12, "time_remaining", FLOAT8OID, -1, 0);
		TupleDescInitEntry(tupdesc, (AttrNumber) 13, "message", TEXTOID, -1, 0);
		funcctx->tuple_desc = BlessTupleDesc(tupdesc);
		MemoryContextSwitchTo(oldcontext);
	}

	funcctx = SRF_PERCALL_SETUP();

	if (app_info == NULL || funcctx->call_cntr >= dai_lrows_n)
		SRF_RETURN_DONE(funcctx);

	i = funcctx->call_cntr;
	{
		Datum		values[13];
		bool		nulls[13] = {false};
		HeapTuple	tuple;
		DaiLongopsRow *row = &dai_lrows[i];
		double		elapsed_sec;
		char		msg[1024];

		values[0] = Int64GetDatum(MyProcPid);
		values[1] = Int32GetDatum(row->rindex);
		values[2] = Int32GetDatum(row->slno);
		if (row->op_name)
			values[3] = PointerGetDatum(cstring_to_text(row->op_name));
		else
			nulls[3] = true;
		values[4] = Int32GetDatum(row->target);
		values[5] = Int32GetDatum(row->context);
		values[6] = Float8GetDatum(row->sofar);
		values[7] = Float8GetDatum(row->totalwork);
		if (row->target_desc)
			values[8] = PointerGetDatum(cstring_to_text(row->target_desc));
		else
			nulls[8] = true;
		if (row->units)
			values[9] = PointerGetDatum(cstring_to_text(row->units));
		else
			nulls[9] = true;
		values[10] = TimestampTzGetDatum(row->start_time);

		/* time_remaining: extrapolate from progress so far (Oracle semantics) */
		if (row->totalwork > 0 && row->sofar > 0 && row->sofar < row->totalwork)
		{
			elapsed_sec =
				(double) (GetCurrentTimestamp() - row->start_time) / 1000000.0;
			values[11] = Float8GetDatum(elapsed_sec * (row->totalwork - row->sofar) / row->sofar);
		}
		else
			nulls[11] = true;

		/* message: "op_name: sofar/totalwork units" (Oracle format) */
		snprintf(msg, sizeof(msg), "%s: %g/%g %s",
				 row->op_name ? row->op_name : "",
				 row->sofar, row->totalwork,
				 row->units ? row->units : "");
		values[12] = PointerGetDatum(cstring_to_text(msg));

		tuple = heap_form_tuple(funcctx->tuple_desc, values, nulls);
		SRF_RETURN_NEXT(funcctx, HeapTupleGetDatum(tuple));
	}
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
