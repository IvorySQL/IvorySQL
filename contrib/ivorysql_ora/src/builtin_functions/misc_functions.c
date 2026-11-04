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
#include "common/hashfn.h"
#include "utils/formatting.h"
#include "utils/lsyscache.h"
#include "utils/numeric.h"
#include "varatt.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"

PG_FUNCTION_INFO_V1(uid);
PG_FUNCTION_INFO_V1(stragg_transfn);
PG_FUNCTION_INFO_V1(ora_vsize);
PG_FUNCTION_INFO_V1(ora_hash);


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


/* Oracle's ORA_HASH accepts max_bucket and seed_value in 0..4294967295. */
#define ORA_HASH_MAX_BUCKET	((uint64) 4294967295)

static bytea *ora_hash_serialize(FunctionCallInfo fcinfo, Datum value);

/*
 * ora_hash
 *
 * Oracle-compatible ORA_HASH function.
 * Computes a deterministic hash of its first argument and returns a value
 * in the range [0, max_bucket]; the optional seed_value varies the mapping
 * (Oracle applies the hash to the combination of the expression and the
 * seed).  The function is intended for analysis and sampling -- splitting
 * data into buckets -- and is NOT a security hash.
 *
 * The hash is computed over the binary (send) representation of the input,
 * so the result does not depend on session formatting settings (datestyle,
 * etc.), and it works uniformly for any data type.  Exact numeric values
 * are not guaranteed to match Oracle (whose algorithm is undocumented);
 * only the contract above (range, determinism, seed semantics) is
 * reproduced.
 *
 * NULL input yields NULL (the function is declared STRICT).
 */
Datum
ora_hash(PG_FUNCTION_ARGS)
{
	Datum		value = PG_GETARG_DATUM(0);
	int64		max_bucket = PG_ARGISNULL(1) ? (int64) ORA_HASH_MAX_BUCKET : PG_GETARG_INT64(1);
	int64		seed_value = PG_ARGISNULL(2) ? 0 : PG_GETARG_INT64(2);
	bytea	   *blob;
	uint64		hash;

	if (max_bucket < 0 || (uint64) max_bucket > ORA_HASH_MAX_BUCKET)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("ORA_HASH max_bucket must be between 0 and " UINT64_FORMAT,
						ORA_HASH_MAX_BUCKET)));
	if (seed_value < 0 || (uint64) seed_value > ORA_HASH_MAX_BUCKET)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("ORA_HASH seed_value must be between 0 and " UINT64_FORMAT,
						ORA_HASH_MAX_BUCKET)));

	blob = ora_hash_serialize(fcinfo, value);
	hash = hash_any_extended((const unsigned char *) VARDATA_ANY(blob),
							 VARSIZE_ANY_EXHDR(blob),
							 (uint64) seed_value);

	/*
	 * max_bucket + 1 is at most 2^32, so the modulo of an arbitrary 64-bit
	 * hash is exact and the result always lies in [0, max_bucket].
	 */
	PG_RETURN_INT64((int64) (hash % ((uint64) max_bucket + 1)));
}

/*
 * Serialize a value of the function's first argument type into a bytea
 * suitable for hashing.  The type's binary output function (typsend) is
 * preferred because it is independent of session GUC settings and, for
 * domain inputs (sys.varchar2, sys.number, sys.clob, ...), resolves to the
 * base type's send function.  Types without a binary output fall back to
 * their text output function.
 */
static bytea *
ora_hash_serialize(FunctionCallInfo fcinfo, Datum value)
{
	Oid			argtype;
	Oid			auxfunc;
	bool		typisvarlena;
	Datum		result;

	/* On each call, resolve the actual datatype of the anycompatible arg */
	argtype = get_fn_expr_argtype(fcinfo->flinfo, 0);
	if (!OidIsValid(argtype))
		elog(ERROR, "could not determine input data type for ORA_HASH");

	getTypeBinaryOutputInfo(argtype, &auxfunc, &typisvarlena);
	if (OidIsValid(auxfunc))
	{
		result = OidFunctionCall1(auxfunc, value);
		return (bytea *) PG_DETOAST_DATUM(result);
	}

	/* No binary output; fall back to the text representation. */
	getTypeOutputInfo(argtype, &auxfunc, &typisvarlena);
	{
		char	   *str = DatumGetCString(OidFunctionCall1(auxfunc, value));
		int			len = strlen(str);
		bytea	   *blob = (bytea *) palloc(VARHDRSZ + len);

		SET_VARSIZE(blob, VARHDRSZ + len);
		memcpy(VARDATA(blob), str, len);
		return blob;
	}
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
