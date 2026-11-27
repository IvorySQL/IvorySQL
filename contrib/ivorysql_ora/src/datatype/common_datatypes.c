/*-------------------------------------------------------------------------
 * Copyright 2025 IvorySQL Global Development Team
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
 * common_datatypes.c
 *
 * This file contains Common support routines for datatypes.
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/common_datatypes.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <math.h>

#include "mb/pg_wchar.h"
#include "utils/builtins.h"

#include "../include/common_datatypes.h"

/*
 * Oracle's default binary floating-point representation uses enough digits
 * to round-trip the value, an uppercase E, and a three-digit exponent.
 * Retain one fractional digit even for integral mantissas.  This is shared
 * by type output (including implicit casts) and the default TO_CHAR overloads.
 */
char *
ora_binary_float_to_cstring(double value, int precision)
{
	char	   *result;
	char	   *exponent;
	char	   *end;
	int			exp;

	Assert(precision == ORACLE_BINARY_FLOAT_DIGITS ||
		   precision == ORACLE_BINARY_DOUBLE_DIGITS);

	if (isnan(value))
		return pstrdup("Nan");
	if (isinf(value))
		return pstrdup(value < 0 ? "-Inf" : "Inf");
	if (value == 0)
		return pstrdup("0");

	/* Sign, 17 significant digits, decimal point, E+nnn, and terminator fit. */
	result = palloc(32);
	snprintf(result, 32, "%.*E", precision - 1, value);
	exponent = strchr(result, 'E');
	Assert(exponent != NULL);
	exp = (int) strtol(exponent + 1, NULL, 10);

	end = exponent - 1;
	while (*end == '0' && end[-1] != '.')
		end--;
	end++;
	snprintf(end, 32 - (end - result), "E%+04d", exp);

	return result;
}

/*
 * Common implementation for btrim, ltrim, rtrim.
 * Note: copy from dotrim of pg core code and rename it to
 * ora_dotrim, perhaps we will modify this function in the future.
 */
text *
ora_dotrim(const char *string, int stringlen, const char *set, int setlen, bool doltrim, bool dortrim)
{
	int			i;

	/* Nothing to do if either string or set is empty */
	if (stringlen > 0 && setlen > 0)
	{
		if (pg_database_encoding_max_length() > 1)
		{
			/*
			 * In the multibyte-encoding case, build arrays of pointers to
			 * character starts, so that we can avoid inefficient checks in
			 * the inner loops.
			 */
			const char **stringchars;
			const char **setchars;
			int		   *stringmblen;
			int		   *setmblen;
			int			stringnchars;
			int			setnchars;
			int			resultndx;
			int			resultnchars;
			const char *p;
			int			len;
			int			mblen;
			const char *str_pos;
			int			str_len;

			stringchars = (const char **) palloc(stringlen * sizeof(char *));
			stringmblen = (int *) palloc(stringlen * sizeof(int));
			stringnchars = 0;
			p = string;
			len = stringlen;
			while (len > 0)
			{
				stringchars[stringnchars] = p;
				stringmblen[stringnchars] = mblen = pg_mblen(p);
				stringnchars++;
				p += mblen;
				len -= mblen;
			}

			setchars = (const char **) palloc(setlen * sizeof(char *));
			setmblen = (int *) palloc(setlen * sizeof(int));
			setnchars = 0;
			p = set;
			len = setlen;
			while (len > 0)
			{
				setchars[setnchars] = p;
				setmblen[setnchars] = mblen = pg_mblen(p);
				setnchars++;
				p += mblen;
				len -= mblen;
			}

			resultndx = 0;		/* index in stringchars[] */
			resultnchars = stringnchars;

			if (doltrim)
			{
				while (resultnchars > 0)
				{
					str_pos = stringchars[resultndx];
					str_len = stringmblen[resultndx];
					for (i = 0; i < setnchars; i++)
					{
						if (str_len == setmblen[i] &&
							memcmp(str_pos, setchars[i], str_len) == 0)
							break;
					}
					if (i >= setnchars)
						break;	/* no match here */
					string += str_len;
					stringlen -= str_len;
					resultndx++;
					resultnchars--;
				}
			}

			if (dortrim)
			{
				while (resultnchars > 0)
				{
					str_pos = stringchars[resultndx + resultnchars - 1];
					str_len = stringmblen[resultndx + resultnchars - 1];
					for (i = 0; i < setnchars; i++)
					{
						if (str_len == setmblen[i] &&
							memcmp(str_pos, setchars[i], str_len) == 0)
							break;
					}
					if (i >= setnchars)
						break;	/* no match here */
					stringlen -= str_len;
					resultnchars--;
				}
			}

			pfree(stringchars);
			pfree(stringmblen);
			pfree(setchars);
			pfree(setmblen);
		}
		else
		{
			/*
			 * In the single-byte-encoding case, we don't need such overhead.
			 */
			if (doltrim)
			{
				while (stringlen > 0)
				{
					char		str_ch = *string;

					for (i = 0; i < setlen; i++)
					{
						if (str_ch == set[i])
							break;
					}
					if (i >= setlen)
						break;	/* no match here */
					string++;
					stringlen--;
				}
			}

			if (dortrim)
			{
				while (stringlen > 0)
				{
					char		str_ch = string[stringlen - 1];

					for (i = 0; i < setlen; i++)
					{
						if (str_ch == set[i])
							break;
					}
					if (i >= setlen)
						break;	/* no match here */
					stringlen--;
				}
			}
		}
	}

	/* Return selected portion of string */
	return cstring_to_text_with_len(string, stringlen);
}

