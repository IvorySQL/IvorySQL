/*-------------------------------------------------------------------------
 *
 *
 * Portions Copyright (c) 2021-2022, IvorySQL
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


#define NUMBER_OF_TIME_ZONES 18


PG_FUNCTION_INFO_V1(ora_fromtz);
PG_FUNCTION_INFO_V1(ora_systimestamp);
PG_FUNCTION_INFO_V1(ora_sys_extract_utc);
PG_FUNCTION_INFO_V1(ora_days_between);
PG_FUNCTION_INFO_V1(ora_days_between_tmtz);
PG_FUNCTION_INFO_V1(new_time);
PG_FUNCTION_INFO_V1(months_betweentimestamptz);
PG_FUNCTION_INFO_V1(oramonths_betweentimestamp);
PG_FUNCTION_INFO_V1(oraadd_months);



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

static
TimestampTz GetTimestamp(void)
{
	TimestampTz result;
	struct timeval tp;

	gettimeofday(&tp, NULL);

	result = (TimestampTz) tp.tv_sec -
		((POSTGRES_EPOCH_JDATE - UNIX_EPOCH_JDATE) * SECS_PER_DAY);

#ifdef HAVE_INT64_TIMESTAMP
	result = (result * USECS_PER_SEC) + tp.tv_usec;
#else
	result = result + (tp.tv_usec / 1000000.0);
#endif

	return result;
}

/********************************************************************
 *
 * ora_systimestamp
 *
 * Purpose:
 *
 * get the system timestamp.
 *
 ********************************************************************/
Datum
ora_systimestamp(PG_FUNCTION_ARGS)
{
	PG_RETURN_TIMESTAMPTZ(GetTimestamp());
}

/********************************************************************
 *
 * ora_sys_extract_utc
 *
 * Purpose:
 *
 * Returns the UTC time.
 *
 ********************************************************************/
Datum
ora_sys_extract_utc(PG_FUNCTION_ARGS)
{
	TimestampTz timestamp = PG_GETARG_TIMESTAMPTZ(0);

	PG_RETURN_TIMESTAMPTZ(timestamp);
}

/********************************************************************
 *
 * function:day_diff
 *
 * Purpose:
 *
 * Calculate the number of days between dates.
 *
 ********************************************************************/
static int 
day_diff (int year_start, int month_start, int day_start, int year_end, int month_end, int day_end)
{
	int y2, m2, d2;
	int y1, m1, d1;
	/* Record the number of months between march */
	m1 = (month_start + 9) % 12;
	y1 = year_start - m1/10;
	/*Returns the days between the given time and 0000/3/1*/
	d1 = 365*y1 + y1/4 - y1/100 + y1/400 + (m1*306 + 5)/10 + (day_start - 1);

	m2 = (month_end + 9) % 12;
	y2 = year_end - m2/10;
	d2 = 365*y2 + y2/4 - y2/100 + y2/400 + (m2*306 + 5)/10 + (day_end - 1);

	return (d2 - d1);
}

/********************************************************************
 *
 * ora_days_between
 *
 * Purpose:
 *
 * Returns the time difference between two dates/times, in days, 
 * with the former parameter subtracted from the latter.
 *
 ********************************************************************/
Datum
ora_days_between(PG_FUNCTION_ARGS)
{

	Timestamp tmtz1 = PG_GETARG_TIMESTAMP(0);
	Timestamp tmtz2 = PG_GETARG_TIMESTAMP(1);

	int tz1, tz2;
	struct pg_tm tt1, *tm1 = &tt1;
	struct pg_tm tt2, *tm2 = &tt2;
	fsec_t fsec1, fsec2;
	const char *tzn1, *tzn2;
	int sod1, sod2, mondiff;

	if (TIMESTAMP_NOT_FINITE(tmtz1) || TIMESTAMP_NOT_FINITE(tmtz2))
	{
		return DirectFunctionCall3(numeric_in,
			CStringGetDatum("NaN"),
			ObjectIdGetDatum(InvalidOid),
			Int32GetDatum(-1));
	}

	if (timestamp2tm(tmtz1, &tz1, tm1, &fsec1, &tzn1, NULL) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				errmsg("timestamp out of range")));

	if (timestamp2tm(tmtz2, &tz2, tm2, &fsec2, &tzn2, NULL) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				errmsg("timestamp out of range")));

	mondiff = day_diff(tm2->tm_year,tm2->tm_mon,tm2->tm_mday,tm1->tm_year,tm1->tm_mon,tm1->tm_mday);
	sod1 = tm1->tm_hour * SECS_PER_HOUR
		+ tm1->tm_min * SECS_PER_MINUTE + tm1->tm_sec;
	sod2 = tm2->tm_hour * SECS_PER_HOUR
		+ tm2->tm_min * SECS_PER_MINUTE + tm2->tm_sec;

	{
		double f8_mondiff;
#ifdef HAVE_INT64_TIMESTAMP
		f8_mondiff = mondiff + ((sod1 - sod2)*USECS_PER_SEC + (fsec1 - fsec2))/(USECS_PER_DAY*1.0);
#else
		f8_mondiff = mondiff + ((sod1 - sod2) + (fsec1 - fsec2))/(SECS_PER_DAY*1.0);
#endif
		return DirectFunctionCall1(float8_numeric, Float8GetDatum(f8_mondiff));
	}
}

/********************************************************************
 *
 * ora_days_between_tmtz
 *
 * Purpose:
 *
 * Returns the time difference between two dates/times, in days, with the 
 * former parameter subtracted from the latter.
 *
 ********************************************************************/
Datum ora_days_between_tmtz(PG_FUNCTION_ARGS)
{
	TimestampTz tmtz1 = PG_GETARG_TIMESTAMPTZ(0);
	TimestampTz tmtz2 = PG_GETARG_TIMESTAMPTZ(1);

	int tz1, tz2;
	struct pg_tm tt1, *tm1 = &tt1;
	struct pg_tm tt2, *tm2 = &tt2;
	fsec_t fsec1, fsec2;
	const char *tzn1, *tzn2;
	int sod1, sod2, mondiff;

	if (TIMESTAMP_NOT_FINITE(tmtz1) || TIMESTAMP_NOT_FINITE(tmtz2))
	{
		return DirectFunctionCall3(numeric_in,
			CStringGetDatum("NaN"),
			ObjectIdGetDatum(InvalidOid),
			Int32GetDatum(-1));
	}

	if (timestamp2tm(tmtz1, &tz1, tm1, &fsec1, &tzn1, NULL) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
		 		errmsg("timestamp out of range")));

	if (timestamp2tm(tmtz2, &tz2, tm2, &fsec2, &tzn2, NULL) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				errmsg("timestamp out of range")));

	mondiff = day_diff(tm2->tm_year,tm2->tm_mon,tm2->tm_mday,tm1->tm_year,tm1->tm_mon,tm1->tm_mday);
	sod1 = tm1->tm_hour * SECS_PER_HOUR
		+ tm1->tm_min * SECS_PER_MINUTE + tm1->tm_sec;
	sod2 = tm2->tm_hour * SECS_PER_HOUR
		+ tm2->tm_min * SECS_PER_MINUTE + tm2->tm_sec;
	{
		double f8_mondiff;
#ifdef HAVE_INT64_TIMESTAMP
		f8_mondiff = mondiff + ((sod1 - sod2)*USECS_PER_SEC + (fsec1 - fsec2))/(USECS_PER_DAY*1.0);
#else
		f8_mondiff = mondiff + ((sod1 - sod2) + (fsec1 - fsec2))/(SECS_PER_DAY*1.0);
#endif
		return DirectFunctionCall1(float8_numeric, Float8GetDatum(f8_mondiff));
	}

}


/********************************************************************
 *
 * FUnction:oratimestamptz2timestamp
 *
 * Description:recover timestamp with zone to timestamp without zone
 *
 * Return:timestamp with out zone
 *
 * Note:oracle compatible timestamp transfer
 *
 ********************************************************************/
static Timestamp
oratimestamptz2timestamp(TimestampTz timestamp)
{
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
	return result;
}


/********************************************************************
 *
 * FUnction:new_time
 *
 * Description:convert the time in the specified time zone to another time zone
 *
 * Return:a new timestamp
 *
 * Note:there is olney support timestamp without time zone
 *
 ********************************************************************/
Datum
new_time(PG_FUNCTION_ARGS)
{
	TimestampTz timestamptz = PG_GETARG_TIMESTAMP(0);
	text *arg1 = PG_GETARG_TEXT_P(1);
	text *arg2 = PG_GETARG_TEXT_P(2);
	int tz, i, zone1 = 0, zone2 = 0, tmp1 = 0, tmp2 = 0, day;
	struct pg_tm tt, *tm = &tt;
	fsec_t fsec;
	const char *tzn = NULL;
	char *pre_zone = NULL, *post_zone = NULL ;
	char *zone[NUMBER_OF_TIME_ZONES] 	= {"ast", "adt", "bst", "bdt", "cst", "cdt", "est", "edt", "gmt", "hst", "hdt", "mst", "mdt", "nst", "pst", "pdt", "yst", "ydt"};
	int zone_num[NUMBER_OF_TIME_ZONES] 	= {	  -4, 	 -3,   -11,   -10,    -6,    -5,    -5,    -4,     0,   -10,    -9,    -7,    -6,    -3,    -8,    -7,    -9,    -8};
	Timestamp result;

	Timestamp timestamp;

	timestamp = oratimestamptz2timestamp(timestamptz);

	/*ignore input parameter case*/
	pre_zone = str_tolower(VARDATA_ANY(arg1), VARSIZE_ANY_EXHDR(arg1), PG_GET_COLLATION());
	post_zone = str_tolower(VARDATA_ANY(arg2), VARSIZE_ANY_EXHDR(arg2), PG_GET_COLLATION());

	//timestamp2tm(timestamp, &tz, tm, &fsec, &tzn, pg_tzset("GMT"));
	timestamp2tm(timestamp, &tz, tm, &fsec, &tzn, NULL);

	for (i = 0; i < NUMBER_OF_TIME_ZONES; i++)
    {
		if (!strcmp(zone[i], pre_zone))
		{
			zone1 = zone_num[i];
			tmp1 = 1;
		}

		if (!strcmp(zone[i], post_zone))
		{
			zone2 = zone_num[i];
			tmp2 = 1;
		}
    }

	if ((tmp1 == 0) || (tmp2 == 0))
		ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("illegal timezone!")));

	/*transfer date into Julian day*/
	day = date2j(tm->tm_year, tm->tm_mon, tm->tm_mday);
	tm->tm_hour = tm->tm_hour + zone2 - zone1;

	/* if the zone is nst, there need to deal minutes, becaus nst is 3.5, is not 3 */
	if (0 == strcmp("nst", post_zone))
	{
		if (tm->tm_min > 29)
		{
			tm->tm_min = tm->tm_min - 30;
		}
		else
		{
			tm->tm_min = tm->tm_min + 30;
			tm->tm_hour = tm->tm_hour - 1;
		}
	}

	if(0 == strcmp("nst",pre_zone))
	{
		if (tm->tm_min < 29)
		{
			tm->tm_min = tm->tm_min + 30;
		}
		else
		{
			tm->tm_min = tm->tm_min - 30;
			tm->tm_hour = tm->tm_hour + 1;
		}
	}

	/*if hour bigger than 24, or small than 0, need to change the day*/
	if (tm->tm_hour >= 24)
	{
		tm->tm_hour -= 24;
		day += 1;
	}
	else if (tm->tm_hour < 0)
	{
		tm->tm_hour += 24;
		day -= 1;
	}

	/*transfer Julian day into date format*/
	j2date(day, &tm->tm_year, &tm->tm_mon, &tm->tm_mday);
	fsec = 0;
	if (tm2timestamp(tm, fsec, &tz, &result) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
			 errmsg("timestamp out of range")));

	PG_RETURN_TIMESTAMP(result);
}

/********************************************************************
 *
 * FUnction:days_of_month
 *
 * Description:Calculate the number of days per month
 *
 * Return:the number of days per month.
 *
 ********************************************************************/
static const int ora_month_days[] = {
	31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};

static int
oradays_of_month(int y, int m)
{
	int	days;

	if (m < 0 || 12 < m)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("date out of range")));

	days = ora_month_days[m - 1];
	if (m == 2 && (y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)))
		days += 1;	/* February 29 in leap year */
	return days;
}

/********************************************************************
 *
 * FUnction:months_betweentimestamptz
 *
 * Description:calculate time difference of two timestamp
 *
 * Return:Returns the number of months between timestamptz1 and timestamptz2. If
 *        a fractional month is calculated, the months_between  function
 *        calculates the fraction based on a 31-day month.
 *
 * Note:there is support timestamp without time zone adn timestamp with time zone,
 * if the pramater is timestamp with time zone, there it not right
 *
 ********************************************************************/
Datum
months_betweentimestamptz(PG_FUNCTION_ARGS)
{
	TimestampTz tmtzrec1 = PG_GETARG_TIMESTAMPTZ(0);
	TimestampTz tmtzrec2 = PG_GETARG_TIMESTAMPTZ(1);

	int tz1, tz2;
	struct pg_tm tt1, *tm1 = &tt1;
	struct pg_tm tt2, *tm2 = &tt2;
	fsec_t fsec1, fsec2;
	const char *tzn1, *tzn2;
	float8 result;
	Timestamp tmtz1 ;
	Timestamp tmtz2 ;
	float8 	time1, time2;

	tmtz1 = oratimestamptz2timestamp(tmtzrec1);
	tmtz2 = oratimestamptz2timestamp(tmtzrec2);

	if (TIMESTAMP_NOT_FINITE(tmtz1) || TIMESTAMP_NOT_FINITE(tmtz2))
	{
		return DirectFunctionCall3(numeric_in,
			CStringGetDatum("NaN"),
			ObjectIdGetDatum(InvalidOid),
			Int32GetDatum(-1));
	}

	if (timestamp2tm(tmtz1, &tz1, tm1, &fsec1, &tzn1, NULL) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				errmsg("timestamp out of range")));

	if (timestamp2tm(tmtz2, &tz2, tm2, &fsec2, &tzn2, NULL) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				errmsg("timestamp out of range")));

	time1 = (tm1->tm_mday*24*60*60 + tm1->tm_hour*60*60 + tm1->tm_min*60 + tm1->tm_sec);
	time2 = (tm2->tm_mday*24*60*60 + tm2->tm_hour*60*60 + tm2->tm_min*60 + tm2->tm_sec);
	time1 = ((time1 - time2)/(24*60*60*31));

	/* Ignore day components for last days, or based on a 31-day month. */
	if ((tm1->tm_mday == oradays_of_month(tm1->tm_year, tm1->tm_mon) && tm2->tm_mday == oradays_of_month(tm2->tm_year, tm2->tm_mon)) ||
		(tm1->tm_mday == tm2->tm_mday))
		result = (tm1->tm_year - tm2->tm_year) * 12 + (tm1->tm_mon - tm2->tm_mon);
	else
		result = (float8)((tm1->tm_year - tm2->tm_year) * 12 + (tm1->tm_mon - tm2->tm_mon)) + time1;

	PG_RETURN_NUMERIC(
		DirectFunctionCall1(float8_numeric, Float8GetDatumFast(result)));
}

/********************************************************************
 *
 * FUnction:oramonths_betweentimestamp
 *
 * Description:calculate time difference of two timestamp
 *
 * Return:Returns the number of months between timestamptz1 and timestamptz2. If
 *        a fractional month is calculated, the months_between  function
 *        calculates the fraction based on a 31-day month.
 *
 * Note:there is support timestamp without time zone adn timestamp with time zone,
 * if the pramater is timestamp with time zone, there it not right
 *
 ********************************************************************/
Datum
oramonths_betweentimestamp(PG_FUNCTION_ARGS)
{
	Timestamp tms1 = PG_GETARG_TIMESTAMP(0);
	Timestamp tms2 = PG_GETARG_TIMESTAMP(1);

	int tz1, tz2;
	struct pg_tm tt1, *tm1 = &tt1;
	struct pg_tm tt2, *tm2 = &tt2;
	fsec_t fsec1, fsec2;
	const char *tzn1, *tzn2;
	float8 result;
	float8 	time1, time2;

	if (TIMESTAMP_NOT_FINITE(tms1) || TIMESTAMP_NOT_FINITE(tms2))
	{
		return DirectFunctionCall3(numeric_in,
			CStringGetDatum("NaN"),
			ObjectIdGetDatum(InvalidOid),
			Int32GetDatum(-1));
	}

	if (timestamp2tm(tms1, &tz1, tm1, &fsec1, &tzn1, NULL) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				errmsg("timestamp out of range")));

	if (timestamp2tm(tms2, &tz2, tm2, &fsec2, &tzn2, NULL) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				errmsg("timestamp out of range")));

	time1 = (tm1->tm_mday*24*60*60 + tm1->tm_hour*60*60 + tm1->tm_min*60 + tm1->tm_sec);
	time2 = (tm2->tm_mday*24*60*60 + tm2->tm_hour*60*60 + tm2->tm_min*60 + tm2->tm_sec);
	time1 = ((time1 - time2)/(24*60*60*31));

	/* Ignore day components for last days, or based on a 31-day month. */
	if ((tm1->tm_mday == oradays_of_month(tm1->tm_year, tm1->tm_mon) && tm2->tm_mday == oradays_of_month(tm2->tm_year, tm2->tm_mon)) ||
		(tm1->tm_mday == tm2->tm_mday))
		result = (tm1->tm_year - tm2->tm_year) * 12 + (tm1->tm_mon - tm2->tm_mon);
	else
		result = (float8)((tm1->tm_year - tm2->tm_year) * 12 + (tm1->tm_mon - tm2->tm_mon)) + time1;

	PG_RETURN_NUMERIC(
		DirectFunctionCall1(float8_numeric, Float8GetDatumFast(result)));
}

/********************************************************************
 *
 * oraadd_months
 *
 * Syntax:
 *
 * date oraadd_months(oracle.date day, int val)
 *
 * Purpose:
 *
 * Returns a date plus n months.
 *
 ********************************************************************/
Datum
oraadd_months(PG_FUNCTION_ARGS)
{
	Timestamp tmtzrec1 = PG_GETARG_TIMESTAMP(0);
	int n = PG_GETARG_INT32(1);
	DateADT day;
	int y, m, d;
	int	days;
	DateADT resultday;
	div_t	v;
	bool	last_day;
	struct  pg_tm tt,
			*tm = &tt;
	fsec_t	fsec;
	Timestamp result;

	timestamp2tm(tmtzrec1, NULL, tm, &fsec, NULL, NULL);
	day = date2j(tm->tm_year, tm->tm_mon, tm->tm_mday) - POSTGRES_EPOCH_JDATE;
	
	j2date(day + POSTGRES_EPOCH_JDATE, &y, &m, &d);
	y = tm->tm_year;
	m = tm->tm_mon;
	d = tm->tm_mday;
	
	last_day = (d == oradays_of_month(y, m));

	v = div(y * 12 + m - 1 + n, 12);
	y = v.quot;
	if (y < 0)
	{
		if(tm->tm_year > 0 && ((tm->tm_year - 1) * 12 + m + n) <= 0)
			y = y-2;
		else if(tm->tm_year < 0 && ((tm->tm_year + 1) * 12 - m + n) >= 0)
			y++;
		else if (tm->tm_year < 0 && (((tm->tm_year + 1) * 12 - m + n) < 0))
			y--;
	}
	else if (y >= 0)
	{
		if (tm->tm_year < 0 && (((tm->tm_year + 1) * 12 - m + n) < 0) && (v.rem == 0))
			y++;
		else if (tm->tm_year < 0 && (((tm->tm_year + 1) * 12 - m + n) < 0) && (v.rem != 0))
			y--;
		else if(tm->tm_year < 0 && ((tm->tm_year + 1) * 12 - m + n) >= 0)
			y++;
		else if(tm->tm_year > 0 && ((tm->tm_year - 1) * 12 + m + n) < 0)
			y = y-2;
		else if(tm->tm_year > 0 && ((tm->tm_year - 1) * 12 + m + n) == 0)
			y--;
	}

	m = v.rem + 1;

	if (m <= 0)
		m = 12 + m;

	days = oradays_of_month(y, m);
	if (last_day || d > days)
		d = days;

	resultday = date2j(y, m, d) - POSTGRES_EPOCH_JDATE;

	j2date(resultday + POSTGRES_EPOCH_JDATE, &y, &m, &d);
	
	tm->tm_year = y;
	tm->tm_mon = m;
	tm->tm_mday = d;

	if (tm2timestamp(tm, fsec, NULL, &result) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
			 errmsg("timestamp out of range")));

	PG_RETURN_TIMESTAMP(result);
}


