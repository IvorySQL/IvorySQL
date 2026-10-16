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
#include <ctype.h>

#include "postgres.h"
#include "fmgr.h"
#include "varatt.h"
#include "utils/builtins.h"
#include "common/base64.h"
#include "mb/pg_wchar.h"

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
 * ivorysql_utl_encode_text_encode
 *
 * Oracle-compatible UTL_ENCODE.TEXT_ENCODE(buf, enc_charset):
 *   - Convert buf (in the database encoding) to the encoding named by
 *     enc_charset and return the resulting bytes as RAW.
 *   - A NULL/omitted enc_charset means the database encoding (no
 *     conversion, input bytes returned as-is).
 *   - An unknown encoding name and invalid multibyte input raise errors.
 *
 * Maps to: (text, text) -> bytea
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_encode_text_encode);
Datum
ivorysql_utl_encode_text_encode(PG_FUNCTION_ARGS)
{
	text	   *buf;
	char	   *src;
	Size		src_len;
	int			target_encoding;
	char	   *converted;
	Size		conv_len;
	bytea	   *result;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	buf = PG_GETARG_TEXT_PP(0);
	src = VARDATA_ANY(buf);
	src_len = VARSIZE_ANY_EXHDR(buf);

	if (PG_NARGS() > 1 && !PG_ARGISNULL(1))
	{
		char	   *name = text_to_cstring(PG_GETARG_TEXT_PP(1));

		target_encoding = pg_char_to_encoding(name);
		if (target_encoding < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_ENCODE.TEXT_ENCODE: unrecognized character set \"%s\"",
							name)));
	}
	else
		target_encoding = GetDatabaseEncoding();

	/* Reject input that is not valid in the database encoding. */
	pg_verify_mbstr(GetDatabaseEncoding(), (const char *) src, src_len, false);

	converted = (char *) pg_do_encoding_conversion((unsigned char *) src, src_len,
												   GetDatabaseEncoding(),
												   target_encoding);
	conv_len = (converted == src) ? src_len : strlen(converted);

	result = (bytea *) palloc(VARHDRSZ + conv_len);
	SET_VARSIZE(result, VARHDRSZ + conv_len);
	memcpy(VARDATA(result), converted, conv_len);
	if (converted != src)
		pfree(converted);

	PG_RETURN_BYTEA_P(result);
}

/*
 * ivorysql_utl_encode_text_decode
 *
 * Oracle-compatible UTL_ENCODE.TEXT_DECODE(buf, enc_charset):
 *   - Decode buf (bytes in the encoding named by enc_charset) into the
 *     database encoding.
 *   - A NULL/omitted enc_charset means the database encoding (no
 *     conversion).
 *   - Invalid multibyte sequences in the source raise an error.
 *
 * Maps to: (bytea, text) -> text
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_encode_text_decode);
Datum
ivorysql_utl_encode_text_decode(PG_FUNCTION_ARGS)
{
	bytea	   *buf;
	char	   *src;
	Size		src_len;
	int			source_encoding;
	char	   *converted;
	Size		conv_len;
	text	   *result;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	buf = PG_GETARG_BYTEA_PP(0);
	src = (char *) VARDATA_ANY(buf);
	src_len = VARSIZE_ANY_EXHDR(buf);

	if (PG_NARGS() > 1 && !PG_ARGISNULL(1))
	{
		char	   *name = text_to_cstring(PG_GETARG_TEXT_PP(1));

		source_encoding = pg_char_to_encoding(name);
		if (source_encoding < 0)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("UTL_ENCODE.TEXT_DECODE: unrecognized character set \"%s\"",
							name)));
	}
	else
		source_encoding = GetDatabaseEncoding();

	/* Reject input that is not valid in the source encoding. */
	pg_verify_mbstr(source_encoding, src, src_len, false);

	converted = (char *) pg_do_encoding_conversion((unsigned char *) src, src_len,
												   source_encoding,
												   GetDatabaseEncoding());
	conv_len = (converted == src) ? src_len : strlen(converted);

	result = (text *) palloc(VARHDRSZ + conv_len);
	SET_VARSIZE(result, VARHDRSZ + conv_len);
	memcpy(VARDATA(result), converted, conv_len);
	if (converted != src)
		pfree(converted);

	PG_RETURN_TEXT_P(result);
}

/*
 * ivorysql_utl_encode_uuencode
 *
 * Oracle-compatible UTL_ENCODE.UUENCODE(r):
 *   - Classic uuencode: 45-byte chunks, each output line starts with the
 *     (byte count + 32) length character, followed by four 6-bit characters
 *     (value + 32) per three bytes, terminated by LF.  No "begin"/"end"
 *     envelope is produced (consistent with the RAW-returning package
 *     function).  Empty input yields empty output.
 *
 * Maps to: bytea -> bytea
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_encode_uuencode);
Datum
ivorysql_utl_encode_uuencode(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	int			src_len = VARSIZE_ANY_EXHDR(src);
	const unsigned char *s = VARDATA_ANY(src);
	int			nlines = (src_len + 44) / 45;
	int			cap = nlines + ((src_len + 2) / 3) * 4 + (nlines > 0 ? nlines : 0) + VARHDRSZ + 1;
	bytea	   *result = (bytea *) palloc(cap);
	char	   *d = VARDATA(result);
	int			off = 0;

	while (off < src_len)
	{
		int			chunk = Min(45, src_len - off);
		int			i;

		*d++ = (char) (chunk + 32);
		for (i = 0; i < chunk; i += 3)
		{
			unsigned char b0 = s[off + i];
			unsigned char b1 = (i + 1 < chunk) ? s[off + i + 1] : 0;
			unsigned char b2 = (i + 2 < chunk) ? s[off + i + 2] : 0;

			*d++ = (char) ((b0 >> 2) + 32);
			*d++ = (char) ((((b0 & 0x03) << 4) | (b1 >> 4)) + 32);
			*d++ = (char) ((((b1 & 0x0F) << 2) | (b2 >> 6)) + 32);
			*d++ = (char) ((b2 & 0x3F) + 32);
		}
		*d++ = '\n';
		off += chunk;
	}

	SET_VARSIZE(result, VARHDRSZ + (d - VARDATA(result)));
	PG_RETURN_BYTEA_P(result);
}

/*
 * ivorysql_utl_encode_uudecode
 *
 * Oracle-compatible UTL_ENCODE.UUDECODE(r):
 *   - Inverse of UUENCODE: skips whitespace, decodes each length-prefixed
 *     line, and returns the original bytes.  Malformed lines (no length
 *     character, impossible length) raise an error.
 *
 * Maps to: bytea -> bytea
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_encode_uudecode);
Datum
ivorysql_utl_encode_uudecode(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	int			src_len = VARSIZE_ANY_EXHDR(src);
	const unsigned char *s = VARDATA_ANY(src);
	bytea	   *result = (bytea *) palloc(VARHDRSZ + src_len);
	char	   *d = VARDATA(result);
	unsigned char line[64];
	int			nline = 0;
	int			i;

	for (i = 0; i < src_len; i++)
	{
		if (s[i] >= 32 && s[i] <= 63)
		{
			if (nline < 62)
				line[nline++] = s[i];
		}
		else if (s[i] == '\n' && nline > 0)
		{
			int			count = line[0] - 32;
			int			j;
			int			produced = 0;

			if (count < 1 || count > 45 || 1 + ((count + 2) / 3) * 4 > nline)
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
						 errmsg("UTL_ENCODE.UUDECODE: invalid uuencoded data")));

			for (j = 1; j + 3 < nline + 1 && produced < count; j += 4, produced += 3)
			{
				unsigned char c0 = line[j];
				unsigned char c1 = (j + 1 < nline) ? line[j + 1] : 32;
				unsigned char c2 = (j + 2 < nline) ? line[j + 2] : 32;
				unsigned char c3 = (j + 3 < nline) ? line[j + 3] : 32;
				int			take = Min(3, count - produced);

				if (take >= 1)
					*d++ = (char) (((c0 - 32) << 2) | ((c1 - 32) >> 4));
				if (take >= 2)
					*d++ = (char) ((((c1 - 32) & 0x0F) << 4) | ((c2 - 32) >> 2));
				if (take >= 3)
					*d++ = (char) ((((c2 - 32) & 0x03) << 6) | ((c3 - 32) & 0x3F));
			}
			nline = 0;
		}
#ifdef notdef
		/* any other byte (CR, space, ...) is skipped */
#endif
	}

	SET_VARSIZE(result, VARHDRSZ + (d - VARDATA(result)));
	PG_RETURN_BYTEA_P(result);
}

/*
 * ivorysql_utl_encode_quoted_printable_encode
 *
 * Oracle-compatible UTL_ENCODE.QUOTED_PRINTABLE_ENCODE(r):
 *   - RFC 2045 quoted-printable: printable ASCII (plus space) stays bare,
 *     everything else (including '=' and all high bytes) becomes =XX with
 *     upper-case hex.  No soft line breaks are inserted (inputs are short);
 *     adopted Oracle convention.
 *
 * Maps to: bytea -> bytea
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_encode_quoted_printable_encode);
Datum
ivorysql_utl_encode_quoted_printable_encode(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	int			src_len = VARSIZE_ANY_EXHDR(src);
	const unsigned char *s = VARDATA_ANY(src);
	bytea	   *result = (bytea *) palloc(VARHDRSZ + src_len * 3);
	char	   *d = VARDATA(result);
	int			i;

	for (i = 0; i < src_len; i++)
	{
		unsigned char c = s[i];

		if (c == ' ' || (c >= 33 && c <= 60) || (c >= 62 && c <= 126))
			*d++ = (char) c;
		else
		{
			static const char hex[] = "0123456789ABCDEF";

			*d++ = '=';
			*d++ = hex[c >> 4];
			*d++ = hex[c & 0x0F];
		}
	}

	SET_VARSIZE(result, VARHDRSZ + (d - VARDATA(result)));
	PG_RETURN_BYTEA_P(result);
}

/* local hex helpers for quoted-printable decoding */
static bool
qp_isxdigit(unsigned char c)
{
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

static int
qp_hexval(unsigned char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return 0;
}

/*
 * ivorysql_utl_encode_quoted_printable_decode
 *
 * Oracle-compatible UTL_ENCODE.QUOTED_PRINTABLE_DECODE(r):
 *   - Inverse of QUOTED_PRINTABLE_ENCODE: =XX hex escapes decode to bytes
 *     and "=\n" / "=\r\n" soft line breaks are dropped.  A '=' not followed
 *     by two hex digits (after ignoring a soft break) raises an error.
 *
 * Maps to: bytea -> bytea
 */
PG_FUNCTION_INFO_V1(ivorysql_utl_encode_quoted_printable_decode);
Datum
ivorysql_utl_encode_quoted_printable_decode(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	int			src_len = VARSIZE_ANY_EXHDR(src);
	const unsigned char *s = VARDATA_ANY(src);
	bytea	   *result = (bytea *) palloc(VARHDRSZ + src_len);
	char	   *d = VARDATA(result);
	int			i;

	for (i = 0; i < src_len; i++)
	{
		unsigned char c = s[i];

		if (c != '=')
		{
			*d++ = (char) c;
			continue;
		}

		/* soft line break: "=\n" or "=\r\n" */
		if (i + 1 < src_len && s[i + 1] == '\n')
		{
			i += 1;
			continue;
		}
		if (i + 2 < src_len && s[i + 1] == '\r' && s[i + 2] == '\n')
		{
			i += 2;
			continue;
		}

		/* =XX escape */
		if (i + 2 < src_len &&
			qp_isxdigit(s[i + 1]) && qp_isxdigit(s[i + 2]))
		{
			int			hi = qp_hexval(s[i + 1]);
			int			lo = qp_hexval(s[i + 2]);

			*d++ = (char) ((hi << 4) | lo);
			i += 2;
			continue;
		}

		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_ENCODE.QUOTED_PRINTABLE_DECODE: invalid quoted-printable data")));
	}

	SET_VARSIZE(result, VARHDRSZ + (d - VARDATA(result)));
	PG_RETURN_BYTEA_P(result);
}
