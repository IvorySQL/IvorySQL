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
 * Implementation of Oracle's DBMS_RESOURCE_MANAGER package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides resource allocation, consumer group assignment, and workload plan
 * management:
 *   - CREATE_PENDING_AREA
 *   - VALIDATE_PENDING_AREA
 *   - SUBMIT_PENDING_AREA
 *   - CLEAR_PENDING_AREA
 *   - CREATE_PLAN
 *   - DELETE_PLAN
 *   - CREATE_CONSUMER_GROUP
 *   - DELETE_CONSUMER_GROUP
 *   - CREATE_PLAN_DIRECTIVE
 *   - DELETE_PLAN_DIRECTIVE
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_resource_manager/dbms_resource_manager.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/builtins.h"

static bool pending_area_active = false;

/*
 * dbms_resource_manager_create_pending_area_internal
 */
PG_FUNCTION_INFO_V1(dbms_resource_manager_create_pending_area_internal);
Datum
dbms_resource_manager_create_pending_area_internal(PG_FUNCTION_ARGS)
{
	pending_area_active = true;
	PG_RETURN_VOID();
}

/*
 * dbms_resource_manager_clear_pending_area_internal
 */
PG_FUNCTION_INFO_V1(dbms_resource_manager_clear_pending_area_internal);
Datum
dbms_resource_manager_clear_pending_area_internal(PG_FUNCTION_ARGS)
{
	pending_area_active = false;
	PG_RETURN_VOID();
}

/*
 * dbms_resource_manager_validate_pending_area_internal
 */
PG_FUNCTION_INFO_V1(dbms_resource_manager_validate_pending_area_internal);
Datum
dbms_resource_manager_validate_pending_area_internal(PG_FUNCTION_ARGS)
{
	if (!pending_area_active)
		ereport(ERROR,
				(errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
				 errmsg("DBMS_RESOURCE_MANAGER: pending area is not active")));

	PG_RETURN_VOID();
}

/*
 * dbms_resource_manager_submit_pending_area_internal
 */
PG_FUNCTION_INFO_V1(dbms_resource_manager_submit_pending_area_internal);
Datum
dbms_resource_manager_submit_pending_area_internal(PG_FUNCTION_ARGS)
{
	if (!pending_area_active)
		ereport(ERROR,
				(errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
				 errmsg("DBMS_RESOURCE_MANAGER: pending area is not active")));

	pending_area_active = false;
	PG_RETURN_VOID();
}

/*
 * dbms_resource_manager_create_plan_internal
 */
PG_FUNCTION_INFO_V1(dbms_resource_manager_create_plan_internal);
Datum
dbms_resource_manager_create_plan_internal(PG_FUNCTION_ARGS)
{
	text	   *plan_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *comment_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	int32		cpu_mth = PG_GETARG_INT32(2);
	int32		active_sess_pool_mth = PG_GETARG_INT32(3);
	int32		parallel_degree_limit_mth = PG_GETARG_INT32(4);
	int32		queueing_mth = PG_GETARG_INT32(5);
	char	   *plan_name;
	StringInfoData buf;
	int			ret;

	if (!plan_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_RESOURCE_MANAGER.CREATE_PLAN: plan must not be NULL")));

	plan_name = text_to_cstring(plan_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.resource_plans (plan, comments, num_plan_directives, status) "
					 "VALUES ('%s', '%s', 0, 'ACTIVE') "
					 "ON CONFLICT (plan) DO UPDATE SET comments = EXCLUDED.comments",
					 plan_name,
					 comment_text ? text_to_cstring(comment_text) : "");
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(plan_name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_resource_manager_delete_plan_internal
 */
PG_FUNCTION_INFO_V1(dbms_resource_manager_delete_plan_internal);
Datum
dbms_resource_manager_delete_plan_internal(PG_FUNCTION_ARGS)
{
	text	   *plan_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *plan_name;
	StringInfoData buf;
	int			ret;

	if (!plan_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_RESOURCE_MANAGER.DELETE_PLAN: plan must not be NULL")));

	plan_name = text_to_cstring(plan_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf, "DELETE FROM sys.resource_plan_directives WHERE plan = '%s'", plan_name);
	SPI_execute(buf.data, false, 0);

	resetStringInfo(&buf);
	appendStringInfo(&buf, "DELETE FROM sys.resource_plans WHERE plan = '%s'", plan_name);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(plan_name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_resource_manager_create_consumer_group_internal
 */
PG_FUNCTION_INFO_V1(dbms_resource_manager_create_consumer_group_internal);
Datum
dbms_resource_manager_create_consumer_group_internal(PG_FUNCTION_ARGS)
{
	text	   *group_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *comment_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	int32		cpu_mth = PG_GETARG_INT32(2);
	char	   *group_name;
	StringInfoData buf;
	int			ret;

	if (!group_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP: consumer_group must not be NULL")));

	group_name = text_to_cstring(group_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.resource_consumer_groups (consumer_group, comments, cpu_method, status) "
					 "VALUES ('%s', '%s', %d, 'ACTIVE') "
					 "ON CONFLICT (consumer_group) DO UPDATE SET comments = EXCLUDED.comments",
					 group_name,
					 comment_text ? text_to_cstring(comment_text) : "",
					 cpu_mth);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(group_name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_resource_manager_delete_consumer_group_internal
 */
PG_FUNCTION_INFO_V1(dbms_resource_manager_delete_consumer_group_internal);
Datum
dbms_resource_manager_delete_consumer_group_internal(PG_FUNCTION_ARGS)
{
	text	   *group_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *group_name;
	StringInfoData buf;
	int			ret;

	if (!group_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_RESOURCE_MANAGER.DELETE_CONSUMER_GROUP: consumer_group must not be NULL")));

	group_name = text_to_cstring(group_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf, "DELETE FROM sys.resource_consumer_groups WHERE consumer_group = '%s'", group_name);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(group_name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_resource_manager_create_plan_directive_internal
 */
PG_FUNCTION_INFO_V1(dbms_resource_manager_create_plan_directive_internal);
Datum
dbms_resource_manager_create_plan_directive_internal(PG_FUNCTION_ARGS)
{
	text	   *plan_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *group_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *comment_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	int32		cpu_p1 = PG_GETARG_INT32(3);
	int32		cpu_p2 = PG_GETARG_INT32(4);
	int32		active_sess_pool_limit = PG_GETARG_INT32(5);
	int32		queueing_time_limit = PG_GETARG_INT32(6);
	int32		parallel_degree_limit_p1 = PG_GETARG_INT32(7);
	char	   *plan_name;
	char	   *group_name;
	StringInfoData buf;
	int			ret;

	if (!plan_text || !group_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE: plan and group must not be NULL")));

	plan_name = text_to_cstring(plan_text);
	group_name = text_to_cstring(group_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.resource_plan_directives "
					 "(plan, group_or_subplan, is_subplan, cpu_p1, cpu_p2, active_sess_pool_limit, comments) "
					 "VALUES ('%s', '%s', false, %d, %d, %d, '%s') "
					 "ON CONFLICT (plan, group_or_subplan) DO UPDATE SET cpu_p1 = EXCLUDED.cpu_p1",
					 plan_name, group_name, cpu_p1, cpu_p2, active_sess_pool_limit,
					 comment_text ? text_to_cstring(comment_text) : "");
	SPI_execute(buf.data, false, 0);

	resetStringInfo(&buf);
	appendStringInfo(&buf, "UPDATE sys.resource_plans SET num_plan_directives = num_plan_directives + 1 WHERE plan = '%s'", plan_name);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(plan_name);
	pfree(group_name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_resource_manager_delete_plan_directive_internal
 */
PG_FUNCTION_INFO_V1(dbms_resource_manager_delete_plan_directive_internal);
Datum
dbms_resource_manager_delete_plan_directive_internal(PG_FUNCTION_ARGS)
{
	text	   *plan_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *group_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	char	   *plan_name;
	char	   *group_name;
	StringInfoData buf;
	int			ret;

	if (!plan_text || !group_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_RESOURCE_MANAGER.DELETE_PLAN_DIRECTIVE: plan and group must not be NULL")));

	plan_name = text_to_cstring(plan_text);
	group_name = text_to_cstring(group_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf, "DELETE FROM sys.resource_plan_directives WHERE plan = '%s' AND group_or_subplan = '%s'",
					 plan_name, group_name);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(plan_name);
	pfree(group_name);
	SPI_finish();

	PG_RETURN_VOID();
}
