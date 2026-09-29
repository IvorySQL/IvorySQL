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
 * Fixed-width integer conversions for UTL_RAW.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw_integer.c
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "varatt.h"

#define UTL_RAW_BIG_ENDIAN       1
#define UTL_RAW_LITTLE_ENDIAN    2
#define UTL_RAW_MACHINE_ENDIAN   3
#define UTL_RAW_INTEGER_BYTES    4

PG_FUNCTION_INFO_V1(ora_utl_raw_cast_from_binary_integer);
PG_FUNCTION_INFO_V1(ora_utl_raw_cast_to_binary_integer);

/* Return true for little-endian encoding, rejecting invalid selectors. */
static bool
utl_raw_integer_little_endian(FunctionCallInfo fcinfo)
{
	int32		endianess;

	endianess = PG_GETARG_INT32(1);
	switch (endianess)
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
					 errmsg("invalid UTL_RAW endianess: %d", endianess),
					 errhint("Use big_endian (1), little_endian (2), or machine_endian (3).")));
	}

	pg_unreachable();
}

/*
 * UTL_RAW.CAST_FROM_BINARY_INTEGER
 *
 * Convert a signed 32-bit integer to its four-byte RAW representation in the
 * requested byte order.
 */
Datum
ora_utl_raw_cast_from_binary_integer(PG_FUNCTION_ARGS)
{
	uint32		value;
	bool		little_endian;
	bytea	   *result;
	unsigned char *bytes;
	int			i;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		PG_RETURN_NULL();

	little_endian = utl_raw_integer_little_endian(fcinfo);
	/* Conversion to unsigned is defined modulo 2^32, also for negatives. */
	value = (uint32) PG_GETARG_INT32(0);
	result = (bytea *) palloc(VARHDRSZ + UTL_RAW_INTEGER_BYTES);
	SET_VARSIZE(result, VARHDRSZ + UTL_RAW_INTEGER_BYTES);
	bytes = (unsigned char *) VARDATA(result);

	for (i = 0; i < UTL_RAW_INTEGER_BYTES; i++)
	{
		int			shift = (little_endian ? i : 3 - i) * 8;

		bytes[i] = (unsigned char) (value >> shift);
	}

	PG_RETURN_BYTEA_P(result);
}

/*
 * UTL_RAW.CAST_TO_BINARY_INTEGER
 *
 * Decode a one-to-four-byte RAW value using the requested byte order and
 * return the resulting signed 32-bit integer.
 */
Datum
ora_utl_raw_cast_to_binary_integer(PG_FUNCTION_ARGS)
{
	bytea	   *raw;
	const unsigned char *bytes;
	uint32		value = 0;
	int64		signed_value;
	int			len;
	bool		little_endian;
	int			i;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		PG_RETURN_NULL();

	little_endian = utl_raw_integer_little_endian(fcinfo);
	raw = PG_GETARG_BYTEA_PP(0);

	/* Short RAWs are zero-extended, as observed on Oracle 23.26.3. */
	len = VARSIZE_ANY_EXHDR(raw);
	if (len == 0)
	{
		PG_FREE_IF_COPY(raw, 0);
		PG_RETURN_NULL();
	}
	if (len > UTL_RAW_INTEGER_BYTES)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_RAW.CAST_TO_BINARY_INTEGER accepts at most 4 bytes")));

	bytes = (const unsigned char *) VARDATA_ANY(raw);
	for (i = 0; i < len; i++)
	{
		int			shift = (little_endian ? i : len - 1 - i) * 8;

		value |= ((uint32) bytes[i]) << shift;
	}

	/* Avoid implementation-defined conversion of uint32 > INT32_MAX. */
	signed_value = (int64) value;
	if (value > (uint32) PG_INT32_MAX)
		signed_value -= INT64CONST(4294967296);

	PG_FREE_IF_COPY(raw, 0);
	PG_RETURN_INT32((int32) signed_value);
}
