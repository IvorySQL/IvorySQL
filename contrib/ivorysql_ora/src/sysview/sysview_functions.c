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
#include "catalog/pg_type.h"
#include "fmgr.h"
#include "nodes/parsenodes.h"
#include "nodes/readfuncs.h"
#include "parser/scansup.h"
#include "partitioning/partdesc.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/ruleutils.h"
#include "utils/syscache.h"

PG_FUNCTION_INFO_V1(ora_case_trans);
PG_FUNCTION_INFO_V1(ora_partition_high_value);
PG_FUNCTION_INFO_V1(ora_partition_position);

static void strip_trailing_cast(char *expr);
static void append_partition_const(StringInfo buf, Node *value,
								   const char **separator);

/*
 * Transform identifier case based on IvorySQL settings.
 */
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
 * Strip trailing PostgreSQL explicit type cast (e.g., "::text", "::date")
 * from a deparsed expression string in place.
 */
static void
strip_trailing_cast(char *expr)
{
	int			len = strlen(expr);
	int			i;
	bool		in_quote = false;
	int			last_colon_colon = -1;

	for (i = 0; i < len; i++)
	{
		if (expr[i] == '\'')
		{
			if (in_quote && i + 1 < len && expr[i + 1] == '\'')
				i++;			/* skip escaped single quote */
			else
				in_quote = !in_quote;
		}
		else if (!in_quote && expr[i] == ':' && i + 1 < len && expr[i + 1] == ':')
		{
			last_colon_colon = i;
		}
	}

	if (last_colon_colon >= 0)
	{
		while (last_colon_colon > 0 && isspace((unsigned char) expr[last_colon_colon - 1]))
			last_colon_colon--;
		expr[last_colon_colon] = '\0';
	}
}

/*
 * Append a partition bound constant formatted for Oracle dictionary views
 * without PostgreSQL type casts (e.g. 'A' instead of 'A'::text).
 */
static void
append_partition_const(StringInfo buf, Node *value, const char **separator)
{
	char	   *deparsed;

	appendStringInfoString(buf, *separator);
	*separator = ", ";

	if (IsA(value, Const))
	{
		Const	   *con = (Const *) value;

		if (con->constisnull)
		{
			appendStringInfoString(buf, "NULL");
			return;
		}

		/*
		 * Numeric constants in Oracle partition bounds are exposed directly
		 * as numbers without quotes or PostgreSQL type casts.
		 */
		switch (con->consttype)
		{
			case INT2OID:
			case INT4OID:
			case INT8OID:
			case FLOAT4OID:
			case FLOAT8OID:
			case NUMERICOID:
			case OIDOID:
				{
					Oid			typoutput;
					bool		typIsVarlena;
					char	   *extval;

					getTypeOutputInfo(con->consttype, &typoutput, &typIsVarlena);
					extval = OidOutputFunctionCall(typoutput, con->constvalue);
					appendStringInfoString(buf, extval);
					pfree(extval);
					return;
				}
			default:
				break;
		}
	}

	deparsed = deparse_expression(value, NIL, false, false);
	strip_trailing_cast(deparsed);
	appendStringInfoString(buf, deparsed);
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

	/*
	 * Allow the parent lookup even if the partition is currently pending
	 * concurrent detach.
	 */
	parentid = get_partition_parent(relid, true);
	parent = table_open(parentid, AccessShareLock);

	/*
	 * Request a partition descriptor that includes pending-detach partitions
	 * so that the partition can still be resolved to its bound position.
	 */
	partdesc = RelationGetPartitionDesc(parent, false);

	if (partdesc)
	{
		for (i = 0; i < partdesc->nparts; i++)
		{
			if (partdesc->oids[i] == relid)
			{
				position = i + 1;
				break;
			}
		}
	}

	table_close(parent, AccessShareLock);

	if (position == 0)
		PG_RETURN_NULL();

	PG_RETURN_INT32(position);
}

