/*-------------------------------------------------------------------------
 *
 * oratimestamptz.c
 *
 * Compatible with Oracle's TIMESTAMP WITH TIME ZONE data type.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/oratimestamptz.c
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

#include "../include/common_datatypes.h"

PG_FUNCTION_INFO_V1(oratimestamptz_in);
PG_FUNCTION_INFO_V1(oratimestamptz_out);
PG_FUNCTION_INFO_V1(oratimestamptz_recv);
PG_FUNCTION_INFO_V1(oratimestamptz_send);
PG_FUNCTION_INFO_V1(oratimestamptztypmodin);
PG_FUNCTION_INFO_V1(oratimestamptztypmodout);
PG_FUNCTION_INFO_V1(oratimestamptz_eq);
PG_FUNCTION_INFO_V1(oratimestamptz_ne);
PG_FUNCTION_INFO_V1(oratimestamptz_lt);
PG_FUNCTION_INFO_V1(oratimestamptz_gt);
PG_FUNCTION_INFO_V1(oratimestamptz_le);
PG_FUNCTION_INFO_V1(oratimestamptz_ge);
PG_FUNCTION_INFO_V1(oratimestamptz);
PG_FUNCTION_INFO_V1(oratimestamptz_cmp);
PG_FUNCTION_INFO_V1(oratimestamptz_cmp_oradate);
PG_FUNCTION_INFO_V1(oratimestamptz_cmp_oratimestamp);
PG_FUNCTION_INFO_V1(oratimestamptz_cmp_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamptz_hash);
PG_FUNCTION_INFO_V1(oratimestamptz_larger);
PG_FUNCTION_INFO_V1(oratimestamptz_smaller);

PG_FUNCTION_INFO_V1(oratimestamptz_eq_oradate);
PG_FUNCTION_INFO_V1(oratimestamptz_ne_oradate);
PG_FUNCTION_INFO_V1(oratimestamptz_lt_oradate);
PG_FUNCTION_INFO_V1(oratimestamptz_gt_oradate);
PG_FUNCTION_INFO_V1(oratimestamptz_le_oradate);
PG_FUNCTION_INFO_V1(oratimestamptz_ge_oradate);

PG_FUNCTION_INFO_V1(oratimestamptz_eq_oratimestamp);
PG_FUNCTION_INFO_V1(oratimestamptz_ne_oratimestamp);
PG_FUNCTION_INFO_V1(oratimestamptz_lt_oratimestamp);
PG_FUNCTION_INFO_V1(oratimestamptz_gt_oratimestamp);
PG_FUNCTION_INFO_V1(oratimestamptz_le_oratimestamp);
PG_FUNCTION_INFO_V1(oratimestamptz_ge_oratimestamp);

PG_FUNCTION_INFO_V1(oratimestamptz_eq_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamptz_ne_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamptz_lt_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamptz_gt_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamptz_le_oratimestampltz);
PG_FUNCTION_INFO_V1(oratimestamptz_ge_oratimestampltz);

PG_FUNCTION_INFO_V1(oratimestamptz_oratimestamp);
PG_FUNCTION_INFO_V1(oratimestamptz_oradate);


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

/* oratimestamptz_in()
 * Convert a string to internal form.
 */
Datum
oratimestamptz_in(PG_FUNCTION_ARGS)
{
		char	   *str = PG_GETARG_CSTRING(0);

#ifdef NOT_USED
		Oid			typelem = PG_GETARG_OID(1);
#endif
		int32		typmod = PG_GETARG_INT32(2);
		Oid		collid = PG_GET_COLLATION();

	if (strcmp(nls_timestamp_tz_format, "pg") == 0 || DATETIME_IGNORE_NLS(datetime_ignore_nls_mask, ORATIMESTAMPTZ_MASK))
	{
		return DirectFunctionCall3(timestamptz_in,
									CStringGetDatum(str),
									ObjectIdGetDatum(InvalidOid),
									Int32GetDatum(typmod));
	}
	else
	{
		TimestampTz	result;
		struct pg_tm tm;
		fsec_t		fsec;
		int			tz;
		DateTimeErrorExtra extra;

		ora_do_to_timestamp(cstring_to_text(str), cstring_to_text(nls_timestamp_tz_format), collid, false, &tm, &fsec, NULL, NULL, NULL, false);

		if (tm.tm_zone)
		{
			int		dterr = DecodeTimezone((char *)tm.tm_zone, &tz);

			if (dterr)
				DateTimeParseError(dterr, &extra, str, "timestamptz", NULL);
		}
		else
			tz = DetermineTimeZoneOffset(&tm, session_timezone);

		/* cancel timezone */
		if (tm2timestamp(&tm, fsec, &tz, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp with time zone out of range")));

		OraAdjustTimestampForTypmod(&result, typmod);

		PG_RETURN_TIMESTAMPTZ(result);
	}
}

/*
 * oratimestamptz_out()
 * Convert a oradate to external form.
 */
Datum
oratimestamptz_out(PG_FUNCTION_ARGS)
{
	TimestampTz	timestamp = PG_GETARG_TIMESTAMPTZ(0);

	if (strcmp(nls_timestamp_tz_format, "pg") != 0)
	{
		char	   *result;
		text	   *date_str;

		date_str = DatumGetTextP(DirectFunctionCall2(timestamptz_to_char,
													  TimestampTzGetDatum(timestamp),
													  PointerGetDatum(cstring_to_text(nls_timestamp_tz_format))));
		
		result = text_to_cstring(date_str);
		PG_RETURN_CSTRING(result);
	}
	else
		return DirectFunctionCall1(timestamptz_out, TimestampTzGetDatum(timestamp));
}

/*
 *	oratimestamptz_recv - converts external binary format to oratimestamptz
 *
 * We make no attempt to provide compatibility between int and float
 * timestamp representations ...
 */
Datum
oratimestamptz_recv(PG_FUNCTION_ARGS)
{
	StringInfo	buf = (StringInfo) PG_GETARG_POINTER(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		typmod = PG_GETARG_INT32(2);
	TimestampTz timestamp;
	int			tz;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;

	timestamp = (TimestampTz) pq_getmsgint64(buf);

	/* rangecheck: see if timestamptz_out would like it */
	if (TIMESTAMP_NOT_FINITE(timestamp))
		 /* ok */ ;
	else if (timestamp2tm(timestamp, &tz, tm, &fsec, NULL, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	OraAdjustTimestampForTypmod(&timestamp, typmod);

	PG_RETURN_TIMESTAMPTZ(timestamp);
}

/*
 *	oratimestamptz_send - converts oratimestamptz to binary format
 */
Datum
oratimestamptz_send(PG_FUNCTION_ARGS)
{
	TimestampTz timestamp = PG_GETARG_TIMESTAMPTZ(0);
	StringInfoData buf;

	pq_begintypsend(&buf);
	pq_sendint64(&buf, timestamp);
	PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}

Datum
oratimestamptztypmodin(PG_FUNCTION_ARGS)
{
	ArrayType  *ta = PG_GETARG_ARRAYTYPE_P(0);

	PG_RETURN_INT32(anytimestamp_typmodin(true, ta));
}

Datum
oratimestamptztypmodout(PG_FUNCTION_ARGS)
{
	int32		typmod = PG_GETARG_INT32(0);

	PG_RETURN_CSTRING(anytimestamp_typmodout(true, typmod));
}

/*****************************************************************************
 *	 Operator Function														 *
 *****************************************************************************/
Datum
oratimestamptz_eq(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}

Datum
oratimestamptz_ne(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oratimestamptz_lt(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oratimestamptz_gt(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oratimestamptz_le(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oratimestamptz_ge(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) >= 0);
}

/* oratimestamptz vs oradate */
Datum
oratimestamptz_eq_oradate(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}

Datum
oratimestamptz_ne_oradate(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oratimestamptz_lt_oradate(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oratimestamptz_gt_oradate(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oratimestamptz_le_oradate(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oratimestamptz_ge_oradate(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) >= 0);
}

/* oratimestamptz vs oratimestamp */
Datum
oratimestamptz_eq_oratimestamp(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}

Datum
oratimestamptz_ne_oratimestamp(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oratimestamptz_lt_oratimestamp(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oratimestamptz_gt_oratimestamp(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oratimestamptz_le_oratimestamp(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oratimestamptz_ge_oratimestamp(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) >= 0);
}

/* oratimestamptz vs oratimestampltz */
Datum
oratimestamptz_eq_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}

Datum
oratimestamptz_ne_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oratimestamptz_lt_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oratimestamptz_gt_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oratimestamptz_le_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oratimestamptz_ge_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) >= 0);
}

/*****************************************************************************
 *	 Converts a oratimestamptz(n) type to the specified typmod size
 *****************************************************************************/
Datum
oratimestamptz(PG_FUNCTION_ARGS)
{
	TimestampTz	source = PG_GETARG_TIMESTAMPTZ(0);
	int32		typmod = PG_GETARG_INT32(1);

	/* No work if typmod is invalid */
	if (typmod == -1)
		PG_RETURN_TIMESTAMPTZ(source);
		
	OraAdjustTimestampForTypmod(&source, typmod);
	PG_RETURN_TIMESTAMPTZ(source);
}

/*****************************************************************************
 *	 B-tree index support procedure
 *****************************************************************************/
Datum
oratimestamptz_cmp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

Datum
oratimestamptz_cmp_oradate(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

Datum
oratimestamptz_cmp_oratimestamp(PG_FUNCTION_ARGS)
{
	TimestampTz dt1 = PG_GETARG_TIMESTAMPTZ(0);
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(1);
	TimestampTz dt2;

	dt2 = timestamp2timestamptz(timestampVal);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

Datum
oratimestamptz_cmp_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

/*****************************************************************************
 *	 Hash index support procedure 
 *****************************************************************************/
Datum
oratimestamptz_hash(PG_FUNCTION_ARGS)
{
	return hashint8(fcinfo);
}

/*****************************************************************************
 *	 Aggregate Function
 *****************************************************************************/
Datum
oratimestamptz_larger(PG_FUNCTION_ARGS)
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
oratimestamptz_smaller(PG_FUNCTION_ARGS)
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
 *	 Cast Function															 *
 *****************************************************************************/

/* oratimestamptz_oradate()
 * Convert oratimestamptz to oradate
 */
Datum
oratimestamptz_oradate(PG_FUNCTION_ARGS)
{
	TimestampTz timestamp = PG_GETARG_TIMESTAMPTZ(0);
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
		if (tm2timestamp(tm, 0, NULL, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
	}
	PG_RETURN_TIMESTAMP(result);
}


/*
 * oratimestamptz_oratimestamp()
 * Convert oratimestamptz to oratimestamp
 */
Datum
oratimestamptz_oratimestamp(PG_FUNCTION_ARGS)
{
	TimestampTz timestamp = PG_GETARG_TIMESTAMPTZ(0);
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
		if (tm2timestamp(tm, fsec, NULL, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
	}
	PG_RETURN_TIMESTAMP(result);
}
