/*-------------------------------------------------------------------------
 *
 * String-processing utility routines for frontend code (Oracle Compatibility)
 *
 * Assorted utility functions that are useful in constructing SQL queries
 * and interpreting backend output.
 *
 *
 * Copyright:
 * Portions Copyright (c) 2023, Ivory SQL Global Development Team
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
		 * Note: ScanKeywordLookup() does case-insensitive comparison, but
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

/* BEGIN - SQL PARSER */
/* get specificed database compatibility mode of current session */
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
/* END - SQL PARSER */
