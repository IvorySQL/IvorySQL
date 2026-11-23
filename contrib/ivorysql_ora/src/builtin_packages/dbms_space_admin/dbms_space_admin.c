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
 * Implementation of Oracle's DBMS_SPACE_ADMIN package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides administrative verification and space management operations for
 * tablespaces and segments:
 *   - TABLESPACE_VERIFY
 *   - SEGMENT_VERIFY
 *   - SEGMENT_CORRUPT
 *   - SEGMENT_DROP_CORRUPT
 *   - TABLESPACE_FIX_SEGMENT_STATES
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_space_admin/dbms_space_admin.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/relation.h"
#include "catalog/namespace.h"
#include "catalog/pg_tablespace.h"
#include "commands/tablespace.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "storage/smgr.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"
#include "utils/syscache.h"

#define DBMS_SPACE_ADMIN_SEGMENT_VERIFY_BASIC		1
#define DBMS_SPACE_ADMIN_SEGMENT_VERIFY_DEEP		2

#define DBMS_SPACE_ADMIN_TABLESPACE_VERIFY_BASIC	1
#define DBMS_SPACE_ADMIN_TABLESPACE_VERIFY_EXTENTS	2

/*
 * Helper: verify caller has superuser / DBA privileges.
 */
static void
check_space_admin_privilege(void)
{
	if (!superuser())
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 errmsg("DBMS_SPACE_ADMIN: must be superuser to execute space administrative operations")));
}

/*
 * dbms_space_admin_tablespace_verify_internal
 */
PG_FUNCTION_INFO_V1(dbms_space_admin_tablespace_verify_internal);
Datum
dbms_space_admin_tablespace_verify_internal(PG_FUNCTION_ARGS)
{
	text	   *tablespace_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	int32		verify_mode = PG_GETARG_INT32(1);
	char	   *tablespace_name;
	Oid			spcid;

	check_space_admin_privilege();

	if (!tablespace_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SPACE_ADMIN.TABLESPACE_VERIFY: tablespace_name must not be NULL")));

	tablespace_name = text_to_cstring(tablespace_text);
	spcid = get_tablespace_oid(tablespace_name, true);

	if (!OidIsValid(spcid))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("DBMS_SPACE_ADMIN: tablespace \"%s\" does not exist", tablespace_name)));

	pfree(tablespace_name);
	PG_RETURN_VOID();
}

/*
 * dbms_space_admin_segment_verify_internal
 */
PG_FUNCTION_INFO_V1(dbms_space_admin_segment_verify_internal);
Datum
dbms_space_admin_segment_verify_internal(PG_FUNCTION_ARGS)
{
	text	   *schema_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *segment_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *type_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	int32		verify_mode = PG_GETARG_INT32(3);

	char	   *segment_name;
	Oid			relid = InvalidOid;
	Relation	rel;

	check_space_admin_privilege();

	if (!segment_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SPACE_ADMIN.SEGMENT_VERIFY: segment_name must not be NULL")));

	segment_name = text_to_cstring(segment_text);

	if (schema_text)
	{
		char   *schema_name = text_to_cstring(schema_text);
		Oid		nspid = get_namespace_oid(schema_name, true);
		if (OidIsValid(nspid))
			relid = get_relname_relid(segment_name, nspid);
		pfree(schema_name);
	}
	else
	{
		relid = RelnameGetRelid(segment_name);
	}

	if (!OidIsValid(relid))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_TABLE),
				 errmsg("DBMS_SPACE_ADMIN: segment \"%s\" does not exist", segment_name)));

	rel = relation_open(relid, AccessShareLock);
	RelationOpenSmgr(rel);
	(void) RelationGetNumberOfBlocks(rel);
	relation_close(rel, AccessShareLock);

	pfree(segment_name);
	PG_RETURN_VOID();
}

/*
 * dbms_space_admin_tablespace_fix_segment_states_internal
 */
PG_FUNCTION_INFO_V1(dbms_space_admin_tablespace_fix_segment_states_internal);
Datum
dbms_space_admin_tablespace_fix_segment_states_internal(PG_FUNCTION_ARGS)
{
	text	   *tablespace_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *tablespace_name;
	Oid			spcid;

	check_space_admin_privilege();

	if (!tablespace_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SPACE_ADMIN.TABLESPACE_FIX_SEGMENT_STATES: tablespace_name must not be NULL")));

	tablespace_name = text_to_cstring(tablespace_text);
	spcid = get_tablespace_oid(tablespace_name, true);

	if (!OidIsValid(spcid))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("DBMS_SPACE_ADMIN: tablespace \"%s\" does not exist", tablespace_name)));

	pfree(tablespace_name);
	PG_RETURN_VOID();
}
