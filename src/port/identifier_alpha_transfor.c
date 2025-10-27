/*-------------------------------------------------------------------------
 *
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
 * identifier_alpha_transfor.c
 *
 * This file provides a string case conversion function
 *
 * upper_character() 	-- transform lowercase letters to uppercase
 * down_character() 	-- transform uppercase letters to lowercase
 * is_all_upper() 	-- Determine whether the letters in the string are all uppercase letters
 * is_all_lower() 	-- Determine whether the letters in the string are all lowercase letters
 *
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * src/port/identifier_alpha_transfor.c
 *
 * add the file for requirement "case-sensitive identifier" feature upgrade
 *
 *-------------------------------------------------------------------------
 */


#include "postgres.h"

#include "c.h"
#include "common/fe_memutils.h"

/*
 * transform upper to lower
 */
char *
down_character(const char *src, int len)
{
	char    *res;
	char	*s ;
	int		i;
	Assert(src != NULL);
	Assert(len >= 0);

	res = (char*)palloc(len + 1);
	memcpy(res, src, len);
	res[len] = '\0';
	s = res;

	/* transform */
	for (i = 0; i < len ; i++)
	{
		*s = tolower(*s);
		s++;
	}

	return res;
}
/*
 * transform lower to upper
 */
char *
upper_character(const char *src, int len)
{
	char	*res;
	char	*s ;
	int		i;
	Assert(src != NULL);
	Assert(len >= 0);

	res = (char*)palloc(len + 1);
	memcpy(res, src, len);
	res[len] = '\0';
	s = res;

	/* transform */
	for (i = 0; i < len ; i++)
	{
		*s = toupper(*s);

		s++;
	}

	return res;
}

/*
 * Determine whether the letters in the string are all lowercase letters
 */
bool
is_all_lower(const char *src, int len)
{
	int		i;
	const char	*s;

	s = src;

	for (i = 0; i < len; i++)
	{
		if (isalpha(*s) && isupper(*s))
			return false;
		s++;
	}

	return true;
}

/*
 * Determine whether the letters in the string are all uppercase letters
 */
bool
is_all_upper(const char *src, int len)
{
	int		i;
	const char	*s;

	s = src;

	for (i = 0; i < len; i++)
	{
		if (isalpha(*s) && islower(*s))
			return false;
		s++;
	}

	return true;
}
