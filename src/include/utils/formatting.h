/* -----------------------------------------------------------------------
 * formatting.h
 *
 * src/include/utils/formatting.h
 *
 *
 *	 Portions Copyright (c) 1999-2024, PostgreSQL Global Development Group
 *
 *	 The PostgreSQL routines for a DateTime/int/float/numeric formatting,
 *	 inspired by the Oracle TO_CHAR() / TO_DATE() / TO_NUMBER() routines.
 *
 *	 Karel Zak
 *
 * -----------------------------------------------------------------------
 */

#ifndef _FORMATTING_H_
#define _FORMATTING_H_

#include "pgtime.h"
#include "datatype/timestamp.h"
#include "utils/numeric.h"
#include "nodes/nodes.h"

/* ----------
 * Datetime to char conversion
 *
 * To support intervals as well as timestamps, we use a custom "tm" struct
 * that is almost like struct pg_tm, but has a 64-bit tm_hour field.
 * We omit the tm_isdst and tm_zone fields, which are not used here.
 * ----------
 */
struct fmt_tm
{
	int			tm_sec;
	int			tm_min;
	int64		tm_hour;
	int			tm_mday;
	int			tm_mon;
	int			tm_year;
	int			tm_wday;
	int			tm_yday;
	long int	tm_gmtoff;
};

/* Copy from formatting.c to here */
typedef struct TmToChar
{
	struct fmt_tm tm;			/* classic 'tm' struct */
	fsec_t		fsec;			/* fractional seconds */
	const char *tzn;			/* timezone */
} TmToChar;

#define tmtcTm(_X)	(&(_X)->tm)
#define tmtcTzn(_X) ((_X)->tzn)
#define tmtcFsec(_X)	((_X)->fsec)

/*
 * The default date values are determined as follows:
 *	the year is the current year, as returned by SYSDATE.
 *	the month is the current month, as returned by SYSDATE.
 *	the day is 01 (the first day of the month).
 *	the hour, minute, and second are all 0.
 *
 */
#define ORA_ZERO_tm(_X) \
do {	\
	memset(_X, 0, sizeof(*(_X))); \
	(_X)->tm_mday = (_X)->tm_mon = 1; \
} while(0)

#define ORA_ZERO_tmtc(_X) \
do { \
	ORA_ZERO_tm( tmtcTm(_X) ); \
	tmtcFsec(_X) = 0; \
	tmtcTzn(_X) = NULL; \
} while(0)

extern char *str_tolower(const char *buff, size_t nbytes, Oid collid);
extern char *str_toupper(const char *buff, size_t nbytes, Oid collid);
extern char *str_initcap(const char *buff, size_t nbytes, Oid collid);

extern char *asc_tolower(const char *buff, size_t nbytes);
extern char *asc_toupper(const char *buff, size_t nbytes);
extern char *asc_initcap(const char *buff, size_t nbytes);

extern Datum parse_datetime(text *date_txt, text *fmt, Oid collid, bool strict,
							Oid *typid, int32 *typmod, int *tz,
							struct Node *escontext);
extern bool datetime_format_has_tz(const char *fmt_str);

/* export datetime_to_char_body from formatting.c used in ivorysql_ora */
extern text *datetime_to_char_body(TmToChar *tmtc, text *fmt,
											bool is_interval, Oid collid);

extern void
ora_do_to_timestamp(text *date_txt, text *fmt, Oid collid, bool std,
				struct pg_tm *tm, fsec_t *fsec, int *fprec,
				uint32 *flags, Node *escontext, bool is_conv_func);
extern Numeric ora_to_number_internal(text *value, text *fmt);

#endif
