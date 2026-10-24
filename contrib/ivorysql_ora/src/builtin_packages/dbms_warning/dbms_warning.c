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
 * Implementation of Oracle's DBMS_WARNING package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides compiler warning settings and categories manipulation:
 *   - ADD_WARNING_SETTING_NUM
 *   - GET_WARNING_SETTING_NUM
 *   - GET_CATEGORY
 *   - SET_WARNING_SETTING_STRING
 *   - GET_WARNING_SETTING_STRING
 *
 * Warning modifiers:
 *   - ENABLE
 *   - DISABLE
 *   - ERROR
 *
 * Warning categories:
 *   - ALL
 *   - INFORMATIONAL
 *   - SEVERE
 *   - PERFORMANCE
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_warning/dbms_warning.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"

static char current_warning_setting[1024] = "ENABLE:ALL";

/*
 * dbms_warning_get_category_internal
 */
PG_FUNCTION_INFO_V1(dbms_warning_get_category_internal);
Datum
dbms_warning_get_category_internal(PG_FUNCTION_ARGS)
{
	int32 warning_number = PG_GETARG_INT32(0);
	const char *category;

	/* Map Oracle standard PL/SQL warning number ranges */
	if (warning_number >= 5000 && warning_number <= 5999)
		category = "SEVERE";
	else if (warning_number >= 6000 && warning_number <= 6999)
		category = "INFORMATIONAL";
	else if (warning_number >= 7000 && warning_number <= 7999)
		category = "PERFORMANCE";
	else
		category = "INFORMATIONAL";

	PG_RETURN_TEXT_P(cstring_to_text(category));
}

/*
 * dbms_warning_add_warning_setting_num_internal
 */
PG_FUNCTION_INFO_V1(dbms_warning_add_warning_setting_num_internal);
Datum
dbms_warning_add_warning_setting_num_internal(PG_FUNCTION_ARGS)
{
	int32		warning_number = PG_GETARG_INT32(0);
	text	   *value_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *current_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	char	   *value_str;
	StringInfoData buf;

	if (!value_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_WARNING.ADD_WARNING_SETTING_NUM: warning_value must not be NULL")));

	value_str = text_to_cstring(value_text);

	initStringInfo(&buf);
	if (current_text && VARSIZE_ANY_EXHDR(current_text) > 0)
	{
		char *curr = text_to_cstring(current_text);
		appendStringInfo(&buf, "%s, ", curr);
		pfree(curr);
	}
	appendStringInfo(&buf, "%s:%d", value_str, warning_number);

	pfree(value_str);
	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

/*
 * dbms_warning_get_warning_setting_num_internal
 */
PG_FUNCTION_INFO_V1(dbms_warning_get_warning_setting_num_internal);
Datum
dbms_warning_get_warning_setting_num_internal(PG_FUNCTION_ARGS)
{
	int32		warning_number = PG_GETARG_INT32(0);
	char		pattern[32];

	snprintf(pattern, sizeof(pattern), ":%d", warning_number);

	if (strstr(current_warning_setting, pattern))
	{
		if (strstr(current_warning_setting, "ERROR"))
			PG_RETURN_TEXT_P(cstring_to_text("ERROR"));
		if (strstr(current_warning_setting, "DISABLE"))
			PG_RETURN_TEXT_P(cstring_to_text("DISABLE"));
		PG_RETURN_TEXT_P(cstring_to_text("ENABLE"));
	}

	PG_RETURN_TEXT_P(cstring_to_text("ENABLE"));
}

/*
 * dbms_warning_set_warning_setting_string_internal
 */
PG_FUNCTION_INFO_V1(dbms_warning_set_warning_setting_string_internal);
Datum
dbms_warning_set_warning_setting_string_internal(PG_FUNCTION_ARGS)
{
	text	   *setting_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);

	if (!setting_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_WARNING: warning_setting must not be NULL")));

	strlcpy(current_warning_setting, text_to_cstring(setting_text), sizeof(current_warning_setting));
	PG_RETURN_VOID();
}

/*
 * dbms_warning_get_warning_setting_string_internal
 */
PG_FUNCTION_INFO_V1(dbms_warning_get_warning_setting_string_internal);
Datum
dbms_warning_get_warning_setting_string_internal(PG_FUNCTION_ARGS)
{
	PG_RETURN_TEXT_P(cstring_to_text(current_warning_setting));
}
