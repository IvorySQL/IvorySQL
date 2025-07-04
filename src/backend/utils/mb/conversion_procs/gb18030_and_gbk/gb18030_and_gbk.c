/* ------------------------------------------------
 *
 * File: gb18030_and_gbk.c
 *
 * Abstract:
 * 		This file was add for compatable windows use gb18030 as server_encoding,
 * 		cause the default codepage was 936(gbk) on windows,without this conversion it will not
 * 		work right on windows.
 *
 * Authored by huawenbo@highgo.com, 20231101.
 *
 * Copyright:
 * Copyright (c) 2009-2023, HighGo Software Co.,Ltd. All rights reserved.
 *
 * Identification:
 *		src/backend/utils/mb/conversion_procs/gb18030_and_gbk
 *
 *-------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "mb/pg_wchar.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(gbk_to_gb18030);
PG_FUNCTION_INFO_V1(gb18030_to_gbk);
static int pg_gb18030_verifychar(const unsigned char *s, int len);
static int pg_gbk_str_validation(const unsigned char *s, int len);

PG_FUNCTION_INFO_V1(gbk_to_gb18030_2);
PG_FUNCTION_INFO_V1(gb18030_to_gbk_2);
static int pg_gb18030_verifychar_2(const unsigned char *s, int len);
static int pg_gbk_str_validation_2(const unsigned char *s, int len);

static int
pg_gbk_str_validation(const unsigned char *s, int len)
{
	const unsigned char *start = s;

	while (len > 0)
	{
		int l;

		/* fast path for ASCII-subset characters */
		if (!IS_HIGHBIT_SET(*s))
		{
			if (*s == '\0')
				break;
			l = 1;
		}
		else
		{
			l = pg_gb18030_verifychar(s, len);
			if (l == -1 )
				break;
			else if(l == 4)
			{
				/* if the gbk character was identified 4-byte cahrracter,throw error */
				ereport(ERROR,(errcode(ERRCODE_UNTRANSLATABLE_CHARACTER)),
			 	errmsg("character with byte sequence 0x%02x 0x%02x 0x%02x 0x%02x in encoding GB18030 has no equivalent in encoding GBK",(unsigned char)s[0],(unsigned char)s[1],(unsigned char)s[2],(unsigned char)s[3]));
				break;
			}
		}
		s += l;
		len -= l;
	}

	return s - start;
}

static int
pg_gb18030_verifychar(const unsigned char *s, int len)
{
	int l;

	if (!IS_HIGHBIT_SET(*s))
		l = 1; /* ASCII */
	else if (len >= 4 && *(s + 1) >= 0x30 && *(s + 1) <= 0x39)
	{
		/* Should be 4-byte, validate remaining bytes */
		if (*s >= 0x81 && *s <= 0xfe &&
			*(s + 2) >= 0x81 && *(s + 2) <= 0xfe &&
			*(s + 3) >= 0x30 && *(s + 3) <= 0x39)
			l = 4;
		else
			l = -1;
	}
	// else if (len >= 2 && *s >= 0x81 && *s <= 0xfe)
	else if (len >= 2 && *s >= 0x80 && *s <= 0xfe)
	{
		/* Should be 2-byte, validate */
		if ((*(s + 1) >= 0x40 && *(s + 1) <= 0x7e) ||
			(*(s + 1) >= 0x80 && *(s + 1) <= 0xfe))
			l = 2;
		else
			l = -1;
	}
	else
		l = -1;
	return l;
}

Datum
gbk_to_gb18030(PG_FUNCTION_ARGS)
{
	unsigned char *src = (unsigned char *) PG_GETARG_CSTRING(2);
	unsigned char *dest = (unsigned char *) PG_GETARG_CSTRING(3);
	int			len = PG_GETARG_INT32(4);
	int			converted;

	CHECK_ENCODING_CONVERSION_ARGS(PG_GBK, PG_GB18030);

	converted = pg_gbk_str_validation((unsigned const char *)src, len);
	if (converted != len)
		elog(ERROR,"converted length not equal src length!");
	memcpy(dest,src,len);
	dest[len] = '\0';
	PG_RETURN_INT32(converted);
}

Datum
gb18030_to_gbk(PG_FUNCTION_ARGS)
{
	unsigned char *src = (unsigned char *) PG_GETARG_CSTRING(2);
	unsigned char *dest = (unsigned char *) PG_GETARG_CSTRING(3);
	int			len = PG_GETARG_INT32(4);
	int			converted;

	CHECK_ENCODING_CONVERSION_ARGS(PG_GB18030, PG_GBK);

	converted = pg_gbk_str_validation((unsigned const char *)src, len);
	if (converted != len)
		elog(ERROR, "converted length not equal src length!");
	memcpy(dest, src, len);
	dest[len] = '\0';
	PG_RETURN_INT32(converted);
}

static int
pg_gbk_str_validation_2(const unsigned char *s, int len)
{
	const unsigned char *start = s;

	while (len > 0)
	{
		int l;

		/* fast path for ASCII-subset characters */
		if (!IS_HIGHBIT_SET(*s))
		{
#if 0
			if (*s == '\0')
				break;
#endif

			l = 1;
		}
		else
		{
			l = pg_gb18030_verifychar_2(s, len);
			if (l == -1 )
				break;
			else if(l == 4)
			{
				/* if the gbk character was identified 4-byte cahrracter,throw error */
				ereport(ERROR,(errcode(ERRCODE_UNTRANSLATABLE_CHARACTER)),
			 	errmsg("character with byte sequence 0x%02x 0x%02x 0x%02x 0x%02x in encoding GB18030 has no equivalent in encoding GBK",(unsigned char)s[0],(unsigned char)s[1],(unsigned char)s[2],(unsigned char)s[3]));
				break;
			}
		}
		s += l;
		len -= l;
	}

	return s - start;
}

static int
pg_gb18030_verifychar_2(const unsigned char *s, int len)
{
	int l;

	if (!IS_HIGHBIT_SET(*s))
		l = 1; /* ASCII */
	else if (len >= 4 && *(s + 1) >= 0x30 && *(s + 1) <= 0x39)
	{
		/* Should be 4-byte, validate remaining bytes */
		if (*s >= 0x81 && *s <= 0xfe &&
			*(s + 2) >= 0x81 && *(s + 2) <= 0xfe &&
			*(s + 3) >= 0x30 && *(s + 3) <= 0x39)
			l = 4;
		else
			l = -1;
	}
	/* else if (len >= 2 && *s >= 0x81 && *s <= 0xfe) */
	else if (len >= 2 && *s >= 0x80 && *s <= 0xfe)
	{
		/* Should be 2-byte, validate */
		if ((*(s + 1) >= 0x40 && *(s + 1) <= 0x7e) ||
			(*(s + 1) >= 0x80 && *(s + 1) <= 0xfe))
			l = 2;
		else
			l = -1;
	}
	else
		l = -1;
	return l;
}

Datum
gbk_to_gb18030_2(PG_FUNCTION_ARGS)
{
	unsigned char *src = (unsigned char *) PG_GETARG_CSTRING(2);
	unsigned char *dest = (unsigned char *) PG_GETARG_CSTRING(3);
	int			len = PG_GETARG_INT32(4);

	/* unsigned char *double_s = (unsigned char *) PG_GETARG_CSTRING(6); */
	int			*counts = (int *) PG_GETARG_POINTER(7);

	int			converted;

	CHECK_ENCODING_CONVERSION_ARGS(PG_GBK, PG_GB18030);

	converted = pg_gbk_str_validation_2((unsigned const char *)src, len);
	if (converted != len)
		elog(ERROR,"converted length not equal src length!");
	memcpy(dest,src,len);
	dest[len] = '\0';

	/* return len */
	*counts = len;

	PG_RETURN_INT32(converted);
}

Datum
gb18030_to_gbk_2(PG_FUNCTION_ARGS)
{
	unsigned char *src = (unsigned char *) PG_GETARG_CSTRING(2);
	unsigned char *dest = (unsigned char *) PG_GETARG_CSTRING(3);
	int			len = PG_GETARG_INT32(4);

	/* unsigned char *double_s = (unsigned char *) PG_GETARG_CSTRING(6); */
	int			*counts = (int *) PG_GETARG_POINTER(7);

	int			converted;

	CHECK_ENCODING_CONVERSION_ARGS(PG_GB18030, PG_GBK);

	converted = pg_gbk_str_validation_2((unsigned const char *)src, len);
	if (converted != len)
		elog(ERROR, "converted length not equal src length!");
	memcpy(dest, src, len);
	dest[len] = '\0';

	/* return len */
	*counts = len;

	PG_RETURN_INT32(converted);
}
