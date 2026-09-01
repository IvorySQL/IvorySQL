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
 * This module is part of ivorysql_ora extension.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "fmgr.h"
#include "mb/pg_wchar.h"
#include "utils/builtins.h"
#include "utils/numeric.h"
#include "utils/memutils.h"
#include "varatt.h"

/* Functions implemented in C (byte manipulation) */
PG_FUNCTION_INFO_V1(ora_utl_raw_concat);
PG_FUNCTION_INFO_V1(ora_utl_raw_length);
PG_FUNCTION_INFO_V1(ora_utl_raw_reverse);
PG_FUNCTION_INFO_V1(ora_utl_raw_copies);
PG_FUNCTION_INFO_V1(ora_utl_raw_xrange);
PG_FUNCTION_INFO_V1(ora_utl_raw_substr);
PG_FUNCTION_INFO_V1(ora_utl_raw_bit_and);
PG_FUNCTION_INFO_V1(ora_utl_raw_bit_or);
PG_FUNCTION_INFO_V1(ora_utl_raw_bit_xor);
PG_FUNCTION_INFO_V1(ora_utl_raw_bit_complement);
PG_FUNCTION_INFO_V1(ora_utl_raw_compare);
PG_FUNCTION_INFO_V1(ora_utl_raw_translate);
PG_FUNCTION_INFO_V1(ora_utl_raw_cast_to_varchar2);

/*
 * UTL_RAW.CONCAT(r1, r2, ...)
 *
 * Concatenates up to 12 RAW values (the same overloads are registered in
 * the SQL script).  Registered STRICT, so a NULL argument yields NULL;
 * the Oracle documentation does not define NULL handling for CONCAT, so
 * conservative NULL propagation is retained.
 */
Datum
ora_utl_raw_concat(PG_FUNCTION_ARGS)
{
	int64		total = 0;
	bytea	   *result;
	char	   *dst;
	int			i;

	for (i = 0; i < PG_NARGS(); i++)
		total += VARSIZE_ANY_EXHDR(PG_GETARG_BYTEA_PP(i));

	if (total > MaxAllocSize - VARHDRSZ)
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("UTL_RAW.CONCAT: result is too large")));

	result = (bytea *) palloc(VARHDRSZ + total);
	dst = VARDATA(result);

	for (i = 0; i < PG_NARGS(); i++)
	{
		bytea	   *src = PG_GETARG_BYTEA_PP(i);
		int			len = VARSIZE_ANY_EXHDR(src);

		memcpy(dst, VARDATA_ANY(src), len);
		dst += len;
	}

	SET_VARSIZE(result, VARHDRSZ + total);
	PG_RETURN_BYTEA_P(result);
}

/*
 * UTL_RAW.LENGTH(r)
 *
 * Returns the length in bytes of the RAW value.
 */
Datum
ora_utl_raw_length(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);

	PG_RETURN_NUMERIC(int64_to_numeric(VARSIZE_ANY_EXHDR(r)));
}

/*
 * UTL_RAW.REVERSE(r)
 *
 * Reverses the byte sequence of the RAW value.
 */
Datum
ora_utl_raw_reverse(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(r);
	char	   *src = VARDATA_ANY(r);
	bytea	   *result;
	char	   *dst;
	int			i;

	result = (bytea *) palloc(VARHDRSZ + len);
	dst = VARDATA(result);

	for (i = 0; i < len; i++)
		dst[i] = src[len - 1 - i];

	SET_VARSIZE(result, VARHDRSZ + len);
	PG_RETURN_BYTEA_P(result);
}

/*
 * UTL_RAW.COPIES(r, n)
 *
 * Returns the RAW value r repeated n times.  Oracle raises VALUE_ERROR
 * when r is NULL or of zero length, or when n < 1; this implementation
 * rejects those cases, so the SQL wrapper is registered without STRICT.
 */
Datum
ora_utl_raw_copies(PG_FUNCTION_ARGS)
{
	bytea	   *r;
	int32		n;
	int			len;
	bytea	   *result;
	char	   *dst;
	int			i;

	if (PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.COPIES: r must not be NULL or empty")));

	r = PG_GETARG_BYTEA_PP(0);
	len = VARSIZE_ANY_EXHDR(r);

	if (len == 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.COPIES: r must not be NULL or empty")));

	if (PG_ARGISNULL(1))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.COPIES: n must be at least 1")));

	n = PG_GETARG_INT32(1);

	if (n < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.COPIES: n must be at least 1")));

	if ((Size) n * len > MaxAllocSize - VARHDRSZ)
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("UTL_RAW.COPIES: result is too large")));

	result = (bytea *) palloc(VARHDRSZ + (Size) n * len);
	dst = VARDATA(result);

	for (i = 0; i < n; i++)
	{
		memcpy(dst, VARDATA_ANY(r), len);
		dst += len;
	}

	SET_VARSIZE(result, VARHDRSZ + (Size) n * len);
	PG_RETURN_BYTEA_P(result);
}

/*
 * UTL_RAW.XRANGE(start, end)
 *
 * Returns a RAW value containing every byte from start to end, inclusive.
 * Both arguments default to 0 and 255 respectively (a NULL argument is
 * treated as the default); values outside 0..255 are rejected.
 *
 * Deviation from Oracle: Oracle declares the parameters as single-byte
 * RAW values (defaults x'00' and x'FF') and does not document the
 * behavior for an inverted range (start > end); this wrapper takes the
 * bounds as INTEGER byte codes for convenience and returns NULL when
 * start > end.
 */
Datum
ora_utl_raw_xrange(PG_FUNCTION_ARGS)
{
	int			start = PG_ARGISNULL(0) ? 0 : PG_GETARG_INT32(0);
	int			end = PG_ARGISNULL(1) ? 255 : PG_GETARG_INT32(1);
	bytea	   *result;
	int			len;
	int			i;

	if (start < 0 || start > 255 || end < 0 || end > 255)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.XRANGE: start and end must be between 0 and 255")));

	if (start > end)
		PG_RETURN_NULL();

	len = end - start + 1;
	result = (bytea *) palloc(VARHDRSZ + len);
	for (i = 0; i < len; i++)
		VARDATA(result)[i] = (unsigned char) (start + i);

	SET_VARSIZE(result, VARHDRSZ + len);
	PG_RETURN_BYTEA_P(result);
}

/*
 * UTL_RAW.SUBSTR(r, pos [, len])
 *
 * Returns len bytes of the RAW value starting at pos.  Oracle semantics:
 * pos is 1-based (0 is an error), a negative pos counts backwards from
 * the end of the value, and len is optional (default: rest of the value).
 * Oracle raises VALUE_ERROR when pos = 0, when pos is out of range, or
 * when len is less than 1 or exceeds the remaining bytes; a NULL r
 * returns NULL.
 */
Datum
ora_utl_raw_substr(PG_FUNCTION_ARGS)
{
	bytea	   *r;
	int			rlen;
	int32		pos;
	int32		start;
	int32		length;
	bytea	   *result;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		PG_RETURN_NULL();

	r = PG_GETARG_BYTEA_PP(0);
	rlen = VARSIZE_ANY_EXHDR(r);
	pos = PG_GETARG_INT32(1);

	/* Oracle: pos = 0 is invalid */
	if (pos == 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.SUBSTR: position must not be 0")));

	/* Oracle: negative pos counts backwards from the end */
	if (pos < 0)
		start = rlen + pos + 1;
	else
		start = pos;

	if (start < 1 || start > rlen)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.SUBSTR: position is out of range")));

	if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
		length = PG_GETARG_INT32(2);
	else
		length = rlen - start + 1;	/* rest of the value */

	if (length < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.SUBSTR: length must be at least 1")));

	if (length > rlen - start + 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.SUBSTR: length is out of range")));

	result = (bytea *) palloc(VARHDRSZ + length);
	memcpy(VARDATA(result), VARDATA_ANY(r) + (start - 1), length);
	SET_VARSIZE(result, VARHDRSZ + length);

	PG_RETURN_BYTEA_P(result);
}

/* helper for the three binary bitwise functions */
static bytea *
ora_utl_raw_bitwise(PG_FUNCTION_ARGS, int op)
{
	bytea	   *r1 = PG_GETARG_BYTEA_PP(0);
	bytea	   *r2 = PG_GETARG_BYTEA_PP(1);
	int			len1 = VARSIZE_ANY_EXHDR(r1);
	int			len2 = VARSIZE_ANY_EXHDR(r2);
	int			common = Min(len1, len2);
	int			outlen = Max(len1, len2);
	bytea	   *result;
	int			i;

	result = (bytea *) palloc(VARHDRSZ + outlen);

	for (i = 0; i < common; i++)
	{
		unsigned char b1 = (unsigned char) VARDATA_ANY(r1)[i];
		unsigned char b2 = (unsigned char) VARDATA_ANY(r2)[i];

		switch (op)
		{
			case 0:
				VARDATA(result)[i] = (char) (b1 & b2);
				break;
			case 1:
				VARDATA(result)[i] = (char) (b1 | b2);
				break;
			case 2:
				VARDATA(result)[i] = (char) (b1 ^ b2);
				break;
		}
	}

	/*
	 * Oracle: when the operands differ in length, the operation is
	 * terminated after the last byte of the shorter operand and the
	 * unprocessed tail of the longer operand is appended; the result
	 * length equals the longer operand length.
	 */
	if (len1 > len2)
		memcpy(VARDATA(result) + common, VARDATA_ANY(r1) + common, len1 - common);
	else if (len2 > len1)
		memcpy(VARDATA(result) + common, VARDATA_ANY(r2) + common, len2 - common);

	SET_VARSIZE(result, VARHDRSZ + outlen);
	return result;
}

/*
 * UTL_RAW.BIT_AND(r1, r2) / BIT_OR / BIT_XOR
 *
 * Bytewise bitwise operation over two RAW values.  NULL inputs return
 * NULL (the SQL wrappers are registered STRICT); operands of different
 * lengths are supported as documented by Oracle.
 */
Datum
ora_utl_raw_bit_and(PG_FUNCTION_ARGS)
{
	PG_RETURN_BYTEA_P(ora_utl_raw_bitwise(fcinfo, 0));
}

Datum
ora_utl_raw_bit_or(PG_FUNCTION_ARGS)
{
	PG_RETURN_BYTEA_P(ora_utl_raw_bitwise(fcinfo, 1));
}

Datum
ora_utl_raw_bit_xor(PG_FUNCTION_ARGS)
{
	PG_RETURN_BYTEA_P(ora_utl_raw_bitwise(fcinfo, 2));
}

/*
 * UTL_RAW.BIT_COMPLEMENT(r)
 *
 * Bytewise bitwise NOT of the RAW value.
 */
Datum
ora_utl_raw_bit_complement(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(r);
	bytea	   *result;
	int			i;

	result = (bytea *) palloc(VARHDRSZ + len);
	for (i = 0; i < len; i++)
		VARDATA(result)[i] = (char) ~((unsigned char) VARDATA_ANY(r)[i]);

	SET_VARSIZE(result, VARHDRSZ + len);
	PG_RETURN_BYTEA_P(result);
}

/*
 * UTL_RAW.COMPARE(r1, r2 [, pad])
 *
 * Compares two RAW values.  When the lengths differ, the shorter value
 * is padded on the right with the single-byte pad value before the
 * comparison; a NULL pad (the Oracle default) means a single byte 0x00.
 * Returns 0 when the values are equal after padding (including two NULL
 * inputs), otherwise the 1-based position of the first mismatched byte
 * (Oracle semantics).  A NULL input is treated as a zero-length value,
 * which is then padded as usual.
 */
Datum
ora_utl_raw_compare(PG_FUNCTION_ARGS)
{
	bytea	   *r1 = NULL;
	bytea	   *r2 = NULL;
	int			len1 = 0;
	int			len2 = 0;
	int			common;
	unsigned char pad = 0;
	int			i;

	if (!PG_ARGISNULL(0))
	{
		r1 = PG_GETARG_BYTEA_PP(0);
		len1 = VARSIZE_ANY_EXHDR(r1);
	}
	if (!PG_ARGISNULL(1))
	{
		r2 = PG_GETARG_BYTEA_PP(1);
		len2 = VARSIZE_ANY_EXHDR(r2);
	}
	common = Min(len1, len2);

	if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
	{
		bytea	   *p = PG_GETARG_BYTEA_PP(2);
		int			plen = VARSIZE_ANY_EXHDR(p);

		if (plen != 1)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_RAW.COMPARE: pad must be a single byte")));
		pad = (unsigned char) VARDATA_ANY(p)[0];
	}
	else
	{
		/*
		 * Oracle default: when pad is NULL (or omitted), the shorter value
		 * is padded with a single 0x00 byte, so values that differ only in
		 * trailing zero bytes compare equal.
		 */
		pad = 0;
	}

	/* compare the common prefix; on a mismatch return its position */
	for (i = 0; i < common; i++)
	{
		unsigned char b1 = (unsigned char) VARDATA_ANY(r1)[i];
		unsigned char b2 = (unsigned char) VARDATA_ANY(r2)[i];

		if (b1 != b2)
			PG_RETURN_NUMERIC(int64_to_numeric(i + 1));
	}

	/* equal prefixes: compare the padded tail (if any) */
	if (len1 != len2)
	{
		bool		r1_shorter = (len1 < len2);
		int			shorter_len = Min(len1, len2);
		int			longer_len = Max(len1, len2);
		const char *longer_data = r1_shorter ? VARDATA_ANY(r2) : VARDATA_ANY(r1);

		for (i = shorter_len; i < longer_len; i++)
		{
			unsigned char b = (unsigned char) longer_data[i];

			if (b != pad)
				PG_RETURN_NUMERIC(int64_to_numeric(i + 1));
		}
	}

	/* identical, or equal after padding (including both NULL) */
	PG_RETURN_NUMERIC(int64_to_numeric(0));
}

/*
 * UTL_RAW.TRANSLATE(r, from, to)
 *
 * Converts the bytes of r using the mapping from `from` to `to`.  A byte
 * of r that appears at position i of `from` is replaced by byte i of `to`;
 * bytes of `from` without a counterpart in `to` are deleted from the
 * result.  Per Oracle, only the first occurrence of a byte that repeats
 * in `from` is used.
 */
Datum
ora_utl_raw_translate(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	bytea	   *from = PG_GETARG_BYTEA_PP(1);
	bytea	   *to = PG_GETARG_BYTEA_PP(2);
	int			flen = VARSIZE_ANY_EXHDR(from);
	int			tlen = VARSIZE_ANY_EXHDR(to);
	int			rlen = VARSIZE_ANY_EXHDR(r);
	unsigned char map[256];
	bool		del[256];
	bool		seen[256];
	bytea	   *result;
	char	   *dst;
	int			i;

	/* identity map by default */
	for (i = 0; i < 256; i++)
		map[i] = (unsigned char) i;
	memset(del, 0, sizeof(del));
	memset(seen, 0, sizeof(seen));

	for (i = 0; i < flen; i++)
	{
		unsigned char b = (unsigned char) VARDATA_ANY(from)[i];

		/* Oracle: only the first occurrence of a byte in from_set is used */
		if (seen[b])
			continue;
		seen[b] = true;

		if (i < tlen)
			map[b] = (unsigned char) VARDATA_ANY(to)[i];
		else
			del[b] = true;
	}

	result = (bytea *) palloc(VARHDRSZ + rlen);
	dst = VARDATA(result);

	for (i = 0; i < rlen; i++)
	{
		unsigned char b = (unsigned char) VARDATA_ANY(r)[i];

		if (del[b])
			continue;
		*dst++ = (char) map[b];
	}

	SET_VARSIZE(result, VARHDRSZ + (dst - VARDATA(result)));
	PG_RETURN_BYTEA_P(result);
}

/*
 * UTL_RAW.CAST_TO_VARCHAR2(r)
 *
 * Interprets the RAW value as text in the database character set.  The
 * byte sequence is validated against that encoding.
 */
Datum
ora_utl_raw_cast_to_varchar2(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(r);

	pg_verify_mbstr(GetDatabaseEncoding(), VARDATA_ANY(r), len, false);

	PG_RETURN_TEXT_P(cstring_to_text_with_len(VARDATA_ANY(r), len));
}
