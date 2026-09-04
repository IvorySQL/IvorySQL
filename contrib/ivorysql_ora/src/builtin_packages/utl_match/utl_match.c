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
 * utl_match.c
 *
 * Implementation of Oracle's UTL_MATCH package:
 *
 *   UTL_MATCH.EDIT_DISTANCE(s1, s2)             -> PLS_INTEGER  (0..)
 *   UTL_MATCH.EDIT_DISTANCE_SIMILARITY(s1, s2)  -> PLS_INTEGER  (0..100)
 *   UTL_MATCH.JARO_WINKLER(s1, s2)              -> BINARY_DOUBLE (0..1)
 *   UTL_MATCH.JARO_WINKLER_SIMILARITY(s1, s2)   -> PLS_INTEGER  (0..100)
 *
 * Comparison is case-sensitive (as in Oracle) and character-based, so
 * multi-byte encodings (UTF-8, GBK, ...) are handled correctly.
 *
 * The algorithms were validated against the golden values published in
 * the Oracle PL/SQL Packages and Types Reference:
 *   EDIT_DISTANCE('shackleford','shackelford')          = 2
 *   EDIT_DISTANCE_SIMILARITY('shackleford','shackelford') = 82
 *   JARO_WINKLER('shackleford','shackelford')           = 0.9818
 *   JARO_WINKLER_SIMILARITY('shackleford','shackelford')  = 98
 *
 * This module is part of the ivorysql_ora extension.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_match/utl_match.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <math.h>

#include "fmgr.h"
#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "utils/builtins.h"
#include "varatt.h"

PG_FUNCTION_INFO_V1(ora_utl_match_edit_distance);
PG_FUNCTION_INFO_V1(ora_utl_match_edit_distance_similarity);
PG_FUNCTION_INFO_V1(ora_utl_match_jaro_winkler);
PG_FUNCTION_INFO_V1(ora_utl_match_jaro_winkler_similarity);

/*
 * Work performed between two checks for interrupts, measured in inner-loop
 * iterations.  Keeps cancellation / statement_timeout responsive even for
 * very large (quadratic) comparisons.
 */
#define UTL_MATCH_CHECK_INTERVAL	1024


/*
 * Decode a text value into an array of pg_wchar characters using the current
 * database encoding.  This makes every comparison character-based instead of
 * byte-based, so multi-byte strings (e.g. Chinese) are handled correctly.
 */
static void
text_to_wchars(text *t, pg_wchar **wchars, int *nchars)
{
	char	   *str;
	int			len;

	str = VARDATA_ANY(t);
	len = VARSIZE_ANY_EXHDR(t);

	/*
	 * Bound the buffer generously: every input byte can map to at most one
	 * pg_wchar in any encoding supported by the server (SQL_ASCII is 1:1,
	 * others are <= 1:1), so len + 1 entries are always sufficient.
	 */
	*wchars = (pg_wchar *) palloc((len + 1) * sizeof(pg_wchar));
	*nchars = pg_mb2wchar_with_len(str, *wchars, len);
}

/* Oracle-style rounding: round half away from zero (inputs are >= 0 here). */
static int
round_to_int(double v)
{
	return (int) floor(v + 0.5);
}

/*
 * Levenshtein edit distance (minimum number of single-character insertions,
 * deletions or substitutions), two-row DP.  Memory usage stays O(min(n1,n2))
 * by making the shorter string the column dimension of the DP matrix.
 */
static int
edit_distance(const pg_wchar *s1, int n1, const pg_wchar *s2, int n2)
{
	int		   *prev,
			   *curr,
			   *tmp;
	int			i,
				j;
	long		progress = 0;
	int			res;

	if (n1 == 0)
		return n2;
	if (n2 == 0)
		return n1;

	/* Levenshtein distance is symmetric, so swap to save memory. */
	if (n1 < n2)
	{
		const pg_wchar *ts = s1;
		int			t = n1;

		s1 = s2;
		s2 = ts;
		n1 = n2;
		n2 = t;
	}

	prev = (int *) palloc((n2 + 1) * sizeof(int));
	curr = (int *) palloc((n2 + 1) * sizeof(int));
	for (j = 0; j <= n2; j++)
		prev[j] = j;

	for (i = 1; i <= n1; i++)
	{
		curr[0] = i;
		for (j = 1; j <= n2; j++)
		{
			int			cost = (s1[i - 1] == s2[j - 1]) ? 0 : 1;
			int			del = prev[j] + 1;
			int			ins = curr[j - 1] + 1;
			int			sub = prev[j - 1] + cost;

			curr[j] = Min(del, ins);
			curr[j] = Min(curr[j], sub);

			/*
			 * Check for interrupts while walking the DP matrix so that huge
			 * inputs can still be cancelled or honor statement_timeout.
			 * progress accumulates across both loop dimensions, so highly
			 * unequal inputs (n1 >> n2) are covered by the outer-loop path
			 * as well.
			 */
			if (++progress == UTL_MATCH_CHECK_INTERVAL)
			{
				CHECK_FOR_INTERRUPTS();
				progress = 0;
			}
		}
		tmp = prev;
		prev = curr;
		curr = tmp;
	}

	res = prev[n2];
	pfree(prev);
	pfree(curr);
	return res;
}

/*
 * EDIT_DISTANCE_SIMILARITY = ROUND((1 - ED / MAX(LEN1, LEN2)) * 100),
 * clamped to a minimum of 0.  Two empty strings are considered 100% similar.
 * Note: results are identical whether calculated on characters or bytes
 * because ED and MAX(LEN1,LEN2) are both in the same unit.
 */
static int
edit_distance_similarity(const pg_wchar *s1, int n1, const pg_wchar *s2, int n2)
{
	int			ed = edit_distance(s1, n1, s2, n2);
	int			max = n1 > n2 ? n1 : n2;
	double		sim;

	if (max == 0)
		return 100;

	sim = (1.0 - (double) ed / (double) max) * 100.0;
	if (sim < 0.0)
		sim = 0.0;
	return round_to_int(sim);
}

/* Jaro distance (standard definition, range 0..1). */
static double
jaro(const pg_wchar *s1, int n1, const pg_wchar *s2, int n2)
{
	int			window;
	int			i,
				j;
	int		   *s1match,
			   *s2match;
	long		m = 0,
				t = 0,
				progress = 0;
	double		res;

	if (n1 == 0 || n2 == 0)
		return 0.0;

	window = (n1 > n2 ? n1 : n2) / 2;
	if (window > 0)
		window--;

	s1match = (int *) palloc0(n1 * sizeof(int));
	s2match = (int *) palloc0(n2 * sizeof(int));

	/*
	 * Count matching characters: each character of s1 can match a not yet
	 * used character of s2 within the search window.
	 */
	for (i = 0; i < n1; i++)
	{
		int			lo = i > window ? i - window : 0;
		int			hi = i + window + 1;

		if (hi > n2)
			hi = n2;
		for (j = lo; j < hi; j++)
		{
			/*
			 * Same interrupt discipline as edit_distance(): keep huge
			 * quadratic matching loops cancellable and timeout-aware.
			 */
			if (++progress == UTL_MATCH_CHECK_INTERVAL)
			{
				CHECK_FOR_INTERRUPTS();
				progress = 0;
			}
			if (!s2match[j] && s1[i] == s2[j])
			{
				s1match[i] = 1;
				s2match[j] = 1;
				m++;
				break;
			}
		}
	}

	/* Count transpositions: matching characters that appear out of order. */
	for (i = 0, j = 0; i < n1; i++)
	{
		if (++progress == UTL_MATCH_CHECK_INTERVAL)
		{
			CHECK_FOR_INTERRUPTS();
			progress = 0;
		}
		if (s1match[i])
		{
			while (!s2match[j])
				j++;
			if (s1[i] != s2[j])
				t++;
			j++;
		}
	}

	pfree(s1match);
	pfree(s2match);

	if (m == 0)
		return 0.0;

	/*
	 * t is the number of matched characters that are in a different
	 * order; the Jaro definition uses half of that count, which may be
	 * fractional (e.g. abcdef vs bcadef -> 3/2 = 1.5), so divide in
	 * floating point.
	 */
	res = ((double) m / (double) n1 + (double) m / (double) n2 +
		   (double) (m - t / 2.0) / (double) m) / 3.0;
	return res;
}

/*
 * Jaro-Winkler distance: boosts the Jaro distance for strings sharing a
 * common prefix (up to 4 characters), as long as it is above 0.7.
 */
static double
jaro_winkler(const pg_wchar *s1, int n1, const pg_wchar *s2, int n2)
{
	double		j = jaro(s1, n1, s2, n2);
	int			p = 0;
	int			max = n1 < n2 ? n1 : n2;

	if (j > 0.7)
	{
		while (p < max && p < 4 && s1[p] == s2[p])
			p++;
		j += (double) p * 0.1 * (1.0 - j);
	}
	return j;
}

/*
 * sys.ora_utl_match_edit_distance(s1 text, s2 text) RETURNS integer
 *
 * Returns the minimum number of edits (insertion, deletion, substitution)
 * required to transform s1 into s2.  NULL in -> NULL out (STRICT in SQL).
 */
Datum
ora_utl_match_edit_distance(PG_FUNCTION_ARGS)
{
	text	   *t1 = PG_GETARG_TEXT_PP(0);
	text	   *t2 = PG_GETARG_TEXT_PP(1);
	pg_wchar   *w1,
			   *w2;
	int			n1,
				n2;
	int			res;

	text_to_wchars(t1, &w1, &n1);
	text_to_wchars(t2, &w2, &n2);
	res = edit_distance(w1, n1, w2, n2);

	pfree(w1);
	pfree(w2);
	PG_FREE_IF_COPY(t1, 0);
	PG_FREE_IF_COPY(t2, 1);

	PG_RETURN_INT32(res);
}

/*
 * sys.ora_utl_match_edit_distance_similarity(s1 text, s2 text) RETURNS integer
 *
 * Returns a percentage (0..100) expressing the similarity of the two strings.
 */
Datum
ora_utl_match_edit_distance_similarity(PG_FUNCTION_ARGS)
{
	text	   *t1 = PG_GETARG_TEXT_PP(0);
	text	   *t2 = PG_GETARG_TEXT_PP(1);
	pg_wchar   *w1,
			   *w2;
	int			n1,
				n2;
	int			res;

	text_to_wchars(t1, &w1, &n1);
	text_to_wchars(t2, &w2, &n2);
	res = edit_distance_similarity(w1, n1, w2, n2);

	pfree(w1);
	pfree(w2);
	PG_FREE_IF_COPY(t1, 0);
	PG_FREE_IF_COPY(t2, 1);

	PG_RETURN_INT32(res);
}

/*
 * sys.ora_utl_match_jaro_winkler(s1 text, s2 text) RETURNS float8
 *
 * Returns a value in the range 0..1 indicating how similar the strings are.
 */
Datum
ora_utl_match_jaro_winkler(PG_FUNCTION_ARGS)
{
	text	   *t1 = PG_GETARG_TEXT_PP(0);
	text	   *t2 = PG_GETARG_TEXT_PP(1);
	pg_wchar   *w1,
			   *w2;
	int			n1,
				n2;
	double		res;

	text_to_wchars(t1, &w1, &n1);
	text_to_wchars(t2, &w2, &n2);
	res = jaro_winkler(w1, n1, w2, n2);

	pfree(w1);
	pfree(w2);
	PG_FREE_IF_COPY(t1, 0);
	PG_FREE_IF_COPY(t2, 1);

	PG_RETURN_FLOAT8(res);
}

/*
 * sys.ora_utl_match_jaro_winkler_similarity(s1 text, s2 text) RETURNS integer
 *
 * Returns JARO_WINKLER(s1, s2) * 100, rounded to the nearest integer (0..100).
 */
Datum
ora_utl_match_jaro_winkler_similarity(PG_FUNCTION_ARGS)
{
	text	   *t1 = PG_GETARG_TEXT_PP(0);
	text	   *t2 = PG_GETARG_TEXT_PP(1);
	pg_wchar   *w1,
			   *w2;
	int			n1,
				n2;
	double		jw;
	int			res;

	text_to_wchars(t1, &w1, &n1);
	text_to_wchars(t2, &w2, &n2);
	jw = jaro_winkler(w1, n1, w2, n2);
	res = round_to_int(jw * 100.0);

	pfree(w1);
	pfree(w2);
	PG_FREE_IF_COPY(t1, 0);
	PG_FREE_IF_COPY(t2, 1);

	PG_RETURN_INT32(res);
}