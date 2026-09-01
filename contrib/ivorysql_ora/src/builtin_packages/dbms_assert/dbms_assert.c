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

#define INVALID_QUOTED_LITERAL_EXCEPTION() \
	ereport(ERROR, \
		(errcode(ERRCODE_INVALID_PARAMETER_VALUE), \
		 errmsg("invalid quoted literal")))

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
	/* Can be a digit, dollar sign, or number sign ... */
	if ((c >= '0' && c <= '9') || c == '$' || c == '#')
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
 * input is a valid nonempty qualified identifier.
 */
static bool
ParseIdentifierString(char *rawstring)
{
	char	   *nextp = rawstring;
	bool		done = false;

	while (isspace((unsigned char) *nextp))
		nextp++;				/* skip leading whitespace */

	if (*nextp == '\0')
		return false;			/* reject whitespace-only input */

	/* At the top of the loop, we are at start of a new identifier. */
	do
	{
		if (*nextp == '\"')
		{
			bool		have_content = false;

			/* Quoted name --- accept adjacent quote pairs as content. */
			nextp++;
			for (;;)
			{
				if (*nextp == '\0')
					return false;	/* mismatched quotes */

				if (*nextp == '\"')
				{
					if (nextp[1] == '\"')
					{
						have_content = true;
						nextp += 2;
						continue;
					}

					if (!have_content)
						return false;	/* empty quoted identifier */

					nextp++;
					break;
				}

				have_content = true;
				nextp++;
			}
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
	text	   *str = PG_GETARG_TEXT_PP(0);
	char	   *data = VARDATA_ANY(str);
	int			len = VARSIZE_ANY_EXHDR(str);
	bool		enclosed;
	int			first;
	int			last;
	int			i;
	text	   *result;
	char	   *dest;

	enclosed = len >= 2 && data[0] == '\'' && data[len - 1] == '\'';
	first = enclosed ? 1 : 0;
	last = enclosed ? len - 1 : len;

	for (i = first; i < last; i++)
	{
		if (data[i] == '\'')
		{
			if (i + 1 >= last || data[i + 1] != '\'')
				INVALID_QUOTED_LITERAL_EXCEPTION();
			i++;
		}
	}

	if (enclosed)
		PG_RETURN_TEXT_P(str);

	result = (text *) palloc(VARHDRSZ + len + 2);
	SET_VARSIZE(result, VARHDRSZ + len + 2);
	dest = VARDATA(result);
	dest[0] = '\'';
	memcpy(dest + 1, data, len);
	dest[len + 1] = '\'';

	PG_RETURN_TEXT_P(result);
}

/****************************************************************
 * DBMS_ASSERT.ENQUOTE_NAME
 *
 * Syntax:
 *   FUNCTION ENQUOTE_NAME(str VARCHAR2) RETURNS VARCHAR2;
 *   FUNCTION ENQUOTE_NAME(str VARCHAR2, capitalize BOOLEAN DEFAULT TRUE)
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
	text	   *name_text = PG_GETARG_TEXT_PP(0);
	char	   *name;
	int			len;
	bool		capitalize = PG_GETARG_BOOL(1);
	StringInfoData str;
	char	   *p;

	/*
	 * Already quoted names are validated and returned unchanged.  Otherwise
	 * Oracle adds the enclosing quotes, optionally upper-cases the input, and
	 * verifies that any embedded double quotes are adjacent pairs.
	 */
	name = text_to_cstring(name_text);
	len = strlen(name);

	if (name[0] == '\"')
	{
		if (!check_sql_name(name, len))
			ISNOT_SIMPLE_SQL_NAME_EXCEPTION();
		PG_RETURN_TEXT_P(name_text);
	}

	if (capitalize)
		for (p = name; *p; p++)
			*p = (char) pg_toupper((unsigned char) *p);

	initStringInfo(&str);
	appendStringInfoChar(&str, '"');
	appendStringInfoString(&str, name);
	appendStringInfoChar(&str, '"');

	if (!check_sql_name(str.data, str.len))
		ISNOT_SIMPLE_SQL_NAME_EXCEPTION();

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
 *   identifier.  Leading and trailing whitespace are allowed and preserved.
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

	while (len > 0 && isspace((unsigned char) *cp))
	{
		cp++;
		len--;
	}
	while (len > 0 && isspace((unsigned char) cp[len - 1]))
		len--;

	if (len == 0 || !check_sql_name(cp, len))
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
