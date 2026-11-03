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
#include "catalog/pg_type.h"
#include "parser/parse_coerce.h"
#include "utils/array.h"
#include "utils/date.h"
#include "utils/formatting.h"
#include "utils/lsyscache.h"
#include "utils/numeric.h"
#include "utils/timestamp.h"
#include "utils/typcache.h"
#include "varatt.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"

PG_FUNCTION_INFO_V1(uid);
PG_FUNCTION_INFO_V1(stragg_transfn);
PG_FUNCTION_INFO_V1(ora_vsize);
PG_FUNCTION_INFO_V1(ora_greatest_varchar);
PG_FUNCTION_INFO_V1(ora_least_varchar);
PG_FUNCTION_INFO_V1(ora_greatest_number);
PG_FUNCTION_INFO_V1(ora_least_number);
PG_FUNCTION_INFO_V1(ora_greatest_date);
PG_FUNCTION_INFO_V1(ora_least_date);
PG_FUNCTION_INFO_V1(ora_greatest_timestamp);
PG_FUNCTION_INFO_V1(ora_least_timestamp);
PG_FUNCTION_INFO_V1(ora_greatest_timestamptz);
PG_FUNCTION_INFO_V1(ora_least_timestamptz);


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

/****************************************************************
 * greatest / least
 *
 * Oracle's GREATEST and LEAST.  Oracle semantics differ from the
 * pg_catalog.greatest()/least() builtins in two ways:
 *
 *   - Oracle returns NULL as soon as any argument is NULL, while the
 *     PostgreSQL builtins ignore NULL inputs and answer the extreme
 *     of the remaining ones;
 *   - Oracle compares using the datatype of the *first* argument (the
 *     "return type" rule), while the PostgreSQL builtins fold every
 *     argument into one common type.
 *
 * These overloads in the sys schema implement the Oracle contract.
 * The first argument is pinned to a concrete type and the remainder is
 * variadic, so the return type follows the first argument and the
 * overload set doubles as the "compare by the first argument's type"
 * rule.  A single polymorphic anyelement signature was tried first,
 * but an anyelement argument refuses unknown literals, and the fixed
 * per-type set must not grow a varchar2 wrapper on top: oracle mode
 * defines implicit casts from the integer and NUMBER types to the
 * Oracle string types, so a varchar2 first argument makes the plain
 * GREATEST(1, 2) shape ambiguous between the wrappers and the numeric
 * overload.  Without the wrapper VARCHAR2 arguments reach the text
 * overloads through varchar2's implicit cast to text.
 *
 * VARCHAR2 comparison is Oracle's non-padded BINARY comparison, so the
 * text overloads compare bytes with memcmp() rather than going through
 * a collation-aware comparison; CHAR compares blank-padded, which the
 * same byte comparison reproduces because char's payload keeps its
 * blanks.  The numeric and datetime overloads reuse the type's own
 * comparison support.
 *
 * The functions are declared STRICT, so a NULL first argument already
 * answers NULL; a NULL carried inside the variadic argument list is
 * caught by the element scan below, because STRICT only inspects the
 * arguments themselves, and the variadic element values live in the
 * array argument.  One entry answers at least two arguments: oracle
 * mode's function resolution does not accept a variadic call with only
 * the fixed parameters, so GREATEST(x) keeps resolving to the
 * pg_catalog builtin.
 *
 * One structural note: in oracle mode the parser turns an *unqualified*
 * GREATEST/LEAST call into a MinMaxExpr (ora_gram.y builds IS_GREATEST
 * / IS_LEAST straight from the grammar), so these sys schema functions
 * are reached through a schema-qualified sys.greatest()/sys.least()
 * call, the same way sys.substrc() and friends are reached for the
 * qualified spelling.
 ****************************************************************/

/*
 * Byte-wise comparison of two text values, i.e. Oracle's BINARY
 * comparison for VARCHAR2: differing bytes decide in unsigned byte
 * order, a proper prefix sorts before its extension.
 */
static int
ora_varchar2_cmp(text *a, text *b)
{
	int			la = VARSIZE_ANY_EXHDR(a);
	int			lb = VARSIZE_ANY_EXHDR(b);
	int			cmp;

	cmp = memcmp(VARDATA_ANY(a), VARDATA_ANY(b), Min(la, lb));
	if (cmp != 0)
		return cmp;

	return (la > lb) - (la < lb);
}

/*
 * Shared walk over the variadic argument list: compare every non-null
 * element against the running extreme and answer NULL as soon as one
 * element is NULL.  "greatest" selects the maximum, "least" the
 * minimum.  The compare callback receives the candidate as its first
 * argument and the running extreme as its second.  Returns false when
 * a NULL element was met, in which case *best must not be used.
 */
typedef int (*ora_extremum_cmp) (Datum candidate, Datum best);

static bool
ora_extremum_common(FunctionCallInfo fcinfo, Datum *best,
					ArrayType *rest, ora_extremum_cmp cmpfunc, bool greatest)
{
	ArrayIterator it;
	Datum		elem;
	bool		isnull;

	it = array_create_iterator(rest, 0, NULL);
	while (array_iterate(it, &elem, &isnull))
	{
		int			cmp;

		if (isnull)
		{
			array_free_iterator(it);
			return false;
		}

		cmp = cmpfunc(elem, *best);
		if (greatest ? cmp > 0 : cmp < 0)
			*best = elem;
	}
	array_free_iterator(it);

	return true;
}

/* ---- text / VARCHAR2 ---- */

static int
ora_text_cmp(Datum a, Datum b)
{
	return ora_varchar2_cmp(DatumGetTextPP(a), DatumGetTextPP(b));
}

static Datum
ora_extremum_varchar(FunctionCallInfo fcinfo, bool greatest)
{
	Datum		best = PG_GETARG_DATUM(0);
	ArrayType  *rest = PG_GETARG_ARRAYTYPE_P(1);

	if (!ora_extremum_common(fcinfo, &best, rest, ora_text_cmp, greatest))
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(DatumGetTextPP(best));
}

Datum
ora_greatest_varchar(PG_FUNCTION_ARGS)
{
	return ora_extremum_varchar(fcinfo, true);
}

Datum
ora_least_varchar(PG_FUNCTION_ARGS)
{
	return ora_extremum_varchar(fcinfo, false);
}

/* ---- NUMBER / numeric ---- */

static int
ora_numeric_cmp(Datum a, Datum b)
{
	return DatumGetInt32(DirectFunctionCall2(numeric_cmp, a, b));
}

static Datum
ora_extremum_number(FunctionCallInfo fcinfo, bool greatest)
{
	Datum		best = PG_GETARG_DATUM(0);
	ArrayType  *rest = PG_GETARG_ARRAYTYPE_P(1);

	if (!ora_extremum_common(fcinfo, &best, rest, ora_numeric_cmp, greatest))
		PG_RETURN_NULL();

	PG_RETURN_NUMERIC(DatumGetNumeric(best));
}

Datum
ora_greatest_number(PG_FUNCTION_ARGS)
{
	return ora_extremum_number(fcinfo, true);
}

Datum
ora_least_number(PG_FUNCTION_ARGS)
{
	return ora_extremum_number(fcinfo, false);
}

/* ---- DATE ---- */

/*
 * In oracle mode the type name date resolves to sys.oradate, which keeps
 * its value as a Timestamp (microseconds since 2000-01-01, because the
 * Oracle DATE carries a time-of-day), not as pg_catalog.date's 4-byte
 * day count.  Compare through oradate's own ordering -- the same
 * timestamp_cmp_internal() call its operators and the oradate_larger()
 * /oradate_smaller() support functions in oradate.c use -- and hand the
 * winning Datum back unchanged: reading the value as a DateADT would
 * truncate the 8-byte microsecond count to 32 bits and corrupt both the
 * comparison and the answer.  Whole-day values order as calendar days.
 */
static int
ora_date_cmp(Datum a, Datum b)
{
	return timestamp_cmp_internal(DatumGetTimestamp(a),
								  DatumGetTimestamp(b));
}

static Datum
ora_extremum_date(FunctionCallInfo fcinfo, bool greatest)
{
	Datum		best = PG_GETARG_DATUM(0);
	ArrayType  *rest = PG_GETARG_ARRAYTYPE_P(1);

	if (!ora_extremum_common(fcinfo, &best, rest, ora_date_cmp, greatest))
		PG_RETURN_NULL();

	PG_RETURN_TIMESTAMP(DatumGetTimestamp(best));
}

Datum
ora_greatest_date(PG_FUNCTION_ARGS)
{
	return ora_extremum_date(fcinfo, true);
}

Datum
ora_least_date(PG_FUNCTION_ARGS)
{
	return ora_extremum_date(fcinfo, false);
}

/* ---- TIMESTAMP ---- */

static int
ora_timestamp_cmp(Datum a, Datum b)
{
	return DatumGetInt32(DirectFunctionCall2(timestamp_cmp, a, b));
}

static Datum
ora_extremum_timestamp(FunctionCallInfo fcinfo, bool greatest)
{
	Datum		best = PG_GETARG_DATUM(0);
	ArrayType  *rest = PG_GETARG_ARRAYTYPE_P(1);

	if (!ora_extremum_common(fcinfo, &best, rest, ora_timestamp_cmp, greatest))
		PG_RETURN_NULL();

	PG_RETURN_TIMESTAMP(DatumGetTimestamp(best));
}

Datum
ora_greatest_timestamp(PG_FUNCTION_ARGS)
{
	return ora_extremum_timestamp(fcinfo, true);
}

Datum
ora_least_timestamp(PG_FUNCTION_ARGS)
{
	return ora_extremum_timestamp(fcinfo, false);
}

/* ---- TIMESTAMP WITH TIME ZONE ---- */

static int
ora_timestamptz_cmp(Datum a, Datum b)
{
	return timestamptz_cmp_internal(DatumGetTimestampTz(a),
									DatumGetTimestampTz(b));
}

static Datum
ora_extremum_timestamptz(FunctionCallInfo fcinfo, bool greatest)
{
	Datum		best = PG_GETARG_DATUM(0);
	ArrayType  *rest = PG_GETARG_ARRAYTYPE_P(1);

	if (!ora_extremum_common(fcinfo, &best, rest, ora_timestamptz_cmp, greatest))
		PG_RETURN_NULL();

	PG_RETURN_TIMESTAMPTZ(DatumGetTimestampTz(best));
}

Datum
ora_greatest_timestamptz(PG_FUNCTION_ARGS)
{
	return ora_extremum_timestamptz(fcinfo, true);
}

Datum
ora_least_timestamptz(PG_FUNCTION_ARGS)
{
	return ora_extremum_timestamptz(fcinfo, false);
}
