/*-------------------------------------------------------------------------
 *
 * oradate.c
 *
 * Compatible with Oracle's DATE data type.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/oradate.c
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
#include "utils/date.h"


PG_FUNCTION_INFO_V1(oradate_in);
PG_FUNCTION_INFO_V1(oradate_out);
PG_FUNCTION_INFO_V1(oradate_recv);
PG_FUNCTION_INFO_V1(oradate_send);
PG_FUNCTION_INFO_V1(oradate_eq);
PG_FUNCTION_INFO_V1(oradate_ne);
PG_FUNCTION_INFO_V1(oradate_lt);
PG_FUNCTION_INFO_V1(oradate_gt);
PG_FUNCTION_INFO_V1(oradate_le);
PG_FUNCTION_INFO_V1(oradate_ge);
PG_FUNCTION_INFO_V1(oradate_cmp);
PG_FUNCTION_INFO_V1(oradate_cmp_oratimestamp);
PG_FUNCTION_INFO_V1(oradate_cmp_oratimestamptz);
PG_FUNCTION_INFO_V1(oradate_cmp_oratimestampltz);
PG_FUNCTION_INFO_V1(oradate_hash);
PG_FUNCTION_INFO_V1(oradate_hash_extended);
PG_FUNCTION_INFO_V1(oradate_smaller);
PG_FUNCTION_INFO_V1(oradate_larger);
PG_FUNCTION_INFO_V1(oradate_eq_oratimestamp);
PG_FUNCTION_INFO_V1(oradate_ne_oratimestamp);
PG_FUNCTION_INFO_V1(oradate_lt_oratimestamp);
PG_FUNCTION_INFO_V1(oradate_gt_oratimestamp);
PG_FUNCTION_INFO_V1(oradate_le_oratimestamp);
PG_FUNCTION_INFO_V1(oradate_ge_oratimestamp);

PG_FUNCTION_INFO_V1(oradate_eq_oratimestamptz);
PG_FUNCTION_INFO_V1(oradate_ne_oratimestamptz);
PG_FUNCTION_INFO_V1(oradate_lt_oratimestamptz);
PG_FUNCTION_INFO_V1(oradate_gt_oratimestamptz);
PG_FUNCTION_INFO_V1(oradate_le_oratimestamptz);
PG_FUNCTION_INFO_V1(oradate_ge_oratimestamptz);

PG_FUNCTION_INFO_V1(oradate_eq_oratimestampltz);
PG_FUNCTION_INFO_V1(oradate_ne_oratimestampltz);
PG_FUNCTION_INFO_V1(oradate_lt_oratimestampltz);
PG_FUNCTION_INFO_V1(oradate_gt_oratimestampltz);
PG_FUNCTION_INFO_V1(oradate_le_oratimestampltz);
PG_FUNCTION_INFO_V1(oradate_ge_oratimestampltz);

PG_FUNCTION_INFO_V1(oradate_date);
PG_FUNCTION_INFO_V1(date_oradate);
PG_FUNCTION_INFO_V1(oradate_timestamptz);
PG_FUNCTION_INFO_V1(timestamptz_oradate);
PG_FUNCTION_INFO_V1(oradate_oratimestamptz);
PG_FUNCTION_INFO_V1(oradate_oratimestampltz);

static Timestamp
date2timestamp(DateADT dateVal)
{
	Timestamp	result;

	if (DATE_IS_NOBEGIN(dateVal))
		TIMESTAMP_NOBEGIN(result);
	else if (DATE_IS_NOEND(dateVal))
		TIMESTAMP_NOEND(result);
	else
	{
#ifdef HAVE_INT64_TIMESTAMP
		/* date is days since 2000, timestamp is microseconds since same... */
		result = dateVal * USECS_PER_DAY;
		/* Date's range is wider than timestamp's, so check for overflow */
		if (result / USECS_PER_DAY != dateVal)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("date out of range for timestamp")));
#else
		/* date is days since 2000, timestamp is seconds since same... */
		result = dateVal * (double) SECS_PER_DAY;
#endif
	}

	return result;
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

/* oradate_in()
 * Convert a string to internal form.
 */
Datum
oradate_in(PG_FUNCTION_ARGS)
{
	char		*str = PG_GETARG_CSTRING(0);
	Oid		collid = PG_GET_COLLATION();
	Timestamp	result;
	struct pg_tm	tm;
	fsec_t		fsec;

	if (strcmp(nls_date_format, "pg") == 0 || DATETIME_IGNORE_NLS(datetime_ignore_nls_mask, ORADATE_MASK))
	{
		return DirectFunctionCall1(date_timestamp,
									DirectFunctionCall1(date_in, CStringGetDatum(str)));
	}
	else
	{
		ora_do_to_timestamp(cstring_to_text(str), cstring_to_text(nls_date_format), collid, false, &tm, &fsec, NULL, NULL, NULL, false);

		/* cancel timezone and truncate fractional second for type oradate */
		fsec = 0;
		if (tm2timestamp(&tm, fsec, NULL, &result) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("date out of range")));

		PG_RETURN_TIMESTAMP(result);
	}
}

/* oradate_out()
 * Convert a oradate to external form.
 */
Datum
oradate_out(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);

	if (strcmp(nls_date_format, "pg") != 0)
	{
		char	   *result;
		text	   *date_str;

		date_str = DatumGetTextP(DirectFunctionCall2(timestamp_to_char,
								  TimestampGetDatum(timestamp),
								  PointerGetDatum(cstring_to_text(nls_date_format))));

		result = text_to_cstring(date_str);
		PG_RETURN_CSTRING(result);
	}
	else
		return DirectFunctionCall1(timestamp_out, TimestampTzGetDatum(timestamp));
}


/*
 * oradate_recv()
 * Convert external binary format to oradate.
 *
 * We make no attempt to provide compatibility
 * between int and float timestamp representations.
 */
Datum
oradate_recv(PG_FUNCTION_ARGS)
{
	StringInfo	buf = (StringInfo) PG_GETARG_POINTER(0);

	Timestamp	timestamp;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;

#ifdef HAVE_INT64_TIMESTAMP
	timestamp = (Timestamp) pq_getmsgint64(buf);
#else
	timestamp = (Timestamp) pq_getmsgfloat8(buf);

	if (isnan(timestamp))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("date cannot be NaN")));
#endif

	/* rangecheck: see if timestamp_out would like it */
	if (TIMESTAMP_NOT_FINITE(timestamp))
		 /* ok */ ;
	else if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("date out of range")));

	PG_RETURN_TIMESTAMP(timestamp);
}


/*
 * oradate_send()
 * Convert oradate to binary format.
 */
Datum
oradate_send(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	StringInfoData buf;

	pq_begintypsend(&buf);
#ifdef HAVE_INT64_TIMESTAMP
	pq_sendint64(&buf, timestamp);
#else
	pq_sendfloat8(&buf, timestamp);
#endif
	PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}


/*****************************************************************************
 *	 Operator Function														 *
 *****************************************************************************/

Datum
oradate_eq(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}

Datum
oradate_ne(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oradate_lt(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oradate_gt(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oradate_le(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oradate_ge(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) >= 0);
}

/*
 * Crosstype comparison functions for oradate vs oratimestamp.
 */
Datum
oradate_eq_oratimestamp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}


Datum
oradate_ne_oratimestamp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oradate_lt_oratimestamp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oradate_gt_oratimestamp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oradate_le_oratimestamp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oradate_ge_oratimestamp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) >= 0);
}

/*
 * Crosstype comparison functions for oradate vs oratimestamptz.
 */
Datum
oradate_eq_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}

Datum
oradate_ne_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oradate_lt_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oradate_gt_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oradate_le_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oradate_ge_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) >= 0);
}

/*
 * Crosstype comparison functions for oradate vs oratimestampltz.
 */
Datum
oradate_eq_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) == 0);
}

Datum
oradate_ne_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) != 0);
}

Datum
oradate_lt_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) < 0);
}

Datum
oradate_gt_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) > 0);
}

Datum
oradate_le_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_BOOL(timestamp_cmp_internal(dt1, dt2) <= 0);
}

Datum
oradate_ge_oratimestampltz(PG_FUNCTION_ARGS)
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
oradate_cmp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

Datum
oradate_cmp_oratimestamp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

Datum
oradate_cmp_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestampVal = PG_GETARG_TIMESTAMP(0);
	TimestampTz dt2 = PG_GETARG_TIMESTAMPTZ(1);
	TimestampTz dt1;

	dt1 = timestamp2timestamptz(timestampVal);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

Datum
oradate_cmp_oratimestampltz(PG_FUNCTION_ARGS)
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
oradate_hash(PG_FUNCTION_ARGS)
{
	return hashint8(fcinfo);
}

Datum
oradate_hash_extended(PG_FUNCTION_ARGS)
{
	return hashint8extended(fcinfo);
}

/*****************************************************************************
 *	 Aggregate Function
 *****************************************************************************/
Datum
oradate_larger(PG_FUNCTION_ARGS)
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
oradate_smaller(PG_FUNCTION_ARGS)
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
/* oradate_date()
 * Convert oradate to date data type of postgresql.
 */
Datum
oradate_date(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	DateADT		result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;

	if (TIMESTAMP_IS_NOBEGIN(timestamp))
		DATE_NOBEGIN(result);
	else if (TIMESTAMP_IS_NOEND(timestamp))
		DATE_NOEND(result);
	else
	{
		if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

		result = date2j(tm->tm_year, tm->tm_mon, tm->tm_mday) - POSTGRES_EPOCH_JDATE;
	}

	PG_RETURN_DATEADT(result);
}

/* date_oradate()
 * Convert date data type of postgresql to oradate data type.
 */
Datum
date_oradate(PG_FUNCTION_ARGS)
{
	DateADT		dateVal = PG_GETARG_DATEADT(0);
	Timestamp	result;

	result = date2timestamp(dateVal);

	PG_RETURN_TIMESTAMP(result);
}

/* oradate_timestamptz()
 * Convert oradate to timestamptz data type of postgresql.
 */
Datum
oradate_timestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);

	PG_RETURN_TIMESTAMPTZ(timestamp2timestamptz(timestamp));
}

/* timestamptz_oradate()
 * Convert timestamptz of postgresql to oradate.
 */
Datum
timestamptz_oradate(PG_FUNCTION_ARGS)
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

/* The following conversion functions are compatible with Oracle */

/* oradate_oratimestamptz()
 * Convert oradate to oratimestamptz.
 */
Datum
oradate_oratimestamptz(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);

	PG_RETURN_TIMESTAMPTZ(timestamp2timestamptz(timestamp));
}

/* oradate_oratimestampltz()
 * Convert oradate to oratimestampltz.
 */
Datum
oradate_oratimestampltz(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);

	PG_RETURN_TIMESTAMPTZ(timestamp2timestamptz(timestamp));
}

