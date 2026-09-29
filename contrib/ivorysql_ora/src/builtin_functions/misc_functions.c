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
#include "mb/pg_wchar.h"

PG_FUNCTION_INFO_V1(uid);
PG_FUNCTION_INFO_V1(stragg_transfn);
PG_FUNCTION_INFO_V1(ora_vsize);
PG_FUNCTION_INFO_V1(ora_dump);


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

/*
 * Type code mapper for Oracle DUMP()
 * Maps PostgreSQL and IvorySQL data types to Oracle Type Codes:
 *   1   - VARCHAR2
 *   2   - NUMBER / numeric / int2 / int4 / int8
 *   8   - LONG
 *   12  - DATE / sys.oradate
 *   23  - RAW / bytea
 *   96  - CHAR / bpchar
 *   100 - BINARY_FLOAT / float4
 *   101 - BINARY_DOUBLE / float8
 *   180 - TIMESTAMP / sys.oratimestamp
 *   181 - TIMESTAMP WITH TIME ZONE / sys.oratimestamptz
 *   182 - INTERVAL YEAR TO MONTH / sys.yminterval
 *   183 - INTERVAL DAY TO SECOND / sys.dsinterval
 *   231 - TIMESTAMP WITH LOCAL TIME ZONE / sys.oratimestampltz
 *   Other types default to 1 (character representation) or general type code.
 */
static int
get_oracle_type_code(Oid typid)
{
	char *typname = format_type_be(typid);

	if (typname == NULL)
		return 1;

	if (strcmp(typname, "character") == 0 ||
		strcmp(typname, "bpchar") == 0 ||
		strcmp(typname, "char") == 0 ||
		strstr(typname, "char") != NULL && strstr(typname, "varchar") == NULL)
		return 96;

	if (strcmp(typname, "text") == 0 ||
		strstr(typname, "varchar") != NULL)
		return 1;

	if (strcmp(typname, "numeric") == 0 ||
		strcmp(typname, "smallint") == 0 ||
		strcmp(typname, "integer") == 0 ||
		strcmp(typname, "bigint") == 0 ||
		strstr(typname, "number") != NULL)
		return 2;

	if (strcmp(typname, "real") == 0 ||
		strcmp(typname, "float4") == 0 ||
		strstr(typname, "binary_float") != NULL)
		return 100;

	if (strcmp(typname, "double precision") == 0 ||
		strcmp(typname, "float8") == 0 ||
		strstr(typname, "binary_double") != NULL)
		return 101;

	if (strcmp(typname, "date") == 0 ||
		strstr(typname, "oradate") != NULL)
		return 12;

	if (strstr(typname, "timestamp with time zone") != NULL ||
		strstr(typname, "oratimestamptz") != NULL)
		return 181;

	if (strstr(typname, "timestamp with local time zone") != NULL ||
		strstr(typname, "oratimestampltz") != NULL)
		return 231;

	if (strstr(typname, "timestamp") != NULL)
		return 180;

	if (strstr(typname, "yminterval") != NULL)
		return 182;

	if (strstr(typname, "dsinterval") != NULL)
		return 183;

	if (strcmp(typname, "bytea") == 0 ||
		strstr(typname, "raw") != NULL)
		return 23;

	if (strstr(typname, "long") != NULL)
		return 8;

	return 1;
}

/*
 * Append byte value formatted according to Oracle return_fmt rules.
 *
 * return_fmt:
 *   8:  Octal
 *   10: Decimal
 *   16: Hexadecimal
 *   17: Character (printable ASCII as character, control as ^X, other in hex)
 */
static void
append_dump_byte(StringInfo buf, unsigned char byte, int fmt)
{
	switch (fmt)
	{
		case 8:
			appendStringInfo(buf, "%o", (unsigned int) byte);
			break;
		case 16:
			appendStringInfo(buf, "%x", (unsigned int) byte);
			break;
		case 17:
			if (byte >= 32 && byte <= 126)
			{
				appendStringInfoChar(buf, (char) byte);
			}
			else if (byte > 0 && byte < 32)
			{
				appendStringInfo(buf, "^%c", (char) (byte + 64));
			}
			else if (byte == 127)
			{
				appendStringInfoString(buf, "^?");
			}
			else
			{
				appendStringInfo(buf, "%x", (unsigned int) byte);
			}
			break;
		case 10:
		default:
			appendStringInfo(buf, "%u", (unsigned int) byte);
			break;
	}
}

/*
 * ora_dump
 *
 * Oracle-compatible DUMP function:
 * DUMP(expr [, return_fmt [, start_position [, length ] ] ])
 *
 * Returns a VARCHAR2 string containing datatype code, length in bytes,
 * optional character set information, and byte values of internal representation.
 * Returns NULL if expr is NULL.
 */
Datum
ora_dump(PG_FUNCTION_ARGS)
{
	Datum		value;
	Oid			argtypeid;
	int			typlen;
	int			type_code;
	int			raw_fmt = 10;
	int			fmt = 10;
	bool		include_charset = false;
	int32		start_pos = 1;
	int32		length = -1;
	const char *bytes = NULL;
	int32		total_len = 0;
	int32		dump_start;
	int32		dump_len;
	StringInfoData res;
	int32		i;
	bool		palloced = false;

	/* If expr (arg 0) is NULL, Oracle DUMP returns NULL */
	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	value = PG_GETARG_DATUM(0);
	argtypeid = get_fn_expr_argtype(fcinfo->flinfo, 0);
	if (!OidIsValid(argtypeid))
		elog(ERROR, "could not determine data type of input expression");

	type_code = get_oracle_type_code(argtypeid);
	typlen = get_typlen(argtypeid);

	/* Parse optional return_fmt */
	if (PG_NARGS() >= 2 && !PG_ARGISNULL(1))
	{
		raw_fmt = PG_GETARG_INT32(1);
		if (raw_fmt >= 1000)
		{
			include_charset = true;
			fmt = raw_fmt - 1000;
		}
		else
		{
			fmt = raw_fmt;
		}

		if (fmt != 8 && fmt != 10 && fmt != 16 && fmt != 17)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("invalid return_fmt %d for dump(); expected 8, 10, 16, 17, or 1000+format", raw_fmt)));
	}

	/* Parse optional start_position */
	if (PG_NARGS() >= 3 && !PG_ARGISNULL(2))
	{
		start_pos = PG_GETARG_INT32(2);
	}

	/* Parse optional length */
	if (PG_NARGS() >= 4 && !PG_ARGISNULL(3))
	{
		length = PG_GETARG_INT32(3);
	}

	/* Retrieve internal bytes and byte length */
	if (typlen == -1)
	{
		/* Varlena type */
		struct varlena *v = PG_DETOAST_DATUM_PACKED(value);
		total_len = VARSIZE_ANY_EXHDR(v);
		bytes = VARDATA_ANY(v);
	}
	else if (typlen == -2)
	{
		/* C-string */
		bytes = DatumGetCString(value);
		total_len = strlen(bytes);
	}
	else if (typlen > 0)
	{
		/* Fixed-width type */
		char *buf = (char *) palloc(typlen);
		palloced = true;
		if (get_typbyval(argtypeid))
		{
			memcpy(buf, &value, typlen);
		}
		else
		{
			memcpy(buf, DatumGetPointer(value), typlen);
		}
		bytes = buf;
		total_len = typlen;
	}
	else
	{
		/* Fallback */
		char *str = OutputFunctionCall(get_fn_expr_argtype(fcinfo->flinfo, 0), value);
		bytes = str;
		total_len = strlen(str);
	}

	/* Calculate start and length slices */
	if (start_pos <= 0)
		start_pos = 1;

	dump_start = start_pos - 1;
	if (dump_start >= total_len)
	{
		dump_len = 0;
	}
	else
	{
		if (length < 0 || (dump_start + length) > total_len)
			dump_len = total_len - dump_start;
		else
			dump_len = length;
	}

	if (dump_len < 0)
		dump_len = 0;

	/* Build result string: Typ=<type_code> Len=<total_len> [CharacterSet=<name>]: byte1,byte2,... */
	initStringInfo(&res);
	appendStringInfo(&res, "Typ=%d Len=%d", type_code, total_len);

	if (include_charset)
	{
		appendStringInfo(&res, " CharacterSet=%s", GetDatabaseEncodingName());
	}

	appendStringInfoString(&res, ": ");

	for (i = 0; i < dump_len; i++)
	{
		if (i > 0)
			appendStringInfoChar(&res, ',');
		append_dump_byte(&res, (unsigned char) bytes[dump_start + i], fmt);
	}

	if (palloced && bytes != NULL)
		pfree((void *) bytes);

	PG_RETURN_TEXT_P(cstring_to_text(res.data));
}
