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
 * Implementation of Oracle's DBMS_ASSERT package.
 * This module is part of ivorysql_ora extension.
 *
 * Provides the identifier-validation and quoting interfaces used by
 * migrated applications that build dynamic SQL: ENQUOTE_NAME,
 * ENQUOTE_LITERAL, NOOP, SIMPLE_SQL_NAME, QUALIFIED_SQL_NAME,
 * SCHEMA_NAME and SQL_OBJECT_NAME.
 *
 * The name-syntax checks are based on orafce's dbms_assert.c (BSD), which
 * mirrors the backend scanner's identifier rules; the orafce-specific
 * ORA_PACKAGES SQLSTATEs are mapped to standard PostgreSQL error codes.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_assert/dbms_assert.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "varatt.h"

#include "catalog/namespace.h"
#include "catalog/pg_namespace_d.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "mb/pg_wchar.h"
#include "utils/acl.h"
#include "utils/builtins.h"
#include "utils/regproc.h"
#include "utils/syscache.h"

/* SQL-callable function declarations */
PG_FUNCTION_INFO_V1(ora_dbms_assert_enquote_literal);
PG_FUNCTION_INFO_V1(ora_dbms_assert_enquote_name);
PG_FUNCTION_INFO_V1(ora_dbms_assert_noop);
PG_FUNCTION_INFO_V1(ora_dbms_assert_qualified_sql_name);
PG_FUNCTION_INFO_V1(ora_dbms_assert_schema_name);
PG_FUNCTION_INFO_V1(ora_dbms_assert_simple_sql_name);
PG_FUNCTION_INFO_V1(ora_dbms_assert_object_name);

#define INVALID_SCHEMA_NAME_EXCEPTION() \
	ereport(ERROR, \
		(errcode(ERRCODE_INVALID_SCHEMA_NAME), \
		 errmsg("invalid schema name")))

#define INVALID_OBJECT_NAME_EXCEPTION() \
	ereport(ERROR, \
		(errcode(ERRCODE_UNDEFINED_OBJECT), \
		 errmsg("invalid object name")))

#define ISNOT_SIMPLE_SQL_NAME_EXCEPTION() \
	ereport(ERROR, \
		(errcode(ERRCODE_INVALID_NAME), \
		 errmsg("string is not simple SQL name")))

#define ISNOT_QUALIFIED_SQL_NAME_EXCEPTION() \
	ereport(ERROR, \
		(errcode(ERRCODE_INVALID_NAME), \
		 errmsg("string is not qualified SQL name")))

#define EMPTY_STR(str)		((VARSIZE(str) - VARHDRSZ) == 0)

static bool check_sql_name(char *cp, int len);
static bool ParseIdentifierString(char *rawstring);

/*
 * Is character a valid identifier start?
 * Must match the backend scanner's {ident_start} character class.
 */
static bool
is_ident_start(unsigned char c)
{
	/* Underscore and ASCII letters are OK */
	if (c == '_')
		return true;
	if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'))
		return true;
	/* Any high-bit-set character is OK (might be part of a multibyte char) */
	if (IS_HIGHBIT_SET(c))
		return true;
	return false;
}

/*
 * Is character a valid identifier continuation?
 * Must match the backend scanner's {ident_cont} character class.
 */
static bool
is_ident_cont(unsigned char c)
{
	/* Can be a digit or a dollar sign ... */
	if ((c >= '0' && c <= '9') || c == '$')
		return true;
	/* ... or an identifier start character */
	return is_ident_start(c);
}

/*
 * ParseIdentifierString - validate a dot-separated identifier chain.
 *
 * Based on SplitIdentifierString from varlena.c, with stricter behavior:
 * quoted parts are only scanned for balanced quotes (no downcasing, no
 * truncation), and any character that cannot appear in an SQL identifier
 * chain makes the whole string invalid.  Returns true when the complete
 * input is a valid (possibly empty) qualified identifier.
 */
static bool
ParseIdentifierString(char *rawstring)
{
	char	   *nextp = rawstring;
	bool		done = false;

	while (isspace((unsigned char) *nextp))
		nextp++;				/* skip leading whitespace */

	if (*nextp == '\0')
		return true;			/* allow empty string */

	/* At the top of the loop, we are at start of a new identifier. */
	do
	{
		if (*nextp == '\"')
		{
			char	   *endp;

			/* Quoted name --- collapse quote-quote pairs, no downcasing */
			for (;;)
			{
				endp = strchr(nextp + 1, '\"');
				if (endp == NULL)
					return false;	/* mismatched quotes */

				if (endp[1] != '\"')
					break;		/* found end of quoted name */

				/* Collapse adjacent quotes into one quote, and look again */
				memmove(endp, endp + 1, strlen(endp));
				nextp = endp;
			}

			/* endp now points at the terminating quote */
			nextp = endp + 1;
		}
		else
		{
			/* Unquoted name --- extends to separator or whitespace */
			if (is_ident_start((unsigned char) *nextp))
			{
				nextp++;

				while (*nextp && is_ident_cont((unsigned char) *nextp))
					nextp++;
			}
			else
				return false;
		}

		while (isspace((unsigned char) *nextp))
			nextp++;			/* skip trailing whitespace */

		if (*nextp == '.')
		{
			nextp++;
			while (isspace((unsigned char) *nextp))
				nextp++;		/* skip leading whitespace for next */
			/* we expect another name, so done remains false */
		}
		else if (*nextp == '\0')
			done = true;
		else
			return false;		/* invalid syntax */

		/* Loop back if we didn't reach end of string */
	} while (!done);

	return true;
}

/****************************************************************
 * DBMS_ASSERT.ENQUOTE_LITERAL
 *
 * Syntax:
 *   FUNCTION ENQUOTE_LITERAL(str VARCHAR2) RETURNS VARCHAR2;
 *
 * Purpose:
 *   Add leading and trailing quotes, verify that all single quotes
 *   are paired with adjacent single quotes.
 ****************************************************************/
Datum
ora_dbms_assert_enquote_literal(PG_FUNCTION_ARGS)
{
	PG_RETURN_DATUM(DirectFunctionCall1(quote_literal, PG_GETARG_DATUM(0)));
}

/****************************************************************
 * DBMS_ASSERT.ENQUOTE_NAME
 *
 * Syntax:
 *   FUNCTION ENQUOTE_NAME(str VARCHAR2) RETURNS VARCHAR2;
 *   FUNCTION ENQUOTE_NAME(str VARCHAR2, capitalize BOOLEAN DEFAULT FALSE)
 *       RETURNS VARCHAR2;
 *
 * Purpose:
 *   Enclose the name in double quotes so it is treated case-sensitively.
 *   The optional flag upper-cases the quoted name, mirroring Oracle's
 *   capitalize parameter.
 ****************************************************************/
Datum
ora_dbms_assert_enquote_name(PG_FUNCTION_ARGS)
{
	char	   *name;
	bool		capitalize = PG_GETARG_BOOL(1);
	StringInfoData str;
	char	   *p;

	/*
	 * Oracle's ENQUOTE_NAME always returns the name enclosed in double
	 * quotes (with embedded quotes doubled), so the name keeps its exact
	 * case and any special characters regardless of how quote_ident would
	 * spell it.  The optional flag upper-cases the name before quoting.
	 */
	name = text_to_cstring(PG_GETARG_TEXT_PP(0));

	if (capitalize)
		for (p = name; *p; p++)
			*p = (char) pg_toupper((unsigned char) *p);

	initStringInfo(&str);
	appendStringInfoChar(&str, '"');
	for (p = name; *p; p++)
	{
		if (*p == '"')
			appendStringInfoChar(&str, '"');
		appendStringInfoChar(&str, *p);
	}
	appendStringInfoChar(&str, '"');

	PG_RETURN_TEXT_P(cstring_to_text(str.data));
}

/****************************************************************
 * DBMS_ASSERT.NOOP
 *
 * Syntax:
 *   FUNCTION NOOP(str VARCHAR2) RETURNS VARCHAR2;
 *
 * Purpose:
 *   Returns the value without any checking.
 ****************************************************************/
Datum
ora_dbms_assert_noop(PG_FUNCTION_ARGS)
{
	text	   *str = PG_GETARG_TEXT_P(0);
	text	   *result;

	result = (text *) palloc(VARSIZE(str));
	memcpy(result, str, VARSIZE(str));

	PG_RETURN_TEXT_P(result);
}

/****************************************************************
 * DBMS_ASSERT.QUALIFIED_SQL_NAME
 *
 * Syntax:
 *   FUNCTION QUALIFIED_SQL_NAME(str VARCHAR2) RETURNS VARCHAR2;
 *
 * Purpose:
 *   Verifies that the input string is a qualified SQL name
 *   (dot-separated identifier chain, parts possibly quoted).
 ****************************************************************/
Datum
ora_dbms_assert_qualified_sql_name(PG_FUNCTION_ARGS)
{
	text	   *qname;

	if (PG_ARGISNULL(0))
		ISNOT_QUALIFIED_SQL_NAME_EXCEPTION();

	qname = PG_GETARG_TEXT_P(0);
	if (EMPTY_STR(qname))
		ISNOT_QUALIFIED_SQL_NAME_EXCEPTION();

	if (!ParseIdentifierString(text_to_cstring(qname)))
		ISNOT_QUALIFIED_SQL_NAME_EXCEPTION();

	PG_RETURN_TEXT_P(qname);
}

/****************************************************************
 * DBMS_ASSERT.SCHEMA_NAME
 *
 * Syntax:
 *   FUNCTION SCHEMA_NAME(str VARCHAR2) RETURNS VARCHAR2;
 *
 * Purpose:
 *   Verifies that the input string is an existing schema name that the
 *   current user has USAGE on.
 ****************************************************************/
Datum
ora_dbms_assert_schema_name(PG_FUNCTION_ARGS)
{
	Oid			namespaceId;
	AclResult	aclresult;
	text	   *sname;
	char	   *nspname;
	List	   *names;

	if (PG_ARGISNULL(0))
		INVALID_SCHEMA_NAME_EXCEPTION();

	sname = PG_GETARG_TEXT_P(0);
	if (EMPTY_STR(sname))
		INVALID_SCHEMA_NAME_EXCEPTION();

	nspname = text_to_cstring(sname);

	names = stringToQualifiedNameList(nspname, NULL);

	if (list_length(names) != 1)
		INVALID_SCHEMA_NAME_EXCEPTION();

	namespaceId = GetSysCacheOid(NAMESPACENAME, Anum_pg_namespace_oid,
								 CStringGetDatum(strVal(linitial(names))),
								 0, 0, 0);

	if (!OidIsValid(namespaceId))
		INVALID_SCHEMA_NAME_EXCEPTION();

	aclresult = object_aclcheck(NamespaceRelationId, namespaceId, GetUserId(),
								ACL_USAGE);

	if (aclresult != ACLCHECK_OK)
		INVALID_SCHEMA_NAME_EXCEPTION();

	PG_RETURN_TEXT_P(sname);
}

/****************************************************************
 * DBMS_ASSERT.SIMPLE_SQL_NAME
 *
 * Syntax:
 *   FUNCTION SIMPLE_SQL_NAME(str VARCHAR2) RETURNS VARCHAR2;
 *
 * Purpose:
 *   Verifies that the input string is a single (possibly quoted) SQL
 *   identifier, with no separators, operators or whitespace around it.
 ****************************************************************/
static bool
check_sql_name(char *cp, int len)
{
	if (*cp == '"')
	{
		char	   *last = cp + len - 1;

		/* don't allow empty identifier */
		if (len < 3)
			return false;

		/* last char should be double quote */
		if (*last != '"')
			return false;

		cp += 1;

		while (*cp && cp < last)
		{
			if (*cp++ == '"')
			{
				if (cp < last)
				{
					if (*cp++ != '"')
						return false;
				}
				else
					return false;
			}
		}

		return true;
	}
	else
	{
		if (is_ident_start((unsigned char) *cp))
		{
			char	   *last = cp + len - 1;

			cp += 1;

			while (cp <= last)
			{
				if (!is_ident_cont((unsigned char) *cp++))
					return false;
			}
		}
		else
			return false;
	}

	return true;
}

Datum
ora_dbms_assert_simple_sql_name(PG_FUNCTION_ARGS)
{
	text	   *sname;
	int			len;
	char	   *cp;

	if (PG_ARGISNULL(0))
		ISNOT_SIMPLE_SQL_NAME_EXCEPTION();

	sname = PG_GETARG_TEXT_P(0);
	if (EMPTY_STR(sname))
		ISNOT_SIMPLE_SQL_NAME_EXCEPTION();

	len = VARSIZE(sname) - VARHDRSZ;
	cp = VARDATA(sname);

	if (!check_sql_name(cp, len))
		ISNOT_SIMPLE_SQL_NAME_EXCEPTION();

	PG_RETURN_TEXT_P(sname);
}

/****************************************************************
 * DBMS_ASSERT.SQL_OBJECT_NAME
 *
 * Syntax:
 *   FUNCTION SQL_OBJECT_NAME(str VARCHAR2) RETURNS VARCHAR2;
 *
 * Purpose:
 *   Verifies that the input string is the (optionally qualified) name of
 *   an existing relation visible to the current user.
 ****************************************************************/
Datum
ora_dbms_assert_object_name(PG_FUNCTION_ARGS)
{
	List	   *names;
	text	   *str;
	char	   *object_name;
	Oid			classId;

	if (PG_ARGISNULL(0))
		INVALID_OBJECT_NAME_EXCEPTION();

	str = PG_GETARG_TEXT_P(0);
	if (EMPTY_STR(str))
		INVALID_OBJECT_NAME_EXCEPTION();

	object_name = text_to_cstring(str);

	names = stringToQualifiedNameList(object_name, NULL);

	classId = RangeVarGetRelid(makeRangeVarFromNameList(names), NoLock, true);
	if (!OidIsValid(classId))
		INVALID_OBJECT_NAME_EXCEPTION();

	PG_RETURN_TEXT_P(str);
}
