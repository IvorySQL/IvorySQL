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
 * numeric_datatype_functions.c
 *
 * This file contains the implementation of Oracle's
 * numeric data type related built-in functions.
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_functions/numeric_datatype_functions.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "varatt.h"
#include "utils/builtins.h"
#include "utils/formatting.h"
#include "utils/numeric.h"

PG_FUNCTION_INFO_V1(number_bitand);
PG_FUNCTION_INFO_V1(ora_to_number);

static int ora_to_number_hex_width(text *fmt);
static Numeric ora_to_number_hex(text *value, int width);

/*
 * Recognize the hexadecimal number format separately from the shared decimal
 * formatter, which has no X token.  Other format models retain their existing
 * parsing, including quoted literals containing X.
 */
static int
ora_to_number_hex_width(text *fmt)
{
	const char *p = VARDATA_ANY(fmt);
	const char *end = p + VARSIZE_ANY_EXHDR(fmt);
	const char *first_x;
	int			width = 0;

	if (end - p >= 2 && pg_strncasecmp(p, "FM", 2) == 0)
		p += 2;
	if (p < end && *p == '0')
	{
		width++;
		p++;
	}
	first_x = p;
	while (p < end && (*p == 'X' || *p == 'x'))
	{
		width++;
		p++;
	}

	if (p != end || p == first_x)
		return 0;
	return width;
}

static Numeric
ora_to_number_hex(text *value, int width)
{
	const char *start = VARDATA_ANY(value);
	const char *end = start + VARSIZE_ANY_EXHDR(value);
	int			len;
	int			i;
	char	   *hexstr;
	Numeric		result;

	/* Ignore surrounding blanks, including padding from CHAR inputs. */
	while (start < end && *start == ' ')
		start++;
	while (end > start && end[-1] == ' ')
		end--;
	len = end - start;

	if (len == 0 || len > width)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
				 errmsg("invalid number")));

	/* Reject signs, prefixes, separators, and non-ASCII hexadecimal digits. */
	for (i = 0; i < len; i++)
	{
		unsigned char c = start[i];

		if (!((c >= '0' && c <= '9') ||
			  (c >= 'A' && c <= 'F') ||
			  (c >= 'a' && c <= 'f')))
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
					 errmsg("invalid number")));
	}

	/* numeric_in handles base-16 integers without int64 or float overflow. */
	hexstr = palloc(len + 3);
	hexstr[0] = '0';
	hexstr[1] = 'x';
	memcpy(hexstr + 2, start, len);
	hexstr[len + 2] = '\0';
	result = DatumGetNumeric(DirectFunctionCall3(numeric_in,
											   CStringGetDatum(hexstr),
											   ObjectIdGetDatum(InvalidOid),
											   Int32GetDatum(-1)));
	pfree(hexstr);

	return result;
}


Datum
number_bitand(PG_FUNCTION_ARGS)
{
	Numeric		arg1 = PG_GETARG_NUMERIC(0);
	Numeric		arg2 = PG_GETARG_NUMERIC(1);

	PG_RETURN_NUMERIC(numeric_bitand(arg1, arg2));
}

/*
 * ora_to_number
 * converts text to a value of NUMBER data type.
 */
Datum
ora_to_number(PG_FUNCTION_ARGS)
{
	text	   *value = PG_GETARG_TEXT_P(0);
	text	   *fmt = NULL;
	Numeric		result;
	int			num = PG_NARGS();
	int			hex_width = 0;

	if (num > 1)
	{
		fmt = PG_GETARG_TEXT_P(1);
		hex_width = ora_to_number_hex_width(fmt);
	}

	if (hex_width > 0)
		result = ora_to_number_hex(value, hex_width);
	else
		result = ora_to_number_internal(value, fmt);

	if (result == NULL)
		PG_RETURN_NULL();
	else
		PG_RETURN_NUMERIC(result);
}
