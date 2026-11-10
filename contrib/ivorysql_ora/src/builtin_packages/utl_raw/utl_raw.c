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

	/* reject byte sequences that are invalid in the database encoding */
	pg_verify_mbstr(GetDatabaseEncoding(), data, len, false);

	PG_RETURN_TEXT_P(cstring_to_text_with_len(data, len));
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
		if (sublen < 1)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("SUBSTR: length must be >= 1")));
	}
	else
		sublen = len;

	/*
	 * Oracle counts a negative position backward from the end of r and
	 * raises VALUE_ERROR for pos = 0 or a position beyond the end.
	 */
	if (pos < 0)
		pos = len + pos + 1;
	else if (pos == 0 || pos > len)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("SUBSTR: position 0 or beyond the end of r")));
	if (pos < 1)
		pos = 1;

	if (sublen > len - (pos - 1))
		sublen = len - (pos - 1);
	if (sublen <= 0)
		PG_RETURN_NULL();

	{
		bytea	   *result = (bytea *) palloc(VARHDRSZ + sublen);

		memcpy(VARDATA(result), data + (pos - 1), sublen);
		SET_VARSIZE(result, VARHDRSZ + sublen);
		PG_RETURN_BYTEA_P(result);
	}
}

/*
 * ora_utl_raw_concat - concatenate up to 12 RAW values (Oracle's documented
 * argument range); NULL arguments are skipped.  Oracle raises an error when
 * the concatenated size exceeds the maximum RAW length of 32767 bytes.
 */
#define UTL_RAW_CONCAT_MAX_ARGS		12
#define UTL_RAW_MAX_LENGTH			32767

Datum
ora_utl_raw_concat(PG_FUNCTION_ARGS)
{
	int			nargs = Min(PG_NARGS(), UTL_RAW_CONCAT_MAX_ARGS);
	Size		outlen = 0;
	bytea	   *result;
	char	   *out;
	int			i;

	for (i = 0; i < nargs; i++)
	{
		if (!PG_ARGISNULL(i))
			outlen += VARSIZE_ANY_EXHDR(PG_GETARG_BYTEA_PP(i));
	}

	if (outlen > UTL_RAW_MAX_LENGTH)
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("CONCAT: concatenated size exceeds the maximum RAW length")));

	result = (bytea *) palloc(VARHDRSZ + outlen);
	out = VARDATA(result);
	for (i = 0; i < nargs; i++)
	{
		if (!PG_ARGISNULL(i))
		{
			bytea	   *ri = PG_GETARG_BYTEA_PP(i);

			memcpy(out, VARDATA_ANY(ri), VARSIZE_ANY_EXHDR(ri));
			out += VARSIZE_ANY_EXHDR(ri);
		}
	}
	SET_VARSIZE(result, VARHDRSZ + outlen);
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

	if (n <= 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("COPIES: count must be positive")));
	if (n > 0 && (Size) len > ((MaxAllocSize - VARHDRSZ) / (Size) n))
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("COPIES: result too large")));

	result = (bytea *) palloc(VARHDRSZ + (Size) len * (Size) n);
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
 * Shared bitwise worker.  Oracle accepts operands of different lengths:
 * the shared prefix is combined bytewise and the remaining tail of the
 * longer operand is appended unchanged.
 */
static bytea *
utl_raw_bit_op(bytea *r1, bytea *r2, char op)
{
	int			len1 = VARSIZE_ANY_EXHDR(r1);
	int			len2 = VARSIZE_ANY_EXHDR(r2);
	const char *d1 = VARDATA_ANY(r1);
	const char *d2 = VARDATA_ANY(r2);
	int			shared = len1 < len2 ? len1 : len2;
	int			outlen = len1 > len2 ? len1 : len2;
	bytea	   *result;
	int			i;

	result = (bytea *) palloc(VARHDRSZ + outlen);
	for (i = 0; i < shared; i++)
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
	if (len1 > len2)
		memcpy(VARDATA(result) + shared, d1 + shared, len1 - shared);
	else if (len2 > len1)
		memcpy(VARDATA(result) + shared, d2 + shared, len2 - shared);
	SET_VARSIZE(result, VARHDRSZ + outlen);
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
 * ora_utl_raw_compare - position of the first mismatching byte between two
 * RAW values, compared after right-padding the shorter operand with "pad"
 * (default 0x00, applied cyclically).  Returns the 1-based position, or 0
 * when the (padded) values are equal.
 */
Datum
ora_utl_raw_compare(PG_FUNCTION_ARGS)
{
	bytea	   *r1;
	bytea	   *r2;
	bytea	   *pad;
	int			len1;
	int			len2;
	const char *d1;
	const char *d2;
	const char *pd;
	int			maxlen;
	int			padlen;
	int			i;

	/*
	 * Oracle returns 0 when both operands are NULL, so the function is
	 * not STRICT; single NULL operands are compared as zero length
	 * (i.e. extended with pad to the other side's length).
	 */
	if (PG_ARGISNULL(0) && PG_ARGISNULL(1))
		PG_RETURN_INT32(0);

	pad = (PG_NARGS() > 2 && !PG_ARGISNULL(2)) ? PG_GETARG_BYTEA_PP(2) : NULL;
	r1 = PG_ARGISNULL(0) ? NULL : PG_GETARG_BYTEA_PP(0);
	r2 = PG_ARGISNULL(1) ? NULL : PG_GETARG_BYTEA_PP(1);
	len1 = r1 ? VARSIZE_ANY_EXHDR(r1) : 0;
	len2 = r2 ? VARSIZE_ANY_EXHDR(r2) : 0;
	d1 = r1 ? VARDATA_ANY(r1) : NULL;
	d2 = r2 ? VARDATA_ANY(r2) : NULL;
	maxlen = len1 > len2 ? len1 : len2;

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
			PG_RETURN_INT32(i + 1);
	}
	PG_RETURN_INT32(0);
}

PG_FUNCTION_INFO_V1(ora_utl_raw_translate);
PG_FUNCTION_INFO_V1(ora_utl_raw_overlay);
PG_FUNCTION_INFO_V1(ora_utl_raw_cast_from_binary_integer);
PG_FUNCTION_INFO_V1(ora_utl_raw_cast_to_binary_integer);

/*
 * ora_utl_raw_translate - map each byte of r through from_set -> to_set.
 *
 * Bytes of r not present in from_set pass through unchanged.  A from_set
 * byte beyond the end of to_set has no counterpart, and matching bytes of
 * r are omitted from the result, per Oracle.  (For pad-filled behaviour
 * Oracle provides TRANSLITERATE instead.)
 */
Datum
ora_utl_raw_translate(PG_FUNCTION_ARGS)
{
	bytea	   *r;
	bytea	   *from_set;
	bytea	   *to_set;
	int			rlen;

	/* registered without STRICT: enforce Oracle's argument rules here */
	if (PG_ARGISNULL(0) || PG_ARGISNULL(1) || PG_ARGISNULL(2))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("TRANSLATE: arguments must not be NULL")));

	r = PG_GETARG_BYTEA_PP(0);
	from_set = PG_GETARG_BYTEA_PP(1);
	to_set = PG_GETARG_BYTEA_PP(2);
	if (VARSIZE_ANY_EXHDR(r) == 0 ||
		VARSIZE_ANY_EXHDR(from_set) == 0 ||
		VARSIZE_ANY_EXHDR(to_set) == 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("TRANSLATE: arguments must have non-zero length")));

	rlen = VARSIZE_ANY_EXHDR(r);
	const char *rdata = VARDATA_ANY(r);
	int			flen = VARSIZE_ANY_EXHDR(from_set);
	const char *fdata = VARDATA_ANY(from_set);
	int			tlen = VARSIZE_ANY_EXHDR(to_set);
	const char *tdata = VARDATA_ANY(to_set);
	StringInfoData buf;
	int			i,
				j;

	initStringInfo(&buf);
	for (i = 0; i < rlen; i++)
	{
		unsigned char b = (unsigned char) rdata[i];

		for (j = 0; j < flen; j++)
		{
			if ((unsigned char) fdata[j] == b)
				break;
		}
		if (j >= flen)
			appendStringInfoChar(&buf, b);	/* unmapped: keep */
		else if (j < tlen)
			appendStringInfoChar(&buf, tdata[j]);	/* mapped */
		/* j >= tlen: omitted entirely */
	}
	PG_RETURN_TEXT_P(cstring_to_text_with_len(buf.data, buf.len));
}

/*
 * ora_utl_raw_overlay - overwrite a region of target with overlay bytes.
 *
 * pos is 1-based and must be >= 1; len defaults to the overlay length; a
 * shorter overlay is extended cyclically with pad (default 0x00).  The
 * result length is max(target length, pos-1+len).
 */
Datum
ora_utl_raw_overlay(PG_FUNCTION_ARGS)
{
	bytea	   *ov = PG_GETARG_BYTEA_PP(0);
	bytea	   *target = PG_GETARG_BYTEA_PP(1);
	int			ovlen = VARSIZE_ANY_EXHDR(ov);
	const char *ovdata = VARDATA_ANY(ov);
	int			tlen = VARSIZE_ANY_EXHDR(target);
	const char *tdata = VARDATA_ANY(target);
	int32		pos = PG_GETARG_INT32(2);
	int32		len;
	const char *pdata = NULL;
	int			padlen = 1;
	int			outlen;
	bytea	   *result;
	int			i;

	/* Oracle raises VALUE_ERROR for a NULL or empty overlay_str */
	if (ovlen <= 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("OVERLAY: overlay_str must not be NULL or empty")));

	if (pos < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("OVERLAY: position must be >= 1")));

	if (PG_NARGS() > 3 && !PG_ARGISNULL(3))
	{
		len = PG_GETARG_INT32(3);
		if (len < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("OVERLAY: length must be non-negative")));
	}
	else
		len = ovlen;

	if (PG_NARGS() > 4 && !PG_ARGISNULL(4))
	{
		bytea	   *pad = PG_GETARG_BYTEA_PP(4);

		if (VARSIZE_ANY_EXHDR(pad) > 0)
		{
			pdata = VARDATA_ANY(pad);
			padlen = VARSIZE_ANY_EXHDR(pad);
		}
	}

	/*
	 * Default pad is 0x00 when the argument is omitted, NULL, or an
	 * empty RAW.
	 */
	if (pdata == NULL || padlen <= 0)
	{
		static const char zero = 0;

		pdata = &zero;
		padlen = 1;
	}

	/*
	 * Compute the result size in 64 bits and clamp it to the maximum
	 * allocatable size: large pos/len must not wrap the 32-bit
	 * arithmetic or hand a negative length to palloc.
	 */
	{
		int64		need = (int64) (pos - 1) + (int64) len;

		if (need < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("OVERLAY: result size out of range")));
		outlen = (tlen > need) ? tlen : (int) need;
		if ((Size) outlen > MaxAllocSize)
			ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("OVERLAY: result too large")));
	}

	result = (bytea *) palloc(VARHDRSZ + (Size) outlen);

	/*
	 * Copy target, padding the region between its end and pos with pad
	 * when pos extends past the target (Oracle pads target up to pos).
	 */
	memcpy(VARDATA(result), tdata, tlen);
	for (i = tlen; i < pos - 1 && i < outlen; i++)
		VARDATA(result)[i] = pdata[(i - tlen) % padlen];

	for (i = 0; i < len && (pos - 1) + i < outlen; i++)
	{
		if (i < ovlen)
			VARDATA(result)[pos - 1 + i] = ovdata[i];
		else
			VARDATA(result)[pos - 1 + i] = pdata[(i - ovlen) % padlen];
	}
	SET_VARSIZE(result, VARHDRSZ + (Size) outlen);
	PG_RETURN_BYTEA_P(result);
}

/*
 * Endianness selector shared by the BINARY_INTEGER casts: 1 = big endian,
 * 2 = little endian, 3 = machine endian.
 */
static int
utl_raw_effective_endian(int32 endianness)
{
	if (endianness == 1)
		return 1;
	if (endianness == 2)
		return 2;
	if (endianness == 3)
	{
		static int	machine = 0;

		if (machine == 0)
		{
			uint32		probe = 0x01020304;
			unsigned char first = *((unsigned char *) &probe);

			machine = (first == 0x01) ? 1 : 2;
		}
		return machine;
	}
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("endianness must be 1 (big), 2 (little) or 3 (machine)")));
}

/*
 * ora_utl_raw_cast_from_binary_integer - encode a 32-bit integer as four
 * bytes in the requested byte order.
 */
Datum
ora_utl_raw_cast_from_binary_integer(PG_FUNCTION_ARGS)
{
	int32		n = PG_GETARG_INT32(0);
	int32		endianness = PG_GETARG_INT32(1);
	int			order = utl_raw_effective_endian(endianness);
	bytea	   *result;
	unsigned char *out;
	uint32		u = (uint32) n;

	result = (bytea *) palloc(VARHDRSZ + 4);
	out = (unsigned char *) VARDATA(result);
	if (order == 1)
	{
		out[0] = (u >> 24) & 0xFF;
		out[1] = (u >> 16) & 0xFF;
		out[2] = (u >> 8) & 0xFF;
		out[3] = u & 0xFF;
	}
	else
	{
		out[0] = u & 0xFF;
		out[1] = (u >> 8) & 0xFF;
		out[2] = (u >> 16) & 0xFF;
		out[3] = (u >> 24) & 0xFF;
	}
	SET_VARSIZE(result, VARHDRSZ + 4);
	PG_RETURN_BYTEA_P(result);
}

/*
 * ora_utl_raw_cast_to_binary_integer - decode one to four bytes as a
 * 32-bit integer in the requested byte order.  Fewer than four bytes are
 * sign-extended from the most significant byte; more than four bytes
 * raise VALUE_ERROR.
 */
Datum
ora_utl_raw_cast_to_binary_integer(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(r);
	const char *data = VARDATA_ANY(r);
	int32		endianness = PG_GETARG_INT32(1);
	int			order = utl_raw_effective_endian(endianness);
	uint32		u = 0;
	int			i;

	if (len < 1 || len > 4)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("CAST_TO_BINARY_INTEGER: input must be 1 to 4 bytes")));
	if (order == 1)
	{
		for (i = 0; i < len; i++)
			u = (u << 8) | (unsigned char) data[i];
		/* sign-extend from the most significant byte actually present */
		if (len < 4 && (data[0] & 0x80))
			u |= 0xFFFFFFFFu << (8 * len);
	}
	else
	{
		for (i = len - 1; i >= 0; i--)
			u = (u << 8) | (unsigned char) data[i];
		if (len < 4 && (data[len - 1] & 0x80))
			u |= 0xFFFFFFFFu << (8 * len);
	}
	PG_RETURN_INT32((int32) u);
}

PG_FUNCTION_INFO_V1(ora_utl_raw_cast_from_binary_double);
PG_FUNCTION_INFO_V1(ora_utl_raw_cast_to_binary_double);
PG_FUNCTION_INFO_V1(ora_utl_raw_cast_from_binary_float);
PG_FUNCTION_INFO_V1(ora_utl_raw_cast_to_binary_float);

/*
 * ora_utl_raw_cast_from_binary_double - emit the IEEE-754 bit pattern of a
 * double as eight bytes in the requested byte order.
 */
Datum
ora_utl_raw_cast_from_binary_double(PG_FUNCTION_ARGS)
{
	float8		n = PG_GETARG_FLOAT8(0);
	int32		endianness = PG_GETARG_INT32(1);
	int			order = utl_raw_effective_endian(endianness);
	union
	{
		float8		f;
		uint64		u;
	}			v;
	bytea	   *result;
	unsigned char *out;
	int			i;

	v.f = n;
	result = (bytea *) palloc(VARHDRSZ + 8);
	out = (unsigned char *) VARDATA(result);
	for (i = 0; i < 8; i++)
	{
		int			shift = order == 1 ? (7 - i) : i;

		out[i] = (unsigned char) ((v.u >> (8 * shift)) & 0xFF);
	}
	SET_VARSIZE(result, VARHDRSZ + 8);
	PG_RETURN_BYTEA_P(result);
}

/*
 * ora_utl_raw_cast_to_binary_double - rebuild a double from exactly eight
 * bytes in the requested byte order; any other length raises VALUE_ERROR.
 */
Datum
ora_utl_raw_cast_to_binary_double(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(r);
	const char *data = VARDATA_ANY(r);
	int32		endianness = PG_GETARG_INT32(1);
	int			order = utl_raw_effective_endian(endianness);
	union
	{
		float8		f;
		uint64		u;
	}			v;
	int			i;

	v.u = 0;
	/*
	 * Oracle uses only the first 8 bytes when more are supplied, and
	 * maps a negative zero result to positive zero.
	 */
	if (len < 8)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("CAST_TO_BINARY_DOUBLE: input must be at least 8 bytes")));

	for (i = 0; i < 8; i++)
	{
		int			shift = order == 1 ? (7 - i) : i;

		v.u |= ((uint64) ((unsigned char) data[i])) << (8 * shift);
	}
	if (v.f == 0.0)
		v.u = 0;				/* -0 -> +0 */
	PG_RETURN_FLOAT8(v.f);
}

/*
 * ora_utl_raw_cast_from_binary_float - IEEE-754 single-precision variant,
 * four bytes in the requested byte order.
 */
Datum
ora_utl_raw_cast_from_binary_float(PG_FUNCTION_ARGS)
{
	float4		n = PG_GETARG_FLOAT4(0);
	int32		endianness = PG_GETARG_INT32(1);
	int			order = utl_raw_effective_endian(endianness);
	union
	{
		float4		f;
		uint32		u;
	}			v;
	bytea	   *result;
	unsigned char *out;
	int			i;

	v.f = n;
	result = (bytea *) palloc(VARHDRSZ + 4);
	out = (unsigned char *) VARDATA(result);
	for (i = 0; i < 4; i++)
	{
		int			shift = order == 1 ? (3 - i) : i;

		out[i] = (unsigned char) ((v.u >> (8 * shift)) & 0xFF);
	}
	SET_VARSIZE(result, VARHDRSZ + 4);
	PG_RETURN_BYTEA_P(result);
}

/*
 * ora_utl_raw_cast_to_binary_float - rebuild a float4 from exactly four
 * bytes in the requested byte order.
 */
Datum
ora_utl_raw_cast_to_binary_float(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(r);
	const char *data = VARDATA_ANY(r);
	int32		endianness = PG_GETARG_INT32(1);
	int			order = utl_raw_effective_endian(endianness);
	union
	{
		float4		f;
		uint32		u;
	}			v;
	int			i;

	v.u = 0;
	/*
	 * Oracle uses only the first 4 bytes when more are supplied, and
	 * maps a negative zero result to positive zero.
	 */
	if (len < 4)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("CAST_TO_BINARY_FLOAT: input must be at least 4 bytes")));

	for (i = 0; i < 4; i++)
	{
		int			shift = order == 1 ? (3 - i) : i;

		v.u |= ((uint32) ((unsigned char) data[i])) << (8 * shift);
	}
	if (v.f == 0.0)
		v.u = 0;				/* -0 -> +0 */
	PG_RETURN_FLOAT4(v.f);
}

PG_FUNCTION_INFO_V1(ora_utl_raw_transliterate);

/*
 * ora_utl_raw_transliterate - like TRANSLATE, but bytes whose from_set
 * position has no to_set counterpart are replaced with pad (default 0x00,
 * applied cyclically) instead of being omitted.
 *
 * Defaults per Oracle: a NULL to_set returns r unchanged; a NULL from_set
 * stands for all 256 byte values in ascending order; a NULL or empty pad
 * is 0x00.
 */
Datum
ora_utl_raw_transliterate(PG_FUNCTION_ARGS)
{
	bytea	   *r;
	bytea	   *to_set = NULL;
	bytea	   *from_set = NULL;
	int			tlen = 0;
	int			flen = 256;
	const char *tdata = NULL;
	char		fallback[256];
	const char *fdata = fallback;
	StringInfoData buf;
	const char *pdata = NULL;
	int			padlen = 1;
	int			rlen,
				i,
				j;

	/*
	 * Oracle raises VALUE_ERROR when r is NULL or zero-length.
	 */
	if (PG_ARGISNULL(0) || VARSIZE_ANY_EXHDR(PG_GETARG_BYTEA_PP(0)) == 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("TRANSLITERATE: r must not be NULL or empty")));
	r = PG_GETARG_BYTEA_PP(0);

	if (PG_NARGS() > 1 && !PG_ARGISNULL(1))
	{
		to_set = PG_GETARG_BYTEA_PP(1);
		tdata = VARDATA_ANY(to_set);
		tlen = VARSIZE_ANY_EXHDR(to_set);
	}
	/*
	 * A NULL to_set stands for the NULL string: with the from_set range
	 * padded, every mapped byte falls through to pad, so the result is
	 * r's length filled with pad (0x00 unless given).
	 */
	if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
	{
		from_set = PG_GETARG_BYTEA_PP(2);
		fdata = VARDATA_ANY(from_set);
		flen = VARSIZE_ANY_EXHDR(from_set);
	}

	rlen = VARSIZE_ANY_EXHDR(r);

	if (from_set != NULL && flen <= 0)
	{
		/* an empty from_set has no mappings: return r unchanged */
		PG_RETURN_BYTEA_P(PG_GETARG_BYTEA_PP(0));
	}
	if (from_set == NULL)
	{
		for (i = 0; i < 256; i++)
			fallback[i] = (char) i;
	}

	if (PG_NARGS() > 3 && !PG_ARGISNULL(3))
	{
		bytea	   *pad = PG_GETARG_BYTEA_PP(3);

		if (VARSIZE_ANY_EXHDR(pad) > 0)
		{
			pdata = VARDATA_ANY(pad);
			padlen = VARSIZE_ANY_EXHDR(pad);
		}
	}

	{
		static const char zero = 0;

		if (pdata == NULL)
			pdata = &zero;
	}

	initStringInfo(&buf);
	for (i = 0; i < rlen; i++)
	{
		unsigned char b = (unsigned char) VARDATA_ANY(r)[i];

		for (j = 0; j < flen; j++)
		{
			if ((unsigned char) fdata[j] == b)
				break;
		}
		if (j < tlen)
			appendStringInfoChar(&buf, tdata[j]);
		else if (j < flen)
			appendStringInfoChar(&buf, pdata[j % padlen]);
		else
			appendStringInfoChar(&buf, b);
	}
	PG_RETURN_TEXT_P(cstring_to_text_with_len(buf.data, buf.len));
}

PG_FUNCTION_INFO_V1(ora_utl_raw_xrange);

/*
 * ora_utl_raw_xrange - succession of single bytes from start_byte to
 * end_byte, wrapping through 0xFF back to 0x00; defaults 0x00 and 0xFF.
 */
Datum
ora_utl_raw_xrange(PG_FUNCTION_ARGS)
{
	unsigned char start;
	unsigned char end;
	unsigned char s,
				e;
	bytea	   *result;
	int			i;

	if (PG_NARGS() > 0 && !PG_ARGISNULL(0))
	{
		bytea	   *sb = PG_GETARG_BYTEA_PP(0);

		if (VARSIZE_ANY_EXHDR(sb) != 1)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("XRANGE: start_byte must be a single byte")));
		start = (unsigned char) VARDATA_ANY(sb)[0];
	}
	else
		start = 0x00;

	if (PG_NARGS() > 1 && !PG_ARGISNULL(1))
	{
		bytea	   *eb = PG_GETARG_BYTEA_PP(1);

		if (VARSIZE_ANY_EXHDR(eb) != 1)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("XRANGE: end_byte must be a single byte")));
		end = (unsigned char) VARDATA_ANY(eb)[0];
	}
	else
		end = 0xFF;

	s = start;
	e = end;

	{
		int			count = (e >= s) ? (e - s + 1) : (256 - s + e + 1);

		result = (bytea *) palloc(VARHDRSZ + count);
		for (i = 0; i < count; i++)
			VARDATA(result)[i] = (char) ((s + i) & 0xFF);
		SET_VARSIZE(result, VARHDRSZ + count);
	}
	PG_RETURN_BYTEA_P(result);
}
