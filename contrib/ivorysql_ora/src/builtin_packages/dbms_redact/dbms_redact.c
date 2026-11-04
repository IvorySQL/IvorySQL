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
 * Implementation of Oracle's DBMS_REDACT package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides data redaction policy administration and masking:
 *   - ADD_POLICY
 *   - DROP_POLICY
 *   - ENABLE_POLICY
 *   - DISABLE_POLICY
 *   - ALTER_POLICY
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_redact/dbms_redact.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "catalog/namespace.h"
#include "commands/dbcommands.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "utils/builtins.h"

#define DBMS_REDACT_FULL				1
#define DBMS_REDACT_PARTIAL				2
#define DBMS_REDACT_RANDOM				3
#define DBMS_REDACT_NONE				4
#define DBMS_REDACT_REGEXP				5

/*
 * dbms_redact_add_policy_internal
 */
PG_FUNCTION_INFO_V1(dbms_redact_add_policy_internal);
Datum
dbms_redact_add_policy_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *object_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *policy_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	text	   *expression_text = PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3);
	int32		function_type = PG_GETARG_INT32(4);
	text	   *column_text = PG_ARGISNULL(5) ? NULL : PG_GETARG_TEXT_PP(5);
	text	   *parameters_text = PG_ARGISNULL(6) ? NULL : PG_GETARG_TEXT_PP(6);
	text	   *description_text = PG_ARGISNULL(7) ? NULL : PG_GETARG_TEXT_PP(7);
	bool		enable = PG_GETARG_BOOL(8);

	char	   *object_name;
	char	   *policy_name;
	char	   *column_name;
	StringInfoData buf;
	int			ret;

	if (!object_text || !policy_text || !column_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_REDACT: object_name, policy_name, and column_name must not be NULL")));

	object_name = text_to_cstring(object_text);
	policy_name = text_to_cstring(policy_text);
	column_name = text_to_cstring(column_text);

	if (function_type < 1 || function_type > 5)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_REDACT: invalid function_type: %d (expected 1-5)", function_type)));

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.redaction_policies "
					 "(object_owner, object_name, policy_name, expression, enable, policy_description) "
					 "VALUES ('%s', '%s', '%s', '%s', %s, '%s') "
					 "ON CONFLICT (object_owner, object_name, policy_name) DO UPDATE "
					 "SET expression = EXCLUDED.expression, enable = EXCLUDED.enable",
					 schema_text ? text_to_cstring(schema_text) : "public",
					 object_name,
					 policy_name,
					 expression_text ? text_to_cstring(expression_text) : "1=1",
					 enable ? "true" : "false",
					 description_text ? text_to_cstring(description_text) : "");
	SPI_execute(buf.data, false, 0);

	resetStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.redaction_columns "
					 "(object_owner, object_name, policy_name, column_name, function_type, function_parameters) "
					 "VALUES ('%s', '%s', '%s', '%s', %d, '%s')",
					 schema_text ? text_to_cstring(schema_text) : "public",
					 object_name,
					 policy_name,
					 column_name,
					 function_type,
					 parameters_text ? text_to_cstring(parameters_text) : "");
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_redact_drop_policy_internal
 */
PG_FUNCTION_INFO_V1(dbms_redact_drop_policy_internal);
Datum
dbms_redact_drop_policy_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *object_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *policy_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	StringInfoData buf;
	int			ret;

	if (!object_text || !policy_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_REDACT: object_name and policy_name must not be NULL")));

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "DELETE FROM sys.redaction_columns WHERE object_owner = '%s' AND object_name = '%s' AND policy_name = '%s'",
					 schema_text ? text_to_cstring(schema_text) : "public",
					 text_to_cstring(object_text),
					 text_to_cstring(policy_text));
	SPI_execute(buf.data, false, 0);

	resetStringInfo(&buf);
	appendStringInfo(&buf,
					 "DELETE FROM sys.redaction_policies WHERE object_owner = '%s' AND object_name = '%s' AND policy_name = '%s'",
					 schema_text ? text_to_cstring(schema_text) : "public",
					 text_to_cstring(object_text),
					 text_to_cstring(policy_text));
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_redact_enable_policy_internal
 */
PG_FUNCTION_INFO_V1(dbms_redact_enable_policy_internal);
Datum
dbms_redact_enable_policy_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *object_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *policy_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	StringInfoData buf;
	int			ret;

	if (!object_text || !policy_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_REDACT: object_name and policy_name must not be NULL")));

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "UPDATE sys.redaction_policies SET enable = true "
					 "WHERE object_owner = '%s' AND object_name = '%s' AND policy_name = '%s'",
					 schema_text ? text_to_cstring(schema_text) : "public",
					 text_to_cstring(object_text),
					 text_to_cstring(policy_text));
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_redact_disable_policy_internal
 */
PG_FUNCTION_INFO_V1(dbms_redact_disable_policy_internal);
Datum
dbms_redact_disable_policy_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *object_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *policy_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	StringInfoData buf;
	int			ret;

	if (!object_text || !policy_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_REDACT: object_name and policy_name must not be NULL")));

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "UPDATE sys.redaction_policies SET enable = false "
					 "WHERE object_owner = '%s' AND object_name = '%s' AND policy_name = '%s'",
					 schema_text ? text_to_cstring(schema_text) : "public",
					 text_to_cstring(object_text),
					 text_to_cstring(policy_text));
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	SPI_finish();

	PG_RETURN_VOID();
}
