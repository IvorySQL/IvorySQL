/*-------------------------------------------------------------------------
 *
 * dsinterval.c
 *
 * Compatible with Oracle's INTERVAL DAY TO SECOND data type.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/dsinterval.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <ctype.h>
#include <math.h>
#include <float.h>
#include <limits.h>
#include <sys/time.h>
#include <time.h>

#include "access/hash.h"
#include "access/xact.h"
#include "catalog/pg_type.h"
#include "common/int128.h"
#include "funcapi.h"
#include "libpq/pqformat.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "parser/scansup.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/datetime.h"
#include "utils/numeric.h"

#include "../include/common_datatypes.h"


PG_FUNCTION_INFO_V1(dsinterval_in);
PG_FUNCTION_INFO_V1(dsinterval_out);
PG_FUNCTION_INFO_V1(dsinterval_recv);
PG_FUNCTION_INFO_V1(dsinterval_send);
PG_FUNCTION_INFO_V1(dsintervaltypmodin);
PG_FUNCTION_INFO_V1(dsintervaltypmodout);

PG_FUNCTION_INFO_V1(dsinterval_eq);
PG_FUNCTION_INFO_V1(dsinterval_ne);
PG_FUNCTION_INFO_V1(dsinterval_lt);
PG_FUNCTION_INFO_V1(dsinterval_gt);
PG_FUNCTION_INFO_V1(dsinterval_le);
PG_FUNCTION_INFO_V1(dsinterval_ge);

PG_FUNCTION_INFO_V1(dsinterval_pl);
PG_FUNCTION_INFO_V1(dsinterval_mi);
PG_FUNCTION_INFO_V1(dsinterval_mul);
PG_FUNCTION_INFO_V1(mul_d_dsinterval);
PG_FUNCTION_INFO_V1(dsinterval_div);

PG_FUNCTION_INFO_V1(dsinterval_cmp);
PG_FUNCTION_INFO_V1(in_range_dsinterval_dsinterval);
PG_FUNCTION_INFO_V1(dsinterval_hash);
PG_FUNCTION_INFO_V1(dsinterval_hash_extended);

PG_FUNCTION_INFO_V1(dsinterval_larger);
PG_FUNCTION_INFO_V1(dsinterval_smaller);

PG_FUNCTION_INFO_V1(dsinterval);


/*
 * strtoi --- just like strtol, but returns int not long
 */
static int
strtoi(const char *nptr, char **endptr, int base)
{
	long		val;

	val = strtol(nptr, endptr, base);
#ifdef HAVE_LONG_INT_64
	if (val != (long) ((int32) val))
		errno = ERANGE;
#endif
	return (int) val;
}

/* Fetch a fractional-second value with suitable error checking */
static int
ParseFractionalSecond(char *cp, fsec_t *fsec)
{
	double		frac;

	/* Caller should always pass the start of the fraction part */
	Assert(*cp == '.');
	errno = 0;
	frac = strtod(cp, &cp);
	/* check for parse failure */
	if (*cp != '\0' || errno != 0)
		return DTERR_BAD_FORMAT;
#ifdef HAVE_INT64_TIMESTAMP
	*fsec = rint(frac * 1000000);
#else
	*fsec = frac;
#endif
	return 0;
}

static int
DecodeTime(char *str, int fmask, int range,
				int *tmask, struct tm * tm, fsec_t *fsec)
{
	char		*cp;
	int			 dterr;

	*tmask = DTK_TIME_M;

	errno = 0;
	tm->tm_hour = strtoi(str, &cp, 10);
	if (errno == ERANGE)
		return DTERR_FIELD_OVERFLOW;
	if (*cp != ':')
		return DTERR_BAD_FORMAT;
	errno = 0;
	tm->tm_min = strtoi(cp + 1, &cp, 10);
	if (errno == ERANGE)
		return DTERR_FIELD_OVERFLOW;
	if (*cp == '\0')
	{
		tm->tm_sec = INT_MAX;
		*fsec = 0;
		/* If it's a MINUTE TO SECOND interval, take 2 fields as being mm:ss */
		if (range == (INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND)))
		{
			tm->tm_sec = tm->tm_min;
			tm->tm_min = tm->tm_hour;
			tm->tm_hour = INT_MAX;
		}
	}
	else if (*cp == '.')
	{
		/* always assume mm:ss.sss is MINUTE TO SECOND */
		dterr = ParseFractionalSecond(cp, fsec);
		if (dterr)
			return dterr;
		tm->tm_sec = tm->tm_min;
		tm->tm_min = tm->tm_hour;
		tm->tm_hour = INT_MAX;
	}
	else if (*cp == ':')
	{
		errno = 0;
		tm->tm_sec = strtoi(cp + 1, &cp, 10);
		if (errno == ERANGE)
			return DTERR_FIELD_OVERFLOW;
		if (*cp == '\0')
			*fsec = 0;
		else if (*cp == '.')
		{
			dterr = ParseFractionalSecond(cp, fsec);
			if (dterr)
				return dterr;
		}
		else
			return DTERR_BAD_FORMAT;
	}
	else
		return DTERR_BAD_FORMAT;

	/*
	 * do a sanity check
	 * for 'tm->tm_min > MINS_PER_HOUR - 1' and 'tm->tm_sec > SECS_PER_MINUTE' check
	 * we will do this check in 'dsinterval_in' function, because the initial value
	 * is INT_MAX,so Cancel check in here.
	 *
	 * if compatible_level is oracle, when interval range is 'MINUTE TO SECOND',
	 * the value of 'tm->tm_min' can greater than MINS_PER_HOUR. Because the field 'MINUTE'
	 * is leading field, not trailing field.
	*/
#ifdef HAVE_INT64_TIMESTAMP
	if (tm->tm_hour < 0 || tm->tm_min < 0 || tm->tm_sec < 0 ||
		*fsec < INT64CONST(0) ||
		*fsec > USECS_PER_SEC)
		return DTERR_FIELD_OVERFLOW;
#else
	if (tm->tm_hour < 0 || tm->tm_min < 0 || tm->tm_min > MINS_PER_HOUR - 1 ||
		tm->tm_sec < 0 || tm->tm_sec > SECS_PER_MINUTE ||
		*fsec < 0 || *fsec > 1)
		return DTERR_FIELD_OVERFLOW;
#endif

	return 0;
}

/*
 * ClearPgTM
 * Zero out a pg_tm and associated fsec_t
 * compatible oracle:
 * In oracle, the string and interval fields is exact matched,
 * for example:interval'1:1' hour to second and interval'1 1:1:1' hour to second is error.
 * change the initial value of pg_tm *tm to INT_MAX, because if the value of 'tm' is 0,
 * we can not know  the '0' is initial value or the value of the input.
 */
static inline void
ClearPgTm(struct tm * tm, fsec_t *fsec)
{
	tm->tm_year = INT_MAX;
	tm->tm_mon = INT_MAX;
	tm->tm_mday = INT_MAX;
	tm->tm_hour = INT_MAX;
	tm->tm_min = INT_MAX;
	tm->tm_sec = INT_MAX;
	*fsec = 0;
}

/*
 * Multiply frac by scale (to produce seconds) and add to *tm & *fsec.
 * We assume the input frac is less than 1 so overflow is not an issue.
 */
static void
AdjustFractSeconds(double frac, struct tm * tm, fsec_t *fsec, int scale)
{
	int			sec;

	if (frac == 0)
		return;
	frac *= scale;
	sec = (int) frac;
	
	if (tm->tm_sec == INT_MAX)
		tm->tm_sec = 0;
	
	tm->tm_sec += sec;
	frac -= sec;
#ifdef HAVE_INT64_TIMESTAMP
	*fsec += rint(frac * 1000000);
#else
	*fsec += frac;
#endif
}

/* As above, but initial scale produces days */
static void
AdjustFractDays(double frac, struct tm * tm, fsec_t *fsec, int scale)
{
	int			extra_days;

	if (frac == 0)
		return;
	frac *= scale;
	extra_days = (int) frac;
	
	if (tm->tm_mday == INT_MAX)
		tm->tm_mday = 0;
	tm->tm_mday += extra_days;
	frac -= extra_days;
	AdjustFractSeconds(frac, tm, fsec, SECS_PER_DAY);
}

/* 
 * The same as function 'Decodeinterval' except that we don`t care
 * about year field and month field.
 */
static int
DecodeDsinterval(char **field, int *ftype, int nf, int range,
			   int *dtype, struct tm * tm, fsec_t *fsec)
{
	bool		is_before = false;
	char		*cp;
	int			fmask = 0,
				tmask,
				type;
	int			i;
	int			dterr;
	int			val;
	double		fval;

	*dtype = DTK_DELTA;
	type = IGNORE_DTF;
	ClearPgTm(tm, fsec);

	/* read through list backwards to pick up units before values */
	for (i = nf - 1; i >= 0; i--)
	{
		switch (ftype[i])
		{
			case DTK_TIME:
				dterr = DecodeTime(field[i], fmask, range,
								   &tmask, tm, fsec);
				if (dterr)
					return dterr;
				type = DTK_DAY;
				break;

			case DTK_TZ:

				/*
				 * Timezone means a token with a leading sign character and at
				 * least one digit; there could be ':', '.', '-' embedded in
				 * it as well.
				 */
				Assert(*field[i] == '-' || *field[i] == '+');

				/*
				 * Check for signed hh:mm or hh:mm:ss.  If so, process exactly
				 * like DTK_TIME case above, plus handling the sign.
				 */
				if (strchr(field[i] + 1, ':') != NULL &&
					DecodeTime(field[i] + 1, fmask, range,
							   &tmask, tm, fsec) == 0)
				{
					if (*field[i] == '-')
					{
						/* flip the sign on all fields */
						tm->tm_hour = -tm->tm_hour;
						tm->tm_min = -tm->tm_min;
						tm->tm_sec = -tm->tm_sec;
						*fsec = -(*fsec);
					}

					/*
					 * Set the next type to be a day, if units are not
					 * specified. This handles the case of '1 +02:03' since we
					 * are reading right to left.
					 */
					type = DTK_DAY;
					break;
				}

				/*
				 * Otherwise, fall through to DTK_NUMBER case, which can
				 * handle signed float numbers and signed year-month values.
				 */

				/* FALL THROUGH */

			case DTK_DATE:
			case DTK_NUMBER:
				if (type == IGNORE_DTF)
				{
					/* use typmod to decide what rightmost field is */
					switch (range)
					{
						case INTERVAL_MASK(YEAR):
						case INTERVAL_MASK(MONTH):
						case INTERVAL_MASK(YEAR) | INTERVAL_MASK(MONTH):
							return DTERR_BAD_FORMAT;
							
						case INTERVAL_MASK(DAY):
							type = DTK_DAY;
							break;
						case INTERVAL_MASK(HOUR):
						case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR):
							type = DTK_HOUR;
							break;
						case INTERVAL_MASK(MINUTE):
						case INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE):
						case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE):
							type = DTK_MINUTE;
							break;
						case INTERVAL_MASK(SECOND):
						case INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
						case INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
						case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
							type = DTK_SECOND;
							break;
						default:
							type = DTK_SECOND;
							break;
					}
				}

				errno = 0;
				val = strtoi(field[i], &cp, 10);
				if (errno == ERANGE)
					return DTERR_FIELD_OVERFLOW;

				if (*cp == '.')
				{
					errno = 0;
					fval = strtod(cp, &cp);
					if (*cp != '\0' || errno != 0)
						return DTERR_BAD_FORMAT;

					if (*field[i] == '-')
						fval = -fval;
				}
				else if (*cp == '\0')
					fval = 0;
				else
					return DTERR_BAD_FORMAT;

				tmask = 0;		/* DTK_M(type); */

				switch (type)
				{
					case DTK_MICROSEC:
#ifdef HAVE_INT64_TIMESTAMP
						*fsec += rint(val + fval);
#else
						*fsec += (val + fval) * 1e-6;
#endif
						tmask = DTK_M(MICROSECOND);
						break;

					case DTK_MILLISEC:
						/* avoid overflowing the fsec field */
						if (tm->tm_sec == INT_MAX)
							tm->tm_sec = 0;
						tm->tm_sec += val / 1000;
						val -= (val / 1000) * 1000;
#ifdef HAVE_INT64_TIMESTAMP
						*fsec += rint((val + fval) * 1000);
#else
						*fsec += (val + fval) * 1e-3;
#endif
						tmask = DTK_M(MILLISECOND);
						break;

					case DTK_SECOND:
						if (tm->tm_sec == INT_MAX)
							tm->tm_sec = 0;
						tm->tm_sec += val;
#ifdef HAVE_INT64_TIMESTAMP
						*fsec += rint(fval * 1000000);
#else
						*fsec += fval;
#endif

						/*
						 * If any subseconds were specified, consider this
						 * microsecond and millisecond input as well.
						 */
						if (fval == 0)
							tmask = DTK_M(SECOND);
						else
							tmask = DTK_ALL_SECS_M;
						break;

					case DTK_MINUTE:
						if (tm->tm_min == INT_MAX)
							tm->tm_min = 0;
						tm->tm_min += val;
						AdjustFractSeconds(fval, tm, fsec, SECS_PER_MINUTE);
						tmask = DTK_M(MINUTE);
						break;

					case DTK_HOUR:
						if (tm->tm_hour == INT_MAX)
							tm->tm_hour = 0;
						tm->tm_hour += val;
						AdjustFractSeconds(fval, tm, fsec, SECS_PER_HOUR);
						tmask = DTK_M(HOUR);
						type = DTK_DAY; /* set for next field */
						break;

					case DTK_DAY:
						if (tm->tm_mday == INT_MAX)
							tm->tm_mday = 0;
						tm->tm_mday += val;
						AdjustFractSeconds(fval, tm, fsec, SECS_PER_DAY);
						tmask = DTK_M(DAY);
						break;

					case DTK_WEEK:
						if (tm->tm_mday == INT_MAX)
							tm->tm_mday = 0;
						tm->tm_mday += val * 7;
						AdjustFractDays(fval, tm, fsec, 7);
						tmask = DTK_M(WEEK);
						break;

					case DTK_MONTH:
						if (tm->tm_mon == INT_MAX)
							tm->tm_mon = 0;
						tm->tm_mon += val;
						AdjustFractDays(fval, tm, fsec, DAYS_PER_MONTH);
						tmask = DTK_M(MONTH);
						break;

					case DTK_YEAR:
						if (tm->tm_year == INT_MAX)
							tm->tm_year = 0;
						tm->tm_year += val;
						if (fval != 0)
							tm->tm_mon += fval * MONTHS_PER_YEAR;
						tmask = DTK_M(YEAR);
						break;

					case DTK_DECADE:
						if (tm->tm_year == INT_MAX)
							tm->tm_year = 0;
						tm->tm_year += val * 10;
						if (fval != 0)
						{
							if (tm->tm_mon == INT_MAX)
								tm->tm_mon = 0;
							
							tm->tm_mon += fval * MONTHS_PER_YEAR * 10;
						}
						tmask = DTK_M(DECADE);
						break;

					case DTK_CENTURY:
						if (tm->tm_year == INT_MAX)
							tm->tm_year = 0;
						tm->tm_year += val * 100;
						if (fval != 0)
						{
							if (tm->tm_mon == INT_MAX)
								tm->tm_mon = 0;
							
							tm->tm_mon += fval * MONTHS_PER_YEAR * 100;
						}
						tmask = DTK_M(CENTURY);
						break;

					case DTK_MILLENNIUM:
						if (tm->tm_year == INT_MAX)
							tm->tm_year = 0;
						tm->tm_year += val * 1000;
						if (fval != 0)
						{
							if (tm->tm_mon == INT_MAX)
								tm->tm_mon = 0;
							
							tm->tm_mon += fval * MONTHS_PER_YEAR * 1000;
						}
						tmask = DTK_M(MILLENNIUM);
						break;

					default:
						return DTERR_BAD_FORMAT;
				}
				break;

			case DTK_STRING:
			case DTK_SPECIAL:
				type = DecodeUnits(i, field[i], &val);
				if (type == IGNORE_DTF)
					continue;

				tmask = 0;		/* DTK_M(type); */
				switch (type)
				{
					case UNITS:
						type = val;
						break;

					case AGO:
						is_before = true;
						type = val;
						break;

					case RESERV:
						tmask = (DTK_DATE_M | DTK_TIME_M);
						*dtype = val;
						break;

					default:
						return DTERR_BAD_FORMAT;
				}
				break;

			default:
				return DTERR_BAD_FORMAT;
		}

		if (tmask & fmask)
			return DTERR_BAD_FORMAT;
		fmask |= tmask;
	}

	/* ensure that at least one time field has been found */
	if (fmask == 0)
		return DTERR_BAD_FORMAT;

	/*----------
	 * The SQL standard defines the interval literal
	 * '-1 1:00:00'
	 * to mean "negative 1 days and negative 1 hours", while Postgres
	 * traditionally treats this as meaning "negative 1 days and positive
	 * 1 hours".  In SQL_STANDARD intervalstyle, we apply the leading sign
	 * to all fields if there are no other explicit signs.
	 *
	 * We leave the signs alone if there are additional explicit signs.
	 * This protects us against misinterpreting postgres-style dump output,
	 * since the postgres-style output code has always put an explicit sign on
	 * all fields following a negative field.  But note that SQL-spec output
	 * is ambiguous and can be misinterpreted on load!	(So it's best practice
	 * to dump in postgres style, not SQL style.)
	 *----------
	 */
	/* Default = INTSTYLE_SQL_STANDARD */
	if (*field[0] == '-')
	{
		/* Check for additional explicit signs */
		bool		more_signs = false;

		for (i = 1; i < nf; i++)
		{
			if (*field[i] == '-' || *field[i] == '+')
			{
				more_signs = true;
				break;
			}
		}

		if (!more_signs)
		{
			/*
			 * Rather than re-determining which field was field[0], just force
			 * 'em all negative.
			 */
			if (*fsec > 0)
				*fsec = -(*fsec);
			if (tm->tm_sec > 0)
				tm->tm_sec = -tm->tm_sec;
			if (tm->tm_min > 0)
				tm->tm_min = -tm->tm_min;
			if (tm->tm_hour > 0)
				tm->tm_hour = -tm->tm_hour;
			if (tm->tm_mday > 0)
				tm->tm_mday = -tm->tm_mday;
			if (tm->tm_mon > 0)
				tm->tm_mon = -tm->tm_mon;
			if (tm->tm_year > 0)
				tm->tm_year = -tm->tm_year;
		}
	}

	/* finally, AGO negates everything */
	if (is_before)
	{
		tm->tm_sec = (tm->tm_sec == INT_MAX) ? 0 : tm->tm_sec;
		tm->tm_min = (tm->tm_min == INT_MAX) ? 0 : tm->tm_min;
		tm->tm_hour = (tm->tm_hour == INT_MAX) ? 0 : tm->tm_hour;
		tm->tm_mday = (tm->tm_mday == INT_MAX) ? 0 : tm->tm_mday;
		tm->tm_mon = (tm->tm_mon == INT_MAX) ? 0 : tm->tm_mon;
		tm->tm_year = (tm->tm_year == INT_MAX) ? 0 : tm->tm_year;

		*fsec = -(*fsec);
		tm->tm_sec = -tm->tm_sec;
		tm->tm_min = -tm->tm_min;
		tm->tm_hour = -tm->tm_hour;
		tm->tm_mday = -tm->tm_mday;
		tm->tm_mon = -tm->tm_mon;
		tm->tm_year = -tm->tm_year;
	}

	return 0;
}

/* 
 * Change Note:
 * 
 * Add one parameter 'trimnum' recode the number of zero to trimed .
 * 
 */
static void
TrimTrailingZeros(char *str, int trimnum)
{
	int			len = strlen(str);
	int			i = 0;
	
	while (len > 1 && *(str + len - 1) == '0' && *(str + len - 2) != '.' && i < trimnum)
	{
		len--;
		i++;
		*(str + len) = '\0';
	}
}

/*
 * Change note:
 * 'precision' is the exact precision of fractional second,rather than
 * the value of MAX_INTERVAL_PRECISION .
 *
 * sprintf append nine(ORACLE_MAX_INTERVAL_PRECISION) decimal fraction.
 *
 */
static void
AppendSeconds(char *cp, int sec, fsec_t fsec, int precision, bool fillzeros)
{
	/* Compatible oracle, do 'fsec' as a nanosecond*/
	fsec *= 1000;

	if (fsec == 0)
	{
		if (fillzeros)
		{
			/* Compatible oracle ,if the precision of fractional second is zero ,dont show */
			if (precision == 0)
				sprintf(cp, "%02d", abs(sec));
			else
				sprintf(cp, "%02d.%0*d", abs(sec), precision, 0);
		}
		else
		{
			sprintf(cp, "%d", abs(sec));
		}
	}
	else
	{
#ifdef HAVE_INT64_TIMESTAMP
		if (fillzeros)
			sprintf(cp, "%02d.%0*d", abs(sec), ORACLE_MAX_INTERVAL_PRECISION, (int) Abs(fsec));
		else
			sprintf(cp, "%d.%0*d", abs(sec), ORACLE_MAX_INTERVAL_PRECISION, (int) Abs(fsec));
#else
		if (fillzeros)
			sprintf(cp, "%0*.*f", ORACLE_MAX_INTERVAL_PRECISION + 3, ORACLE_MAX_INTERVAL_PRECISIONcision, fabs(sec + fsec));
		else
			sprintf(cp, "%.*f", ORACLE_MAX_INTERVAL_PRECISIONion, fabs(sec + fsec));
#endif
		TrimTrailingZeros(cp, ORACLE_MAX_INTERVAL_PRECISION - precision);
	}
}

/*
 * Encodedsinterval()
 * Interpret time structure as a delta time and convert to string.
 */
static void
EncodeDsinterval(struct pg_tm * tm, fsec_t fsec, int style, char *str, int day_precision, int second_precision)
{
	char	   *cp = str;
	int			year = tm->tm_year;
	int			mon = tm->tm_mon;
	int			mday = tm->tm_mday;
	int			hour = tm->tm_hour;
	int			min = tm->tm_min;
	int			sec = tm->tm_sec;
	
	switch (style)
	{
			/* SQL Standard interval format */
		case INTSTYLE_SQL_STANDARD:
			{
				bool		has_negative = year < 0 || mon < 0 ||
				mday < 0 || hour < 0 ||
				min < 0 || sec < 0 || fsec < 0;
				bool		has_positive = year > 0 || mon > 0 ||
				mday > 0 || hour > 0 ||
				min > 0 || sec > 0 || fsec > 0;
				bool		has_year_month = year != 0 || mon != 0;
				bool		has_day_time = mday != 0 || hour != 0 ||
				min != 0 || sec != 0 || fsec != 0;
				bool		has_day = mday != 0;
				bool		sql_standard_value = !(has_negative && has_positive) &&
				!(has_year_month && has_day_time);

				/*
				 * SQL Standard wants only 1 "<sign>" preceding the whole
				 * interval ... but can't do that if mixed signs.
				 */
				if (has_negative && sql_standard_value)
				{
					*cp++ = '-';
					year = -year;
					mon = -mon;
					mday = -mday;
					hour = -hour;
					min = -min;
					sec = -sec;
					fsec = -fsec;
				}

				/* Compatible oracle, show sign '+' or '-' */
				if (!has_negative)
					*cp++ = '+';

				/* Compatible oracle, the value of interval is zero should show "+00 00:00:00.000000" */
				if (!has_negative && !has_positive)
				{
					sprintf(cp, "%0*d %02d:%02d:", day_precision, mday, hour, min);
					cp += strlen(cp);
					AppendSeconds(cp, sec, fsec, second_precision, true);
				}
				else if (!sql_standard_value)
				{
					/*
					 * For non sql-standard interval values, force outputting
					 * the signs to avoid ambiguities with intervals with
					 * mixed sign components.
					 */
					char		year_sign = (year < 0 || mon < 0) ? '-' : '+';
					char		day_sign = (mday < 0) ? '-' : '+';
					char		sec_sign = (hour < 0 || min < 0 ||
											sec < 0 || fsec < 0) ? '-' : '+';

					sprintf(cp, "%c%d-%d %c%d %c%d:%02d:",
							year_sign, abs(year), abs(mon),
							day_sign, abs(mday),
							sec_sign, abs(hour), abs(min));
					cp += strlen(cp);
					AppendSeconds(cp, sec, fsec, second_precision, true);
				}
				else if (has_year_month)
				{
					sprintf(cp, "%d-%d", year, mon);
				}
				else if (has_day)
				{
					sprintf(cp, "%0*d %02d:%02d:", day_precision, mday, hour, min);
					cp += strlen(cp);
					AppendSeconds(cp, sec, fsec, second_precision, true);
				}
				else
				{
					sprintf(cp, "%0*d %02d:%02d:", day_precision, 0, hour, min);
					cp += strlen(cp);
					AppendSeconds(cp, sec, fsec, second_precision, true);
				}
			}
			break;
		default:
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("interval style not support.")));
	}
}

/*
 *	Adjust interval for specified precision, in both DAY to SECOND
 *	range and sub-second precision.
 */
static void
AdjustIntervalForTypmod(Interval *interval, int32 typmod)
{
#ifdef HAVE_INT64_TIMESTAMP
	static const int64 IntervalScales[MAX_INTERVAL_PRECISION + 1] = {
		INT64CONST(1000000),
		INT64CONST(100000),
		INT64CONST(10000),
		INT64CONST(1000),
		INT64CONST(100),
		INT64CONST(10),
		INT64CONST(1)
	};

	static const int64 IntervalOffsets[MAX_INTERVAL_PRECISION + 1] = {
		INT64CONST(500000),
		INT64CONST(50000),
		INT64CONST(5000),
		INT64CONST(500),
		INT64CONST(50),
		INT64CONST(5),
		INT64CONST(0)
	};
#else
	static const double IntervalScales[MAX_INTERVAL_PRECISION + 1] = {
		1,
		10,
		100,
		1000,
		10000,
		100000,
		1000000
	};
#endif

	/*
	 * Unspecified range and precision? Then not necessary to adjust. Setting
	 * typmod to -1 is the convention for all data types.
	 */
	if (typmod >= 0)
	{
		int			range = INTERVAL_RANGE(typmod);
		int			second_precision = INTERVAL_SECOND_PRECISION(typmod);

		if (range == INTERVAL_FULL_RANGE)
		{
			/* Do nothing... */
		}
		else if (range == INTERVAL_MASK(DAY))
		{
			interval->time = 0;
		}
		else if (range == INTERVAL_MASK(HOUR))
		{
#ifdef HAVE_INT64_TIMESTAMP
			interval->time = (interval->time / USECS_PER_HOUR) *
				USECS_PER_HOUR;
#else
			interval->time = ((int) (interval->time / SECS_PER_HOUR)) * (double) SECS_PER_HOUR;
#endif
		}
		else if (range == INTERVAL_MASK(MINUTE))
		{
#ifdef HAVE_INT64_TIMESTAMP
			interval->time = (interval->time / USECS_PER_MINUTE) *
				USECS_PER_MINUTE;
#else
			interval->time = ((int) (interval->time / SECS_PER_MINUTE)) * (double) SECS_PER_MINUTE;
#endif
		}
		else if (range == INTERVAL_MASK(SECOND))
		{
			/* fractional-second rounding will be dealt with below */
		}
		/* DAY TO HOUR */
		else if (range == (INTERVAL_MASK(DAY) |
						   INTERVAL_MASK(HOUR)))
		{
#ifdef HAVE_INT64_TIMESTAMP
			interval->time = (interval->time / USECS_PER_HOUR) *
				USECS_PER_HOUR;
#else
			interval->time = ((int) (interval->time / SECS_PER_HOUR)) * (double) SECS_PER_HOUR;
#endif
		}
		/* DAY TO MINUTE */
		else if (range == (INTERVAL_MASK(DAY) |
						   INTERVAL_MASK(HOUR) |
						   INTERVAL_MASK(MINUTE)))
		{
#ifdef HAVE_INT64_TIMESTAMP
			interval->time = (interval->time / USECS_PER_MINUTE) *
				USECS_PER_MINUTE;
#else
			interval->time = ((int) (interval->time / SECS_PER_MINUTE)) * (double) SECS_PER_MINUTE;
#endif
		}
		/* DAY TO SECOND */
		else if (range == (INTERVAL_MASK(DAY) |
						   INTERVAL_MASK(HOUR) |
						   INTERVAL_MASK(MINUTE) |
						   INTERVAL_MASK(SECOND)))
		{
			/* fractional-second rounding will be dealt with below */
		}
		/* HOUR TO MINUTE */
		else if (range == (INTERVAL_MASK(HOUR) |
						   INTERVAL_MASK(MINUTE)))
		{
#ifdef HAVE_INT64_TIMESTAMP
			interval->time = (interval->time / USECS_PER_MINUTE) *
				USECS_PER_MINUTE;
#else
			interval->time = ((int) (interval->time / SECS_PER_MINUTE)) * (double) SECS_PER_MINUTE;
#endif
		}
		/* HOUR TO SECOND */
		else if (range == (INTERVAL_MASK(HOUR) |
						   INTERVAL_MASK(MINUTE) |
						   INTERVAL_MASK(SECOND)))
		{
			/* fractional-second rounding will be dealt with below */
		}
		/* MINUTE TO SECOND */
		else if (range == (INTERVAL_MASK(MINUTE) |
						   INTERVAL_MASK(SECOND)))
		{
			/* fractional-second rounding will be dealt with below */
		}
		else
			elog(ERROR, "unrecognized interval typmod: %d", typmod);

		/* Need to adjust subsecond precision? */
		if (second_precision != INTERVAL_FULL_PRECISION)
		{
			if (second_precision < 0 || second_precision > ORACLE_MAX_INTERVAL_PRECISION)
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				   errmsg("interval(%d) precision must be between %d and %d",
						  second_precision, 0, MAX_INTERVAL_PRECISION)));
						  
			if (second_precision > MAX_INTERVAL_PRECISION)
				second_precision = MAX_INTERVAL_PRECISION;

			/*
			 * Note: this round-to-nearest code is not completely consistent
			 * about rounding values that are exactly halfway between integral
			 * values.  On most platforms, rint() will implement
			 * round-to-nearest-even, but the integer code always rounds up
			 * (away from zero).  Is it worth trying to be consistent?
			 */
#ifdef HAVE_INT64_TIMESTAMP
			if (interval->time >= INT64CONST(0))
			{
				interval->time = ((interval->time +
								   IntervalOffsets[second_precision]) /
								  IntervalScales[second_precision]) *
					IntervalScales[second_precision];
			}
			else
			{
				interval->time = -(((-interval->time +
									 IntervalOffsets[second_precision]) /
									IntervalScales[second_precision]) *
								   IntervalScales[second_precision]);
			}
#else
			interval->time = rint(((double) interval->time) *
								  IntervalScales[second_precision]) /
				IntervalScales[second_precision];
#endif
		}
		
	}
	
	/* Convert interval->time to interval->day */
	interval->day += interval->time / USECS_PER_DAY;
	interval->time = interval->time % USECS_PER_DAY;
}

/*
 *	Adjust interval day for specified precision
 */
static void
AdjustTypmodForDay(Interval *interval, int32 typmod)
{
	if (typmod > 0)
	{
		int			range = INTERVAL_RANGE(typmod);
		int			day_precision = INTERVAL_DAY_PRECISION(typmod);
		int			interval_day;

		if (range != INTERVAL_FULL_RANGE)
		{
			/* interval'-100' day */
			interval_day = abs(interval->day);
			switch(day_precision)
			{
				case 0:
					if (interval_day != 0)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 1:
					if (interval_day >= 10)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 2:
					if (interval_day >= 100)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 3:
					if (interval_day >= 1000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 4:
					if (interval_day >= 10000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 5:
					if (interval_day >= 100000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 6:
					if (interval_day >= 1000000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 7:
					if (interval_day >= 10000000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 8:
					if (interval_day >= 100000000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 9:
					if (interval_day >= 1000000000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				default:
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("precision of interval is too large")));
			}
		}
	}
}

/* copy&pasted from .../src/backend/utils/adt/datetime.c */
static int
ora_ISO8601IntegerWidth(const char *fieldstart)
{
	/* We might have had a leading '-' */
	if (*fieldstart == '-')
		fieldstart++;
	return strspn(fieldstart, "0123456789");
}

/* copy&pasted from .../src/backend/utils/adt/datetime.c */
static int
ora_ParseISO8601Number(const char *str, char **endptr, int *ipart, double *fpart)
{
	double		val;

	if (!(isdigit((unsigned char) *str) || *str == '-' || *str == '.'))
		return DTERR_BAD_FORMAT;
	errno = 0;
	val = strtod(str, endptr);
	/* did we not see anything that looks like a double? */
	if (*endptr == str || errno != 0)
		return DTERR_BAD_FORMAT;
	/* watch out for overflow */
	if (val < INT_MIN || val > INT_MAX)
		return DTERR_FIELD_OVERFLOW;
	/* be very sure we truncate towards zero (cf dtrunc()) */
	if (val >= 0)
		*ipart = (int) floor(val);
	else
		*ipart = (int) -floor(-val);
	*fpart = val - *ipart;
	return 0;
}

/* copy&pasted from .../src/backend/utils/adt/datetime.c
 *
 * * changed struct pg_tm to struct tm
 *
 * * Made the function static
 */
static int
ora_DecodeISO8601Interval(char *str,
					  int *dtype, struct /* pg_ */ tm *tm, fsec_t *fsec)
{
	bool		datepart = true;
	bool		havefield = false;

	*dtype = DTK_DELTA;
	memset(tm, 0, sizeof(struct tm));

	if (strlen(str) < 2 || str[0] != 'P')
		return DTERR_BAD_FORMAT;

	str++;
	while (*str)
	{
		char	   *fieldstart;
		int			val;
		double		fval;
		char		unit;
		int			dterr;

		if (*str == 'T')		/* T indicates the beginning of the time part */
		{
			datepart = false;
			havefield = false;
			str++;
			continue;
		}

		fieldstart = str;
		dterr = ora_ParseISO8601Number(str, &str, &val, &fval);
		if (dterr)
			return dterr;

		/*
		 * Note: we could step off the end of the string here.  Code below
		 * *must* exit the loop if unit == '\0'.
		 */
		unit = *str++;

		if (datepart)
		{
			switch (unit)		/* before T: Y M W D */
			{
				case 'Y':
					tm->tm_year += val;
					tm->tm_mon += rint(fval * MONTHS_PER_YEAR);
					break;
				case 'M':
					tm->tm_mon += val;
					AdjustFractDays(fval, tm, fsec, DAYS_PER_MONTH);
					break;
				case 'W':
					tm->tm_mday += val * 7;
					AdjustFractDays(fval, tm, fsec, 7);
					break;
				case 'D':
					tm->tm_mday += val;
					AdjustFractSeconds(fval, tm, fsec, SECS_PER_DAY);
					break;
				case 'T':		/* ISO 8601 4.4.3.3 Alternative Format / Basic */
				case '\0':
					if (ora_ISO8601IntegerWidth(fieldstart) == 8 && !havefield)
					{
						tm->tm_year += val / 10000;
						tm->tm_mon += (val / 100) % 100;
						tm->tm_mday += val % 100;
						AdjustFractSeconds(fval, tm, fsec, SECS_PER_DAY);
						if (unit == '\0')
							return 0;
						datepart = false;
						havefield = false;
						continue;
					}
					/* Else fall through to extended alternative format */
					/* FALLTHROUGH */
				case '-':		/* ISO 8601 4.4.3.3 Alternative Format,
								 * Extended */
					if (havefield)
						return DTERR_BAD_FORMAT;

					tm->tm_year += val;
					tm->tm_mon += rint(fval * MONTHS_PER_YEAR);
					if (unit == '\0')
						return 0;
					if (unit == 'T')
					{
						datepart = false;
						havefield = false;
						continue;
					}

					dterr = ora_ParseISO8601Number(str, &str, &val, &fval);
					if (dterr)
						return dterr;
					tm->tm_mon += val;
					AdjustFractDays(fval, tm, fsec, DAYS_PER_MONTH);
					if (*str == '\0')
						return 0;
					if (*str == 'T')
					{
						datepart = false;
						havefield = false;
						continue;
					}
					if (*str != '-')
						return DTERR_BAD_FORMAT;
					str++;

					dterr = ora_ParseISO8601Number(str, &str, &val, &fval);
					if (dterr)
						return dterr;
					tm->tm_mday += val;
					AdjustFractSeconds(fval, tm, fsec, SECS_PER_DAY);
					if (*str == '\0')
						return 0;
					if (*str == 'T')
					{
						datepart = false;
						havefield = false;
						continue;
					}
					return DTERR_BAD_FORMAT;
				default:
					/* not a valid date unit suffix */
					return DTERR_BAD_FORMAT;
			}
		}
		else
		{
			switch (unit)		/* after T: H M S */
			{
				case 'H':
					tm->tm_hour += val;
					AdjustFractSeconds(fval, tm, fsec, SECS_PER_HOUR);
					break;
				case 'M':
					tm->tm_min += val;
					AdjustFractSeconds(fval, tm, fsec, SECS_PER_MINUTE);
					break;
				case 'S':
					tm->tm_sec += val;
					AdjustFractSeconds(fval, tm, fsec, 1);
					break;
				case '\0':		/* ISO 8601 4.4.3.3 Alternative Format */
					if (ora_ISO8601IntegerWidth(fieldstart) == 6 && !havefield)
					{
						tm->tm_hour += val / 10000;
						tm->tm_min += (val / 100) % 100;
						tm->tm_sec += val % 100;
						AdjustFractSeconds(fval, tm, fsec, 1);
						return 0;
					}
					/* Else fall through to extended alternative format */
					/* FALLTHROUGH */
				case ':':		/* ISO 8601 4.4.3.3 Alternative Format,
								 * Extended */
					if (havefield)
						return DTERR_BAD_FORMAT;

					tm->tm_hour += val;
					AdjustFractSeconds(fval, tm, fsec, SECS_PER_HOUR);
					if (unit == '\0')
						return 0;

					dterr = ora_ParseISO8601Number(str, &str, &val, &fval);
					if (dterr)
						return dterr;
					tm->tm_min += val;
					AdjustFractSeconds(fval, tm, fsec, SECS_PER_MINUTE);
					if (*str == '\0')
						return 0;
					if (*str != ':')
						return DTERR_BAD_FORMAT;
					str++;

					dterr = ora_ParseISO8601Number(str, &str, &val, &fval);
					if (dterr)
						return dterr;
					tm->tm_sec += val;
					AdjustFractSeconds(fval, tm, fsec, 1);
					if (*str == '\0')
						return 0;
					return DTERR_BAD_FORMAT;

				default:
					/* not a valid time unit suffix */
					return DTERR_BAD_FORMAT;
			}
		}

		havefield = true;
	}

	return 0;
}

/* interval2tm()
 * Convert an interval data type to a tm structure.
 */
static int
interval2tm(Interval span, struct pg_tm *tm, fsec_t *fsec)
{
	TimeOffset	time;
	TimeOffset	tfrac;

	tm->tm_year = span.month / MONTHS_PER_YEAR;
	tm->tm_mon = span.month % MONTHS_PER_YEAR;
	tm->tm_mday = span.day;
	time = span.time;

	tfrac = time / USECS_PER_HOUR;
	time -= tfrac * USECS_PER_HOUR;
	tm->tm_hour = tfrac;
	if (!SAMESIGN(tm->tm_hour, tfrac))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));
	tfrac = time / USECS_PER_MINUTE;
	time -= tfrac * USECS_PER_MINUTE;
	tm->tm_min = tfrac;
	tfrac = time / USECS_PER_SEC;
	*fsec = time - (tfrac * USECS_PER_SEC);
	tm->tm_sec = tfrac;

	return 0;
}

static int
tm2dsinterval(struct tm * tm, fsec_t fsec, Interval *span)
{
	double		total_months = (double) tm->tm_year * MONTHS_PER_YEAR + tm->tm_mon;

	if (total_months > INT_MAX || total_months < INT_MIN)
		return -1;
	span->month = total_months;
	span->day = tm->tm_mday;
#ifdef HAVE_INT64_TIMESTAMP
	span->time = (((((tm->tm_hour * INT64CONST(60)) +
					 tm->tm_min) * INT64CONST(60)) +
					 tm->tm_sec) * USECS_PER_SEC) + fsec;
#else
	span->time = (((tm->tm_hour * (double) MINS_PER_HOUR) +
					 tm->tm_min) * (double) SECS_PER_MINUTE) +
					 tm->tm_sec + fsec;
#endif

	return 0;
}

/*
 * Compatible oracle:
 * For INTERVAL DAY TO SECOND type the field of "MONTH" is invalid.
 * Only calculate the value of "interval->day" and "interval->time".
 */
static inline TimeOffset
dsinterval_cmp_value(const Interval *interval)
{
	TimeOffset	span;

	span = interval->time;

#ifdef HAVE_INT64_TIMESTAMP
//	span += interval->month * INT64CONST(30) * USECS_PER_DAY;
	span += interval->day * INT64CONST(24) * USECS_PER_HOUR;
#else
//	span += interval->month * ((double) DAYS_PER_MONTH * SECS_PER_DAY);
	span += interval->day * ((double) HOURS_PER_DAY * SECS_PER_HOUR);
#endif

	return span;
}

static int
dsinterval_cmp_internal(Interval *interval1, Interval *interval2)
{
	TimeOffset	span1 = dsinterval_cmp_value(interval1);
	TimeOffset	span2 = dsinterval_cmp_value(interval2);

	return ((span1 < span2) ? -1 : (span1 > span2) ? 1 : 0);
}

/*****************************************************************************
 *	 Base I/O function
 *****************************************************************************/

/* dsinterval_in()
 * Convert a string to internal form.
 *
 * External format(s):
 *	Uses the generic date/time parsing and decoding routines.
 */
Datum
dsinterval_in(PG_FUNCTION_ARGS)
{
	char	   *str = PG_GETARG_CSTRING(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		typmod = PG_GETARG_INT32(2);
	Interval   *result;
	fsec_t		fsec;
	struct		tm tt,
			   *tm = &tt;
	int			dtype = -1;
	int			nf = 0;
	int			range;
	int			dterr;
	char	   *field[MAXDATEFIELDS];
	int			ftype[MAXDATEFIELDS];
	char		workbuf[256];
	bool		isiso = false;
	char 		*strsrc;
	char 		*strold;
	DateTimeErrorExtra extra;

	tm->tm_year = INT_MAX;
	tm->tm_mon = INT_MAX;
	tm->tm_mday = INT_MAX;
	tm->tm_hour = INT_MAX;
	tm->tm_min = INT_MAX;
	tm->tm_sec = INT_MAX;
	fsec = 0;

	if (typmod >= 0)
		range = INTERVAL_RANGE(typmod);
	else
		range = INTERVAL_FULL_RANGE;

	while (*str == ' ')
		str++;

	strsrc = str;
	strold = str;
	while (*strold != '\0')
	{
		if (*strold == ' ')
		{
			while (*(strold + 1) == ' ')
				strold++;
			if (*(strold + 1) == ':' || *(strold + 1) == '.')
			{
				strold++;
				*strsrc++ = *strold++;
				while (*strold == ' ')
					strold++;

				if (*strold == '\0')
					break;
			}
		}
		else if (*strold == ':' && *(strold + 1) == ' ')
		{
			*strsrc++ = *strold++;
			while (*strold == ' ')
				strold++;

			if (*strold == '\0')
				break;
		}
		*strsrc++ = *strold++;
	}
	*strsrc = *strold;

	dterr = ParseDateTime(str, workbuf, sizeof(workbuf), field,
						  ftype, MAXDATEFIELDS, &nf);

	/*
	 * Compatible oracle 
	 * interval'+1 +1:1:1' is error in oracle db.(istz > 1)
	 * interval'1 +1:1:1' is error in oracle db. (istz == 1 && ftype[0] != DTK_TZ)
	 * Only leading field can specify '-' or '+'
	 */
	if (nf > 1 && dterr == 0)
	{
		int		i;
		int		istz = 0;
		for (i = 0; i < nf; i++)
		{
			if (ftype[i] == DTK_TZ)
				istz++;
		}
		if (istz > 1 || (istz == 1 && ftype[0] != DTK_TZ))
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("the interval is invalid")));
	}

	if (dterr == 0)
		dterr = DecodeDsinterval(field, ftype, nf, range,
							   &dtype, tm, &fsec);

	/* if those functions think it's a bad format, try ISO8601 style */
	if (dterr == DTERR_BAD_FORMAT)
	{
		dterr = ora_DecodeISO8601Interval(str,
									  &dtype, tm, &fsec);
		isiso = true;
	}

	if (dterr != 0)
	{
		if (dterr == DTERR_FIELD_OVERFLOW)
			dterr = DTERR_INTERVAL_OVERFLOW;
		DateTimeParseError(dterr, &extra, str, "interval", NULL);
	}

	/*
	 * compatible oracle, the valid range of values for the trailing field
	 * HOUR: 0 to 23
	 * MINUTE: 0 to 59
	 * SECOND: 0 to 59.999999999
	 *
	 * In oracle, the string and interval fields is exact matched,
	 * for example:interval'1:1' hour to second and interval'1 1:1:1' hour to second is error.
	 * change the initial value of 'pg_tm *tm' to INT_MAX, because if the value of 'pg_tm *tm' is 0,
	 * we can not know  the '0' is initial value or the value of the input.
	 */
	if (!isiso)
	{
		switch(range)
		{
			case INTERVAL_MASK(DAY):
				if (abs(tm->tm_year) != INT_MAX ||
					abs(tm->tm_mon)  != INT_MAX ||
					abs(tm->tm_min)  != INT_MAX ||
					abs(tm->tm_sec)  != INT_MAX ||
					abs(tm->tm_hour) != INT_MAX ||
					abs(tm->tm_mday) == INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));
				break;

			case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR):
				if (abs(tm->tm_year) != INT_MAX ||
					abs(tm->tm_mon) != INT_MAX  ||
					abs(tm->tm_min) != INT_MAX  ||
					abs(tm->tm_sec) != INT_MAX  ||
					abs(tm->tm_hour) == INT_MAX ||
					abs(tm->tm_mday) == INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));

				if (abs(tm->tm_hour) < 0 || abs(tm->tm_hour) > 23)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("hour must be between 0 and 23")));
				break;

			case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE):
				if (abs(tm->tm_year) != INT_MAX ||
					abs(tm->tm_mon) != INT_MAX  ||
					abs(tm->tm_sec) != INT_MAX  ||
					abs(tm->tm_mday) == INT_MAX ||
					abs(tm->tm_hour) == INT_MAX ||
					abs(tm->tm_min) == INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));

				if (abs(tm->tm_hour) < 0 || abs(tm->tm_hour) > 23)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("hour must be between 0 and 23")));

				if (abs(tm->tm_min) < 0 || abs(tm->tm_min) > 59)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("minutes must be between 0 and 59")));
				break;

			case INTERVAL_FULL_RANGE:
			case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
				if (abs(tm->tm_year) != INT_MAX ||
					abs(tm->tm_mon)  != INT_MAX ||
					abs(tm->tm_mday) == INT_MAX ||
					abs(tm->tm_hour) == INT_MAX ||
					abs(tm->tm_min)  == INT_MAX ||
					abs(tm->tm_sec)  == INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));

				if (abs(tm->tm_hour) < 0 || abs(tm->tm_hour) > 23)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("hour must be between 0 and 23")));

				if (abs(tm->tm_min) < 0 || abs(tm->tm_min) > 59)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("minutes must be between 0 and 59")));

				if (abs(tm->tm_sec) < 0 || abs(tm->tm_sec) > 59)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("seconds must be between 0 and 59")));
				break;
			case INTERVAL_MASK(HOUR):
				if (abs(tm->tm_year) != INT_MAX ||
					abs(tm->tm_mon)  != INT_MAX ||
					abs(tm->tm_mday) != INT_MAX ||
					abs(tm->tm_min)  != INT_MAX ||
					abs(tm->tm_sec)  != INT_MAX ||
					abs(tm->tm_hour) == INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));
				break;
			case INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE):
				if (abs(tm->tm_year) != INT_MAX ||
					abs(tm->tm_mon)  != INT_MAX ||
					abs(tm->tm_mday) != INT_MAX ||
					abs(tm->tm_sec)  != INT_MAX ||
					abs(tm->tm_hour) == INT_MAX ||
					abs(tm->tm_min)  == INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));

				if (abs(tm->tm_min) < 0 || abs(tm->tm_min) > 59)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("minutes must be between 0 and 59")));
				break;
			case INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
				if (abs(tm->tm_year) != INT_MAX ||
					abs(tm->tm_mon)  != INT_MAX ||
					abs(tm->tm_mday) != INT_MAX ||
					abs(tm->tm_hour) == INT_MAX ||
					abs(tm->tm_min)  == INT_MAX ||
					abs(tm->tm_sec)  == INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));

				if (abs(tm->tm_min) < 0 || abs(tm->tm_min) > 59)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("minutes must be between 0 and 59")));

				if (abs(tm->tm_sec) < 0 || abs(tm->tm_sec) > 59)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("seconds must be between 0 and 59")));
				break;
			case INTERVAL_MASK(MINUTE):
				if (abs(tm->tm_year) != INT_MAX ||
					abs(tm->tm_mon)  != INT_MAX ||
					abs(tm->tm_mday) != INT_MAX ||
					abs(tm->tm_hour) != INT_MAX ||
					abs(tm->tm_sec)  != INT_MAX ||
					abs(tm->tm_min)  == INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));
				break;
			case INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
				if (abs(tm->tm_year) != INT_MAX ||
					abs(tm->tm_mon)  != INT_MAX ||
					abs(tm->tm_mday) != INT_MAX ||
					abs(tm->tm_hour) != INT_MAX ||
					abs(tm->tm_min)  == INT_MAX ||
					abs(tm->tm_sec)  == INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));

				if (abs(tm->tm_sec) < 0 || abs(tm->tm_sec) > 59)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("seconds must be between 0 and 59")));
				break;
			case INTERVAL_MASK(SECOND):
				if (abs(tm->tm_year) != INT_MAX ||
					abs(tm->tm_mon)  != INT_MAX ||
					abs(tm->tm_mday) != INT_MAX ||
					abs(tm->tm_hour) != INT_MAX ||
					abs(tm->tm_min)  != INT_MAX ||
					abs(tm->tm_sec)  == INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));
				break;
			default:
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("missing or invalid datetime field")));
		}

		/* reset the initial value to '0' */
		tm->tm_sec = (abs(tm->tm_sec) == INT_MAX) ? 0 : tm->tm_sec;
		tm->tm_min = (abs(tm->tm_min) == INT_MAX) ? 0 : tm->tm_min;
		tm->tm_hour = (abs(tm->tm_hour) == INT_MAX) ? 0 : tm->tm_hour;
		tm->tm_mday = (abs(tm->tm_mday) == INT_MAX) ? 0 : tm->tm_mday;

		/* Compatible oracle: if interval type is INTERVAL DAY TO SECOND that
		 * year and month are invalid.
		 */
		tm->tm_mon = 0;
		tm->tm_year = 0;
	}
	else
	{
		/* Interval is ISO8601 format
		 *
		 * Compatible oracle: if interval type is INTERVAL DAY TO SECOND that
		 * year and month can not be specified.
		 */
		if (abs(tm->tm_year) != 0 || abs(tm->tm_mon) != 0)
		{
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("The character string you specified is not a valid interval")));
		}

		tm->tm_mon = 0;
		tm->tm_year = 0;
	}

	result = (Interval *) palloc(sizeof(Interval));
	
	switch (dtype)
	{
		case DTK_DELTA:
			if (tm2dsinterval(tm, fsec, result) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("interval out of range")));
			break;

		default:
			elog(ERROR, "unexpected dtype %d while parsing interval \"%s\"",
				 dtype, str);
	}

	AdjustIntervalForTypmod(result, typmod);
	AdjustTypmodForDay(result, typmod);

	PG_RETURN_INTERVAL_P(result);
}

/*
 * dsinterval_out()
 * Convert a time span to external form.
 */
Datum
dsinterval_out(PG_FUNCTION_ARGS)
{
	Interval   *span = PG_GETARG_INTERVAL_P(0);
	int32		typmod;
	char	   *result;
	int			second_precision;
	int			day_precision;	
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;
	char		buf[MAXDATELEN + 1];

	if (interval2tm(*span, tm, &fsec) != 0)
		elog(ERROR, "could not convert interval to tm");

	if (PG_NARGS() >= 2)
		typmod = PG_GETARG_INT32(1);
	else
		typmod = -1;

	if (typmod >= 0)
	{
		second_precision = INTERVAL_SECOND_PRECISION(typmod);
		day_precision = INTERVAL_DAY_PRECISION(typmod);

		/* struct fcinfo not pass typmod */
		if (second_precision > ORACLE_MAX_INTERVAL_PRECISION)
		{
			ereport(WARNING,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			  errmsg("The typmod in dsinterval_out is invalid, second_precision reduced to maximum allowed, %d",
					 ORACLE_MAX_INTERVAL_PRECISION)));
			second_precision = ORACLE_MAX_INTERVAL_PRECISION;
		}

		if (day_precision > ORACLE_MAX_INTERVAL_PRECISION)
		{
			ereport(WARNING,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			  errmsg("The typmod in dsinterval_out is invalid, day_precision reduced to maximum allowed, %d",
					 ORACLE_MAX_INTERVAL_PRECISION)));
			day_precision = ORACLE_MAX_INTERVAL_PRECISION;
		}
	}
	else
	{
		day_precision = ORACLE_MAX_INTERVAL_PRECISION;
		second_precision = ORACLE_MAX_INTERVAL_PRECISION;
	}

	EncodeDsinterval(tm, fsec, INTSTYLE_SQL_STANDARD, buf, day_precision, second_precision);

	result = pstrdup(buf);
	PG_RETURN_CSTRING(result);
}

/*
 *	dsinterval_recv - converts external binary format to interval
 */
Datum
dsinterval_recv(PG_FUNCTION_ARGS)
{
	StringInfo	buf = (StringInfo) PG_GETARG_POINTER(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		typmod = PG_GETARG_INT32(2);
	Interval   *interval;

	interval = (Interval *) palloc(sizeof(Interval));

#ifdef HAVE_INT64_TIMESTAMP
	interval->time = pq_getmsgint64(buf);
#else
	interval->time = pq_getmsgfloat8(buf);
#endif
	interval->day = pq_getmsgint(buf, sizeof(interval->day));
	interval->month = pq_getmsgint(buf, sizeof(interval->month));

	AdjustIntervalForTypmod(interval, typmod);
	AdjustTypmodForDay(interval, typmod);

	PG_RETURN_INTERVAL_P(interval);
}

/*
 *	dsinterval_send - converts interval to binary format
 */
Datum
dsinterval_send(PG_FUNCTION_ARGS)
{
	Interval   *interval = PG_GETARG_INTERVAL_P(0);
	StringInfoData buf;

	pq_begintypsend(&buf);
#ifdef HAVE_INT64_TIMESTAMP
	pq_sendint64(&buf, interval->time);
#else
	pq_sendfloat8(&buf, interval->time);
#endif
	pq_sendint(&buf, interval->day, sizeof(interval->day));
	pq_sendint(&buf, interval->month, sizeof(interval->month));
	PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}

/*
 * dsinterval typmodin
 */
Datum
dsintervaltypmodin(PG_FUNCTION_ARGS)
{
	ArrayType  *ta = PG_GETARG_ARRAYTYPE_P(0);
	int32	   *tl;
	int			n;
	int32		typmod = -1;

	tl = ArrayGetIntegerTypmods(ta, &n);

	/*
	 * tl[0] - interval range (fields bitmask)
	 * tl[1] - precision (day_precision)
	 * tl[2] - precision (second_precision)
	 *
	 * tl[0] can not be INTERVAL_FULL_RANGE, because interval'100' is error syntax in oracle,
	 * 'precison' come from gram.y, so the value of 'n' must be equal or greater than 2.
	 */
	if (n >= 2)
	{
		switch (tl[0])
		{
			case INTERVAL_MASK(DAY):
			case INTERVAL_MASK(HOUR):
			case INTERVAL_MASK(MINUTE):
			case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR):
			case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE):
			case INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE):
				{
					if (n != 2)
					{
						ereport(ERROR,
								(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
								 errmsg("invalid INTERVAL type modifier")));
					}
					else
					{
						if (tl[1] < 0)
							ereport(ERROR,
									(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
									 errmsg("INTERVAL(%d) precision must not be negative",
											tl[1])));
						if (tl[1] > ORACLE_MAX_INTERVAL_PRECISION)
							ereport(ERROR,
									(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
									 errmsg("interval precision is out of range")));
						
						typmod = INTERVAL_DAY_TYPMOD(tl[1], tl[0]);	
					}
				}
				break;
			case INTERVAL_MASK(SECOND):
				{
					if (n < 2)
					{
						ereport(ERROR,
								(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
								 errmsg("invalid INTERVAL DAY TO SECOND type modifier")));
					}
					else if (n == 2)
					{
						if (tl[1] < 0)
							ereport(ERROR,
									(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
									 errmsg("INTERVAL(%d) precision must not be negative",
											tl[1])));
						if (tl[1] > ORACLE_MAX_INTERVAL_PRECISION)
							ereport(ERROR,
									(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
									 errmsg("interval precision is out of range")));
						
						typmod = INTERVAL_DS_TYPMOD(tl[1], 2, tl[0]);
					}
					else if (n == 3)
					{
						if (tl[1] < 0 || tl[2] < 0)
							ereport(ERROR,
									(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
									 errmsg("INTERVAL(%d) precision must not be negative",
											tl[1])));
						if (tl[1] > ORACLE_MAX_INTERVAL_PRECISION || tl[2] > ORACLE_MAX_INTERVAL_PRECISION)
							ereport(ERROR,
									(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
									 errmsg("interval precision is out of range")));
						
						typmod = INTERVAL_DS_TYPMOD(tl[2], tl[1], tl[0]);	
					}
				}
				break;
			case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
			case INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
			case INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
				{
					if (n != 3)
					{
						ereport(ERROR,
								(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
								 errmsg("invalid INTERVAL type modifier")));	
					}
					else
					{
						if (tl[1] < 0 || tl[2] < 0)
							ereport(ERROR,
									(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
									 errmsg("INTERVAL(%d) precision must not be negative",
											tl[1])));
						if (tl[1] > ORACLE_MAX_INTERVAL_PRECISION || tl[2] > ORACLE_MAX_INTERVAL_PRECISION)
							ereport(ERROR,
									(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
									 errmsg("interval precision is out of range")));
						
						typmod = INTERVAL_DS_TYPMOD(tl[2], tl[1], tl[0]);
					}
				}
				break;
			case INTERVAL_FULL_RANGE:
			default:
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
						 errmsg("missing or invalid datetime field")));
		}
	}
	else
	{
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("invalid INTERVAL DAY TO SECOND type modifier")));
		typmod = 0;				/* keep compiler quiet */
	}

	PG_RETURN_INT32(typmod);
}


Datum
dsintervaltypmodout(PG_FUNCTION_ARGS)
{
	int32		typmod = PG_GETARG_INT32(0);
	char	   *res = (char *) palloc(64);
	int			fields;
	int			day_precision, second_precision;

	if (typmod < 0)
	{
		*res = '\0';
		PG_RETURN_CSTRING(res);
	}

	fields = INTERVAL_RANGE(typmod);
	day_precision = INTERVAL_DAY_PRECISION(typmod);
	second_precision = INTERVAL_SECOND_PRECISION(typmod);

	switch (fields)
	{
		case INTERVAL_MASK(DAY):
		case INTERVAL_MASK(HOUR):
		case INTERVAL_MASK(MINUTE):
		case INTERVAL_MASK(SECOND):
		case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR):
		case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE):
		case INTERVAL_MASK(DAY) | INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
		case INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE):
		case INTERVAL_MASK(HOUR) | INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
		case INTERVAL_MASK(MINUTE) | INTERVAL_MASK(SECOND):
			{
				if (day_precision >= 0 && second_precision >=0)
					snprintf(res, 64, "%s(%d)%s(%d)", " day", day_precision, " to second", second_precision);
				else
					ereport(ERROR,
							(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
							 errmsg("invalid INTERVAL type modifier")));
			}
			break;
		case INTERVAL_FULL_RANGE:
		default:
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("invalid INTERVAL type modifier")));
			break;
	}

	PG_RETURN_CSTRING(res);
}


/*
 * dsinterval()
 * Adjust interval type for specified fields.
 * Used by PostgreSQL type system to stuff columns.
 */
Datum
dsinterval(PG_FUNCTION_ARGS)
{
	Interval   *interval = PG_GETARG_INTERVAL_P(0);
	int32		typmod = PG_GETARG_INT32(1);
	Interval   *result;

	result = palloc(sizeof(Interval));
	*result = *interval;

	AdjustIntervalForTypmod(result, typmod);
	AdjustTypmodForDay(result, typmod);

	PG_RETURN_INTERVAL_P(result);
}


/*****************************************************************************
 *	 Operator Function														 *
 *****************************************************************************/
Datum
dsinterval_eq(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(dsinterval_cmp_internal(interval1, interval2) == 0);
}

Datum
dsinterval_ne(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(dsinterval_cmp_internal(interval1, interval2) != 0);
}

Datum
dsinterval_lt(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(dsinterval_cmp_internal(interval1, interval2) < 0);
}

Datum
dsinterval_gt(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(dsinterval_cmp_internal(interval1, interval2) > 0);
}

Datum
dsinterval_le(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(dsinterval_cmp_internal(interval1, interval2) <= 0);
}

Datum
dsinterval_ge(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(dsinterval_cmp_internal(interval1, interval2) >= 0);
}

/*
 * '+' operator function
 * left operand = interval day to second
 * right operand = interval day to second
 */
Datum
dsinterval_pl(PG_FUNCTION_ARGS)
{
	Interval   *span1 = PG_GETARG_INTERVAL_P(0);
	Interval   *span2 = PG_GETARG_INTERVAL_P(1);
	Interval   *result;

	result = (Interval *) palloc(sizeof(Interval));

	result->day = span1->day + span2->day;
	if (SAMESIGN(span1->day, span2->day) &&
		!SAMESIGN(result->day, span1->day))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));

	result->time = span1->time + span2->time;
	if (SAMESIGN(span1->time, span2->time) &&
		!SAMESIGN(result->time, span1->time))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));

	/* 
	 * compatible oracle 
	 * For Interval day to second, the field of datetime 'YEAR' and 'MONTH' will be zero.
	 * Recompute the value of result->day and result->time .
	 */
	result->month = 0;
	result->day += result->time / USECS_PER_DAY;
	result->time = result->time % USECS_PER_DAY;

	PG_RETURN_INTERVAL_P(result);
}

/*
 * '-' operator function
 * left operand = interval day to second
 * right operand = interval day to second
 */
Datum
dsinterval_mi(PG_FUNCTION_ARGS)
{
	Interval   *span1 = PG_GETARG_INTERVAL_P(0);
	Interval   *span2 = PG_GETARG_INTERVAL_P(1);
	Interval   *result;
	TimeOffset	span1_usecs;
	TimeOffset	span2_usecs;

	span1_usecs = span1->time;
	span1_usecs += span1->day * INT64CONST(24) * USECS_PER_HOUR;
	
	span2_usecs = span2->time;
	span2_usecs += span2->day * INT64CONST(24) * USECS_PER_HOUR;

	result = (Interval *) palloc(sizeof(Interval));

	/* 
	 * Compatible oracle 
	 * For Interval day to second, the field of datetime 'YEAR' 'MONTH' will be zero.
	 * Recompute the value of result->day and result->time .
	 */
	result->month = 0;
	result->day = (span1_usecs - span2_usecs) / USECS_PER_DAY;
	result->time = (span1_usecs - span2_usecs) % USECS_PER_DAY;
	
	/* overflow check copied from int4mi */
	if (!SAMESIGN(span1->day, span2->day) &&
		!SAMESIGN(result->day, span1->day))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));

	if (!SAMESIGN(span1->time, span2->time) &&
		!SAMESIGN(result->time, span1->time))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));

	PG_RETURN_INTERVAL_P(result);
}

/*
 * '*' operator function
 * left operand = interval day to second 
 * right operand = number
 */
Datum
dsinterval_mul(PG_FUNCTION_ARGS)
{
	Interval   *span = PG_GETARG_INTERVAL_P(0);
	Numeric		num = PG_GETARG_NUMERIC(1);
	float8		factor;
	double		month_remainder_days,
				sec_remainder,
				result_double;
	int32		orig_month = span->month,
				orig_day = span->day;
	Interval   *result;

	factor = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
	result = (Interval *) palloc(sizeof(Interval));

	result_double = span->month * factor;
	if (result_double > INT_MAX || result_double < INT_MIN)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));
	result->month = (int32) result_double;

	result_double = span->day * factor;
	if (result_double > INT_MAX || result_double < INT_MIN)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));
	result->day = (int32) result_double;

	/*
	 * The above correctly handles the whole-number part of the month and day
	 * products, but we have to do something with any fractional part
	 * resulting when the factor is nonintegral.  We cascade the fractions
	 * down to lower units using the conversion factors DAYS_PER_MONTH and
	 * SECS_PER_DAY.  Note we do NOT cascade up, since we are not forced to do
	 * so by the representation.  The user can choose to cascade up later,
	 * using justify_hours and/or justify_days.
	 */

	/*
	 * Fractional months full days into days.
	 *
	 * Floating point calculation are inherently inprecise, so these
	 * calculations are crafted to produce the most reliable result possible.
	 * TSROUND() is needed to more accurately produce whole numbers where
	 * appropriate.
	 */
	month_remainder_days = (orig_month * factor - result->month) * DAYS_PER_MONTH;
	month_remainder_days = TSROUND(month_remainder_days);
	sec_remainder = (orig_day * factor - result->day +
		   month_remainder_days - (int) month_remainder_days) * SECS_PER_DAY;
	sec_remainder = TSROUND(sec_remainder);

	/*
	 * Might have 24:00:00 hours due to rounding, or >24 hours because of time
	 * cascade from months and days.  It might still be >24 if the combination
	 * of cascade and the seconds factor operation itself.
	 */
	if (Abs(sec_remainder) >= SECS_PER_DAY)
	{
		result->day += (int) (sec_remainder / SECS_PER_DAY);
		sec_remainder -= (int) (sec_remainder / SECS_PER_DAY) * SECS_PER_DAY;
	}

	/* cascade units down */
	result->day += (int32) month_remainder_days;
#ifdef HAVE_INT64_TIMESTAMP
	result_double = rint(span->time * factor + sec_remainder * USECS_PER_SEC);
	if (result_double > PG_INT64_MAX || result_double < PG_INT64_MIN)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));
	result->time = (int64) result_double;
#else
	result->time = span->time * factor + sec_remainder;
#endif

	/* 
	 * compatible oracle 
	 * For Interval day to second, the field of datetime 'year' 'month' will be truncated.
	 */
	result->month = 0;
	result->day += result->time / USECS_PER_DAY;
	result->time = result->time % USECS_PER_DAY;

	PG_RETURN_INTERVAL_P(result);
}

/*
 * '*' operator function
 * left operand = number
 * right operand = interval day to second 
 */
Datum
mul_d_dsinterval(PG_FUNCTION_ARGS)
{
	/* Args are number and Interval *, but leave them as generic Datum */
	Datum		factor = PG_GETARG_DATUM(0);
	Datum		span = PG_GETARG_DATUM(1);

	return DirectFunctionCall2(dsinterval_mul, span, factor);
}

/*
 * '/' operator function
 * left operand = interval day to second
 * right operand = number
 */
Datum
dsinterval_div(PG_FUNCTION_ARGS)
{
	Interval   *span = PG_GETARG_INTERVAL_P(0);
	Numeric		num = PG_GETARG_NUMERIC(1);
	float8		factor;
	double		month_remainder_days,
				sec_remainder;
	int32		orig_month = span->month,
				orig_day = span->day;
	Interval   *result;

	factor = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
	result = (Interval *) palloc(sizeof(Interval));

	if (factor == 0.0)
		ereport(ERROR,
				(errcode(ERRCODE_DIVISION_BY_ZERO),
				 errmsg("division by zero")));

	result->month = (int32) (span->month / factor);
	result->day = (int32) (span->day / factor);

	/*
	 * Fractional months full days into days.  See comment in interval_mul().
	 */
	month_remainder_days = (orig_month / factor - result->month) * DAYS_PER_MONTH;
	month_remainder_days = TSROUND(month_remainder_days);
	sec_remainder = (orig_day / factor - result->day +
		   month_remainder_days - (int) month_remainder_days) * SECS_PER_DAY;
	sec_remainder = TSROUND(sec_remainder);
	if (Abs(sec_remainder) >= SECS_PER_DAY)
	{
		result->day += (int) (sec_remainder / SECS_PER_DAY);
		sec_remainder -= (int) (sec_remainder / SECS_PER_DAY) * SECS_PER_DAY;
	}

	/* cascade units down */
	result->day += (int32) month_remainder_days;
#ifdef HAVE_INT64_TIMESTAMP
	result->time = rint(span->time / factor + sec_remainder * USECS_PER_SEC);
#else
	/* See TSROUND comment in interval_mul(). */
	result->time = span->time / factor + sec_remainder;
#endif

	/* 
	 * compatible oracle
	 * For Interval day to second, the field of datetime 'year' 'month' will be truncated.
	 */
	result->month = 0;
	result->day += result->time / USECS_PER_DAY;
	result->time = result->time % USECS_PER_DAY;

	PG_RETURN_INTERVAL_P(result);
}


/*****************************************************************************
 *	 B-tree index support procedure
 *****************************************************************************/
Datum
dsinterval_cmp(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_INT32(dsinterval_cmp_internal(interval1, interval2));
}

Datum
in_range_dsinterval_dsinterval(PG_FUNCTION_ARGS)
{
	Interval   *val = PG_GETARG_INTERVAL_P(0);
	Interval   *base = PG_GETARG_INTERVAL_P(1);
	Interval   *offset = PG_GETARG_INTERVAL_P(2);
	bool		sub = PG_GETARG_BOOL(3);
	bool		less = PG_GETARG_BOOL(4);
	Interval   *sum;

	if (int128_compare(int64_to_int128(dsinterval_cmp_value(offset)), int64_to_int128(0)) < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PRECEDING_OR_FOLLOWING_SIZE),
				 errmsg("invalid preceding or following size in window function")));

	/* We don't currently bother to avoid overflow hazards here */
	if (sub)
		sum = DatumGetIntervalP(DirectFunctionCall2(dsinterval_mi,
													IntervalPGetDatum(base),
													IntervalPGetDatum(offset)));
	else
		sum = DatumGetIntervalP(DirectFunctionCall2(dsinterval_pl,
													IntervalPGetDatum(base),
													IntervalPGetDatum(offset)));

	if (less)
		PG_RETURN_BOOL(dsinterval_cmp_internal(val, sum) <= 0);
	else
		PG_RETURN_BOOL(dsinterval_cmp_internal(val, sum) >= 0);
}

/*****************************************************************************
 *	 Hash index support procedure 
 *****************************************************************************/
 
/*
 * Hashing for intervals
 *
 * We must produce equal hashvals for values that yminterval_cmp_internal()
 * considers equal.  So, compute the net span the same way it does,
 * and then hash that, using either int64 or float8 hashing.
 */
Datum
dsinterval_hash(PG_FUNCTION_ARGS)
{
	Interval   *interval = PG_GETARG_INTERVAL_P(0);
	TimeOffset	span = dsinterval_cmp_value(interval);

	return DirectFunctionCall1(hashint8, Int64GetDatumFast(span));
}

Datum
dsinterval_hash_extended(PG_FUNCTION_ARGS)
{
	Interval   *interval = PG_GETARG_INTERVAL_P(0);
	INT128		span = int64_to_int128(dsinterval_cmp_value(interval));
	int64		span64;

	/* Same approach as interval_hash */
	span64 = int128_to_int64(span);

	return DirectFunctionCall2(hashint8extended, Int64GetDatumFast(span64),
							   PG_GETARG_DATUM(1));
}


/*****************************************************************************
 *	 AGGREGATE FUNCTION 
 *****************************************************************************/
Datum
dsinterval_smaller(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);
	Interval   *result;

	if (dsinterval_cmp_internal(interval1, interval2) < 0)
		result = interval1;
	else
		result = interval2;
	PG_RETURN_INTERVAL_P(result);
}

Datum
dsinterval_larger(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);
	Interval   *result;

	if (dsinterval_cmp_internal(interval1, interval2) > 0)
		result = interval1;
	else
		result = interval2;
	PG_RETURN_INTERVAL_P(result);
}
