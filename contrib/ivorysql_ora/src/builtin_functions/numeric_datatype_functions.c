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
#include "utils/builtins.h"
#include "utils/formatting.h"
#include "utils/numeric.h"

/* Functions implemented in src/datatype/binary_float.c and binary_double.c */
extern Datum binary_float_in(PG_FUNCTION_ARGS);
extern Datum binary_double_in(PG_FUNCTION_ARGS);
extern Datum number_binary_float(PG_FUNCTION_ARGS);
extern Datum number_binary_double(PG_FUNCTION_ARGS);

PG_FUNCTION_INFO_V1(number_bitand);
PG_FUNCTION_INFO_V1(ora_to_number);
PG_FUNCTION_INFO_V1(ora_to_binary_float);
PG_FUNCTION_INFO_V1(ora_to_binary_double);


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
	Numeric	result;
	int num = PG_NARGS();

	if(num > 1)
		fmt = PG_GETARG_TEXT_P(1);

	result = ora_to_number_internal(value, fmt);

	if(result == NULL)
		PG_RETURN_NULL();
	else
		PG_RETURN_NUMERIC(result);
}

/*
 * ora_to_binary_float_internal
 * Convert a character string, with an optional number format model, to a
 * single-precision floating-point value in the same manner as Oracle's
 * TO_BINARY_FLOAT function.
 *
 * When a format model is supplied, the string is first converted to a
 * NUMBER value using the same number format model logic as TO_NUMBER,
 * and then that value is converted to BINARY_FLOAT.  Otherwise the string
 * is parsed directly as a floating-point literal, which also accepts the
 * Oracle special values 'NaN', 'Infinity' (or 'INF') and their negations.
 */
static float4
ora_to_binary_float_internal(text *value, text *fmt)
{
	Datum		result;

	if (fmt)
	{
		Numeric		num = ora_to_number_internal(value, fmt);

		result = DirectFunctionCall1(number_binary_float,
									 NumericGetDatum(num));
	}
	else
	{
		char	   *numstr = text_to_cstring(value);

		result = DirectFunctionCall1(binary_float_in,
									 CStringGetDatum(numstr));
		pfree(numstr);
	}

	return DatumGetFloat4(result);
}

/*
 * ora_to_binary_double_internal
 * Convert a character string, with an optional number format model, to a
 * double-precision floating-point value in the same manner as Oracle's
 * TO_BINARY_DOUBLE function.
 *
 * This is the double-precision counterpart of
 * ora_to_binary_float_internal().
 */
static float8
ora_to_binary_double_internal(text *value, text *fmt)
{
	Datum		result;

	if (fmt)
	{
		Numeric		num = ora_to_number_internal(value, fmt);

		result = DirectFunctionCall1(number_binary_double,
									 NumericGetDatum(num));
	}
	else
	{
		char	   *numstr = text_to_cstring(value);

		result = DirectFunctionCall1(binary_double_in,
									 CStringGetDatum(numstr));
		pfree(numstr);
	}

	return DatumGetFloat8(result);
}

/*
 * ora_to_binary_float
 * Oracle compatible TO_BINARY_FLOAT function.
 *
 * Converts a character string to a value of BINARY_FLOAT data type.
 * The optional second argument is a number format model that describes
 * how the character string should be interpreted.
 */
Datum
ora_to_binary_float(PG_FUNCTION_ARGS)
{
	text	   *value = PG_GETARG_TEXT_P(0);
	text	   *fmt = NULL;

	if (PG_NARGS() > 1)
		fmt = PG_GETARG_TEXT_P(1);

	PG_RETURN_FLOAT4(ora_to_binary_float_internal(value, fmt));
}

/*
 * ora_to_binary_double
 * Oracle compatible TO_BINARY_DOUBLE function.
 *
 * Converts a character string to a value of BINARY_DOUBLE data type.
 * The optional second argument is a number format model that describes
 * how the character string should be interpreted.
 */
Datum
ora_to_binary_double(PG_FUNCTION_ARGS)
{
	text	   *value = PG_GETARG_TEXT_P(0);
	text	   *fmt = NULL;

	if (PG_NARGS() > 1)
		fmt = PG_GETARG_TEXT_P(1);

	PG_RETURN_FLOAT8(ora_to_binary_double_internal(value, fmt));
}
