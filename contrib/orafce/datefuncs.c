/*-------------------------------------------------------------------------
 *
 *
 * Copyright (c) 2001-2021, highgo compatible Group
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
#include "builtins.h"
#include "pgtime.h"
#include "utils/datetime.h"
#include "utils/numeric.h"
#include "port.h"
#include "miscadmin.h"
#include <utils/date.h>
#include <funcapi.h>


PG_FUNCTION_INFO_V1(ora_fromtz);

static bool
valid_zone(char *tzname)
{
	pg_tz	   *tz;
	pg_tzenum  *tzenum;
	int tzoff;
	struct pg_tm tm;
	fsec_t fsec;
	const char *tzn;
	tzenum = pg_tzenumerate_start();
	for (;;)
	{
		tz = pg_tzenumerate_next(tzenum);
		if (!tz)
		{
			pg_tzenumerate_end(tzenum);
			return -1;
		}
		if (timestamp2tm(GetCurrentTransactionStartTimestamp(),
						 &tzoff, &tm, &fsec, &tzn, tz) != 0)
			continue;
		if (tzn && strlen(tzn) > 31)
			continue;
		if (strncmp(pg_get_timezone_name(tz),tzname,strlen(tzname)) == 0 ||
			strncmp(tzn,tzname,strlen(tzname)) == 0)
		{
			pg_tzenumerate_end(tzenum);
			return 0;
		}
	}
	return -1;
}

/********************************************************************
 *
 * ora_fromtz
 *
 * Purpose:
 *
 * Returns the specified time zone as the time
 *
 ********************************************************************/
Datum
ora_fromtz(PG_FUNCTION_ARGS)
{
		Timestamp timestamp = PG_GETARG_TIMESTAMP(0);
		text *zone = PG_GETARG_TEXT_PP(1);
		char tzname[TZ_STRLEN_MAX+1];
		TimestampTz result;
		struct pg_tm tt,
		*tm = &tt;
		fsec_t  fsec;
		int tz,tz_1;
		char dtstr[TZ_STRLEN_MAX+1];

		int dtlen = 0;
		int tzlen = 0;

		char *resval;
		/*convert timestamp to tm structure*/
		if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
				ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				errmsg("timestamp out of range")));

		/*convert  tm structure to timestamp*/
		if (tm2timestamp(tm, fsec, &tz, &result) != 0)
				ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				errmsg("timestamp out of range")));

		/*encode the datetime*/
		EncodeDateTime(tm, fsec, false, tz, NULL, DateStyle, dtstr);

		dtlen = strlen(dtstr);

		/*call pg functions to switch text to cstring*/
		text_to_cstring_buffer(zone, tzname, sizeof(tzname));
		tzlen = strlen(tzname)+1;
	if (isdigit((unsigned char)*tzname))
	{
		for(int i=tzlen ;i >= 0 ;i--)
		{
			tzname[i+1]=tzname[i];
		}
		tzname[0]='+';
		tz_1=DecodeTimezone(tzname,&tz);
		if (tz_1)
					ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					errmsg("timeszone must be between -16 and 16 ")));
	}
	else if (*tzname == '+' || *tzname == '-')
	{
		tz_1=DecodeTimezone(tzname,&tz);
		if (tz_1)
					ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					errmsg("timeszone must be between -16 and 16 ")));
	}
	else if (isalpha((unsigned char)*tzname))
	{
		if(valid_zone(tzname))
		{
			ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					errmsg("times zone unrecognized")));
		}
	}
	else
	{
			ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					errmsg("times zone unrecognized")));
	}
		resval = (char *)palloc(dtlen + tzlen + 2);

		sprintf(resval, "%s%c%s", dtstr, ' ', tzname);
		PG_RETURN_CSTRING(resval);
}



