/*------------------------------------------------------------------
 * Copyright 2025 IvorySQL Global Development Team
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
 * File: sysview_functions.c
 *
 * Abstract: 
 * 		Function which converts all-uppercase text to all-lowercase text 
 * 		and vice versa.
 *
 * Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * Identification:
 *		contrib/ivorysql_ora/src/sysview/sysview_functions.c
 *
 *------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/table.h"
#include "catalog/partition.h"
#include "catalog/pg_class.h"
#include "fmgr.h"
#include "nodes/parsenodes.h"
#include "nodes/readfuncs.h"
#include "parser/scansup.h"
#include "partitioning/partdesc.h"
#include "utils/builtins.h"
#include "utils/ruleutils.h"
#include "utils/syscache.h"

PG_FUNCTION_INFO_V1(ora_case_trans);
PG_FUNCTION_INFO_V1(ora_partition_high_value);
PG_FUNCTION_INFO_V1(ora_partition_position);

static void append_partition_const(StringInfo buf, Node *value,
								   const char **separator);

Datum
ora_case_trans(PG_FUNCTION_ARGS)
{
	char	*string;
	char	*retval;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	string = (char *) TextDatumGetCString(PG_GETARG_DATUM(0));

	retval = identifier_case_transform(string, strlen(string));

	PG_RETURN_TEXT_P(cstring_to_text(retval));
}

/*
 * Append a partition bound constant using PostgreSQL's expression deparser.
 * Reading the stored PartitionBoundSpec avoids depending on the textual
 * format produced by pg_get_expr().
 */
static void
append_partition_const(StringInfo buf, Node *value, const char **separator)
{
	char	   *deparsed;

	deparsed = deparse_expression(value, NIL, false, false);
	appendStringInfoString(buf, *separator);
	appendStringInfoString(buf, deparsed);
	*separator = ", ";
}

/*
 * Return the Oracle-style HIGH_VALUE for a table partition.
 *
 * RANGE partitions expose their upper bound, LIST partitions expose their
 * value list, and HASH partitions return NULL because they have no high
 * bound.  DEFAULT partitions are represented by Oracle's DEFAULT keyword.
 */
Datum
ora_partition_high_value(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	HeapTuple	tuple;
	Datum		bound_datum;
	bool		isnull;
	PartitionBoundSpec *spec;
	StringInfoData buf;
	const char *separator = "";
	ListCell   *cell;

	tuple = SearchSysCache1(RELOID, ObjectIdGetDatum(relid));
	if (!HeapTupleIsValid(tuple))
		PG_RETURN_NULL();

	bound_datum = SysCacheGetAttr(RELOID, tuple,
								 Anum_pg_class_relpartbound, &isnull);
	if (isnull)
	{
		ReleaseSysCache(tuple);
		PG_RETURN_NULL();
	}

	spec = castNode(PartitionBoundSpec,
					stringToNode(TextDatumGetCString(bound_datum)));
	ReleaseSysCache(tuple);

	if (spec->is_default)
		PG_RETURN_TEXT_P(cstring_to_text("DEFAULT"));

	if (spec->strategy == PARTITION_STRATEGY_HASH)
		PG_RETURN_NULL();

	initStringInfo(&buf);

	if (spec->strategy == PARTITION_STRATEGY_LIST)
	{
		foreach(cell, spec->listdatums)
			append_partition_const(&buf, (Node *) lfirst(cell), &separator);
	}
	else if (spec->strategy == PARTITION_STRATEGY_RANGE)
	{
		foreach(cell, spec->upperdatums)
		{
			PartitionRangeDatum *datum =
				lfirst_node(PartitionRangeDatum, cell);

			if (datum->kind == PARTITION_RANGE_DATUM_VALUE)
				append_partition_const(&buf, datum->value, &separator);
			else
			{
				appendStringInfoString(&buf, separator);
				if (datum->kind == PARTITION_RANGE_DATUM_MINVALUE)
					appendStringInfoString(&buf, "MINVALUE");
				else
					appendStringInfoString(&buf, "MAXVALUE");
				separator = ", ";
			}
		}
	}
	else
		elog(ERROR, "unrecognized partition strategy: %d",
			 (int) spec->strategy);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

/*
 * Return a partition's one-based position in its immediate parent's
 * canonical bound order.
 */
Datum
ora_partition_position(PG_FUNCTION_ARGS)
{
	Oid			relid = PG_GETARG_OID(0);
	Oid			parentid;
	Relation	parent;
	PartitionDesc partdesc;
	int			position = 0;
	int			i;

	parentid = get_partition_parent(relid, false);
	parent = table_open(parentid, AccessShareLock);
	partdesc = RelationGetPartitionDesc(parent, true);

	for (i = 0; i < partdesc->nparts; i++)
	{
		if (partdesc->oids[i] == relid)
		{
			position = i + 1;
			break;
		}
	}

	table_close(parent, AccessShareLock);

	if (position == 0)
		PG_RETURN_NULL();

	PG_RETURN_INT32(position);
}

