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
#include <math.h>
#include "fmgr.h"
#include "utils/builtins.h"
#include "utils/formatting.h"
#include "utils/numeric.h"

/* Functions implemented in contrib/ivorysql_ora/src/datatype/binary_float.c and contrib/ivorysql_ora/src/datatype/binary_double.c */
extern Datum binary_float_in(PG_FUNCTION_ARGS);
extern Datum binary_double_in(PG_FUNCTION_ARGS);
extern Datum number_binary_float(PG_FUNCTION_ARGS);
extern Datum number_binary_double(PG_FUNCTION_ARGS);

PG_FUNCTION_INFO_V1(number_bitand);
PG_FUNCTION_INFO_V1(ora_to_number);
PG_FUNCTION_INFO_V1(number_nanvl);
PG_FUNCTION_INFO_V1(binary_float_nanvl);
PG_FUNCTION_INFO_V1(binary_double_nanvl);
PG_FUNCTION_INFO_V1(ora_to_binary_float);
PG_FUNCTION_INFO_V1(ora_to_binary_double);
PG_FUNCTION_INFO_V1(ora_bit_and_agg_transfn);
PG_FUNCTION_INFO_V1(ora_bit_and_agg_combinefn);


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
 * number_nanvl
 * Oracle NANVL(expr1, expr2) for NUMBER: returns expr2 when expr1
 * is NaN, otherwise returns expr1. PostgreSQL's numeric type (unlike
 * Oracle's NUMBER) can hold a NaN value, so this reuses the existing
 * numeric_is_nan() rather than assuming expr1 is never NaN.
 *
 * Oracle only inspects expr1: expr2 is evaluated (and thus only
 * matters) when expr1 is NaN, so this function cannot be STRICT --
 * a NULL expr2 must not force a NULL result when expr1 is a normal
 * (non-NaN) value.
 */
Datum
number_nanvl(PG_FUNCTION_ARGS)
{
	Numeric		arg1;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	arg1 = PG_GETARG_NUMERIC(0);

	if (!numeric_is_nan(arg1))
		PG_RETURN_NUMERIC(arg1);

	if (PG_ARGISNULL(1))
		PG_RETURN_NULL();

	PG_RETURN_NUMERIC(PG_GETARG_NUMERIC(1));
}

/*
 * binary_float_nanvl
 * Oracle NANVL(expr1, expr2) for BINARY_FLOAT: returns expr2 when
 * expr1 is NaN, otherwise returns expr1. See number_nanvl() for why
 * this cannot be STRICT.
 */
Datum
binary_float_nanvl(PG_FUNCTION_ARGS)
{
	float4		arg1;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	arg1 = PG_GETARG_FLOAT4(0);

	if (!isnan(arg1))
		PG_RETURN_FLOAT4(arg1);

	if (PG_ARGISNULL(1))
		PG_RETURN_NULL();

	PG_RETURN_FLOAT4(PG_GETARG_FLOAT4(1));
}

/*
 * binary_double_nanvl
 * Oracle NANVL(expr1, expr2) for BINARY_DOUBLE: returns expr2 when
 * expr1 is NaN, otherwise returns expr1. See number_nanvl() for why
 * this cannot be STRICT.
 */
Datum
binary_double_nanvl(PG_FUNCTION_ARGS)
{
	float8		arg1;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	arg1 = PG_GETARG_FLOAT8(0);

	if (!isnan(arg1))
		PG_RETURN_FLOAT8(arg1);

	if (PG_ARGISNULL(1))
		PG_RETURN_NULL();

	PG_RETURN_FLOAT8(PG_GETARG_FLOAT8(1));
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
ora_to_binary_float_internal(text *value, text *fmt, bool *isnull)
{
	Datum		result;

	*isnull = false;

	if (fmt)
	{
		Numeric		num = ora_to_number_internal(value, fmt);

		if (num == NULL)
		{
			*isnull = true;
			return (float4) 0;
		}

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
ora_to_binary_double_internal(text *value, text *fmt, bool *isnull)
{
	Datum		result;

	*isnull = false;

	if (fmt)
	{
		Numeric		num = ora_to_number_internal(value, fmt);

		if (num == NULL)
		{
			*isnull = true;
			return (float8) 0;
		}

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
	float4		result;
	bool		isnull;

	if (PG_NARGS() > 1)
		fmt = PG_GETARG_TEXT_P(1);

	result = ora_to_binary_float_internal(value, fmt, &isnull);

	if (isnull)
		PG_RETURN_NULL();

	PG_RETURN_FLOAT4(result);
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
	float8		result;
	bool		isnull;

	if (PG_NARGS() > 1)
		fmt = PG_GETARG_TEXT_P(1);

	result = ora_to_binary_double_internal(value, fmt, &isnull);

	if (isnull)
		PG_RETURN_NULL();

	PG_RETURN_FLOAT8(result);
}

/*
 * ora_bit_and_agg_transfn
 * Transition function for the Oracle-compatible BIT_AND_AGG aggregate.
 *
 * The aggregate is declared STRICT with an int8 transition state and no
 * INITCOND, so the executor seeds the state with the first non-null input
 * and skips NULL inputs without calling this function; NULL inputs are
 * ignored and a group with no non-null input aggregates to NULL, matching
 * Oracle.
 *
 * Oracle truncates fractional input values toward zero before aggregating,
 * so 4.64 and 4.4 both contribute 4; numeric_trunc() implements exactly
 * that.  Values that do not fit in bigint raise an error, while Oracle
 * aggregates the wider 128-bit range; the int64 state keeps the aggregate
 * trivially parallel-safe.
 */
Datum
ora_bit_and_agg_transfn(PG_FUNCTION_ARGS)
{
	int64		state = PG_GETARG_INT64(0);
	Numeric		arg = PG_GETARG_NUMERIC(1);
	Datum		truncated;
	int64		input;

	truncated = DirectFunctionCall2(numeric_trunc,
									NumericGetDatum(arg),
									Int32GetDatum(0));
	input = DatumGetInt64(DirectFunctionCall1(numeric_int8, truncated));

	PG_RETURN_INT64(state & input);
}

/*
 * ora_bit_and_agg_combinefn
 * Combine function for partial states of the BIT_AND_AGG aggregate.
 *
 * STRICT makes a NULL partial state (a worker that saw no non-null rows)
 * drop out and the surviving side pass through unchanged.
 */
Datum
ora_bit_and_agg_combinefn(PG_FUNCTION_ARGS)
{
	int64		state1 = PG_GETARG_INT64(0);
	int64		state2 = PG_GETARG_INT64(1);

	PG_RETURN_INT64(state1 & state2);
}
