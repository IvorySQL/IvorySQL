/*-------------------------------------------------------------------------
 *
 * pg_logicalinspect.c
 *		  Functions to inspect contents of PostgreSQL logical snapshots
 *
 * Copyright (c) 2024, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *		  contrib/pg_logicalinspect/pg_logicalinspect.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "funcapi.h"
#include "replication/snapbuild_internal.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/pg_lsn.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(pg_get_logical_snapshot_meta);
PG_FUNCTION_INFO_V1(pg_get_logical_snapshot_info);

/* Return the description of SnapBuildState */
static const char *
get_snapbuild_state_desc(SnapBuildState state)
{
	const char *stateDesc = "unknown state";

	switch (state)
	{
		case SNAPBUILD_START:
			stateDesc = "start";
			break;
		case SNAPBUILD_BUILDING_SNAPSHOT:
			stateDesc = "building";
			break;
		case SNAPBUILD_FULL_SNAPSHOT:
			stateDesc = "full";
			break;
		case SNAPBUILD_CONSISTENT:
			stateDesc = "consistent";
			break;
	}

	return stateDesc;
}

/*
 * Retrieve the logical snapshot file metadata.
 */
Datum
pg_get_logical_snapshot_meta(PG_FUNCTION_ARGS)
{
#define PG_GET_LOGICAL_SNAPSHOT_META_COLS 3
	SnapBuildOnDisk ondisk;
	HeapTuple	tuple;
	Datum		values[PG_GET_LOGICAL_SNAPSHOT_META_COLS] = {0};
	bool		nulls[PG_GET_LOGICAL_SNAPSHOT_META_COLS] = {0};
	TupleDesc	tupdesc;
	char		path[MAXPGPATH];
	int			i = 0;
	text	   *filename_t = PG_GETARG_TEXT_PP(0);

	/* Build a tuple descriptor for our result type */
	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		elog(ERROR, "return type must be a row type");

	sprintf(path, "%s/%s",
			PG_LOGICAL_SNAPSHOTS_DIR,
			text_to_cstring(filename_t));

	/* Validate and restore the snapshot to 'ondisk' */
	SnapBuildRestoreSnapshot(&ondisk, path, CurrentMemoryContext, false);

	values[i++] = UInt32GetDatum(ondisk.magic);
	values[i++] = Int64GetDatum((int64) ondisk.checksum);
	values[i++] = UInt32GetDatum(ondisk.version);

	Assert(i == PG_GET_LOGICAL_SNAPSHOT_META_COLS);

	tuple = heap_form_tuple(tupdesc, values, nulls);

	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));

#undef PG_GET_LOGICAL_SNAPSHOT_META_COLS
}

Datum
pg_get_logical_snapshot_info(PG_FUNCTION_ARGS)
{
#define PG_GET_LOGICAL_SNAPSHOT_INFO_COLS 14
	SnapBuildOnDisk ondisk;
	HeapTuple	tuple;
	Datum		values[PG_GET_LOGICAL_SNAPSHOT_INFO_COLS] = {0};
	bool		nulls[PG_GET_LOGICAL_SNAPSHOT_INFO_COLS] = {0};
	TupleDesc	tupdesc;
	char		path[MAXPGPATH];
	int			i = 0;
	text	   *filename_t = PG_GETARG_TEXT_PP(0);

	/* Build a tuple descriptor for our result type */
	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		elog(ERROR, "return type must be a row type");

	sprintf(path, "%s/%s",
			PG_LOGICAL_SNAPSHOTS_DIR,
			text_to_cstring(filename_t));

	/* Validate and restore the snapshot to 'ondisk' */
	SnapBuildRestoreSnapshot(&ondisk, path, CurrentMemoryContext, false);

	values[i++] = CStringGetTextDatum(get_snapbuild_state_desc(ondisk.builder.state));
	values[i++] = TransactionIdGetDatum(ondisk.builder.xmin);
	values[i++] = TransactionIdGetDatum(ondisk.builder.xmax);
	values[i++] = LSNGetDatum(ondisk.builder.start_decoding_at);
	values[i++] = LSNGetDatum(ondisk.builder.two_phase_at);
	values[i++] = TransactionIdGetDatum(ondisk.builder.initial_xmin_horizon);
	values[i++] = BoolGetDatum(ondisk.builder.building_full_snapshot);
	values[i++] = BoolGetDatum(ondisk.builder.in_slot_creation);
	values[i++] = LSNGetDatum(ondisk.builder.last_serialized_snapshot);
	values[i++] = TransactionIdGetDatum(ondisk.builder.next_phase_at);

	values[i++] = UInt32GetDatum(ondisk.builder.committed.xcnt);
	if (ondisk.builder.committed.xcnt > 0)
	{
		Datum	   *arrayelems;

		arrayelems = (Datum *) palloc(ondisk.builder.committed.xcnt * sizeof(Datum));

		for (int j = 0; j < ondisk.builder.committed.xcnt; j++)
			arrayelems[j] = TransactionIdGetDatum(ondisk.builder.committed.xip[j]);

		values[i++] = PointerGetDatum(construct_array_builtin(arrayelems,
															  ondisk.builder.committed.xcnt,
															  XIDOID));
	}
	else
		nulls[i++] = true;

	values[i++] = UInt32GetDatum(ondisk.builder.catchange.xcnt);
	if (ondisk.builder.catchange.xcnt > 0)
	{
		Datum	   *arrayelems;

		arrayelems = (Datum *) palloc(ondisk.builder.catchange.xcnt * sizeof(Datum));

		for (int j = 0; j < ondisk.builder.catchange.xcnt; j++)
			arrayelems[j] = TransactionIdGetDatum(ondisk.builder.catchange.xip[j]);

		values[i++] = PointerGetDatum(construct_array_builtin(arrayelems,
															  ondisk.builder.catchange.xcnt,
															  XIDOID));
	}
	else
		nulls[i++] = true;

	Assert(i == PG_GET_LOGICAL_SNAPSHOT_INFO_COLS);

	tuple = heap_form_tuple(tupdesc, values, nulls);

	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));

#undef PG_GET_LOGICAL_SNAPSHOT_INFO_COLS
}
