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
 * Implementation of Oracle's UTL_URL package.
 * This module is part of ivorysql_ora extension.
 *
 * Provides the URL escape mechanism described by RFC 2396 (which is
 * what Oracle's UTL_URL implements).  Note that this is NOT the
 * x-www-form-urlencoded scheme: a space becomes "%20", never "+".
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_url/utl_url.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "lib/stringinfo.h"
#include "mb/pg_wchar.h"
#include "utils/builtins.h"

/*
 * RFC 2396 / Oracle UTL_URL character classes.
 *
 * "Unreserved" characters are always passed through unescaped:
 *		A-Z  a-z  0-9  -  _  .  !  ~  *  '  (  )
 *
 * "Reserved" characters are URL delimiters.  They are passed through when
 * escape_reserved_chars is FALSE (the Oracle default) and escaped when it is
 * TRUE:
 *		;  /  ?  :  @  &  =  +  $  %  ,  #
 *
 * Everything else (space, control characters, "<", ">", quotes, braces,
 * brackets, backslash, and every non-ASCII byte) is an "illegal" URL
 * character and is always escaped.
 */
#define UTL_URL_UNRESERVED_CHARS	"-_.!~*'()"
#define UTL_URL_RESERVED_CHARS		";/?:@&=+$%,#"

static bool utl_url_is_unreserved(unsigned char c);
static bool utl_url_is_reserved(unsigned char c);
static int	utl_url_charset_to_encoding(text *charset);

/*
 * utl_url_is_unreserved - is c an RFC 2396 unreserved character?
 *
 * Only plain ASCII alphanumerics qualify, so we deliberately avoid the
 * locale-dependent isalnum() here.
 */
static bool
utl_url_is_unreserved(unsigned char c)
{
	if ((c >= 'A' && c <= 'Z') ||
		(c >= 'a' && c <= 'z') ||
		(c >= '0' && c <= '9'))
		return true;

	return (c != '\0' && strchr(UTL_URL_UNRESERVED_CHARS, c) != NULL);
}

/*
 * utl_url_is_reserved - is c an RFC 2396 reserved (delimiter) character?
 */
static bool
utl_url_is_reserved(unsigned char c)
{
	return (c != '\0' && strchr(UTL_URL_RESERVED_CHARS, c) != NULL);
}

/*
 * utl_url_charset_to_encoding - resolve a url_charset argument.
 *
 * Accepts both IANA names ("ISO-8859-1", "UTF-8") and PostgreSQL names
 * ("LATIN1", "UTF8"); pg_char_to_encoding() normalises case, dashes and
 * underscores for us.
 *
 * Oracle raises BAD_FIXED_WIDTH_CHARSET (ORA-29274) for fixed-width multibyte
 * character sets.  PostgreSQL has no such encoding in its catalog at all
 * (UTF-16/UTF-32 are not supported), so that condition is unreachable here and
 * every rejected name lands in the "unrecognized" branch below.
 */
static int
utl_url_charset_to_encoding(text *charset)
{
	char	   *name = text_to_cstring(charset);
	int			encoding = pg_char_to_encoding(name);

	if (encoding < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_URL: unrecognized URL character set \"%s\"", name)));

	pfree(name);

	return encoding;
}

/*
 * ivorysql_utl_url_escape
 *
 * Oracle-compatible ESCAPE implementation:
 *   - Escapes illegal URL characters as %XX (upper-case hex)
 *   - Escapes the reserved delimiters as well when escape_reserved_chars is
 *     TRUE; passes them through when it is FALSE (Oracle's default)
 *   - Multibyte characters are first converted to url_charset and then each
 *     resulting byte is escaped separately, so a UTF-8 CJK character yields
 *     three %XX groups
 *   - A NULL url returns NULL
 *   - A NULL url_charset means "use the database encoding, do not convert",
 *     which is Oracle's documented behaviour for a NULL url_charset
 *
 * Oracle signature:
 *   UTL_URL.ESCAPE(url IN VARCHAR2,
 *                  escape_reserved_chars IN BOOLEAN DEFAULT FALSE,
 *                  url_charset IN VARCHAR2 DEFAULT utl_http.body_charset)
 *   RETURN VARCHAR2
 * Maps to: (text, bool, text) -> text
 *
 * Not declared STRICT: url_charset is legitimately NULL in the default case,
 * and a STRICT function would then wrongly return NULL for every call.
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_url_escape);
Datum
ivorysql_utl_url_escape(PG_FUNCTION_ARGS)
{
	text	   *url;
	bool		escape_reserved;
	int			target_encoding;
	char	   *src;
	char	   *converted;
	int			len;
	int			i;
	StringInfoData buf;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	url = PG_GETARG_TEXT_PP(0);

	/* A NULL boolean is treated like the default, FALSE */
	escape_reserved = PG_ARGISNULL(1) ? false : PG_GETARG_BOOL(1);

	target_encoding = PG_ARGISNULL(2) ? GetDatabaseEncoding() :
		utl_url_charset_to_encoding(PG_GETARG_TEXT_PP(2));

	/*
	 * Work on a NUL-terminated copy: pg_server_to_any() may hand the input
	 * pointer straight back, and the conversion helpers expect C strings.
	 */
	src = text_to_cstring(url);
	converted = pg_server_to_any(src, strlen(src), target_encoding);
	len = strlen(converted);

	initStringInfo(&buf);
	for (i = 0; i < len; i++)
	{
		unsigned char c = (unsigned char) converted[i];

		if (utl_url_is_unreserved(c) ||
			(!escape_reserved && utl_url_is_reserved(c)))
			appendStringInfoChar(&buf, (char) c);
		else
			appendStringInfo(&buf, "%%%02X", c);
	}

	/* The result is pure ASCII, hence valid in every server encoding */
	PG_RETURN_TEXT_P(cstring_to_text_with_len(buf.data, buf.len));
}
