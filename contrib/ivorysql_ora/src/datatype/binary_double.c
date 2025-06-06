/*-------------------------------------------------------------------------
 *
 * binary_double.c
 *
 * Compatible with Oracle's binary_double data type.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/binary_double.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <ctype.h>
#include <float.h>
#include <math.h>
#include <limits.h>

#include "catalog/pg_type.h"
#include "common/int.h"
#include "common/shortest_dec.h"
#include "libpq/pqformat.h"
#include "miscadmin.h"
#include "utils/array.h"
#include "utils/float.h"
#include "utils/fmgrprotos.h"
#include "utils/sortsupport.h"
#include "utils/timestamp.h"
#include "utils/numeric.h"
#include "utils/guc.h"
#include "utils/ora_compatible.h"


PG_FUNCTION_INFO_V1(binary_double_in);
PG_FUNCTION_INFO_V1(binary_double_out);
PG_FUNCTION_INFO_V1(binary_double_send);
PG_FUNCTION_INFO_V1(binary_double_recv);


static double binary_double_in_internal_opt_error(char *num, char **endptr_p, const char *type_name, 
												const char *orig_string, bool *have_error);
static double binary_double_in_internal(char *num, char **endptr_p, const char *type_name, const char *orig_string);
static char * binary_double_out_internal(double num);



/* ========== USER I/O ROUTINES ========== */

/*
 *		binary_double_in		- converts "num" to binary_double
 */
Datum
binary_double_in(PG_FUNCTION_ARGS)
{
	char	   *num = PG_GETARG_CSTRING(0);

	PG_RETURN_FLOAT8(binary_double_in_internal(num, NULL, "binary_double", num));
}

/* Convenience macro: set *have_error flag (if provided) or throw error */
#define RETURN_ERROR(throw_error, have_error) \
do { \
	if (have_error) { \
		*have_error = true; \
		return 0.0; \
	} else { \
		throw_error; \
	} \
} while (0)

/*
 * binary_double_in_internal_opt_error - guts of binary_double_in()
 *
 * This is exposed for use by functions that want a reasonably
 * platform-independent way of inputting doubles.  The behavior is
 * essentially like strtod + ereport on error, but note the following
 * differences:
 * 1. Both leading and trailing whitespace are skipped.
 * 2. If endptr_p is NULL, we throw error if there's trailing junk.
 * Otherwise, it's up to the caller to complain about trailing junk.
 * 3. In event of a syntax error, the report mentions the given type_name
 * and prints orig_string as the input; this is meant to support use of
 * this function with types such as "box" and "point", where what we are
 * parsing here is just a substring of orig_string.
 *
 * "num" could validly be declared "const char *", but that results in an
 * unreasonable amount of extra casting both here and in callers, so we don't.
 *
 * When "*have_error" flag is provided, it's set instead of throwing an
 * error.  This is helpful when caller need to handle errors by itself.
 */
static double
binary_double_in_internal_opt_error(char *num, char **endptr_p,
									const char *type_name, const char *orig_string,
									bool *have_error)
{
	double		val;
	char	   *endptr;
	bool		isliteral = false;

	if (have_error)
		*have_error = false;

	/* skip leading whitespace */
	while (*num != '\0' && isspace((unsigned char) *num))
		num++;

	/*
	 * Check for an empty-string input to begin with, to avoid the vagaries of
	 * strtod() on different platforms.
	 */
	if (*num == '\0')
		RETURN_ERROR(ereport(ERROR,
							 (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
							  errmsg("invalid input syntax for type %s: \"%s\"",
									 type_name, orig_string))),
					 have_error);

	if (pg_strncasecmp(num, "BD", 2) == 0)
	{
		num += 2;
		isliteral = true;
	}

	errno = 0;
	val = strtod(num, &endptr);

	/* did we not see anything that looks like a double? */
	if (endptr == num || errno != 0)
	{
		int			save_errno = errno;

		/*
		 * C99 requires that strtod() accept NaN, [+-]Infinity, and [+-]Inf,
		 * but not all platforms support all of these (and some accept them
		 * but set ERANGE anyway...)  Therefore, we check for these inputs
		 * ourselves if strtod() fails.
		 *
		 * Note: C99 also requires hexadecimal input as well as some extended
		 * forms of NaN, but we consider these forms unportable and don't try
		 * to support them.  You can use 'em if your strtod() takes 'em.
		 */
		if (pg_strncasecmp(num, "NaN", 3) == 0)
		{
			val = get_float8_nan();
			endptr = num + 3;
		}
		else if (pg_strncasecmp(num, "Infinity", 8) == 0)
		{
			val = get_float8_infinity();
			endptr = num + 8;
		}
		else if (pg_strncasecmp(num, "+Infinity", 9) == 0)
		{
			val = get_float8_infinity();
			endptr = num + 9;
		}
		else if (pg_strncasecmp(num, "-Infinity", 9) == 0)
		{
			val = -get_float8_infinity();
			endptr = num + 9;
		}
		else if (pg_strncasecmp(num, "inf", 3) == 0)
		{
			val = get_float8_infinity();
			endptr = num + 3;
		}
		else if (pg_strncasecmp(num, "+inf", 4) == 0)
		{
			val = get_float8_infinity();
			endptr = num + 4;
		}
		else if (pg_strncasecmp(num, "-inf", 4) == 0)
		{
			val = -get_float8_infinity();
			endptr = num + 4;
		}
		else if (save_errno == ERANGE)
		{
			if (ORA_PARSER == compatible_db && !isliteral)
			{
				if (val >= HUGE_VAL)
					return get_float8_infinity();
				else if (val <= -HUGE_VAL)
					return -get_float8_infinity();
				else if (val == 0.0)
					return 0;
			}

			/*
			 * Some platforms return ERANGE for denormalized numbers (those
			 * that are not zero, but are too close to zero to have full
			 * precision).  We'd prefer not to throw error for that, so try to
			 * detect whether it's a "real" out-of-range condition by checking
			 * to see if the result is zero or huge.
			 *
			 * On error, we intentionally complain about double precision not
			 * the given type name, and we print only the part of the string
			 * that is the current number.
			 */
			if (val == 0.0 || val >= HUGE_VAL || val <= -HUGE_VAL)
			{
				char	   *errnumber = pstrdup(num);

				errnumber[endptr - num] = '\0';
				RETURN_ERROR(ereport(ERROR,
									 (errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
									  errmsg("\"%s\" is out of range for type binary_double",
											 errnumber))),
							 have_error);
			}
		}
		else
			RETURN_ERROR(ereport(ERROR,
								 (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
								  errmsg("invalid input syntax for type "
										 "%s: \"%s\"",
										 type_name, orig_string))),
						 have_error);
	}

	/* skip trailing whitespace */
	while (*endptr != '\0' && isspace((unsigned char) *endptr))
		endptr++;

	/* report stopping point if wanted, else complain if not end of string */
	if (endptr_p)
		*endptr_p = endptr;
	else if (*endptr != '\0')
		RETURN_ERROR(ereport(ERROR,
							 (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
							  errmsg("invalid input syntax for type "
									 "%s: \"%s\"",
									 type_name, orig_string))),
					 have_error);

	return val;
}

/*
 * Interface to binary_double_in_internal_opt_error() without "have_error" argument.
 */
static double
binary_double_in_internal(char *num, char **endptr_p, const char *type_name, const char *orig_string)
{
	return binary_double_in_internal_opt_error(num, endptr_p, type_name, orig_string, NULL);
}


/*
 * binary_double_out - converts binary_double number to a string using a standard output format
 */
Datum
binary_double_out(PG_FUNCTION_ARGS)
{
	float8		num = PG_GETARG_FLOAT8(0);

	PG_RETURN_CSTRING(binary_double_out_internal(num));
}

/*
 * binary_double_out_internal - guts of binary_double_out()
 *
 * This is exposed for use by functions that want a reasonably
 * platform-independent way of outputting doubles.
 * The result is always palloc'd.
 */
static char *
binary_double_out_internal(double num)
{
	char	   *ascii = (char *) palloc(32);
	int			ndig = DBL_DIG + extra_float_digits;

	if (extra_float_digits > 0)
	{
		if (ORA_PARSER == compatible_db)
			binary_double_to_shortest_decimal_buf(num, ascii);
		else
			double_to_shortest_decimal_buf(num, ascii);
		return ascii;
	}

	if (ORA_PARSER == compatible_db)
		(void) ivy_strfromd(ascii, 32, ndig, num);
	else
		(void) pg_strfromd(ascii, 32, ndig, num);
	return ascii;
}

/*
 * binary_double_recv - converts external binary format to binary_double
 */
Datum
binary_double_recv(PG_FUNCTION_ARGS)
{
	StringInfo	buf = (StringInfo) PG_GETARG_POINTER(0);

	PG_RETURN_FLOAT8(pq_getmsgfloat8(buf));
}

/*
 * binary_double_send - converts binary_double to binary format
 */
Datum
binary_double_send(PG_FUNCTION_ARGS)
{
	float8		num = PG_GETARG_FLOAT8(0);
	StringInfoData buf;

	pq_begintypsend(&buf);
	pq_sendfloat8(&buf, num);
	PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}

