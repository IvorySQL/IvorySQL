/*-------------------------------------------------------------------------
 *
 * identifier_alpha_transfor.c
 *
 * This file provides a string case conversion function
 *
 * upper_character() 	-- transfor lower to upper
 * down_character() 	-- transfor upper to lower
 * is_all_upper() 	-- Determine whether the letters in the string are all uppercase letters
 * is_all_lower() 	-- Determine whether the letters in the string are all lowercase letters
 *
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * src/port/identifier_alpha_transfor.c
 *
 * add the file for requirement "CASE SENSITIVE IDENTIFY" feature upgrade
 *
 *-------------------------------------------------------------------------
 */


#include "postgres.h"

#include "c.h"
#include "common/fe_memutils.h"

/*
 * transfor upper to lower
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

	/* transfor */
	for (i = 0; i < len ; i++)
	{
		*s = tolower(*s);
		s++;
	}

	return res;
}
/*
 * transfor lower to upper
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

	/* transfor */
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
