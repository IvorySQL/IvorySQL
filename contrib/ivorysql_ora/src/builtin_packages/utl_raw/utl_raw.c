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
 * Implementation of the representation-conversion routines of Oracle's
 * UTL_RAW package.  This module is part of the ivorysql_ora extension.
 *
 * Oracle's RAW type maps to bytea in IvorySQL, so every routine below reads
 * and writes bytea.  These are the UTL_RAW functions that cannot be written
 * as a plain type cast in PL/iSQL, so they live in C and are registered as
 * sys.utl_raw_* STRICT functions in utl_raw--1.0.sql; the PL/iSQL package
 * wraps them, exactly like UTL_ENCODE and UTL_MATCH.
 *
 *   XRANGE(start_byte, end_byte)
 *       The RAW holding every 1-byte value from start_byte to end_byte,
 *       inclusive, so XRANGE(hextoraw('20'), hextoraw('2F')) is the 16-byte
 *       value 20 21 ... 2F.  Both bounds must be exactly one byte.  A NULL
 *       bound selects the Oracle default, X'00' for start_byte and X'FF' for
 *       end_byte, and an inverted range wraps around the 8-bit space instead
 *       of failing, so XRANGE(hextoraw('FE'), hextoraw('01')) is FE FF 00 01.
 *
 *   CAST_TO_VARCHAR2(r)
 *       Reinterprets the bytes of r as text in the database character set,
 *       the inverse of UTL_RAW.CAST_TO_RAW.  Oracle simply relabels the
 *       bytes; because IvorySQL stores text in a known server encoding we
 *       additionally verify the byte string against that encoding and raise
 *       the usual encoding error when it is not valid, instead of building a
 *       corrupt text value.
 *
 *   CAST_FROM_BINARY_INTEGER(bin, endian)
 *       The 4-byte RAW holding the two's-complement representation of the
 *       32-bit integer bin, most significant byte first for big_endian and
 *       least significant byte first for little_endian.  -1 yields the full
 *       FFFFFFFF pattern.
 *
 *   CAST_TO_BINARY_INTEGER(r, endian)
 *       The inverse: the 32-bit integer encoded by the bytes of r.  As in
 *       Oracle, r may be 1 to 4 bytes long; a shorter RAW is read in
 *       significance order and its bytes become the low-order ones, so the
 *       missing high-order bytes stay zero.  An empty RAW or one longer than
 *       four bytes is reported as an error (ORA-06502).
 *
 * The endian argument selects the byte order and uses the package constants
 * big_endian = 1, little_endian = 2 and machine_endian = 3 declared in
 * utl_raw--1.0.sql.  machine_endian follows the byte order of the server
 * process, so it always names the native order.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "fmgr.h"
#include "mb/pg_wchar.h"
#include "utils/builtins.h"
#include "varatt.h"

/*
 * Endianness selectors.  The values are part of the public package interface
 * (see the CONSTANT declarations in utl_raw--1.0.sql) and must stay in sync.
 */
#define UTL_RAW_BIG_ENDIAN		1
#define UTL_RAW_LITTLE_ENDIAN	2
#define UTL_RAW_MACHINE_ENDIAN	3

/*
 * Decode an endianness selector into "little endian?".
 *
 * machine_endian is resolved against the byte order of the server process, so
 * WORDS_BIGENDIAN (set by configure on a big-endian host) is the only thing
 * that distinguishes it from little_endian.
 */
static bool
utl_raw_is_little_endian(int32 endian)
{
	switch (endian)
	{
		case UTL_RAW_BIG_ENDIAN:
			return false;
		case UTL_RAW_LITTLE_ENDIAN:
			return true;
		case UTL_RAW_MACHINE_ENDIAN:
#ifdef WORDS_BIGENDIAN
			return false;
#else
			return true;
#endif
		default:
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_RAW: endian must be big_endian (1), little_endian (2) or machine_endian (3)")));
			return false;		/* keep the compiler quiet */
	}
}

/*
 * sys.utl_raw_xrange(bytea, bytea) RETURNS bytea
 *
 * XRANGE(start_byte, end_byte): build the inclusive byte range
 * start_byte..end_byte.  A NULL bound selects the Oracle default, X'00' for
 * start_byte and X'FF' for end_byte, and an inverted range wraps around the
 * 8-bit space, so XRANGE(X'FE', X'01') yields FE FF 00 01.  A non-NULL bound
 * must still be a single-byte RAW.
 *
 * The function is intentionally not STRICT: STRICT would short-circuit on a
 * NULL argument and return NULL before the defaults below are applied.
 */
PG_FUNCTION_INFO_V1(utl_raw_xrange);
Datum
utl_raw_xrange(PG_FUNCTION_ARGS)
{
	unsigned char first;
	unsigned char last;
	int			len;
	int			i;
	bytea	   *result;
	unsigned char *out;

	/* start_byte defaults to X'00' when omitted or NULL. */
	if (PG_ARGISNULL(0))
		first = 0x00;
	else
	{
		bytea	   *start = PG_GETARG_BYTEA_PP(0);

		if (VARSIZE_ANY_EXHDR(start) != 1)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_RAW.XRANGE: start_byte must be exactly one byte")));
		first = *(unsigned char *) VARDATA_ANY(start);
	}

	/* end_byte defaults to X'FF' when omitted or NULL. */
	if (PG_ARGISNULL(1))
		last = 0xFF;
	else
	{
		bytea	   *end = PG_GETARG_BYTEA_PP(1);

		if (VARSIZE_ANY_EXHDR(end) != 1)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_RAW.XRANGE: end_byte must be exactly one byte")));
		last = *(unsigned char *) VARDATA_ANY(end);
	}

	/* Inclusive length; masks so an inverted range wraps through X'FF'. */
	len = (int) (((last - first) & 0xFF) + 1);
	result = (bytea *) palloc(VARHDRSZ + len);
	SET_VARSIZE(result, VARHDRSZ + len);
	out = (unsigned char *) VARDATA(result);
	for (i = 0; i < len; i++)
		out[i] = (unsigned char) (first + i);

	PG_RETURN_BYTEA_P(result);
}

/*
 * sys.utl_raw_cast_to_varchar2(bytea) RETURNS text
 *
 * CAST_TO_VARCHAR2(r): reinterpret the bytes of r in the database encoding.
 * pg_any_to_server() validates the byte string against the database encoding
 * and returns it unchanged, raising the usual encoding error when the bytes
 * are not valid.
 */
PG_FUNCTION_INFO_V1(utl_raw_cast_to_varchar2);
Datum
utl_raw_cast_to_varchar2(PG_FUNCTION_ARGS)
{
	bytea	   *raw = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(raw);
	char	   *bytes = VARDATA_ANY(raw);
	char	   *converted;

	converted = pg_any_to_server(bytes, len, GetDatabaseEncoding());

	PG_RETURN_TEXT_P(cstring_to_text_with_len(converted, len));
}

/*
 * sys.utl_raw_cast_from_binary_integer(integer, integer) RETURNS bytea
 *
 * CAST_FROM_BINARY_INTEGER(bin, endian): write the 32-bit two's-complement
 * value of bin into 4 bytes.
 */
PG_FUNCTION_INFO_V1(utl_raw_cast_from_binary_integer);
Datum
utl_raw_cast_from_binary_integer(PG_FUNCTION_ARGS)
{
	int32		value = PG_GETARG_INT32(0);
	int32		endian = PG_GETARG_INT32(1);
	uint32		uvalue = (uint32) value;
	unsigned char bytes[4];
	bytea	   *result;

	if (utl_raw_is_little_endian(endian))
	{
		bytes[0] = (unsigned char) (uvalue & 0xFF);
		bytes[1] = (unsigned char) ((uvalue >> 8) & 0xFF);
		bytes[2] = (unsigned char) ((uvalue >> 16) & 0xFF);
		bytes[3] = (unsigned char) ((uvalue >> 24) & 0xFF);
	}
	else
	{
		bytes[0] = (unsigned char) ((uvalue >> 24) & 0xFF);
		bytes[1] = (unsigned char) ((uvalue >> 16) & 0xFF);
		bytes[2] = (unsigned char) ((uvalue >> 8) & 0xFF);
		bytes[3] = (unsigned char) (uvalue & 0xFF);
	}

	result = (bytea *) palloc(VARHDRSZ + 4);
	SET_VARSIZE(result, VARHDRSZ + 4);
	memcpy(VARDATA(result), bytes, 4);

	PG_RETURN_BYTEA_P(result);
}

/*
 * sys.utl_raw_cast_to_binary_integer(bytea, integer) RETURNS integer
 *
 * CAST_TO_BINARY_INTEGER(r, endian): read back a 32-bit two's-complement
 * integer from the bytes of r.  Oracle accepts a RAW shorter than four bytes
 * and reads the bytes it is given, so 1..4 bytes are accepted; the value keeps
 * them as the low-order bytes and the missing high-order bytes stay zero.  An
 * empty RAW or one longer than four bytes is rejected.
 */
PG_FUNCTION_INFO_V1(utl_raw_cast_to_binary_integer);
Datum
utl_raw_cast_to_binary_integer(PG_FUNCTION_ARGS)
{
	bytea	   *raw = PG_GETARG_BYTEA_PP(0);
	int32		endian = PG_GETARG_INT32(1);
	int			len;
	const unsigned char *bytes;
	uint32		uvalue = 0;
	int			i;

	len = VARSIZE_ANY_EXHDR(raw);
	if (len < 1 || len > 4)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.CAST_TO_BINARY_INTEGER: input RAW must be between 1 and 4 bytes")));

	bytes = (const unsigned char *) VARDATA_ANY(raw);

	/*
	 * Fold the bytes into the value in significance order, which zero-extends a
	 * short RAW on the high side and reproduces the plain 4-byte reads.
	 */
	if (utl_raw_is_little_endian(endian))
	{
		for (i = len - 1; i >= 0; i--)
			uvalue = (uvalue << 8) | bytes[i];
	}
	else
	{
		for (i = 0; i < len; i++)
			uvalue = (uvalue << 8) | bytes[i];
	}

	PG_RETURN_INT32((int32) uvalue);
}
