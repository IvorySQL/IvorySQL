/*-------------------------------------------------------------------------
 * Copyright 2026 IvorySQL Global Development Team
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * scheduler_calendar.c
 *
 * Oracle DBMS_SCHEDULER calendaring syntax engine (core subset):
 *
 *   FREQ=YEARLY|MONTHLY|WEEKLY|DAILY|HOURLY|MINUTELY|SECONDLY   (mandatory)
 *   INTERVAL=1..99
 *   BYMONTH=JAN..DEC | 1..12          (comma separated)
 *   BYMONTHDAY=-31..-1 | 1..31        (negative counts from month end)
 *   BYDAY=[[-]n]MON..SUN              (ordinal prefix only for YEARLY/MONTHLY)
 *   BYHOUR=0..23
 *   BYMINUTE=0..59
 *   BYSECOND=0..59
 *
 * Evaluation follows Oracle semantics: the repeat pattern is anchored at
 * start_date and date/time components not constrained by a BY clause are
 * inherited from start_date.  All evaluation happens in the session's
 * time zone.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_scheduler/scheduler_calendar.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <limits.h>

#include "miscadmin.h"
#include "pgtime.h"
#include "utils/builtins.h"
#include "utils/datetime.h"
#include "utils/timestamp.h"

#include "dbms_scheduler.h"

typedef enum SchedFreq
{
	FREQ_YEARLY,
	FREQ_MONTHLY,
	FREQ_WEEKLY,
	FREQ_DAILY,
	FREQ_HOURLY,
	FREQ_MINUTELY,
	FREQ_SECONDLY
} SchedFreq;

typedef struct SchedByDay
{
	int			dow;			/* 0 = Sunday .. 6 = Saturday */
	int			ord;			/* 0 = every, else 1..5 / -1..-5 within month */
} SchedByDay;

typedef struct CalendarRule
{
	SchedFreq	freq;
	int			interval;

	bool		bymonth[13];	/* index 1..12 */
	bool		has_bymonth;

	int			bymonthday[62];
	int			n_bymonthday;

	SchedByDay	byday[64];
	int			n_byday;
	bool		byday_has_ord;

	bool		byhour[24];
	bool		has_byhour;

	bool		byminute[60];
	bool		has_byminute;

	bool		bysecond[60];
	bool		has_bysecond;
} CalendarRule;

/* Search this many periods past the fast-forward point before giving up. */
#define SCHED_MAX_PERIODS	4000

static void parse_calendar(const char *calendar, CalendarRule *rule);
static bool eval_calendar(const CalendarRule *rule, TimestampTz start,
						  TimestampTz after, TimestampTz *next);

/*
 * sched_calendar_validate - syntax-check a calendar string.
 */
void
sched_calendar_validate(const char *calendar)
{
	CalendarRule rule;

	parse_calendar(calendar, &rule);
}

/*
 * sched_calendar_next - first timestamp matching "calendar" that is
 * strictly after "after" and not before "start_date".
 */
bool
sched_calendar_next(const char *calendar, TimestampTz start_date,
					TimestampTz after, TimestampTz *next)
{
	CalendarRule rule;

	parse_calendar(calendar, &rule);
	return eval_calendar(&rule, start_date, after, next);
}

/* ------------------------------------------------------------------
 * Parsing
 * ------------------------------------------------------------------
 */

static const char *const month_names[] = {
	"JAN", "FEB", "MAR", "APR", "MAY", "JUN",
	"JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
};

/* Oracle day names, mapped to 0 = Sunday .. 6 = Saturday */
static const struct
{
	const char *name;
	int			dow;
}			day_names[] =

{
	{"SUN", 0}, {"MON", 1}, {"TUE", 2}, {"WED", 3},
	{"THU", 4}, {"FRI", 5}, {"SAT", 6}
};

static void
calendar_error(const char *calendar, const char *detail)
{
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("invalid calendar string \"%s\"", calendar),
			 errdetail("%s", detail)));
}

/* Return an upper-cased copy of s with all whitespace removed. */
static char *
normalize_calendar(const char *s)
{
	char	   *out = palloc(strlen(s) + 1);
	int			n = 0;

	for (; *s; s++)
	{
		if (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r')
			continue;
		out[n++] = pg_toupper((unsigned char) *s);
	}
	out[n] = '\0';
	return out;
}

/* Parse a decimal integer (with optional sign); returns false on garbage. */
static bool
parse_int(const char *s, int len, int *result)
{
	int			val = 0;
	int			sign = 1;
	int			i = 0;

	if (len > 0 && (s[0] == '-' || s[0] == '+'))
	{
		sign = (s[0] == '-') ? -1 : 1;
		i = 1;
	}
	if (i >= len)
		return false;
	for (; i < len; i++)
	{
		if (s[i] < '0' || s[i] > '9')
			return false;
		if (val > (INT_MAX - 9) / 10)
			return false;
		val = val * 10 + (s[i] - '0');
	}
	*result = sign * val;
	return true;
}

/*
 * Parse one comma separated value list, invoking the item callback for each
 * item.  Items are [start, end) substrings of "value".
 */
typedef void (*item_cb) (const char *calendar, const char *item, int len,
						 CalendarRule *rule);

static void
parse_list(const char *calendar, const char *value, CalendarRule *rule,
		   item_cb cb)
{
	const char *p = value;

	if (*p == '\0')
		calendar_error(calendar, "empty value list.");

	while (*p)
	{
		const char *comma = strchr(p, ',');
		int			len = comma ? (int) (comma - p) : (int) strlen(p);

		if (len == 0)
			calendar_error(calendar, "empty element in value list.");
		cb(calendar, p, len, rule);
		p += len;
		if (*p == ',')
			p++;
	}
}

static void
bymonth_cb(const char *calendar, const char *item, int len, CalendarRule *rule)
{
	int			val = -1;
	int			i;

	if (len == 3)
	{
		for (i = 0; i < 12; i++)
		{
			if (strncmp(item, month_names[i], 3) == 0)
			{
				val = i + 1;
				break;
			}
		}
	}
	if (val < 0 && !parse_int(item, len, &val))
		val = -1;
	if (val < 1 || val > 12)
		calendar_error(calendar, "BYMONTH values must be month names or 1 through 12.");
	rule->bymonth[val] = true;
}

static void
bymonthday_cb(const char *calendar, const char *item, int len, CalendarRule *rule)
{
	int			val;

	if (!parse_int(item, len, &val) || val == 0 || val < -31 || val > 31)
		calendar_error(calendar, "BYMONTHDAY values must be -31 through -1 or 1 through 31.");
	if (rule->n_bymonthday >= (int) lengthof(rule->bymonthday))
		calendar_error(calendar, "too many BYMONTHDAY values.");
	rule->bymonthday[rule->n_bymonthday++] = val;
}

static void
byday_cb(const char *calendar, const char *item, int len, CalendarRule *rule)
{
	int			ord = 0;
	int			dow = -1;
	int			i;

	if (len > 3)
	{
		if (!parse_int(item, len - 3, &ord) || ord == 0 || ord < -5 || ord > 5)
			calendar_error(calendar, "BYDAY ordinal must be -5 through -1 or 1 through 5.");
		item += len - 3;
		len = 3;
	}
	if (len == 3)
	{
		for (i = 0; i < (int) lengthof(day_names); i++)
		{
			if (strncmp(item, day_names[i].name, 3) == 0)
			{
				dow = day_names[i].dow;
				break;
			}
		}
	}
	if (dow < 0)
		calendar_error(calendar, "BYDAY values must be day names (MON through SUN) with an optional ordinal.");
	if (rule->n_byday >= (int) lengthof(rule->byday))
		calendar_error(calendar, "too many BYDAY values.");
	rule->byday[rule->n_byday].dow = dow;
	rule->byday[rule->n_byday].ord = ord;
	rule->n_byday++;
	if (ord != 0)
		rule->byday_has_ord = true;
}

static void
byhour_cb(const char *calendar, const char *item, int len, CalendarRule *rule)
{
	int			val;

	if (!parse_int(item, len, &val) || val < 0 || val > 23)
		calendar_error(calendar, "BYHOUR values must be 0 through 23.");
	rule->byhour[val] = true;
}

static void
byminute_cb(const char *calendar, const char *item, int len, CalendarRule *rule)
{
	int			val;

	if (!parse_int(item, len, &val) || val < 0 || val > 59)
		calendar_error(calendar, "BYMINUTE values must be 0 through 59.");
	rule->byminute[val] = true;
}

static void
bysecond_cb(const char *calendar, const char *item, int len, CalendarRule *rule)
{
	int			val;

	if (!parse_int(item, len, &val) || val < 0 || val > 59)
		calendar_error(calendar, "BYSECOND values must be 0 through 59.");
	rule->bysecond[val] = true;
}

static void
parse_calendar(const char *calendar, CalendarRule *rule)
{
	char	   *norm;
	char	   *clause;
	bool		has_freq = false;
	bool		seen[8] = {false};

	if (calendar == NULL || *calendar == '\0')
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("calendar string must not be empty")));

	MemSet(rule, 0, sizeof(CalendarRule));
	rule->interval = 1;

	norm = normalize_calendar(calendar);

	for (clause = norm; clause && *clause;)
	{
		char	   *semi = strchr(clause, ';');
		char	   *eq;
		char	   *value;

		if (semi)
			*semi = '\0';

		if (*clause == '\0')
		{
			/* tolerate empty clause (e.g. trailing semicolon) */
			clause = semi ? semi + 1 : NULL;
			continue;
		}

		eq = strchr(clause, '=');
		if (eq == NULL)
			calendar_error(calendar, "each clause must have the form NAME=VALUE.");
		*eq = '\0';
		value = eq + 1;

		if (strcmp(clause, "FREQ") == 0)
		{
			if (seen[0])
				calendar_error(calendar, "duplicate FREQ clause.");
			seen[0] = true;
			has_freq = true;
			if (strcmp(value, "YEARLY") == 0)
				rule->freq = FREQ_YEARLY;
			else if (strcmp(value, "MONTHLY") == 0)
				rule->freq = FREQ_MONTHLY;
			else if (strcmp(value, "WEEKLY") == 0)
				rule->freq = FREQ_WEEKLY;
			else if (strcmp(value, "DAILY") == 0)
				rule->freq = FREQ_DAILY;
			else if (strcmp(value, "HOURLY") == 0)
				rule->freq = FREQ_HOURLY;
			else if (strcmp(value, "MINUTELY") == 0)
				rule->freq = FREQ_MINUTELY;
			else if (strcmp(value, "SECONDLY") == 0)
				rule->freq = FREQ_SECONDLY;
			else
				calendar_error(calendar, "FREQ must be one of YEARLY, MONTHLY, WEEKLY, DAILY, HOURLY, MINUTELY or SECONDLY.");
		}
		else if (strcmp(clause, "INTERVAL") == 0)
		{
			if (seen[1])
				calendar_error(calendar, "duplicate INTERVAL clause.");
			seen[1] = true;
			if (!parse_int(value, strlen(value), &rule->interval) ||
				rule->interval < 1 || rule->interval > 99)
				calendar_error(calendar, "INTERVAL must be 1 through 99.");
		}
		else if (strcmp(clause, "BYMONTH") == 0)
		{
			if (seen[2])
				calendar_error(calendar, "duplicate BYMONTH clause.");
			seen[2] = true;
			rule->has_bymonth = true;
			parse_list(calendar, value, rule, bymonth_cb);
		}
		else if (strcmp(clause, "BYMONTHDAY") == 0)
		{
			if (seen[3])
				calendar_error(calendar, "duplicate BYMONTHDAY clause.");
			seen[3] = true;
			parse_list(calendar, value, rule, bymonthday_cb);
		}
		else if (strcmp(clause, "BYDAY") == 0)
		{
			if (seen[4])
				calendar_error(calendar, "duplicate BYDAY clause.");
			seen[4] = true;
			parse_list(calendar, value, rule, byday_cb);
		}
		else if (strcmp(clause, "BYHOUR") == 0)
		{
			if (seen[5])
				calendar_error(calendar, "duplicate BYHOUR clause.");
			seen[5] = true;
			rule->has_byhour = true;
			parse_list(calendar, value, rule, byhour_cb);
		}
		else if (strcmp(clause, "BYMINUTE") == 0)
		{
			if (seen[6])
				calendar_error(calendar, "duplicate BYMINUTE clause.");
			seen[6] = true;
			rule->has_byminute = true;
			parse_list(calendar, value, rule, byminute_cb);
		}
		else if (strcmp(clause, "BYSECOND") == 0)
		{
			if (seen[7])
				calendar_error(calendar, "duplicate BYSECOND clause.");
			seen[7] = true;
			rule->has_bysecond = true;
			parse_list(calendar, value, rule, bysecond_cb);
		}
		else
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("invalid calendar string \"%s\"", calendar),
					 errdetail("Clause \"%s\" is not supported.", clause)));

		clause = semi ? semi + 1 : NULL;
	}

	if (!has_freq)
		calendar_error(calendar, "FREQ clause is required.");

	/* Ordinal BYDAY (e.g. 2FRI) only makes sense within a month window. */
	if (rule->byday_has_ord &&
		rule->freq != FREQ_YEARLY && rule->freq != FREQ_MONTHLY)
		calendar_error(calendar, "BYDAY ordinals are only supported with FREQ=YEARLY or FREQ=MONTHLY.");

	pfree(norm);
}

/* ------------------------------------------------------------------
 * Evaluation
 * ------------------------------------------------------------------
 */

static int
days_in_month(int year, int month)
{
	static const int md[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

	if (month == 2 && isleap(year))
		return 29;
	return md[month - 1];
}

/* Convert a local calendar time to TimestampTz in the session time zone. */
static bool
local_time_to_timestamptz(int year, int mon, int mday,
						  int hour, int min, int sec, TimestampTz *result)
{
	struct pg_tm tm;
	int			tz;
	Timestamp	ts;

	MemSet(&tm, 0, sizeof(tm));
	tm.tm_year = year;
	tm.tm_mon = mon;
	tm.tm_mday = mday;
	tm.tm_hour = hour;
	tm.tm_min = min;
	tm.tm_sec = sec;
	tm.tm_isdst = -1;

	tz = DetermineTimeZoneOffset(&tm, session_timezone);
	if (tm2timestamp(&tm, 0, &tz, &ts) != 0)
		return false;
	*result = ts;
	return true;
}

/*
 * Build the ascending list of matching days for (year, mon).
 * "fallback_mday" is used when neither BYMONTHDAY nor BYDAY is given.
 * Returns the number of days stored in days[] (capacity 31).
 */
static int
month_day_list(const CalendarRule *rule, int year, int mon, int fallback_mday,
			   int *days)
{
	int			dim = days_in_month(year, mon);
	bool		mark[32] = {false};
	int			n = 0;
	int			i,
				d;

	if (rule->n_bymonthday > 0)
	{
		for (i = 0; i < rule->n_bymonthday; i++)
		{
			d = rule->bymonthday[i];
			if (d < 0)
				d = dim + d + 1;
			if (d >= 1 && d <= dim)
				mark[d] = true;
		}

		/* When BYDAY is also given it acts as a day-of-week filter. */
		if (rule->n_byday > 0)
		{
			for (d = 1; d <= dim; d++)
			{
				if (!mark[d])
					continue;
				for (i = 0; i < rule->n_byday; i++)
				{
					if (j2day(date2j(year, mon, d)) == rule->byday[i].dow)
						break;
				}
				if (i >= rule->n_byday)
					mark[d] = false;
			}
		}
	}
	else if (rule->n_byday > 0)
	{
		for (i = 0; i < rule->n_byday; i++)
		{
			int			dow = rule->byday[i].dow;
			int			ord = rule->byday[i].ord;
			int			first_dow = j2day(date2j(year, mon, 1));
			int			first_match = 1 + ((dow - first_dow) + 7) % 7;
			int			count = (dim - first_match) / 7 + 1;

			if (ord == 0)
			{
				for (d = first_match; d <= dim; d += 7)
					mark[d] = true;
			}
			else if (ord > 0)
			{
				if (ord <= count)
					mark[first_match + (ord - 1) * 7] = true;
			}
			else
			{
				if (-ord <= count)
					mark[first_match + (count + ord) * 7] = true;
			}
		}
	}
	else
	{
		if (fallback_mday <= dim)
			mark[fallback_mday] = true;
	}

	for (d = 1; d <= dim; d++)
	{
		if (mark[d])
			days[n++] = d;
	}
	return n;
}

/* Expand a boolean set into an ascending int list; fallback when unset. */
static int
set_to_list(const bool *set, int setsize, bool has_set, int fallback,
			int *list)
{
	int			n = 0;
	int			i;

	if (has_set)
	{
		for (i = 0; i < setsize; i++)
		{
			if (set[i])
				list[n++] = i;
		}
	}
	else
		list[n++] = fallback;
	return n;
}

/*
 * Check the date-part filters (BYMONTH/BYMONTHDAY/BYDAY) against a concrete
 * date; used by the WEEKLY/DAILY/HOURLY/MINUTELY/SECONDLY paths where the
 * period already determines the date.
 */
static bool
date_matches(const CalendarRule *rule, int year, int mon, int mday)
{
	int			i;

	if (rule->has_bymonth && !rule->bymonth[mon])
		return false;

	if (rule->n_bymonthday > 0)
	{
		int			dim = days_in_month(year, mon);

		for (i = 0; i < rule->n_bymonthday; i++)
		{
			int			d = rule->bymonthday[i];

			if (d < 0)
				d = dim + d + 1;
			if (d == mday)
				break;
		}
		if (i >= rule->n_bymonthday)
			return false;
	}

	if (rule->n_byday > 0)
	{
		int			dow = j2day(date2j(year, mon, mday));

		for (i = 0; i < rule->n_byday; i++)
		{
			if (rule->byday[i].dow == dow)
				break;
		}
		if (i >= rule->n_byday)
			return false;
	}

	return true;
}

/*
 * Try one candidate; keep the smallest candidate that is > after and
 * >= start.  Returns true when the candidate was accepted.
 */
static bool
consider_candidate(TimestampTz cand, TimestampTz start, TimestampTz after,
				   TimestampTz *best, bool *found)
{
	if (cand <= after || cand < start)
		return false;
	if (!*found || cand < *best)
	{
		*best = cand;
		*found = true;
	}
	return true;
}

/*
 * Enumerate candidates on one calendar date, honoring the time-of-day rules,
 * and fold them into best/found.  hour_fixed/min_fixed of -1 mean "use the
 * BYHOUR/BYMINUTE lists (or the start_date component)".
 */
static void
scan_times_on_date(const CalendarRule *rule, int year, int mon, int mday,
				   int hour_fixed, int min_fixed, int sec_fixed,
				   const struct pg_tm *tm_start,
				   TimestampTz start, TimestampTz after,
				   TimestampTz *best, bool *found)
{
	int			hours[24],
				minutes[60],
				seconds[60];
	int			nh,
				nm,
				ns;
	int			hi,
				mi,
				si;

	if (hour_fixed >= 0)
	{
		nh = 1;
		hours[0] = hour_fixed;
	}
	else
		nh = set_to_list(rule->byhour, 24, rule->has_byhour, tm_start->tm_hour, hours);

	if (min_fixed >= 0)
	{
		nm = 1;
		minutes[0] = min_fixed;
	}
	else
		nm = set_to_list(rule->byminute, 60, rule->has_byminute, tm_start->tm_min, minutes);

	if (sec_fixed >= 0)
	{
		ns = 1;
		seconds[0] = sec_fixed;
	}
	else
		ns = set_to_list(rule->bysecond, 60, rule->has_bysecond, tm_start->tm_sec, seconds);

	for (hi = 0; hi < nh; hi++)
	{
		for (mi = 0; mi < nm; mi++)
		{
			for (si = 0; si < ns; si++)
			{
				TimestampTz cand;

				if (local_time_to_timestamptz(year, mon, mday,
											  hours[hi], minutes[mi], seconds[si],
											  &cand))
				{
					if (consider_candidate(cand, start, after, best, found))
						return; /* lists ascend; first hit in this date wins */
				}
			}
		}
	}
}

static bool
eval_calendar(const CalendarRule *rule, TimestampTz start, TimestampTz after,
			  TimestampTz *next)
{
	struct pg_tm tm_start;
	fsec_t		fsec;
	int			tzoff;
	const char *tzn;
	int64		k,
				k0 = 0;
	TimestampTz best = 0;
	bool		found = false;

	if (timestamp2tm(start, &tzoff, &tm_start, &fsec, &tzn, session_timezone) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("timestamp out of range")));

	/*
	 * Fast-forward: estimate the first period that could contain a candidate
	 * greater than "after", so that e.g. FREQ=SECONDLY anchored years in the
	 * past does not step through billions of periods.  Back off one period
	 * to stay safe against boundary effects.
	 */
	if (after > start)
	{
		int64		diff_usec = after - start;
		int64		periods = 0;

		switch (rule->freq)
		{
			case FREQ_SECONDLY:
				periods = diff_usec / (rule->interval * USECS_PER_SEC);
				break;
			case FREQ_MINUTELY:
				periods = diff_usec / (rule->interval * USECS_PER_MINUTE);
				break;
			case FREQ_HOURLY:
				periods = diff_usec / (rule->interval * USECS_PER_HOUR);
				break;
			case FREQ_DAILY:
				periods = diff_usec / (rule->interval * USECS_PER_DAY);
				break;
			case FREQ_WEEKLY:
				periods = diff_usec / (rule->interval * 7 * USECS_PER_DAY);
				break;
			case FREQ_MONTHLY:
				periods = (diff_usec / USECS_PER_DAY / 32) / rule->interval;
				break;
			case FREQ_YEARLY:
				periods = (diff_usec / USECS_PER_DAY / 366) / rule->interval;
				break;
		}
		k0 = periods > 2 ? periods - 2 : 0;
	}

	for (k = k0; k < k0 + SCHED_MAX_PERIODS; k++)
	{
		CHECK_FOR_INTERRUPTS();

		switch (rule->freq)
		{
			case FREQ_YEARLY:
				{
					int			year = tm_start.tm_year + (int) (k * rule->interval);
					int			months[12];
					int			nmon;
					int			mi;

					nmon = set_to_list(rule->bymonth, 13, rule->has_bymonth,
									   tm_start.tm_mon, months);
					/* set_to_list over index 1..12 never yields index 0 */

					for (mi = 0; mi < nmon; mi++)
					{
						int			days[31];
						int			nd,
									di;

						nd = month_day_list(rule, year, months[mi],
											tm_start.tm_mday, days);
						for (di = 0; di < nd && !found; di++)
							scan_times_on_date(rule, year, months[mi], days[di],
											   -1, -1, -1, &tm_start,
											   start, after, &best, &found);
						if (found)
							break;
					}
					break;
				}

			case FREQ_MONTHLY:
				{
					int64		mindex = (int64) tm_start.tm_year * 12 +
						(tm_start.tm_mon - 1) + k * rule->interval;
					int			year = (int) (mindex / 12);
					int			mon = (int) (mindex % 12) + 1;
					int			days[31];
					int			nd,
								di;

					if (rule->has_bymonth && !rule->bymonth[mon])
						break;

					nd = month_day_list(rule, year, mon, tm_start.tm_mday, days);
					for (di = 0; di < nd && !found; di++)
						scan_times_on_date(rule, year, mon, days[di],
										   -1, -1, -1, &tm_start,
										   start, after, &best, &found);
					break;
				}

			case FREQ_WEEKLY:
				{
					int			j0 = date2j(tm_start.tm_year, tm_start.tm_mon,
											tm_start.tm_mday) +
						(int) (k * rule->interval * 7);
					int			d;

					/*
					 * The week window is anchored at start_date's weekday:
					 * days j0 .. j0+6.  Without BYDAY only the anchor day
					 * itself repeats.
					 */
					for (d = 0; d < 7 && !found; d++)
					{
						int			jd = j0 + d;
						int			year,
									mon,
									mday;
						int			dow = j2day(jd);
						int			i;

						if (rule->n_byday > 0)
						{
							for (i = 0; i < rule->n_byday; i++)
							{
								if (rule->byday[i].dow == dow)
									break;
							}
							if (i >= rule->n_byday)
								continue;
						}
						else if (d != 0)
							continue;

						j2date(jd, &year, &mon, &mday);
						if (rule->has_bymonth && !rule->bymonth[mon])
							continue;
						scan_times_on_date(rule, year, mon, mday,
										   -1, -1, -1, &tm_start,
										   start, after, &best, &found);
					}
					break;
				}

			case FREQ_DAILY:
				{
					int			jd = date2j(tm_start.tm_year, tm_start.tm_mon,
											tm_start.tm_mday) +
						(int) (k * rule->interval);
					int			year,
								mon,
								mday;

					j2date(jd, &year, &mon, &mday);
					if (!date_matches(rule, year, mon, mday))
						break;
					scan_times_on_date(rule, year, mon, mday,
									   -1, -1, -1, &tm_start,
									   start, after, &best, &found);
					break;
				}

			case FREQ_HOURLY:
			case FREQ_MINUTELY:
			case FREQ_SECONDLY:
				{
					/*
					 * Time-based frequencies step in absolute time from
					 * start_date; finer-grained components come from the BY
					 * lists (or start_date), coarser-grained BY clauses act
					 * as filters on the period's local time.
					 */
					int64		step_usec;
					TimestampTz base;
					struct pg_tm tm;
					fsec_t		f2;
					int			tz2;

					if (rule->freq == FREQ_HOURLY)
						step_usec = rule->interval * USECS_PER_HOUR;
					else if (rule->freq == FREQ_MINUTELY)
						step_usec = rule->interval * USECS_PER_MINUTE;
					else
						step_usec = rule->interval * USECS_PER_SEC;

					base = start + k * step_usec;
					if (timestamp2tm(base, &tz2, &tm, &f2, NULL, session_timezone) != 0)
						break;

					if (!date_matches(rule, tm.tm_year, tm.tm_mon, tm.tm_mday))
						break;

					if (rule->freq == FREQ_HOURLY)
					{
						if (rule->has_byhour && !rule->byhour[tm.tm_hour])
							break;
						scan_times_on_date(rule, tm.tm_year, tm.tm_mon, tm.tm_mday,
										   tm.tm_hour, -1, -1, &tm_start,
										   start, after, &best, &found);
					}
					else if (rule->freq == FREQ_MINUTELY)
					{
						if (rule->has_byhour && !rule->byhour[tm.tm_hour])
							break;
						if (rule->has_byminute && !rule->byminute[tm.tm_min])
							break;
						scan_times_on_date(rule, tm.tm_year, tm.tm_mon, tm.tm_mday,
										   tm.tm_hour, tm.tm_min, -1, &tm_start,
										   start, after, &best, &found);
					}
					else
					{
						if (rule->has_byhour && !rule->byhour[tm.tm_hour])
							break;
						if (rule->has_byminute && !rule->byminute[tm.tm_min])
							break;
						if (rule->has_bysecond && !rule->bysecond[tm.tm_sec])
							break;
						consider_candidate(base - f2, start, after, &best, &found);
					}
					break;
				}
		}

		if (found)
		{
			*next = best;
			return true;
		}
	}

	return false;
}
