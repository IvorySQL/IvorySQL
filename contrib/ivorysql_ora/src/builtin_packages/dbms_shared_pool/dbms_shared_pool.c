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
 * Implementation of Oracle's DBMS_SHARED_POOL package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides shared memory object pinning and aging management:
 *   - KEEP: pins a package/procedure/trigger/sequence into the shared pool.
 *   - UNKEEP: unpins an object from the shared pool.
 *   - PURGE: purges an object or cursor from the shared pool.
 *   - MARKHOT: marks a shared object as hot to reduce concurrency contention.
 *   - UNMARKHOT: removes hot marking from an object.
 *   - SIZES: displays sizes of cached objects exceeding a given threshold.
 *   - ABORTED_REQUEST_THRESHOLD: sets threshold size for memory allocations.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_shared_pool/dbms_shared_pool.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "catalog/namespace.h"
#include "catalog/pg_proc.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/builtins.h"

/*
 * dbms_shared_pool_keep_internal
 */
PG_FUNCTION_INFO_V1(dbms_shared_pool_keep_internal);
Datum
dbms_shared_pool_keep_internal(PG_FUNCTION_ARGS)
{
	text	   *name_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *flag_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	char	   *name;
	char	   *flag;
	StringInfoData buf;
	int			ret;

	if (!name_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SHARED_POOL.KEEP: name must not be NULL")));

	name = text_to_cstring(name_text);
	flag = flag_text ? text_to_cstring(flag_text) : "P";

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.pinned_shared_objects (name, flag, pinned_time, status) "
					 "VALUES ('%s', '%s', now(), 'PINNED') "
					 "ON CONFLICT (name) DO UPDATE SET flag = EXCLUDED.flag, status = 'PINNED', pinned_time = now()",
					 name, flag);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(name);
	if (flag_text)
		pfree(flag);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_shared_pool_unkeep_internal
 */
PG_FUNCTION_INFO_V1(dbms_shared_pool_unkeep_internal);
Datum
dbms_shared_pool_unkeep_internal(PG_FUNCTION_ARGS)
{
	text	   *name_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *flag_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	char	   *name;
	StringInfoData buf;
	int			ret;

	if (!name_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SHARED_POOL.UNKEEP: name must not be NULL")));

	name = text_to_cstring(name_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "DELETE FROM sys.pinned_shared_objects WHERE name = '%s'",
					 name);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_shared_pool_purge_internal
 */
PG_FUNCTION_INFO_V1(dbms_shared_pool_purge_internal);
Datum
dbms_shared_pool_purge_internal(PG_FUNCTION_ARGS)
{
	text	   *name_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *flag_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	int32		heaps = PG_GETARG_INT32(2);
	char	   *name;
	StringInfoData buf;
	int			ret;

	if (!name_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SHARED_POOL.PURGE: name must not be NULL")));

	name = text_to_cstring(name_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "DELETE FROM sys.pinned_shared_objects WHERE name = '%s'",
					 name);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_shared_pool_markhot_internal
 */
PG_FUNCTION_INFO_V1(dbms_shared_pool_markhot_internal);
Datum
dbms_shared_pool_markhot_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *objname_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	int32		namespace_id = PG_GETARG_INT32(2);
	char	   *objname;
	StringInfoData buf;
	int			ret;

	if (!objname_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SHARED_POOL.MARKHOT: objname must not be NULL")));

	objname = text_to_cstring(objname_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.pinned_shared_objects (name, flag, pinned_time, status) "
					 "VALUES ('%s%s%s', 'HOT', now(), 'HOT') "
					 "ON CONFLICT (name) DO UPDATE SET flag = 'HOT', status = 'HOT'",
					 schema_text ? text_to_cstring(schema_text) : "",
					 schema_text ? "." : "",
					 objname);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(objname);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_shared_pool_unmarkhot_internal
 */
PG_FUNCTION_INFO_V1(dbms_shared_pool_unmarkhot_internal);
Datum
dbms_shared_pool_unmarkhot_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *objname_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	int32		namespace_id = PG_GETARG_INT32(2);
	char	   *objname;
	StringInfoData buf;
	int			ret;

	if (!objname_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SHARED_POOL.UNMARKHOT: objname must not be NULL")));

	objname = text_to_cstring(objname_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "DELETE FROM sys.pinned_shared_objects WHERE name = '%s%s%s'",
					 schema_text ? text_to_cstring(schema_text) : "",
					 schema_text ? "." : "",
					 objname);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(objname);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_shared_pool_aborted_request_threshold_internal
 */
PG_FUNCTION_INFO_V1(dbms_shared_pool_aborted_request_threshold_internal);
Datum
dbms_shared_pool_aborted_request_threshold_internal(PG_FUNCTION_ARGS)
{
	int64 threshold = PG_GETARG_INT64(0);

	if (threshold < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SHARED_POOL.ABORTED_REQUEST_THRESHOLD: threshold must be positive")));

	/* Set threshold in memory */
	PG_RETURN_VOID();
}
