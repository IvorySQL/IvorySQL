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
 * Implementation of Oracle's DBMS_RLS package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides Row-Level Security (Virtual Private Database / Fine-Grained Access
 * Control) administration:
 *   - ADD_POLICY
 *   - DROP_POLICY
 *   - ENABLE_POLICY
 *   - REFRESH_POLICY
 *   - CREATE_POLICY_GROUP
 *   - DELETE_POLICY_GROUP
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_rls/dbms_rls.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "catalog/namespace.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/builtins.h"

#define DBMS_RLS_DYNAMIC			1
#define DBMS_RLS_STATIC				2
#define DBMS_RLS_SHARED_STATIC		3
#define DBMS_RLS_CONTEXT_SENSITIVE	4
#define DBMS_RLS_SHARED_CONTEXT_SENSITIVE 5

/*
 * dbms_rls_add_policy_internal
 */
PG_FUNCTION_INFO_V1(dbms_rls_add_policy_internal);
Datum
dbms_rls_add_policy_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *object_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *policy_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	text	   *func_schema_text = PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3);
	text	   *policy_func_text = PG_ARGISNULL(4) ? NULL : PG_GETARG_TEXT_PP(4);
	text	   *statement_types_text = PG_ARGISNULL(5) ? NULL : PG_GETARG_TEXT_PP(5);
	bool		update_check = PG_GETARG_BOOL(6);
	bool		enable = PG_GETARG_BOOL(7);
	bool		static_policy = PG_GETARG_BOOL(8);
	int32		policy_type = PG_GETARG_INT32(9);
	text	   *sec_relevant_cols_text = PG_ARGISNULL(10) ? NULL : PG_GETARG_TEXT_PP(10);
	int32		sec_relevant_cols_opt = PG_GETARG_INT32(11);

	char	   *object_name;
	char	   *policy_name;
	StringInfoData buf;
	int			ret;

	if (!object_text || !policy_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_RLS.ADD_POLICY: object_name and policy_name must not be NULL")));

	object_name = text_to_cstring(object_text);
	policy_name = text_to_cstring(policy_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.rls_policies "
					 "(object_owner, object_name, policy_name, function_owner, policy_function, "
					 " statement_types, update_check, enable, static_policy, policy_type, sec_relevant_cols, sec_relevant_cols_opt) "
					 "VALUES ('%s', '%s', '%s', '%s', '%s', '%s', %s, %s, %s, %d, '%s', %d) "
					 "ON CONFLICT (object_owner, object_name, policy_name) DO UPDATE "
					 "SET policy_function = EXCLUDED.policy_function, enable = EXCLUDED.enable",
					 schema_text ? text_to_cstring(schema_text) : "public",
					 object_name,
					 policy_name,
					 func_schema_text ? text_to_cstring(func_schema_text) : "public",
					 policy_func_text ? text_to_cstring(policy_func_text) : "",
					 statement_types_text ? text_to_cstring(statement_types_text) : "SELECT,INSERT,UPDATE,DELETE",
					 update_check ? "true" : "false",
					 enable ? "true" : "false",
					 static_policy ? "true" : "false",
					 policy_type,
					 sec_relevant_cols_text ? text_to_cstring(sec_relevant_cols_text) : "",
					 sec_relevant_cols_opt);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(object_name);
	pfree(policy_name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_rls_drop_policy_internal
 */
PG_FUNCTION_INFO_V1(dbms_rls_drop_policy_internal);
Datum
dbms_rls_drop_policy_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *object_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *policy_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	StringInfoData buf;
	int			ret;

	if (!object_text || !policy_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_RLS.DROP_POLICY: object_name and policy_name must not be NULL")));

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "DELETE FROM sys.rls_policies WHERE object_owner = '%s' AND object_name = '%s' AND policy_name = '%s'",
					 schema_text ? text_to_cstring(schema_text) : "public",
					 text_to_cstring(object_text),
					 text_to_cstring(policy_text));
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_rls_enable_policy_internal
 */
PG_FUNCTION_INFO_V1(dbms_rls_enable_policy_internal);
Datum
dbms_rls_enable_policy_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *object_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *policy_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	bool		enable = PG_GETARG_BOOL(3);
	StringInfoData buf;
	int			ret;

	if (!object_text || !policy_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_RLS.ENABLE_POLICY: object_name and policy_name must not be NULL")));

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "UPDATE sys.rls_policies SET enable = %s WHERE object_owner = '%s' AND object_name = '%s' AND policy_name = '%s'",
					 enable ? "true" : "false",
					 schema_text ? text_to_cstring(schema_text) : "public",
					 text_to_cstring(object_text),
					 text_to_cstring(policy_text));
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	SPI_finish();

	PG_RETURN_VOID();
}
