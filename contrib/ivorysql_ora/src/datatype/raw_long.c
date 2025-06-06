/*-------------------------------------------------------------------------
 *
 * raw_long.c
 *
 * Auxiliary routine for compatible with Oracle's LONG RAW data type.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/raw_long.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/hash.h"
#include "access/detoast.h"
#include "libpq/pqformat.h"
#include "nodes/nodeFuncs.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/varlena.h"
#include "mb/pg_wchar.h"
#include "fmgr.h"

#include "../include/common_datatypes.h"

#define MaxCharSize 32767

PG_FUNCTION_INFO_V1(oralongtypmodin);	
PG_FUNCTION_INFO_V1(oralongtypmodout);
PG_FUNCTION_INFO_V1(orarawtypmodin);
PG_FUNCTION_INFO_V1(orarawtypmodout);
PG_FUNCTION_INFO_V1(orabytea_to_raw_with_typmod);
PG_FUNCTION_INFO_V1(orachar_to_long_with_typmod);

static int32 longraw_typmodin(ArrayType *ta, const char *typename);
static char* longraw_typmodout(int32 typmod);

/*
 * LONG
 */
Datum
oralongtypmodin(PG_FUNCTION_ARGS)
{
	ArrayType  *ta = PG_GETARG_ARRAYTYPE_P(0);

	PG_RETURN_INT32(longraw_typmodin(ta, "long"));
}

Datum
oralongtypmodout(PG_FUNCTION_ARGS)
{
	int32		typmod = PG_GETARG_INT32(0);

	PG_RETURN_CSTRING(longraw_typmodout(typmod));
}

/*
 * RAW
 */
Datum
orarawtypmodin(PG_FUNCTION_ARGS)
{
	ArrayType  *ta = PG_GETARG_ARRAYTYPE_P(0);

	PG_RETURN_INT32(longraw_typmodin(ta, "raw"));
}

Datum
orarawtypmodout(PG_FUNCTION_ARGS)
{
	int32		typmod = PG_GETARG_INT32(0);

	PG_RETURN_CSTRING(longraw_typmodout(typmod));
}

/* A copy of the anychar_typmodin function, modified to longraw_typmodin */
static int32
longraw_typmodin(ArrayType *ta, const char *typename)
{
	int32		typmod;
	int32	   *tl;
	int			n;

	tl = ArrayGetIntegerTypmods(ta, &n);

	if (n != 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("invalid type modifier")));

	if (*tl < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("length for type %s must be at least 1", typename)));

	if (*tl > MaxCharSize)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("length for type %s cannot exceed %d",
						typename, MaxCharSize)));

	/*
	 * For largely historical reasons, the typmod is VARHDRSZ plus the number
	 * of characters; there is enough client-side code that knows about that
	 * that we'd better not change it.
	 */
	typmod = VARHDRSZ + *tl;

	return typmod;
}

static char*
longraw_typmodout(int32 typmod)
{
	char *res = (char*)palloc(64);

	if (typmod > VARHDRSZ)
		snprintf(res, 64, "(%d)", (int)(typmod - VARHDRSZ));
	else
		*res = '\0';
	return res;
}

Datum
orabytea_to_raw_with_typmod(PG_FUNCTION_ARGS)
{
	bytea	   *source = PG_GETARG_BYTEA_P(0);
	int32		maxlen = PG_GETARG_INT32(1);
	bool		isExplicit = PG_GETARG_BOOL(2);
	BpChar	   *result;
	int32		len;
	char	   *r;
	char	   *s;

	/* No work if typmod is invalid */
	if (maxlen < (int32) VARHDRSZ)
		PG_RETURN_BYTEA_P(source);

	maxlen -= VARHDRSZ;

	len = VARSIZE_ANY_EXHDR(source);
	s = VARDATA_ANY(source);

	/* No work if supplied data matches typmod already */
	if (len == maxlen)
		PG_RETURN_BYTEA_P(source);

	/*
	 * Report error for implicit conversion
	 * Truncate string for exlicit conversion
	 */
	if (len > maxlen)
	{
		if (!isExplicit)
			ereport(ERROR,
					(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
					 errmsg("value too long for type raw(%d)",
							maxlen)));
		len = maxlen;	
	}

	Assert(maxlen >= len);

	result = palloc(len + VARHDRSZ);
	SET_VARSIZE(result, len + VARHDRSZ);
	r = VARDATA(result);

	memcpy(r, s, len);

	PG_RETURN_BYTEA_P(result);
}

Datum
orachar_to_long_with_typmod(PG_FUNCTION_ARGS)
{
	text	   *source = PG_GETARG_TEXT_P(0);
	int32		maxlen = PG_GETARG_INT32(1);
	bool		isExplicit = PG_GETARG_BOOL(2);
	BpChar	   *result;
	int32		len;
	char	   *r;
	char	   *s;

	/* No work if typmod is invalid */
	if (maxlen < (int32) VARHDRSZ)
		PG_RETURN_TEXT_P(source);

	maxlen -= VARHDRSZ;

	len = VARSIZE_ANY_EXHDR(source);
	s = VARDATA_ANY(source);

	/* No work if supplied data matches typmod already */
	if (len == maxlen)
		PG_RETURN_TEXT_P(source);

	/*
	 * Report error for implicit conversion 
	 * Truncate string for exlicit conversion 
	 */
	if (len > maxlen)
	{
		if (!isExplicit)
			ereport(ERROR,
					(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
					 errmsg("value too long for type long(%d)",
							maxlen)));
		len = maxlen;	
	}

	Assert(maxlen >= len);

	result = palloc(len + VARHDRSZ);
	SET_VARSIZE(result, len + VARHDRSZ);
	r = VARDATA(result);

	memcpy(r, s, len);

	PG_RETURN_TEXT_P(result);
}
