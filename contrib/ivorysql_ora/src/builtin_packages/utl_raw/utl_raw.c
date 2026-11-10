/*-------------------------------------------------------------------------
 * Copyright 2026 IvorySQL Global Development Team
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
 * Implementation of Oracle's UTL_RAW package.
 * This module is part of the ivorysql_ora extension.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw.c
 *
 * RAW is represented as bytea; VARCHAR2 as text in the database encoding,
 * matching the existing PL/iSQL CAST_TO_RAW wrapper (convert_to with the
 * database encoding).
 *
 * NULL semantics follow Oracle: every function returns NULL on NULL input
 * except CONCAT, which returns the non-NULL operand when the other is NULL.
 * Length mismatches raise VALUE_ERROR where Oracle does (BIT_* and SUBSTR
 * position checks).
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "varatt.h"
#include "mb/pg_wchar.h"
#include "utils/builtins.h"
#include "utils/numeric.h"

PG_FUNCTION_INFO_V1(ora_utl_raw_cast_to_varchar2);
PG_FUNCTION_INFO_V1(ora_utl_raw_length);
PG_FUNCTION_INFO_V1(ora_utl_raw_substr);
PG_FUNCTION_INFO_V1(ora_utl_raw_concat);
PG_FUNCTION_INFO_V1(ora_utl_raw_copies);
PG_FUNCTION_INFO_V1(ora_utl_raw_reverse);
PG_FUNCTION_INFO_V1(ora_utl_raw_bit_and);
PG_FUNCTION_INFO_V1(ora_utl_raw_bit_or);
PG_FUNCTION_INFO_V1(ora_utl_raw_bit_xor);
PG_FUNCTION_INFO_V1(ora_utl_raw_bit_complement);
PG_FUNCTION_INFO_V1(ora_utl_raw_compare);

/*
 * ora_utl_raw_cast_to_varchar2 - inverse of the PL/iSQL CAST_TO_RAW:
 * interpret the bytes in the database encoding.
 */
Datum
ora_utl_raw_cast_to_varchar2(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(r);
	const char *data = VARDATA_ANY(r);

	PG_RETURN_TEXT_P(pg_do_encoding_conversion(
									 (unsigned char *) data, len,
									 GetDatabaseEncoding(),
									 GetDatabaseEncoding()));
}

/*
 * ora_utl_raw_length - number of bytes in the RAW value.
 */
Datum
ora_utl_raw_length(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);

	PG_RETURN_INT32(VARSIZE_ANY_EXHDR(r));
}

/*
 * ora_utl_raw_substr - extract "len" bytes starting at 1-based "pos".
 *
 * Oracle raises VALUE_ERROR when pos < 1 or len < 0; a position beyond the
 * end of the value returns NULL; a NULL len means "to the end".
 */
Datum
ora_utl_raw_substr(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(r);
	const char *data = VARDATA_ANY(r);
	int32		pos = PG_GETARG_INT32(1);
	int32		sublen;

	if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
	{
		sublen = PG_GETARG_INT32(2);
		if (sublen < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("SUBSTR: length must be non-negative")));
	}
	else
		sublen = len;

	if (pos < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("SUBSTR: position must be >= 1")));

	if (pos > len)
		PG_RETURN_NULL();

	if (sublen > len - (pos - 1))
		sublen = len - (pos - 1);

	{
		bytea	   *result = (bytea *) palloc(VARHDRSZ + sublen);

		memcpy(VARDATA(result), data + (pos - 1), sublen);
		SET_VARSIZE(result, VARHDRSZ + sublen);
		PG_RETURN_BYTEA_P(result);
	}
}

/*
 * ora_utl_raw_concat - concatenate two RAW values.  Oracle returns the
 * non-NULL operand when exactly one input is NULL, so this is not STRICT.
 */
Datum
ora_utl_raw_concat(PG_FUNCTION_ARGS)
{
	bytea	   *r1;
	bytea	   *r2;
	int			len1,
				len2;
	bytea	   *result;

	if (PG_ARGISNULL(0) && PG_ARGISNULL(1))
		PG_RETURN_NULL();
	if (PG_ARGISNULL(0))
		PG_RETURN_BYTEA_P(PG_GETARG_BYTEA_PP(1));
	if (PG_ARGISNULL(1))
		PG_RETURN_BYTEA_P(PG_GETARG_BYTEA_PP(0));

	r1 = PG_GETARG_BYTEA_PP(0);
	r2 = PG_GETARG_BYTEA_PP(1);
	len1 = VARSIZE_ANY_EXHDR(r1);
	len2 = VARSIZE_ANY_EXHDR(r2);

	result = (bytea *) palloc(VARHDRSZ + len1 + len2);
	memcpy(VARDATA(result), VARDATA_ANY(r1), len1);
	memcpy(VARDATA(result) + len1, VARDATA_ANY(r2), len2);
	SET_VARSIZE(result, VARHDRSZ + len1 + len2);
	PG_RETURN_BYTEA_P(result);
}

/*
 * ora_utl_raw_copies - n concatenated copies of r.  n must be non-negative;
 * 0 copies yield an empty RAW.
 */
Datum
ora_utl_raw_copies(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(r);
	int32		n = PG_GETARG_INT32(1);
	bytea	   *result;
	int			i;

	if (n < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("COPIES: count must be non-negative")));

	result = (bytea *) palloc(VARHDRSZ + (size_t) len * n);
	for (i = 0; i < n; i++)
		memcpy(VARDATA(result) + (size_t) len * i, VARDATA_ANY(r), len);
	SET_VARSIZE(result, VARHDRSZ + (size_t) len * n);
	PG_RETURN_BYTEA_P(result);
}

/*
 * ora_utl_raw_reverse - byte order reversal.
 */
Datum
ora_utl_raw_reverse(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(r);
	const char *data = VARDATA_ANY(r);
	bytea	   *result;
	int			i;

	result = (bytea *) palloc(VARHDRSZ + len);
	for (i = 0; i < len; i++)
		VARDATA(result)[i] = data[len - 1 - i];
	SET_VARSIZE(result, VARHDRSZ + len);
	PG_RETURN_BYTEA_P(result);
}

/*
 * Shared bitwise worker: r1 and r2 must have equal length, as Oracle raises
 * VALUE_ERROR on a mismatch rather than truncating silently.
 */
static bytea *
utl_raw_bit_op(bytea *r1, bytea *r2, char op)
{
	int			len1 = VARSIZE_ANY_EXHDR(r1);
	int			len2 = VARSIZE_ANY_EXHDR(r2);
	const char *d1 = VARDATA_ANY(r1);
	const char *d2 = VARDATA_ANY(r2);
	bytea	   *result;
	int			i;

	if (len1 != len2)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("BIT_%c: operands must have equal length", op)));

	result = (bytea *) palloc(VARHDRSZ + len1);
	for (i = 0; i < len1; i++)
	{
		switch (op)
		{
			case '&':
				VARDATA(result)[i] = d1[i] & d2[i];
				break;
			case '|':
				VARDATA(result)[i] = d1[i] | d2[i];
				break;
			case '^':
				VARDATA(result)[i] = d1[i] ^ d2[i];
				break;
		}
	}
	SET_VARSIZE(result, VARHDRSZ + len1);
	return result;
}

Datum
ora_utl_raw_bit_and(PG_FUNCTION_ARGS)
{
	PG_RETURN_BYTEA_P(utl_raw_bit_op(PG_GETARG_BYTEA_PP(0),
									 PG_GETARG_BYTEA_PP(1), '&'));
}

Datum
ora_utl_raw_bit_or(PG_FUNCTION_ARGS)
{
	PG_RETURN_BYTEA_P(utl_raw_bit_op(PG_GETARG_BYTEA_PP(0),
									 PG_GETARG_BYTEA_PP(1), '|'));
}

Datum
ora_utl_raw_bit_xor(PG_FUNCTION_ARGS)
{
	PG_RETURN_BYTEA_P(utl_raw_bit_op(PG_GETARG_BYTEA_PP(0),
									 PG_GETARG_BYTEA_PP(1), '^'));
}

/*
 * ora_utl_raw_bit_complement - one's complement of every byte.
 */
Datum
ora_utl_raw_bit_complement(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(r);
	const char *data = VARDATA_ANY(r);
	bytea	   *result;
	int			i;

	result = (bytea *) palloc(VARHDRSZ + len);
	for (i = 0; i < len; i++)
		VARDATA(result)[i] = ~data[i];
	SET_VARSIZE(result, VARHDRSZ + len);
	PG_RETURN_BYTEA_P(result);
}

/*
 * ora_utl_raw_compare - lexicographic comparison of two RAW values.
 *
 * The shorter value is right-padded with "pad" (default 0x00, applied
 * cyclically) to the longer length before comparing, per Oracle.  Returns
 * -1, 0 or 1.
 */
Datum
ora_utl_raw_compare(PG_FUNCTION_ARGS)
{
	bytea	   *r1 = PG_GETARG_BYTEA_PP(0);
	bytea	   *r2 = PG_GETARG_BYTEA_PP(1);
	bytea	   *pad;
	int			len1 = VARSIZE_ANY_EXHDR(r1);
	int			len2 = VARSIZE_ANY_EXHDR(r2);
	int			maxlen = len1 > len2 ? len1 : len2;
	const char *d1 = VARDATA_ANY(r1);
	const char *d2 = VARDATA_ANY(r2);
	const char *pd;
	int			padlen;
	int			i;

	if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
		pad = PG_GETARG_BYTEA_PP(2);
	else
		pad = NULL;

	if (pad != NULL && VARSIZE_ANY_EXHDR(pad) > 0)
	{
		pd = VARDATA_ANY(pad);
		padlen = VARSIZE_ANY_EXHDR(pad);
	}
	else
	{
		static const char zero = 0;

		pd = &zero;
		padlen = 1;
	}

	for (i = 0; i < maxlen; i++)
	{
		unsigned char b1 = i < len1 ? (unsigned char) d1[i]
			: (unsigned char) pd[i % padlen];
		unsigned char b2 = i < len2 ? (unsigned char) d2[i]
			: (unsigned char) pd[i % padlen];

		if (b1 != b2)
			PG_RETURN_INT32(b1 < b2 ? -1 : 1);
	}
	PG_RETURN_INT32(0);
}
