/*-------------------------------------------------------------------------
 *
 * yminterval.c
 *
 * Compatible with Oracle's INTERVAL YEAR TO MONTH data type.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/yminterval.c
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

PG_FUNCTION_INFO_V1(yminterval_in);
PG_FUNCTION_INFO_V1(yminterval_out);
PG_FUNCTION_INFO_V1(ymintervaltypmodin);
PG_FUNCTION_INFO_V1(ymintervaltypmodout);
PG_FUNCTION_INFO_V1(yminterval_recv);
PG_FUNCTION_INFO_V1(yminterval_send);

PG_FUNCTION_INFO_V1(yminterval_eq);
PG_FUNCTION_INFO_V1(yminterval_ne);
PG_FUNCTION_INFO_V1(yminterval_lt);
PG_FUNCTION_INFO_V1(yminterval_gt);
PG_FUNCTION_INFO_V1(yminterval_le);
PG_FUNCTION_INFO_V1(yminterval_ge);
PG_FUNCTION_INFO_V1(yminterval_mul);
PG_FUNCTION_INFO_V1(mul_d_yminterval);
PG_FUNCTION_INFO_V1(yminterval_mi);
PG_FUNCTION_INFO_V1(yminterval_pl);
PG_FUNCTION_INFO_V1(yminterval_div);

PG_FUNCTION_INFO_V1(yminterval_cmp);
PG_FUNCTION_INFO_V1(in_range_yminterval_yminterval);

PG_FUNCTION_INFO_V1(yminterval_hash);
PG_FUNCTION_INFO_V1(yminterval_hash_extended);

PG_FUNCTION_INFO_V1(yminterval_smaller);
PG_FUNCTION_INFO_V1(yminterval_larger);

PG_FUNCTION_INFO_V1(yminterval);


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
	char	   *cp;
	int			dterr;

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

/* we will do check in dsinterval_in */

	/* do a sanity check */
/*
#ifdef HAVE_INT64_TIMESTAMP
	if (tm->tm_hour < 0 || tm->tm_min < 0 || tm->tm_min > MINS_PER_HOUR - 1 ||
		tm->tm_sec < 0 || tm->tm_sec > SECS_PER_MINUTE ||
		*fsec < INT64CONST(0) ||
		*fsec > USECS_PER_SEC)
		return DTERR_FIELD_OVERFLOW;
#else
	if (tm->tm_hour < 0 || tm->tm_min < 0 || tm->tm_min > MINS_PER_HOUR - 1 ||
		tm->tm_sec < 0 || tm->tm_sec > SECS_PER_MINUTE ||
		*fsec < 0 || *fsec > 1)
		return DTERR_FIELD_OVERFLOW;
#endif
*/
	return 0;
}

/*
 * ClearPgTM
 * Zero out a pg_tm and associated fsec_t
 * compatible oracle
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
 * TrimTrailingZeros()
 * ... resulting from printing numbers with full precision.
 *
 * Before Postgres 8.4, this always left at least 2 fractional digits,
 * but conversations on the lists suggest this isn't desired
 * since showing '0.10' is misleading with values of precision(1).
 */
static void
TrimTrailingZeros(char *str)
{
	int			len = strlen(str);

	while (len > 1 && *(str + len - 1) == '0' && *(str + len - 2) != '.')
	{
		len--;
		*(str + len) = '\0';
	}
}

/*
 * Append sections and fractional seconds (if any) at *cp.
 * precision is the max number of fraction digits, fillzeros says to
 * pad to two integral-seconds digits.
 * Note that any sign is stripped from the input seconds values.
 */
static void
AppendSeconds(char *cp, int sec, fsec_t fsec, int precision, bool fillzeros)
{
	if (fsec == 0)
	{
		if (fillzeros)
			sprintf(cp, "%02d", abs(sec));
		else
			sprintf(cp, "%d", abs(sec));
	}
	else
	{
#ifdef HAVE_INT64_TIMESTAMP
		if (fillzeros)
			sprintf(cp, "%02d.%0*d", abs(sec), precision, (int) Abs(fsec));
		else
			sprintf(cp, "%d.%0*d", abs(sec), precision, (int) Abs(fsec));
#else
		if (fillzeros)
			sprintf(cp, "%0*.*f", precision + 3, precision, fabs(sec + fsec));
		else
			sprintf(cp, "%.*f", precision, fabs(sec + fsec));
#endif
		TrimTrailingZeros(cp);
	}
}

/*
 * EncodeYminterval()
 * Interpret time structure as a delta time and convert to string.
 */
static void
EncodeYminterval(struct pg_tm * tm, fsec_t fsec, int style, char *str, int precision)
{
	char	   *cp = str;
	int			year = tm->tm_year;
	int			mon = tm->tm_mon;
	int			mday = tm->tm_mday;
	int			hour = tm->tm_hour;
	int			min = tm->tm_min;
	int			sec = tm->tm_sec;

	/*
	 * The sign of year and month are guaranteed to match, since they are
	 * stored internally as "month". But we'll need to check for is_before and
	 * is_zero when determining the signs of day and hour/minute/seconds
	 * fields.
	 */
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
				
				/* Compatible oracle, the value of interval is zero should show "+00-00" */
				if (!has_negative && !has_positive)
				{
					sprintf(cp, "%0*d-%02d", precision, year, mon);
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
					AppendSeconds(cp, sec, fsec, MAX_INTERVAL_PRECISION, true);
				}
				else if (has_year_month)
				{
					sprintf(cp, "%0*d-%02d", precision, year, mon);
				}
				else if (has_day)
				{
					sprintf(cp, "%d %d:%02d:", mday, hour, min);
					cp += strlen(cp);
					AppendSeconds(cp, sec, fsec, MAX_INTERVAL_PRECISION, true);
				}
				else
				{
					sprintf(cp, "%d:%02d:", hour, min);
					cp += strlen(cp);
					AppendSeconds(cp, sec, fsec, MAX_INTERVAL_PRECISION, true);
				}
			}
			break;
		case INTSTYLE_ISO_8601:
		case INTSTYLE_POSTGRES:
		case INTSTYLE_POSTGRES_VERBOSE:
		default:
			ereport(ERROR,
					(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
					 errmsg("Invalid interval format")));
			break;
	}
}

/*
 * DecodeYminterval()
 * Interpret previously parsed fields for general time interval.
 * Returns 0 if successful, DTERR code if bogus input detected.
 * dtype, tm, fsec are output parameters.
 *
 * Allow "date" field DTK_DATE since this could be just
 *	an unsigned floating point number. - thomas 1997-11-16
 *
 * Allow ISO-style time span, with implicit units on number of days
 *	preceding an hh:mm:ss field. - thomas 1998-04-30
 */
static int
DecodeYminterval(char **field, int *ftype, int nf, int range,
			   int *dtype, struct tm * tm, fsec_t *fsec)
{
	bool		is_before = false;
	char	   *cp;
	int			fmask = 0,
				tmask,
				type;
	int			i;
	int			dterr;
	int			val;
	int			val2 = INT_MAX;
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
							type = DTK_YEAR;
							break;
						case INTERVAL_MASK(MONTH):
							type = DTK_MONTH;
							break;
						case INTERVAL_MASK(YEAR) | INTERVAL_MASK(MONTH):
							type = DTK_DATE;
							break;
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

				if (*cp == '-')
				{
					/* SQL "years-months" syntax */
					val2 = strtoi(cp + 1, &cp, 10);
					if (errno == ERANGE || val2 < 0 || val2 >= MONTHS_PER_YEAR)
						return DTERR_FIELD_OVERFLOW;
					if (*cp != '\0')
						return DTERR_BAD_FORMAT;
					type = DTK_DATE;
					if (*field[i] == '-')
						val2 = -val2;
					if (((double) val * MONTHS_PER_YEAR + val2) > INT_MAX ||
						((double) val * MONTHS_PER_YEAR + val2) < INT_MIN)
						return DTERR_FIELD_OVERFLOW;
//					val = val * MONTHS_PER_YEAR + val2;
					fval = 0;
				}
				else if (*cp == '.')
				{
					errno = 0;
					fval = strtod(cp, &cp);
					if (*cp != '\0' || errno != 0)
						return DTERR_BAD_FORMAT;

					if (*field[i] == '-')
						fval = -fval;
				}
				else if (*cp == '\0')
				{
					fval = 0;
					val2 = INT_MAX;
				}
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
						
					case DTK_DATE:
						if (tm->tm_year == INT_MAX)
							tm->tm_year = 0;
						if (tm->tm_mon == INT_MAX)
							tm->tm_mon = 0;
						
						tm->tm_year += val;
						tm->tm_mon += val2;
						
						if (fval != 0)
							tm->tm_mon += fval * MONTHS_PER_YEAR;
						tmask = DTK_M(MONTH);
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
	 *	 '-1 1:00:00'
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
 *	Adjust interval year to month for specified precision
 */
static void
AdjustYmintervalForTypmod(Interval *interval, int32 typmod)
{
	if (typmod > 0)
	{
		int		range = INTERVAL_RANGE(typmod);
		int		precision = INTERVAL_PRECISION(typmod);
		int64	interval_year;
		
		if (range == INTERVAL_MASK(YEAR) ||
			range == INTERVAL_MASK(MONTH) ||
			range == (INTERVAL_MASK(YEAR) | INTERVAL_MASK(MONTH)))
		{
			interval_year = abs(interval->month / MONTHS_PER_YEAR);
			switch(precision)
			{
				case 0:
					if (interval_year != 0)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 1:
					if (interval_year >= 10)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 2:
					if (interval_year >= 100)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 3:
					if (interval_year >= 1000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 4:
					if (interval_year >= 10000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 5:
					if (interval_year >= 100000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 6:
					if (interval_year >= 1000000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 7:
					if (interval_year >= 10000000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 8:
					if (interval_year >= 100000000)
						ereport(ERROR,
								(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
								 errmsg("Leading precision of the interval is too small")));
					break;
				case 9:
					if (interval_year >= 1000000000)
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
	*fsec = 0;

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

static int
tm2interval(struct tm *tm, fsec_t fsec, Interval *span)
{
	double		total_months = (double) tm->tm_year * MONTHS_PER_YEAR + tm->tm_mon;

	if (total_months > INT_MAX || total_months < INT_MIN)
		return -1;
	span->month = total_months;
	span->day = tm->tm_mday;
	span->time = (((((tm->tm_hour * INT64CONST(60)) +
					 tm->tm_min) * INT64CONST(60)) +
				   tm->tm_sec) * USECS_PER_SEC) + fsec;

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

/*
 * Compatible oracle
 * For INTERVAL YEAR TO MONTH type the field of "day" and "time" is invalid.
 * Only calculate the value of "interval->month".
 */
static inline TimeOffset
yminterval_cmp_value(const Interval *interval)
{
	TimeOffset	span;

//	span = interval->time;
	span = 0;

#ifdef HAVE_INT64_TIMESTAMP
	span += interval->month * INT64CONST(30) * USECS_PER_DAY;
//	span += interval->day * INT64CONST(24) * USECS_PER_HOUR;
#else
	span += interval->month * ((double) DAYS_PER_MONTH * SECS_PER_DAY);
//	span += interval->day * ((double) HOURS_PER_DAY * SECS_PER_HOUR);
#endif

	return span;
}

static int
yminterval_cmp_internal(Interval *interval1, Interval *interval2)
{
	TimeOffset	span1 = yminterval_cmp_value(interval1);
	TimeOffset	span2 = yminterval_cmp_value(interval2);

	return ((span1 < span2) ? -1 : (span1 > span2) ? 1 : 0);
}

/* yminterval_in()
 * Convert a string to internal form.
 *
 * External format(s):
 *	Uses the generic date/time parsing and decoding routines.
 */
Datum
yminterval_in(PG_FUNCTION_ARGS)
{
	char	   *str = PG_GETARG_CSTRING(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		typmod = PG_GETARG_INT32(2);
	Interval   *result;
	fsec_t		fsec;
	struct	tm  tt,
			   *tm = &tt;
	int			dtype = -1;
	int			nf;
	int			range;
	int			dterr;
	char	   *field[MAXDATEFIELDS];
	int			ftype[MAXDATEFIELDS];
	char		workbuf[256];
	bool		isiso = false;
	char 		*strold;
	char 		*strsrc;
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

	strold = str;
	strsrc = str;
	while (*strold != '\0')
	{
		if (*strold == ' ')
		{
			while (*(strold + 1) == ' ')
				strold++;
			if (*(strold + 1) == '-')
			{
				strold++;
				*strsrc++ = *strold++;
				while (*strold == ' ')
					strold++;

				if (*strold == '\0')
					break;
			}
		}
		else if (*strold == '-' && *(strold + 1) == ' ')
		{
			*strsrc++ = *strold++;
			while (*(strold) == ' ')
				strold++;

			if (*strold == '\0')
				break;
		}
		*strsrc++ = *strold++;
	}
	*strsrc = *strold;

	dterr = ParseDateTime(str, workbuf, sizeof(workbuf), field,
						  ftype, MAXDATEFIELDS, &nf);
	if (dterr == 0)
		dterr = DecodeYminterval(field, ftype, nf, range,
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
		DateTimeParseError(dterr, &extra, str, "interval year to month", NULL);
	}

	/* 
	 * compatible oracle, the valid range of values for the trailing field
	 * MONTH: 0 to 11
	 *
	 * In oracle, the string and interval fields is exact matched,
	 * for example:interval'1:1' hour to second and interval'1 1:1:1' hour to second is error.
	 * change the initial value of 'pg_tm *tm' to INT_MAX, because if the value of 'pg_tm *tm' is 0,
	 * we can not know  the '0' is initial value or the value of the input.
	 */
	if(!isiso)
	{
		switch(range)
		{
			case INTERVAL_MASK(YEAR):
				if (abs(tm->tm_year) == INT_MAX ||
					abs(tm->tm_mon)  != INT_MAX ||
					abs(tm->tm_min)  != INT_MAX ||
					abs(tm->tm_sec)  != INT_MAX ||
					abs(tm->tm_hour) != INT_MAX ||
					abs(tm->tm_mday) != INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));
				break;

			case INTERVAL_MASK(MONTH):
				if (abs(tm->tm_year) != INT_MAX ||
					abs(tm->tm_mon)  == INT_MAX ||
					abs(tm->tm_min)  != INT_MAX ||
					abs(tm->tm_sec)  != INT_MAX ||
					abs(tm->tm_hour) != INT_MAX ||
					abs(tm->tm_mday) != INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));
				break;

			case INTERVAL_MASK(YEAR) | INTERVAL_MASK(MONTH):
			case INTERVAL_FULL_RANGE:
				if (abs(tm->tm_year) == INT_MAX ||
					abs(tm->tm_mon)  == INT_MAX ||
					abs(tm->tm_min)  != INT_MAX ||
					abs(tm->tm_sec)  != INT_MAX ||
					abs(tm->tm_hour) != INT_MAX ||
					abs(tm->tm_mday) != INT_MAX)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("The character string you specified is not a valid interval")));

				if (abs(tm->tm_mon) < 0 || abs(tm->tm_mon) > 11)
					ereport(ERROR,
							(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
							 errmsg("month must be between 0 and 11")));
				break;

			default:
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("missing or invalid datetime field")));
		}

		/* reset the initial value to '0' */
		tm->tm_mon = (abs(tm->tm_mon) == INT_MAX) ? 0 : tm->tm_mon;
		tm->tm_year = (abs(tm->tm_year) == INT_MAX) ? 0 : tm->tm_year;

		/* Compatible oracle: if interval type is INTERVAL YEAR TO MONTH that
		 * days, hours, minutes, seconds, and frac_secs are invalid.
		 */
		tm->tm_sec = 0;
		tm->tm_min = 0;
		tm->tm_hour = 0;
		tm->tm_mday = 0;
		fsec = 0;
	}
	else
	{
		/* Interval is ISO8601 format 
		 *
		 * Compatible oracle: if interval type is INTERVAL YEAR TO MONTH that
		 * days, hours, minutes, seconds, and frac_secs are ignored.
		 */
		tm->tm_sec = 0;
		tm->tm_min = 0;
		tm->tm_hour = 0;
		tm->tm_mday = 0;
		fsec = 0;
	}

	result = (Interval *) palloc(sizeof(Interval));

	switch (dtype)
	{
		case DTK_DELTA:
			if (tm2interval(tm, fsec, result) != 0)
				ereport(ERROR,
						(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
						 errmsg("interval year to month out of range")));
			break;

		default:
			elog(ERROR, "unexpected dtype %d while parsing interval \"%s\"",
				 dtype, str);
	}

	AdjustYmintervalForTypmod(result, typmod);
	
	PG_RETURN_INTERVAL_P(result);
}

/*
 * yminterval_out()
 * Convert a time span to external form.
 */
Datum
yminterval_out(PG_FUNCTION_ARGS)
{
	Interval   *span = PG_GETARG_INTERVAL_P(0);
	int32		typmod;
	int		precision;
	char	   *result;
	struct pg_tm tt,
			   *tm = &tt;
	fsec_t		fsec;
	char		buf[MAXDATELEN + 1];

	if (interval2tm(*span, tm, &fsec) != 0)
		elog(ERROR, "could not convert interval to tm");

	/* some situations like array_out doesn't supply typmod */
	if (PG_NARGS() >= 2)
		typmod = PG_GETARG_INT32(1);
	else
		typmod = -1;

	if (typmod >= 0)
	{
		precision = INTERVAL_PRECISION(typmod);

		/* struct fcinfo not pass typmod */
		if (precision > ORACLE_MAX_INTERVAL_PRECISION)
		{
			ereport(WARNING,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("The typmod in yminterval_out is invalid, reduced to maximum allowed, %d",
					 ORACLE_MAX_INTERVAL_PRECISION)));
			precision = ORACLE_MAX_INTERVAL_PRECISION;
		}
	}
	else
	{
		precision = ORACLE_MAX_INTERVAL_PRECISION;
	}

	EncodeYminterval(tm, fsec, INTSTYLE_SQL_STANDARD, buf, precision);

	result = pstrdup(buf);
	PG_RETURN_CSTRING(result);
}

Datum
ymintervaltypmodin(PG_FUNCTION_ARGS)
{
	ArrayType  *ta = PG_GETARG_ARRAYTYPE_P(0);
	int32	   *tl;
	int			n;
	int32		typmod;

	tl = ArrayGetIntegerTypmods(ta, &n);

	/*
	 * tl[0] - interval range (fields bitmask)	tl[1] - precision (optional)
	 *
	 * Note we must validate tl[0] even though it's normally guaranteed
	 * correct by the grammar --- consider SELECT 'foo'::"interval"(1000).
	 */
	if (n > 0)
	{
		switch (tl[0])
		{
			case INTERVAL_MASK(YEAR):
			case INTERVAL_MASK(MONTH):
			case INTERVAL_MASK(YEAR) | INTERVAL_MASK(MONTH):
			case INTERVAL_FULL_RANGE:
				/* all OK */
				break;
			default:
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
						 errmsg("invalid INTERVAL type modifier")));
		}
	}

	/* here do: YEAR default precision is 2 */
	if (n == 1)
	{
		if (tl[0] != INTERVAL_FULL_RANGE)
			typmod = INTERVAL_TYPMOD(2, tl[0]);
		else
			typmod = -1;
	}
	else if (n == 2)
	{
		if (tl[1] < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("INTERVAL(%d) precision must not be negative",
							tl[1])));

		if (tl[1] > ORACLE_MAX_INTERVAL_PRECISION)
		{
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("INTERVAL YEAR(%d) TO MONTH precision out of range",
							tl[1])));
		}
		else
			typmod = INTERVAL_TYPMOD(tl[1], tl[0]);
	}
	else
	{
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("invalid INTERVAL type modifier")));
		typmod = 0;				/* keep compiler quiet */
	}

	PG_RETURN_INT32(typmod);
}

Datum
ymintervaltypmodout(PG_FUNCTION_ARGS)
{
	int32		typmod = PG_GETARG_INT32(0);
	char	   *res = (char *) palloc(64);
	int			fields;
	int			precision;
	const char *fieldstr_year;
	const char *fieldstr_month;

	if (typmod < 0)
	{
		*res = '\0';
		PG_RETURN_CSTRING(res);
	}

	fields = INTERVAL_RANGE(typmod);
	precision = INTERVAL_PRECISION(typmod);

	switch (fields)
	{
		case INTERVAL_MASK(YEAR):
		case INTERVAL_MASK(MONTH):
		case INTERVAL_MASK(YEAR) | INTERVAL_MASK(MONTH):
			fieldstr_year = " year";
			fieldstr_month = " to month";
			if (precision >= 0)
				snprintf(res, 64, "%s(%d)%s", fieldstr_year, precision, fieldstr_month);
			else
				snprintf(res, 64, "%s%s", fieldstr_year, fieldstr_month);
			break;
		case INTERVAL_FULL_RANGE:
			fieldstr_year = "";
			if (precision >= 0)
				snprintf(res, 64, "%s(%d)", fieldstr_year, precision);
			else
				snprintf(res, 64, "%s", fieldstr_year);
			break;
		default:
			elog(ERROR, "invalid INTERVAL typmod: 0x%x", typmod);
			break;
	}

	PG_RETURN_CSTRING(res);
}

/*
 *	yminterval_recv - converts external binary format to interval
 */
Datum
yminterval_recv(PG_FUNCTION_ARGS)
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

	AdjustYmintervalForTypmod(interval, typmod);
	
	PG_RETURN_INTERVAL_P(interval);
}

/*
 *	yminterval_send - converts interval to binary format
 */
Datum
yminterval_send(PG_FUNCTION_ARGS)
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
 * yminterval()
 * Adjust interval type for specified fields.
 * Used by PostgreSQL type system to stuff columns.
 */
Datum
yminterval(PG_FUNCTION_ARGS)
{
	Interval   *interval = PG_GETARG_INTERVAL_P(0);
	int32		typmod = PG_GETARG_INT32(1);
	Interval   *result;

	result = palloc(sizeof(Interval));
	*result = *interval;

	AdjustYmintervalForTypmod(result, typmod);

	PG_RETURN_INTERVAL_P(result);
}

/*****************************************************************************
 *	 Operator Function														 *
 *****************************************************************************/
Datum
yminterval_eq(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(yminterval_cmp_internal(interval1, interval2) == 0);
}

Datum
yminterval_ne(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(yminterval_cmp_internal(interval1, interval2) != 0);
}

Datum
yminterval_lt(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(yminterval_cmp_internal(interval1, interval2) < 0);
}

Datum
yminterval_gt(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(yminterval_cmp_internal(interval1, interval2) > 0);
}

Datum
yminterval_le(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(yminterval_cmp_internal(interval1, interval2) <= 0);
}

Datum
yminterval_ge(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_BOOL(yminterval_cmp_internal(interval1, interval2) >= 0);
}

/*
 * '*' operator function
 * left operand = interval year to month
 * right operand = number
 */
Datum
yminterval_mul(PG_FUNCTION_ARGS)
{
	Interval   *span = PG_GETARG_INTERVAL_P(0);
	Numeric		num = PG_GETARG_NUMERIC(1);
	float8		factor;
	double		result_double;
	Interval   *result;

	factor = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
	result = (Interval *) palloc(sizeof(Interval));

	result_double = span->month * factor;
	if (result_double > INT_MAX || result_double < INT_MIN)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));
	result->month = (int32) result_double;

	/* 
	 * compatible oracle
	 * For Interval year to month, the field of datetime 'DAY' 'HOUR' 'MINUTE' 'SECOND' will be truncated.
	 */
	result->day = 0;
	result->time = 0;

	PG_RETURN_INTERVAL_P(result);
}

/*
 * '*' operator function
 * left operand = number
 * right operand = interval year to month 
 */
Datum
mul_d_yminterval(PG_FUNCTION_ARGS)
{
	Numeric		num = PG_GETARG_NUMERIC(0);
	Interval   *span = PG_GETARG_INTERVAL_P(1);
	float8		factor;
	double		result_double;
	Interval   *result;

	factor = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
	result = (Interval *) palloc(sizeof(Interval));

	result_double = span->month * factor;
	if (result_double > INT_MAX || result_double < INT_MIN)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));
	result->month = (int32) result_double;

	/*
	 * compatible oracle
	 * For Interval year to month, the field of datetime 'DAY' 'HOUR' 'MINUTE' 'SECOND' will be truncated.
	 */
	result->day = 0;
	result->time = 0;

	PG_RETURN_INTERVAL_P(result);
}

/*
 * '-' operator function
 * left operand = interval year to month
 * right operand = interval year to month
 */
Datum
yminterval_mi(PG_FUNCTION_ARGS)
{
	Interval   *span1 = PG_GETARG_INTERVAL_P(0);
	Interval   *span2 = PG_GETARG_INTERVAL_P(1);
	Interval   *result;

	result = (Interval *) palloc(sizeof(Interval));

	result->month = span1->month - span2->month;
	/* overflow check copied from int4mi */
	if (!SAMESIGN(span1->month, span2->month) &&
		!SAMESIGN(result->month, span1->month))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));

	/* 
	 * compatible oracle
	 * For Interval year to month, the field of datetime 'DAY' 'HOUR' 'MINUTE' 'SECOND' will be zero.
	 */
	result->day = 0;
	result->time = 0;

	PG_RETURN_INTERVAL_P(result);
}

/*
 * '+' operator function
 * left operand = interval year to month
 * right operand = interval year to month
 */
Datum
yminterval_pl(PG_FUNCTION_ARGS)
{
	Interval   *span1 = PG_GETARG_INTERVAL_P(0);
	Interval   *span2 = PG_GETARG_INTERVAL_P(1);
	Interval   *result;

	result = (Interval *) palloc(sizeof(Interval));

	result->month = span1->month + span2->month;
	/* overflow check copied from int4pl */
	if (SAMESIGN(span1->month, span2->month) &&
		!SAMESIGN(result->month, span1->month))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("interval out of range")));

	/* 
	 * compatible oracle
	 * For Interval year to month, the field of datetime 'DAY' 'HOUR' 'MINUTE' 'SECOND' will be zero.
	 */
	result->day = 0;
	result->time = 0;

	PG_RETURN_INTERVAL_P(result);
}

/*
 * '/' operator function
 * left operand = interval year to month
 * right operand = number
 */
Datum
yminterval_div(PG_FUNCTION_ARGS)
{
	Interval   *span = PG_GETARG_INTERVAL_P(0);
	Numeric		num = PG_GETARG_NUMERIC(1);
	float8		factor;
	Interval   *result;

	factor = DatumGetFloat8(DirectFunctionCall1(numeric_float8, NumericGetDatum(num)));
	result = (Interval *) palloc(sizeof(Interval));

	if (factor == 0.0)
		ereport(ERROR,
				(errcode(ERRCODE_DIVISION_BY_ZERO),
				 errmsg("division by zero")));

	result->month = (int32) (span->month / factor);

	/*
	 * compatible oracle
	 * For Interval year to month, the field of datetime 'DAY' 'HOUR' 'MINUTE' 'SECOND' will be zero.
	 */
	result->day = 0;
	result->time = 0;

	PG_RETURN_INTERVAL_P(result);
}

/*****************************************************************************
 *	 B-tree index support procedure
 *****************************************************************************/
Datum
yminterval_cmp(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);

	PG_RETURN_INT32(yminterval_cmp_internal(interval1, interval2));
}

Datum
in_range_yminterval_yminterval(PG_FUNCTION_ARGS)
{
	Interval   *val = PG_GETARG_INTERVAL_P(0);
	Interval   *base = PG_GETARG_INTERVAL_P(1);
	Interval   *offset = PG_GETARG_INTERVAL_P(2);
	bool		sub = PG_GETARG_BOOL(3);
	bool		less = PG_GETARG_BOOL(4);
	Interval   *sum;

	if (int128_compare(int64_to_int128(yminterval_cmp_value(offset)), int64_to_int128(0)) < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PRECEDING_OR_FOLLOWING_SIZE),
				 errmsg("invalid preceding or following size in window function")));

	/* We don't currently bother to avoid overflow hazards here */
	if (sub)
		sum = DatumGetIntervalP(DirectFunctionCall2(yminterval_mi,
													IntervalPGetDatum(base),
													IntervalPGetDatum(offset)));
	else
		sum = DatumGetIntervalP(DirectFunctionCall2(yminterval_pl,
													IntervalPGetDatum(base),
													IntervalPGetDatum(offset)));

	if (less)
		PG_RETURN_BOOL(yminterval_cmp_internal(val, sum) <= 0);
	else
		PG_RETURN_BOOL(yminterval_cmp_internal(val, sum) >= 0);
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
yminterval_hash(PG_FUNCTION_ARGS)
{
	Interval   *interval = PG_GETARG_INTERVAL_P(0);
	TimeOffset	span = yminterval_cmp_value(interval);

	return DirectFunctionCall1(hashint8, Int64GetDatumFast(span));
}

Datum
yminterval_hash_extended(PG_FUNCTION_ARGS)
{
	Interval   *interval = PG_GETARG_INTERVAL_P(0);
	INT128		span = int64_to_int128(yminterval_cmp_value(interval));
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
yminterval_smaller(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);
	Interval   *result;

	/* use yminterval_cmp_internal to be sure this agrees with comparisons */
	if (yminterval_cmp_internal(interval1, interval2) < 0)
		result = interval1;
	else
		result = interval2;
	PG_RETURN_INTERVAL_P(result);
}

Datum
yminterval_larger(PG_FUNCTION_ARGS)
{
	Interval   *interval1 = PG_GETARG_INTERVAL_P(0);
	Interval   *interval2 = PG_GETARG_INTERVAL_P(1);
	Interval   *result;

	if (yminterval_cmp_internal(interval1, interval2) > 0)
		result = interval1;
	else
		result = interval2;
	PG_RETURN_INTERVAL_P(result);
}
