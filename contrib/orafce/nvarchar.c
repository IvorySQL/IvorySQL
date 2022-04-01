
/*----------------------------------------------------------------------------
 *
 *     nvarchar.c
 *     nvarchar type for PostgreSQL.
 *
 *----------------------------------------------------------------------------
 */

#include "postgres.h"
#include "access/hash.h"
#include "libpq/pqformat.h"
#include "nodes/nodeFuncs.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "mb/pg_wchar.h"
#include "fmgr.h"

#include "orafce.h"
#include "builtins.h"


PG_FUNCTION_INFO_V1(nvarcharin);
PG_FUNCTION_INFO_V1(nvarchar);

/*
 * varchar_input -- common guts of varcharin and varcharrecv
 *
 * s is the input text of length len (may not be null-terminated)
 * atttypmod is the typmod value to apply
 *
 * Note that atttypmod is measured in characters, which
 * is not necessarily the same as the number of bytes.
 *
 * If the input string is too long, raise an error, unless the extra
 * characters are spaces, in which case they're truncated.  (per SQL)
 *
 * Uses the C string to text conversion function, which is only appropriate
 * if VarChar and text are equivalent types.
 */
static VarChar *
nvarchar_input(const char *s, size_t len, int32 atttypmod)
{
	VarChar    *result;
	size_t		maxlen;

	maxlen = atttypmod - VARHDRSZ;

	if (atttypmod >= (int32) VARHDRSZ && len > maxlen)
	{
		/* Verify that extra characters are spaces, and clip them off */
		size_t		mbmaxlen = pg_mbcharcliplen(s, len, maxlen);
		size_t		j;

		for (j = mbmaxlen; j < len; j++)
		{
			if (s[j] != ' ')
				ereport(ERROR,
						(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
						 errmsg("value too long for type character varying(%d)",
								(int) maxlen)));
		}

		len = mbmaxlen;
	}

	result = (VarChar *) cstring_to_text_with_len(s, len);
	return result;
}

/*
 * Convert a C string to VARCHAR internal representation.  atttypmod
 * is the declared length of the type plus VARHDRSZ.
 */
Datum
nvarcharin(PG_FUNCTION_ARGS)
{
	char	   *s = PG_GETARG_CSTRING(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		atttypmod = PG_GETARG_INT32(2);
	VarChar    *result;

	result = nvarchar_input(s, strlen(s), atttypmod);
	PG_RETURN_VARCHAR_P(result);
}


/*
 * nvarcharout()
 * converts a NVARCHAR value to a C string.
 *
 * Uses the text to C string conversion function, which is only appropriate
 * if VarChar and text are equivalent types.
 *
 * just use varcharout()
 */


/*
 * nvarcharrecv()
 * converts external binary format to nvarchar
 *
 * just use varcharrecv()
 */


/*
 * nvarcharsend -- convert nvarchar to binary value
 *
 * just use varcharsend()
 */


/*
 * Converts a VARCHAR type to the specified size.
 *
 * maxlen is the typmod, ie, declared length plus VARHDRSZ bytes.
 * isExplicit is true if this is for an explicit cast to varchar(N).
 *
 * Truncation rules: for an explicit cast, silently truncate to the given
 * length; for an implicit cast, raise error unless extra characters are
 * all spaces.  (This is sort-of per SQL: the spec would actually have us
 * raise a "completion condition" for the explicit cast case, but Postgres
 * hasn't got such a concept.)
 */
Datum
nvarchar(PG_FUNCTION_ARGS)
{
	VarChar    *source = PG_GETARG_VARCHAR_PP(0);
	int32		typmod = PG_GETARG_INT32(1);
	bool		isExplicit = PG_GETARG_BOOL(2);
	int32		len,
				maxlen;
	size_t		maxmblen;
	int			i;
	int			charlen;
	char	   *s_data;
	int			perstrlen = 0;

	len = VARSIZE_ANY_EXHDR(source);
	s_data = VARDATA_ANY(source);
	maxlen = typmod - VARHDRSZ;

	/* No work if typmod is invalid or supplied data fits it already */
	if (maxlen < 0 || len <= maxlen)
		PG_RETURN_VARCHAR_P(source);

	/* only reach here if string is too long... */

	/* truncate multibyte string preserving multibyte boundary */
	maxmblen = pg_mbcharcliplen(s_data, len, maxlen);

	charlen = pg_mbstrlen_with_len(s_data, len);

	if (!isExplicit)
	{
		for (i = maxmblen; i < len; i++)
			if (s_data[i] != ' ')
				ereport(ERROR,
						(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
						 errmsg("value too long for type character varying(%d)",
								maxlen)));
	}

	/* Added these because 'Chinese character'::varchar(5) to 'Chinese character'::varchar(3),
	 * display first Chinese character.
	 */
	if (!isExplicit)
	{
		perstrlen = pg_mblen(s_data);
		if (perstrlen > 1)
		{
			int iscomplate = 0;
			bool iscomplate1 = false;

			if (charlen * perstrlen == len)
				iscomplate1 = true;

			iscomplate = maxlen % perstrlen;

			if (iscomplate1 == true)
				maxmblen = maxlen - iscomplate;
			else if (maxlen < maxmblen)
				maxmblen = maxlen;
		}
	}

	PG_RETURN_VARCHAR_P((VarChar *) cstring_to_text_with_len(s_data,
															 maxmblen));
}


/*
 * nvarchartypmodin -- type modifier input function
 *
 * just use varchartypmodin()
 */

/*
 * nvarchartypmodout -- type modifier output function
 *
 * just use varchartypmodout()
 */
