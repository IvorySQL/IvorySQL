/*-------------------------------------------------------------------------
 *
 * oracharchar.c
 *
 * Compatible with Oracle's CHAR(n char) data type.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/oracharchar.c
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
#include "utils/varlena.h"
#include "mb/pg_wchar.h"
#include "fmgr.h"

#include "../include/common_datatypes.h"

#define MaxCharSize 32767

PG_FUNCTION_INFO_V1(oracharcharin);
PG_FUNCTION_INFO_V1(oracharcharout);
PG_FUNCTION_INFO_V1(oracharcharrecv);
PG_FUNCTION_INFO_V1(oracharcharsend);
PG_FUNCTION_INFO_V1(oracharchar);
PG_FUNCTION_INFO_V1(oracharchartypmodin);
PG_FUNCTION_INFO_V1(oracharchartypmodout);
PG_FUNCTION_INFO_V1(oracharcharcmp);
PG_FUNCTION_INFO_V1(oracharchar_sortsupport);
PG_FUNCTION_INFO_V1(oracharchareq);	
PG_FUNCTION_INFO_V1(oracharcharne);
PG_FUNCTION_INFO_V1(oracharchargt);
PG_FUNCTION_INFO_V1(oracharcharge);
PG_FUNCTION_INFO_V1(oracharcharlt);
PG_FUNCTION_INFO_V1(oracharcharle);
PG_FUNCTION_INFO_V1(rtrim);
PG_FUNCTION_INFO_V1(char_orachar);
PG_FUNCTION_INFO_V1(orachar_char);
PG_FUNCTION_INFO_V1(name_orachar);
PG_FUNCTION_INFO_V1(orachar_name);
PG_FUNCTION_INFO_V1(bool_orachar);
PG_FUNCTION_INFO_V1(oracharchar_larger);
PG_FUNCTION_INFO_V1(oracharchar_smaller);
PG_FUNCTION_INFO_V1(oracharcharhash);
PG_FUNCTION_INFO_V1(orachar_pattern_lt);
PG_FUNCTION_INFO_V1(orachar_pattern_le);
PG_FUNCTION_INFO_V1(orachar_pattern_ge);
PG_FUNCTION_INFO_V1(orachar_pattern_gt);
PG_FUNCTION_INFO_V1(btorachar_pattern_cmp);
PG_FUNCTION_INFO_V1(btoracharchar_pattern_sortsupport);
PG_FUNCTION_INFO_V1(btoracharbyte_pattern_sortsupport);


/****************************************************************
 * 
 * common code for oracharchartypmodin
 *
 ****************************************************************/
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

/*******************************************************************
 * bpchar_input -- common guts of oracharcharin and oracharcharrecv
 *
 * s is the input text of length len (may not be null-terminated)
 * atttypmod is the typmod value to apply
 *
 * Note that atttypmod is measured in characters, which
 * is not necessarily the same as the number of bytes.
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
		size_t		charlen;	/* number of CHARACTERS in the input */

		maxlen = atttypmod - VARHDRSZ;
		charlen = pg_mbstrlen_with_len(s, len);
		if (charlen > maxlen)
		{
			ereport(ERROR,
					(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
					 errmsg("value too long for type char(%d char)",
							(int) maxlen)));
		}
		else
		{
			/*
			 * Now we set maxlen to the necessary byte length, not the number
			 * of CHARACTERS!
			 */
			maxlen = len + (maxlen - charlen);
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
 * common code for oracharchartypmodout
 *
 ****************************************************************/
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

/*
 * The following operators support character-by-character comparison
 * of bpchar datums, to allow building indexes suitable for LIKE clauses.
 * Note that the regular bpchareq/bpcharne comparison operators are assumed
 * to be compatible with these!
 */
static int
internal_bpchar_pattern_compare(BpChar *arg1, BpChar *arg2)
{
	int			result;
	int			len1,
				len2;

	len1 = bcTruelen(arg1);
	len2 = bcTruelen(arg2);

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

/*********************************************************************
 *
 * Convert a C string to CHARACTER internal representation.
 * atttypmod is the declared length of the type plus VARHDRSZ.
 *
 *********************************************************************/
Datum
oracharcharin(PG_FUNCTION_ARGS)
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
 * if oracharchar and text are equivalent types.
 *
 *********************************************************************/
Datum
oracharcharout(PG_FUNCTION_ARGS)
{
	Datum		txt = PG_GETARG_DATUM(0);

	PG_RETURN_CSTRING(TextDatumGetCString(txt));
}

/*********************************************************************
 *
 * oracharcharrecv()
 * converts external binary format to bpchar
 *
 *********************************************************************/
Datum
oracharcharrecv(PG_FUNCTION_ARGS)
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
 * oracharcharsend()
 * converts bpchar to binary format
 *
 *********************************************************************/
/*
 *		bpcharsend			- 
 */
Datum
oracharcharsend(PG_FUNCTION_ARGS)
{
	/* Exactly the same as textsend, so share code */
	return textsend(fcinfo);
}

/*********************************************************************
 *
 * oracharchartypmodin.
 *
 *********************************************************************/
Datum
oracharchartypmodin(PG_FUNCTION_ARGS)
{
	ArrayType  *ta = PG_GETARG_ARRAYTYPE_P(0);

	PG_RETURN_INT32(anychar_typmodin(ta, "char"));
}

/*********************************************************************
 *
 * oracharchartypmodout.
 *
 *********************************************************************/
Datum
oracharchartypmodout(PG_FUNCTION_ARGS)
{
	int32		typmod = PG_GETARG_INT32(0);

	PG_RETURN_CSTRING(anychar_typmodout(typmod));
}

/*************************************************************************
 * Conversion Function
 *
 * Common for 'oracharchar' and 'oracharbyte' data type
 * except function 'oracharchar'
 *
 **************************************************************************/
/* Converts a char(n char) type to the specified size. */
Datum
oracharchar(PG_FUNCTION_ARGS)
{
	BpChar	   *source = PG_GETARG_BPCHAR_PP(0);
	int32		maxlen = PG_GETARG_INT32(1);
	bool		isExplicit = PG_GETARG_BOOL(2);
	BpChar	   *result;
	int32		len;
	char	   *r;
	char	   *s;
	int			charlen;	

	/* No work if typmod is invalid */
	if (maxlen < (int32) VARHDRSZ)
		PG_RETURN_BPCHAR_P(source);

	maxlen -= VARHDRSZ;

	len = VARSIZE_ANY_EXHDR(source);
	s = VARDATA_ANY(source);

	charlen = pg_mbstrlen_with_len(s, len);

	/* No work if supplied data matches typmod already */
	if (charlen == maxlen)
		PG_RETURN_BPCHAR_P(source);

	/*
	 * Report error for implicit conversion
	 * Truncate string for exlicit conversion
	 */
	if (charlen > maxlen)
	{
		size_t		maxmblen;

		maxmblen = pg_mbcharcliplen(s, len, maxlen);
		
		if (!isExplicit)
		{
			ereport(ERROR,
					(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
					 errmsg("value too long for type char(%d char)",
							maxlen)));
		}

		len = maxmblen;

		/*
		 * At this point, maxlen is the necessary byte length, not the number
		 * of CHARACTERS!
		 */
		maxlen = len;
	}
	else
	{
		/*
		 * At this point, maxlen is the necessary byte length, not the number
		 * of CHARACTERS!
		 */
		maxlen = len + (maxlen - charlen);
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

/* Convert orachar(byte/char) to text */
Datum
rtrim(PG_FUNCTION_ARGS)
{
	text	   *string = PG_GETARG_TEXT_PP(0);
	text	   *ret;

	ret = ora_dotrim(VARDATA_ANY(string), VARSIZE_ANY_EXHDR(string),
					" ", 1,
					false, true);

	PG_RETURN_TEXT_P(ret);
}

/* Convert "char" to orachar(1) */
Datum
char_orachar(PG_FUNCTION_ARGS)
{
	char		c = PG_GETARG_CHAR(0);
	BpChar	   *result;

	result = (BpChar *) palloc(VARHDRSZ + 1);

	SET_VARSIZE(result, VARHDRSZ + 1);
	*(VARDATA(result)) = c;

	PG_RETURN_BPCHAR_P(result);
}

/* Convert orachar to "char" */
Datum
orachar_char(PG_FUNCTION_ARGS)
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

/* Convert a orachar type to a NameData type */
Datum
orachar_name(PG_FUNCTION_ARGS)
{
	BpChar	   *s = PG_GETARG_BPCHAR_PP(0);
	char	   *s_data;
	Name		result;
	int			len;

	len = VARSIZE_ANY_EXHDR(s);
	s_data = VARDATA_ANY(s);

	/* Truncate oversize input */
	if (len >= NAMEDATALEN)
		len = pg_mbcliplen(s_data, len, NAMEDATALEN - 1);

	/* Remove trailing blanks */
	while (len > 0)
	{
		if (s_data[len - 1] != ' ')
			break;
		len--;
	}

	/* We use palloc0 here to ensure result is zero-padded */
	result = (Name) palloc0(NAMEDATALEN);
	memcpy(NameStr(*result), s_data, len);

	PG_RETURN_NAME(result);
}

/* Convert a NameData type to a orachar type */
Datum
name_orachar(PG_FUNCTION_ARGS)
{
	Name		s = PG_GETARG_NAME(0);
	BpChar	   *result;

	result = (BpChar *) cstring_to_text(NameStr(*s));
	PG_RETURN_BPCHAR_P(result);
}

/* Convert a boolean type to a orachar type */
Datum
bool_orachar(PG_FUNCTION_ARGS)
{
	bool		arg1 = PG_GETARG_BOOL(0);
	const char *str;

	if (arg1)
		str = "true";
	else
		str = "false";

	PG_RETURN_TEXT_P(cstring_to_text(str));
}

/*****************************************************************************
 *	Comparison Functions used for oracharchar
 *
 * Note: btree indexes need these routines not to leak memory; therefore,
 * be careful to free working copies of toasted datums.  Most places don't
 * need to be so careful.
 *****************************************************************************/
Datum
oracharchareq(PG_FUNCTION_ARGS)
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
oracharcharne(PG_FUNCTION_ARGS)
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
oracharcharlt(PG_FUNCTION_ARGS)
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
oracharcharle(PG_FUNCTION_ARGS)
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
oracharchargt(PG_FUNCTION_ARGS)
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
oracharcharge(PG_FUNCTION_ARGS)
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

/*
 * character-by-character comparison, 
 * to allow building indexes suitable for LIKE clauses.
 * common code for orachar
 */
Datum
orachar_pattern_lt(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			result;

	result = internal_bpchar_pattern_compare(arg1, arg2);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result < 0);
}

Datum
orachar_pattern_le(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			result;

	result = internal_bpchar_pattern_compare(arg1, arg2);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result <= 0);
}

Datum
orachar_pattern_ge(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			result;

	result = internal_bpchar_pattern_compare(arg1, arg2);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result >= 0);
}

Datum
orachar_pattern_gt(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			result;

	result = internal_bpchar_pattern_compare(arg1, arg2);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_BOOL(result > 0);
}

/*************************************************************************
 * Aggregate Function
 *************************************************************************/
/* State transition function for aggregate 'max'*/
Datum
oracharchar_larger(PG_FUNCTION_ARGS)
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
oracharchar_smaller(PG_FUNCTION_ARGS)
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
 **********************************************************************/
/* The support routine for B-tree */
Datum
oracharcharcmp(PG_FUNCTION_ARGS)
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
oracharchar_sortsupport(PG_FUNCTION_ARGS)
{
	SortSupport ssup = (SortSupport) PG_GETARG_POINTER(0);
	Oid			collid = ssup->ssup_collation;
	MemoryContext oldcontext;

	oldcontext = MemoryContextSwitchTo(ssup->ssup_cxt);

	/* Use generic string SortSupport */
	varstr_sortsupport(ssup, ORACHARCHAROID, collid);

	MemoryContextSwitchTo(oldcontext);

	PG_RETURN_VOID();
}

Datum
btorachar_pattern_cmp(PG_FUNCTION_ARGS)
{
	BpChar	   *arg1 = PG_GETARG_BPCHAR_PP(0);
	BpChar	   *arg2 = PG_GETARG_BPCHAR_PP(1);
	int			result;

	result = internal_bpchar_pattern_compare(arg1, arg2);

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_INT32(result);
}

Datum
btoracharchar_pattern_sortsupport(PG_FUNCTION_ARGS)
{
	SortSupport ssup = (SortSupport) PG_GETARG_POINTER(0);
	MemoryContext oldcontext;

	oldcontext = MemoryContextSwitchTo(ssup->ssup_cxt);

	/* Use generic string SortSupport, forcing "C" collation */
	varstr_sortsupport(ssup, ORACHARCHAROID, C_COLLATION_OID);

	MemoryContextSwitchTo(oldcontext);

	PG_RETURN_VOID();
}

Datum
btoracharbyte_pattern_sortsupport(PG_FUNCTION_ARGS)
{
	SortSupport ssup = (SortSupport) PG_GETARG_POINTER(0);
	MemoryContext oldcontext;

	oldcontext = MemoryContextSwitchTo(ssup->ssup_cxt);

	/* Use generic string SortSupport, forcing "C" collation */
	varstr_sortsupport(ssup, ORACHARBYTEOID, C_COLLATION_OID);

	MemoryContextSwitchTo(oldcontext);

	PG_RETURN_VOID();
}

/*
 * The support routine for hash.
 * orachar needs a specialized hash function because we want to ignore
 * trailing blanks in comparisons.
 *
 * Note: currently there is no need for locale-specific behavior here,
 * but if we ever change the semantics of orachar comparison to trust
 * strcoll() completely, we'd need to do something different in non-C locales.
 */
Datum
oracharcharhash(PG_FUNCTION_ARGS)
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

