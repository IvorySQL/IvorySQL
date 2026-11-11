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

/* value of a hex digit, or -1 if not one */
static int
utl_encode_hexval(unsigned char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	return -1;
}

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

PG_FUNCTION_INFO_V1(ora_utl_encode_qp_encode);
PG_FUNCTION_INFO_V1(ora_utl_encode_qp_decode);

/*
 * QUOTED_PRINTABLE_ENCODE
 *
 * RFC 2045 section 6.7 quoted-printable, with 76-character lines closed by
 * CRLF and '=' soft line breaks.  Oracle documents 76-character lines for
 * this function.
 *
 * Byte handling:
 *   - 0x21-0x7E except '=' pass through literally
 *   - space and tab pass through literally except at end of line or end of
 *     input (RFC 2045 rule 3: transport-padding must be encoded)
 *   - everything else, including '=' itself, becomes "=XX" (uppercase hex)
 */
#define UTL_ENCODE_QP_MAX_LINE 76

Datum
ora_utl_encode_qp_encode(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(src);
	const char *data = VARDATA_ANY(src);
	StringInfoData buf;
	int			linelen = 0;
	int			i;

		initStringInfo(&buf);
	for (i = 0; i < len; i++)
	{
		unsigned char c = (unsigned char) data[i];
		bool		last = (i == len - 1);
		bool		literal = (c >= 0x21 && c <= 0x7E && c != '=')
			|| ((c == ' ' || c == '\t') && !last);

		/*
		 * The '=' of a soft break must fit on the current line, so a
		 * literal may use at most 75 columns and an =XX escape at most
		 * 72; anything beyond that closes the line first.  A space or
		 * tab would otherwise land at the end of a line, so when the
		 * break displaces it, encode it instead.
		 */
		if (literal && linelen > 74)
		{
			appendStringInfoString(&buf, "=\r\n");
			linelen = 0;
		}
		else if (!literal && linelen > 72)
		{
			appendStringInfoString(&buf, "=\r\n");
			linelen = 0;
		}
		else if (!literal && (c == ' ' || c == '\t') && linelen > 72)
		{
			appendStringInfoString(&buf, "=\r\n");
			linelen = 0;
		}

		if (literal)
		{
			appendStringInfoChar(&buf, c);
			linelen++;
		}
		else
		{
			appendStringInfo(&buf, "=%02X", c);
			linelen += 3;
		}
	}
PG_RETURN_BYTEA_P(cstring_to_text_with_len(buf.data, buf.len));
}

/*
 * QUOTED_PRINTABLE_DECODE
 *
 * Decodes "=XX" hex escapes and strips soft line breaks ("=CRLF" or "=LF").
 * An '=' not followed by two hex digits or a line break raises VALUE_ERROR.
 */
Datum
ora_utl_encode_qp_decode(PG_FUNCTION_ARGS)
{
	bytea	   *src = PG_GETARG_BYTEA_PP(0);
	int			len = VARSIZE_ANY_EXHDR(src);
	const char *data = VARDATA_ANY(src);
	StringInfoData buf;
	int			i;

	initStringInfo(&buf);
	for (i = 0; i < len; i++)
	{
		unsigned char c = (unsigned char) data[i];

		if (c != '=')
		{
			appendStringInfoChar(&buf, c);
			continue;
		}

		if (i + 2 < len &&
			utl_encode_hexval((unsigned char) data[i + 1]) >= 0 &&
			utl_encode_hexval((unsigned char) data[i + 2]) >= 0)
		{
			appendStringInfoChar(&buf,
								 (char) ((utl_encode_hexval((unsigned char) data[i + 1]) << 4)
										 | utl_encode_hexval((unsigned char) data[i + 2])));
			i += 2;
		}
		else if (i + 1 < len && data[i + 1] == '\n')
			i++;				/* soft break "=LF" */
		else if (i + 2 < len && data[i + 1] == '\r' && data[i + 2] == '\n')
			i += 2;				/* soft break "=CRLF" */
		else
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("QUOTED_PRINTABLE_DECODE: invalid escape sequence")));
	}

	PG_RETURN_BYTEA_P(cstring_to_text_with_len(buf.data, buf.len));
}

PG_FUNCTION_INFO_V1(ora_utl_encode_text_encode);
PG_FUNCTION_INFO_V1(ora_utl_encode_text_decode);

/*
 * Oracle encoding-scheme constants: NULL = none, 1 = base64, 2 = quoted
 * printable (utl_encode.base64 / utl_encode.quoted_printable in Oracle).
 */
#define UTL_ENCODE_SCHEME_BASE64	1
#define UTL_ENCODE_SCHEME_QP		2

/*
 * ora_utl_encode_text_encode - convert a VARCHAR2 to a target character
 * set and optionally apply an encoding scheme.
 *
 *   TEXT_ENCODE(s, charset DEFAULT NULL, scheme DEFAULT NULL)
 *
 * A NULL charset means the database encoding; scheme NULL sends the raw
 * converted bytes, 1 applies base64, 2 applies quoted-printable.
 */
Datum
ora_utl_encode_text_encode(PG_FUNCTION_ARGS)
{
	bytea	   *raw;

	/* optional args prevent STRICT; reject NULL input explicitly */
	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	{
		text	   *s = PG_GETARG_TEXT_PP(0);
		Datum		encname;

		if (PG_NARGS() > 1 && !PG_ARGISNULL(1))
		{
			char	   *charset = text_to_cstring(PG_GETARG_TEXT_PP(1));

			encname = DirectFunctionCall1(namein, CStringGetDatum(charset));
		}
		else
			encname = DirectFunctionCall1(namein, CStringGetDatum(GetDatabaseEncodingName()));

		raw = (bytea *) DatumGetPointer(DirectFunctionCall2(pg_convert_to,
															PointerGetDatum(s),
															encname));
	}

	if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
	{
		int32		scheme = PG_GETARG_INT32(2);

		if (scheme == UTL_ENCODE_SCHEME_BASE64)
			raw = (bytea *) DatumGetPointer(DirectFunctionCall1(ivorysql_utl_encode_base64_encode,
																PointerGetDatum(raw)));
		else if (scheme == UTL_ENCODE_SCHEME_QP)
			raw = (bytea *) DatumGetPointer(DirectFunctionCall1(ora_utl_encode_qp_encode,
																PointerGetDatum(raw)));
		else
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("TEXT_ENCODE: encoding scheme must be NULL, 1 (base64) or 2 (quoted printable)")));
	}

	PG_RETURN_BYTEA_P(raw);
}

/*
 * ora_utl_encode_text_decode - inverse of TEXT_ENCODE: optionally undo the
 * encoding scheme, then convert the bytes from the given character set
 * into the database encoding.
 */
Datum
ora_utl_encode_text_decode(PG_FUNCTION_ARGS)
{
	text	   *result;

	/* optional args prevent STRICT; reject NULL input explicitly */
	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	{
		bytea	   *raw = PG_GETARG_BYTEA_PP(0);

	if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
	{
		int32		scheme = PG_GETARG_INT32(2);

		if (scheme == UTL_ENCODE_SCHEME_BASE64)
			raw = (bytea *) DatumGetPointer(DirectFunctionCall1(ivorysql_utl_encode_base64_decode,
																PointerGetDatum(raw)));
		else if (scheme == UTL_ENCODE_SCHEME_QP)
			raw = (bytea *) DatumGetPointer(DirectFunctionCall1(ora_utl_encode_qp_decode,
																PointerGetDatum(raw)));
		else
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("TEXT_DECODE: encoding scheme must be NULL, 1 (base64) or 2 (quoted printable)")));
	}

	if (PG_NARGS() > 1 && !PG_ARGISNULL(1))
	{
		char	   *charset = text_to_cstring(PG_GETARG_TEXT_PP(1));

		result = (text *) DatumGetPointer(DirectFunctionCall2(pg_convert_from,
															  PointerGetDatum(raw),
															  DirectFunctionCall1(namein, CStringGetDatum(charset))));
	}
	else
		result = (text *) DatumGetPointer(DirectFunctionCall2(pg_convert_from,
															  PointerGetDatum(raw),
															  DirectFunctionCall1(namein, CStringGetDatum(GetDatabaseEncodingName()))));

	PG_RETURN_TEXT_P(result);
}
