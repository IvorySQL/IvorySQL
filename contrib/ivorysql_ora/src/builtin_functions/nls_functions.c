/*-------------------------------------------------------------------------
 *
 * nls_functions.c
 *
 * This file contains the implementation of Oracle's NLS-aware case
 * conversion functions NLS_UPPER and NLS_LOWER.
 *
 * Without an NLS parameter (or with 'NLS_SORT=BINARY') the conversion is
 * a simple per-character mapping performed with the Unicode simple case
 * tables, so it does not depend on the database locale.  This mirrors the
 * default behaviour on Oracle, e.g. NLS_UPPER('straße') = 'STRAßE'.
 *
 * When the optional second parameter is of the form 'NLS_SORT=<sort>'
 * (optionally suffixed with _CI or _AI), the linguistic special cases that
 * Oracle applies for the X-prefixed German, West-European and Turkish
 * sorts are reproduced:
 *
 *   NLS_UPPER('straße', 'NLS_SORT=XGERMAN') = 'STRASSE'
 *   NLS_UPPER('iyigi',  'NLS_SORT=XTURKISH') = 'İYİGİ'
 *   NLS_LOWER('IYIGI',  'NLS_SORT=XTURKISH') = 'ıyıgı'
 *
 * Any other NLS parameter clause (a single NAME=VALUE whose name is not
 * NLS_SORT) is accepted and ignored, the same way Oracle does.  Unknown
 * sort names and malformed parameter strings are rejected with the Oracle
 * ORA-12702 error text.
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_functions/nls_functions.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "mb/pg_wchar.h"
#include "varatt.h"

#include "common/unicode_case.h"
#include "utils/builtins.h"

/* linguistic sorts with verified case-conversion special cases */
typedef enum NlsSortKind
{
	NLS_SORT_BINARY,		/* BINARY and simple-mapping sorts */
	NLS_SORT_PLAIN,			/* recognized linguistic sort, simple mapping */
	NLS_SORT_X_GERMAN,		/* XGERMAN / XGERMAN_DIN: ß -> SS on upper */
	NLS_SORT_X_WEST_EUROPEAN,	/* XWEST_EUROPEAN: ß -> SS on upper */
	NLS_SORT_X_TURKISH		/* XTURKISH: i/ı/İ/I specials */
} NlsSortKind;

#define ORA_INVALID_NLS_PARAM_MSG "invalid NLS parameter string used in SQL function"

static char *
nls_downcase_copy(const char *src, int len)
{
	char	   *dst = palloc(len + 1);
	int			i;

	for (i = 0; i < len; i++)
		dst[i] = pg_ascii_tolower((unsigned char) src[i]);
	dst[len] = '\0';
	return dst;
}

/*
 * Parse the optional nlsparam argument of NLS_UPPER/NLS_LOWER.
 *
 * Accepted forms (matching Oracle 23ai behaviour):
 *   'NLS_SORT=<sort>'   sort name is case-insensitive, spaces are allowed
 *                       around '=' and value, optional _CI/_AI suffix
 *   '<NAME>=<VALUE>'    any other single NLS clause is accepted and ignored
 *
 * Anything else (no '=', a comma-joined clause list, an empty or unknown
 * sort name) raises an error with Oracle's ORA-12702 text.
 */
static NlsSortKind
nls_parse_sort(const char *param)
{
	const char *p = param;
	const char *eq;
	int			namelen;
	char	   *name;
	char	   *value;

	/* locate the '=' and validate the clause shape */
	eq = strchr(param, '=');
	if (eq == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg(ORA_INVALID_NLS_PARAM_MSG)));

	/* reject clause lists: a comma before '=' means a malformed name */
	for (p = param; p < eq; p++)
	{
		if (*p == ',')
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg(ORA_INVALID_NLS_PARAM_MSG)));
	}

	/* trim the name */
	p = param;
	while (*p == ' ' || *p == '\t')
		p++;
	name = nls_downcase_copy(p, eq - p);
	namelen = strlen(name);
	while (namelen > 0 && (name[namelen - 1] == ' ' || name[namelen - 1] == '\t'))
		name[--namelen] = '\0';
	if (namelen == 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg(ORA_INVALID_NLS_PARAM_MSG)));

	/* trim the value; reject empty values and clause lists */
	p = eq + 1;
	while (*p == ' ' || *p == '\t')
		p++;
	value = nls_downcase_copy(p, strlen(p));
	namelen = strlen(value);
	while (namelen > 0 && (value[namelen - 1] == ' ' || value[namelen - 1] == '\t'))
		value[--namelen] = '\0';
	if (namelen == 0 || strchr(value, ',') != NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg(ORA_INVALID_NLS_PARAM_MSG)));

	if (strcmp(name, "nls_sort") != 0)
	{
		/* a valid-looking clause for another NLS parameter: ignore it */
		pfree(name);
		pfree(value);
		return NLS_SORT_PLAIN;
	}
	pfree(name);

	/* strip the _CI/_AI suffixes Oracle allows on sort names */
	if (namelen > 3 && strcmp(value + namelen - 3, "_ci") == 0)
		value[namelen - 3] = '\0';
	else if (namelen > 3 && strcmp(value + namelen - 3, "_ai") == 0)
		value[namelen - 3] = '\0';

	if (strcmp(value, "binary") == 0 ||
		strcmp(value, "german") == 0 ||
		strcmp(value, "german_din") == 0 ||
		strcmp(value, "french") == 0 ||
		strcmp(value, "xfrench") == 0 ||
		strcmp(value, "west_european") == 0 ||
		strcmp(value, "turkish") == 0)
	{
		pfree(value);
		return NLS_SORT_PLAIN;
	}
	if (strcmp(value, "xgerman") == 0 ||
		strcmp(value, "xgerman_din") == 0)
	{
		pfree(value);
		return NLS_SORT_X_GERMAN;
	}
	if (strcmp(value, "xwest_european") == 0)
	{
		pfree(value);
		return NLS_SORT_X_WEST_EUROPEAN;
	}
	if (strcmp(value, "xturkish") == 0)
	{
		pfree(value);
		return NLS_SORT_X_TURKISH;
	}

	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg(ORA_INVALID_NLS_PARAM_MSG)));
	return NLS_SORT_PLAIN;		/* keep compiler quiet */
}

/*
 * Core case conversion.  Works on pg_wchar so the Unicode simple case
 * tables apply regardless of the database locale; results are re-encoded
 * in the database encoding.
 */
static text *
nls_case_convert(text *input, bool to_upper, NlsSortKind kind)
{
	Size		inlen = VARSIZE_ANY_EXHDR(input);
	const char *inp = VARDATA_ANY(input);
	pg_wchar   *wcs;
	pg_wchar   *out;
	char		*mbbuf;
	int			nwcs;
	int			outchars = 0;
	int			i;
	int			mbbytes;
	text	   *result;

	/* Oracle treats the empty string as NULL */
	if (inlen == 0)
		return NULL;

	wcs = (pg_wchar *) palloc(sizeof(pg_wchar) * (inlen + 1));
	nwcs = pg_mb2wchar_with_len(inp, wcs, (int) inlen);
	out = (pg_wchar *) palloc(sizeof(pg_wchar) * ((Size) nwcs * 2 + 1));

	for (i = 0; i < nwcs; i++)
	{
		pg_wchar	c = wcs[i];

		switch (kind)
		{
			case NLS_SORT_X_TURKISH:
				if (to_upper)
					out[outchars++] = (c == 'i') ? 0x0130 :
						(c == 0x0131) ? 'I' :
						unicode_uppercase_simple((char32_t) c);
				else
					out[outchars++] = (c == 'I') ? 0x0131 :
						(c == 0x0130) ? 'i' :
						unicode_lowercase_simple((char32_t) c);
				break;

			case NLS_SORT_X_GERMAN:
			case NLS_SORT_X_WEST_EUROPEAN:
				if (to_upper && c == 0x00DF)
				{
					out[outchars++] = 'S';
					out[outchars++] = 'S';
					break;
				}
				out[outchars++] = to_upper ?
					unicode_uppercase_simple((char32_t) c) :
					unicode_lowercase_simple((char32_t) c);
				break;

			default:
				out[outchars++] = to_upper ?
					unicode_uppercase_simple((char32_t) c) :
					unicode_lowercase_simple((char32_t) c);
				break;
		}
	}

	mbbuf = (char *) palloc((Size) outchars * MAX_MULTIBYTE_CHAR_LEN + 1);
	mbbytes = pg_wchar2mb_with_len(out, mbbuf, outchars);
	mbbuf[mbbytes] = '\0';
	result = cstring_to_text((const char *) mbbuf);

	pfree(wcs);
	pfree(out);
	pfree(mbbuf);

	return result;
}

Datum
ora_nls_upper(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(ora_nls_upper);

Datum
ora_nls_upper(PG_FUNCTION_ARGS)
{
	text	   *result = nls_case_convert(PG_GETARG_TEXT_PP(0), true,
										  NLS_SORT_BINARY);

	if (result == NULL)
		PG_RETURN_NULL();
	PG_RETURN_TEXT_P(result);
}

Datum
ora_nls_upper_param(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(ora_nls_upper_param);

Datum
ora_nls_upper_param(PG_FUNCTION_ARGS)
{
	NlsSortKind kind = nls_parse_sort(text_to_cstring(PG_GETARG_TEXT_PP(1)));
	text	   *result = nls_case_convert(PG_GETARG_TEXT_PP(0), true, kind);

	if (result == NULL)
		PG_RETURN_NULL();
	PG_RETURN_TEXT_P(result);
}

Datum
ora_nls_lower(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(ora_nls_lower);

Datum
ora_nls_lower(PG_FUNCTION_ARGS)
{
	text	   *result = nls_case_convert(PG_GETARG_TEXT_PP(0), false,
										  NLS_SORT_BINARY);

	if (result == NULL)
		PG_RETURN_NULL();
	PG_RETURN_TEXT_P(result);
}

Datum
ora_nls_lower_param(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(ora_nls_lower_param);

Datum
ora_nls_lower_param(PG_FUNCTION_ARGS)
{
	NlsSortKind kind = nls_parse_sort(text_to_cstring(PG_GETARG_TEXT_PP(1)));
	text	   *result = nls_case_convert(PG_GETARG_TEXT_PP(0), false, kind);

	if (result == NULL)
		PG_RETURN_NULL();
	PG_RETURN_TEXT_P(result);
}
