
/*----------------------------------------------------------------------------
 *
 *     nchar.c
 *     nchar type for PostgreSQL.
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


PG_FUNCTION_INFO_V1(ncharin);
PG_FUNCTION_INFO_V1(nchar);

/*
 * nchar_input -- common guts of ncharin and ncharrecv
 *
 * s is the input text of length len (may not be null-terminated)
 * atttypmod is the typmod value to apply
 *
 * Note that atttypmod is measured in characters, which
 * is not necessarily the same as the number of bytes.
 *
 * If the input string is too long, raise an error, unless the extra
 * characters are spaces, in which case they're truncated.  (per SQL)
 */
static BpChar *
nchar_input(const char *s, size_t len, int32 atttypmod)
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
			/* Verify that extra characters are spaces, and clip them off */
			size_t		mbmaxlen = pg_mbcharcliplen(s, len, maxlen);
			size_t		j;

			/*
			 * at this point, len is the actual BYTE length of the input
			 * string, maxlen is the max number of CHARACTERS allowed for this
			 * nchar type, mbmaxlen is the length in BYTES of those chars.
			 */
			for (j = mbmaxlen; j < len; j++)
			{
				if (s[j] != ' ')
					ereport(ERROR,
							(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
							 errmsg("value too long for type character(%d)",
									(int) maxlen)));
			}

			/*
			 * Now we set maxlen to the necessary byte length, not the number
			 * of CHARACTERS!
			 */
			maxlen = len = mbmaxlen;
		}
		else
		{
			//size_t		j;
			/*
			 * Now we set maxlen to the necessary byte length, not the number
			 * of CHARACTERS!
			 */
			/*if (nls_length_semantics == NLSLENGTH_BYTE)
			{
				for (j = maxlen; j < len; j++)
				{
					if (s[j] != ' ')
						ereport(ERROR,
								(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
								errmsg("value too long for type character(%d byte)", (int)maxlen)));
				}
			}
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

/*
 * Convert a C string to CHARACTER internal representation.  atttypmod
 * is the declared length of the type plus VARHDRSZ.
 */
Datum
ncharin(PG_FUNCTION_ARGS)
{
	char	   *s = PG_GETARG_CSTRING(0);

#ifdef NOT_USED
	Oid			typelem = PG_GETARG_OID(1);
#endif
	int32		atttypmod = PG_GETARG_INT32(2);
	BpChar	   *result;

	result = nchar_input(s, strlen(s), atttypmod);
	PG_RETURN_BPCHAR_P(result);
}


/*
 * ncharout()
 * converts a NCHAR value to a C string.
 *
 * Uses the text to C string conversion function, which is only appropriate
 * if VarChar and text are equivalent types.
 *
 * just use bpcharout()
 */


/*
 * ncharrecv()
 * converts external binary format to nvarchar
 *
 * just use bpcharrecv()
 */


/*
 * ncharsend -- convert nchar to binary value
 *
 * just use bpcharsend()
 */


/*
 * Converts a CHARACTER type to the specified size.
 *
 * maxlen is the typmod, ie, declared length plus VARHDRSZ bytes.
 * isExplicit is true if this is for an explicit cast to char(N).
 *
 * Truncation rules: for an explicit cast, silently truncate to the given
 * length; for an implicit cast, raise error unless extra characters are
 * all spaces.  (This is sort-of per SQL: the spec would actually have us
 * raise a "completion condition" for the explicit cast case, but Postgres
 * hasn't got such a concept.)
 */
Datum
nchar(PG_FUNCTION_ARGS)
{
	BpChar	   *source = PG_GETARG_BPCHAR_PP(0);
	int32		maxlen = PG_GETARG_INT32(1);
	bool		isExplicit = PG_GETARG_BOOL(2);
	BpChar	   *result;
	int32		len;
	char	   *r;
	char	   *s;
	size_t		i;
	int			charlen;		/* number of characters in the input string +
								 * VARHDRSZ */

	/* No work if typmod is invalid */
	if (maxlen < (int32) VARHDRSZ)
		PG_RETURN_BPCHAR_P(source);

	maxlen -= VARHDRSZ;

	len = VARSIZE_ANY_EXHDR(source);
	s = VARDATA_ANY(source);

	charlen = pg_mbstrlen_with_len(s, len);

	//maxmblen = pg_mbcharcliplen(s, len, maxlen);

	/*if (nls_length_semantics == NLSLENGTH_CHAR)
	{
		if (charlen > maxlen && !isExplicit)
		{
			ereport(ERROR,
				(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
				 errmsg("value too long for type character(%d char)", maxlen)));
		}
	}
	else if (nls_length_semantics == NLSLENGTH_BYTE)
	{
		if (maxmblen > maxlen && !isExplicit)
			ereport(ERROR,
					(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
					 errmsg("value too long for type character(%d byte)", maxlen)));
	}*/

	/* No work if supplied data matches typmod already */
	if (charlen == maxlen)
		PG_RETURN_BPCHAR_P(source);

	if (charlen > maxlen)
	{
		/* Verify that extra characters are spaces, and clip them off */
		size_t		maxmblen;

		maxmblen = pg_mbcharcliplen(s, len, maxlen);

		if (!isExplicit)
		{
			for (i = maxmblen; i < len; i++)
				if (s[i] != ' ')
					ereport(ERROR,
							(errcode(ERRCODE_STRING_DATA_RIGHT_TRUNCATION),
							 errmsg("value too long for type character(%d)",
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


/*
 * nchartypmodin -- type modifier input function
 *
 * just use bpchartypmodin()
 */

/*
 * nchartypmodout -- type modifier output function
 *
 * just use bpchartypmodout()
 */
