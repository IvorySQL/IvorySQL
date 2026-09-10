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
 * Implementation of Oracle's DBMS_APPLICATION_INFO package.
 * This module is part of ivorysql_ora extension.
 *
 * Provides session metadata registration and diagnostics:
 *   - SET_MODULE(module_name, action_name)
 *   - SET_ACTION(action_name)
 *   - SET_CLIENT_INFO(client_info)
 *   - READ_MODULE(module_name OUT, action_name OUT)
 *   - READ_CLIENT_INFO(client_info OUT)
 *
 * Field sizes matching Oracle documentation:
 *   module_name: up to 48 bytes (longer values truncated)
 *   action_name: up to 32 bytes (longer values truncated)
 *   client_info: up to 64 bytes (longer values truncated)
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_application_info/dbms_application_info.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "funcapi.h"
#include "utils/builtins.h"
#include "utils/memutils.h"

#define DBMS_APPINFO_MODULE_LEN	48
#define DBMS_APPINFO_ACTION_LEN	32
#define DBMS_APPINFO_CLIENT_LEN	64

/* Per-backend session application info state */
static char *session_module = NULL;
static char *session_action = NULL;
static char *session_client_info = NULL;
static MemoryContext DbmsAppInfoContext = NULL;

static void init_appinfo_context(void);
static void copy_truncated(char **dest, const char *src, size_t max_bytes);

static void
init_appinfo_context(void)
{
	if (DbmsAppInfoContext == NULL)
	{
		DbmsAppInfoContext = AllocSetContextCreate(TopMemoryContext,
												   "DbmsApplicationInfoContext",
												   ALLOCSET_DEFAULT_SIZES);
	}
}

static void
copy_truncated(char **dest, const char *src, size_t max_bytes)
{
	init_appinfo_context();

	if (*dest != NULL)
	{
		pfree(*dest);
		*dest = NULL;
	}

	if (src != NULL)
	{
		size_t len = strlen(src);
		size_t copylen = (len > max_bytes) ? max_bytes : len;
		MemoryContext oldcxt = MemoryContextSwitchTo(DbmsAppInfoContext);

		*dest = (char *) palloc(copylen + 1);
		memcpy(*dest, src, copylen);
		(*dest)[copylen] = '\0';

		MemoryContextSwitchTo(oldcxt);
	}
}

/*
 * dbms_application_info_set_module
 *
 * Sets module_name (max 48 bytes) and action_name (max 32 bytes).
 */
PG_FUNCTION_INFO_V1(dbms_application_info_set_module);
Datum
dbms_application_info_set_module(PG_FUNCTION_ARGS)
{
	const char *mod = PG_ARGISNULL(0) ? NULL : text_to_cstring(PG_GETARG_TEXT_PP(0));
	const char *act = PG_ARGISNULL(1) ? NULL : text_to_cstring(PG_GETARG_TEXT_PP(1));

	copy_truncated(&session_module, mod, DBMS_APPINFO_MODULE_LEN);
	copy_truncated(&session_action, act, DBMS_APPINFO_ACTION_LEN);

	PG_RETURN_VOID();
}

/*
 * dbms_application_info_set_action
 *
 * Sets action_name (max 32 bytes).
 */
PG_FUNCTION_INFO_V1(dbms_application_info_set_action);
Datum
dbms_application_info_set_action(PG_FUNCTION_ARGS)
{
	const char *act = PG_ARGISNULL(0) ? NULL : text_to_cstring(PG_GETARG_TEXT_PP(0));

	copy_truncated(&session_action, act, DBMS_APPINFO_ACTION_LEN);

	PG_RETURN_VOID();
}

/*
 * dbms_application_info_set_client_info
 *
 * Sets client_info (max 64 bytes).
 */
PG_FUNCTION_INFO_V1(dbms_application_info_set_client_info);
Datum
dbms_application_info_set_client_info(PG_FUNCTION_ARGS)
{
	const char *info = PG_ARGISNULL(0) ? NULL : text_to_cstring(PG_GETARG_TEXT_PP(0));

	copy_truncated(&session_client_info, info, DBMS_APPINFO_CLIENT_LEN);

	PG_RETURN_VOID();
}

/*
 * dbms_application_info_read_module
 *
 * Returns module and action via record/composite or simple getter.
 */
PG_FUNCTION_INFO_V1(dbms_application_info_get_module);
Datum
dbms_application_info_get_module(PG_FUNCTION_ARGS)
{
	if (session_module == NULL)
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(cstring_to_text(session_module));
}

PG_FUNCTION_INFO_V1(dbms_application_info_get_action);
Datum
dbms_application_info_get_action(PG_FUNCTION_ARGS)
{
	if (session_action == NULL)
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(cstring_to_text(session_action));
}

/*
 * dbms_application_info_get_client_info
 */
PG_FUNCTION_INFO_V1(dbms_application_info_get_client_info);
Datum
dbms_application_info_get_client_info(PG_FUNCTION_ARGS)
{
	if (session_client_info == NULL)
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(cstring_to_text(session_client_info));
}
