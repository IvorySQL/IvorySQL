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
#include "lib/stringinfo.h"
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
PG_FUNCTION_INFO_V1(ora_to_char_number);

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
 * ora_to_char_number
 *
 * Oracle's default TO_CHAR(number) conversion, i.e. the "text minimum"
 * TM9 format model used when no format is given.
 *
 * The digits come from PostgreSQL's own numeric output, so they are always
 * correct; only the layout rule applied to them is Oracle's:
 *
 * 1. The value is normalized into fixed-point text: trailing fraction
 *    zeros and a dangling point are dropped, and the integer digit is
 *    omitted for values between -1 and 1 (0.50 -> '.5', 100.0 -> '100').
 *    While that text fits in 40 characters, the sign included, it is the
 *    answer: 1e39 (40 characters) stays fixed-point, while 1e40 (41)
 *    switches to scientific notation, and the sign counts toward the
 *    budget, so -1e39 switches too.  The shapes were established by
 *    probing Oracle Database 23ai Free directly, because the 64-character
 *    wording in the manual does not match what the server does.
 * 2. Past the budget the fixed and the scientific rendering compete.
 *    The scientific form rounds the value to the mantissa width that the
 *    40 characters allow and always spans exactly 40 characters (a
 *    mantissa zero-padded to the width, a signed exponent with at least
 *    two digits, and half-up rounding whose carry folds into the
 *    exponent).  The fixed form rounds the value to whatever fits the
 *    budget.  The candidate keeping more significant digits wins; when
 *    both denote the same rounded value -- compared as their significant
 *    digits plus the decimal exponent those digits spell -- the fixed
 *    form wins, so 9.99..9e-5 rounds to '.0001' either way.
 *
 * The ora_to_char_default regression suite pins the rule against Oracle
 * Database 23ai Free: the 40-character boundaries on both sides, the
 * round-half-up carries into the exponent, the mantissa zero padding and
 * the candidate comparisons.
 */
#define TM9_BUDGET 40

/* Width in decimal digits of the absolute value of exp. */
static int
tm9_exponent_width(int exp)
{
	int			width = 1;

	if (exp < 0)
		exp = -exp;
	while (exp >= 10)
	{
		exp /= 10;
		width++;
	}
	return width;
}

/*
 * Append the absolute value of exp as exponent digits, zero-padded to two
 * digits but never truncated (E-09, E+40, E+100).
 */
static void
tm9_append_exponent_digits(StringInfo s, int exp)
{
	char		buf[16];

	if (exp < 0)
		exp = -exp;
	if (tm9_exponent_width(exp) < 2)
		appendStringInfoChar(s, '0');
	snprintf(buf, sizeof(buf), "%d", exp);
	appendStringInfoString(s, buf);
}

/*
 * Print the numeric_out text the way Oracle prints a NUMBER without a
 * format model: trailing fraction zeros and a dangling point disappear,
 * and the integer digit is omitted for values between -1 and 1
 * (0.50 -> '.5', 1.50 -> '1.5', 100.0 -> '100').  A NaN passes through.
 */
static void
tm9_fixed_text(const char *numtext, StringInfo out)
{
	const char *dot = strchr(numtext, '.');
	const char *end = numtext + strlen(numtext);

	resetStringInfo(out);

	if (dot)
	{
		/* drop the trailing fraction zeros, then a dangling point */
		while (end > dot + 1 && end[-1] == '0')
			end--;
		if (end == dot + 1)
			end = dot;
		appendBinaryStringInfo(out, numtext, end - numtext);
	}
	else
		appendBinaryStringInfo(out, numtext, end - numtext);

	/* omit the integer digit of a value between -1 and 1 */
	if (out->len >= 2 && out->data[0] == '0' && out->data[1] == '.')
	{
		memmove(out->data, out->data + 1, out->len);
		out->len--;
	}
	else if (out->len >= 3 && out->data[0] == '-' && out->data[1] == '0' &&
			 out->data[2] == '.')
	{
		memmove(out->data + 1, out->data + 2, out->len - 1);
		out->len--;
	}
	out->data[out->len] = '\0';
}

/*
 * Increment a digit string the way (digits::numeric + 1)::text behaves:
 * leading zeros vanish and a carry out of the top grows the string
 * ("00999" -> "1000").  Callers that need a fixed width re-pad afterwards.
 */
static void
tm9_increment_digits(StringInfo s)
{
	int			i = 0;

	while (i < s->len && s->data[i] == '0')
		i++;
	if (i > 0)
	{
		memmove(s->data, s->data + i, s->len - i + 1);
		s->len -= i;
	}
	if (s->len == 0)
		s->data[s->len++] = '0';

	for (i = s->len - 1; i >= 0; i--)
	{
		if (s->data[i] == '9')
			s->data[i] = '0';
		else
		{
			s->data[i]++;
			break;
		}
	}

	if (i < 0)
	{
		/* carry out of the top digit */
		enlargeStringInfo(s, 1);
		memmove(s->data + 1, s->data, s->len + 1);
		s->data[0] = '1';
		s->len++;
	}
	s->data[s->len] = '\0';
}

/*
 * The fixed-point rendering: [sign]digits[0..intlen2) followed by the
 * fraction that survives once its trailing zeros are dropped.
 */
static void
tm9_render_fixed(StringInfo out, const char *digits, int dlen,
				 bool neg, int intlen2)
{
	int			end = dlen;

	resetStringInfo(out);
	if (neg)
		appendStringInfoChar(out, '-');
	appendBinaryStringInfo(out, digits, intlen2);
	while (end > intlen2 && digits[end - 1] == '0')
		end--;
	if (end > intlen2)
	{
		appendStringInfoChar(out, '.');
		appendBinaryStringInfo(out, digits + intlen2, end - intlen2);
	}
}

/*
 * The TM9 scientific rendering: one mantissa digit, a point, the rest of
 * the mantissa, then a signed exponent with at least two digits.  For the
 * inputs that reach it the result spans exactly 40 characters.
 */
static void
tm9_render_sci(StringInfo out, const char *mant, int mantlen,
			   bool neg, int e_sci)
{
	resetStringInfo(out);
	if (neg)
		appendStringInfoChar(out, '-');
	appendStringInfoChar(out, mant[0]);
	appendStringInfoChar(out, '.');
	appendBinaryStringInfo(out, mant + 1, mantlen - 1);
	appendStringInfoChar(out, 'E');
	appendStringInfoChar(out, (e_sci >= 0) ? '+' : '-');
	tm9_append_exponent_digits(out, e_sci);
}

/* Wrap a C string as the VARCHAR2 the SQL entry declares. */
static VarChar *
tm9_make_result(const char *s)
{
	return (VarChar *) cstring_to_text(s);
}

Datum
ora_to_char_number(PG_FUNCTION_ARGS)
{
	Numeric		num = PG_GETARG_NUMERIC(0);
	char	   *numtext;
	StringInfoData w;			/* the fixed text, then the sign-less digits */
	StringInfoData sig;			/* significant digits of the value */
	StringInfoData scidig;		/* digits kept by the scientific rounding */
	StringInfoData fixdig;		/* digits kept by the fixed rounding */
	StringInfoData render;		/* whichever candidate wins */
	VarChar    *result;
	const char *mant;
	bool		neg;
	bool		hasdot;
	bool		scicarry;
	bool		same;
	char		rounddigit;
	int			i;
	int			intlen;
	int			intlen2;
	int			z;
	int			evalue;
	int			explen;
	int			scisig;
	int			e_sci;
	int			el2;
	int			capfin;
	int			mantlen;
	int			sciklen;
	int			sciexp;
	int			fixcut;
	int			fixlo;
	int			fixhi;
	int			fixklen;
	int			fixedexp;

	/* PostgreSQL's own numeric output provides the digits. */
	numtext = DatumGetCString(DirectFunctionCall1(numeric_out,
												  NumericGetDatum(num)));

	initStringInfo(&w);
	tm9_fixed_text(numtext, &w);
	pfree(numtext);

	/* inside the budget the fixed-point text is the answer */
	if (w.len <= TM9_BUDGET)
	{
		result = tm9_make_result(w.data);
		pfree(w.data);
		PG_RETURN_VARCHAR_P(result);
	}

	/* drop the sign, then locate and squeeze out the point */
	neg = (w.data[0] == '-');
	if (neg)
	{
		memmove(w.data, w.data + 1, w.len);
		w.len--;
		w.data[w.len] = '\0';
	}

	intlen = 0;
	while (intlen < w.len && w.data[intlen] != '.')
		intlen++;
	hasdot = (intlen < w.len);
	if (hasdot)
	{
		memmove(w.data + intlen, w.data + intlen + 1, w.len - intlen - 1);
		w.len--;
		w.data[w.len] = '\0';
	}

	/* leading zeros of the fraction: they fix the exponent below 1 */
	z = 0;
	if (hasdot)
		while (intlen + z < w.len && w.data[intlen + z] == '0')
			z++;

	/* decimal exponent of the first significant digit */
	evalue = (intlen >= 1) ? intlen - 1 : -(z + 1);
	explen = Max(2, tm9_exponent_width(evalue));

	/* significant digits: leading and trailing zeros are not significant */
	i = 0;
	while (i < w.len && w.data[i] == '0')
		i++;
	fixhi = w.len;
	while (fixhi > i && w.data[fixhi - 1] == '0')
		fixhi--;
	initStringInfo(&sig);
	appendBinaryStringInfo(&sig, w.data + i, fixhi - i);

	/* the mantissa width the 40-character budget allows */
	scisig = 37 - (neg ? 1 : 0) - explen;

	initStringInfo(&scidig);
	rounddigit = '\0';
	if (sig.len > scisig)
	{
		appendBinaryStringInfo(&scidig, sig.data, scisig);
		rounddigit = sig.data[scisig];
	}
	else
	{
		appendBinaryStringInfo(&scidig, sig.data, sig.len);
		while (scidig.len < scisig)
			appendStringInfoChar(&scidig, '0');
	}

	/* half-up rounding at the cut; an all-nines carry grows the digits */
	if (rounddigit >= '5')
		tm9_increment_digits(&scidig);
	scicarry = (scidig.len > scisig);
	e_sci = evalue + (scicarry ? 1 : 0);

	/* a carried mantissa is re-cut to the final width */
	el2 = Max(2, tm9_exponent_width(e_sci));
	capfin = 36 - (neg ? 1 : 0) - el2;
	mantlen = scicarry ? Min(capfin + 1, scidig.len) : scidig.len;
	mant = scidig.data;

	/*
	 * fingerprint of the scientific rounding: significant digits plus the
	 * decimal exponent they spell
	 */
	sciklen = mantlen;
	while (sciklen > 0 && mant[sciklen - 1] == '0')
		sciklen--;
	sciexp = e_sci + 1 - sciklen;

	/* the digits that fit the remaining budget */
	fixcut = intlen + Max(TM9_BUDGET - (neg ? 1 : 0) - intlen - (hasdot ? 1 : 0),
						  0);

	initStringInfo(&fixdig);
	appendBinaryStringInfo(&fixdig, w.data, Min(fixcut, w.len));
	rounddigit = (fixcut < w.len) ? w.data[fixcut] : '\0';
	if (rounddigit >= '5')
	{
		tm9_increment_digits(&fixdig);
		if (fixdig.len < fixcut)
		{
			/* the increment dropped leading zeros: re-pad to the cut */
			int			pad = fixcut - fixdig.len;

			enlargeStringInfo(&fixdig, pad);
			memmove(fixdig.data + pad, fixdig.data, fixdig.len + 1);
			memset(fixdig.data, '0', pad);
			fixdig.len += pad;
		}
	}

	/* a rounding carry may push one digit into the integer part */
	intlen2 = intlen + (fixdig.len > fixcut ? 1 : 0);

	/*
	 * fingerprint of the fixed rounding, spelled the same way as the
	 * scientific one so equal rounded values compare equal across the two
	 * forms
	 */
	fixlo = 0;
	while (fixlo < fixdig.len && fixdig.data[fixlo] == '0')
		fixlo++;
	fixhi = fixdig.len;
	while (fixhi > fixlo && fixdig.data[fixhi - 1] == '0')
		fixhi--;
	fixklen = fixhi - fixlo;

	/*
	 * length(ltrim(fix_digits,'0')) is fixdig.len - fixlo, so the exponent
	 * folds to intlen2 - fixlo - fixklen
	 */
	fixedexp = intlen2 - fixlo - fixklen;

	/* do the two renderings denote the same rounded value? */
	same = (fixklen == sciklen) && (fixedexp == sciexp) &&
		(sciklen == 0 ||
		 memcmp(fixdig.data + fixlo, mant, sciklen) == 0);

	initStringInfo(&render);
	tm9_render_fixed(&render, fixdig.data, fixdig.len, neg, intlen2);

	/*
	 * The scientific candidate wins when the fixed one overflows the
	 * budget, or when it keeps strictly more significant digits; equal
	 * renderings are won by the fixed form.
	 */
	if (render.len > TM9_BUDGET || (!same && fixklen < scisig))
		tm9_render_sci(&render, mant, mantlen, neg, e_sci);

	result = tm9_make_result(render.data);
	pfree(w.data);
	pfree(sig.data);
	pfree(scidig.data);
	pfree(fixdig.data);
	pfree(render.data);
	PG_RETURN_VARCHAR_P(result);
}
