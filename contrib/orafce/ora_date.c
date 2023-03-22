/*-------------------------------------------------------------------------
 *
 *
 * Copyright (c) 2021-2022, IvorySQL
 *
 *
 * IDENTIFICATION
 *        contrib/orafce /
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"
#include "access/xact.h"
#include "commands/variable.h"
#include "mb/pg_wchar.h"
#include "utils/date.h"
#include "utils/builtins.h"
#include "utils/numeric.h"
#include "utils/formatting.h"
#include <sys/time.h>
#include "orafce.h"
#include "builtins.h"
#include "libpq/pqformat.h"	
#include "pgtime.h"
#include "utils/datetime.h"
#include "utils/numeric.h"
#include "port.h"
#include "miscadmin.h"
#include "utils/guc.h"



#define PARFLOATMIN -2147483648.00
#define PARFLOATMAX 2147483647.00

Datum timestamp_pl_days(Datum pl_tmtz, int pl_days, TimeOffset pl_offset);

PG_FUNCTION_INFO_V1(ora_date_in);
PG_FUNCTION_INFO_V1(ora_date_out);
PG_FUNCTION_INFO_V1(ora_date_recv);
PG_FUNCTION_INFO_V1(ora_date_send);


/*****************************************************************************
 *	 USER I/O ROUTINES														 *
 *****************************************************************************/

/* ora_date_in()
 * Convert a string to internal form.
 */
Datum
ora_date_in(PG_FUNCTION_ARGS)
{
	char	   *str = PG_GETARG_CSTRING(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	Timestamp	result;
	fsec_t		fsec;
	struct pg_tm tt,
			   *tm = &tt;
	int			tz;
	int			dtype;
	int			nf;
	int			dterr;
	char	   *field[MAXDATEFIELDS];
	int			ftype[MAXDATEFIELDS];
	char		workbuf[MAXDATELEN + MAXDATEFIELDS];
	bool		flag = false;
	char	   *str1;

	/* In oracle schema,support the negative sign before the year,skip sign '-' */
	if(*str == '-' && compatible_db == COMPATIBLE_ORA)
	{
		str1 = (char*)palloc(strlen(str));
		memcpy(str1, str + 1, strlen(str));
		flag = true;
		dterr = ParseDateTime(str1, workbuf, sizeof(workbuf),
						  field, ftype, MAXDATEFIELDS, &nf);
		pfree(str1);
	}
	else
		dterr = ParseDateTime(str, workbuf, sizeof(workbuf),
							  field, ftype, MAXDATEFIELDS, &nf);
	if (dterr == 0)
		dterr = DecodeDateTime(field, ftype, nf, &dtype, tm, &fsec, &tz);

	/* deal the year,restore the negative sign of the year */
	if(flag)
	{
		tm->tm_year = - tm->tm_year;
	}
	/* IN oracle schema,support the BC sign before the year,deal year. */
	else if (compatible_db == COMPATIBLE_ORA && tm->tm_year < 0)
	{
		tm->tm_year--;
	}
	if (dterr == 5)
		PG_RETURN_TIMESTAMP(DT_NOBEGIN+ 1);
	if (dterr != 0)
		DateTimeParseError(dterr, str, "date");/* oracle's date */

	switch (dtype)
	{
		case DTK_DATE:
			if (tm2timestamp(tm, 0, NULL, &result) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("date out of range: \"%s\"", str)));
			break;

		case DTK_EPOCH:
			result = SetEpochTimestamp();
			break;

		case DTK_LATE:
			TIMESTAMP_NOEND(result);
			break;

		case DTK_EARLY:
			TIMESTAMP_NOBEGIN(result);
			break;

		default:
			elog(ERROR, "unexpected dtype %d while parsing date \"%s\"",
				 dtype, str);
			TIMESTAMP_NOEND(result);
	}

	PG_RETURN_TIMESTAMP(result);
}

/* timestamp_out()
 * Convert a oracle,s date to external form.
 */
Datum
ora_date_out(PG_FUNCTION_ARGS)
{
	Timestamp	date = PG_GETARG_TIMESTAMP(0);
	char	   *result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;
	char		buf[MAXDATELEN + 1];
	if (date == DT_NOBEGIN+ 1)
		PG_RETURN_CSTRING(pstrdup(""));
	if (TIMESTAMP_NOT_FINITE(date))
		EncodeSpecialTimestamp(date, buf);
	else if (timestamp2tm(date, NULL, tm, &fsec, NULL, NULL) == 0)
	{
		/* IN oracle schema,support the negative sign before the year,deal year. */
		if(tm->tm_year < 0 && compatible_db == COMPATIBLE_ORA)
			tm->tm_year++;
		EncodeDateTime(tm, 0, false, 0, NULL, DateStyle, buf);
	}
	else
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	result = pstrdup(buf);
	PG_RETURN_CSTRING(result);
}

/*
 *		ora_date_recv			- converts external binary format to oracle's date
 */
Datum
ora_date_recv(PG_FUNCTION_ARGS)
{
	StringInfo	buf = (StringInfo) PG_GETARG_POINTER(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	Timestamp	date;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;

	date = (Timestamp) pq_getmsgint64(buf);

	/* range check: see if timestamp_out would like it */
	if (TIMESTAMP_NOT_FINITE(date))
		 /* ok */ ;
	else if (timestamp2tm(date, NULL, tm, &fsec, NULL, NULL) != 0 ||
			 !IS_VALID_TIMESTAMP(date))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("date out of range")));

	PG_RETURN_TIMESTAMP(date);
}

/*
 *		ora_date_send			- converts oracle's date to binary format
 */
Datum
ora_date_send(PG_FUNCTION_ARGS)
{
	Timestamp	timestamp = PG_GETARG_TIMESTAMP(0);
	StringInfoData buf;

	pq_begintypsend(&buf);
	pq_sendint64(&buf, timestamp);
	PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}

