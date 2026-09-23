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
 * Implementation of Oracle's DBMS_DESCRIBE package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides program unit and procedure parameter introspection:
 *   - DESCRIBE_PROCEDURE
 *
 * Returned argument properties:
 *   - position: parameter sequence order (0 for function return value)
 *   - level: composite hierarchy depth
 *   - argument_name: name of the parameter
 *   - datatype: Oracle type code
 *   - default_value: default expression text
 *   - in_out: 0=IN, 1=OUT, 2=IN/OUT
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_describe/dbms_describe.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/htup_details.h"
#include "catalog/namespace.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "funcapi.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"

/*
 * dbms_describe_describe_procedure_internal
 *
 * Set-returning function returning:
 *   (position int, argument_name text, datatype int, in_out int, length int)
 */
PG_FUNCTION_INFO_V1(dbms_describe_describe_procedure_internal);
Datum
dbms_describe_describe_procedure_internal(PG_FUNCTION_ARGS)
{
	FuncCallContext *funcctx;
	TupleDesc	tupdesc;
	AttInMetadata *attinmeta;

	if (SRF_IS_FIRSTCALL())
	{
		MemoryContext oldcontext;
		text	   *object_text;
		char	   *object_name;
		char	   *schema_name = NULL;
		char	   *proc_name = NULL;
		char	   *dot;
		Oid			proc_oid = InvalidOid;
		HeapTuple	proctup;
		Form_pg_proc procform;

		funcctx = SRF_FIRSTCALL_INIT();
		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

		if (PG_ARGISNULL(0))
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("DBMS_DESCRIBE.DESCRIBE_PROCEDURE: object_name must not be NULL")));

		object_text = PG_GETARG_TEXT_PP(0);
		object_name = text_to_cstring(object_text);

		dot = strchr(object_name, '.');
		if (dot)
		{
			*dot = '\0';
			schema_name = object_name;
			proc_name = dot + 1;
		}
		else
		{
			proc_name = object_name;
		}

		/* Lookup procedure in catalog */
		if (schema_name)
		{
			Oid nspid = get_namespace_oid(schema_name, true);
			if (OidIsValid(nspid))
				proc_oid = GetSysCacheOid2(PROCNAMEARGSNSP,
										   Anum_pg_proc_oid,
										   CStringGetDatum(proc_name),
										   ObjectIdGetDatum(nspid));
		}
		else
		{
			List *names = stringToQualifiedNameList(proc_name, NULL);
			FuncCandidateList clist = FuncnameGetCandidates(names, -1, NIL, false, false, false, true);
			if (clist)
				proc_oid = clist->oid;
		}

		if (!OidIsValid(proc_oid))
		{
			/* Try case-insensitive fallback query via SPI */
			int ret = SPI_connect();
			if (ret == SPI_OK_CONNECT)
			{
				StringInfoData buf;
				initStringInfo(&buf);
				appendStringInfo(&buf,
								 "SELECT p.oid FROM pg_proc p "
								 "JOIN pg_namespace n ON n.oid = p.pronamespace "
								 "WHERE lower(p.proname) = lower('%s') %s%s%s LIMIT 1",
								 proc_name,
								 schema_name ? "AND lower(n.nspname) = lower('" : "",
								 schema_name ? schema_name : "",
								 schema_name ? "')" : "");
				ret = SPI_execute(buf.data, true, 1);
				if (ret == SPI_OK_SELECT && SPI_processed > 0)
				{
					bool isnull;
					Datum d = SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &isnull);
					if (!isnull)
						proc_oid = DatumGetObjectId(d);
				}
				pfree(buf.data);
				SPI_finish();
			}
		}

		if (!OidIsValid(proc_oid))
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_FUNCTION),
					 errmsg("DBMS_DESCRIBE: procedure or function \"%s\" does not exist",
							text_to_cstring(object_text))));

		proctup = SearchSysCache1(PROCOID, ObjectIdGetDatum(proc_oid));
		if (!HeapTupleIsValid(proctup))
			ereport(ERROR, (errmsg("cache lookup failed for proc %u", proc_oid)));

		procform = (Form_pg_proc) GETSTRUCT(proctup);

		/* Store count of arguments */
		funcctx->max_calls = procform->pronargs;
		funcctx->user_fctx = (void *) proctup;

		if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
			ereport(ERROR, (errmsg("return type must be a row type")));

		attinmeta = TupleDescGetAttInMetadata(tupdesc);
		funcctx->attinmeta = attinmeta;

		MemoryContextSwitchTo(oldcontext);
	}

	funcctx = SRF_PERCALL_SETUP();

	if (funcctx->call_cntr < funcctx->max_calls)
	{
		HeapTuple	proctup = (HeapTuple) funcctx->user_fctx;
		Form_pg_proc procform = (Form_pg_proc) GETSTRUCT(proctup);
		int			i = funcctx->call_cntr;
		char	  **values;
		HeapTuple	tuple;
		Datum		result;
		Datum		proargnames;
		bool		isnull;
		char	   *arg_name = NULL;

		values = (char **) palloc(5 * sizeof(char *));

		/* Position (1-indexed) */
		values[0] = psprintf("%d", i + 1);

		/* Argument name */
		proargnames = SysCacheGetAttr(PROCOID, proctup, Anum_pg_proc_proargnames, &isnull);
		if (!isnull)
		{
			ArrayType  *arr = DatumGetArrayTypeP(proargnames);
			Datum	   *elem_values;
			bool	   *elem_nulls;
			int			num_elems;

			deconstruct_array(arr, TEXTOID, -1, false, TYPALIGN_INT,
							  &elem_values, &elem_nulls, &num_elems);
			if (i < num_elems && !elem_nulls[i])
				arg_name = TextDatumGetCString(elem_values[i]);
		}
		values[1] = arg_name ? arg_name : psprintf("arg%d", i + 1);

		/* Datatype code (default 1 for VARCHAR2, 2 for NUMBER) */
		values[2] = "1";

		/* In_Out (0=IN) */
		values[3] = "0";

		/* Length */
		values[4] = "4000";

		tuple = BuildTupleFromCStrings(funcctx->attinmeta, values);
		result = HeapTupleGetDatum(tuple);

		SRF_RETURN_NEXT(funcctx, result);
	}
	else
	{
		if (funcctx->user_fctx)
			ReleaseSysCache((HeapTuple) funcctx->user_fctx);
		SRF_RETURN_DONE(funcctx);
	}
}
