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
 * Implementation of Oracle's UTL_ENCODE package.
 * This module is part of ivorysql_ora extension.
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_encode/utl_encode.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"
#include "fmgr.h"
#include "varatt.h"
#include "utils/builtins.h"
#include "common/base64.h"

/*
 * Oracle UTL_ENCODE.BASE64_ENCODE uses 64-character lines (RFC 1521 MIME format).
 * PostgreSQL's built-in encode(bytea, 'base64') uses 76-character lines (RFC 2045),
 * so we implement our own wrapper to match Oracle's line-break convention.
 */
#define UTL_ENCODE_B64_LINE_LEN 64

/*
 * ivorysql_utl_encode_base64_encode
 *
 * Oracle-compatible BASE64_ENCODE implementation:
 *   - Encodes binary (RAW/bytea) input to base64 ASCII bytes
 *   - Inserts a LF (\n) after every 64-character line, including the last
 *   - Empty input returns empty bytea
 *   - NULL input: handled by STRICT modifier in SQL registration
 *
 * Oracle signature: UTL_ENCODE.BASE64_ENCODE(r IN RAW) RETURN RAW
 * Maps to: bytea -> bytea  (RAW is bytea in IvorySQL)
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_encode_base64_encode);
Datum
ivorysql_utl_encode_base64_encode(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	int			src_len = VARSIZE_ANY_EXHDR(src);
	uint8	   *src_data = (uint8 *) VARDATA_ANY(src);
	int			b64_len;
	int			num_lines;
	int			result_len;
	char	   *raw_b64;
	int			encoded_len;
	bytea	   *result;
	char	   *dst;
	char	   *p;
	int			remaining;
	int			chunk;

	/* Empty input: return empty bytea */
	if (src_len == 0)
	{
		result = (bytea *) palloc(VARHDRSZ);
		SET_VARSIZE(result, VARHDRSZ);
		PG_RETURN_BYTEA_P(result);
	}

	/* Calculate raw base64 encoded length (no newlines) */
	b64_len = pg_b64_enc_len(src_len);

	/* Number of output lines: ceil(b64_len / 64) */
	num_lines = (b64_len + UTL_ENCODE_B64_LINE_LEN - 1) / UTL_ENCODE_B64_LINE_LEN;

	/* Total buffer: base64 characters + one LF per line */
	result_len = b64_len + num_lines;

	/* Encode input to raw base64 (no line breaks) */
	raw_b64 = palloc(b64_len + 1);
	encoded_len = pg_b64_encode(src_data, src_len, raw_b64, b64_len);
	if (encoded_len < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("UTL_ENCODE.BASE64_ENCODE: encoding failed")));

	/* Build output: copy 64-char chunks with LF terminator after each */
	result = (bytea *) palloc(VARHDRSZ + result_len);
	dst = VARDATA(result);
	p = raw_b64;
	remaining = encoded_len;

	while (remaining > 0)
	{
		chunk = (remaining >= UTL_ENCODE_B64_LINE_LEN) ?
				UTL_ENCODE_B64_LINE_LEN : remaining;
		memcpy(dst, p, chunk);
		dst += chunk;
		p += chunk;
		remaining -= chunk;
		*dst++ = '\n';
	}

	SET_VARSIZE(result, VARHDRSZ + (dst - VARDATA(result)));
	pfree(raw_b64);

	PG_RETURN_BYTEA_P(result);
}

/*
 * ivorysql_utl_encode_base64_decode
 *
 * Oracle-compatible BASE64_DECODE implementation:
 *   - Decodes base64 ASCII bytes (RAW/bytea) back to binary
 *   - Strips embedded whitespace (\n, \r, \t, space) before decoding,
 *     because Oracle's BASE64_ENCODE inserts LF every 64 chars and
 *     pg_b64_decode() rejects all whitespace characters
 *   - Whitespace-only input returns empty bytea
 *   - Empty input returns empty bytea
 *   - NULL input: handled by STRICT modifier in SQL registration
 *   - Invalid base64 characters (after whitespace stripping) raise ERROR
 *
 * Oracle signature: UTL_ENCODE.BASE64_DECODE(r IN RAW) RETURN RAW
 * Maps to: bytea -> bytea  (RAW is bytea in IvorySQL)
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_encode_base64_decode);
Datum
ivorysql_utl_encode_base64_decode(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	int			src_len = VARSIZE_ANY_EXHDR(src);
	char	   *src_data = VARDATA_ANY(src);
	char	   *clean_buf;
	int			clean_len;
	int			i;
	int			dec_buf_len;
	int			decoded_len;
	bytea	   *result;
	uint8	   *dst;

	/* Empty input: return empty bytea */
	if (src_len == 0)
	{
		result = (bytea *) palloc(VARHDRSZ);
		SET_VARSIZE(result, VARHDRSZ);
		PG_RETURN_BYTEA_P(result);
	}

	/*
	 * Strip whitespace pass: copy only non-whitespace bytes into clean_buf.
	 * pg_b64_decode() rejects whitespace characters, but Oracle's BASE64_ENCODE
	 * inserts LF (\n) after every 64-character line.  We accept \n, \r, \t,
	 * and plain space as legitimate padding whitespace.
	 */
	clean_buf = palloc(src_len);
	clean_len = 0;
	for (i = 0; i < src_len; i++)
	{
		unsigned char c = (unsigned char) src_data[i];

		if (c != '\n' && c != '\r' && c != '\t' && c != ' ')
			clean_buf[clean_len++] = src_data[i];
	}

	/* Whitespace-only input: return empty bytea */
	if (clean_len == 0)
	{
		pfree(clean_buf);
		result = (bytea *) palloc(VARHDRSZ);
		SET_VARSIZE(result, VARHDRSZ);
		PG_RETURN_BYTEA_P(result);
	}

	/* Allocate output buffer (pg_b64_dec_len gives an upper bound) */
	dec_buf_len = pg_b64_dec_len(clean_len);
	result = (bytea *) palloc(VARHDRSZ + dec_buf_len);
	dst = (uint8 *) VARDATA(result);

	decoded_len = pg_b64_decode(clean_buf, clean_len, dst, dec_buf_len);
	pfree(clean_buf);

	if (decoded_len < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_ENCODE.BASE64_DECODE: invalid base64 input")));

	SET_VARSIZE(result, VARHDRSZ + decoded_len);

	PG_RETURN_BYTEA_P(result);
}
