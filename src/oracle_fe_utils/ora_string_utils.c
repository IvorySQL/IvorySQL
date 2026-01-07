/*-------------------------------------------------------------------------
 *
 * String-processing utility routines for frontend code (Oracle Compatibility)
 *
 * Assorted utility functions that are useful in constructing SQL queries
 * and interpreting backend output.
 *
 *
 * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * src/oracle_fe_utils/ora_string_utils.c
 *
 * add the file for requirement "SQL PARSER"
 *
 *-------------------------------------------------------------------------
 */
#include "postgres_fe.h"

#include <ctype.h>

#include "fe_utils/string_utils.h"

#include "oracle_fe_utils/ora_string_utils.h"

#include "oracle_parser/ora_keywords.h"

#include "mb/pg_wchar.h"


static PQExpBuffer oraDefaultGetLocalPQExpBuffer(void);

/* Globals exported by this file */
DBMode db_mode = DB_PG;

/*
 * Returns a temporary PQExpBuffer, valid until the next call to the function.
 * This is used by ora_fmtId and fmtQualifiedId.
 *
 * Non-reentrant and non-thread-safe but reduces memory leakage. You can
 * replace this with a custom version by setting the oraGetLocalPQExpBuffer
 * function pointer.
 */
static PQExpBuffer
oraDefaultGetLocalPQExpBuffer(void)
{
	static PQExpBuffer id_return = NULL;

	if (id_return)				/* first time through? */
	{
		/* same buffer, just wipe contents */
		resetPQExpBuffer(id_return);
	}
	else
	{
		/* new buffer */
		id_return = createPQExpBuffer();
	}

	return id_return;
}

/*
 *	Quotes input string if it's not a legitimate SQL identifier as-is.
 *
 *	Note that the returned string must be used before calling fmtId again,
 *	since we re-use the same return buffer each time.
 */
const char *
ora_fmtId(const char *rawid)
{
	PQExpBuffer id_return = oraDefaultGetLocalPQExpBuffer();

	const char *cp;
	bool		need_quotes = false;

	/*
	 * These checks need to match the identifier production in scan.l. Don't
	 * use islower() etc.
	 */
	if (quote_all_identifiers)
		need_quotes = true;
	/* slightly different rules for first character */
	else if (!((rawid[0] >= 'a' && rawid[0] <= 'z')
			|| rawid[0] == '_'
			|| rawid[0] == '"'))
		need_quotes = true;
	else if (rawid[0] != '"')
	{
		/* otherwise check the entire string */
		for (cp = rawid; *cp; cp++)
		{
			if (!((*cp >= 'a' && *cp <= 'z')
				  || (*cp >= '0' && *cp <= '9')
				  || (*cp == '_')))
			{
				need_quotes = true;
				break;
			}
		}
	}

	if (!need_quotes)
	{
		/*
		 * Check for keyword.  We quote keywords except for unreserved ones.
		 * (In some cases we could avoid quoting a col_name or type_func_name
		 * keyword, but it seems much harder than it's worth to tell that.)
		 *
		 * Note: OraScanKeywordLookup() does case-insensitive comparison, but
		 * that's fine, since we already know we have all-lower-case.
		 */
		int			kwnum = ScanKeywordLookup(rawid, &OraScanKeywords);

		if (kwnum >= 0 && OraScanKeywordCategories[kwnum] != UNRESERVED_KEYWORD)
			need_quotes = true;
	}

	if (!need_quotes)
	{
		/* no quoting needed */
		appendPQExpBufferStr(id_return, rawid);
	}
	else
	{
		appendPQExpBufferChar(id_return, '"');
		for (cp = rawid; *cp; cp++)
		{
			/*
			 * Did we find a double-quote in the string? Then make this a
			 * double double-quote per SQL99. Before, we put in a
			 * backslash/double-quote pair. - thomas 2000-08-05
			 */
			if (*cp == '"')
				appendPQExpBufferChar(id_return, '"');
			appendPQExpBufferChar(id_return, *cp);
		}
		appendPQExpBufferChar(id_return, '"');
	}

	return id_return->data;
}

/**
 * Determine and record the current session's database compatibility mode.
 *
 * Queries the session setting "ivorysql.compatible_mode" and sets the global
 * `db_mode` to DB_ORACLE when the setting is equal to "oracle" (case-insensitive);
 * otherwise sets `db_mode` to DB_PG. If the query does not return a tuple result,
 * `db_mode` is set to DB_PG. The function clears any PGresult it obtains.
 *
 * @param conn Connection to the database whose session mode is queried.
 */
void
getDbCompatibleMode(PGconn *conn)
{
	PGresult *res;

	char *db_style = NULL;

	res = PQexec(conn, "show ivorysql.compatible_mode;");

	if (PQresultStatus(res) != PGRES_TUPLES_OK)
		db_mode = DB_PG;
	else
	{
		db_style = PQgetvalue(res, 0, 0);

		if (0 == pg_strcasecmp(db_style, "oracle"))
			db_mode = DB_ORACLE;
		else
			db_mode = DB_PG;
	}

	if (res)
		PQclear(res);
}

/**
 * Convert ASCII single-byte characters in a buffer to lowercase while preserving multibyte sequences.
 *
 * Modifies the input buffer in place for up to `len` bytes. For encodings where characters
 * occupy multiple bytes, multibyte sequences are left unchanged; only single-byte characters
 * are converted using the C locale `tolower` behavior.
 *
 * @param src Pointer to the byte buffer to transform; must be writable and at least `len` bytes long.
 * @param len Number of bytes from `src` to process.
 * @param encoding Server encoding identifier used by pg_encoding_mblen to determine multibyte lengths.
 * @returns Pointer to the original buffer (`src`), after in-place modification.
 */
char *
down_character(const char *src, int len, int encoding)
{
	char	*s;
	char	*res;
	int		i;
	Assert(src != NULL);
	Assert(len >= 0);

	s = (char *) src;
	res = s;

	/* transform */
	for (i = 0; i < len ; i++)
	{
		int mblen = pg_encoding_mblen(encoding, s);

		if (mblen > 1)
		{
			s += mblen;
			i += (mblen - 1);
			continue;
		}

		*s = tolower(*s);
		s++;
	}

	return res;
}

/**
 * Convert ASCII single-byte characters in a buffer to uppercase, preserving multibyte characters.
 *
 * Processes up to `len` bytes of `src`, uppercasing single-byte characters in place while skipping
 * multibyte sequences as determined by `encoding`.
 *
 * @param src Buffer whose contents will be modified; must be non-NULL.
 * @param len Number of bytes from `src` to process; must be >= 0.
 * @param encoding Server encoding used to determine multibyte character lengths.
 * @returns Pointer to the input buffer `src` (modified in place).
 */
char *
upper_character(const char *src, int len, int encoding)
{
	char	*s;
	char	*res;
	int		i;
	Assert(src != NULL);
	Assert(len >= 0);

	s = (char *) src;
	res = s;

	/* transform */
	for (i = 0; i < len ; i++)
	{
		int mblen = pg_encoding_mblen(encoding, s);

		if (mblen > 1)
		{
			s += mblen;
			i += (mblen - 1);
			continue;
		}

		*s = toupper(*s);
		s++;
	}

	return res;
}

/**
 * Check whether all alphabetic characters in a byte string are lowercase for the given encoding.
 *
 * Multibyte character sequences (per pg_encoding_mblen) are skipped and not examined; only single-byte
 * characters are tested with C locale character functions.
 *
 * @param src Pointer to the byte string to examine.
 * @param len Number of bytes from src to examine.
 * @param encoding Encoding identifier used to determine multibyte character lengths.
 * @returns `true` if every alphabetic character encountered is lowercase, `false` otherwise.
 */
bool
is_all_lower(const char *src, int len, int encoding)
{
	int		i;
	const char	*s;

	s = src;

	for (i = 0; i < len; i++)
	{
		int mblen = pg_encoding_mblen(encoding, s);

		if (mblen > 1)
		{
			s += mblen;
			i += (mblen - 1);
			continue;
		}

		if (isalpha(*s) && isupper(*s))
			return false;
		s++;
	}

	return true;
}

/**
 * Check whether all alphabetic characters in the given byte sequence are uppercase.
 *
 * Examines up to `len` bytes starting at `src`, treating multibyte characters according
 * to `encoding` (multibyte sequences are skipped). Non-alphabetic characters do not
 * affect the result.
 *
 * @param src Pointer to the byte sequence to examine.
 * @param len Number of bytes from `src` to examine.
 * @param encoding Server encoding identifier used with pg_encoding_mblen to detect multibyte sequences.
 * @return `true` if every alphabetic character encountered is uppercase, `false` otherwise.
 */
bool
is_all_upper(const char *src, int len, int encoding)
{
	int		i;
	const char	*s;

	s = src;

	for (i = 0; i < len; i++)
	{
		int mblen = pg_encoding_mblen(encoding, s);

		if (mblen > 1)
		{
			s += mblen;
			i += (mblen - 1);
			continue;
		}

		if (isalpha(*s) && islower(*s))
			return false;
		s++;
	}

	return true;
}