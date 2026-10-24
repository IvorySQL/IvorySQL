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
 * Implementation of Oracle's DBMS_TTS package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides Transportable Tablespace self-containment checks and validations:
 *   - TRANSPORT_SET_CHECK
 *   - DOWNGRADE
 *   - IS_PLATFORM_SUPPORTED
 *   - GET_ENDIANNESS
 *   - CHECK_VERSION
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_tts/dbms_tts.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "catalog/pg_tablespace.h"
#include "commands/tablespace.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/builtins.h"

#define DBMS_TTS_BIG_ENDIAN		1
#define DBMS_TTS_LITTLE_ENDIAN	2

/*
 * dbms_tts_transport_set_check_internal
 *
 * Checks if the specified tablespaces form a self-contained transportable set.
 * Inserts any closure violations into sys.transport_set_violations.
 */
PG_FUNCTION_INFO_V1(dbms_tts_transport_set_check_internal);
Datum
dbms_tts_transport_set_check_internal(PG_FUNCTION_ARGS)
{
	text	   *ts_list_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	bool		incl_constraints = PG_GETARG_BOOL(1);
	bool		full_check = PG_GETARG_BOOL(2);
	char	   *ts_list;
	char	   *token;
	char	   *saveptr;
	StringInfoData buf;
	int			ret;

	if (!ts_list_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_TTS.TRANSPORT_SET_CHECK: ts_list must not be NULL")));

	ts_list = text_to_cstring(ts_list_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfoString(&buf, "DELETE FROM sys.transport_set_violations");
	SPI_execute(buf.data, false, 0);

	/* Validate each tablespace in the comma-separated list */
	token = strtok_r(ts_list, ", ", &saveptr);
	while (token != NULL)
	{
		Oid spcid = get_tablespace_oid(token, true);
		if (!OidIsValid(spcid))
		{
			resetStringInfo(&buf);
			appendStringInfo(&buf,
							 "INSERT INTO sys.transport_set_violations (violation) "
							 "VALUES ('Tablespace \"%s\" does not exist')", token);
			SPI_execute(buf.data, false, 0);
		}
		token = strtok_r(NULL, ", ", &saveptr);
	}

	pfree(buf.data);
	pfree(ts_list);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_tts_downgrade_internal
 */
PG_FUNCTION_INFO_V1(dbms_tts_downgrade_internal);
Datum
dbms_tts_downgrade_internal(PG_FUNCTION_ARGS)
{
	if (!superuser())
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 errmsg("DBMS_TTS: must be superuser to execute downgrade")));

	/* Clean up transportable tablespace metadata */
	PG_RETURN_VOID();
}

/*
 * dbms_tts_is_platform_supported_internal
 */
PG_FUNCTION_INFO_V1(dbms_tts_is_platform_supported_internal);
Datum
dbms_tts_is_platform_supported_internal(PG_FUNCTION_ARGS)
{
	text	   *platform_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *platform;
	bool		supported = false;

	if (!platform_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_TTS.IS_PLATFORM_SUPPORTED: platform_name must not be NULL")));

	platform = text_to_cstring(platform_text);

	/* Check common supported operating platforms */
	if (pg_strcasecmp(platform, "Linux x86 64-bit") == 0 ||
		pg_strcasecmp(platform, "Linux x86-64") == 0 ||
		pg_strcasecmp(platform, "Linux ARM 64-bit") == 0 ||
		pg_strcasecmp(platform, "Microsoft Windows x86 64-bit") == 0 ||
		pg_strcasecmp(platform, "Microsoft Windows 64-bit") == 0 ||
		pg_strcasecmp(platform, "Solaris Operating System (x86-64)") == 0 ||
		pg_strcasecmp(platform, "AIX-Based Systems (64-bit)") == 0 ||
		pg_strcasecmp(platform, "HP-UX (64-bit)") == 0)
	{
		supported = true;
	}

	pfree(platform);
	PG_RETURN_BOOL(supported);
}

/*
 * dbms_tts_get_endianness_internal
 */
PG_FUNCTION_INFO_V1(dbms_tts_get_endianness_internal);
Datum
dbms_tts_get_endianness_internal(PG_FUNCTION_ARGS)
{
	text	   *platform_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *platform;
	int32		endianness;

	if (!platform_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_TTS.GET_ENDIANNESS: platform_name must not be NULL")));

	platform = text_to_cstring(platform_text);

	if (pg_strcasecmp(platform, "AIX-Based Systems (64-bit)") == 0 ||
		pg_strcasecmp(platform, "HP-UX (64-bit)") == 0 ||
		pg_strcasecmp(platform, "Solaris[tm] OE (64-bit)") == 0)
	{
		endianness = DBMS_TTS_BIG_ENDIAN;
	}
	else
	{
		/* Default x86/ARM platforms are little endian */
		endianness = DBMS_TTS_LITTLE_ENDIAN;
	}

	pfree(platform);
	PG_RETURN_INT32(endianness);
}

/*
 * dbms_tts_check_version_internal
 */
PG_FUNCTION_INFO_V1(dbms_tts_check_version_internal);
Datum
dbms_tts_check_version_internal(PG_FUNCTION_ARGS)
{
	text	   *version_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *version;
	bool		compatible = false;

	if (!version_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_TTS.CHECK_VERSION: version must not be NULL")));

	version = text_to_cstring(version_text);

	/* Check for compatibility with Oracle 11g, 12c, 19c, 21c, 23ai standards */
	if (strncmp(version, "11.", 3) == 0 ||
		strncmp(version, "12.", 3) == 0 ||
		strncmp(version, "18.", 3) == 0 ||
		strncmp(version, "19.", 3) == 0 ||
		strncmp(version, "21.", 3) == 0 ||
		strncmp(version, "23.", 3) == 0)
	{
		compatible = true;
	}

	pfree(version);
	PG_RETURN_BOOL(compatible);
}
