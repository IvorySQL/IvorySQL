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
#include "varatt.h"
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
PG_FUNCTION_INFO_V1(ora_sqrt_number);
PG_FUNCTION_INFO_V1(ora_exp_number);
PG_FUNCTION_INFO_V1(ora_ln_number);
PG_FUNCTION_INFO_V1(ora_log_number);
PG_FUNCTION_INFO_V1(ora_power_number);

/*
 * Significant digits that ora_number_math() computes with: 40 for the
 * largest NUMBER mantissa, plus guard digits for the final rounding.
 */
#define ORA_MATH_DIGITS 60

static int ora_to_number_hex_width(text *fmt);
static Numeric ora_to_number_hex(text *value, int width);
static bool ora_number_exponent(Numeric num, int *exponent);
static Numeric ora_number_round(Numeric num);
static Numeric ora_number_math(PGFunction func, Numeric x, Numeric y);

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
 * Set *exponent to the power of ten of the first nonzero digit of num.
 * Returns false if num is zero, NaN or infinite.
 */
static bool
ora_number_exponent(Numeric num, int *exponent)
{
	char	   *str;
	char	   *p;
	char	   *point;
	bool		nonzero = true;

	if (numeric_is_nan(num) || numeric_is_inf(num))
		return false;

	str = DatumGetCString(DirectFunctionCall1(numeric_out,
											  NumericGetDatum(num)));
	p = str;
	if (*p == '-')
		p++;
	point = strchr(p, '.');

	if (*p != '0')
		*exponent = (point ? point - p : strlen(p)) - 1;
	else
	{
		char	   *q = point ? point + 1 : p + 1;

		while (*q == '0')
			q++;
		if (*q == '\0')
			nonzero = false;
		else
			*exponent = -(q - point);
	}

	pfree(str);
	return nonzero;
}

/*
 * Round num to what an Oracle NUMBER holds, and drop trailing zeros.
 *
 * A NUMBER keeps 20 base-100 digits, starting with the one that holds the
 * first nonzero decimal digit.  So a value in [1, 100) keeps 38 decimal
 * places: 39 significant digits below 10 and 40 from 10 up.
 */
static Numeric
ora_number_round(Numeric num)
{
	int			exponent;
	Datum		result = NumericGetDatum(num);

	if (ora_number_exponent(num, &exponent))
	{
		int			exponent100;

		exponent100 = exponent >= 0 ? exponent / 2 : -((1 - exponent) / 2);
		result = DirectFunctionCall2(numeric_round, result,
									 Int32GetDatum(38 - 2 * exponent100));
	}

	return DatumGetNumeric(DirectFunctionCall1(numeric_trim_scale, result));
}

/*
 * Compute func(x) or, if y is not NULL, func(x, y), to NUMBER precision.
 *
 * numeric's sqrt, exp, ln, log and power give about 16 significant digits,
 * but never fewer decimal places than their first argument has.  So a first
 * call gives the magnitude of the result, and a second call with x scaled
 * up gives ORA_MATH_DIGITS significant digits.
 */
static Numeric
ora_number_math(PGFunction func, Numeric x, Numeric y)
{
	Datum		result;
	int			exponent;

	if (y)
		result = DirectFunctionCall2(func, NumericGetDatum(x),
									 NumericGetDatum(y));
	else
		result = DirectFunctionCall1(func, NumericGetDatum(x));

	if (ora_number_exponent(DatumGetNumeric(result), &exponent) &&
		!numeric_is_nan(x) && !numeric_is_inf(x))
	{
		int			scale = ORA_MATH_DIGITS - 1 - exponent;
		int			xscale;

		scale = Min(scale, NUMERIC_MAX_DISPLAY_SCALE);
		xscale = DatumGetInt32(DirectFunctionCall1(numeric_scale,
												   NumericGetDatum(x)));
		if (scale > xscale)
		{
			Datum		scaled = DirectFunctionCall2(numeric_round,
													 NumericGetDatum(x),
													 Int32GetDatum(scale));

			if (y)
				result = DirectFunctionCall2(func, scaled, NumericGetDatum(y));
			else
				result = DirectFunctionCall1(func, scaled);
		}
	}

	return ora_number_round(DatumGetNumeric(result));
}

/*
 * ora_sqrt_number, ora_exp_number, ora_ln_number, ora_log_number and
 * ora_power_number
 * Oracle SQRT, EXP, LN, LOG and POWER computed to NUMBER precision.
 * LOG with one argument is base 10, like PostgreSQL's.
 */
Datum
ora_sqrt_number(PG_FUNCTION_ARGS)
{
	PG_RETURN_NUMERIC(ora_number_math(numeric_sqrt,
									  PG_GETARG_NUMERIC(0), NULL));
}

Datum
ora_exp_number(PG_FUNCTION_ARGS)
{
	PG_RETURN_NUMERIC(ora_number_math(numeric_exp,
									  PG_GETARG_NUMERIC(0), NULL));
}

Datum
ora_ln_number(PG_FUNCTION_ARGS)
{
	PG_RETURN_NUMERIC(ora_number_math(numeric_ln,
									  PG_GETARG_NUMERIC(0), NULL));
}

Datum
ora_log_number(PG_FUNCTION_ARGS)
{
	if (PG_NARGS() == 1)
	{
		Numeric		ten = int64_to_numeric(10);

		PG_RETURN_NUMERIC(ora_number_math(numeric_log, ten,
										  PG_GETARG_NUMERIC(0)));
	}

	PG_RETURN_NUMERIC(ora_number_math(numeric_log, PG_GETARG_NUMERIC(0),
									  PG_GETARG_NUMERIC(1)));
}

Datum
ora_power_number(PG_FUNCTION_ARGS)
{
	PG_RETURN_NUMERIC(ora_number_math(numeric_power, PG_GETARG_NUMERIC(0),
									  PG_GETARG_NUMERIC(1)));
}
