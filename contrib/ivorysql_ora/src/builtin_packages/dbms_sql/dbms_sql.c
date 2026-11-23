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
 * dbms_sql.c
 *    Session-local dynamic SQL handles, scalar binds and streaming results.
 *
 * Statement/bind/define state belongs to a backend memory context. Result
 * portals belong to a transaction and notify their handle when destroyed.
 * No privileged execution, SQL string interpolation, or shared cursor state.
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/htup_details.h"
#include "catalog/pg_type.h"
#include "catalog/pg_proc.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "parser/parse_node.h"
#include "utils/builtins.h"
#include "utils/datum.h"
#include "utils/hsearch.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/portal.h"

#define DBMS_SQL_MAX_CURSORS 1024
#define DBMS_SQL_MAX_BINDS 1024

typedef struct SqlBind
{
	char	   *name;
	int			id;
	Oid			type;
	Datum		value;
	bool		isnull;
	bool		bound;
	MemoryContext context;
} SqlBind;

typedef struct SqlDefine
{
	int			position;
	Oid			type;
	int			size;
} SqlDefine;

typedef struct SqlCursor
{
	int			id;				/* dynahash key */
	Oid			owner;
	Oid			session_user;
	MemoryContext context;
	MemoryContext statement_context;
	MemoryContext row_context;
	char	   *query;
	List	   *binds;
	List	   *defines;
	bool		is_select;
	Portal		portal;
	TupleDesc	descriptor;
	HeapTuple	row;
	uint64		fetched;
} SqlCursor;

static HTAB *sql_cursors;
static int	next_cursor_id = 1;
static uint64 last_row_count;

PG_FUNCTION_INFO_V1(ora_dbms_sql_open_cursor);
PG_FUNCTION_INFO_V1(ora_dbms_sql_is_open);
PG_FUNCTION_INFO_V1(ora_dbms_sql_close_cursor);
PG_FUNCTION_INFO_V1(ora_dbms_sql_parse);
PG_FUNCTION_INFO_V1(ora_dbms_sql_bind_variable);
PG_FUNCTION_INFO_V1(ora_dbms_sql_define_column);
PG_FUNCTION_INFO_V1(ora_dbms_sql_execute);
PG_FUNCTION_INFO_V1(ora_dbms_sql_fetch_rows);
PG_FUNCTION_INFO_V1(ora_dbms_sql_column_value);
PG_FUNCTION_INFO_V1(ora_dbms_sql_last_row_count);

static void
sql_state_error(const char *message)
{
	ereport(ERROR, (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
					errmsg("DBMS_SQL: %s", message)));
}

static SqlCursor *
sql_cursor(int id)
{
	SqlCursor  *cursor = sql_cursors ? hash_search(sql_cursors, &id, HASH_FIND, NULL) : NULL;

	if (cursor == NULL)
		ereport(ERROR, (errcode(ERRCODE_INVALID_CURSOR_NAME),
						errmsg("DBMS_SQL: cursor %d is not open", id)));

	/*
	 * Apply ownership checks to every operation, including fetching and
	 * close.
	 */
	if (cursor->owner != GetUserId() || cursor->session_user != GetSessionUserId())
		ereport(ERROR, (errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
						errmsg("DBMS_SQL: cursor %d belongs to a different user", id)));
	return cursor;
}

static SqlCursor *
sql_cursor_argument(FunctionCallInfo fcinfo)
{
	if (PG_ARGISNULL(0))
		ereport(ERROR, (errcode(ERRCODE_INVALID_CURSOR_NAME),
						errmsg("DBMS_SQL: cursor must not be NULL")));
	return sql_cursor(PG_GETARG_INT32(0));
}

/* Called before the portal context disappears, including on abort/commit. */
static void
sql_portal_reset(void *arg)
{
	SqlCursor  *cursor = arg;

	cursor->portal = NULL;
	cursor->descriptor = NULL;
	cursor->row = NULL;
	MemoryContextReset(cursor->row_context);
}

static void
sql_clear_result(SqlCursor *cursor)
{
	if (cursor->portal != NULL)
		SPI_cursor_close(cursor->portal);
	cursor->row = NULL;
	cursor->descriptor = NULL;
	cursor->fetched = 0;
	MemoryContextReset(cursor->row_context);
}

static SqlBind *
sql_bind(SqlCursor *cursor, const char *name)
{
	ListCell   *lc;

	/* Oracle callers may include or omit the leading colon. */
	if (name[0] == ':')
		name++;
	foreach(lc, cursor->binds)
	{
		SqlBind    *bind = lfirst(lc);

		if (pg_strcasecmp(bind->name, name) == 0)
			return bind;
	}
	return NULL;
}

/* Walk actual parser nodes, so quoted text and comments are never binds. */
static bool
sql_collect_binds(Node *node, SqlCursor *cursor)
{
	if (node == NULL)
		return false;
	if ((IsA(node, SelectStmt) && ((SelectStmt *) node)->intoClause) ||
		(IsA(node, CommonTableExpr) && !IsA(((CommonTableExpr *) node)->ctequery, SelectStmt)))
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						errmsg("DBMS_SQL: SELECT INTO and data-modifying CTEs are not supported")));
	if ((IsA(node, InsertStmt) && ((InsertStmt *) node)->returningClause) ||
		(IsA(node, UpdateStmt) && ((UpdateStmt *) node)->returningClause) ||
		(IsA(node, DeleteStmt) && ((DeleteStmt *) node)->returningClause) ||
		(IsA(node, MergeStmt) && ((MergeStmt *) node)->returningClause))
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						errmsg("DBMS_SQL: DML RETURNING is not supported")));
	if (IsA(node, OraParamRef))
	{
		OraParamRef *ref = (OraParamRef *) node;

		if (sql_bind(cursor, ref->name) == NULL)
		{
			SqlBind    *bind;

			if (list_length(cursor->binds) >= DBMS_SQL_MAX_BINDS)
				ereport(ERROR, (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
								errmsg("DBMS_SQL: too many bind variables")));
			bind = palloc0(sizeof(SqlBind));
			bind->name = pstrdup(ref->name + (ref->name[0] == ':'));
			bind->id = list_length(cursor->binds) + 1;
			bind->context = AllocSetContextCreate(cursor->statement_context,
												  "DBMS_SQL bind", ALLOCSET_SMALL_SIZES);
			cursor->binds = lappend(cursor->binds, bind);
		}
		return false;
	}
	if (IsA(node, ParamRef))
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						errmsg("DBMS_SQL: use Oracle :name bind placeholders")));
	return raw_expression_tree_walker(node, sql_collect_binds, cursor);
}

static Node *
sql_param_ref(ParseState *pstate, ParamRef *ref)
{
	SqlCursor  *cursor = pstate->p_ref_hook_state;
	SqlBind    *bind;
	Param	   *param;

	if (!IsA(ref, OraParamRef))
		return NULL;
	bind = sql_bind(cursor, ((OraParamRef *) ref)->name);
	if (bind == NULL || !bind->bound)
		ereport(ERROR, (errcode(ERRCODE_UNDEFINED_PARAMETER),
						errmsg("DBMS_SQL: bind variable is not assigned")));
	param = makeNode(Param);
	param->paramkind = PARAM_EXTERN;
	param->paramid = bind->id;
	param->paramtype = bind->type;
	param->paramtypmod = -1;
	param->paramcollid = get_typcollation(bind->type);
	param->location = ref->location;
	return (Node *) param;
}

static void
sql_parser_setup(ParseState *pstate, void *arg)
{
	pstate->p_paramref_hook = sql_param_ref;
	pstate->p_ref_hook_state = arg;
}

Datum
ora_dbms_sql_open_cursor(PG_FUNCTION_ARGS)
{
	SqlCursor  *cursor;
	MemoryContext context;
	bool		found;
	int			id;
	int			level = PG_ARGISNULL(0) ? 1 : PG_GETARG_INT32(0);

	if (level != 1 && level != 2)
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
						errmsg("DBMS_SQL: security_level must be 1 or 2")));
	if (sql_cursors == NULL)
	{
		HASHCTL		ctl;

		MemSet(&ctl, 0, sizeof(ctl));
		ctl.keysize = sizeof(int);
		ctl.entrysize = sizeof(SqlCursor);
		ctl.hcxt = TopMemoryContext;
		sql_cursors = hash_create("DBMS_SQL handles", 16, &ctl,
								  HASH_ELEM | HASH_BLOBS | HASH_CONTEXT);
	}
	if (hash_get_num_entries(sql_cursors) >= DBMS_SQL_MAX_CURSORS ||
		next_cursor_id == PG_INT32_MAX)
		ereport(ERROR, (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
						errmsg("DBMS_SQL: cursor limit exceeded")));
	context = AllocSetContextCreate(TopMemoryContext, "DBMS_SQL cursor", ALLOCSET_SMALL_SIZES);
	id = next_cursor_id++;
	/* Do fallible allocation before publishing a handle in the session hash. */
	PG_TRY();
	{
		MemoryContext statement_context;
		MemoryContext row_context;

		statement_context = AllocSetContextCreate(context, "DBMS_SQL statement", ALLOCSET_DEFAULT_SIZES);
		row_context = AllocSetContextCreate(context, "DBMS_SQL row", ALLOCSET_SMALL_SIZES);
		cursor = hash_search(sql_cursors, &id, HASH_ENTER, &found);
		Assert(!found);
		MemSet(cursor, 0, sizeof(SqlCursor));
		cursor->id = id;
		cursor->owner = GetUserId();
		cursor->session_user = GetSessionUserId();
		cursor->context = context;
		cursor->statement_context = statement_context;
		cursor->row_context = row_context;
	}
	PG_CATCH();
	{
		MemoryContextDelete(context);
		PG_RE_THROW();
	}
	PG_END_TRY();
	PG_RETURN_INT32(id);
}

Datum
ora_dbms_sql_is_open(PG_FUNCTION_ARGS)
{
	int			id;
	SqlCursor  *cursor;

	if (PG_ARGISNULL(0))
		PG_RETURN_BOOL(false);
	id = PG_GETARG_INT32(0);
	cursor = sql_cursors ? hash_search(sql_cursors, &id, HASH_FIND, NULL) : NULL;
	if (cursor == NULL)
		PG_RETURN_BOOL(false);
	(void) sql_cursor(id);
	PG_RETURN_BOOL(true);
}

Datum
ora_dbms_sql_close_cursor(PG_FUNCTION_ARGS)
{
	SqlCursor  *cursor = sql_cursor_argument(fcinfo);
	int			id = cursor->id;

	sql_clear_result(cursor);
	MemoryContextDelete(cursor->context);
	hash_search(sql_cursors, &id, HASH_REMOVE, NULL);
	PG_RETURN_VOID();
}

Datum
ora_dbms_sql_parse(PG_FUNCTION_ARGS)
{
	SqlCursor  *cursor = sql_cursor_argument(fcinfo);
	char	   *query;
	List	   *statements;
	Node	   *statement;
	MemoryContext old;

	if (PG_ARGISNULL(1))
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
						errmsg("DBMS_SQL: statement must not be NULL")));
	query = text_to_cstring(PG_GETARG_TEXT_PP(1));
	if (PG_ARGISNULL(2) || PG_GETARG_INT32(2) != 1)
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						errmsg("DBMS_SQL: only the NATIVE language flag is supported")));
	sql_clear_result(cursor);
	MemoryContextReset(cursor->statement_context);
	cursor->query = NULL;
	cursor->binds = NIL;
	cursor->defines = NIL;
	/* Keep parser scratch in the call context; only validated state persists. */
	statements = raw_parser(query, RAW_PARSE_DEFAULT);
	if (list_length(statements) != 1)
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						errmsg("DBMS_SQL: PARSE requires exactly one SQL statement")));
	statement = ((RawStmt *) linitial(statements))->stmt;
	if (!(IsA(statement, SelectStmt) || IsA(statement, InsertStmt) ||
		  IsA(statement, UpdateStmt) || IsA(statement, DeleteStmt) || IsA(statement, MergeStmt)))
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						errmsg("DBMS_SQL: only SELECT and DML statements are supported"),
						errdetail("DDL, transaction control and anonymous blocks are not supported.")));
	if (IsA(statement, SelectStmt) && ((SelectStmt *) statement)->intoClause)
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						errmsg("DBMS_SQL: SELECT INTO is not supported")));
	old = MemoryContextSwitchTo(cursor->statement_context);
	sql_collect_binds(statement, cursor);
	cursor->query = pstrdup(query);
	cursor->is_select = IsA(statement, SelectStmt);
	MemoryContextSwitchTo(old);
	PG_RETURN_VOID();
}

Datum
ora_dbms_sql_bind_variable(PG_FUNCTION_ARGS)
{
	SqlCursor  *cursor = sql_cursor_argument(fcinfo);
	char	   *name;
	SqlBind    *bind;
	MemoryContext old;
	int16		length;
	bool		byval;
	Oid			type = get_fn_expr_argtype(fcinfo->flinfo, 2);

	if (PG_ARGISNULL(1))
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
						errmsg("DBMS_SQL: bind name must not be NULL")));
	name = text_to_cstring(PG_GETARG_TEXT_PP(1));
	bind = sql_bind(cursor, name);
	if (cursor->query == NULL)
		sql_state_error("PARSE must precede BIND_VARIABLE");
	if (bind == NULL)
		ereport(ERROR, (errcode(ERRCODE_UNDEFINED_PARAMETER),
						errmsg("DBMS_SQL: bind variable \"%s\" does not occur in the statement", name)));
	get_typlenbyval(type, &length, &byval);
	MemoryContextReset(bind->context);
	bind->bound = false;
	bind->type = type;
	bind->isnull = PG_ARGISNULL(2);
	old = MemoryContextSwitchTo(bind->context);
	bind->value = bind->isnull ? (Datum) 0 : datumCopy(PG_GETARG_DATUM(2), byval, length);
	MemoryContextSwitchTo(old);
	bind->bound = true;
	PG_RETURN_VOID();
}

Datum
ora_dbms_sql_define_column(PG_FUNCTION_ARGS)
{
	SqlCursor  *cursor = sql_cursor_argument(fcinfo);
	int			position = PG_GETARG_INT32(1);
	int			size = PG_ARGISNULL(3) ? -1 : PG_GETARG_INT32(3);
	SqlDefine  *define = NULL;
	ListCell   *lc;
	MemoryContext old;

	if (cursor->query == NULL)
		sql_state_error("PARSE must precede DEFINE_COLUMN");
	if (PG_ARGISNULL(1) || position < 1 || position > MaxTupleAttributeNumber ||
		(!PG_ARGISNULL(3) && size <= 0))
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
						errmsg("DBMS_SQL: invalid column position or size")));
	foreach(lc, cursor->defines)
	{
		SqlDefine  *item = lfirst(lc);

		if (item->position == position)
			define = item;
	}
	old = MemoryContextSwitchTo(cursor->statement_context);
	if (define == NULL)
	{
		define = palloc(sizeof(SqlDefine));
		cursor->defines = lappend(cursor->defines, define);
	}
	define->position = position;
	define->type = get_fn_expr_argtype(fcinfo->flinfo, 2);
	define->size = size;
	MemoryContextSwitchTo(old);
	PG_RETURN_VOID();
}

Datum
ora_dbms_sql_execute(PG_FUNCTION_ARGS)
{
	SqlCursor  *cursor = sql_cursor_argument(fcinfo);
	ParamListInfo params;
	SPIPrepareOptions options;
	SPIPlanPtr	plan;
	ListCell   *lc;
	uint64		affected = 0;

	if (cursor->query == NULL)
		sql_state_error("PARSE must precede EXECUTE");
	sql_clear_result(cursor);
	last_row_count = 0;
	params = makeParamList(list_length(cursor->binds));
	foreach(lc, cursor->binds)
	{
		SqlBind    *bind = lfirst(lc);
		ParamExternData *param = &params->params[bind->id - 1];

		if (!bind->bound)
			ereport(ERROR, (errcode(ERRCODE_UNDEFINED_PARAMETER),
							errmsg("DBMS_SQL: bind variable \"%s\" is not assigned", bind->name)));
		param->value = bind->value;
		param->isnull = bind->isnull;
		param->pflags = PARAM_FLAG_CONST;
		param->ptype = bind->type;
		param->ptypmod = -1;
		param->pmode = PROARGMODE_IN;
	}
	SPI_connect();
	MemSet(&options, 0, sizeof(options));
	options.parserSetup = sql_parser_setup;
	options.parserSetupArg = cursor;
	plan = SPI_prepare_extended(cursor->query, &options);
	if (plan == NULL)
		elog(ERROR, "DBMS_SQL: SPI_prepare_extended failed: %s", SPI_result_code_string(SPI_result));
	if (cursor->is_select)
	{
		Portal		portal;
		MemoryContextCallback *callback;
		MemoryContext old;

		portal = SPI_cursor_open_with_paramlist(NULL, plan, params, false);
		if (portal == NULL)
			elog(ERROR, "DBMS_SQL: could not open result portal");
		old = MemoryContextSwitchTo(portal->portalContext);
		callback = palloc(sizeof(MemoryContextCallback));
		callback->func = sql_portal_reset;
		callback->arg = cursor;
		MemoryContextRegisterResetCallback(portal->portalContext, callback);
		MemoryContextSwitchTo(old);
		cursor->portal = portal;
		cursor->descriptor = portal->tupDesc;
	}
	else
	{
		int			rc = SPI_execute_plan_with_paramlist(plan, params, false, 0);

		if (rc < 0)
			elog(ERROR, "DBMS_SQL: execution failed: %s", SPI_result_code_string(rc));
		affected = SPI_processed;
	}
	SPI_freeplan(plan);
	SPI_finish();
	last_row_count = affected;
	if (affected > PG_INT32_MAX)
		ereport(ERROR, (errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
						errmsg("DBMS_SQL: affected row count exceeds INTEGER range")));
	PG_RETURN_INT32((int32) affected);
}

Datum
ora_dbms_sql_fetch_rows(PG_FUNCTION_ARGS)
{
	SqlCursor  *cursor = sql_cursor_argument(fcinfo);
	bool		found;
	MemoryContext old;

	if (cursor->portal == NULL)
		sql_state_error("no active query; EXECUTE a SELECT in the current transaction");
	if (cursor->portal->status == PORTAL_FAILED)
		sql_state_error("query failed; EXECUTE it again before fetching");
	cursor->row = NULL;
	MemoryContextReset(cursor->row_context);
	SPI_connect();
	SPI_cursor_fetch(cursor->portal, true, 1);
	found = SPI_processed != 0;
	if (found)
	{
		old = MemoryContextSwitchTo(cursor->row_context);
		cursor->row = heap_copytuple(SPI_tuptable->vals[0]);
		MemoryContextSwitchTo(old);
		cursor->fetched++;
	}
	SPI_finish();
	last_row_count = cursor->fetched;
	PG_RETURN_INT32(found ? 1 : 0);
}

Datum
ora_dbms_sql_column_value(PG_FUNCTION_ARGS)
{
	SqlCursor  *cursor = sql_cursor_argument(fcinfo);
	int			position = PG_GETARG_INT32(1);
	Oid			target = get_fn_expr_argtype(fcinfo->flinfo, 2);
	SqlDefine  *define = NULL;
	ListCell   *lc;
	Datum		value;
	bool		isnull;
	Oid			source;
	Oid			output,
				input,
				ioparam;
	bool varlena;
	char	   *string;

	if (cursor->row == NULL || cursor->descriptor == NULL)
		sql_state_error("FETCH_ROWS must return a row before COLUMN_VALUE");
	if (PG_ARGISNULL(1) || position < 1 || position > cursor->descriptor->natts)
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
						errmsg("DBMS_SQL: column position %d is out of range", position)));
	foreach(lc, cursor->defines)
	{
		SqlDefine  *item = lfirst(lc);

		if (item->position == position)
			define = item;
	}
	if (define == NULL)
		sql_state_error("DEFINE_COLUMN must precede COLUMN_VALUE");
	if (define->type != target)
		ereport(ERROR, (errcode(ERRCODE_DATATYPE_MISMATCH),
						errmsg("DBMS_SQL: COLUMN_VALUE type differs from DEFINE_COLUMN type")));
	value = heap_getattr(cursor->row, position, cursor->descriptor, &isnull);
	if (isnull)
		PG_RETURN_NULL();
	source = TupleDescAttr(cursor->descriptor, position - 1)->atttypid;
	getTypeOutputInfo(source, &output, &varlena);
	string = OidOutputFunctionCall(output, value);
	if (define->size >= 0 && strlen(string) > define->size)
		ereport(ERROR, (errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
						errmsg("DBMS_SQL: column value exceeds its defined byte size")));
	getTypeInputInfo(target, &input, &ioparam);
	PG_RETURN_DATUM(OidInputFunctionCall(input, string, ioparam, -1));
}

Datum
ora_dbms_sql_last_row_count(PG_FUNCTION_ARGS)
{
	char		buffer[32];

	snprintf(buffer, sizeof(buffer), UINT64_FORMAT, last_row_count);
	PG_RETURN_DATUM(DirectFunctionCall3(numeric_in, CStringGetDatum(buffer),
										ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1)));
}
