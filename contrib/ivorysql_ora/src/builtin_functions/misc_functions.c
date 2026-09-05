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
#include "catalog/pg_type.h"
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
 * Numeric input is answered in Oracle's internal NUMBER format, because
 * that is what Oracle's VSIZE reports: one exponent byte, then one
 * mantissa byte per pair of significant decimal digits (trailing zeros
 * are not stored), plus one extra terminator byte (0x66) for negative
 * values; zero occupies a single byte.  So VSIZE(100) is 2, VSIZE(-1)
 * is 3 and VSIZE(12345.67) is 5, whichever native type carries the
 * value -- in Oracle every numeric literal is a NUMBER.
 *
 * Float4/float8 keep the type's storage width, which already equals
 * Oracle's BINARY_FLOAT/BINARY_DOUBLE sizes.  For varlena types the
 * logical (decompressed) data size is returned, excluding the varlena
 * header, so that VSIZE('abc') is 3, matching Oracle's behavior for
 * character data.  For fixed-width types the type's storage width is
 * returned.
 */

/*
 * Count the significant decimal digits in the textual form of a number,
 * skipping the sign, the decimal point, leading and trailing zeros.
 * Sets *negative when the value carries a minus sign.  Returns 0 when
 * every digit is zero.
 */
static int
count_significant_decimal_digits(const char *s, bool *negative)
{
	const char *p;
	const char *first = NULL;
	const char *last = NULL;
	int			ndigits = 0;

	*negative = false;
	if (*s == '-')
	{
		*negative = true;
		s++;
	}
	else if (*s == '+')
		s++;

	for (p = s; *p; p++)
	{
		if (*p == '.')
			continue;
		if (*p != '0')
		{
			if (first == NULL)
				first = p;
			last = p;
		}
	}
	if (first == NULL)
		return 0;

	for (p = first; p <= last; p++)
	{
		if (*p != '.')
			ndigits++;
	}
	return ndigits;
}

/*
 * Byte length of a value in Oracle's internal NUMBER format, given the
 * count of significant decimal digits and the sign of the value.
 */
static int32
oracle_number_byte_length(int ndigits, bool negative)
{
	if (ndigits == 0)
		return 1;			/* zero is stored as the single byte 0x80 */
	return 1 + (ndigits + 1) / 2 + (negative ? 1 : 0);
}

Datum
ora_vsize(PG_FUNCTION_ARGS)
{
	Datum		value = PG_GETARG_DATUM(0);
	int32		result;
	int			typlen;
	Oid			argtypeid;

	/* On first call, get the input type's typlen, and save at *fn_extra */
	if (fcinfo->flinfo->fn_extra == NULL)
	{
		/* Lookup the datatype of the supplied argument */
		argtypeid = get_fn_expr_argtype(fcinfo->flinfo, 0);

		typlen = get_typlen(argtypeid);
		if (typlen == 0)		/* should not happen */
			elog(ERROR, "cache lookup failed for type %u", argtypeid);

		fcinfo->flinfo->fn_extra = MemoryContextAlloc(fcinfo->flinfo->fn_mcxt,
													  sizeof(int) + sizeof(Oid));
		*((int *) fcinfo->flinfo->fn_extra) = typlen;
		*((Oid *) ((char *) fcinfo->flinfo->fn_extra + sizeof(int))) = argtypeid;
	}
	else
	{
		typlen = *((int *) fcinfo->flinfo->fn_extra);
		argtypeid = *((Oid *) ((char *) fcinfo->flinfo->fn_extra + sizeof(int)));
	}

	if (argtypeid == INT2OID || argtypeid == INT4OID ||
		argtypeid == INT8OID || argtypeid == NUMERICOID)
	{
		char		buf[64];
		const char *str;
		bool		negative;
		int			ndigits;

		if (argtypeid == NUMERICOID)
		{
			Numeric		num = DatumGetNumeric(value);

			/*
			 * Oracle's NUMBER has no NaN/Infinity counterpart, so keep the
			 * storage-size answer for those instead of inventing a
			 * NUMBER-format length for them.
			 */
			if (numeric_is_nan(num) || numeric_is_inf(num))
			{
				result = toast_raw_datum_size(value) - VARHDRSZ;
				PG_RETURN_INT32(result);
			}
			str = DatumGetCString(DirectFunctionCall1(numeric_out,
													  NumericGetDatum(num)));
		}
		else
		{
			int64		v;

			switch (argtypeid)
			{
				case INT2OID:
					v = DatumGetInt16(value);
					break;
				case INT4OID:
					v = DatumGetInt32(value);
					break;
				default:
					v = DatumGetInt64(value);
					break;
			}
			snprintf(buf, sizeof(buf), INT64_FORMAT, v);
			str = buf;
		}

		ndigits = count_significant_decimal_digits(str, &negative);
		PG_RETURN_INT32(oracle_number_byte_length(ndigits, negative));
	}

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
