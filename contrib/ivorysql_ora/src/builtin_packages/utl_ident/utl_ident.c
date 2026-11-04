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
 * Implementation of Oracle's UTL_IDENT package.
 * This module is part of ivorysql_ora extension.
 *
 * Provides database and client environment identification flags
 * commonly used in conditional compilation and runtime environment detection:
 *   - IS_ORACLE_SERVER
 *   - IS_ORACLE_CLIENT
 *   - IS_TIMESTEN
 *   - IS_ORACLE_FORMS
 *   - IS_SATELLITE
 *
 * In addition, provides environment inspection helpers:
 *   - GET_ENVIRONMENT() -> 'ORACLE_SERVER'
 *   - CHECK_SERVER() -> TRUE
 *   - GET_RELEASE_MAJOR()
 *   - GET_RELEASE_MINOR()
 *   - GET_VERSION_STRING()
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_ident/utl_ident.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "miscadmin.h"
#include "utils/builtins.h"
#include "utils/guc.h"

/*
 * Returns whether current backend is running in IvorySQL Oracle server mode.
 */
PG_FUNCTION_INFO_V1(utl_ident_is_oracle_server);
Datum
utl_ident_is_oracle_server(PG_FUNCTION_ARGS)
{
	PG_RETURN_BOOL(true);
}

PG_FUNCTION_INFO_V1(utl_ident_is_oracle_client);
Datum
utl_ident_is_oracle_client(PG_FUNCTION_ARGS)
{
	PG_RETURN_BOOL(false);
}

PG_FUNCTION_INFO_V1(utl_ident_is_timesten);
Datum
utl_ident_is_timesten(PG_FUNCTION_ARGS)
{
	PG_RETURN_BOOL(false);
}

PG_FUNCTION_INFO_V1(utl_ident_is_oracle_forms);
Datum
utl_ident_is_oracle_forms(PG_FUNCTION_ARGS)
{
	PG_RETURN_BOOL(false);
}

PG_FUNCTION_INFO_V1(utl_ident_is_satellite);
Datum
utl_ident_is_satellite(PG_FUNCTION_ARGS)
{
	PG_RETURN_BOOL(false);
}

/*
 * utl_ident_environment
 *
 * Diagnostic helper returning the current environment name.
 */
PG_FUNCTION_INFO_V1(utl_ident_environment);
Datum
utl_ident_environment(PG_FUNCTION_ARGS)
{
	PG_RETURN_TEXT_P(cstring_to_text("ORACLE_SERVER"));
}

/*
 * utl_ident_get_release_major
 *
 * Returns the major release compatibility number (e.g., 23 / 19 / 18).
 */
PG_FUNCTION_INFO_V1(utl_ident_get_release_major);
Datum
utl_ident_get_release_major(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT32(23);
}

/*
 * utl_ident_get_release_minor
 *
 * Returns the minor release compatibility number.
 */
PG_FUNCTION_INFO_V1(utl_ident_get_release_minor);
Datum
utl_ident_get_release_minor(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT32(0);
}

/*
 * utl_ident_get_version_string
 *
 * Returns human-readable version string for the active Oracle compatibility layer.
 */
PG_FUNCTION_INFO_V1(utl_ident_get_version_string);
Datum
utl_ident_get_version_string(PG_FUNCTION_ARGS)
{
	PG_RETURN_TEXT_P(cstring_to_text("IvorySQL Oracle Compatible Server 23c"));
}

/*
 * utl_ident_matches_environment
 *
 * Returns true if the query parameter matches the current environment name (case-insensitive).
 */
PG_FUNCTION_INFO_V1(utl_ident_matches_environment);
Datum
utl_ident_matches_environment(PG_FUNCTION_ARGS)
{
	text *env_text;
	char *env;
	bool matches = false;

	if (PG_ARGISNULL(0))
		PG_RETURN_BOOL(false);

	env_text = PG_GETARG_TEXT_PP(0);
	env = text_to_cstring(env_text);

	if (pg_strcasecmp(env, "ORACLE_SERVER") == 0 ||
		pg_strcasecmp(env, "SERVER") == 0 ||
		pg_strcasecmp(env, "ORACLE") == 0)
	{
		matches = true;
	}

	pfree(env);
	PG_RETURN_BOOL(matches);
}
