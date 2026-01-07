/*-------------------------------------------------------------------------
 *
 * scansup.c
 *	  scanner support routines used by the core lexer
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 *
 * IDENTIFICATION
 *	  src/backend/parser/scansup.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <ctype.h>
#include <stdbool.h>

#include "mb/pg_wchar.h"
#include "parser/scansup.h"


/*
 * downcase_truncate_identifier() --- do appropriate downcasing and
 * truncation of an unquoted identifier.  Optionally warn of truncation.
 *
 * Returns a palloc'd string containing the adjusted identifier.
 *
 * Note: in some usages the passed string is not null-terminated.
 *
 * Note: the API of this function is designed to allow for downcasing
 * transformations that increase the string length, but we don't yet
 * support that.  If you want to implement it, you'll need to fix
 * SplitIdentifierString() in utils/adt/varlena.c.
 */
char *
downcase_truncate_identifier(const char *ident, int len, bool warn)
{
	return downcase_identifier(ident, len, warn, true);
}

/**
 * Produce a downcased copy of an identifier substring.
 *
 * Creates and returns a palloc'd, NUL-terminated string containing a
 * downcased form of the first `len` bytes of `ident`. ASCII letters
 * are converted to lower-case; for single-byte encodings, high-bit
 * characters are converted using `tolower()` when appropriate. Multi-byte
 * character sequences are preserved unchanged. If `truncate` is true and
 * the converted name is longer than NAMEDATALEN-1 bytes, the result is
 * truncated in-place to that length; if `warn` is true a NOTICE is emitted
 * when truncation occurs.
 *
 * @param ident input identifier bytes (not necessarily NUL-terminated)
 * @param len number of bytes from `ident` to process
 * @param warn emit a NOTICE if truncation occurs
 * @param truncate truncate the result to NAMEDATALEN-1 when necessary
 * @returns a palloc'd, NUL-terminated downcased string representing the input
 */
char *
downcase_identifier(const char *ident, int len, bool warn, bool truncate)
{
	char	   *result;
	int			i;
	bool		enc_is_single_byte;

	result = palloc(len + 1);
	enc_is_single_byte = pg_database_encoding_max_length() == 1;

	/*
	 * SQL99 specifies Unicode-aware case normalization, which we don't yet
	 * have the infrastructure for.  Instead we use tolower() to provide a
	 * locale-aware translation.  However, in some locales (for example,
	 * Turkish with 'i' and 'I') this still is not correct.  Our compromise is
	 * to use tolower() for characters with the high bit set, as long as they
	 * aren't part of a multi-byte character, and use an ASCII-only approach
	 * for 7-bit characters.
	 */
	strncpy(result, ident, len);
	for (i = 0; i < len; i++)
	{
		unsigned char ch = (unsigned char) ident[i];
		int mblen = pg_mblen(ident + i);
		if (mblen > 1)
		{
			i += mblen - 1;
			continue;
		}

		if (ch >= 'A' && ch <= 'Z')
			ch += 'a' - 'A';
		else if (enc_is_single_byte && IS_HIGHBIT_SET(ch) && isupper(ch))
			ch = tolower(ch);
		result[i] = (char) ch;
	}
	result[i] = '\0';

	if (i >= NAMEDATALEN && truncate)
		truncate_identifier(result, i, warn);

	return result;
}

/**
 * Produce an upcased form of an identifier, suitable for use by the lexer.
 *
 * The function returns a newly allocated, NUL-terminated string containing
 * an upper-case version of the first `len` bytes of `ident`. Multi-byte
 * characters are preserved (not transformed) and single-byte characters are
 * converted to upper-case where appropriate. If `truncate` is true and the
 * converted identifier exceeds NAMEDATALEN-1 bytes, it will be truncated;
 * if `warn` is true a NOTICE will be issued when truncation occurs.
 *
 * @param ident Input identifier (not necessarily NUL-terminated within `len`).
 * @param len Number of bytes from `ident` to convert.
 * @param warn If true, emit a NOTICE when truncation happens.
 * @param truncate If true, truncate the result to NAMEDATALEN-1 bytes when necessary.
 * @return A palloc'd, NUL-terminated string containing the upcased identifier.
 */
char *
upcase_identifier(const char *ident, int len, bool warn, bool truncate)
{
	char	   *result;
	int			i;
	bool		enc_is_single_byte;

	result = palloc(len + 1);
	enc_is_single_byte = pg_database_encoding_max_length() == 1;

	/*
	 * SQL99 specifies Unicode-aware case normalization, which we don't yet
	 * have the infrastructure for.  Instead we use toupper() to provide a
	 * locale-aware translation.  However, there are some locales where this
	 * locale-aware translation.  However, there are some locales where this
	 * is not right either (eg, Turkish may do strange things with 'i' and
	 * 'I').  Our current compromise is to use toupper() for characters with
	 * the high bit set, as long as they aren't part of a multi-byte
	 * character, and use an ASCII-only downcasing for 7-bit characters.
	 */
	strncpy(result, ident, len);
	for (i = 0; i < len; i++)
	{
		unsigned char ch = (unsigned char) ident[i];
		int mblen = pg_mblen(ident + i);
		if (mblen > 1)
		{
			i += mblen - 1;
			continue;
		}

		if (ch >= 'a' && ch <= 'z')
			ch -= 'a' - 'A';
		else if (enc_is_single_byte && IS_HIGHBIT_SET(ch) && islower(ch))
			ch = toupper(ch);
		result[i] = (char) ch;
	}
	result[i] = '\0';

	if (i >= NAMEDATALEN && truncate)
		truncate_identifier(result, i, warn);

	return result;
}

char *
identifier_case_transform(const char *ident, int len)
{
	char *upper_ident = NULL, *lower_ident = NULL, *result = NULL;

	upper_ident = upcase_identifier(ident, len, true, true);
	lower_ident = downcase_identifier(ident, len, true, true);

	if (strcmp(upper_ident, ident) == 0)
	{
		result = lower_ident;
		pfree(upper_ident);
	}
	else if (strcmp(lower_ident, ident) == 0)
	{
		result = upper_ident;
		pfree(lower_ident);
	}
	else
	{
		result = palloc0(len + 1);
		memcpy(result, ident, len);
		pfree(upper_ident);
		pfree(lower_ident);
	}

	return result;
}

/*
 * truncate_identifier() --- truncate an identifier to NAMEDATALEN-1 bytes.
 *
 * The given string is modified in-place, if necessary.  A warning is
 * issued if requested.
 *
 * We require the caller to pass in the string length since this saves a
 * strlen() call in some common usages.
 */
void
truncate_identifier(char *ident, int len, bool warn)
{
	if (len >= NAMEDATALEN)
	{
		len = pg_mbcliplen(ident, len, NAMEDATALEN - 1);
		if (warn)
			ereport(NOTICE,
					(errcode(ERRCODE_NAME_TOO_LONG),
					 errmsg("identifier \"%s\" will be truncated to \"%.*s\"",
							ident, len, ident)));
		ident[len] = '\0';
	}
}

/**
 * Report whether the scanner treats a character as whitespace.
 *
 * Matches the flex scanner's definition of whitespace used in scan.l:
 * space, horizontal tab, newline, carriage return, vertical tab, or form feed.
 *
 * @return `true` if `ch` is one of those whitespace characters, `false` otherwise.
 */
bool
scanner_isspace(char ch)
{
	/* This must match scan.l's list of {space} characters */
	if (ch == ' ' ||
		ch == '\t' ||
		ch == '\n' ||
		ch == '\r' ||
		ch == '\v' ||
		ch == '\f')
		return true;
	return false;
}

/**
 * Check whether every alphabetic character in the given identifier is lowercase.
 *
 * Multibyte character sequences are treated as indivisible units and are not
 * examined for case; only single-byte characters are checked.
 *
 * @param ident Pointer to the identifier bytes to examine.
 * @param len Number of bytes from ident to consider.
 * @returns `true` if every alphabetic character in the examined bytes is lowercase, `false` otherwise.
 */
 bool
 identifier_is_all_lower(const char *ident, int len)
{
	int i;
	const char* s;

	s = ident;

	for (i = 0; i < len; i++)
	{
		int mblen = pg_mblen(s);

		if (mblen > 1)
		{
			s += mblen;
			i += mblen - 1;
			continue;
		}

		if (isalpha(*s) && isupper(*s))
			return false;
		s++;
	}
	return true;
}

/**
 * Determine whether all alphabetic characters in ident are uppercase.
 *
 * Multibyte character sequences are skipped and not inspected for case.
 *
 * @param ident string to test (may not be NUL-terminated; only the first len bytes are examined)
 * @param len number of bytes to examine in ident
 * @returns `true` if every alphabetic character within the first len bytes is uppercase, `false` otherwise.
 */
 bool
 identifier_is_all_upper(const char *ident, int len)
{
	int i;
	const char* s;

	s = ident;

	for (i = 0; i < len; i++)
	{
		int mblen = pg_mblen(s);

		if (mblen > 1)
		{
			s += mblen;
			i += mblen - 1;
			continue;
		}

		if (isalpha(*s) && islower(*s))
			return false;
		s++;
	}
	return true;
}