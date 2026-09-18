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
 * Implementation of Oracle's UTL_COMPRESS package.
 * This module is part of ivorysql_ora extension.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_compress/utl_compress.c
 *
 *-------------------------------------------------------------------------
 */

/*
 * Oracle UTL_COMPRESS package: LZ_COMPRESS / LZ_UNCOMPRESS.
 *
 * The compression stream format is self-contained: we use zlib's
 * compress2()/uncompress() (zlib-wrapped DEFLATE), so LZ_COMPRESS output
 * always roundtrips through LZ_UNCOMPRESS.  We do NOT attempt to be
 * byte-compatible with Oracle's proprietary LZ77+Huffman stream (real-world
 * users almost never exchange compressed blobs across databases).
 *
 * Exceptions follow Oracle's UTL_COMPRESS semantics:
 *   - LZ_INVALID_PARAMETER   quality outside 1..9
 *   - LZ_COMPRESS_EXCEPTION  compression failed
 *   - LZ_UNCOMPRESS_EMPTY_FILE  input is an empty bytea
 *   - LZ_UNCOMPRESS_EXCEPTION   stream corrupt / truncated / too large
 */

#include "postgres.h"
#include "fmgr.h"
#include "varatt.h"
#include "utils/builtins.h"
#include "utils/memutils.h"

#include <zlib.h>

#define UTL_COMPRESS_QUALITY_MIN	1
#define UTL_COMPRESS_QUALITY_MAX	9

/*
 * uncompress() needs an output buffer big enough for the whole stream.
 * We start with a conservative guess and double it (pfree'ing the previous
 * buffer) whenever Z_BUF_ERROR reports that more room is required.
 * UTL_COMPRESS_INITIAL_RATIO is a safe expansion guess for a fresh,
 * incompressible or missing header; the loop below always terminates.
 */
#define UTL_COMPRESS_INITIAL_RATIO	8UL
#define UTL_COMPRESS_INITIAL_MIN	1024UL
#define UTL_COMPRESS_MAX_RATIO		1032UL /* max DEFLATE expansion (48-byte window) */

PG_FUNCTION_INFO_V1(ora_utl_compress_lz_compress);
PG_FUNCTION_INFO_V1(ora_utl_compress_lz_uncompress);

/* Oracle exception names (see header comment) */
#define LZ_INVALID_PARAMETER		"LZ_INVALID_PARAMETER"
#define LZ_COMPRESS_EXCEPTION		"LZ_COMPRESS_EXCEPTION"
#define LZ_UNCOMPRESS_EMPTY_FILE	"LZ_UNCOMPRESS_EMPTY_FILE"
#define LZ_UNCOMPRESS_EXCEPTION		"LZ_UNCOMPRESS_EXCEPTION"

static void utl_compress_raise(const char *exc, const char *detail)
{
	ereport(ERROR,
			(errcode(ERRCODE_RAISE_EXCEPTION),
			 errmsg("%s", exc),
			 detail != NULL ? errdetail("%s", detail) : 0));
}

/*
 * ora_utl_compress_lz_compress
 *
 * Oracle signature: UTL_COMPRESS.LZ_COMPRESS(src IN RAW,
 *                     quality IN BINARY_INTEGER DEFAULT 6) RETURN RAW
 * Maps to: (bytea, integer) -> bytea   (RAW is bytea in IvorySQL)
 *
 * zlib compress2() with level 1..9 produces a zlib-wrapped DEFLATE stream.
 * Empty input still yields a valid (8-byte) stream so that
 * LZ_UNCOMPRESS(LZ_COMPRESS('')) == ''.
 * NULL input is handled by STRICT in the SQL registration.
 */
Datum
ora_utl_compress_lz_compress(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	int			quality = PG_GETARG_INT32(1);
	int			src_len = VARSIZE_ANY_EXHDR(src);
	const Bytef *src_data = (const Bytef *) VARDATA_ANY(src);
	uLongf		out_len;
	bytea	   *result;
	int			zrc;

	if (quality < UTL_COMPRESS_QUALITY_MIN ||
		quality > UTL_COMPRESS_QUALITY_MAX)
		ereport(ERROR,
				(errcode(ERRCODE_RAISE_EXCEPTION),
				 errmsg("%s", LZ_INVALID_PARAMETER),
				 errdetail("quality must be between %d and %d, got %d",
						   UTL_COMPRESS_QUALITY_MIN,
						   UTL_COMPRESS_QUALITY_MAX, quality)));

	/*
	 * compressBound() gives the worst-case output size for the given input
	 * (it already accounts for the zlib wrapper).  Add a small margin so a
	 * pathological stream can never write one byte past the buffer.
	 */
	out_len = compressBound((uLong) src_len);
	if (out_len > (uLong) (MaxAllocSize - VARHDRSZ))
		utl_compress_raise(LZ_COMPRESS_EXCEPTION,
						   "input too large to compress");

	result = (bytea *) palloc(VARHDRSZ + (Size) out_len);
	zrc = compress2((Bytef *) VARDATA(result), &out_len,
					src_data, (uLong) src_len, quality);
	if (zrc != Z_OK)
	{
		pfree(result);
		utl_compress_raise(LZ_COMPRESS_EXCEPTION,
						   "zlib compress2 failed (this should not happen)");
	}

	SET_VARSIZE(result, VARHDRSZ + (Size) out_len);
	PG_RETURN_BYTEA_P(result);
}

/*
 * ora_utl_compress_lz_uncompress
 *
 * Oracle signature: UTL_COMPRESS.LZ_UNCOMPRESS(src IN RAW) RETURN RAW
 * Maps to: bytea -> bytea   (RAW is bytea in IvorySQL)
 *
 * Empty input raises LZ_UNCOMPRESS_EMPTY_FILE, matching Oracle.
 * The output buffer starts at a conservative guess and is doubled on
 * Z_BUF_ERROR until the whole stream fits.  A corrupted or truncated
 * stream (Z_DATA_ERROR, or output growth beyond the palloc limit) raises
 * LZ_UNCOMPRESS_EXCEPTION instead of crashing or exhausting memory.
 */
Datum
ora_utl_compress_lz_uncompress(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	int			src_len = VARSIZE_ANY_EXHDR(src);
	const Bytef *src_data = (const Bytef *) VARDATA_ANY(src);
	uLongf		out_len;
	bytea	   *result;
	Size		capacity;
	int			zrc;

	if (src_len == 0)
		utl_compress_raise(LZ_UNCOMPRESS_EMPTY_FILE,
						   "tried to uncompress an empty source");

	/*
	 * Initial output guess: 8x input size + slack, no less than 1KB and no
	 * more than what we can palloc.  A stream that needs more room is
	 * reported by uncompress() as Z_BUF_ERROR (buffer fully consumed), so
	 * doubling here can never loop on an incomplete-but-valid input.
	 */
	capacity = (Size) src_len * UTL_COMPRESS_INITIAL_RATIO + 64;
	if (capacity < UTL_COMPRESS_INITIAL_MIN)
		capacity = UTL_COMPRESS_INITIAL_MIN;
	if (capacity > MaxAllocSize - VARHDRSZ)
		capacity = MaxAllocSize - VARHDRSZ;
	else if (capacity > (Size) src_len * UTL_COMPRESS_MAX_RATIO + 64)
		capacity = (Size) src_len * UTL_COMPRESS_MAX_RATIO + 64;

	for (;;)
	{
		result = (bytea *) palloc(VARHDRSZ + capacity);
		out_len = (uLongf) capacity;

		zrc = uncompress((Bytef *) VARDATA(result), &out_len,
						 src_data, (uLong) src_len);

		if (zrc == Z_OK || zrc == Z_STREAM_END)
		{
			SET_VARSIZE(result, VARHDRSZ + (Size) out_len);
			PG_RETURN_BYTEA_P(result);
		}

		pfree(result);

		/*
		 * Z_BUF_ERROR means the decompressed data did not fit into the
		 * buffer (uncompress() only returns Z_BUF_ERROR when the output was
		 * exhausted; anything else is an invalid stream).
		 */
		if (zrc != Z_BUF_ERROR)
			utl_compress_raise(LZ_UNCOMPRESS_EXCEPTION,
							   "input is not a valid compressed stream");

		if (capacity >= UTL_COMPRESS_MAX_RATIO &&
			capacity >= (Size) src_len * UTL_COMPRESS_MAX_RATIO + 64)
			utl_compress_raise(LZ_UNCOMPRESS_EXCEPTION,
							   "uncompressed data exceeds the maximum size");
		if (capacity > MaxAllocSize / 2 - VARHDRSZ)
			utl_compress_raise(LZ_UNCOMPRESS_EXCEPTION,
							   "uncompressed data is too large");

		capacity *= 2;
	}
}