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
#include "catalog/pg_type_d.h"
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
 * ora_number_vsize
 *
 * Return the size of a numeric value in Oracle's internal NUMBER format:
 * one exponent byte, one mantissa byte per two significant base-100 digits,
 * plus one terminator byte for negative values.  Zero is a single byte.
 * Trailing all-zero mantissa bytes are dropped, but only whole bytes:
 * VSIZE(100) is 2 while VSIZE(1.50) is 3, matching Oracle.
 *
 * The mantissa's base-100 byte boundaries are anchored at the decimal
 * point: the integer digits are grouped right to left (an odd count leaves
 * a leading one-digit group) and the fractional digits are grouped left to
 * right, padded with a trailing zero when their count is odd.  Grouping
 * the concatenated digits without that boundary would be wrong; e.g. 1.5
 * is the two mantissa bytes 1 and 50, so VSIZE(1.5) is 3 even though the
 * value has only two significant decimal digits.
 *
 * The input is the plain decimal rendering of the value ("123.4500").
 * Returns -1 if the string is not a plain decimal number, so that the
 * caller can fall back to the storage-width result.
 */
static int32
ora_number_vsize(const char *numstr)
{
	const char *cp;
	const char *intdigits;
	const char *fracdigits;
	const char *dot = NULL;
	int			intlen;
	int			fraclen;
	int			mantbytes;
	bool		negative = false;
	bool		saw_nonzero = false;

	cp = numstr;
	if (*cp == '+' || *cp == '-')
		negative = (*cp++ == '-');

	intdigits = NULL;
	fracdigits = NULL;
	intlen = 0;
	fraclen = 0;
	for (; *cp; cp++)
	{
		if (*cp >= '0' && *cp <= '9')
		{
			if (dot == NULL)
			{
				if (intdigits == NULL)
					intdigits = cp;
				intlen++;
			}
			else
			{
				if (fracdigits == NULL)
					fracdigits = cp;
				fraclen++;
			}

			if (*cp != '0')
				saw_nonzero = true;
		}
		else if (*cp == '.' && dot == NULL)
			dot = cp;
		else
			return -1;
	}

	if ((intdigits == NULL && fracdigits == NULL) || !saw_nonzero)
		return 1;				/* zero */

	/* drop leading zero digits of the integer part */
	while (intlen > 0 && *intdigits == '0')
	{
		intdigits++;
		intlen--;
	}

	/* drop trailing zero digits of the fractional part */
	while (fraclen > 0 && fracdigits[fraclen - 1] == '0')
		fraclen--;

	/*
	 * Count the mantissa bytes.  The digit pairs are aligned on the decimal
	 * point, so an odd integer digit count leaves a leading one-digit group.
	 * With no fractional part, trailing integer zero pairs form all-zero
	 * mantissa bytes that Oracle does not store.  With an integer part,
	 * leading fractional zero pairs are significant interior bytes (e.g.
	 * 1.005 stores 1,00,50), but without an integer part they are not.
	 * An odd fractional digit count is zero-padded on the right, so 1.5
	 * yields the same 50 byte as 1.50.
	 */
	mantbytes = 0;
	if (intlen > 0)
	{
		mantbytes = (intlen + 1) / 2;

		if (fraclen == 0)
		{
			int			tz = 0;

			while (tz < intlen && intdigits[intlen - 1 - tz] == '0')
				tz++;
			mantbytes -= tz / 2;
		}
	}

	if (fraclen > 0)
	{
		mantbytes += (fraclen + 1) / 2;

		if (intlen == 0)
		{
			int			lz = 0;

			while (lz < fraclen && fracdigits[lz] == '0')
				lz++;
			mantbytes -= lz / 2;
		}
	}

	return 1 + mantbytes + (negative ? 1 : 0);
}

/*
 * ora_vsize
 *
 * Oracle-compatible VSIZE function.
 * Returns the number of bytes in the internal representation of the
 * argument.  NULL input yields NULL (the function is declared STRICT).
 *
 * For integer and numeric-family input the size in Oracle's internal
 * NUMBER format is returned, so that VSIZE(100) is 2 and VSIZE(-1) is 3,
 * matching Oracle regardless of the type carrying the value.  For other
 * varlena types the logical (decompressed) data size is returned,
 * excluding the varlena header, so that VSIZE('abc') is 3, matching
 * Oracle's behavior for character data.  For fixed-width types the
 * type's storage width is returned (which also matches Oracle for
 * BINARY_FLOAT and BINARY_DOUBLE).
 */
Datum
ora_vsize(PG_FUNCTION_ARGS)
{
	Datum		value = PG_GETARG_DATUM(0);
	int32		result;
	int			typlen;
	Oid			argbase;

	/* On first call, get the input type's OID and typlen, saved at *fn_extra */
	if (fcinfo->flinfo->fn_extra == NULL)
	{
		Oid			argtypeid = get_fn_expr_argtype(fcinfo->flinfo, 0);
		Oid		   *extra;

		argbase = getBaseType(argtypeid);
		typlen = get_typlen(argbase);
		if (typlen == 0)		/* should not happen */
			elog(ERROR, "cache lookup failed for type %u", argtypeid);

		extra = (Oid *) MemoryContextAlloc(fcinfo->flinfo->fn_mcxt,
										   sizeof(Oid) * 2);
		extra[0] = argbase;
		extra[1] = (Oid) typlen;
		fcinfo->flinfo->fn_extra = extra;
	}
	else
	{
		Oid		   *extra = (Oid *) fcinfo->flinfo->fn_extra;

		argbase = extra[0];
		typlen = (int) extra[1];
	}

	if (argbase == INT2OID || argbase == INT4OID ||
		argbase == INT8OID || argbase == NUMERICOID ||
		argbase == NUMBEROID)
	{
		const char *numstr;
		int32		nvsize;

		switch (argbase)
		{
			case INT2OID:
				numstr = DatumGetCString(DirectFunctionCall1(int2out, value));
				break;
			case INT4OID:
				numstr = DatumGetCString(DirectFunctionCall1(int4out, value));
				break;
			case INT8OID:
				numstr = DatumGetCString(DirectFunctionCall1(int8out, value));
				break;
			default:
				/* sys.number is binary-coercible with numeric */
				numstr = DatumGetCString(DirectFunctionCall1(numeric_out, value));
				break;
		}

		nvsize = ora_number_vsize(numstr);
		if (nvsize > 0)
			PG_RETURN_INT32(nvsize);

		/*
		 * Not a plain decimal number (e.g. NaN): report the storage size,
		 * as there is no Oracle NUMBER equivalent for such values.
		 */
		result = (typlen == -1) ? toast_raw_datum_size(value) - VARHDRSZ : typlen;
	}
	else if (typlen == -1)
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
