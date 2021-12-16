/*-------------------------------------------------------------------------
 *
 * number.c
 *	  An exact number data type for the Oracle database system
 *
 * IDENTIFICATION
 *	  contrib/orafce/number.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "utils/numeric.h"
#include "utils/fmgrprotos.h"
#include "parser/parse_type.h"

PG_FUNCTION_INFO_V1(number_out);
PG_FUNCTION_INFO_V1(number);
PG_FUNCTION_INFO_V1(numbertypmodin);

static int32
getnumbertypmodin(int32 *tl)
{
	int	typmod;
	if (tl[0] < 1 || tl[0] > NUMERIC_MAX_PRECISION)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("NUMBER precision %d must be between 1 and %d",
						tl[0], NUMERIC_MAX_PRECISION)));
	if (tl[1] < 0)
	{
		if (-tl[1] <= 0x7FFF)
			typmod = ((tl[0] << 16) | (1 << 15) | (-tl[1])) + VARHDRSZ;
		else
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("NUMBER scale %d must be between 0 and precision %d",
							tl[1], tl[0])));
	}
	else
		typmod = ((tl[0] << 16) | tl[1]) + VARHDRSZ;
	return typmod;
}

/*
 * number_out() -
 *
 *	Output function for number data type
 */
Datum
number_out(PG_FUNCTION_ARGS)
{
	Datum		result;

	TypenameTypeModIn_hook = getnumbertypmodin;
	result = numeric_out(fcinfo);
	TypenameTypeModIn_hook = NULL;

	return result;
}

Datum
numbertypmodin(PG_FUNCTION_ARGS)
{
	Datum		result;

	TypenameTypeModIn_hook = getnumbertypmodin;
	result = numerictypmodin(fcinfo);
	TypenameTypeModIn_hook = NULL;

	return result;
}


Datum
number(PG_FUNCTION_ARGS)
{
	Datum		result;

	TypenameTypeModIn_hook = getnumbertypmodin;
	result = numeric(fcinfo);
	TypenameTypeModIn_hook = NULL;

	return result;
}

