/*
    pg_get_functiondef_extend.c
        The implementation of pg_get_functiondef('function_name', 'function_name', ...)
*/
#include "postgres.h"
#include "fmgr.h"
#include "utils/elog.h"
#include "lib/stringinfo.h"
#include "executor/spi.h"
#include "utils/array.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type_d.h"
#include "funcapi.h"
#include "utils/builtins.h"
#include "utils/catcache.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"
#include "access/htup_details.h"

typedef struct FunctionInfoData *FunctionInfo;
struct FunctionInfoData
{
	char **function_name; /* The user's input */
	int cursor; /* The cursor of the function_name[] */
	int count_of_tuples; /* How many tuples will return? */
	TupleDesc result_desc; /* Describe the tuple */
	AttInMetadata *result_tuple_meta; /* Describe the tuple's attribute */
};

/*
	GetFuncDefByName
		Export the oid based on the function name, the use the oid get the definition
 */
char *GetFuncDefByName(char *function_name);
char *GetFuncDefByName(char *function_name)
{
	CatCList *catlist = NULL;
	StringInfoData result = {};
	initStringInfo(&result);
	catlist = SearchSysCacheList1(PROCNAMEARGSNSP, CStringGetDatum(function_name));
	
	if (catlist->n_members == 0)
	{
		appendStringInfo(&result, "/* Not Found */");
	}
	else
	{
		/* A function name may correspond to multiple different results */
		for (int i = 0; i < catlist->n_members; i++)
		{
			HeapTuple proctup = &catlist->members[i]->tuple;
			Form_pg_proc proc = (Form_pg_proc)GETSTRUCT(proctup);
			if (proc->prokind == PROKIND_AGGREGATE)
			{
				appendStringInfo(&result, "/* Not support aggregate function, oid: %d */\n", proc->oid);
				continue;
			}
			appendStringInfo(&result, "/* oid: %d */\n", proc->oid);
			appendStringInfo(&result, "%s", text_to_cstring(DatumGetTextP(DirectFunctionCall1(pg_get_functiondef, proc->oid))));
		}
	}
	ReleaseCatCacheList(catlist);
	return result.data;
}

PG_FUNCTION_INFO_V1(pg_get_functiondef_extend);

Datum pg_get_functiondef_extend(PG_FUNCTION_ARGS)
{
	FuncCallContext *funcctx = NULL;
	FunctionInfo info = NULL;

	if (SRF_IS_FIRSTCALL())
	{
		ArrayType *arguments_raw;
		int count_of_arguments;
		Datum *arguments;
		MemoryContext old_context;

		funcctx = SRF_FIRSTCALL_INIT();
		old_context = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

		arguments_raw = PG_GETARG_ARRAYTYPE_P(0);
		deconstruct_array_builtin((ArrayType *)arguments_raw, TEXTOID, &arguments, NULL, &count_of_arguments);

		info = (FunctionInfo)palloc0(sizeof(struct FunctionInfoData));
		funcctx->user_fctx = info;

		info->function_name = palloc0(count_of_arguments * sizeof(char *));
		for (int i = 0; i < count_of_arguments; i++)
		{
			info->function_name[i] = text_to_cstring((text *)arguments[i]);
		}

		info->cursor = 0;
		info->count_of_tuples = count_of_arguments;

		if (get_call_result_type(fcinfo, NULL, &info->result_desc) != TYPEFUNC_COMPOSITE)
		{
			ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED), errmsg("function returning record called in context that cannot accept type record")));
		}
		info->result_tuple_meta = TupleDescGetAttInMetadata(info->result_desc);
		MemoryContextSwitchTo(old_context);
	}

	funcctx = SRF_PERCALL_SETUP();
	info = (FunctionInfo)(funcctx->user_fctx);

	if (info->cursor == info->count_of_tuples)
	{
		SRF_RETURN_DONE(funcctx);
	}
	else
	{
		HeapTuple tuple;
		Datum tuple_return;
		char **values;
		values = palloc0(sizeof(char *) * 2);
		values[0] = pstrdup(info->function_name[info->cursor]);
		values[1] = GetFuncDefByName(info->function_name[info->cursor]);
		info->cursor++;
		tuple = BuildTupleFromCStrings(info->result_tuple_meta, values);
		tuple_return = HeapTupleGetDatum(tuple);
		SRF_RETURN_NEXT(funcctx, tuple_return);
	}
	PG_RETURN_NULL();
}
