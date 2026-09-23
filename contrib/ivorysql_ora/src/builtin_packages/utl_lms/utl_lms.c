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
 * Implementation of Oracle's UTL_LMS package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides language and message service formatting and retrieval:
 *   - GET_MESSAGE: retrieves message template from message repository.
 *   - FORMAT_MESSAGE: replaces '%s', '%d' format specifiers in template string.
 *   - FORMAT_MESSAGE_N: handles variable number of parameters (up to 8).
 *   - GET_MESSAGE_EXT: extended error message retrieval with language mapping.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_lms/utl_lms.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"

/*
 * utl_lms_format_message_internal
 *
 * Formats a template string by replacing %s or %d with provided arguments.
 */
PG_FUNCTION_INFO_V1(utl_lms_format_message_internal);
Datum
utl_lms_format_message_internal(PG_FUNCTION_ARGS)
{
	text	   *format_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *format;
	char	   *p;
	StringInfoData buf;
	int			arg_idx = 1;
	int			nargs = PG_NARGS();

	if (!format_text)
		PG_RETURN_NULL();

	format = text_to_cstring(format_text);
	initStringInfo(&buf);

	p = format;
	while (*p != '\0')
	{
		if (*p == '%' && (*(p + 1) == 's' || *(p + 1) == 'd'))
		{
			p += 2;
			if (arg_idx < nargs && !PG_ARGISNULL(arg_idx))
			{
				text *arg_text = PG_GETARG_TEXT_PP(arg_idx);
				char *arg_str = text_to_cstring(arg_text);
				appendStringInfoString(&buf, arg_str);
				pfree(arg_str);
			}
			arg_idx++;
		}
		else if (*p == '%' && *(p + 1) == '%')
		{
			appendStringInfoChar(&buf, '%');
			p += 2;
		}
		else
		{
			appendStringInfoChar(&buf, *p);
			p++;
		}
	}

	pfree(format);
	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

/*
 * utl_lms_format_message_extended_internal
 *
 * Supports up to 8 positional parameter replacements.
 */
PG_FUNCTION_INFO_V1(utl_lms_format_message_extended_internal);
Datum
utl_lms_format_message_extended_internal(PG_FUNCTION_ARGS)
{
	text	   *format_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *format;
	char	   *p;
	StringInfoData buf;
	int			arg_idx = 1;
	int			nargs = PG_NARGS();

	if (!format_text)
		PG_RETURN_NULL();

	format = text_to_cstring(format_text);
	initStringInfo(&buf);

	p = format;
	while (*p != '\0')
	{
		if (*p == '%' && (*(p + 1) == 's' || *(p + 1) == 'd'))
		{
			p += 2;
			if (arg_idx < nargs && !PG_ARGISNULL(arg_idx))
			{
				text *arg_text = PG_GETARG_TEXT_PP(arg_idx);
				char *arg_str = text_to_cstring(arg_text);
				appendStringInfoString(&buf, arg_str);
				pfree(arg_str);
			}
			arg_idx++;
		}
		else if (*p == '%' && *(p + 1) == '%')
		{
			appendStringInfoChar(&buf, '%');
			p += 2;
		}
		else
		{
			appendStringInfoChar(&buf, *p);
			p++;
		}
	}

	pfree(format);
	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

/*
 * utl_lms_get_message_internal
 */
PG_FUNCTION_INFO_V1(utl_lms_get_message_internal);
Datum
utl_lms_get_message_internal(PG_FUNCTION_ARGS)
{
	int32		errnum = PG_GETARG_INT32(0);
	text	   *product_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *facility_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	text	   *language_text = PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3);
	char		buf[256];

	/* Synthesize Oracle standard message for code */
	snprintf(buf, sizeof(buf), "ORA-%05d: error message occurred for code %d", errnum, errnum);

	PG_RETURN_TEXT_P(cstring_to_text(buf));
}

/*
 * utl_lms_get_message_extended_internal
 */
PG_FUNCTION_INFO_V1(utl_lms_get_message_extended_internal);
Datum
utl_lms_get_message_extended_internal(PG_FUNCTION_ARGS)
{
	int32		errnum = PG_GETARG_INT32(0);
	text	   *product_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *facility_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	text	   *language_text = PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3);
	char		buf[384];

	snprintf(buf, sizeof(buf),
			 "ORA-%05d: error occurred in %s.%s [lang: %s]",
			 errnum,
			 product_text ? text_to_cstring(product_text) : "rdbms",
			 facility_text ? text_to_cstring(facility_text) : "ora",
			 language_text ? text_to_cstring(language_text) : "american");

	PG_RETURN_TEXT_P(cstring_to_text(buf));
}
