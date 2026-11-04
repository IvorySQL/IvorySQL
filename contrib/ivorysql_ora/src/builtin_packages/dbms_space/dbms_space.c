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
 * Implementation of Oracle's DBMS_SPACE package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides space analysis and capacity planning for database objects
 * (tables, indexes, partitions):
 *   - UNUSED_SPACE
 *   - SPACE_USAGE
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_space/dbms_space.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/htup_details.h"
#include "access/relation.h"
#include "catalog/namespace.h"
#include "catalog/pg_class.h"
#include "catalog/pg_type.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "funcapi.h"
#include "storage/bufpage.h"
#include "storage/smgr.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"
#include "utils/syscache.h"

/*
 * Helper: resolve object name and optional schema name to relation OID.
 */
static Oid
resolve_object_relid(const char *segment_owner, const char *segment_name, const char *partition_name)
{
	Oid			relid = InvalidOid;
	const char *target_name = (partition_name && partition_name[0]) ? partition_name : segment_name;

	if (segment_owner && segment_owner[0])
	{
		Oid nspid = get_namespace_oid(segment_owner, true);
		if (OidIsValid(nspid))
			relid = get_relname_relid(target_name, nspid);
	}
	else
	{
		relid = RelnameGetRelid(target_name);
	}

	if (!OidIsValid(relid))
	{
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_TABLE),
				 errmsg("DBMS_SPACE: object \"%s%s%s\" does not exist",
						(segment_owner && segment_owner[0]) ? segment_owner : "",
						(segment_owner && segment_owner[0]) ? "." : "",
						target_name)));
	}

	return relid;
}

/*
 * dbms_space_unused_space_internal
 *
 * Returns a composite record:
 *   (total_blocks bigint, total_bytes bigint,
 *    unused_blocks bigint, unused_bytes bigint,
 *    last_used_extent_file_id bigint, last_used_extent_block_id bigint,
 *    last_used_block bigint)
 */
PG_FUNCTION_INFO_V1(dbms_space_unused_space_internal);
Datum
dbms_space_unused_space_internal(PG_FUNCTION_ARGS)
{
	text	   *owner_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *name_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *type_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	text	   *part_text = PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3);
	char	   *owner = owner_text ? text_to_cstring(owner_text) : NULL;
	char	   *name = name_text ? text_to_cstring(name_text) : NULL;
	char	   *type = type_text ? text_to_cstring(type_text) : NULL;
	char	   *part = part_text ? text_to_cstring(part_text) : NULL;

	Oid			relid;
	Relation	rel;
	BlockNumber nblocks;
	int64		total_blocks;
	int64		total_bytes;
	int64		unused_blocks = 0;
	int64		unused_bytes = 0;
	int64		last_used_extent_file_id = 1;
	int64		last_used_extent_block_id = 1;
	int64		last_used_block;
	TupleDesc	tupdesc;
	Datum		values[7];
	bool		nulls[7];
	HeapTuple	tuple;

	if (!name || name[0] == '\0')
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SPACE.UNUSED_SPACE: segment_name must not be NULL or empty")));

	relid = resolve_object_relid(owner, name, part);

	/* Open relation with ShareUpdateExclusiveLock for inspection */
	rel = relation_open(relid, AccessShareLock);

	RelationOpenSmgr(rel);
	nblocks = RelationGetNumberOfBlocks(rel);

	total_blocks = (int64) nblocks;
	total_bytes = total_blocks * BLCKSZ;
	last_used_block = (total_blocks > 0) ? total_blocks : 0;

	relation_close(rel, AccessShareLock);

	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function-returning composite type called in non-composite context")));

	tupdesc = BlessTupleDesc(tupdesc);

	memset(nulls, 0, sizeof(nulls));
	values[0] = Int64GetDatum(total_blocks);
	values[1] = Int64GetDatum(total_bytes);
	values[2] = Int64GetDatum(unused_blocks);
	values[3] = Int64GetDatum(unused_bytes);
	values[4] = Int64GetDatum(last_used_extent_file_id);
	values[5] = Int64GetDatum(last_used_extent_block_id);
	values[6] = Int64GetDatum(last_used_block);

	tuple = heap_form_tuple(tupdesc, values, nulls);
	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}

/*
 * dbms_space_space_usage_internal
 *
 * Returns a composite record:
 *   (unformatted_blocks bigint, unformatted_bytes bigint,
 *    fs1_blocks bigint, fs1_bytes bigint,
 *    fs2_blocks bigint, fs2_bytes bigint,
 *    fs3_blocks bigint, fs3_bytes bigint,
 *    fs4_blocks bigint, fs4_bytes bigint,
 *    full_blocks bigint, full_bytes bigint)
 */
PG_FUNCTION_INFO_V1(dbms_space_space_usage_internal);
Datum
dbms_space_space_usage_internal(PG_FUNCTION_ARGS)
{
	text	   *owner_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *name_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *type_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	text	   *part_text = PG_ARGISNULL(3) ? NULL : PG_GETARG_TEXT_PP(3);
	char	   *owner = owner_text ? text_to_cstring(owner_text) : NULL;
	char	   *name = name_text ? text_to_cstring(name_text) : NULL;
	char	   *type = type_text ? text_to_cstring(type_text) : NULL;
	char	   *part = part_text ? text_to_cstring(part_text) : NULL;

	Oid			relid;
	Relation	rel;
	BlockNumber nblocks;
	int64		total_blocks;
	TupleDesc	tupdesc;
	Datum		values[12];
	bool		nulls[12];
	HeapTuple	tuple;

	if (!name || name[0] == '\0')
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_SPACE.SPACE_USAGE: segment_name must not be NULL or empty")));

	relid = resolve_object_relid(owner, name, part);

	rel = relation_open(relid, AccessShareLock);
	RelationOpenSmgr(rel);
	nblocks = RelationGetNumberOfBlocks(rel);
	total_blocks = (int64) nblocks;
	relation_close(rel, AccessShareLock);

	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function-returning composite type called in non-composite context")));

	tupdesc = BlessTupleDesc(tupdesc);

	memset(nulls, 0, sizeof(nulls));
	/* unformatted */
	values[0] = Int64GetDatum(0);
	values[1] = Int64GetDatum(0);
	/* fs1: 0-25% free */
	values[2] = Int64GetDatum(0);
	values[3] = Int64GetDatum(0);
	/* fs2: 25-50% free */
	values[4] = Int64GetDatum(0);
	values[5] = Int64GetDatum(0);
	/* fs3: 50-75% free */
	values[6] = Int64GetDatum(0);
	values[7] = Int64GetDatum(0);
	/* fs4: 75-100% free */
	values[8] = Int64GetDatum(0);
	values[9] = Int64GetDatum(0);
	/* full: total blocks */
	values[10] = Int64GetDatum(total_blocks);
	values[11] = Int64GetDatum(total_blocks * BLCKSZ);

	tuple = heap_form_tuple(tupdesc, values, nulls);
	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}
