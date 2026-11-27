/*-------------------------------------------------------------------------
 *
 * number.c
 *    Output support for Oracle's NUMBER data type.
 *
 * Copyright (c) 2026, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *    contrib/ivorysql_ora/src/datatype/number.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "fmgr.h"
#include "utils/fmgrprotos.h"

PG_FUNCTION_INFO_V1(ora_number_out);

/*
 * NUMBER's scale constrains input rounding, but should not force trailing
 * fractional zeros in its default text representation.  Normalize a copy for
 * output so the stored value, typmod and PostgreSQL numeric output are intact.
 * numeric_trim_scale also preserves the existing handling of special values.
 */
Datum
ora_number_out(PG_FUNCTION_ARGS)
{
	Datum		normalized;
	char	   *result;

	normalized = DirectFunctionCall1(numeric_trim_scale, PG_GETARG_DATUM(0));
	result = DatumGetCString(DirectFunctionCall1(numeric_out, normalized));
	pfree(DatumGetPointer(normalized));

	PG_RETURN_CSTRING(result);
}
