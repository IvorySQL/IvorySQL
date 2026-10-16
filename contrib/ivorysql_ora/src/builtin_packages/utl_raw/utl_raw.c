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
 * Implementation of the byte-manipulation core of Oracle's UTL_RAW package.
 * This module is part of the ivorysql_ora extension.
 *
 * Oracle's RAW type maps to bytea in IvorySQL, so every routine below reads
 * and writes bytea.  The C entry points implement the byte-level semantics
 * and are registered STRICT (a NULL argument yields NULL).  Where Oracle
 * gives a NULL argument a special meaning the PL/iSQL wrappers in
 * utl_raw--1.0.sql resolve it before calling C, through a shorter or a
 * pad-carrying overload:
 *   - SUBSTR's "len" (NULL means "through the end of r");
 *   - COMPARE's "pad" (NULL means pad with 0x00) and the two-NULL case,
 *     which Oracle defines as equal (0);
 *   - CONCAT's arguments (NULL values are skipped, so the wrapper calls the
 *     2-argument C entry once per supplied value);
 *   - OVERLAY's "len" (NULL means length(overlay_str)) and "pad" (NULL means
 *     0x00).
 *
 * Behaviour notes (Oracle Database 19c, UTL_RAW in the PL/SQL Packages and
 * Types Reference):
 *
 *   LENGTH(r)               octet length of r.
 *
 *   SUBSTR(r, pos, len)     1-based byte slice.  A negative pos counts
 *                           backwards from the end of r (-1 is the last byte)
 *                           and a pos of 0 is read as 1.  Oracle raises
 *                           ORA-06502 (VALUE_ERROR) when pos resolves before
 *                           the first byte, when pos is past the end of r, when
 *                           len is less than 1, and when len runs past the end
 *                           of r.  A NULL len means "through the end of r".
 *
 *   CONCAT(r1..r12)         the non-NULL arguments concatenated in order.
 *                           Every argument defaults to NULL; the result is
 *                           NULL only when all of them are NULL.
 *
 *   COMPARE(r1, r2, pad)    the 1-based position of the first byte that
 *                           differs, or 0 when the arguments are equal.  When
 *                           the arguments differ in length the shorter one is
 *                           virtually extended with the bytes of pad (a NULL
 *                           pad means 0x00, the Oracle default); pad repeats
 *                           if it is shorter than the length difference.
 *
 *   BIT_AND/OR/XOR(r1, r2)  byte-wise logical operation over the longer
 *                           operand, with the shorter one padded -- X'FF' for
 *                           BIT_AND, X'00' for BIT_OR and BIT_XOR, as Oracle
 *                           does.
 *
 *   BIT_COMPLEMENT(r)       byte-wise one's complement (~b for every byte).
 *
 *   REVERSE(r)              the bytes of r in reverse order.
 *
 *   OVERLAY(overlay_str, target, pos, len, pad)
 *                           replaces len bytes of target starting at pos with
 *                           the bytes of overlay_str.  Bytes of target outside
 *                           the overlaid range are kept; a pos past the end of
 *                           target and a len longer than overlay_str are both
 *                           filled with the first byte of pad (0x00 by default;
 *                           Oracle repeats that one byte rather than cycling
 *                           through pad).  A len of 0 leaves target unchanged;
 *                           the PL/iSQL wrapper turns a NULL len into
 *                           length(overlay_str) and a NULL pad into 0x00.
 *
 *   TRANSLATE(r, from, to)  every byte of r found in from is replaced by the
 *                           byte at the same position in to.  When to is
 *                           shorter than from the matching input bytes are
 *                           dropped; when to is longer the extra bytes are
 *                           ignored.  The first occurrence wins when from
 *                           contains duplicate bytes.
 *
 *   COPIES(r, n)            n concatenated copies of r.  Oracle returns NULL
 *                           when n is less than 1 (its copy loop never runs).
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "fmgr.h"
#include "utils/builtins.h"
#include "utils/memutils.h"
#include "varatt.h"

PG_FUNCTION_INFO_V1(utl_raw_length);
PG_FUNCTION_INFO_V1(utl_raw_substr);
PG_FUNCTION_INFO_V1(utl_raw_substr_len);
PG_FUNCTION_INFO_V1(utl_raw_concat);
PG_FUNCTION_INFO_V1(utl_raw_compare);
PG_FUNCTION_INFO_V1(utl_raw_compare_pad);
PG_FUNCTION_INFO_V1(utl_raw_bit_and);
PG_FUNCTION_INFO_V1(utl_raw_bit_or);
PG_FUNCTION_INFO_V1(utl_raw_bit_xor);
PG_FUNCTION_INFO_V1(utl_raw_bit_complement);
PG_FUNCTION_INFO_V1(utl_raw_reverse);
PG_FUNCTION_INFO_V1(utl_raw_overlay);
PG_FUNCTION_INFO_V1(utl_raw_overlay_pad);
PG_FUNCTION_INFO_V1(utl_raw_translate);
PG_FUNCTION_INFO_V1(utl_raw_copies);

/*
 * Allocate a result bytea of the given payload length.  The body is zeroed so
 * that callers which only fill part of the buffer (TRANSLATE drops bytes) do
 * not need their own memset.
 */
static bytea *
raw_new(int len)
{
	bytea	   *result = (bytea *) palloc0(VARHDRSZ + len);

	SET_VARSIZE(result, VARHDRSZ + len);
	return result;
}

/*
 * Shared implementation of the 2-argument (has_len == false) and 3-argument
 * (has_len == true) SUBSTR variants.  Oracle reads a pos of 0 as 1 and raises
 * ORA-06502 (VALUE_ERROR) when pos resolves before the first byte, when pos is
 * past the end of the RAW, when len is below one, and when len runs past the
 * end of the RAW.
 */
static bytea *
raw_substr(bytea *r, int32 pos, int32 len, bool has_len)
{
	int64		rlen = (int64) VARSIZE_ANY_EXHDR(r);
	const char *data = VARDATA_ANY(r);
	int64		start;
	int64		end;
	int64		outlen;
	bytea	   *result;

	if (pos == 0)
		pos = 1;

	if (pos > 0)
		start = pos;
	else
		start = rlen + (int64) pos + 1;

	if (start < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.SUBSTR: position %d is before the start of the RAW",
						pos)));

	if (start > rlen)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.SUBSTR: position %d is past the end of the RAW",
						pos)));

	if (has_len && len < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.SUBSTR: length must be greater than zero")));

	if (has_len && start + (int64) len - 1 > rlen)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.SUBSTR: length %d runs past the end of the RAW",
						len)));

	if (has_len)
		end = start + (int64) len - 1;
	else
		end = rlen;

	outlen = end - start + 1;
	result = raw_new((int) outlen);
	memcpy(VARDATA(result), data + (start - 1), outlen);
	return result;
}

/*
 * sys.utl_raw_length(bytea) RETURNS integer
 *
 * Number of bytes in the RAW.
 */
Datum
utl_raw_length(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);

	PG_RETURN_INT32((int32) VARSIZE_ANY_EXHDR(r));
}

/*
 * sys.utl_raw_substr(bytea, integer) RETURNS bytea
 *
 * SUBSTR without a length: everything from pos through the end of the RAW.
 */
Datum
utl_raw_substr(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int32		pos = PG_GETARG_INT32(1);
	bytea	   *result = raw_substr(r, pos, 0, false);

	if (result == NULL)
		PG_RETURN_NULL();

	PG_RETURN_BYTEA_P(result);
}

/*
 * sys.utl_raw_substr(bytea, integer, integer) RETURNS bytea
 *
 * SUBSTR with an explicit length.  The PL/iSQL wrapper routes here whenever
 * len is not NULL; a NULL len uses the 2-argument variant above.
 */
Datum
utl_raw_substr_len(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int32		pos = PG_GETARG_INT32(1);
	int32		len = PG_GETARG_INT32(2);
	bytea	   *result = raw_substr(r, pos, len, true);

	if (result == NULL)
		PG_RETURN_NULL();

	PG_RETURN_BYTEA_P(result);
}

/*
 * sys.utl_raw_concat(bytea, bytea) RETURNS bytea
 *
 * r1 followed by r2.
 */
Datum
utl_raw_concat(PG_FUNCTION_ARGS)
{
	bytea	   *r1 = PG_GETARG_BYTEA_PP(0);
	bytea	   *r2 = PG_GETARG_BYTEA_PP(1);
	int			len1 = (int) VARSIZE_ANY_EXHDR(r1);
	int			len2 = (int) VARSIZE_ANY_EXHDR(r2);
	int64		total = (int64) len1 + len2;
	bytea	   *result;

	if (total > (int64) (MaxAllocSize - VARHDRSZ))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("UTL_RAW.CONCAT: result size exceeds the maximum allowed")));

	result = raw_new((int) total);
	memcpy(VARDATA(result), VARDATA_ANY(r1), len1);
	memcpy(VARDATA(result) + len1, VARDATA_ANY(r2), len2);

	PG_RETURN_BYTEA_P(result);
}

/*
 * Shared comparison used by COMPARE with and without a pad RAW.  padlen == 0
 * means "pad with 0x00".
 */
static int32
raw_compare(const char *d1, int len1, const char *d2, int len2,
			const char *pad, int padlen)
{
	int			minlen = Min(len1, len2);
	int			i;

	for (i = 0; i < minlen; i++)
	{
		if ((unsigned char) d1[i] != (unsigned char) d2[i])
			return i + 1;
	}

	if (len1 == len2)
		return 0;

	/*
	 * One RAW is a prefix of the other.  The trailing bytes of the longer one
	 * are compared against pad, repeated as needed.  With padlen == 0 the
	 * expression below yields 0x00 without a separate branch.
	 */
	{
		const char *longer = (len1 > len2) ? d1 : d2;
		int			maxlen = Max(len1, len2);

		for (i = minlen; i < maxlen; i++)
		{
			unsigned char p = (padlen > 0) ?
				(unsigned char) pad[(i - minlen) % padlen] : 0;

			if ((unsigned char) longer[i] != p)
				return i + 1;
		}
	}

	return 0;
}

/*
 * sys.utl_raw_compare(bytea, bytea) RETURNS integer
 *
 * COMPARE without a pad RAW: the shorter operand is padded with 0x00.
 */
Datum
utl_raw_compare(PG_FUNCTION_ARGS)
{
	bytea	   *r1 = PG_GETARG_BYTEA_PP(0);
	bytea	   *r2 = PG_GETARG_BYTEA_PP(1);

	PG_RETURN_INT32(raw_compare(VARDATA_ANY(r1), (int) VARSIZE_ANY_EXHDR(r1),
								VARDATA_ANY(r2), (int) VARSIZE_ANY_EXHDR(r2),
								NULL, 0));
}

/*
 * sys.utl_raw_compare(bytea, bytea, bytea) RETURNS integer
 *
 * COMPARE with an explicit pad RAW.
 */
Datum
utl_raw_compare_pad(PG_FUNCTION_ARGS)
{
	bytea	   *r1 = PG_GETARG_BYTEA_PP(0);
	bytea	   *r2 = PG_GETARG_BYTEA_PP(1);
	bytea	   *pad = PG_GETARG_BYTEA_PP(2);

	PG_RETURN_INT32(raw_compare(VARDATA_ANY(r1), (int) VARSIZE_ANY_EXHDR(r1),
								VARDATA_ANY(r2), (int) VARSIZE_ANY_EXHDR(r2),
								VARDATA_ANY(pad),
								(int) VARSIZE_ANY_EXHDR(pad)));
}

/*
 * Shared implementation of BIT_AND (op 0), BIT_OR (op 1) and BIT_XOR (op 2).
 *
 * Oracle does not require the operands to have the same length: the shorter
 * one is padded -- with X'FF' for BIT_AND (so the extra bytes keep the longer
 * operand) and with X'00' for BIT_OR and BIT_XOR -- and the result is as long
 * as the longer operand.
 */
static bytea *
raw_bitwise(bytea *r1, bytea *r2, int op)
{
	int			len1 = (int) VARSIZE_ANY_EXHDR(r1);
	int			len2 = (int) VARSIZE_ANY_EXHDR(r2);
	const unsigned char *d1 = (const unsigned char *) VARDATA_ANY(r1);
	const unsigned char *d2 = (const unsigned char *) VARDATA_ANY(r2);
	unsigned char pad = (op == 0) ? (unsigned char) 0xFF : (unsigned char) 0x00;
	int			len = Max(len1, len2);
	bytea	   *result;
	unsigned char *dst;
	int			i;

	result = raw_new(len);
	dst = (unsigned char *) VARDATA(result);
	for (i = 0; i < len; i++)
	{
		unsigned char b1 = (i < len1) ? d1[i] : pad;
		unsigned char b2 = (i < len2) ? d2[i] : pad;

		if (op == 0)
			dst[i] = b1 & b2;
		else if (op == 1)
			dst[i] = b1 | b2;
		else
			dst[i] = b1 ^ b2;
	}

	return result;
}

/*
 * sys.utl_raw_bit_and(bytea, bytea) RETURNS bytea
 */
Datum
utl_raw_bit_and(PG_FUNCTION_ARGS)
{
	PG_RETURN_BYTEA_P(raw_bitwise(PG_GETARG_BYTEA_PP(0),
								  PG_GETARG_BYTEA_PP(1), 0));
}

/*
 * sys.utl_raw_bit_or(bytea, bytea) RETURNS bytea
 */
Datum
utl_raw_bit_or(PG_FUNCTION_ARGS)
{
	PG_RETURN_BYTEA_P(raw_bitwise(PG_GETARG_BYTEA_PP(0),
								  PG_GETARG_BYTEA_PP(1), 1));
}

/*
 * sys.utl_raw_bit_xor(bytea, bytea) RETURNS bytea
 */
Datum
utl_raw_bit_xor(PG_FUNCTION_ARGS)
{
	PG_RETURN_BYTEA_P(raw_bitwise(PG_GETARG_BYTEA_PP(0),
								  PG_GETARG_BYTEA_PP(1), 2));
}

/*
 * sys.utl_raw_bit_complement(bytea) RETURNS bytea
 */
Datum
utl_raw_bit_complement(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = (int) VARSIZE_ANY_EXHDR(r);
	const unsigned char *src = (const unsigned char *) VARDATA_ANY(r);
	bytea	   *result = raw_new(len);
	unsigned char *dst = (unsigned char *) VARDATA(result);
	int			i;

	for (i = 0; i < len; i++)
		dst[i] = (unsigned char) ~src[i];

	PG_RETURN_BYTEA_P(result);
}

/*
 * sys.utl_raw_reverse(bytea) RETURNS bytea
 */
Datum
utl_raw_reverse(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = (int) VARSIZE_ANY_EXHDR(r);
	const char *src = VARDATA_ANY(r);
	bytea	   *result = raw_new(len);
	char	   *dst = VARDATA(result);
	int			i;

	for (i = 0; i < len; i++)
		dst[i] = src[len - 1 - i];

	PG_RETURN_BYTEA_P(result);
}

/*
 * Shared implementation of the 4- and 5-argument OVERLAY entry points.  The
 * arguments follow Oracle's list (overlay_str, target, pos, len); padlen == 0
 * means "fill with 0x00".  The caller resolves a NULL len to the length of
 * overlay_str, so len is always a real byte count here.
 */
static bytea *
raw_overlay(bytea *overlay_str, bytea *target, int32 pos, int32 len,
			const char *pad, int padlen)
{
	int			olen = (int) VARSIZE_ANY_EXHDR(overlay_str);
	int			tlen = (int) VARSIZE_ANY_EXHDR(target);
	const char *odata = VARDATA_ANY(overlay_str);
	const char *tdata = VARDATA_ANY(target);
	int64		start;
	int64		outlen;
	bytea	   *result;
	char	   *dst;
	char		fill;
	int64		i;

	if (pos < 1)
		pos = 1;
	if (len < 0)
		len = 0;

	start = (int64) pos - 1;

	/*
	 * The overlaid window is [pos, pos + len - 1]; the result is as long as
	 * target or the window, whichever reaches further.
	 */
	if (len == 0)
		outlen = tlen;
	else
		outlen = Max((int64) tlen, start + (int64) len);

	if (outlen > (int64) (MaxAllocSize - VARHDRSZ))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("UTL_RAW.OVERLAY: result size exceeds the maximum allowed")));

	result = raw_new((int) outlen);
	dst = VARDATA(result);

	if (tlen > 0)
		memcpy(dst, tdata, tlen);

	/*
	 * The gap between the end of target and the window, and the window bytes
	 * overlay_str does not cover, are both filled with the first byte of pad
	 * (0x00 when pad is absent).  Oracle repeats that one byte rather than
	 * cycling through pad, and it fills the gap instead of leaving it at 0x00.
	 */
	fill = (padlen > 0) ? pad[0] : (char) 0x00;

	if (len > 0)
	{
		for (i = tlen; i < start; i++)
			dst[i] = fill;

		for (i = 0; i < len; i++)
		{
			if (i < (int64) olen)
				dst[start + i] = odata[i];
			else
				dst[start + i] = fill;
		}
	}

	return result;
}

/*
 * sys.utl_raw_overlay(bytea, bytea, integer, integer) RETURNS bytea
 *
 * OVERLAY without an explicit pad RAW: the filler byte is 0x00.
 */
Datum
utl_raw_overlay(PG_FUNCTION_ARGS)
{
	PG_RETURN_BYTEA_P(raw_overlay(PG_GETARG_BYTEA_PP(0),
								  PG_GETARG_BYTEA_PP(1),
								  PG_GETARG_INT32(2),
								  PG_GETARG_INT32(3),
								  NULL, 0));
}

/*
 * sys.utl_raw_overlay_pad(bytea, bytea, integer, integer, bytea) RETURNS bytea
 *
 * OVERLAY with an explicit pad RAW.
 */
Datum
utl_raw_overlay_pad(PG_FUNCTION_ARGS)
{
	bytea	   *pad = PG_GETARG_BYTEA_PP(4);

	PG_RETURN_BYTEA_P(raw_overlay(PG_GETARG_BYTEA_PP(0),
								  PG_GETARG_BYTEA_PP(1),
								  PG_GETARG_INT32(2),
								  PG_GETARG_INT32(3),
								  VARDATA_ANY(pad),
								  (int) VARSIZE_ANY_EXHDR(pad)));
}

/*
 * sys.utl_raw_translate(bytea, bytea, bytea) RETURNS bytea
 */
Datum
utl_raw_translate(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	bytea	   *from = PG_GETARG_BYTEA_PP(1);
	bytea	   *to = PG_GETARG_BYTEA_PP(2);
	int			rlen = (int) VARSIZE_ANY_EXHDR(r);
	int			fromlen = (int) VARSIZE_ANY_EXHDR(from);
	int			tolen = (int) VARSIZE_ANY_EXHDR(to);
	const unsigned char *src = (const unsigned char *) VARDATA_ANY(r);
	const unsigned char *fsrc = (const unsigned char *) VARDATA_ANY(from);
	const unsigned char *tsrc = (const unsigned char *) VARDATA_ANY(to);
	bytea	   *result = raw_new(rlen);
	unsigned char *dst = (unsigned char *) VARDATA(result);
	int			map[256];
	int			outlen = 0;
	int			i;

	/* map[b] is the position of the first b in from, or -1 if absent. */
	for (i = 0; i < 256; i++)
		map[i] = -1;
	for (i = 0; i < fromlen; i++)
	{
		unsigned char b = fsrc[i];

		if (map[b] < 0)
			map[b] = i;
	}

	for (i = 0; i < rlen; i++)
	{
		unsigned char b = src[i];
		int			idx = map[b];

		if (idx < 0)
			dst[outlen++] = b;	/* not translated */
		else if (idx < tolen)
			dst[outlen++] = tsrc[idx];
		/* else: no replacement byte, drop the input byte */
	}

	SET_VARSIZE(result, VARHDRSZ + outlen);

	PG_RETURN_BYTEA_P(result);
}

/*
 * sys.utl_raw_copies(bytea, integer) RETURNS bytea
 */
Datum
utl_raw_copies(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int32		n = PG_GETARG_INT32(1);
	int			rlen = (int) VARSIZE_ANY_EXHDR(r);
	const char *data = VARDATA_ANY(r);
	bytea	   *result;
	char	   *dst;
	int			i;

	/* Oracle returns NULL when n is not positive. */
	if (n < 1)
		PG_RETURN_NULL();

	/* Nothing to copy; also avoids an n-iteration loop over an empty RAW. */
	if (rlen == 0)
		PG_RETURN_BYTEA_P(raw_new(0));

	if ((int64) rlen * n > (int64) (MaxAllocSize - VARHDRSZ))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("UTL_RAW.COPIES: result size exceeds the maximum allowed")));

	result = raw_new((int) ((int64) rlen * n));
	dst = VARDATA(result);
	for (i = 0; i < n; i++)
		memcpy(dst + (int64) i * rlen, data, rlen);

	PG_RETURN_BYTEA_P(result);
}
