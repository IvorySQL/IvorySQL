/*-------------------------------------------------------------------------
 *
 * datetime_datatype_functions.c
 *
 * This file contains the implementation of Oracle's
 * datetime data type related built-in functions.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_functions/datetime_datatype_functions.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include <time.h>

#include "postgres.h"
#include "datatype/timestamp.h"
#include "mb/pg_wchar.h"
#include "pgtime.h"
#include "utils/builtins.h"
#include "utils/datetime.h"
#include "utils/formatting.h"
#include "utils/guc.h"
#include "utils/numeric.h"
#include "access/xact.h"

#include "../include/common_datatypes.h"

PG_FUNCTION_INFO_V1(sysdate);
PG_FUNCTION_INFO_V1(ora_current_timestamp);
PG_FUNCTION_INFO_V1(ora_local_timestamp);
PG_FUNCTION_INFO_V1(ora_current_date);
PG_FUNCTION_INFO_V1(last_day);
PG_FUNCTION_INFO_V1(add_months);
PG_FUNCTION_INFO_V1(ora_round);
PG_FUNCTION_INFO_V1(ora_trunc);
PG_FUNCTION_INFO_V1(next_day_by_index);
PG_FUNCTION_INFO_V1(next_day);
PG_FUNCTION_INFO_V1(ora_new_time);
PG_FUNCTION_INFO_V1(ora_tz_offset);
PG_FUNCTION_INFO_V1(months_between);
PG_FUNCTION_INFO_V1(ora_from_tz);
PG_FUNCTION_INFO_V1(ora_sys_extract_utc);
PG_FUNCTION_INFO_V1(ora_sessiontimezone);
PG_FUNCTION_INFO_V1(to_oradate1);
PG_FUNCTION_INFO_V1(to_oradate2);
PG_FUNCTION_INFO_V1(to_oradate3);
PG_FUNCTION_INFO_V1(to_oratimestamp1);
PG_FUNCTION_INFO_V1(to_oratimestamp2);
PG_FUNCTION_INFO_V1(to_oratimestamp3);
PG_FUNCTION_INFO_V1(to_oratimestamptz1);
PG_FUNCTION_INFO_V1(to_oratimestamptz2);
PG_FUNCTION_INFO_V1(to_oratimestamptz3);
PG_FUNCTION_INFO_V1(oradate_to_char1);
PG_FUNCTION_INFO_V1(oradate_to_char2);
PG_FUNCTION_INFO_V1(oradate_to_char3);
PG_FUNCTION_INFO_V1(oratimestamp_to_char1);
PG_FUNCTION_INFO_V1(oratimestamp_to_char2);
PG_FUNCTION_INFO_V1(oratimestamp_to_char3);
PG_FUNCTION_INFO_V1(oratimestamptz_to_char1);
PG_FUNCTION_INFO_V1(oratimestamptz_to_char2);
PG_FUNCTION_INFO_V1(oratimestamptz_to_char3);
PG_FUNCTION_INFO_V1(oratimestampltz_to_char1);
PG_FUNCTION_INFO_V1(oratimestampltz_to_char2);
PG_FUNCTION_INFO_V1(oratimestampltz_to_char3);
PG_FUNCTION_INFO_V1(oradsinterval_to_char1);
PG_FUNCTION_INFO_V1(orayminterval_to_char1);
PG_FUNCTION_INFO_V1(to_yminterval);
PG_FUNCTION_INFO_V1(numtoyminterval);
PG_FUNCTION_INFO_V1(to_dsinterval);
PG_FUNCTION_INFO_V1(numtodsinterval);


#define CHECK_SEQ_SEARCH(_l, _s) \
do { \
	if ((_l) < 0) { \
		ereport(ERROR, \
				(errcode(ERRCODE_INVALID_DATETIME_FORMAT), \
				 errmsg("invalid value for %s", (_s)))); \
	} \
} while (0)

#define DATE2J(y,m,d)	(date2j((y),(m),(d)) - POSTGRES_EPOCH_JDATE)
#define J2DAY(date)	(j2day(date + POSTGRES_EPOCH_JDATE))

#define NOT_ROUND_MDAY(_p_) \
	do { if (_p_) rounded = false; } while(0)
#define ROUND_MDAY(_tm_) \
	do { if (rounded) _tm_->tm_mday += _tm_->tm_hour >= 12?1:0; } while(0)

	/* Note: this is used to copy pg_tm to fmt_tm, so not quite a bitwise copy */
#define COPY_tm(_DST, _SRC) \
	do {	\
		(_DST)->tm_sec = (_SRC)->tm_sec; \
		(_DST)->tm_min = (_SRC)->tm_min; \
		(_DST)->tm_hour = (_SRC)->tm_hour; \
		(_DST)->tm_mday = (_SRC)->tm_mday; \
		(_DST)->tm_mon = (_SRC)->tm_mon; \
		(_DST)->tm_year = (_SRC)->tm_year; \
		(_DST)->tm_wday = (_SRC)->tm_wday; \
		(_DST)->tm_yday = (_SRC)->tm_yday; \
		(_DST)->tm_gmtoff = (_SRC)->tm_gmtoff; \
	} while(0)

typedef struct WeekDays
{
	int			encoding;
	const char *names[7];
} WeekDays;

static const WeekDays WEEKDAYS[] =
{
	{ PG_UTF8,
	 {"\xe6\x98\x9f\xe6\x9c\x9f\xe6\x97\xa5",
	  "\xe6\x98\x9f\xe6\x9c\x9f\xe4\xb8\x80",
	  "\xe6\x98\x9f\xe6\x9c\x9f\xe4\xba\x8c",
	  "\xe6\x98\x9f\xe6\x9c\x9f\xe4\xb8\x89",
	  "\xe6\x98\x9f\xe6\x9c\x9f\xe5\x9b\x9b",
	  "\xe6\x98\x9f\xe6\x9c\x9f\xe4\xba\x94",
	  "\xe6\x98\x9f\xe6\x9c\x9f\xe5\x85\xad"
	 }
	},

	{ PG_GBK,
	 {"\320\307\306\332\310\325",
	  "\320\307\306\332\322\273",
	  "\320\307\306\332\266\376",
	  "\320\307\306\332\310\375",
	  "\320\307\306\332\313\304",
	  "\320\307\306\332\316\345",
	  "\320\307\306\332\301\371"
	 }
	}
};

static const int month_days[] = {
	31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 
};

const char *const ora_days[] = {"Sunday", "Monday", "Tuesday", "Wednesday",
"Thursday", "Friday", "Saturday", NULL};

#define CASE_fmt_YYYY	case 0: case 1: case 2: case 3: case 4: case 5: case 6:
#define CASE_fmt_IYYY	case 7: case 8: case 9: case 10:
#define	CASE_fmt_Q	case 11:
#define	CASE_fmt_WW	case 12:
#define CASE_fmt_IW	case 13:
#define	CASE_fmt_W	case 14:
#define CASE_fmt_DAY	case 15: case 16: case 17:
#define CASE_fmt_MON	case 18: case 19: case 20: case 21:
#define CASE_fmt_CC	case 22: case 23:
#define CASE_fmt_DDD	case 24: case 25: case 26:
#define CASE_fmt_HH	case 27: case 28: case 29:
#define CASE_fmt_MI	case 30: 

const char *const date_fmt[] =
{
	"Y", "Yy", "Yyy", "Yyyy", "Year", "Syyyy", "syear",
	"I", "Iy", "Iyy", "Iyyy",
	"Q", "Ww", "Iw", "W",
	"Day", "Dy", "D",
	"Month", "Mon", "Mm", "Rm",
	"Cc", "Scc",
	"Ddd", "Dd", "J",
	"Hh", "Hh12", "Hh24",
	"Mi",
	NULL
};

#define CASE_timezone_0		case 0:
#define CASE_timezone_3		case 1:
#define CASE_timezone_35	case 2:
#define CASE_timezone_4		case 3: case 4:
#define CASE_timezone_5		case 5: case 6:
#define CASE_timezone_6		case 7: case 8:
#define CASE_timezone_7		case 9: case 10:
#define CASE_timezone_8		case 11: case 12:
#define CASE_timezone_9		case 13: case 14:
#define CASE_timezone_10	case 15: case 16:
#define CASE_timezone_11	case 17:

const char *const date_timezone[] =
{
	"GMT", "ADT", "NST", "AST", "EDT", "CDT",
	"EST","CST", "MDT", "MST", "PDT", "PST",
	"YDT", "HDT", "YST", "BDT", "HST", "BST",
	NULL
};

static int64 sys_time_zone(void);
static int days_of_month(int y, int m);
static void tm_round(struct pg_tm *tm, text *fmt);
static Timestamp iso_year (int y, int m, int d);
static pg_tz *ora_make_timezone(char **newval);
static void tm_trunc(struct pg_tm *tm, text *fmt);
static int ora_seq_prefix_search(const char *name, const char *const array[], int max);
static int weekday_search(const WeekDays *weekdays, const char *str, int len);
static int ora_timezone_name_to_num(const char *name);

/*
 * sysdate returns the current date and time set for the operating
 * system on which the database server resides.
 *
 * The data type of the returned value is DATE, and the format returned
 * depends on the value of the NLS_DATE_FORMAT initialization parameter.
 */
Datum
sysdate(PG_FUNCTION_ARGS)
{
	TimestampTz timestamp = GetCurrentTimestamp();
	Timestamp	result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;
	int64 systimezone;

	systimezone = sys_time_zone();
	timestamp = timestamp + systimezone * 1000000;

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

/*
 * Returns the current date in the session time zone,
 * in a value in the Gregorian calendar of data type DATE.
 */
Datum
ora_current_date(PG_FUNCTION_ARGS)
{

	TimestampTz timestamp = GetCurrentTimestamp();
	Timestamp	result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;
	int			tz;

	if (timestamp2tm(timestamp, &tz, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
		
	if (tm2timestamp(tm, 0, NULL, &result) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
			errmsg("timestamp out of range")));

	PG_RETURN_TIMESTAMP(result);
}

/* 
 * Returns the current date and time in the session time zone, 
 * in a value of data type TIMESTAMP WITH TIME ZONE.
 */
Datum
ora_current_timestamp(PG_FUNCTION_ARGS)
{
	TimestampTz timestamp = GetCurrentTransactionStartTimestamp();
	int argsnum = PG_NARGS();
	if (argsnum == 1)
	{
		int n = PG_GETARG_INT32(0);
		if(n > MAX_TIMESTAMP_PRECISION && n <= ORACLE_MAX_TIMESTAMP_PRECISION)
		{
			ereport(WARNING,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				errmsg("TIMESTAMP(%d) effective number of fractional seconds is 6,the part of excess is 0",
				  n)));
			n = MAX_TIMESTAMP_PRECISION;
		}
		OraAdjustTimestampForTypmod((Timestamp *)&timestamp, n);
	}

	PG_RETURN_TIMESTAMPTZ(timestamp);
}

/* 
 * Returns the current date and time in the session time zone in a value of data type TIMESTAMP.
 */
Datum
ora_local_timestamp(PG_FUNCTION_ARGS)
{
	Timestamp timestamp = GetCurrentTransactionStartTimestamp();
	int argsnum = PG_NARGS();
	struct pg_tm tt,
				*tm = &tt;
	fsec_t		fsec;
	int			tz;
	const char *tzn;

	/* Apply session timezone */
	if (timestamp2tm(timestamp, &tz, tm, &fsec, &tzn, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	/* Convert to a timestamp data type */
	if (tm2timestamp(tm, fsec, NULL, &timestamp) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	if (argsnum == 1)
	{
		int n = PG_GETARG_INT32(0);
		if(n > MAX_TIMESTAMP_PRECISION && n <= ORACLE_MAX_TIMESTAMP_PRECISION)
		{
			ereport(WARNING,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				errmsg("TIMESTAMP(%d) effective number of fractional seconds is 6,the part of excess is 0",
				  n)));
			n = MAX_TIMESTAMP_PRECISION;
		}
		OraAdjustTimestampForTypmod((Timestamp *)&timestamp, n);
	}
	PG_RETURN_TIMESTAMP(timestamp);
}

/* 
 * Returns the date of the last day of the month that contains date. 
 * The return type is always DATE, regardless of the data type of date.
 */
Datum
last_day(PG_FUNCTION_ARGS)
{
	Timestamp time = PG_GETARG_TIMESTAMP(0);
	Timestamp	date;
	int y = 0, m = 0, d = 0; 
	int	last_day = 0;
	Timestamp result;
	
	TMODULO(time, date, USECS_PER_DAY);
	if (time < INT64CONST(0))
	{
		time += USECS_PER_DAY;
		date -= 1;
	}

	date += POSTGRES_EPOCH_JDATE;
	j2date((int)date, &y, &m, &d);
	last_day = days_of_month(y, m);

	result = date2j(y, m, last_day) - POSTGRES_EPOCH_JDATE;

	result = result * USECS_PER_DAY + time;

	PG_RETURN_TIMESTAMP(result);
}

/* 
 * Returns the date 'time' plus 'num' months.
 * The return type is always DATE, regardless of the data type of 'time'.
 */
Datum
add_months(PG_FUNCTION_ARGS)
{
	Timestamp time = PG_GETARG_TIMESTAMP(0);
	Timestamp	date;
	int y = 0, m = 0, d = 0; 
	int days;
	Timestamp result;
	div_t	v;
	bool	last_day;
	int64	n;
	Numeric		num = PG_GETARG_NUMERIC(1);

	n = DatumGetInt32(DirectFunctionCall1(numeric_int8, NumericGetDatum(num)));

	TMODULO(time, date, USECS_PER_DAY);
	if (time < INT64CONST(0))
	{
		time += USECS_PER_DAY;
		date -= 1;
	}

	date += POSTGRES_EPOCH_JDATE;
	j2date((int)date, &y, &m, &d);
	last_day = (d == days_of_month(y, m));

	v = div(y * 12 + m - 1 + n, 12);
	y = v.quot;
	if (y < 0)
		y += 1;
	m = v.rem + 1;

	days = days_of_month(y, m);
	if (last_day || d > days)
		d = days;

	result = date2j(y, m, d) - POSTGRES_EPOCH_JDATE;

	result = result * USECS_PER_DAY + time;

	PG_RETURN_TIMESTAMP(result);
}

/*
 * Returns the datetime type 'timestamp' rounded to the unit specified by the format model 'fmt'.
 */
Datum
ora_round(PG_FUNCTION_ARGS)
{
	fsec_t fsec;
	struct pg_tm tt, *tm = &tt;
	Timestamp timestamp = PG_GETARG_TIMESTAMP(0);
	Timestamp result;
	text *fmt = NULL;
	int argsnum = PG_NARGS();
	if(argsnum == 1)
		fmt = cstring_to_text("DDD");
	else
		fmt = PG_GETARG_TEXT_PP(1);

	if (TIMESTAMP_NOT_FINITE(timestamp))
		PG_RETURN_TIMESTAMPTZ(timestamp);

	if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
		ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

	tm_round(tm, fmt);

	if (tm2timestamp(tm, fsec, NULL, &result) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	PG_RETURN_TIMESTAMP(result);
}

/*
 * Returns 'timestamp' with the time portion of the day truncated
 * to the unit specified by the format model 'fmt'.
 */
Datum
ora_trunc(PG_FUNCTION_ARGS)
{
	Timestamp timestamp = PG_GETARG_TIMESTAMP(0);
	Timestamp result;
	text *fmt = NULL;
	fsec_t fsec;
	struct pg_tm tt, *tm = &tt;
	
	int argsnum = PG_NARGS();
	if(argsnum == 1)
		fmt = cstring_to_text("DDD");
	else
		fmt = PG_GETARG_TEXT_PP(1);

	if (TIMESTAMP_NOT_FINITE(timestamp))
		PG_RETURN_TIMESTAMPTZ(timestamp);

	if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
		ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

	tm_trunc(tm, fmt);
	fsec = 0;

	if (tm2timestamp(tm, fsec, NULL, &result) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	PG_RETURN_TIMESTAMP(result);
}

/* 
 * Internal implementation of Oracle's NEXT_DAY function.
 * First weekday specified by int type.
 */
Datum
next_day_by_index(PG_FUNCTION_ARGS)
{
	Timestamp day = PG_GETARG_TIMESTAMP(0);
	int		idx = PG_GETARG_INT32(1);
	Timestamp	date;
	int	off = 0;
	Timestamp result;

	CHECK_SEQ_SEARCH((idx < 1 || 7 < idx) ? -1 : 0, "DAY/Day/day");
	TMODULO(day, date, USECS_PER_DAY);
	if (day < INT64CONST(0))
	{
		day += USECS_PER_DAY;
		date -= 1;
	}
	date += POSTGRES_EPOCH_JDATE;

	/* j2day returns 0..6 as Sun..Sat */
	off = (idx - 1) - j2day((int)date);
	date = (off <= 0) ? date+off+7 : date + off;

	result = date - POSTGRES_EPOCH_JDATE;
	result = result * USECS_PER_DAY + day;

	PG_RETURN_TIMESTAMP(result);
}

/* 
 * Internal implementation of Oracle's NEXT_DAY function.
 * First weekday specified by character type.
 */
Datum
next_day(PG_FUNCTION_ARGS)
{
	Timestamp day = PG_GETARG_TIMESTAMP(0);
	text *day_txt = PG_GETARG_TEXT_PP(1);
	const char *str = VARDATA_ANY(day_txt);
	int len = VARSIZE_ANY_EXHDR(day_txt);
	char *changstr =NULL;
	int changstrlen =0;
	Timestamp date;
	int off = 0;
	Timestamp result;
	int d = -1;

	if (len >= 3 && (d = ora_seq_prefix_search(str, ora_days, 3)) >= 0)
		goto found;

	changstr = pg_server_to_any(str, len, PG_UTF8);
	changstrlen = strlen(changstr);

	if ((d = weekday_search(&WEEKDAYS[0], changstr, changstrlen)) >= 0)
		goto found;
				
	CHECK_SEQ_SEARCH(-1, "DAY/Day/day");

found:
	TMODULO(day, date, USECS_PER_DAY);
	if (day < INT64CONST(0))
	{
		day += USECS_PER_DAY;
		date -= 1;
	}
	date += POSTGRES_EPOCH_JDATE;

	/* j2day returns 0..6 as Sun..Sat */
	off = d - j2day((int)date);
	date = (off <= 0) ? date+off+7 : date + off;

	result = date - POSTGRES_EPOCH_JDATE;
	result = result * USECS_PER_DAY + day;

	PG_RETURN_TIMESTAMP(result);
}

/*
 * Returns the date and time in time zone 'txtimezone2'
 * when date and time in time zone 'txtimezone1' are date 'day'.
 *
 * The return type is always DATE.
 */
Datum
ora_new_time(PG_FUNCTION_ARGS)
{
	Timestamp day = PG_GETARG_TIMESTAMP(0);
	text *txtimezone1 = PG_GETARG_TEXT_PP(1);
	text *txtimezone2 = PG_GETARG_TEXT_PP(2);

	char *strtimezone1 = text_to_cstring(txtimezone1);
	char *strtimezone2 = text_to_cstring(txtimezone2);
	Timestamp result;
	struct pg_tm tt,
				*tm = &tt;
	fsec_t		fsec;
	int			tz1;
	int			tz2;
	
	if((tz1 = ora_timezone_name_to_num(strtimezone1)) == -1)
	{
		ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("Invalid time zone")));
	}

	if((tz2 = ora_timezone_name_to_num(strtimezone2)) == -1)
	{
		ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("Invalid time zone")));
	}
	if (timestamp2tm(day, NULL, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));
	tz1 = tz1 - tz2;
	tm2timestamp(tm, fsec, &tz1, &result);

	PG_RETURN_TIMESTAMP(result);
}

/*
 * Returns the time zone offset corresponding to the
 * argument based on the date the statement is executed.
 */
Datum
ora_tz_offset(PG_FUNCTION_ARGS)
{
	text	*res;
	bool ispositive = true;
	pg_tz *timezonedat;
	struct pg_tm tt,
				*tm = &tt;
	fsec_t		fsec;
	int64			tz;
	int hourdat,mindate;
	char *reschar = (char *) palloc(8);
	text *txtimezone1 = PG_GETARG_TEXT_PP(0);

	char *strtimezone1 = text_to_cstring(txtimezone1);
	TimestampTz timestamp = GetCurrentTimestamp();

	/* to get pg_tz struct data of char */
	if((timezonedat = ora_make_timezone(&strtimezone1)) == NULL)
	{
		ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timezone is not ok")));
	}

	if (timestamp2tm(timestamp, NULL, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

	tz = DetermineTimeZoneOffset(tm, timezonedat);
	if(tz <= 0)
	{
		tz = tz * (-1);
		ispositive = false;
	}
	hourdat = tz / 3600;
	mindate = (tz - hourdat*3600) / 60;

	snprintf(reschar,8,"%s%02d:%02d",ispositive ? "-":"+",hourdat,mindate);

	res = cstring_to_text(reschar);

	PG_RETURN_TEXT_P(res);
}

/* 
 * Returns number of months between dates 'time1' and 'time2'.
 */
Datum
months_between(PG_FUNCTION_ARGS)
{
	Timestamp time1 = PG_GETARG_TIMESTAMP(0);
	Timestamp time2 = PG_GETARG_TIMESTAMP(1);

	Timestamp date1;
	Timestamp date2;

	int y1, m1, d1;
	int y2, m2, d2;

	float8 result;

	TMODULO(time1, date1, USECS_PER_DAY);
	if (time1 < INT64CONST(0))
	{
		time1 += USECS_PER_DAY;
		date1 -= 1;
	}
	TMODULO(time2, date2, USECS_PER_DAY);
	if (time2 < INT64CONST(0))
	{
		time2 += USECS_PER_DAY;
		date2 -= 1;
	}

	date1 += POSTGRES_EPOCH_JDATE;
	j2date((int)date1, &y1, &m1, &d1);

	date2 += POSTGRES_EPOCH_JDATE;
	j2date((int)date2, &y2, &m2, &d2);

	/* Ignore day components for last days, or based on a 31-day month. */
	if (d1 == days_of_month(y1, m1) && d2 == days_of_month(y2, m2))
		result = (y1 - y2) * 12 + (m1 - m2);
	else
	{
		result = (y1 - y2) * 12 + (m1 - m2) + (d1 - d2) / 31.0;
		/* If the days are different, you need to compare the time difference */
		if(d1 != d2)
			result += ((time1 - time2) / 31.0) / USECS_PER_DAY;
	}
	PG_RETURN_FLOAT8(result);
}

/*
 * Converts a timestamp value and a time zone to a TIMESTAMP WITH TIME ZONE value.
 */
Datum
ora_from_tz(PG_FUNCTION_ARGS)
{
	Timestamp day = PG_GETARG_TIMESTAMP(0);
	text *day_txt = PG_GETARG_TEXT_PP(1);
	TimestampTz result;
	struct pg_tm tt,
				*tm = &tt;
	pg_tz *timezonedat;
	char *day_char = text_to_cstring(day_txt);
	fsec_t		fsec;
	int			tz;

	if((timezonedat = ora_make_timezone(&day_char)) == NULL)
	{
		ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timezone is not ok")));
	}

	if (timestamp2tm(day, NULL, tm, &fsec, NULL, NULL) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("timestamp out of range")));

	tz = DetermineTimeZoneOffset(tm, timezonedat);
	tm2timestamp(tm, fsec, &tz, &result);

	PG_RETURN_TIMESTAMPTZ(result);
}

/*
 * Extracts the UTC(Coordinated Universal Time--formerly Greenwich Mean Time) 
 * from a datetime value with time zone offset or time zone region name.
 */
Datum
ora_sys_extract_utc(PG_FUNCTION_ARGS)
{
	TimestampTz timestamp = PG_GETARG_TIMESTAMP(0);
	Timestamp result = timestamp;

	PG_RETURN_TIMESTAMP(result);
}

/*
 * returns the time zone of the current session.
 */
Datum
ora_sessiontimezone(PG_FUNCTION_ARGS)
{
	char	*res;
	text	*out;

	res = (char *)pg_get_timezone_name(session_timezone);
	out = cstring_to_text(res);

	PG_RETURN_TEXT_P(out);
}

/*
 * Compatible with Oracle's to_date() function.
 *
 * Converts 'date_txt' to a value of DATE data type.
 */
Datum
to_oradate1(PG_FUNCTION_ARGS)
{
	text		*date_txt = PG_GETARG_TEXT_P(0);
	Oid		collid = PG_GET_COLLATION();
	Timestamp	result;
	struct pg_tm tm;
	fsec_t		fsec;

	ora_do_to_timestamp(date_txt, cstring_to_text(nls_date_format), collid, false, &tm, &fsec, NULL, NULL, NULL, true);

	/* no timezone and no fractional second */
	fsec = 0;
	if (tm2timestamp(&tm, fsec, NULL, &result) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("oradate out of range")));

	PG_RETURN_TIMESTAMP(result);
}

Datum
to_oradate2(PG_FUNCTION_ARGS)
{
	text		*date_txt = PG_GETARG_TEXT_P(0);
	text		*fmt = PG_GETARG_TEXT_P(1);
	Oid		collid = PG_GET_COLLATION();
	Timestamp	result;
	struct pg_tm tm;
	fsec_t		fsec;

	ora_do_to_timestamp(date_txt, fmt, collid, false, &tm, &fsec, NULL, NULL, NULL, true);

	/* no timezone and no fractional second */
	fsec = 0;
	if (tm2timestamp(&tm, fsec, NULL, &result) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("oradate out of range")));

	PG_RETURN_TIMESTAMP(result);
}

Datum
to_oradate3(PG_FUNCTION_ARGS)
{
	text	   *date_txt = PG_GETARG_TEXT_P(0);
	text	   *fmt = PG_GETARG_TEXT_P(1);
	text	   *nlsparam = PG_GETARG_TEXT_P(2);
	Oid		    collid = PG_GET_COLLATION();
	Timestamp	result;
	struct pg_tm tm;
	fsec_t		fsec;

	/* TODO */
	char	*p;
	p = text_to_cstring(nlsparam);

#if 0
	if (strlen(p) != 0)
		ereport(WARNING,
				(errcode(ERRCODE_UNTERMINATED_C_STRING),
				 errmsg("function \"to_date\" not support the parameter of \"nlsparam\".")));
#endif

	if (p && strlen(p) != 0)
	/* make compiler quiet */

	ora_do_to_timestamp(date_txt, fmt, collid, false, &tm, &fsec, NULL, NULL, NULL, true);

	/* no timezone and no fractional second */
	fsec = 0;
	if (tm2timestamp(&tm, fsec, NULL, &result) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("oradate out of range")));

	PG_RETURN_TIMESTAMP(result);
}

/*
 * Compatible with Oracle's to_timestamp() function.
 *
 * Converts 'date_txt' to a value of TIMESTAMP data type.
 */
Datum
to_oratimestamp1(PG_FUNCTION_ARGS)
{
	text	   *date_txt = PG_GETARG_TEXT_P(0);
	Oid		collid = PG_GET_COLLATION();
	Timestamp	result;
	struct pg_tm tm;
	fsec_t		fsec;

	ora_do_to_timestamp(date_txt, cstring_to_text(nls_timestamp_format), collid, false, &tm, &fsec, NULL, NULL, NULL, true);

	/* no time zone */
	if (tm2timestamp(&tm, fsec, NULL, &result) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	PG_RETURN_TIMESTAMP(result);
}

Datum
to_oratimestamp2(PG_FUNCTION_ARGS)
{
	text	   *date_txt = PG_GETARG_TEXT_P(0);
	text	   *fmt = PG_GETARG_TEXT_P(1);
	Oid		collid = PG_GET_COLLATION();
	Timestamp	result;
	struct pg_tm tm;
	fsec_t		fsec;

	ora_do_to_timestamp(date_txt, fmt, collid, false, &tm, &fsec, NULL, NULL, NULL, true);

	/* no time zone */
	if (tm2timestamp(&tm, fsec, NULL, &result) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	PG_RETURN_TIMESTAMP(result);
}

Datum
to_oratimestamp3(PG_FUNCTION_ARGS)
{
	text	   *date_txt = PG_GETARG_TEXT_P(0);
	text	   *fmt = PG_GETARG_TEXT_P(1);
	text	   *nlsparam = PG_GETARG_TEXT_P(2);
	Oid		collid = PG_GET_COLLATION();
	Timestamp	result;
	struct pg_tm tm;
	fsec_t		fsec;
	char	*p;
	p = text_to_cstring(nlsparam);

	/*
	if (strlen(p) != 0)
		ereport(WARNING,
				(errcode(ERRCODE_UNTERMINATED_C_STRING),
				 errmsg("function \"to_date\" not support the parameter of \"nlsparam\".")));
	*/
	if (p && strlen(p) != 0)
	/* make compiler quiet */

	ora_do_to_timestamp(date_txt, fmt, collid, false, &tm, &fsec, NULL, NULL, NULL, true);

	/* no time zone */
	if (tm2timestamp(&tm, fsec, NULL, &result) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	PG_RETURN_TIMESTAMP(result);
}

/*
 * Compatible with Oracle's to_timestamp_tz() function.
 *
 * Converts 'date_txt' to a value of TIMESTAMP WITH TIME ZONE data type.
 */
Datum
to_oratimestamptz1(PG_FUNCTION_ARGS)
{
	text	   *date_txt = PG_GETARG_TEXT_P(0);
	Oid		collid = PG_GET_COLLATION();
	Timestamp	result;
	int			tz;
	struct pg_tm tm;
	fsec_t		fsec;
	DateTimeErrorExtra extra;

	ora_do_to_timestamp(date_txt, cstring_to_text(nls_timestamp_tz_format), collid, false, &tm, &fsec, NULL, NULL, NULL, true);

	if (tm.tm_zone)
	{
		int dterr = DecodeTimezone((char *)tm.tm_zone, &tz);

		if (dterr)
			DateTimeParseError(dterr, &extra, text_to_cstring(date_txt), "timestamptz", NULL);
	}
	else
		tz = DetermineTimeZoneOffset(&tm, session_timezone);

	if (tm2timestamp(&tm, fsec, &tz, &result) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("oratimestamptz out of range")));

	PG_RETURN_TIMESTAMP(result);
}
 
Datum
to_oratimestamptz2(PG_FUNCTION_ARGS)
{
	text	   *date_txt = PG_GETARG_TEXT_P(0);
	text	   *fmt = PG_GETARG_TEXT_P(1);
	Oid		collid = PG_GET_COLLATION();
	Timestamp	result;
	int			tz;
	struct pg_tm tm;
	fsec_t		fsec;
	DateTimeErrorExtra extra;

	ora_do_to_timestamp(date_txt, fmt, collid, false, &tm, &fsec, NULL, NULL, NULL, true);

	if (tm.tm_zone)
	{
		int			dterr = DecodeTimezone((char *)tm.tm_zone, &tz);

		if (dterr)
			DateTimeParseError(dterr, &extra, text_to_cstring(date_txt), "timestamptz", NULL);
	}
	else
		tz = DetermineTimeZoneOffset(&tm, session_timezone);

#if 0
	if(tm.tm_gmtoff == -1)
	{
		tm.tm_gmtoff = 0;
		tz = DetermineTimeZoneOffset(&tm, session_timezone);
	}
	else
		tz = (int)tm.tm_gmtoff * (-1);
#endif

	if (tm2timestamp(&tm, fsec, &tz, &result) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("oratimestamptz out of range")));

	PG_RETURN_TIMESTAMP(result);
}

Datum
to_oratimestamptz3(PG_FUNCTION_ARGS)
{
	text	   *date_txt = PG_GETARG_TEXT_P(0);
	text	   *fmt = PG_GETARG_TEXT_P(1);
	text	   *nlsparam = PG_GETARG_TEXT_P(2);
	Oid		collid = PG_GET_COLLATION();
	Timestamp	result;
	int			tz;
	struct pg_tm tm;
	fsec_t		fsec;
	DateTimeErrorExtra extra;
	char	*p;
	p = text_to_cstring(nlsparam);

	if (p && strlen(p) != 0)
	/* make compile quiet */

	/*
	if (strlen(p) != 0)
		ereport(WARNING,
				(errcode(ERRCODE_UNTERMINATED_C_STRING),
				 errmsg("function \"to_date\" not support the parameter of \"nlsparam\".")));
	*/

	ora_do_to_timestamp(date_txt, fmt, collid, false, &tm, &fsec, NULL, NULL, NULL, true);

	if (tm.tm_zone)
	{
		int 	dterr = DecodeTimezone((char *)tm.tm_zone, &tz);

		if (dterr)
			DateTimeParseError(dterr, &extra, text_to_cstring(date_txt), "timestamptz", NULL);
	}
	else
		tz = DetermineTimeZoneOffset(&tm, session_timezone);

	if (tm2timestamp(&tm, fsec, &tz, &result) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("oratimestamptz out of range")));

	PG_RETURN_TIMESTAMP(result);
}

/*
 * Compatible with Oracle's TO_CHAR(DATETIME) function.
 *
 * Converts a DATETIME or INTERVAL data type to a value of VARCHAR2 data 
 * type in the format specified by the date format fmt.
 */
Datum
oradate_to_char1(PG_FUNCTION_ARGS)
{
	Timestamp	dt = PG_GETARG_TIMESTAMP(0);
	VarChar	*res;

	res = DatumGetVarCharP(DirectFunctionCall2(timestamp_to_char,
							TimestampGetDatum(dt),
							PointerGetDatum(cstring_to_text(nls_date_format))));

	PG_RETURN_VARCHAR_P(res);
}

Datum
oradate_to_char2(PG_FUNCTION_ARGS)
{
	Timestamp	dt = PG_GETARG_TIMESTAMP(0);
	text	   *fmt = PG_GETARG_TEXT_P(1);
	VarChar	*res;

	res = DatumGetVarCharP(DirectFunctionCall2(timestamp_to_char,
							TimestampGetDatum(dt),
							PointerGetDatum(fmt)));

	PG_RETURN_VARCHAR_P(res);
}

Datum
oradate_to_char3(PG_FUNCTION_ARGS)
{
	Timestamp	dt = PG_GETARG_TIMESTAMP(0);
	text	   *fmt = PG_GETARG_TEXT_P(1);
	VarChar	   *res;

	/*
	ereport(WARNING,
			(errcode(ERRCODE_UNTERMINATED_C_STRING),
			 errmsg("function \"to_char\" not support the parameter of \"nlsparam\".")));
	*/

	res = DatumGetVarCharP(DirectFunctionCall2(timestamp_to_char,
							TimestampGetDatum(dt),
							PointerGetDatum(fmt)));

	PG_RETURN_VARCHAR_P(res);
}

Datum
oratimestamp_to_char1(PG_FUNCTION_ARGS)
{
	Timestamp	dt = PG_GETARG_TIMESTAMP(0);
	text	   *fmt = cstring_to_text(nls_timestamp_format),
			   *res;
	TmToChar	tmtc;
	struct pg_tm pgtm;
	struct pg_tm *tm;

	int			thisdate;
	VarChar	   *vres;

	if ((VARSIZE(fmt) - VARHDRSZ) <= 0 || TIMESTAMP_NOT_FINITE(dt))
		PG_RETURN_NULL();

	ORA_ZERO_tmtc(&tmtc);
	tm = &pgtm;
	ORA_ZERO_tm(tm);

	if (timestamp2tm(dt, NULL, tm, &tmtcFsec(&tmtc), NULL, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	thisdate = date2j(tm->tm_year, tm->tm_mon, tm->tm_mday);
	tm->tm_wday = (thisdate + 1) % 7;
	tm->tm_yday = thisdate - date2j(tm->tm_year, 1, 1) + 1;

	COPY_tm(tmtcTm(&tmtc), tm);
	if (!(res = datetime_to_char_body(&tmtc, fmt, false, PG_GET_COLLATION())))
		PG_RETURN_NULL();

	vres = (VarChar *)res;
	PG_RETURN_VARCHAR_P(vres);
}

Datum
oratimestamp_to_char2(PG_FUNCTION_ARGS)
{
	Timestamp	dt = PG_GETARG_TIMESTAMP(0);
	text	   *fmt = PG_GETARG_TEXT_P(1),
			   *res;
	TmToChar	tmtc;
	struct pg_tm pgtm;
	struct pg_tm *tm;
	int			thisdate;
	VarChar	   *vres;

	if ((VARSIZE(fmt) - VARHDRSZ) <= 0 || TIMESTAMP_NOT_FINITE(dt))
		PG_RETURN_NULL();

	ORA_ZERO_tmtc(&tmtc);
	ORA_ZERO_tm(&pgtm);
	tm = &pgtm;

	if (timestamp2tm(dt, NULL, tm, &tmtcFsec(&tmtc), NULL, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	thisdate = date2j(tm->tm_year, tm->tm_mon, tm->tm_mday);
	tm->tm_wday = (thisdate + 1) % 7;
	tm->tm_yday = thisdate - date2j(tm->tm_year, 1, 1) + 1;

	COPY_tm(tmtcTm(&tmtc), tm);
	if (!(res = datetime_to_char_body(&tmtc, fmt, false, PG_GET_COLLATION())))
		PG_RETURN_NULL();

	vres = (VarChar *)res;
	PG_RETURN_VARCHAR_P(vres);
}

Datum
oratimestamp_to_char3(PG_FUNCTION_ARGS)
{
	Timestamp	dt = PG_GETARG_TIMESTAMP(0);
	text	   *fmt = PG_GETARG_TEXT_P(1),
			   *res;
	TmToChar	tmtc;
	struct pg_tm pgtm;
	struct pg_tm *tm;
	int			thisdate;
	VarChar	   *vres;

	if ((VARSIZE(fmt) - VARHDRSZ) <= 0 || TIMESTAMP_NOT_FINITE(dt))
		PG_RETURN_NULL();

	ORA_ZERO_tmtc(&tmtc);
	ORA_ZERO_tm(&pgtm);
	tm = &pgtm;

	if (timestamp2tm(dt, NULL, tm, &tmtcFsec(&tmtc), NULL, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	thisdate = date2j(tm->tm_year, tm->tm_mon, tm->tm_mday);
	tm->tm_wday = (thisdate + 1) % 7;
	tm->tm_yday = thisdate - date2j(tm->tm_year, 1, 1) + 1;

	COPY_tm(tmtcTm(&tmtc), tm);
	if (!(res = datetime_to_char_body(&tmtc, fmt, false, PG_GET_COLLATION())))
		PG_RETURN_NULL();

	vres = (VarChar *)res;
	PG_RETURN_VARCHAR_P(vres);
}

Datum
oratimestamptz_to_char1(PG_FUNCTION_ARGS)
{
	TimestampTz dt = PG_GETARG_TIMESTAMP(0);
	VarChar	*res;

	res = DatumGetVarCharP(DirectFunctionCall2(timestamptz_to_char,
							TimestampGetDatum(dt),
							PointerGetDatum(cstring_to_text(nls_timestamp_tz_format))));

	PG_RETURN_VARCHAR_P(res);
}

Datum
oratimestamptz_to_char2(PG_FUNCTION_ARGS)
{
	TimestampTz dt = PG_GETARG_TIMESTAMP(0);
	text	   *fmt = PG_GETARG_TEXT_P(1);
	VarChar *res;
	res = DatumGetVarCharP(DirectFunctionCall2(timestamptz_to_char,
							TimestampGetDatum(dt),
							PointerGetDatum(fmt)));
	PG_RETURN_VARCHAR_P(res);
}

Datum
oratimestamptz_to_char3(PG_FUNCTION_ARGS)
{
	TimestampTz dt = PG_GETARG_TIMESTAMP(0);
	text	   *fmt = PG_GETARG_TEXT_P(1);
	VarChar	   *res;

	/*
	ereport(WARNING,
			(errcode(ERRCODE_UNTERMINATED_C_STRING),
			 errmsg("function \"to_char\" not support the parameter of \"nlsparam\".")));
	*/

	res = DatumGetVarCharP(DirectFunctionCall2(timestamptz_to_char,
							TimestampGetDatum(dt),
							PointerGetDatum(fmt)));
	PG_RETURN_VARCHAR_P(res);
}

Datum
oratimestampltz_to_char1(PG_FUNCTION_ARGS)
{
	TimestampTz dt = PG_GETARG_TIMESTAMP(0);
	text	*res;
	
	res = DatumGetTextP(DirectFunctionCall2(timestamptz_to_char,
						TimestampGetDatum(dt),
						PointerGetDatum(cstring_to_text(nls_timestamp_format))));
	
	PG_RETURN_VARCHAR_P(res);
}

Datum
oratimestampltz_to_char2(PG_FUNCTION_ARGS)
{
	TimestampTz dt = PG_GETARG_TIMESTAMP(0);
	text	   *fmt = PG_GETARG_TEXT_P(1);
	text	*res;
	res = DatumGetTextP(DirectFunctionCall2(timestamptz_to_char,
						TimestampGetDatum(dt),
						PointerGetDatum(fmt)));
	
	PG_RETURN_VARCHAR_P(res);
}

Datum
oratimestampltz_to_char3(PG_FUNCTION_ARGS)
{
	TimestampTz dt = PG_GETARG_TIMESTAMP(0);
	text	   *fmt = PG_GETARG_TEXT_P(1);
	text	*res;

	/*
	ereport(WARNING,
			(errcode(ERRCODE_UNTERMINATED_C_STRING),
			 errmsg("function \"to_char\" not support the parameter of \"nlsparam\".")));
	*/

	res = DatumGetTextP(DirectFunctionCall2(timestamptz_to_char,
						TimestampGetDatum(dt),
						PointerGetDatum(fmt)));
	
	PG_RETURN_VARCHAR_P(res);
}

Datum
oradsinterval_to_char1(PG_FUNCTION_ARGS)
{
	Interval   *intervaldate = PG_GETARG_INTERVAL_P(0);
	text	*res;
	char *aa;
	VarChar	*vres;
	aa = DatumGetCString(DirectFunctionCall1(dsinterval_out,
						 IntervalPGetDatum(intervaldate)));

	res = cstring_to_text(aa);
	vres = (VarChar *)res;
	PG_RETURN_VARCHAR_P(vres);
}

Datum
orayminterval_to_char1(PG_FUNCTION_ARGS)
{
	Interval   *intervaldate = PG_GETARG_INTERVAL_P(0);
	text	*res;
	char *aa;
	VarChar	*vres;
	aa = DatumGetCString(DirectFunctionCall1(yminterval_out,
						 IntervalPGetDatum(intervaldate)));

	res = cstring_to_text(aa);
	vres = (VarChar *)res;
	PG_RETURN_VARCHAR_P(vres);
}

/* 
 * Compatible oracle 'TO_YMINTERVAL' function.
 */
Datum
to_yminterval(PG_FUNCTION_ARGS)
{
	text	*interval_txt = PG_GETARG_TEXT_P(0);
	char	*interval_str;
	int32	typmod;
	Interval   *result;

	typmod = INTERVAL_TYPMOD(ORACLE_MAX_INTERVAL_PRECISION, INTERVAL_MASK(YEAR) | INTERVAL_MASK(MONTH));
	interval_str = text_to_cstring(interval_txt);

	result = DatumGetIntervalP(DirectFunctionCall3(yminterval_in, 
												   CStringGetDatum(interval_str), 
												   ObjectIdGetDatum(InvalidOid),
												   Int32GetDatum(typmod)));

	PG_RETURN_INTERVAL_P(result);
}

/* 
 * Compatible oracle 'NUMTOYMINTERVAL' function
 *
 * if 'interval_unit' is 'month' then do round() according to
 * the first place after the decimal point.
 *
 * if 'interval_unit' is 'year' then 'interval_val' multiply 12 and
 * do round() according to the first place after the decimal point.
 *  
 */
Datum
numtoyminterval(PG_FUNCTION_ARGS)
{
	float8	interval_val = PG_GETARG_FLOAT8(0);
	text	*interval_unit = PG_GETARG_TEXT_P(1);
	char	*interval_unit_str;
	int		interval_unit_len = 0;
	Interval   *result;

	interval_unit_str = text_to_cstring(interval_unit);

	/* Compatible Oracle: drop leading/trailing whitespace */
	while (*interval_unit_str && isspace((unsigned char) *interval_unit_str))
		interval_unit_str++;

	interval_unit_len = strlen(interval_unit_str);
	while (interval_unit_len > 0 && isspace((unsigned char) interval_unit_str[interval_unit_len - 1]))
		interval_unit_len--;

	interval_unit_str[interval_unit_len] = '\0';

	if (pg_strcasecmp(interval_unit_str, "year") == 0)
	{
		interval_val *= MONTHS_PER_YEAR;
	}
	else if (pg_strcasecmp(interval_unit_str, "month") == 0)
	{
		/* do nothing */
	}
	else
	{
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("illegal argument for function numtoyminterval")));
	}

	/* positive */
	if (interval_val > 0)
	{
		if( interval_val < 0.01)
			interval_val = 0;
		
		if(interval_val >= 0.01 && interval_val < 1)
			interval_val = 1;
	}

	/* negative */
	if (interval_val < 0)
	{
		if (interval_val > -0.5 && interval_val < 0)
			interval_val = 0;
		
		if (interval_val <= -0.5 && interval_val > -1)
			interval_val = 1;
	}

	/* round to first place after the decimal point */
	if (interval_val > 0)
		interval_val = ((int)(interval_val*10) + 5) / 10;

	if (interval_val < 0)
	{
		interval_val = interval_val * (-1);
		interval_val = ((int)(interval_val*10) + 5) / 10;
		interval_val = interval_val * (-1);
	}

	result = (Interval *) palloc(sizeof(Interval));

	result->month = interval_val;
	result->day = 0;
	result->time = 0;
	
	PG_RETURN_INTERVAL_P(result);
}

/* 
 * Compatible oracle TO_DSINTERVAL function.
 */
Datum
to_dsinterval(PG_FUNCTION_ARGS)
{
	text	*interval_txt = PG_GETARG_TEXT_P(0);
	char	*interval_str;
	int32	typmod;
	Interval   *result;

	typmod = INTERVAL_DS_TYPMOD(ORACLE_MAX_INTERVAL_PRECISION,
								ORACLE_MAX_INTERVAL_PRECISION,
								(INTERVAL_MASK(DAY) |
								 INTERVAL_MASK(HOUR) |
								 INTERVAL_MASK(MINUTE) |
								 INTERVAL_MASK(SECOND)));

	interval_str = text_to_cstring(interval_txt);

	result = DatumGetIntervalP(DirectFunctionCall3(dsinterval_in,
												   CStringGetDatum(interval_str),
												   ObjectIdGetDatum(InvalidOid),
												   Int32GetDatum(typmod)));

	PG_RETURN_INTERVAL_P(result);
}

/* 
 * Compatible oracle 'NUMTODSINTERVAL' function
 */
Datum
numtodsinterval(PG_FUNCTION_ARGS)
{
	float8	interval_val = PG_GETARG_FLOAT8(0);
	text	*interval_unit = PG_GETARG_TEXT_P(1);
	char	*interval_unit_str;
	int		interval_unit_len = 0;
	Interval   *result;

	interval_unit_str = text_to_cstring(interval_unit);

	/* Compatible Oracle: drop leading/trailing whitespace */
	while (*interval_unit_str && isspace((unsigned char) *interval_unit_str))
		interval_unit_str++;

	interval_unit_len = strlen(interval_unit_str);
	while (interval_unit_len > 0 && isspace((unsigned char) interval_unit_str[interval_unit_len - 1]))
		interval_unit_len--;

	interval_unit_str[interval_unit_len] = '\0';

	if (pg_strcasecmp(interval_unit_str, "day") == 0)
	{
		interval_val *= USECS_PER_DAY;
	}
	else if (pg_strcasecmp(interval_unit_str, "hour") == 0)
	{
		interval_val *= USECS_PER_HOUR;
	}
	else if (pg_strcasecmp(interval_unit_str, "minute") == 0)
	{
		interval_val *= USECS_PER_MINUTE;
	}
	else if (pg_strcasecmp(interval_unit_str, "second") == 0)
	{
		interval_val *= USECS_PER_SEC;
	}
	else
	{
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("illegal argument for function numtoyminterval")));
	}

	result = (Interval *) palloc(sizeof(Interval));

	result->month = 0;
	result->day = (int)(interval_val / USECS_PER_DAY);
	result->time = (interval_val - ((int)(interval_val / USECS_PER_DAY)) * USECS_PER_DAY);

	PG_RETURN_INTERVAL_P(result);
}

static pg_tz *
ora_make_timezone(char **newval)
{
	pg_tz	   *new_tz;
	long		gmtoffset;
	int			hours = 0;
	int			minu = 0;
	int 		res = 0;

	/*
	 * Try it as a numeric number of hours (possibly fractional).
	 */
	res = sscanf(*newval,"%d:%d",&hours,&minu);
	if(res == 2)
	{
		if(hours < -12 || hours >14)
			ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				errmsg("timezone hour between -12 and 14")));
		if(minu < 0 || minu > 59 || (hours == 14 && minu > 0))
			ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					errmsg("timezone minute between 0 and 59")));
		if(hours < 0)
			minu *= -1;
		gmtoffset = -(hours * SECS_PER_HOUR + minu * SECS_PER_MINUTE);
		new_tz = pg_tzset_offset(gmtoffset);
	}
	else
	{
		if(res > 0)
			ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					errmsg("timezone type is error")));
		/*
		* Otherwise assume it is a timezone name, and try to load it.
		*/
		new_tz = pg_tzset(*newval);
		if (!new_tz)
		{
			/* Doesn't seem to be any great value in errdetail here */
			return NULL;
		}

		if (!pg_tz_acceptable(new_tz))
		{
			ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					errmsg("time zone \"%s\" appears to use leap seconds",
							*newval)));
		}
	}

	/* Test for failure in pg_tzset_offset, which we assume is out-of-range */
	if (!new_tz)
	{
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("UTC timezone offset is out of range.")));
	}
	/*
	 * Pass back data for assign_timezone to use
	 */
	return new_tz;
}

/*
 * Make a timestamp according to the year, month and day.
 */
static Timestamp
iso_year (int y, int m, int d)
{
	Timestamp result, result2, day;
	int off;

	result = DATE2J(y,1,1);
	day = DATE2J(y,m,d);
	off = 4 - J2DAY(result);
	result += off + ((off >= 0) ? - 3: + 4);  // to monday
	if (result > day)
	{
		result = DATE2J(y-1,1,1);
		off = 4 - J2DAY(result);
		result += off + ((off >= 0) ? - 3: + 4);  // to monday
	}

	if (((day - result) / 7 + 1) > 52)
	{
		result2 = DATE2J(y+1,1,1);
		off = 4 - J2DAY(result2);
		result2 += off + ((off >= 0) ? - 3: + 4);  // to monday
		if (day >= result2)
			return result2;
	}

	return result;
}

/*
 * Get the timezone value of the operating system.
 */
static int64
sys_time_zone()
{

#ifdef _WIN64 
	size_t a;
	char time_zone[128];
	long diff_secs;
	_get_tzname(&a, time_zone, 128, 0);
	_get_timezone(&diff_secs);
	return (int64)diff_secs * (-1);
#else  
	struct tm *gmt;
	time_t t;	
	t = time(NULL);	
	gmt = localtime(&t);
	return (int64)gmt->tm_gmtoff;
#endif  
}

/*
 * Returns the number of days in the corresponding year and month.
 */
static int
days_of_month(int y, int m)
{
	int		days;

	if (m < 0 || 12 < m)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("date out of range")));

	days = month_days[m - 1];
	if (m == 2 && (y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)))
		days += 1;	/* February 29 in leap year */
	return days;
}

static int
ora_seq_search(const char *name, const char *const array[], int max)
{
	int		i;

	if (!*name)
		return -1;

	for (i = 0; array[i]; i++)
	{
		if (strlen(array[i]) == max &&
			pg_strncasecmp(name, array[i], max) == 0)
			return i;
	}
	return -1;	/* not found */
}

static Timestamp
ora_date_round(Timestamp day, int f)
{
	int y, m, d, z;
	Timestamp result;

	j2date(day + POSTGRES_EPOCH_JDATE, &y, &m, &d);

	switch (f)
	{
		CASE_fmt_CC
			if (y > 0)
				result = DATE2J((y/100)*100+(day < DATE2J((y/100)*100+50,1,1) ?1:101),1,1);
			else
				result = DATE2J((y/100)*100+(day < DATE2J((y/100)*100-50+1,1,1) ?-99:1),1,1);
			break;
		CASE_fmt_YYYY
			result = DATE2J(y+(day<DATE2J(y,7,1)?0:1),1,1);
			break;
		CASE_fmt_IYYY
			{
				if (day < DATE2J(y,7,1))
				{
					result = iso_year(y, m, d);
				}
				else
				{
					Timestamp iy1 = iso_year(y+1, 1, 8);
					result = iy1;

					if (((day - DATE2J(y,1,1)) / 7 + 1) >= 52)
					{
						bool overl = ((date2j(y+2,1,1)-date2j(y+1,1,1)) == 366);
						bool isSaturday = (J2DAY(day) == 6);

						Timestamp iy2 = iso_year(y+2, 1, 8);
						Timestamp day1 = DATE2J(y+1,1,1);
						// exception saturdays 
						if (iy1 >= (day1) && day >= day1 - 2 && isSaturday)
						{
							result = overl?iy2:iy1;
						}
						// iso year stars in last year and day >= iso year 
						else if (iy1 <= (day1) && day >= iy1 - 3)
						{
							Timestamp cmp = iy1 - (iy1 < day1?0:1);
							int d1 = J2DAY(day1);
							// some exceptions 
							if ((day >= cmp - 2) && (!(d1 == 3 && overl)))
							{
								// if year don't starts in thursday
								if ((d1 < 4 && J2DAY(day) != 5 && !isSaturday)
									||(d1 == 2 && isSaturday && overl))
								{
									result = iy2;
								}
							}
						}
					}
				}
				break;
			}
		CASE_fmt_MON
			result = DATE2J(y,m+(day<DATE2J(y,m,16)?0:1),1);
			break;
		CASE_fmt_WW
			z = (day - DATE2J(y,1,1)) % 7;
			result = day - z + (z < 4?0:7);
			break;
		CASE_fmt_IW
		{
			z = (day - iso_year(y,m,d)) % 7;
			result = day - z + (z < 4?0:7);
			if (((day - DATE2J(y,1,1)) / 7 + 1) >= 52)
			{
				// only for last iso week 
				Timestamp isoyear = iso_year(y+1, 1, 8);
				if (isoyear > (DATE2J(y+1,1,1)-1))
					if (day > isoyear - 7)
					{
						int tmpd = J2DAY(day);
						result -= (tmpd == 0 || tmpd > 4?7:0);
					}
			}
			break;
		}
		CASE_fmt_W
			z = (day - DATE2J(y,m,1)) % 7;
			result = day - z + (z < 4?0:7);
			break;
		CASE_fmt_DAY
			z = J2DAY(day);
			if (y > 0)
				result = day - z + (z < 4?0:7);
			else
				result = day + (5 - (z>0?(z>1?z:z+7):7));
			break;
		CASE_fmt_Q
			result = DATE2J(y,((m-1)/3)*3+(day<(DATE2J(y,((m-1)/3)*3+2,16))?1:4),1);
			break;
		default:
			result = day;
	}
	return result;
}

static void
tm_round(struct pg_tm *tm, text *fmt)
{
	int 	f;
	bool	rounded = true;

	f = ora_seq_search(VARDATA_ANY(fmt), date_fmt, VARSIZE_ANY_EXHDR(fmt));
	CHECK_SEQ_SEARCH(f, "round/trunc format string");

	// set rounding rule 
	switch (f)
	{
	CASE_fmt_IYYY
		NOT_ROUND_MDAY(tm->tm_mday < 8 && tm->tm_mon == 1);
		NOT_ROUND_MDAY(tm->tm_mday == 30 && tm->tm_mon == 6);
		if (tm->tm_mday >= 28 && tm->tm_mon == 12 && tm->tm_hour >= 12)
		{
			Timestamp isoyear = iso_year(tm->tm_year+1, 1, 8);
			Timestamp day0 = DATE2J(tm->tm_year+1,1,1);
			Timestamp dayc = DATE2J(tm->tm_year, tm->tm_mon, tm->tm_mday);

			if ((isoyear <= day0) || (day0 <= dayc + 2))
			{
				rounded = false;
			}
		}
		break;
	CASE_fmt_YYYY
		NOT_ROUND_MDAY(tm->tm_mday == 30 && tm->tm_mon == 6);
		break;
	CASE_fmt_MON
		NOT_ROUND_MDAY(tm->tm_mday == 15);
		break;
	CASE_fmt_Q
		NOT_ROUND_MDAY(tm->tm_mday == 15 && tm->tm_mon == ((tm->tm_mon-1)/3)*3+2);
		break;
	CASE_fmt_WW
	CASE_fmt_IW
		// last day in year 
		NOT_ROUND_MDAY(DATE2J(tm->tm_year, tm->tm_mon, tm->tm_mday) ==
		(DATE2J(tm->tm_year+1, 1,1) - 1));
		break;
	CASE_fmt_W
		// last day in month 
		NOT_ROUND_MDAY(DATE2J(tm->tm_year, tm->tm_mon, tm->tm_mday) ==
		(DATE2J(tm->tm_year, tm->tm_mon+1,1) - 1));
		break;
	}

	switch (f)
	{
	// easier convert to date
	CASE_fmt_IW
	CASE_fmt_DAY
	CASE_fmt_IYYY
	CASE_fmt_WW
	CASE_fmt_W
	CASE_fmt_CC
	CASE_fmt_MON
	CASE_fmt_YYYY
	CASE_fmt_Q
		ROUND_MDAY(tm);
		j2date(ora_date_round(DATE2J(tm->tm_year, tm->tm_mon, tm->tm_mday), f)
			   + POSTGRES_EPOCH_JDATE,
		&tm->tm_year, &tm->tm_mon, &tm->tm_mday);
		tm->tm_hour = 0;
		tm->tm_min = 0;
		break;
	CASE_fmt_DDD
		tm->tm_mday += (tm->tm_hour >= 12)?1:0;
		tm->tm_hour = 0;
		tm->tm_min = 0;
		break;
	CASE_fmt_MI
		tm->tm_min += (tm->tm_sec >= 30)?1:0;
		break;
	CASE_fmt_HH
		tm->tm_hour += (tm->tm_min >= 30)?1:0;
		tm->tm_min = 0;
		break;
	}

	tm->tm_sec = 0;
}

static Timestamp
ora_date_trunc(Timestamp day, int f)
{
	int y, m, d;
	Timestamp result;

	j2date(day + POSTGRES_EPOCH_JDATE, &y, &m, &d);

	switch (f)
	{
	CASE_fmt_CC
		if (y > 0)
			result = DATE2J((y/100)*100+1,1,1);
		else
			result = DATE2J(-((99 - (y - 1)) / 100) * 100 + 1,1,1);
		break;
	CASE_fmt_YYYY
		result = DATE2J(y,1,1);
		break;
	CASE_fmt_IYYY
		result = iso_year(y,m,d);
		break;
	CASE_fmt_MON
		result = DATE2J(y,m,1);
		break;
	CASE_fmt_WW
		result = day - (day - DATE2J(y,1,1)) % 7;
		break;
	CASE_fmt_IW
		result = day - (day - iso_year(y,m,d)) % 7;
		break;
	CASE_fmt_W
		result = day - (day - DATE2J(y,m,1)) % 7;
		break;
	CASE_fmt_DAY
		result = day - J2DAY(day);
		break;
	CASE_fmt_Q
		result = DATE2J(y,((m-1)/3)*3+1,1);
		break;
	default:
		result = day;
	}

	return result;
}

static void
tm_trunc(struct pg_tm *tm, text *fmt)
{
	int f;

	f = ora_seq_search(VARDATA_ANY(fmt), date_fmt, VARSIZE_ANY_EXHDR(fmt));
	CHECK_SEQ_SEARCH(f, "round/trunc format string");

	tm->tm_sec = 0;

	switch (f)
	{
	CASE_fmt_IYYY
	CASE_fmt_WW
	CASE_fmt_W
	CASE_fmt_IW
	CASE_fmt_DAY
	CASE_fmt_CC
		j2date(ora_date_trunc(DATE2J(tm->tm_year, tm->tm_mon, tm->tm_mday), f)
			   + POSTGRES_EPOCH_JDATE,
		&tm->tm_year, &tm->tm_mon, &tm->tm_mday);
		tm->tm_hour = 0;
		tm->tm_min = 0;
		break;
	CASE_fmt_YYYY
		tm->tm_mon = 1;
				tm->tm_mday = 1;
		tm->tm_hour = 0;
		tm->tm_min = 0;
		break;
	CASE_fmt_Q
		tm->tm_mon = (3*((tm->tm_mon - 1)/3)) + 1;
				tm->tm_mday = 1;
		tm->tm_hour = 0;
		tm->tm_min = 0;
		break;
	CASE_fmt_MON
		tm->tm_mday = 1;
		tm->tm_hour = 0;
		tm->tm_min = 0;
		break;
	CASE_fmt_DDD
		tm->tm_hour = 0;
		tm->tm_min = 0;
		break;
	CASE_fmt_HH
		tm->tm_min = 0;
		break;
	}
}

static int
ora_seq_prefix_search(const char *name, const char *const array[], int max)
{
	int		i;

	if (!*name)
		return -1;

	for (i = 0; array[i]; i++)
	{
		if (pg_strncasecmp(name, array[i], max) == 0)
			return i;
	}
	return -1;	/* not found */
}

static int
weekday_search(const WeekDays *weekdays, const char *str, int len)
{
	int		i;

	for (i = 0; i < 7; i++)
	{
		int	n = strlen(weekdays->names[i]);
		if (n > len)
			continue;	/* too short */
		if (pg_strncasecmp(weekdays->names[i], str, n) == 0)
			return i;
	}
	return -1;	/* not found */
}

static int ora_timezone_name_to_num(const char *name)
{
	int i;
	if(strlen(name) != 3)
		return -1;

	for(i = 0; date_timezone[i] != NULL; ++i)
	{
		if(pg_strncasecmp(name, date_timezone[i], 3) == 0)
			break;

	}
	switch (i)
	{
		CASE_timezone_0
			return 0;
			break;
		CASE_timezone_3
			return 3*3600;
			break;
		CASE_timezone_35
			return 3.5*3600;
			break;
		CASE_timezone_4
			return 4*3600;
			break;
		CASE_timezone_5
			return 5*3600;
			break;
		CASE_timezone_6
			return 6*3600;
			break;
		CASE_timezone_7
			return 7*3600;
			break;
		CASE_timezone_8
			return 8*3600;
			break;
		CASE_timezone_9
			return 9*3600;
			break;
		CASE_timezone_10
			return 10*3600;
			break;
		CASE_timezone_11
			return 11*3600;
			break;
		default:
			return -1;
	}
}
