/*-------------------------------------------------------------------------
 *
 * oratimestamp.c
 *
 * Compatible with Oracle's TIMESTAMP data type.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/oratimestamp.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include <ctype.h>
#include <math.h>
#include <float.h>
#include "fmgr.h"
#include <limits.h>
#include <sys/time.h>
#include "access/hash.h"
#include "access/xact.h"
#include "catalog/pg_type.h"
#include "funcapi.h"
#include "libpq/pqformat.h"
#include "miscadmin.h"
#include "pgtime.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "parser/scansup.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/datetime.h"
#include "utils/formatting.h"
#include "utils/guc.h"
#include "utils/timestamp.h"
#include "utils/numeric.h"

#include "../include/common_datatypes.h"

/* Judge leap year */
const int	day_tab[2][13] =
{
	{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 0},
	{31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 0}
};

PG_FUNCTION_INFO_V1(oratimestamp_in);
PG_FUNCTION_INFO_V1(oratimestamp_out);
PG_FUNCTION_INFO_V1(oratimestamp_recv);
PG_FUNCTION_INFO_V1(oratimestamp_send);
PG_FUNCTION_INFO_V1(oratimestamptypmodin);
PG_FUNCTION_INFO_V1(oratimestamptypmodout);
PG_FUNCTION_INFO_V1(oratimestamp_eq);
PG_FUNCTION_INFO_V1(oratimestamp_ne);
PG_FUNCTION_INFO_V1(oratimestamp_lt);
PG_FUNCTION_INFO_V1(oratimestamp_gt);
PG_FUNCTION_INFO_V1(oratimestamp_le);
PG_FUNCTION_INFO_V1(oratimestamp_ge);
PG_FUNCTION_INFO_V1(oratimestamp_cmp);
PG_FUNCTION_INFO_V1(oratimestamp_cmp_oradate);
PG_FUNCTION_INFO_V1(oratimestamp_cmp_oratimestamptz);
PG_FUNCTION_INFO_V1(oratimestamp_cmp_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamp_hash);
PG_FUNCTION_INFO_V1(oratimestamp_hash_extended);
PG_FUNCTION_INFO_V1(oratimestamp_smaller);
PG_FUNCTION_INFO_V1(oratimestamp_larger);
PG_FUNCTION_INFO_V1(oratimestamp);

PG_FUNCTION_INFO_V1(oratimestamp_eq_oradate);
PG_FUNCTION_INFO_V1(oratimestamp_ne_oradate);
PG_FUNCTION_INFO_V1(oratimestamp_lt_oradate);
PG_FUNCTION_INFO_V1(oratimestamp_gt_oradate);
PG_FUNCTION_INFO_V1(oratimestamp_le_oradate);
PG_FUNCTION_INFO_V1(oratimestamp_ge_oradate);

PG_FUNCTION_INFO_V1(oratimestamp_eq_oratimestamptz);
PG_FUNCTION_INFO_V1(oratimestamp_ne_oratimestamptz);
PG_FUNCTION_INFO_V1(oratimestamp_lt_oratimestamptz);
PG_FUNCTION_INFO_V1(oratimestamp_gt_oratimestamptz);
PG_FUNCTION_INFO_V1(oratimestamp_le_oratimestamptz);
PG_FUNCTION_INFO_V1(oratimestamp_ge_oratimestamptz);

PG_FUNCTION_INFO_V1(oratimestamp_eq_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamp_ne_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamp_lt_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamp_gt_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamp_le_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamp_ge_oratimestampltz);

PG_FUNCTION_INFO_V1(oratimestamp_oradate);
PG_FUNCTION_INFO_V1(oratimestamp_oratimestamptz);
PG_FUNCTION_INFO_V1(oratimestamp_oratimestampltz);

PG_FUNCTION_INFO_V1(oratimestamp_mi);
PG_FUNCTION_INFO_V1(oradate_mi);
PG_FUNCTION_INFO_V1(oradate_mi_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestampltz_mi_oradate);
PG_FUNCTION_INFO_V1(oradate_pl_interval);
PG_FUNCTION_INFO_V1(oradate_mi_interval);
PG_FUNCTION_INFO_V1(oratimestamp_pl_interval);
PG_FUNCTION_INFO_V1(oratimestamp_mi_interval);
PG_FUNCTION_INFO_V1(oratimestamptz_pl_interval);
PG_FUNCTION_INFO_V1(oratimestamptz_mi_interval);
PG_FUNCTION_INFO_V1(interval_pl_oradate);
PG_FUNCTION_INFO_V1(interval_pl_oratimestamp);
PG_FUNCTION_INFO_V1(interval_pl_oratimestamptz);
PG_FUNCTION_INFO_V1(oradate_pl_number);
PG_FUNCTION_INFO_V1(number_pl_oradate);
PG_FUNCTION_INFO_V1(oradate_mi_number);
PG_FUNCTION_INFO_V1(oratimestamp_pl_number);
PG_FUNCTION_INFO_V1(number_pl_oratimestamp);
PG_FUNCTION_INFO_V1(oratimestamp_mi_number);
PG_FUNCTION_INFO_V1(oratimestamptz_mi_number);
PG_FUNCTION_INFO_V1(oratimestamptz_pl_number);
PG_FUNCTION_INFO_V1(number_pl_oratimestamptz);


void
OraAdjustTimestampForTypmod(Timestamp *time, int32 typmod)
{
	static const int64 TimestampScales[MAX_TIMESTAMP_PRECISION + 1] = {
		INT64CONST(1000000),
		INT64CONST(100000),
		INT64CONST(10000),
		INT64CONST(1000),
		INT64CONST(100),
		INT64CONST(10),
		INT64CONST(1)
	};

	static const int64 TimestampOffsets[MAX_TIMESTAMP_PRECISION + 1] = {
		INT64CONST(500000),
		INT64CONST(50000),
		INT64CONST(5000),
		INT64CONST(500),
		INT64CONST(50),
		INT64CONST(5),
		INT64CONST(0)
	};

	if (typmod > MAX_TIMESTAMP_PRECISION)
		typmod = MAX_TIMESTAMP_PRECISION;

	if (!TIMESTAMP_NOT_FINITE(*time)
		&& (typmod != -1) && (typmod != MAX_TIMESTAMP_PRECISION))
	{
		if (typmod < 0 || typmod > MAX_TIMESTAMP_PRECISION)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				  errmsg("timestamp(%d) precision must be between %d and %d",
						 typmod, 0, MAX_TIMESTAMP_PRECISION)));

		/*
		 * Note: this round-to-nearest code is not completely consistent about
		 * rounding values that are exactly halfway between integral values.
		 * On most platforms, rint() will implement round-to-nearest-even, but
		 * the integer code always rounds up (away from zero).  Is it worth
		 * trying to be consistent?
		 */
		if (*time >= INT64CONST(0))
		{
			*time = ((*time + TimestampOffsets[typmod]) / TimestampScales[typmod]) *
				TimestampScales[typmod];
		}
		else
		{
			*time = -((((-*time) + TimestampOffsets[typmod]) / TimestampScales[typmod])
					  * TimestampScales[typmod]);
		}
	}
}

/* common code for timestamptypmodin and timestamptztypmodin */
static int32
anytimestamp_typmodin(bool istz, ArrayType *ta)
{
	int32		typmod;
	int32	   *tl;
	int			n;

	tl = ArrayGetIntegerTypmods(ta, &n);

	/*
	 * we're not too tense about good error message here because grammar
	 * shouldn't allow wrong number of modifiers for TIMESTAMP
	 */
	if (n != 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("invalid type modifier")));

	if (*tl < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("TIMESTAMP(%d)%s precision must not be negative",
						*tl, (istz ? " WITH TIME ZONE" : ""))));
	if (*tl > MAX_TIMESTAMP_PRECISION && *tl <= ORACLE_MAX_TIMESTAMP_PRECISION)
	{
		ereport(WARNING,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
		   errmsg("TIMESTAMP(%d)%s effective number of fractional seconds is 6,the part of excess is 0",
				  *tl, (istz ? " WITH TIME ZONE" : ""))));
		typmod = *tl;
	}
	else if (*tl > ORACLE_MAX_TIMESTAMP_PRECISION)
	{
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
		   errmsg("the precision of datetime out of rang")));	
	}
	else
		typmod = *tl;

	return typmod;
}


/* common code for timestamptypmodout and timestamptztypmodout */
static char *
anytimestamp_typmodout(bool istz, int32 typmod)
{
	const char *tz = istz ? " with time zone" : "";

	if (typmod >= 0)
		return psprintf("(%d)%s", (int) typmod, tz);
	else
		return psprintf("%s", tz);
}

static TimestampTz
timestamp2timestamptz(Timestamp timestamp)
{
	TimestampTz result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;
	int			tz;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		tz = DetermineTimeZoneOffset(tm, session_timezone);

		if (tm2timestamp(tm, fsec, &tz, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
	}

	return result;
}

/*****************************************************************************
 *	 USER I/O ROUTINES														 *
 *****************************************************************************/

/* oratimestamp_in()
 * Convert a string to internal form.
 */
Datum
oratimestamp_in(PG_FUNCTION_ARGS)
{
	char	   *str = PG_GETARG_CSTRING(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		typmod = PG_GETARG_INT32(2);
	Oid		collid = PG_GET_COLLATION();
	Timestamp	result;
	struct pg_tm tm;
	fsec_t		fsec;

	if (strcmp(nls_timestamp_format, "pg") == 0 || DATETIME_IGNORE_NLS(datetime_ignore_nls_mask, ORATIMESTAMP_MASK))
	{
		return DirectFunctionCall3(timestamp_in,
									CStringGetDatum(str),
									ObjectIdGetDatum(InvalidOid),
									Int32GetDatum(typmod));
	}
	else
	{
		ora_do_to_timestamp(cstring_to_text(str), cstring_to_text(nls_timestamp_format), collid, false, &tm, &fsec, NULL, NULL, NULL, false);

		/* cancel timezone */
		if (tm2timestamp(&tm, fsec, NULL, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		OraAdjustTimestampForTypmod(&result, typmod);

		PG_RETURN_TIMESTAMP(result);
	}
}

/* oratimestamp_out()
 * Convert a oradate to external form.
 */
Datum
oratimestamp_out(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);

	if (strcmp(nls_timestamp_format, "pg") != 0)
	{
		char	   *result;
		text	   *date_str;

		date_str = DatumGetTextP(DirectFunctionCall2(timestamp_to_char,
								  TimestampGetDatum(timestamp),
								  PointerGetDatum(cstring_to_text(nls_timestamp_format))));

		result = text_to_cstring(date_str);
		PG_RETURN_CSTRING(result);
	}
	else
		return DirectFunctionCall1(timestamp_out, TimestampTzGetDatum(timestamp));
}



/*
 * oratimestamp_recv - converts external binary format to timestamp
 *
 * We make no attempt to provide compatibility between int and float
 * timestamp representations ...
 */
Datum
oratimestamp_recv(PG_FUNCTION_ARGS)
{
	StringInfo	buf = (StringInfo) PG_GETARG_POINTER(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		typmod = PG_GETARG_INT32(2);
	Timestamp	timestamp;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;

	timestamp = (Timestamp) pq_getmsgint64(buf);

	/* rangecheck: see if timestamp_out would like it */
	if (TIMESTAMP_NOT_FINITE(timestamp))
		 /* ok */ ;
	else if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	OraAdjustTimestampForTypmod(&timestamp, typmod);

	PG_RETURN_TIMESTAMP(timestamp);
}

/*
 *	oratimestamp_send - converts timestamp to binary format
 */
Datum
oratimestamp_send(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	StringInfoData buf;

	pq_begintypsend(&buf);
	pq_sendint64(&buf, timestamp);
	PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}

Datum
oratimestamptypmodin(PG_FUNCTION_ARGS)
{
	ArrayType  *ta = PG_GETARG_ARRAYTYPE_P(0);

	PG_RETURN_INT32(anytimestamp_typmodin(false, ta));
}

Datum
oratimestamptypmodout(PG_FUNCTION_ARGS)
{
	int32		typmod = PG_GETARG_INT32(0);

	PG_RETURN_CSTRING(anytimestamp_typmodout(false, typmod));
}

/*****************************************************************************
 *	 Operator Function														 *
 *****************************************************************************/
Datum
oratimestamp_eq(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}

Datum
oratimestamp_ne(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oratimestamp_lt(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oratimestamp_gt(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oratimestamp_le(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oratimestamp_ge(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) >= 0);
}

/*
 * Crosstype comparison functions for oratimestamp vs oradate
 */
Datum
oratimestamp_eq_oradate(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}

Datum
oratimestamp_ne_oradate(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oratimestamp_lt_oradate(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oratimestamp_gt_oradate(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oratimestamp_le_oradate(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oratimestamp_ge_oradate(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) >= 0);
}

/*
 * Crosstype comparison functions for oratimestamp vs oratimestamptz
 */
Datum
oratimestamp_eq_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}

Datum
oratimestamp_ne_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oratimestamp_lt_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oratimestamp_gt_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oratimestamp_le_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oratimestamp_ge_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) >= 0);
}

/*
 * Crosstype comparison functions for oratimestamp vs oratimestampltz
 */
Datum
oratimestamp_eq_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}

Datum
oratimestamp_ne_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oratimestamp_lt_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oratimestamp_gt_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oratimestamp_le_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oratimestamp_ge_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) >= 0);
}

/*****************************************************************************
 *	 B-tree index support procedure
 *****************************************************************************/
Datum
oratimestamp_cmp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

Datum
oratimestamp_cmp_oradate(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

Datum
oratimestamp_cmp_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

Datum
oratimestamp_cmp_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

/*****************************************************************************
 *	 Hash index support procedure 
 *****************************************************************************/
Datum
oratimestamp_hash(PG_FUNCTION_ARGS)
{
	return hashint8(fcinfo);
}

Datum
oratimestamp_hash_extended(PG_FUNCTION_ARGS)
{
	return hashint8extended(fcinfo);
}

/*****************************************************************************
 *	 Aggregate Function
 *****************************************************************************/
Datum
oratimestamp_larger(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);
	Timestamp	result;

	if (timestamp_cmp_internal(dt1, dt2) > 0)
		result = dt1;
	else
		result = dt2;
	PG_RETURN_TIMESTAMP(result);
}

Datum
oratimestamp_smaller(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);
	Timestamp	result;

	/* use timestamp_cmp_internal to be sure this agrees with comparisons */
	if (timestamp_cmp_internal(dt1, dt2) < 0)
		result = dt1;
	else
		result = dt2;
	PG_RETURN_TIMESTAMP(result);
}

/*****************************************************************************
 *	 Converts a timestamp(n) type to the specified typmod size
 *****************************************************************************/
Datum
oratimestamp(PG_FUNCTION_ARGS)
{
	Timestamp	source = PG_GETARG_TIMESTAMP(0);
	int32		typmod = PG_GETARG_INT32(1);

	/* No work if typmod is invalid */
	if (typmod == -1)
		PG_RETURN_TIMESTAMP(source);
		
	OraAdjustTimestampForTypmod(&source, typmod);
	PG_RETURN_TIMESTAMP(source);
}

/*****************************************************************************
 *	 Cast Function															 *
 *****************************************************************************/
/* oratimestamp_oradate()
 * Convert oratimestamp to oradate
 */
Datum
oratimestamp_oradate(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	Timestamp	result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		if (tm2timestamp(tm, 0, NULL, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
	}

	PG_RETURN_TIMESTAMP(result);
}



/* oratimestamp_oratimestamptz()
 * Convert oratimestamp to oratimestamptz
 */
Datum
oratimestamp_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);

	PG_RETURN_TIMESTAMPTZ(timestamp2timestamptz(timestamp));
}

/* oratimestamp_oratimestampltz()
 * Convert oratimestamp to oratimestampltz
 */
Datum
oratimestamp_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);

	PG_RETURN_TIMESTAMPTZ(timestamp2timestamptz(timestamp));
}

/*****************************************************************************
 *
 * Datetime/Interval Arithmetic
 *
 *****************************************************************************/
/* oradate - oratimestampltz
 * oradate - oratimestamptz
 * oratimestamp - oratimestampltz
 * oratimestamp - oratimestampltz
 */
Datum
oradate_mi_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	TimestampTz	dt2 = PG_GETARG_TIMESTAMP(1);
	Timestamp	timestamp;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;
	int			tz;
	Interval   *result;

	result = (Interval *) palloc(sizeof(Interval));

	if (TIMESTAMP_NOT_FINITE(dt1) || TIMESTAMP_NOT_FINITE(dt2))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("cannot subtract infinite timestamps")));
	else
	{
		if (timestamp2tm(dt2, &tz, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
		if (tm2timestamp(tm, fsec, NULL, &timestamp) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
	}

	result->time = dt1 - timestamp;

	result->month = 0;
	result->day = 0;

	result = DatumGetIntervalP(DirectFunctionCall1(interval_justify_hours,
												 IntervalPGetDatum(result)));

	PG_RETURN_INTERVAL_P(result);
}

/*
 * oratimestamptz - oratimestamp
 * oratimestampltz - oratimestamp
 * oratimestamptz - oradate
 * oratimestampltz - oradate
 */
Datum
oratimestampltz_mi_oradate(PG_FUNCTION_ARGS)
{
	TimestampTz	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);
	Timestamp	timestamp;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;
	int			tz;
	Interval   *result;

	result = (Interval *) palloc(sizeof(Interval));

	if (TIMESTAMP_NOT_FINITE(dt1) || TIMESTAMP_NOT_FINITE(dt2))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("cannot subtract infinite timestamps")));
	else
	{
		if (timestamp2tm(dt1, &tz, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
		if (tm2timestamp(tm, fsec, NULL, &timestamp) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
	}

	result->time = timestamp - dt2;

	result->month = 0;
	result->day = 0;

	result = DatumGetIntervalP(DirectFunctionCall1(interval_justify_hours,
												 IntervalPGetDatum(result)));

	PG_RETURN_INTERVAL_P(result);
}

/*
 * Compatible oracle
 * The arithmetic operation of oradate minus oradate, Result
 * type is NUMBER.
 *
 * Because Operates internally using float8 data type, so the
 * number type to be returned maximum significant digits is 15.
 *
 */
Datum
oradate_mi(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);
	double		result;

	if (TIMESTAMP_NOT_FINITE(dt1) || TIMESTAMP_NOT_FINITE(dt2))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("cannot subtract infinite timestamps")));

	result = dt1 - dt2;

	result = result / USECS_PER_DAY;

	PG_RETURN_DATUM(DirectFunctionCall1(float8_numeric, Float8GetDatum(result)));
}

/*
 * Compatible oracle
 * The arithmetic operation of oratimestamp minus oratimestamp, Result
 * type is INTERVAL.
 *
 * The other format arithmetic operation depend on this function,
 * include 'oratimestamp - oradate' and 'oradate - oratimestamp'.
 *
 * The only exception is that arithmetic operation 'oradate - oradate' , the result
 * type is NUMBER type.
 *
 */
Datum
oratimestamp_mi(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);
	Interval   *result;

	result = (Interval *) palloc(sizeof(Interval));

	if (TIMESTAMP_NOT_FINITE(dt1) || TIMESTAMP_NOT_FINITE(dt2))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("cannot subtract infinite timestamps")));

	result->time = dt1 - dt2;

	result->month = 0;
	result->day = 0;

	result = DatumGetIntervalP(DirectFunctionCall1(interval_justify_hours,
												 IntervalPGetDatum(result)));

	PG_RETURN_INTERVAL_P(result);
}


/*
 * Compatible oracle
 * The arithmetic operation of oradate plus interval, Result
 * type is oradate.
 *
 */
Datum
oradate_pl_interval(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	Interval   *span = PG_GETARG_INTERVAL_P(1);
	Timestamp	result;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		/* interval year to month */
		if (span->month != 0)
		{
			struct pg_tm tt,
					   *tm = &tt;
			fsec_t		fsec;

			if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));

			tm->tm_mon += span->month;
			if (tm->tm_mon > MONTHS_PER_YEAR)
			{
				tm->tm_year += (tm->tm_mon - 1) / MONTHS_PER_YEAR;
				tm->tm_mon = ((tm->tm_mon - 1) % MONTHS_PER_YEAR) + 1;
			}
			else if (tm->tm_mon < 1)
			{
				tm->tm_year += tm->tm_mon / MONTHS_PER_YEAR - 1;
				tm->tm_mon = tm->tm_mon % MONTHS_PER_YEAR + MONTHS_PER_YEAR;
			}

			/* Compatible oracle, the result must be an actual datetime value */
			if (tm->tm_mday > day_tab[isleap(tm->tm_year)][tm->tm_mon - 1])
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("datetime not valid for month specified")));

			/* Compatible oracle oradate dont have fsec */
			fsec = 0;
			
			if (tm2timestamp(tm, fsec, NULL, &timestamp) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));
		}

		/* interval day to second */
		if (span->day != 0)
		{
			struct pg_tm tt,
					   *tm = &tt;
			fsec_t		fsec;
			int			julian;

			if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));

			/* Add days by converting to and from julian */
			julian = date2j(tm->tm_year, tm->tm_mon, tm->tm_mday) + span->day;
			j2date(julian, &tm->tm_year, &tm->tm_mon, &tm->tm_mday);

			/* Compatible oracle oradate dont have fsec */
			fsec = 0;
			
			if (tm2timestamp(tm, fsec, NULL, &timestamp) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));
		}

		timestamp += span->time;
		result = timestamp;
	}

	PG_RETURN_TIMESTAMP(result);
}

/*
 * Compatible oracle
 * The arithmetic operation of oradate minus interval, Result
 * type is oradate.
 *
 */
Datum
oradate_mi_interval(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	Interval   *span = PG_GETARG_INTERVAL_P(1);
	Interval	tspan;

	tspan.month = -span->month;
	tspan.day = -span->day;
	tspan.time = -span->time;

	return DirectFunctionCall2(oradate_pl_interval,
							   TimestampGetDatum(timestamp),
							   PointerGetDatum(&tspan));
}



/*
 * Compatible oracle
 * The arithmetic operation of oratimestamp plus interval, Result
 * type is oratimestamp.
 *
 */
Datum
oratimestamp_pl_interval(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	Interval   *span = PG_GETARG_INTERVAL_P(1);
	Timestamp	result;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		if (span->month != 0)
		{
			struct pg_tm tt,
					   *tm = &tt;
			fsec_t		fsec;

			if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));

			tm->tm_mon += span->month;
			if (tm->tm_mon > MONTHS_PER_YEAR)
			{
				tm->tm_year += (tm->tm_mon - 1) / MONTHS_PER_YEAR;
				tm->tm_mon = ((tm->tm_mon - 1) % MONTHS_PER_YEAR) + 1;
			}
			else if (tm->tm_mon < 1)
			{
				tm->tm_year += tm->tm_mon / MONTHS_PER_YEAR - 1;
				tm->tm_mon = tm->tm_mon % MONTHS_PER_YEAR + MONTHS_PER_YEAR;
			}

			/* adjust for end of month boundary problems... */
			if (tm->tm_mday > day_tab[isleap(tm->tm_year)][tm->tm_mon - 1])
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("datetime not valid for month specified")));

			if (tm2timestamp(tm, fsec, NULL, &timestamp) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));
		}

		if (span->day != 0)
		{
			struct pg_tm tt,
					   *tm = &tt;
			fsec_t		fsec;
			int			julian;

			if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));

			/* Add days by converting to and from julian */
			julian = date2j(tm->tm_year, tm->tm_mon, tm->tm_mday) + span->day;
			j2date(julian, &tm->tm_year, &tm->tm_mon, &tm->tm_mday);

			if (tm2timestamp(tm, fsec, NULL, &timestamp) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));
		}

		timestamp += span->time;
		result = timestamp;
	}

	PG_RETURN_TIMESTAMP(result);
}


/*
 * Compatible oracle
 * The arithmetic operation of oratimestamp minus interval, Result
 * type is oratimestamp.
 *
 */
Datum
oratimestamp_mi_interval(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	Interval   *span = PG_GETARG_INTERVAL_P(1);
	Interval	tspan;

	tspan.month = -span->month;
	tspan.day = -span->day;
	tspan.time = -span->time;

	return DirectFunctionCall2(oratimestamp_pl_interval,
							   TimestampGetDatum(timestamp),
							   PointerGetDatum(&tspan));
}

/*
 * Compatible oracle
 * The arithmetic operation of oratimestamptz plus interval, Result
 * type is oratimestamptz.
 *
 * note that, the operation of oratimestampltz plus interval alse use this.
 *
 */
Datum
oratimestamptz_pl_interval(PG_FUNCTION_ARGS)
{
	TimestampTz timestamp = PG_GETARG_TIMESTAMPTZ(0);
	Interval   *span = PG_GETARG_INTERVAL_P(1);
	TimestampTz result;
	int			tz;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		if (span->month != 0)
		{
			struct pg_tm tt,
					   *tm = &tt;
			fsec_t		fsec;

			if (timestamp2tm(timestamp, &tz, tm, &fsec, NULL, NULL) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));

			tm->tm_mon += span->month;
			if (tm->tm_mon > MONTHS_PER_YEAR)
			{
				tm->tm_year += (tm->tm_mon - 1) / MONTHS_PER_YEAR;
				tm->tm_mon = ((tm->tm_mon - 1) % MONTHS_PER_YEAR) + 1;
			}
			else if (tm->tm_mon < 1)
			{
				tm->tm_year += tm->tm_mon / MONTHS_PER_YEAR - 1;
				tm->tm_mon = tm->tm_mon % MONTHS_PER_YEAR + MONTHS_PER_YEAR;
			}

			/* adjust for end of month boundary problems... */
			if (tm->tm_mday > day_tab[isleap(tm->tm_year)][tm->tm_mon - 1])
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("datetime not valid for month specified")));

			tz = DetermineTimeZoneOffset(tm, session_timezone);

			if (tm2timestamp(tm, fsec, &tz, &timestamp) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));
		}

		if (span->day != 0)
		{
			struct pg_tm tt,
					   *tm = &tt;
			fsec_t		fsec;
			int			julian;

			if (timestamp2tm(timestamp, &tz, tm, &fsec, NULL, NULL) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));

			/* Add days by converting to and from julian */
			julian = date2j(tm->tm_year, tm->tm_mon, tm->tm_mday) + span->day;
			j2date(julian, &tm->tm_year, &tm->tm_mon, &tm->tm_mday);

			tz = DetermineTimeZoneOffset(tm, session_timezone);

			if (tm2timestamp(tm, fsec, &tz, &timestamp) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("timestamp out of range")));
		}

		timestamp += span->time;
		result = timestamp;
	}

	PG_RETURN_TIMESTAMPTZ(result);
}

/*
 * Compatible oracle
 * The arithmetic operation of oratimestamptz minus interval, Result
 * type is oratimestamptz.
 *
 * note that, the operation of oratimestampltz minus interval alse use this.
 */
Datum
oratimestamptz_mi_interval(PG_FUNCTION_ARGS)
{
	TimestampTz timestamp = PG_GETARG_TIMESTAMPTZ(0);
	Interval   *span = PG_GETARG_INTERVAL_P(1);
	Interval	tspan;

	tspan.month = -span->month;
	tspan.day = -span->day;
	tspan.time = -span->time;

	return DirectFunctionCall2(oratimestamptz_pl_interval,
							   TimestampGetDatum(timestamp),
							   PointerGetDatum(&tspan));
}

/*
 * Compatible oracle
 * The arithmetic operation of interval plus oradate, Result
 * type is oradate.
 */
Datum
interval_pl_oradate(PG_FUNCTION_ARGS)
{
	Interval   *span = PG_GETARG_INTERVAL_P(0);
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(1);

	return DirectFunctionCall2(oradate_pl_interval,
							   TimestampGetDatum(timestamp),
							   PointerGetDatum(span));
}

/*
 * Compatible oracle
 * The arithmetic operation of interval plus oratimestamp, Result
 * type is oratimestamp.
 */
Datum
interval_pl_oratimestamp(PG_FUNCTION_ARGS)
{
	Interval   *span = PG_GETARG_INTERVAL_P(0);
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(1);

	return DirectFunctionCall2(oratimestamp_pl_interval,
							   TimestampGetDatum(timestamp),
							   PointerGetDatum(span));
}

/*
 * Compatible oracle
 * The arithmetic operation of interval plus oratimestamptz , Result
 * type is oratimestamptz.
 *
 * note that, the operation of interval plus oratimestampltz alse use this.
 */
Datum
interval_pl_oratimestamptz(PG_FUNCTION_ARGS)
{
	Interval   *span = PG_GETARG_INTERVAL_P(0);
	TimestampTz timestamp = PG_GETARG_TIMESTAMPTZ(1);

	return DirectFunctionCall2(oratimestamptz_pl_interval,
							   TimestampGetDatum(timestamp),
							   PointerGetDatum(span));
}

/*
 * Compatible oracle
 * The arithmetic operation of oradate plus number, Result
 * type is oradate.
 */
Datum
oradate_pl_number(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	Numeric		num = PG_GETARG_NUMERIC(1);
	float8		addend;
	Timestamp	result;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		addend = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
		addend = rint(addend * USECS_PER_DAY);
		result = timestamp + addend;
	}

	PG_RETURN_TIMESTAMP(result);
}


/*
 * Compatible oracle
 * The arithmetic operation of number plus oradate, Result
 * type is oradate.
 */
Datum
number_pl_oradate(PG_FUNCTION_ARGS)
{
	Numeric		num = PG_GETARG_NUMERIC(0);
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(1);
	float8		addend;
	Timestamp	result;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		addend = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
		addend = rint(addend * USECS_PER_DAY);
		result = timestamp + addend;
	}

	PG_RETURN_TIMESTAMP(result);
}


/*
 * Compatible oracle
 * The arithmetic operation of oradate minus number, Result
 * type is oradate.
 */
Datum
oradate_mi_number(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	Numeric		num = PG_GETARG_NUMERIC(1);
	float8		mi;
	Timestamp	result;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		mi = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
		mi = rint(mi * USECS_PER_DAY);
		result = timestamp - mi;
	}

	PG_RETURN_TIMESTAMP(result);
}

/* 
 * Compatible oracle
 * The arithmetic operation of oratimestamp plus number, Result
 * type is oradate.
 */
Datum
oratimestamp_pl_number(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	Numeric		num = PG_GETARG_NUMERIC(1);
	float8		addend;
	Timestamp	result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		/* Convert timestamp to TM and ignore time zone */
		if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
					 
		/* Convert timestamp to date ignore time zone and fractional second */
		if (tm2timestamp(tm, 0, NULL, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		addend = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
		addend = rint(addend * USECS_PER_DAY);
		
		result = result + addend;
	}

	PG_RETURN_TIMESTAMP(result);
}

/* 
 * Compatible oracle
 * The arithmetic operation of number plus oratimestamp, Result
 * type is oradate.
 */
Datum
number_pl_oratimestamp(PG_FUNCTION_ARGS)
{
	Numeric		num = PG_GETARG_NUMERIC(0);
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(1);
	float8		addend;
	Timestamp	result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		/* Convert timestamp to TM and ignore time zone */
		if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		/* Convert timestamp to date ignore time zone and fractional second */
		if (tm2timestamp(tm, 0, NULL, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		addend = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
		addend = rint(addend * USECS_PER_DAY);
		
		result = result + addend;
	}

	PG_RETURN_TIMESTAMP(result);
}



/*
 * Compatible oracle
 * The arithmetic operation of oratimestamp minus number, Result
 * type is oradate.
 */
Datum
oratimestamp_mi_number(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	Numeric		num = PG_GETARG_NUMERIC(1);
	float8		mi;
	Timestamp	result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		/* Convert timestamp to TM and ignore time zone */
		if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		/* Convert timestamp to date ignore time zone and fractional second */
		if (tm2timestamp(tm, 0, NULL, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		mi = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
		mi = rint(mi * USECS_PER_DAY);
		result = result - mi;
	}

	PG_RETURN_TIMESTAMP(result);
}

/*
 * Compatible oracle
 * The arithmetic operation of oratimestamptz minus number, Result
 * type is oradate.
 */
Datum
oratimestamptz_mi_number(PG_FUNCTION_ARGS)
{
	TimestampTz	timestamp = PG_GETARG_TIMESTAMPTZ(0);
	Numeric		num = PG_GETARG_NUMERIC(1);
	float8		mi;
	Timestamp	result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;
	int			tz;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		if (timestamp2tm(timestamp, &tz, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
					 
		/* Convert timestamp to date ignore fractional second */
		if (tm2timestamp(tm, 0, NULL, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		mi = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
		mi = rint(mi * USECS_PER_DAY);
		result = result - mi;
	}

	PG_RETURN_TIMESTAMP(result);
}

/*
 * Compatible oracle
 * The arithmetic operation of oratimestamptz plus number, Result
 * type is oradate.
 */
Datum
oratimestamptz_pl_number(PG_FUNCTION_ARGS)
{
	TimestampTz	timestamp = PG_GETARG_TIMESTAMPTZ(0);
	Numeric		num = PG_GETARG_NUMERIC(1);
	float8		addend;
	Timestamp	result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;
	int			tz;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		/* Convert timestamp to TM and ignore time zone */
		if (timestamp2tm(timestamp, &tz, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
					 
		/* Convert timestamp to date ignore time zone and fractional second */
		if (tm2timestamp(tm, 0, NULL, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		addend = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
		addend = rint(addend * USECS_PER_DAY);
		
		result = result + addend;
	}

	PG_RETURN_TIMESTAMP(result);
}

/*
 * Compatible oracle
 * The arithmetic operation of number plus oratimestamptz, Result
 * type is oradate.
 */
Datum
number_pl_oratimestamptz(PG_FUNCTION_ARGS)
{
	Numeric		num = PG_GETARG_NUMERIC(0);
	TimestampTz	timestamp = PG_GETARG_TIMESTAMPTZ(1);
	float8		addend;
	Timestamp	result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;
	int			tz;

	if (TIMESTAMP_NOT_FINITE(timestamp))
		result = timestamp;
	else
	{
		/* Convert timestamp to TM and ignore time zone */
		if (timestamp2tm(timestamp, &tz, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		/* Convert timestamp to date ignore time zone and fractional second */
		if (tm2timestamp(tm, 0, NULL, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		addend = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
		addend = rint(addend * USECS_PER_DAY);
		
		result = result + addend;
	}

	PG_RETURN_TIMESTAMP(result);
}

