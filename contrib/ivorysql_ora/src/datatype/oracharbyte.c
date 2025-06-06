/*-------------------------------------------------------------------------
 *
 * oracharbyte.c
 *
 * Compatible with Oracle's CHAR(n byte) data type.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/oracharbyte.c
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
#include "utils/ora_compatible.h"
#include "utils/varlena.h"
#include "mb/pg_wchar.h"
#include "fmgr.h"

#define MaxCharSize 32767

PG_FUNCTION_INFO_V1(oracharbytein);
PG_FUNCTION_INFO_V1(oracharbyteout);
PG_FUNCTION_INFO_V1(oracharbyterecv);
PG_FUNCTION_INFO_V1(oracharbytesend);
PG_FUNCTION_INFO_V1(oracharbyte);
PG_FUNCTION_INFO_V1(oracharbytetypmodin);
PG_FUNCTION_INFO_V1(oracharbytetypmodout);
PG_FUNCTION_INFO_V1(oracharbyteeq);
PG_FUNCTION_INFO_V1(oracharbytene);
PG_FUNCTION_INFO_V1(oracharbytegt);
PG_FUNCTION_INFO_V1(oracharbytege);
PG_FUNCTION_INFO_V1(oracharbytelt);
PG_FUNCTION_INFO_V1(oracharbytele);
PG_FUNCTION_INFO_V1(oracharbytecmp);
PG_FUNCTION_INFO_V1(oracharbyte_sortsupport);
PG_FUNCTION_INFO_V1(oracharbyte_larger);
PG_FUNCTION_INFO_V1(oracharbyte_smaller);
PG_FUNCTION_INFO_V1(oracharbytehash);

/*******************************************************************
 * bpchar_input -- common guts of oracharbytein and oracharbyterecv
 *
 * s is the input text of length len (may not be null-terminated)
 * atttypmod is the typmod value to apply
 *
 * Note that atttypmod is measured in bytes
 *
 ******************************************************************/
static BpChar *
bpchar_input(const char *s, size_t len, int32 atttypmod)
{
	BpChar	   *result;
	char	   *r;
	size_t		maxlen;

	/* If typmod is -1 (or invalid), use the actual string length */
	if (atttypmod < (int32) VARHDRSZ)
		maxlen = len;
	else
	{
		maxlen = atttypmod - VARHDRSZ;
		if (len > maxlen)
		{
			ereport(ERROR,
					(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
					 errmsg("value too long for type char(%d byte)",
							(int) maxlen)));
		}
	}

	result = (BpChar *) palloc(maxlen + VARHDRSZ);
	SET_VARSIZE(result, maxlen + VARHDRSZ);
	r = VARDATA(result);
	memcpy(r, s, len);

	/* blank pad the string if necessary */
	if (maxlen > len)
		memset(r + len, ' ', maxlen - len);

	return result;
}

/****************************************************************
 * 
 * common code for oracharbytetypmodin
 *
 ****************************************************************/
static int32
anychar_typmodin(ArrayType *ta, const char *typename)
{
	int32		typmod;
	int32	   *tl;
	int			n;

	tl = ArrayGetIntegerTypmods(ta, &n);

	/*
	 * we're not too tense about good error message here because grammar
	 * shouldn't allow wrong number of modifiers for CHAR
	 */
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

/****************************************************************
 * 
 * common code for oracharbytetypmodout
 *
 ****************************************************************/
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

/* "True" length (not counting trailing blanks) */
static int
bcTruelen(BpChar *arg)
{
	char	   *s = VARDATA_ANY(arg);
	int			i;
	int			len;

	len = VARSIZE_ANY_EXHDR(arg);
	for (i = len - 1; i >= 0; i--)
	{
		if (s[i] != ' ')
			break;
	}
	return i + 1;
}

/*********************************************************************
*
 * Convert a C string to CHARACTER internal representation.
 * atttypmod is the declared length of the type plus VARHDRSZ.
 *
 *********************************************************************/
Datum
oracharbytein(PG_FUNCTION_ARGS)
{
	char	   *s = PG_GETARG_CSTRING(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		atttypmod = PG_GETARG_INT32(2);
	BpChar	   *result;

	result = bpchar_input(s, strlen(s), atttypmod);
	PG_RETURN_BPCHAR_P(result);
}

/*********************************************************************
 * 
 * Convert a CHARACTER value to a C string.
 * Uses the text conversion functions, which is only appropriate
 * if oracharbyte and text are equivalent types.
 *
 *********************************************************************/
Datum
oracharbyteout(PG_FUNCTION_ARGS)
{
	Datum		txt = PG_GETARG_DATUM(0);

	PG_RETURN_CSTRING(TextDatumGetCString(txt));
}

/*********************************************************************
 * 
 * oracharbyterecv()
 * converts external binary format to bpchar
 *
 *********************************************************************/
Datum
oracharbyterecv(PG_FUNCTION_ARGS)
{
	StringInfo	buf = (StringInfo) PG_GETARG_POINTER(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		atttypmod = PG_GETARG_INT32(2);
	BpChar	   *result;
	char	   *str;
	int			nbytes;

	str = pq_getmsgtext(buf, buf->len - buf->cursor, &nbytes);
	result = bpchar_input(str, nbytes, atttypmod);
	pfree(str);
	PG_RETURN_BPCHAR_P(result);
}

/*********************************************************************
 * 
 * oracharbytesend()
 * converts bpchar to binary format
 *
 *********************************************************************/
Datum
oracharbytesend(PG_FUNCTION_ARGS)
{
	/* Exactly the same as textsend, so share code */
	return textsend(fcinfo);
}

/*********************************************************************
 * 
 * oracharbytetypmodin.
 * 
 *********************************************************************/
Datum
oracharbytetypmodin(PG_FUNCTION_ARGS)
{
	ArrayType  *ta = PG_GETARG_ARRAYTYPE_P(0);

	PG_RETURN_INT32(anychar_typmodin(ta, "char"));
}

/*********************************************************************
 * 
 * oracharbytetypmodout.
 * 
 *********************************************************************/
Datum
oracharbytetypmodout(PG_FUNCTION_ARGS)
{
	int32		typmod = PG_GETARG_INT32(0);

	PG_RETURN_CSTRING(anychar_typmodout(typmod));
}

/*************************************************************************
 *
 * Converts a char(n byte) type to the specified size.
 *
 * maxlen is the typmod, ie, declared length plus VARHDRSZ bytes.
 * isExplicit is true if this is for an explicit cast to char(N).
 *
 * Truncation rules: for an explicit cast, silently truncate to the given
 * length; for an implicit cast, raise error unless extra characters are
 * all spaces.  (This is sort-of per SQL: the spec would actually have us
 * raise a "completion condition" for the explicit cast case, but Postgres
 * hasn't got such a concept.)
 *
 *************************************************************************/
Datum
oracharbyte(PG_FUNCTION_ARGS)
{
	BpChar	   *source = PG_GETARG_BPCHAR_PP(0);
	int32		maxlen = PG_GETARG_INT32(1);
	bool		isExplicit = PG_GETARG_BOOL(2);
	BpChar	   *result;
	int32		len;
	char	   *r;
	char	   *s;

	/* No work if typmod is invalid */
	if (maxlen < (int32) VARHDRSZ)
		PG_RETURN_BPCHAR_P(source);

	maxlen -= VARHDRSZ;

	len = VARSIZE_ANY_EXHDR(source);
	s = VARDATA_ANY(source);

	/* No work if supplied data matches typmod already */
	if (len == maxlen)
		PG_RETURN_BPCHAR_P(source);

	/*
	 * Report error for implicit conversion 
	 * Truncate string for exlicit conversion 
	 */
	if (len > maxlen)
	{
		if (!isExplicit)
			ereport(ERROR,
					(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
					 errmsg("value too long for type char(%d byte)",
							maxlen)));
		len = maxlen;	
	}

	Assert(maxlen >= len);

	result = palloc(maxlen + VARHDRSZ);
	SET_VARSIZE(result, maxlen + VARHDRSZ);
	r = VARDATA(result);

	memcpy(r, s, len);

	/* blank pad the string if necessary */
	if (maxlen > len)
		memset(r + len, ' ', maxlen - len);

	PG_RETURN_BPCHAR_P(result);
}

/*****************************************************************************
 *	Comparison Functions 
 *
 * Note: btree indexes need these routines not to leak memory; therefore,
 * be careful to free working copies of toasted datums.  Most places don't
 * need to be so careful.
 *****************************************************************************/
Datum
oracharbyteeq(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			len1,
				len2;
	bool		result;

	len1 = bcTruelen(arg1);
	len2 = bcTruelen(arg2);

	/*
	 * Since we only care about equality or not-equality, we can avoid all the
	 * expense of strcoll() here, and just do bitwise comparison.
	 */
	if (len1 != len2)
		result = false;
	else
		result = (memcmp(VARDATA_ANY(arg1), VARDATA_ANY(arg2), len1) == 0);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result);
}

Datum
oracharbytene(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			len1,
				len2;
	bool		result;

	len1 = bcTruelen(arg1);
	len2 = bcTruelen(arg2);

	/*
	 * Since we only care about equality or not-equality, we can avoid all the
	 * expense of strcoll() here, and just do bitwise comparison.
	 */
	if (len1 != len2)
		result = true;
	else
		result = (memcmp(VARDATA_ANY(arg1), VARDATA_ANY(arg2), len1) != 0);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result);
}

Datum
oracharbytelt(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			len1,
				len2;
	int			cmp;

	len1 = bcTruelen(arg1);
	len2 = bcTruelen(arg2);

	cmp = varstr_cmp(VARDATA_ANY(arg1), len1, VARDATA_ANY(arg2), len2,
					 PG_GET_COLLATION());

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(cmp < 0);
}

Datum
oracharbytele(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			len1,
				len2;
	int			cmp;

	len1 = bcTruelen(arg1);
	len2 = bcTruelen(arg2);

	cmp = varstr_cmp(VARDATA_ANY(arg1), len1, VARDATA_ANY(arg2), len2,
					 PG_GET_COLLATION());

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(cmp <= 0);
}

Datum
oracharbytegt(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			len1,
				len2;
	int			cmp;

	len1 = bcTruelen(arg1);
	len2 = bcTruelen(arg2);

	cmp = varstr_cmp(VARDATA_ANY(arg1), len1, VARDATA_ANY(arg2), len2,
					 PG_GET_COLLATION());

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(cmp > 0);
}

Datum
oracharbytege(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			len1,
				len2;
	int			cmp;

	len1 = bcTruelen(arg1);
	len2 = bcTruelen(arg2);

	cmp = varstr_cmp(VARDATA_ANY(arg1), len1, VARDATA_ANY(arg2), len2,
					 PG_GET_COLLATION());

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(cmp >= 0);
}

/*************************************************************************
 * 
 * Aggregate Function
 *
 **************************************************************************/
/* State transition function for aggregate 'max'*/
Datum
oracharbyte_larger(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			len1,
				len2;
	int			cmp;

	len1 = bcTruelen(arg1);
	len2 = bcTruelen(arg2);

	cmp = varstr_cmp(VARDATA_ANY(arg1), len1, VARDATA_ANY(arg2), len2,
					 PG_GET_COLLATION());

	PG_RETURN_BPCHAR_P((cmp >= 0) ? arg1 : arg2);
}

/* State transition function for aggregate 'min'*/
Datum
oracharbyte_smaller(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			len1,
				len2;
	int			cmp;

	len1 = bcTruelen(arg1);
	len2 = bcTruelen(arg2);

	cmp = varstr_cmp(VARDATA_ANY(arg1), len1, VARDATA_ANY(arg2), len2,
					 PG_GET_COLLATION());

	PG_RETURN_BPCHAR_P((cmp <= 0) ? arg1 : arg2);
}

/**********************************************************************
 *
 * Index support procedure 
 *
 *********************************************************************/

/* The support routine for B-tree */
Datum
oracharbytecmp(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			len1,
				len2;
	int			cmp;

	len1 = bcTruelen(arg1);
	len2 = bcTruelen(arg2);

	cmp = varstr_cmp(VARDATA_ANY(arg1), len1, VARDATA_ANY(arg2), len2,
					 PG_GET_COLLATION());

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_INT32(cmp);
}

Datum
oracharbyte_sortsupport(PG_FUNCTION_ARGS)
{
	SortSupport ssup = (SortSupport) PG_GETARG_POINTER(0);
	Oid			collid = ssup->ssup_collation;
	MemoryContext oldcontext;

	oldcontext = MemoryContextSwitchTo(ssup->ssup_cxt);

	/* Use generic string SortSupport */
	varstr_sortsupport(ssup, ORACHARBYTEOID, collid);

	MemoryContextSwitchTo(oldcontext);

	PG_RETURN_VOID();
}

/*
 * The support routine for hash.
 *
 * orachar needs a specialized hash function because we want to ignore
 * trailing blanks in comparisons.
 *
 * Note: currently there is no need for locale-specific behavior here,
 * but if we ever change the semantics of orachar comparison to trust
 * strcoll() completely, we'd need to do something different in non-C locales.
 */
Datum
oracharbytehash(PG_FUNCTION_ARGS)
{
	BpChar	   *key = PG_GETARG_BPCHAR_PP(0);
	char	   *keydata;
	int			keylen;
	Datum		result;

	keydata = VARDATA_ANY(key);
	keylen = bcTruelen(key);

	result = hash_any((unsigned char *) keydata, keylen);

	/* Avoid leaking memory for toasted inputs */
	PG_FREE_IF_COPY(key, 0);

	return result;
}

