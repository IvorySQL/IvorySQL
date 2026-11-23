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
 * Implementation of Oracle's UTL_I18N package.
 * This module is part of ivorysql_ora extension.
 *
 * Provides national language architecture and character conversion utilities:
 *   - ESCAPE_REFERENCE: converts characters to HTML/XML character references
 *   - UNESCAPE_REFERENCE: decodes character references back to characters
 *   - STRING_TO_RAW: converts string to raw data in target character set
 *   - RAW_TO_CHAR: converts raw data to string in database character set
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_i18n/utl_i18n.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <ctype.h>
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "mb/pg_wchar.h"
#include "utils/builtins.h"

static int utl_i18n_charset_to_encoding(const char *charset);

/*
 * Map Oracle character set names or common charset aliases to PostgreSQL encoding.
 * Returns -1 if unrecognized.
 */
static int
utl_i18n_charset_to_encoding(const char *charset)
{
	int encoding;
	char lower_name[64];
	int i;

	if (charset == NULL || charset[0] == '\0')
		return GetDatabaseEncoding();

	for (i = 0; charset[i] != '\0' && i < sizeof(lower_name) - 1; i++)
		lower_name[i] = (char) tolower((unsigned char) charset[i]);
	lower_name[i] = '\0';

	/* Check common Oracle charset names */
	if (strcmp(lower_name, "al32utf8") == 0 ||
		strcmp(lower_name, "utf8") == 0 ||
		strcmp(lower_name, "utf-8") == 0)
		return PG_UTF8;

	if (strcmp(lower_name, "us7ascii") == 0 ||
		strcmp(lower_name, "ascii") == 0 ||
		strcmp(lower_name, "us-ascii") == 0)
		return PG_SQL_ASCII;

	if (strcmp(lower_name, "we8iso8859p1") == 0 ||
		strcmp(lower_name, "iso-8859-1") == 0 ||
		strcmp(lower_name, "latin1") == 0)
		return PG_LATIN1;

	if (strcmp(lower_name, "gbk") == 0 ||
		strcmp(lower_name, "zhs16gbk") == 0)
		return PG_GBK;

	if (strcmp(lower_name, "gb18030") == 0)
		return PG_GB18030;

	encoding = pg_char_to_encoding(charset);
	if (encoding < 0)
		encoding = pg_char_to_encoding(lower_name);

	return encoding;
}

/*
 * ivorysql_utl_i18n_escape_reference
 *
 * Converts a text string to HTML/XML character references.
 *
 * Predefined entities:
 *   '&' -> '&amp;'
 *   '<' -> '&lt;'
 *   '>' -> '&gt;'
 *   '"' -> '&quot;'
 *   '\'' -> '&apos;'
 *
 * When page_cs_name is specified (e.g., 'us7ascii'), non-ASCII characters
 * (code points > 127) are converted to hexadecimal character references:
 *   &#x[hex];
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_i18n_escape_reference);
Datum
ivorysql_utl_i18n_escape_reference(PG_FUNCTION_ARGS)
{
	text	   *input_text;
	char	   *str;
	int			str_len;
	const char *page_cs = NULL;
	int			target_encoding = -1;
	StringInfoData buf;
	int			i;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	input_text = PG_GETARG_TEXT_PP(0);
	str = text_to_cstring(input_text);
	str_len = strlen(str);

	if (PG_NARGS() >= 2 && !PG_ARGISNULL(1))
	{
		text *cs_text = PG_GETARG_TEXT_PP(1);
		page_cs = text_to_cstring(cs_text);
		target_encoding = utl_i18n_charset_to_encoding(page_cs);
		if (target_encoding < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_I18N: invalid character set \"%s\"", page_cs)));
	}

	initStringInfo(&buf);

	for (i = 0; i < str_len; )
	{
		unsigned char c = (unsigned char) str[i];

		if (c == '&')
		{
			appendStringInfoString(&buf, "&amp;");
			i++;
		}
		else if (c == '<')
		{
			appendStringInfoString(&buf, "&lt;");
			i++;
		}
		else if (c == '>')
		{
			appendStringInfoString(&buf, "&gt;");
			i++;
		}
		else if (c == '"')
		{
			appendStringInfoString(&buf, "&quot;");
			i++;
		}
		else if (c == '\'')
		{
			appendStringInfoString(&buf, "&apos;");
			i++;
		}
		else if (c < 128)
		{
			appendStringInfoChar(&buf, (char) c);
			i++;
		}
		else
		{
			/*
			 * Multibyte or non-ASCII character.
			 * If target encoding is restricted (e.g. ASCII) or character doesn't fit,
			 * convert to numeric character reference &#x...;
			 */
			int mblen = pg_mblen(&str[i]);

			if (target_encoding == PG_SQL_ASCII || target_encoding >= 0)
			{
				int codepoint = 0;
				if (GetDatabaseEncoding() == PG_UTF8)
				{
					codepoint = (int) utf8_to_unicode((const unsigned char *) &str[i]);
				}
				else
				{
					codepoint = (unsigned char) str[i];
				}
				appendStringInfo(&buf, "&#x%x;", codepoint);
			}
			else
			{
				/* Keep character as is */
				appendBinaryStringInfo(&buf, &str[i], mblen);
			}
			i += mblen;
		}
	}

	PG_RETURN_TEXT_P(cstring_to_text_with_len(buf.data, buf.len));
}

/*
 * ivorysql_utl_i18n_unescape_reference
 *
 * Decodes character references in string back to characters.
 * Supports:
 *   Predefined entities: &amp;, &lt;, &gt;, &quot;, &apos;
 *   Hexadecimal numeric references: &#x[0-9a-fA-F]+;
 *   Decimal numeric references: &# [0-9]+;
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_i18n_unescape_reference);
Datum
ivorysql_utl_i18n_unescape_reference(PG_FUNCTION_ARGS)
{
	text	   *input_text;
	char	   *str;
	int			str_len;
	StringInfoData buf;
	int			i;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	input_text = PG_GETARG_TEXT_PP(0);
	str = text_to_cstring(input_text);
	str_len = strlen(str);

	if (str_len == 0)
		PG_RETURN_TEXT_P(cstring_to_text(""));

	initStringInfo(&buf);

	for (i = 0; i < str_len; )
	{
		if (str[i] == '&')
		{
			if (strncmp(&str[i], "&amp;", 5) == 0)
			{
				appendStringInfoChar(&buf, '&');
				i += 5;
				continue;
			}
			if (strncmp(&str[i], "&lt;", 4) == 0)
			{
				appendStringInfoChar(&buf, '<');
				i += 4;
				continue;
			}
			if (strncmp(&str[i], "&gt;", 4) == 0)
			{
				appendStringInfoChar(&buf, '>');
				i += 4;
				continue;
			}
			if (strncmp(&str[i], "&quot;", 6) == 0)
			{
				appendStringInfoChar(&buf, '"');
				i += 6;
				continue;
			}
			if (strncmp(&str[i], "&apos;", 6) == 0)
			{
				appendStringInfoChar(&buf, '\'');
				i += 6;
				continue;
			}
			if (str[i + 1] == '#')
			{
				/* Numeric character reference */
				int semi = i + 2;
				while (semi < str_len && str[semi] != ';' && (semi - i) < 12)
					semi++;

				if (semi < str_len && str[semi] == ';')
				{
					long codepoint = 0;
					char *endptr = NULL;

					if (str[i + 2] == 'x' || str[i + 2] == 'X')
					{
						codepoint = strtol(&str[i + 3], &endptr, 16);
					}
					else if (isdigit((unsigned char) str[i + 2]))
					{
						codepoint = strtol(&str[i + 2], &endptr, 10);
					}

					if (endptr == &str[semi] && codepoint > 0)
					{
						if (codepoint < 128)
						{
							appendStringInfoChar(&buf, (char) codepoint);
						}
						else if (GetDatabaseEncoding() == PG_UTF8 && codepoint <= 0x10FFFF)
						{
							unsigned char utf8_buf[8];
							unicode_to_utf8((pg_wchar) codepoint, utf8_buf);
							appendBinaryStringInfo(&buf, (char *) utf8_buf, pg_utf_mblen((char *) utf8_buf));
						}
						else
						{
							appendStringInfoChar(&buf, (char) (codepoint & 0xFF));
						}
						i = semi + 1;
						continue;
					}
				}
			}
		}

		/* Normal character */
		appendStringInfoChar(&buf, str[i]);
		i++;
	}

	PG_RETURN_TEXT_P(cstring_to_text_with_len(buf.data, buf.len));
}

/*
 * ivorysql_utl_i18n_string_to_raw
 *
 * Converts a string to RAW (bytea) encoded in target charset.
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_i18n_string_to_raw);
Datum
ivorysql_utl_i18n_string_to_raw(PG_FUNCTION_ARGS)
{
	text	   *input_text;
	char	   *src;
	int			src_len;
	int			target_encoding;
	char	   *converted;
	int			converted_len;
	bytea	   *result;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	input_text = PG_GETARG_TEXT_PP(0);
	src = text_to_cstring(input_text);
	src_len = strlen(src);

	if (src_len == 0)
		PG_RETURN_NULL();

	if (PG_NARGS() >= 2 && !PG_ARGISNULL(1))
	{
		char *dst_cs = text_to_cstring(PG_GETARG_TEXT_PP(1));
		target_encoding = utl_i18n_charset_to_encoding(dst_cs);
		if (target_encoding < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_I18N: invalid character set \"%s\"", dst_cs)));
	}
	else
	{
		target_encoding = GetDatabaseEncoding();
	}

	converted = pg_server_to_any(src, src_len, target_encoding);
	converted_len = strlen(converted);

	result = (bytea *) palloc(converted_len + VARHDRSZ);
	SET_VARSIZE(result, converted_len + VARHDRSZ);
	memcpy(VARDATA(result), converted, converted_len);

	PG_RETURN_BYTEA_P(result);
}

/*
 * ivorysql_utl_i18n_raw_to_char
 *
 * Converts RAW (bytea) data in source charset to a VARCHAR2 (text) string.
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_i18n_raw_to_char);
Datum
ivorysql_utl_i18n_raw_to_char(PG_FUNCTION_ARGS)
{
	bytea	   *input_raw;
	char	   *raw_data;
	int			raw_len;
	int			src_encoding;
	char	   *converted;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	input_raw = PG_GETARG_BYTEA_PP(0);
	raw_len = VARSIZE_ANY_EXHDR(input_raw);
	raw_data = VARDATA_ANY(input_raw);

	if (raw_len == 0)
		PG_RETURN_NULL();

	if (PG_NARGS() >= 2 && !PG_ARGISNULL(1))
	{
		char *src_cs = text_to_cstring(PG_GETARG_TEXT_PP(1));
		src_encoding = utl_i18n_charset_to_encoding(src_cs);
		if (src_encoding < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_I18N: invalid character set \"%s\"", src_cs)));
	}
	else
	{
		src_encoding = GetDatabaseEncoding();
	}

	converted = pg_any_to_server(raw_data, raw_len, src_encoding);

	PG_RETURN_TEXT_P(cstring_to_text(converted));
}
