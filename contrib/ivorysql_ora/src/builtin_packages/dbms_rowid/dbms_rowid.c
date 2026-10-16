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
 * Implementation of Oracle's DBMS_ROWID package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides functions for creating, extracting, converting, and verifying
 * Oracle ROWID values.
 *
 * Oracle ROWID formats supported:
 *   - Extended ROWID: 18 base-64 characters
 *     Format: OOOOOOFFFBBBBBBRRR
 *       OOOOOO (6 chars): Data object number (32-bit unsigned)
 *       FFF    (3 chars): Relative file number (16-bit unsigned)
 *       BBBBBB (6 chars): Block number (32-bit unsigned)
 *       RRR    (3 chars): Row number (16-bit unsigned)
 *   - Restricted ROWID: 16 hexadecimal characters (or 18 chars with dots)
 *     Format: BBBBBBBB.RRRR.FFFF
 *       BBBBBBBB (8 chars): Block number (hex)
 *       RRRR     (4 chars): Row number (hex)
 *       FFFF     (4 chars): File number (hex)
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_rowid/dbms_rowid.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"

#define DBMS_ROWID_ROWID_TYPE_RESTRICTED	0
#define DBMS_ROWID_ROWID_TYPE_EXTENDED		1

#define DBMS_ROWID_ROWID_IS_VALID			0
#define DBMS_ROWID_ROWID_IS_INVALID			1

/*
 * Base64 alphabet used by Oracle Extended ROWID:
 * A-Z (0-25), a-z (26-51), 0-9 (52-61), + (62), / (63)
 */
static const char b64_table[] =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static int
b64_val(char c)
{
	if (c >= 'A' && c <= 'Z')
		return c - 'A';
	if (c >= 'a' && c <= 'z')
		return c - 'a' + 26;
	if (c >= '0' && c <= '9')
		return c - '0' + 52;
	if (c == '+')
		return 62;
	if (c == '/')
		return 63;
	return -1;
}

static void
encode_b64(uint32 val, char *buf, int len)
{
	int i;

	for (i = len - 1; i >= 0; i--)
	{
		buf[i] = b64_table[val & 0x3F];
		val >>= 6;
	}
}

static bool
decode_b64(const char *buf, int len, uint32 *val)
{
	uint32 res = 0;
	int i;

	for (i = 0; i < len; i++)
	{
		int v = b64_val(buf[i]);
		if (v < 0)
			return false;
		res = (res << 6) | (uint32) v;
	}
	*val = res;
	return true;
}

/*
 * Helper: parse extended ROWID (18 chars)
 */
static bool
parse_extended_rowid(const char *str, uint32 *obj, uint32 *rfile, uint32 *block, uint32 *row)
{
	if (strlen(str) != 18)
		return false;

	if (!decode_b64(str, 6, obj))
		return false;
	if (!decode_b64(str + 6, 3, rfile))
		return false;
	if (!decode_b64(str + 9, 6, block))
		return false;
	if (!decode_b64(str + 15, 3, row))
		return false;

	return true;
}

/*
 * Helper: parse restricted ROWID
 * Format: BBBBBBBB.RRRR.FFFF (18 chars) or BBBBBBBBRRRRFFFF (16 hex chars)
 */
static bool
parse_restricted_rowid(const char *str, uint32 *block, uint32 *row, uint32 *file)
{
	size_t len = strlen(str);

	if (len == 18 && str[8] == '.' && str[13] == '.')
	{
		unsigned int b, r, f;
		if (sscanf(str, "%8x.%4x.%4x", &b, &r, &f) == 3)
		{
			*block = b;
			*row = r;
			*file = f;
			return true;
		}
	}
	else if (len == 16)
	{
		unsigned int b, r, f;
		if (sscanf(str, "%8x%4x%4x", &b, &r, &f) == 3)
		{
			*block = b;
			*row = r;
			*file = f;
			return true;
		}
	}
	return false;
}

/*
 * dbms_rowid_rowid_create
 *
 * Creates an extended or restricted ROWID string.
 */
PG_FUNCTION_INFO_V1(dbms_rowid_rowid_create);
Datum
dbms_rowid_rowid_create(PG_FUNCTION_ARGS)
{
	int32 rowid_type = PG_GETARG_INT32(0);
	int64 object_number = PG_GETARG_INT64(1);
	int64 relative_fno = PG_GETARG_INT64(2);
	int64 block_number = PG_GETARG_INT64(3);
	int64 row_number = PG_GETARG_INT64(4);
	char buf[32];

	if (rowid_type == DBMS_ROWID_ROWID_TYPE_EXTENDED)
	{
		if (object_number < 0 || object_number > 0xFFFFFFFF ||
			relative_fno < 0 || relative_fno > 0x3FFFF ||
			block_number < 0 || block_number > 0xFFFFFFFF ||
			row_number < 0 || row_number > 0x3FFFF)
		{
			ereport(ERROR,
					(errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
					 errmsg("DBMS_ROWID: input parameter out of range for extended rowid")));
		}

		encode_b64((uint32) object_number, buf, 6);
		encode_b64((uint32) relative_fno, buf + 6, 3);
		encode_b64((uint32) block_number, buf + 9, 6);
		encode_b64((uint32) row_number, buf + 15, 3);
		buf[18] = '\0';
	}
	else if (rowid_type == DBMS_ROWID_ROWID_TYPE_RESTRICTED)
	{
		if (block_number < 0 || block_number > 0xFFFFFFFF ||
			row_number < 0 || row_number > 0xFFFF ||
			relative_fno < 0 || relative_fno > 0xFFFF)
		{
			ereport(ERROR,
					(errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
					 errmsg("DBMS_ROWID: input parameter out of range for restricted rowid")));
		}

		snprintf(buf, sizeof(buf), "%08X.%04X.%04X",
				 (uint32) block_number,
				 (uint32) row_number,
				 (uint32) relative_fno);
	}
	else
	{
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_ROWID: invalid rowid_type: %d (expected 0 for restricted, 1 for extended)",
						rowid_type)));
	}

	PG_RETURN_TEXT_P(cstring_to_text(buf));
}

/*
 * dbms_rowid_rowid_type
 */
PG_FUNCTION_INFO_V1(dbms_rowid_rowid_type);
Datum
dbms_rowid_rowid_type(PG_FUNCTION_ARGS)
{
	text *rowid_text = PG_GETARG_TEXT_PP(0);
	char *str = text_to_cstring(rowid_text);
	uint32 obj, rfile, block, row;

	if (parse_extended_rowid(str, &obj, &rfile, &block, &row))
	{
		pfree(str);
		PG_RETURN_INT32(DBMS_ROWID_ROWID_TYPE_EXTENDED);
	}
	if (parse_restricted_rowid(str, &block, &row, &rfile))
	{
		pfree(str);
		PG_RETURN_INT32(DBMS_ROWID_ROWID_TYPE_RESTRICTED);
	}

	pfree(str);
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("DBMS_ROWID: invalid rowid format")));
}

/*
 * dbms_rowid_rowid_object
 */
PG_FUNCTION_INFO_V1(dbms_rowid_rowid_object);
Datum
dbms_rowid_rowid_object(PG_FUNCTION_ARGS)
{
	text *rowid_text = PG_GETARG_TEXT_PP(0);
	char *str = text_to_cstring(rowid_text);
	uint32 obj, rfile, block, row;

	if (parse_extended_rowid(str, &obj, &rfile, &block, &row))
	{
		pfree(str);
		PG_RETURN_INT64((int64) obj);
	}
	if (parse_restricted_rowid(str, &block, &row, &rfile))
	{
		pfree(str);
		PG_RETURN_INT64(0);
	}

	pfree(str);
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("DBMS_ROWID: invalid rowid format")));
}

/*
 * dbms_rowid_rowid_relative_fno
 */
PG_FUNCTION_INFO_V1(dbms_rowid_rowid_relative_fno);
Datum
dbms_rowid_rowid_relative_fno(PG_FUNCTION_ARGS)
{
	text *rowid_text = PG_GETARG_TEXT_PP(0);
	char *str = text_to_cstring(rowid_text);
	uint32 obj, rfile, block, row;

	if (parse_extended_rowid(str, &obj, &rfile, &block, &row))
	{
		pfree(str);
		PG_RETURN_INT64((int64) rfile);
	}
	if (parse_restricted_rowid(str, &block, &row, &rfile))
	{
		pfree(str);
		PG_RETURN_INT64((int64) rfile);
	}

	pfree(str);
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("DBMS_ROWID: invalid rowid format")));
}

/*
 * dbms_rowid_rowid_block_number
 */
PG_FUNCTION_INFO_V1(dbms_rowid_rowid_block_number);
Datum
dbms_rowid_rowid_block_number(PG_FUNCTION_ARGS)
{
	text *rowid_text = PG_GETARG_TEXT_PP(0);
	char *str = text_to_cstring(rowid_text);
	uint32 obj, rfile, block, row;

	if (parse_extended_rowid(str, &obj, &rfile, &block, &row))
	{
		pfree(str);
		PG_RETURN_INT64((int64) block);
	}
	if (parse_restricted_rowid(str, &block, &row, &rfile))
	{
		pfree(str);
		PG_RETURN_INT64((int64) block);
	}

	pfree(str);
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("DBMS_ROWID: invalid rowid format")));
}

/*
 * dbms_rowid_rowid_row_number
 */
PG_FUNCTION_INFO_V1(dbms_rowid_rowid_row_number);
Datum
dbms_rowid_rowid_row_number(PG_FUNCTION_ARGS)
{
	text *rowid_text = PG_GETARG_TEXT_PP(0);
	char *str = text_to_cstring(rowid_text);
	uint32 obj, rfile, block, row;

	if (parse_extended_rowid(str, &obj, &rfile, &block, &row))
	{
		pfree(str);
		PG_RETURN_INT64((int64) row);
	}
	if (parse_restricted_rowid(str, &block, &row, &rfile))
	{
		pfree(str);
		PG_RETURN_INT64((int64) row);
	}

	pfree(str);
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("DBMS_ROWID: invalid rowid format")));
}

/*
 * dbms_rowid_rowid_to_absolute_fno
 */
PG_FUNCTION_INFO_V1(dbms_rowid_rowid_to_absolute_fno);
Datum
dbms_rowid_rowid_to_absolute_fno(PG_FUNCTION_ARGS)
{
	text *rowid_text = PG_GETARG_TEXT_PP(0);
	char *str = text_to_cstring(rowid_text);
	uint32 obj, rfile, block, row;

	if (parse_extended_rowid(str, &obj, &rfile, &block, &row) ||
		parse_restricted_rowid(str, &block, &row, &rfile))
	{
		pfree(str);
		PG_RETURN_INT64((int64) rfile);
	}

	pfree(str);
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("DBMS_ROWID: invalid rowid format")));
}

/*
 * dbms_rowid_rowid_to_extended
 */
PG_FUNCTION_INFO_V1(dbms_rowid_rowid_to_extended);
Datum
dbms_rowid_rowid_to_extended(PG_FUNCTION_ARGS)
{
	text *rowid_text = PG_GETARG_TEXT_PP(0);
	char *str = text_to_cstring(rowid_text);
	char buf[32];
	uint32 obj, rfile, block, row;

	if (parse_extended_rowid(str, &obj, &rfile, &block, &row))
	{
		/* Already extended, return original string */
		pfree(str);
		PG_RETURN_TEXT_P(rowid_text);
	}
	if (parse_restricted_rowid(str, &block, &row, &rfile))
	{
		pfree(str);
		encode_b64(0, buf, 6);
		encode_b64(rfile, buf + 6, 3);
		encode_b64(block, buf + 9, 6);
		encode_b64(row, buf + 15, 3);
		buf[18] = '\0';
		PG_RETURN_TEXT_P(cstring_to_text(buf));
	}

	pfree(str);
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("DBMS_ROWID: invalid rowid format")));
}

/*
 * dbms_rowid_rowid_to_restricted
 */
PG_FUNCTION_INFO_V1(dbms_rowid_rowid_to_restricted);
Datum
dbms_rowid_rowid_to_restricted(PG_FUNCTION_ARGS)
{
	text *rowid_text = PG_GETARG_TEXT_PP(0);
	char *str = text_to_cstring(rowid_text);
	char buf[32];
	uint32 obj, rfile, block, row;

	if (parse_restricted_rowid(str, &block, &row, &rfile))
	{
		/* Already restricted */
		pfree(str);
		PG_RETURN_TEXT_P(rowid_text);
	}
	if (parse_extended_rowid(str, &obj, &rfile, &block, &row))
	{
		pfree(str);
		snprintf(buf, sizeof(buf), "%08X.%04X.%04X",
				 block,
				 (uint32) (row & 0xFFFF),
				 (uint32) (rfile & 0xFFFF));
		PG_RETURN_TEXT_P(cstring_to_text(buf));
	}

	pfree(str);
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("DBMS_ROWID: invalid rowid format")));
}

/*
 * dbms_rowid_rowid_verify
 */
PG_FUNCTION_INFO_V1(dbms_rowid_rowid_verify);
Datum
dbms_rowid_rowid_verify(PG_FUNCTION_ARGS)
{
	text *rowid_text = PG_GETARG_TEXT_PP(0);
	char *str = text_to_cstring(rowid_text);
	uint32 obj, rfile, block, row;

	if (parse_extended_rowid(str, &obj, &rfile, &block, &row) ||
		parse_restricted_rowid(str, &block, &row, &rfile))
	{
		pfree(str);
		PG_RETURN_INT32(DBMS_ROWID_ROWID_IS_VALID);
	}

	pfree(str);
	PG_RETURN_INT32(DBMS_ROWID_ROWID_IS_INVALID);
}
