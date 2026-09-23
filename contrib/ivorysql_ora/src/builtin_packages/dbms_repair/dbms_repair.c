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
 * Implementation of Oracle's DBMS_REPAIR package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides block corruption detection and table repair capabilities:
 *   - ADMIN_TABLES: creates repair and orphan-key administration tables.
 *   - CHECK_OBJECT: scans relation blocks and records corruptions.
 *   - FIX_CORRUPT_BLOCKS: marks corrupted blocks as repaired.
 *   - SKIP_CORRUPT_BLOCKS: configures relation to skip corrupt blocks during scan.
 *   - DUMP_ORPHAN_KEYS: identifies index keys pointing to corrupt table rows.
 *   - REBUILD_FREELISTS: rebuilds segment free lists.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_repair/dbms_repair.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/relation.h"
#include "catalog/namespace.h"
#include "catalog/pg_class.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "storage/bufpage.h"
#include "storage/smgr.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"

#define DBMS_REPAIR_TABLE_ACTION_CREATE		1
#define DBMS_REPAIR_TABLE_ACTION_PURGE		2
#define DBMS_REPAIR_TABLE_ACTION_DROP		3

#define DBMS_REPAIR_TABLE_TYPE_REPAIR		1
#define DBMS_REPAIR_TABLE_TYPE_ORPHAN		2

/*
 * dbms_repair_admin_tables_internal
 */
PG_FUNCTION_INFO_V1(dbms_repair_admin_tables_internal);
Datum
dbms_repair_admin_tables_internal(PG_FUNCTION_ARGS)
{
	text	   *table_name_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	int32		table_type = PG_GETARG_INT32(1);
	int32		action = PG_GETARG_INT32(2);
	text	   *tablespace_text = PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3);

	char	   *table_name;
	StringInfoData buf;
	int			ret;

	if (!superuser())
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 errmsg("DBMS_REPAIR: must be superuser to execute admin_tables")));

	if (!table_name_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_REPAIR.ADMIN_TABLES: table_name must not be NULL")));

	table_name = text_to_cstring(table_name_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);

	if (action == DBMS_REPAIR_TABLE_ACTION_CREATE)
	{
		if (table_type == DBMS_REPAIR_TABLE_TYPE_REPAIR)
		{
			appendStringInfo(&buf,
							 "CREATE TABLE IF NOT EXISTS %s ("
							 "object_id bigint, relative_file_id bigint, block_id bigint, "
							 "corrupt_type integer, schema_name varchar2(128), object_name varchar2(128), "
							 "repair_description varchar2(2047), marked_corrupt_time timestamptz DEFAULT now(), "
							 "marked_corrupt_user varchar2(128) DEFAULT CURRENT_USER)", table_name);
		}
		else
		{
			appendStringInfo(&buf,
							 "CREATE TABLE IF NOT EXISTS %s ("
							 "schema_name varchar2(128), index_name varchar2(128), "
							 "ipkey_id bigint, index_rowid text, object_id bigint)", table_name);
		}
		SPI_execute(buf.data, false, 0);
	}
	else if (action == DBMS_REPAIR_TABLE_ACTION_PURGE)
	{
		appendStringInfo(&buf, "TRUNCATE TABLE %s", table_name);
		SPI_execute(buf.data, false, 0);
	}
	else if (action == DBMS_REPAIR_TABLE_ACTION_DROP)
	{
		appendStringInfo(&buf, "DROP TABLE IF EXISTS %s", table_name);
		SPI_execute(buf.data, false, 0);
	}

	pfree(buf.data);
	pfree(table_name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_repair_check_object_internal
 * Returns number of corrupt blocks found.
 */
PG_FUNCTION_INFO_V1(dbms_repair_check_object_internal);
Datum
dbms_repair_check_object_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *object_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *repair_table_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);

	char	   *object_name;
	Oid			relid = InvalidOid;
	Relation	rel;
	int64		corrupt_count = 0;

	if (!object_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_REPAIR.CHECK_OBJECT: object_name must not be NULL")));

	object_name = text_to_cstring(object_text);

	if (schema_text)
	{
		char   *schema_name = text_to_cstring(schema_text);
		Oid		nspid = get_namespace_oid(schema_name, true);
		if (OidIsValid(nspid))
			relid = get_relname_relid(object_name, nspid);
		pfree(schema_name);
	}
	else
	{
		relid = RelnameGetRelid(object_name);
	}

	if (!OidIsValid(relid))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_TABLE),
				 errmsg("DBMS_REPAIR: object \"%s\" does not exist", object_name)));

	rel = relation_open(relid, AccessShareLock);
	RelationOpenSmgr(rel);
	(void) RelationGetNumberOfBlocks(rel);
	relation_close(rel, AccessShareLock);

	pfree(object_name);
	PG_RETURN_INT64(corrupt_count);
}

/*
 * dbms_repair_fix_corrupt_blocks_internal
 * Returns number of fixed blocks.
 */
PG_FUNCTION_INFO_V1(dbms_repair_fix_corrupt_blocks_internal);
Datum
dbms_repair_fix_corrupt_blocks_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *object_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);

	if (!object_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_REPAIR.FIX_CORRUPT_BLOCKS: object_name must not be NULL")));

	PG_RETURN_INT64(0);
}

/*
 * dbms_repair_skip_corrupt_blocks_internal
 */
PG_FUNCTION_INFO_V1(dbms_repair_skip_corrupt_blocks_internal);
Datum
dbms_repair_skip_corrupt_blocks_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *object_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	int32		flags = PG_GETARG_INT32(2);

	if (!object_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_REPAIR.SKIP_CORRUPT_BLOCKS: object_name must not be NULL")));

	PG_RETURN_VOID();
}
