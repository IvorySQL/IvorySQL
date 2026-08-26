/*-------------------------------------------------------------------------
 * Copyright 2025 IvorySQL Global Development Team
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
 * misc_functions.c
 *
 * This file contains the implementation of Oracle's
 * datatype-independent built-in functions.
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_functions/misc_functions.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "access/detoast.h"
#include "utils/formatting.h"
#include "utils/lsyscache.h"
#include "utils/numeric.h"
#include "varatt.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"

PG_FUNCTION_INFO_V1(uid);
PG_FUNCTION_INFO_V1(stragg_transfn);
PG_FUNCTION_INFO_V1(ora_vsize);


/*
 * ora_vsize
 *
 * Oracle-compatible VSIZE function.
 * Returns the number of bytes in the internal representation of the
 * argument.  NULL input yields NULL (the function is declared STRICT).
 *
 * For varlena types the logical (decompressed) data size is returned,
 * excluding the varlena header, so that VSIZE('abc') is 3, matching
 * Oracle's behavior for character data.  For fixed-width types the
 * type's storage width is returned.
 */
Datum
ora_vsize(PG_FUNCTION_ARGS)
{
	Datum		value = PG_GETARG_DATUM(0);
	int32		result;
	int			typlen;

	/* On first call, get the input type's typlen, and save at *fn_extra */
	if (fcinfo->flinfo->fn_extra == NULL)
	{
		/* Lookup the datatype of the supplied argument */
		Oid			argtypeid = get_fn_expr_argtype(fcinfo->flinfo, 0);

		typlen = get_typlen(argtypeid);
		if (typlen == 0)		/* should not happen */
			elog(ERROR, "cache lookup failed for type %u", argtypeid);

		fcinfo->flinfo->fn_extra = MemoryContextAlloc(fcinfo->flinfo->fn_mcxt,
													  sizeof(int));
		*((int *) fcinfo->flinfo->fn_extra) = typlen;
	}
	else
		typlen = *((int *) fcinfo->flinfo->fn_extra);

	if (typlen == -1)
	{
		/*
		 * varlena type.  toast_raw_datum_size() normalizes 1-byte/4-byte
		 * headers, compression and external (toasted) storage to the
		 * logical (decompressed) size using the 4-byte header convention,
		 * so subtracting VARHDRSZ yields the payload byte count in every
		 * case -- the same pattern octet_length() uses.
		 */
		result = toast_raw_datum_size(value) - VARHDRSZ;
	}
	else if (typlen == -2)
	{
		/* cstring */
		result = strlen(DatumGetCString(value)) + 1;
	}
	else
	{
		/* ordinary fixed-width type */
		result = typlen;
	}

	PG_RETURN_INT32(result);
}


Datum
uid(PG_FUNCTION_ARGS)
{
	PG_RETURN_UINT32(GetUserId());
}

/*
 * stragg_transfn
 *
 * Transition function for Oracle-compatible STRAGG aggregate.
 * Concatenates non-null text values with ',' as separator.
 * Uses the same StringInfo state layout as string_agg_transfn so that
 * string_agg_finalfn and string_agg_combine can be reused directly.
 *
 * State layout (mirrors string_agg internal state):
 *   data   = "," + val1 + "," + val2 + ...
 *   cursor = 1  (length of the leading delimiter to strip in finalfn)
 */
Datum
stragg_transfn(PG_FUNCTION_ARGS)
{
	StringInfo	state;
	MemoryContext aggcontext;
	MemoryContext oldcontext;

	if (!AggCheckCallContext(fcinfo, &aggcontext))
		elog(ERROR, "stragg_transfn called in non-aggregate context");

	state = PG_ARGISNULL(0) ? NULL : (StringInfo) PG_GETARG_POINTER(0);

	/* Skip NULL input values */
	if (!PG_ARGISNULL(1))
	{
		text	   *value = PG_GETARG_TEXT_PP(1);

		if (state == NULL)
		{
			oldcontext = MemoryContextSwitchTo(aggcontext);
			state = makeStringInfo();
			MemoryContextSwitchTo(oldcontext);

			/* Prepend delimiter so finalfn can strip it uniformly */
			appendStringInfoChar(state, ',');
			state->cursor = 1;	/* length of "," */
		}
		else
		{
			appendStringInfoChar(state, ',');
		}

		appendBinaryStringInfo(state, VARDATA_ANY(value), VARSIZE_ANY_EXHDR(value));
	}

	if (state)
		PG_RETURN_POINTER(state);
	PG_RETURN_NULL();
}
