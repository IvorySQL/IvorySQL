/*-------------------------------------------------------------------------
 *
 * oravarcharchar.c
 *
 * Compatible with Oracle's VARCHAR2(n char) data type.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/oravarcharchar.c
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
#include "mb/pg_wchar.h"
#include "utils/varlena.h"
#include "fmgr.h"
#include "catalog/namespace.h"
#include "utils/xml.h"
#include "../include/common_datatypes.h"

#define MaxVarcharSize 32767

PG_FUNCTION_INFO_V1(oravarcharcharin);
PG_FUNCTION_INFO_V1(oravarcharcharout);
PG_FUNCTION_INFO_V1(oravarcharchar);
PG_FUNCTION_INFO_V1(oravarcharchartypmodin);
PG_FUNCTION_INFO_V1(oravarcharchartypmodout);
PG_FUNCTION_INFO_V1(oravarcharcharrecv);
PG_FUNCTION_INFO_V1(oravarcharcharsend);
PG_FUNCTION_INFO_V1(oravarchareq);	
PG_FUNCTION_INFO_V1(oravarcharne);
PG_FUNCTION_INFO_V1(oravarcharlt);
PG_FUNCTION_INFO_V1(oravarcharle);
PG_FUNCTION_INFO_V1(oravarchargt);
PG_FUNCTION_INFO_V1(oravarcharge);
PG_FUNCTION_INFO_V1(bt_oravarchar_cmp);
PG_FUNCTION_INFO_V1(btoravarcharcharsortsupport);
PG_FUNCTION_INFO_V1(btoravarchar_pattern_cmp);
PG_FUNCTION_INFO_V1(btoravarcharchar_pattern_sortsupport);
PG_FUNCTION_INFO_V1(oravarchar_pattern_lt);
PG_FUNCTION_INFO_V1(oravarchar_pattern_le);
PG_FUNCTION_INFO_V1(oravarchar_pattern_gt);
PG_FUNCTION_INFO_V1(oravarchar_pattern_ge);
PG_FUNCTION_INFO_V1(hashoravarchar);	
PG_FUNCTION_INFO_V1(oravarchar_larger);	
PG_FUNCTION_INFO_V1(oravarchar_smaller);

PG_FUNCTION_INFO_V1(oravarchar_regclass);
PG_FUNCTION_INFO_V1(char_oravarchar);
PG_FUNCTION_INFO_V1(oravarchar_char);
PG_FUNCTION_INFO_V1(name_oravarchar);
PG_FUNCTION_INFO_V1(oravarchar_name);
PG_FUNCTION_INFO_V1(bool_oravarchar);
PG_FUNCTION_INFO_V1(oravarchar_xml);

PG_FUNCTION_INFO_V1(oravarcharcat);
static VarChar *oravarchar_catenate(VarChar *t1, VarChar *t2);


/*
 * varchar_input -- common guts of oravarcharcharin and oravarcharcharrecv
 *
 * "atttypmod" is measured in characters ,but for "oravarcharbyte" type is
 * measured in bytes.
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
		/* Verify that the length of multi-byte characters equal len */
		size_t		mbmaxlen = pg_mbcharcliplen(s, len, maxlen);

		if (len != mbmaxlen)
			ereport(ERROR,
					(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
				  errmsg("value too long for type varchar2(%d char)",
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
		if (nls_length_semantics == NLS_LENGTH_CHAR)
			snprintf(res, 64, "(%d)", (int) (typmod - VARHDRSZ));
		else
			snprintf(res, 69, "(%d char)", (int) (typmod - VARHDRSZ));
	}
	else
	{
		*res = '\0';
	}

	return res;
}

static int
internal_varchar_pattern_compare(VarChar *arg1, VarChar *arg2)
{
	int			result;
	int			len1,
				len2;

	len1 = VARSIZE_ANY_EXHDR(arg1);
	len2 = VARSIZE_ANY_EXHDR(arg2);

	result = memcmp(VARDATA_ANY(arg1), VARDATA_ANY(arg2), Min(len1, len2));
	if (result != 0)
		return result;
	else if (len1 < len2)
		return -1;
	else if (len1 > len2)
		return 1;
	else
		return 0;
}

/*
 * Convert a C string to VARCHAR2 internal representation.
 * atttypmod is the declared length of the type plus VARHDRSZ.
 */
Datum
oravarcharcharin(PG_FUNCTION_ARGS)
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
oravarcharcharout(PG_FUNCTION_ARGS)
{
	Datum		txt = PG_GETARG_DATUM(0);

	PG_RETURN_CSTRING(TextDatumGetCString(txt));
}

/*
 *	oravarcharcharrecv	- converts external binary format to varchar2
 */
Datum
oravarcharcharrecv(PG_FUNCTION_ARGS)
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
oravarcharcharsend(PG_FUNCTION_ARGS)
{
	/* Exactly the same as textsend, so share code */
	return textsend(fcinfo);
}

Datum
oravarcharchartypmodin(PG_FUNCTION_ARGS)
{
	ArrayType  *ta = PG_GETARG_ARRAYTYPE_P(0);

	PG_RETURN_INT32(anychar_typmodin(ta, "varchar2"));
}

Datum
oravarcharchartypmodout(PG_FUNCTION_ARGS)
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
oravarcharchar(PG_FUNCTION_ARGS)
{
	VarChar    *source = PG_GETARG_VARCHAR_PP(0);
	int32		typmod = PG_GETARG_INT32(1);
	bool		isExplicit = PG_GETARG_BOOL(2);
	VarChar    *result;
	int32		len,
				maxlen;
	size_t		maxmblen;
	char	   *s_data;

	len = VARSIZE_ANY_EXHDR(source);
	s_data = VARDATA_ANY(source);
	maxlen = typmod - VARHDRSZ;

	/* No work if typmod is invalid or supplied data fits it already */
	if (maxlen < 0 || len <= maxlen)
		PG_RETURN_VARCHAR_P(source);

	maxmblen = pg_mbcharcliplen(s_data, len, maxlen);

	if (!isExplicit)
	{
		if (len > maxmblen)
				ereport(ERROR,
						(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
					  errmsg("value too long for type varchar2(%d char)",
							 maxlen)));
	}

	result = (VarChar *) palloc(maxmblen + VARHDRSZ);
	SET_VARSIZE(result, maxmblen + VARHDRSZ);
	memcpy(VARDATA(result), s_data, maxmblen);

	PG_RETURN_VARCHAR_P(result);
}

/****************************************************************
 * 
 * Operator function
 *
 ****************************************************************/

/* oravarcharchar_cmp()
 * Internal comparison function for oravarchar.
 * Returns -1, 0 or 1
 */
static int
oravarcharchar_cmp(VarChar *arg1, VarChar *arg2, Oid collid)
{
	char	   *a1p,
			   *a2p;
	int			len1,
				len2;

	a1p = VARDATA_ANY(arg1);
	a2p = VARDATA_ANY(arg2);

	len1 = VARSIZE_ANY_EXHDR(arg1);
	len2 = VARSIZE_ANY_EXHDR(arg2);

	return varstr_cmp(a1p, len1, a2p, len2, collid);
}

Datum
oravarchareq(PG_FUNCTION_ARGS)
{
	Datum		arg1 = PG_GETARG_DATUM(0);
	Datum		arg2 = PG_GETARG_DATUM(1);
	bool		result;
	Size		len1,
				len2;

	len1 = toast_raw_datum_size(arg1);
	len2 = toast_raw_datum_size(arg2);
	if (len1 != len2)
		result = false;
	else
	{
		VarChar	   *targ1 = DatumGetVarCharPP(arg1);
		VarChar	   *targ2 = DatumGetVarCharPP(arg2);

		result = (memcmp(VARDATA_ANY(targ1), VARDATA_ANY(targ2),
						 len1 - VARHDRSZ) == 0);

		PG_FREE_IF_COPY(targ1, 0);
		PG_FREE_IF_COPY(targ2, 1);
	}

	PG_RETURN_BOOL(result);
}

Datum
oravarcharne(PG_FUNCTION_ARGS)
{
	Datum		arg1 = PG_GETARG_DATUM(0);
	Datum		arg2 = PG_GETARG_DATUM(1);
	bool		result;
	Size		len1,
				len2;

	len1 = toast_raw_datum_size(arg1);
	len2 = toast_raw_datum_size(arg2);
	if (len1 != len2)
		result = true;
	else
	{
		VarChar	   *targ1 = DatumGetVarCharPP(arg1);
		VarChar	   *targ2 = DatumGetVarCharPP(arg2);

		result = (memcmp(VARDATA_ANY(targ1), VARDATA_ANY(targ2),
						 len1 - VARHDRSZ) != 0);

		PG_FREE_IF_COPY(targ1, 0);
		PG_FREE_IF_COPY(targ2, 1);
	}

	PG_RETURN_BOOL(result);
}

Datum
oravarcharlt(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	bool		result;

	result = (oravarcharchar_cmp(arg1, arg2, PG_GET_COLLATION()) < 0);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result);
}

Datum
oravarcharle(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	bool		result;

	result = (oravarcharchar_cmp(arg1, arg2, PG_GET_COLLATION()) <= 0);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result);
}

Datum
oravarchargt(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	bool		result;

	result = (oravarcharchar_cmp(arg1, arg2, PG_GET_COLLATION()) > 0);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result);
}

Datum
oravarcharge(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	bool		result;

	result = (oravarcharchar_cmp(arg1, arg2, PG_GET_COLLATION()) >= 0);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result);
}


/*
 * The following operators support character-by-character comparison
 * of text datums, to allow building indexes suitable for LIKE clauses.
 * Note that the regular texteq/textne comparison operators are assumed
 * to be compatible with these!
 */
Datum
oravarchar_pattern_lt(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	int			result;

	result = internal_varchar_pattern_compare(arg1, arg2);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result < 0);
}

Datum
oravarchar_pattern_le(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	int			result;

	result = internal_varchar_pattern_compare(arg1, arg2);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result <= 0);
}

Datum
oravarchar_pattern_ge(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	int			result;

	result = internal_varchar_pattern_compare(arg1, arg2);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result >= 0);
}


Datum
oravarchar_pattern_gt(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	int			result;

	result = internal_varchar_pattern_compare(arg1, arg2);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result > 0);
}

/**********************************************************************
 *
 * Index support procedure
 *
 *********************************************************************/

/* B-tree support procedure for type 'oravarcharbyte' and 'oravarcharchar' */
Datum
bt_oravarchar_cmp(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	int32		result;

	result = oravarcharchar_cmp(arg1, arg2, PG_GET_COLLATION());

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_INT32(result);
}

Datum
btoravarcharcharsortsupport(PG_FUNCTION_ARGS)
{
	SortSupport ssup = (SortSupport) PG_GETARG_POINTER(0);
	Oid			collid = ssup->ssup_collation;
	MemoryContext oldcontext;

	oldcontext = MemoryContextSwitchTo(ssup->ssup_cxt);

	/* Use generic string SortSupport */
	varstr_sortsupport(ssup, ORAVARCHARCHAROID, collid);

	MemoryContextSwitchTo(oldcontext);

	PG_RETURN_VOID();
}

/* Hash support procedure for type 'oravarcharbyte' and 'oravarcharchar' */
Datum
hashoravarchar(PG_FUNCTION_ARGS)
{
	VarChar	   *key = PG_GETARG_VARCHAR_PP(0);
	Datum		result;

	/*
	 * Note: this is currently identical in behavior to hashvarlena, but keep
	 * it as a separate function in case we someday want to do something
	 * different in non-C locales.  (See also hashbpchar, if so.)
	 */
	result = hash_any((unsigned char *) VARDATA_ANY(key),
					  VARSIZE_ANY_EXHDR(key));

	/* Avoid leaking memory for toasted inputs */
	PG_FREE_IF_COPY(key, 0);

	return result;
}

Datum
btoravarchar_pattern_cmp(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	int			result;

	result = internal_varchar_pattern_compare(arg1, arg2);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_INT32(result);
}

Datum
btoravarcharchar_pattern_sortsupport(PG_FUNCTION_ARGS)
{
	SortSupport ssup = (SortSupport) PG_GETARG_POINTER(0);
	MemoryContext oldcontext;

	oldcontext = MemoryContextSwitchTo(ssup->ssup_cxt);

	/* Use generic string SortSupport, forcing "C" collation */
	varstr_sortsupport(ssup, ORAVARCHARCHAROID, C_COLLATION_OID);

	MemoryContextSwitchTo(oldcontext);

	PG_RETURN_VOID();
}

/*************************************************************************
 * 
 * Aggregate Function
 * 
 **************************************************************************/

Datum
oravarchar_larger(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	VarChar	   *result;

	result = ((oravarcharchar_cmp(arg1, arg2, PG_GET_COLLATION()) > 0) ? arg1 : arg2);

	PG_RETURN_VARCHAR_P(result);
}

Datum
oravarchar_smaller(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	VarChar	   *result;

	result = ((oravarcharchar_cmp(arg1, arg2, PG_GET_COLLATION()) < 0) ? arg1 : arg2);

	PG_RETURN_VARCHAR_P(result);
}

/*************************************************************************
 * 
 * Conversion Function
 * 
 **************************************************************************/

/*
 * oravarchar_regclass: convert varchar2 to regclass
 *
 * This could be replaced by CoerceViaIO, except that we need to treat
 * text-to-regclass as an implicit cast to support legacy forms of nextval()
 * and related functions.
 */
Datum
oravarchar_regclass(PG_FUNCTION_ARGS)
{
	text	   *relname = PG_GETARG_TEXT_P(0);
	Oid			result;
	RangeVar   *rv;

	rv = makeRangeVarFromNameList(textToQualifiedNameList(relname));

	/* We might not even have permissions on this relation; don't lock it. */
	result = RangeVarGetRelid(rv, NoLock, false);

	PG_RETURN_OID(result);
}

/*
 * char_oravarchar: convert "char" to varchar2
 */
Datum
char_oravarchar(PG_FUNCTION_ARGS)
{
	char		arg1 = PG_GETARG_CHAR(0);
	text	   *result = palloc(VARHDRSZ + 1);

	/*
	 * Convert \0 to an empty string, for consistency with charout (and
	 * because the text stuff doesn't like embedded nulls all that well).
	 */
	if (arg1 != '\0')
	{
		SET_VARSIZE(result, VARHDRSZ + 1);
		*(VARDATA(result)) = arg1;
	}
	else
		SET_VARSIZE(result, VARHDRSZ);

	PG_RETURN_TEXT_P(result);
}


/*
 * oravarchar_char: convert varchar2 to "char"
 */
Datum
oravarchar_char(PG_FUNCTION_ARGS)
{
	text	   *arg1 = PG_GETARG_TEXT_P(0);
	char		result;

	/*
	 * An empty input string is converted to \0 (for consistency with charin).
	 * If the input is longer than one character, the excess data is silently
	 * discarded.
	 */
	if (VARSIZE(arg1) > VARHDRSZ)
		result = *(VARDATA(arg1));
	else
		result = '\0';

	PG_RETURN_CHAR(result);
}

/* name_oravarchar()
 * Converts a Name type to a varchar2 type.
 */
Datum
name_oravarchar(PG_FUNCTION_ARGS)
{
	Name		s = PG_GETARG_NAME(0);

	PG_RETURN_TEXT_P(cstring_to_text(NameStr(*s)));
}

/* oravarchar_name()
 * Converts a oravarchar type to a Name type.
 */
Datum
oravarchar_name(PG_FUNCTION_ARGS)
{
	text	   *s = PG_GETARG_TEXT_PP(0);
	Name		result;
	int			len;

	len = VARSIZE_ANY_EXHDR(s);

	/* Truncate oversize input */
	if (len >= NAMEDATALEN)
		len = pg_mbcliplen(VARDATA_ANY(s), len, NAMEDATALEN - 1);

	/* We use palloc0 here to ensure result is zero-padded */
	result = (Name) palloc0(NAMEDATALEN);
	memcpy(NameStr(*result), VARDATA_ANY(s), len);

	PG_RETURN_NAME(result);
}

/* bool_oravarchar()
 * Converts a boolean type to a varchar2 type.
 */
Datum
bool_oravarchar(PG_FUNCTION_ARGS)
{
	bool		arg1 = PG_GETARG_BOOL(0);
	const char *str;

	if (arg1)
		str = "true";
	else
		str = "false";

	PG_RETURN_TEXT_P(cstring_to_text(str));
}

/* oravarchar_xml()
 * Converts a varchar2 type to a xml type.
 */
Datum
oravarchar_xml(PG_FUNCTION_ARGS)
{
	text	   *data = PG_GETARG_TEXT_P(0);

	PG_RETURN_XML_P(xmlparse(data, xmloption, true));
}

/*
 * support number || integer we handle like
 * textcat
 */
Datum
oravarcharcat(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1;
	VarChar	   *arg2;
	VarChar	   *result;

	if (PG_ARGISNULL(0) && PG_ARGISNULL(1))
		PG_RETURN_NULL();
	else if (!PG_ARGISNULL(0) && PG_ARGISNULL(1))
		PG_RETURN_TEXT_P(PG_GETARG_TEXT_PP(0));
	else if (!PG_ARGISNULL(1) && PG_ARGISNULL(0))
		PG_RETURN_TEXT_P(PG_GETARG_TEXT_PP(1));

	arg1 = PG_GETARG_VARCHAR_PP(0);
	arg2 = PG_GETARG_VARCHAR_PP(1);

	result = oravarchar_catenate(arg1, arg2);

	PG_RETURN_VARCHAR_P(result);
}

/*
 * like text_catenate
 */
static VarChar *
oravarchar_catenate(VarChar *t1, VarChar *t2)
{
	VarChar	   *result;
	int 		len1,
				len2,
				len;
	char	   *ptr;

	len1 = VARSIZE_ANY_EXHDR(t1);
	len2 = VARSIZE_ANY_EXHDR(t2);

	/* paranoia ... probably should throw error instead? */
	if (len1 < 0)
		len1 = 0;
	if (len2 < 0)
		len2 = 0;

	len = len1 + len2 + VARHDRSZ;
	result = (VarChar *) palloc(len);

	/* Set size of result string... */
	SET_VARSIZE(result, len);

	/* Fill data field of result string... */
	ptr = VARDATA(result);
	if (len1 > 0)
		memcpy(ptr, VARDATA_ANY(t1), len1);
	if (len2 > 0)
		memcpy(ptr + len1, VARDATA_ANY(t2), len2);

	return result;
}

