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
#include "mb/pg_wchar.h"
#include <ctype.h>

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

/*
 * ora_utl_encode_qp_encode
 *
 * Quoted-printable encoding per RFC 2045 section 6.7: bytes outside
 * the printable range are emitted as =XX, lines are wrapped at 76
 * characters with a trailing soft break (=CRLF).
 */
PG_FUNCTION_INFO_V1(ora_utl_encode_qp_encode);
Datum
ora_utl_encode_qp_encode(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	const	   unsigned char *data = (const unsigned char *) VARDATA_ANY(src);
	int			src_len = VARSIZE_ANY_EXHDR(src);
	StringInfoData buf;
	int			col = 0;
	int			i;

	initStringInfo(&buf);

	for (i = 0; i < src_len; i++)
	{
		unsigned char c = data[i];

		if ((c >= 33 && c <= 60) || (c >= 62 && c <= 126))
		{
			appendStringInfoChar(&buf, (char) c);
			col++;
		}
		else
		{
			appendStringInfo(&buf, "=%02X", c);
			col += 3;
		}

		if (col >= 73 && i < src_len - 1)
		{
			appendStringInfoString(&buf, "=\r\n");
			col = 0;
		}
	}

	{
		bytea	   *result = (bytea *) palloc(VARHDRSZ + buf.len);

		memcpy(VARDATA(result), buf.data, buf.len);
		SET_VARSIZE(result, VARHDRSZ + buf.len);
		pfree(buf.data);
		PG_RETURN_BYTEA_P(result);
	}
}

/*
 * ora_utl_encode_qp_decode
 *
 * Inverse of qp_encode: decodes =XX sequences and removes soft
 * line breaks (=CRLF / =LF).
 */
PG_FUNCTION_INFO_V1(ora_utl_encode_qp_decode);
Datum
ora_utl_encode_qp_decode(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	const	   unsigned char *data = (const unsigned char *) VARDATA_ANY(src);
	int			src_len = VARSIZE_ANY_EXHDR(src);
	bytea	   *result;
	unsigned char *dst;
	int			dst_len = 0;
	int			i = 0;

	result = (bytea *) palloc(VARHDRSZ + src_len);
	dst = (unsigned char *) VARDATA(result);

	while (i < src_len)
	{
		if (data[i] == '=' && i + 2 < src_len &&
			isxdigit((unsigned char) data[i + 1]) &&
			isxdigit((unsigned char) data[i + 2]))
		{
			char		hex[3];

			hex[0] = data[i + 1];
			hex[1] = data[i + 2];
			hex[2] = '\0';
			dst[dst_len++] = (unsigned char) strtol(hex, NULL, 16);
			i += 3;
		}
		else if (data[i] == '=' && i + 2 < src_len &&
				 data[i + 1] == '\r' && data[i + 2] == '\n')
		{
			i += 3;				/* soft line break */
		}
		else if (data[i] == '=' && i + 1 < src_len && data[i + 1] == '\n')
		{
			i += 2;				/* soft line break (LF only) */
		}
		else
		{
			dst[dst_len++] = data[i];
			i++;
		}
	}

	SET_VARSIZE(result, VARHDRSZ + dst_len);
	PG_RETURN_BYTEA_P(result);
}

/*
 * ora_utl_encode_text_encode
 *
 * Encode text into the requested character set. charset NULL means
 * the database encoding. encoding 1 additionally applies base64,
 * matching UTL_ENCODE.TEXT_ENCODE's scheme parameter.
 */
PG_FUNCTION_INFO_V1(ora_utl_encode_text_encode);
Datum
ora_utl_encode_text_encode(PG_FUNCTION_ARGS)
{
	text	   *s;
	text	   *charset;
	int			encoding_arg;
	const char *str;
	int			slen;
	int			dest_enc;
	bytea	   *result;
	char	   *converted;
	int			out_len;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();
	s = PG_GETARG_TEXT_PP(0);
	str = VARDATA_ANY(s);
	slen = VARSIZE_ANY_EXHDR(s);

	if (PG_ARGISNULL(1))
		dest_enc = GetDatabaseEncoding();
	else
	{
		charset = PG_GETARG_TEXT_PP(1);
		if (VARSIZE_ANY_EXHDR(charset) > 0)
			dest_enc = pg_char_to_encoding(text_to_cstring(charset));
		else
			dest_enc = GetDatabaseEncoding();
	}

	encoding_arg = PG_ARGISNULL(2) ? 0 : PG_GETARG_INT32(2);

	if (dest_enc < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_ENCODE.TEXT_ENCODE: unknown character set")));

	if (dest_enc == GetDatabaseEncoding())
	{
		converted = str;
		out_len = slen;
	}
	else
	{
		converted = pg_server_to_any(str, slen, dest_enc);
		out_len = strlen(converted);
	}

	if (encoding_arg == 1)
	{
		/* base64-encode the converted bytes */
		int			b64_len = pg_b64_enc_len(out_len);
		char	   *b64 = (char *) palloc(b64_len + 1);
		int			n = pg_b64_encode(converted, out_len, b64, b64_len);

		result = (bytea *) palloc(VARHDRSZ + n);
		memcpy(VARDATA(result), b64, n);
		SET_VARSIZE(result, VARHDRSZ + n);
	}
	else
	{
		result = (bytea *) palloc(VARHDRSZ + out_len);
		memcpy(VARDATA(result), converted, out_len);
		SET_VARSIZE(result, VARHDRSZ + out_len);
	}

	PG_RETURN_BYTEA_P(result);
}

/*
 * ora_utl_encode_text_decode
 *
 * Decode bytes in the given character set back to database-encoding
 * text. encoding 1 means the input bytes are base64.
 */
PG_FUNCTION_INFO_V1(ora_utl_encode_text_decode);
Datum
ora_utl_encode_text_decode(PG_FUNCTION_ARGS)
{
	bytea	   *r;
	text	   *charset;
	int			encoding_arg;
	const	   unsigned char *data;
	int			dlen;
	int			src_enc;
	const char *converted;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();
	r = PG_GETARG_BYTEA_PP(0);
	data = (const unsigned char *) VARDATA_ANY(r);
	dlen = VARSIZE_ANY_EXHDR(r);

	if (PG_ARGISNULL(1))
		src_enc = GetDatabaseEncoding();
	else
	{
		charset = PG_GETARG_TEXT_PP(1);
		if (VARSIZE_ANY_EXHDR(charset) > 0)
			src_enc = pg_char_to_encoding(text_to_cstring(charset));
		else
			src_enc = GetDatabaseEncoding();
	}

	encoding_arg = PG_ARGISNULL(2) ? 0 : PG_GETARG_INT32(2);

	if (src_enc < 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_ENCODE.TEXT_DECODE: unknown character set")));

	if (encoding_arg == 1)
	{
		int			dec_len = pg_b64_dec_len(dlen);
		char	   *dec = (char *) palloc(dec_len + 1);
		int			n = pg_b64_decode((const char *) data, dlen, dec, dec_len);

		if (n < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_ENCODE.TEXT_DECODE: invalid base64 input")));
		converted = pg_any_to_server(dec, n, src_enc);
	}
	else
		converted = pg_any_to_server((const char *) data, dlen, src_enc);

	PG_RETURN_TEXT_P(cstring_to_text(converted));
}

/*
 * ora_utl_raw_cast_to_varchar2
 *
 * Byte-for-byte cast of RAW bytes to VARCHAR2, no encoding conversion.
 */
PG_FUNCTION_INFO_V1(ora_utl_raw_cast_to_varchar2);
Datum
ora_utl_raw_cast_to_varchar2(PG_FUNCTION_ARGS)
{
	bytea	   *r = PG_GETARG_BYTEA_PP(0);
	int			dlen = VARSIZE_ANY_EXHDR(r);
	text	   *result = (text *) palloc(VARHDRSZ + dlen);

	memcpy(VARDATA(result), VARDATA_ANY(r), dlen);
	SET_VARSIZE(result, VARHDRSZ + dlen);

	PG_RETURN_TEXT_P(result);
}

/*
 * ora_utl_encode_mimeheader_decode
 *
 * Decode a single RFC 2047 encoded-word '=?charset?B/Q?payload?=' back
 * to database-encoding text. Implemented in C to avoid PL/iSQL
 * varlena length quirks; non-encoded input passes through unchanged.
 */
PG_FUNCTION_INFO_V1(ora_utl_encode_mimeheader_decode);
Datum
ora_utl_encode_mimeheader_decode(PG_FUNCTION_ARGS)
{
	text	   *buf;
	const char *b;
	int			blen;
	char	   *work = NULL;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();
	buf = PG_GETARG_TEXT_PP(0);
	b = VARDATA_ANY(buf);
	blen = VARSIZE_ANY_EXHDR(buf);
	work = (char *) palloc(blen + 1);
	char	   *p,
			   *p2,
			   *p3,
			   *payload;
	int			payload_len;
	char	   *charset;
	const char *decoded;
	int			dec_len;
	text	   *result;

	memcpy(work, b, blen);
	work[blen] = '\0';

	/* not an encoded-word: pass through unchanged */
	if (blen < 8 || strncmp(work, "=?", 2) != 0)
		PG_RETURN_TEXT_P(cstring_to_text(work));

	p = strchr(work + 2, '?');
	if (p == NULL)
		PG_RETURN_TEXT_P(buf);
	*p = '\0';
	charset = work + 2;

	p2 = strchr(p + 1, '?');	/* the '?' between scheme (B/Q) and payload */
	if (p2 == NULL || *(p2 + 1) == '\0')
		PG_RETURN_TEXT_P(buf);
	payload = p2 + 1;

	/* payload ends at the last "?=" */
	p3 = strrchr(payload, '?');
	if (p3 == NULL || p3 == payload || p3[1] != '=')
		PG_RETURN_TEXT_P(buf);
	payload_len = (int) (p3 - payload);
	payload[payload_len] = '\0';

	if (toupper((unsigned char) *(p2 - 1)) == 'B')
	{
		int			raw_len = pg_b64_dec_len(payload_len);
		char	   *raw = (char *) palloc(raw_len + 1);
		int			n = pg_b64_decode(payload, payload_len, raw, raw_len);

		if (n < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_ENCODE.MIMEHEADER_DECODE: invalid base64 input")));
		decoded = raw;
		dec_len = n;
	}
	else
	{
		/* inline quoted-printable decode of the payload bytes */
		char	   *out = (char *) palloc(payload_len + 1);
		int			out_len = 0;
		int			i = 0;

		while (i < payload_len)
		{
			if (payload[i] == '=' && i + 2 < payload_len &&
				isxdigit((unsigned char) payload[i + 1]) &&
				isxdigit((unsigned char) payload[i + 2]))
			{
				char		hex[3];

				hex[0] = payload[i + 1];
				hex[1] = payload[i + 2];
				hex[2] = '\0';
				out[out_len++] = (char) strtol(hex, NULL, 16);
				i += 3;
			}
			else if (payload[i] == '=' && i + 2 < payload_len &&
					 payload[i + 1] == '\r' && payload[i + 2] == '\n')
				i += 3;
			else if (payload[i] == '=' && i + 1 < payload_len &&
					 payload[i + 1] == '\n')
				i += 2;
			else
				out[out_len++] = payload[i++];
		}

		decoded = out;
		dec_len = out_len;
	}

	{
		int			src_enc = pg_char_to_encoding(charset);

		if (src_enc < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_ENCODE.MIMEHEADER_DECODE: unknown character set \"%s\"", charset)));

		if (src_enc == GetDatabaseEncoding())
		{
			result = (text *) palloc(VARHDRSZ + dec_len);
			memcpy(VARDATA(result), decoded, dec_len);
			SET_VARSIZE(result, VARHDRSZ + dec_len);
		}
		else
			result = cstring_to_text(pg_any_to_server(decoded, dec_len, src_enc));
	}

	PG_RETURN_TEXT_P(result);
}
