/*-------------------------------------------------------------------------
 *
 * oravarcharbyte.c
 *
 * Compatible with Oracle's VARCHAR2(n byte) data type.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/oravarcharbyte.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "access/hash.h"
#include "access/detoast.h"
#include "catalog/pg_collation.h"
#include "libpq/pqformat.h"
#include "nodes/nodeFuncs.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/ora_compatible.h"
#include "utils/sortsupport.h"
#include "utils/varlena.h"
#include "mb/pg_wchar.h"
#include "fmgr.h"

#define MaxVarcharSize 32767

PG_FUNCTION_INFO_V1(oravarcharbytein);
PG_FUNCTION_INFO_V1(oravarcharbyteout);
PG_FUNCTION_INFO_V1(oravarcharbyte);
PG_FUNCTION_INFO_V1(oravarcharbytetypmodin);
PG_FUNCTION_INFO_V1(oravarcharbytetypmodout);
PG_FUNCTION_INFO_V1(oravarcharbyterecv);
PG_FUNCTION_INFO_V1(oravarcharbytesend);
PG_FUNCTION_INFO_V1(btoravarcharbytesortsupport);
PG_FUNCTION_INFO_V1(btoravarcharbyte_pattern_sortsupport);

/*
 * varchar_input -- common guts of oravarcharbytein and oravarcharbyterecv
 *
 * "atttypmod" is measured in bytes
 *
 * Remove the Verify of extra spaces characters
 */
static VarChar *
varchar_input(const char *s, size_t len, int32 atttypmod)
{
	VarChar    *result;
	size_t		maxlen;
	
	maxlen = atttypmod - VARHDRSZ;

	if (atttypmod >= (int32) VARHDRSZ && len > maxlen)
	{
		ereport(ERROR,
				(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
				 errmsg("value too long for type varchar2(%d byte)",
				 (int) maxlen)));
	}

	result = (VarChar *) palloc(len + VARHDRSZ);
	SET_VARSIZE(result, len + VARHDRSZ);
	memcpy(VARDATA(result), s, len);
	return result;
}

static int32
anychar_typmodin(ArrayType *ta, const char *typename)
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
	if (*tl > MaxVarcharSize)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("length for type %s cannot exceed %d",
						typename, MaxVarcharSize)));

	/*
	 * For largely historical reasons, the typmod is VARHDRSZ plus the number
	 * of characters; there is enough client-side code that knows about that
	 * that we'd better not change it.
	 */
	typmod = VARHDRSZ + *tl;

	return typmod;
}

/* need modify */
static char *
anychar_typmodout(int32 typmod)
{
	char	   *res = (char *) palloc(69);

	if (typmod > VARHDRSZ)
	{
		if (nls_length_semantics == NLS_LENGTH_BYTE)
			snprintf(res, 64, "(%d)", (int) (typmod - VARHDRSZ));
		else	
			snprintf(res, 69, "(%d byte)", (int) (typmod - VARHDRSZ));
	}
	else
	{
		*res = '\0';
	}
	
	return res;
}

/*
 * Convert a C string to VARCHAR2 internal representation.
 * atttypmod is the declared length of the type plus VARHDRSZ.
 */
Datum
oravarcharbytein(PG_FUNCTION_ARGS)
{
	char	   *s = PG_GETARG_CSTRING(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		atttypmod = PG_GETARG_INT32(2);
	VarChar    *result;

	result = varchar_input(s, strlen(s), atttypmod);
	PG_RETURN_VARCHAR_P(result);
}

/*
 * Convert a VARCHAR2 value to a C string.
 *
 * Uses the text to C string conversion function, which is only appropriate
 * if VarChar and text are equivalent types.
 */
Datum
oravarcharbyteout(PG_FUNCTION_ARGS)
{
	Datum		txt = PG_GETARG_DATUM(0);

	PG_RETURN_CSTRING(TextDatumGetCString(txt));
}

/*
 *	oravarcharcharrecv	- converts external binary format to varchar2
 */
Datum
oravarcharbyterecv(PG_FUNCTION_ARGS)
{
	StringInfo	buf = (StringInfo) PG_GETARG_POINTER(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		atttypmod = PG_GETARG_INT32(2);
	VarChar    *result;
	char	   *str;
	int			nbytes;

	str = pq_getmsgtext(buf, buf->len - buf->cursor, &nbytes);
	result = varchar_input(str, nbytes, atttypmod);
	pfree(str);
	PG_RETURN_VARCHAR_P(result);
}

/*
 *	oravarcharcharsend	- converts varchar2 to binary format
 */
Datum
oravarcharbytesend(PG_FUNCTION_ARGS)
{
	/* Exactly the same as textsend, so share code */
	return textsend(fcinfo);
}

Datum
oravarcharbytetypmodin(PG_FUNCTION_ARGS)
{
	ArrayType  *ta = PG_GETARG_ARRAYTYPE_P(0);

	PG_RETURN_INT32(anychar_typmodin(ta, "varchar2"));
}

Datum
oravarcharbytetypmodout(PG_FUNCTION_ARGS)
{
	int32		typmod = PG_GETARG_INT32(0);

	PG_RETURN_CSTRING(anychar_typmodout(typmod));
}

/*
 * Converts a VARCHAR2 type to the specified size.
 *
 * maxlen is the typmod, ie, declared character length plus VARHDRSZ.
 * isExplicit is true if this is for an explicit cast to varchar2(N).
 *
 * Truncation rules: for an explicit cast, silently truncate to the given
 * length; for an implicit cast, raise error 
 *
 */
Datum
oravarcharbyte(PG_FUNCTION_ARGS)
{
	VarChar    *source = PG_GETARG_VARCHAR_PP(0);
	int32		typmod = PG_GETARG_INT32(1);
	bool		isExplicit = PG_GETARG_BOOL(2);
	VarChar    *result;
	int32		len,
				maxlen;
	char	   *s_data;

	len = VARSIZE_ANY_EXHDR(source);
	s_data = VARDATA_ANY(source);
	maxlen = typmod - VARHDRSZ;

	/* No work if typmod is invalid or supplied data fits it already */
	if (maxlen < 0 || len <= maxlen)
		PG_RETURN_VARCHAR_P(source);

	if (!isExplicit)
	{
		if (len > maxlen)
				ereport(ERROR,
						(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
					  errmsg("value too long for type varchar2(%d byte)",
							 maxlen)));
	}
	else
	{
		len = maxlen;
	}

	result = (VarChar *) palloc(len + VARHDRSZ);
	SET_VARSIZE(result, len + VARHDRSZ);
	memcpy(VARDATA(result), s_data, len);
	
	PG_RETURN_VARCHAR_P(result);
}

Datum
btoravarcharbytesortsupport(PG_FUNCTION_ARGS)
{
	SortSupport ssup = (SortSupport) PG_GETARG_POINTER(0);
	Oid			collid = ssup->ssup_collation;
	MemoryContext oldcontext;

	oldcontext = MemoryContextSwitchTo(ssup->ssup_cxt);

	/* Use generic string SortSupport */
	varstr_sortsupport(ssup, ORAVARCHARBYTEOID, collid);

	MemoryContextSwitchTo(oldcontext);

	PG_RETURN_VOID();
}

Datum
btoravarcharbyte_pattern_sortsupport(PG_FUNCTION_ARGS)
{
	SortSupport ssup = (SortSupport) PG_GETARG_POINTER(0);
	MemoryContext oldcontext;

	oldcontext = MemoryContextSwitchTo(ssup->ssup_cxt);

	/* Use generic string SortSupport, forcing "C" collation */
	varstr_sortsupport(ssup, ORAVARCHARBYTEOID, C_COLLATION_OID);

	MemoryContextSwitchTo(oldcontext);

	PG_RETURN_VOID();
}
