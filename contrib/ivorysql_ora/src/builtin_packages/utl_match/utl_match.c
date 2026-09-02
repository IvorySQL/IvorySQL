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
 *   UTL_MATCH.EDIT_DISTANCE(s1, s2)             -> PLS_INTEGER
 *   UTL_MATCH.EDIT_DISTANCE_SIMILARITY(s1, s2)  -> PLS_INTEGER  (0..100)
 *   UTL_MATCH.JARO_WINKLER(s1, s2)              -> BINARY_DOUBLE (0..1)
 *   UTL_MATCH.JARO_WINKLER_SIMILARITY(s1, s2)   -> PLS_INTEGER  (0..100)
 *
 * Oracle compatibility notes -- all of the following were verified
 * empirically against a real Oracle Database 19c instance (AL32UTF8),
 * since the UTL_MATCH documentation does not specify them:
 *
 * - All comparisons are BYTE-based, not character-based, e.g.
 *       EDIT_DISTANCE('中文测试','中文测A') = 3
 *   (the last multi-byte character differs from 'A' in all 3 of its
 *   UTF-8 bytes: 1 substitution + 2 deletions), and
 *       EDIT_DISTANCE_SIMILARITY('中文测试','中文测A') = 75
 *   i.e. the maximum length in the formula is the length in bytes, too.
 * - NULL inputs do NOT propagate (the functions are not STRICT):
 *       EDIT_DISTANCE              : any NULL           -> -1
 *       EDIT_DISTANCE_SIMILARITY   : one NULL -> 0, both NULL -> 100
 *       JARO_WINKLER               : any NULL           -> 0
 *       JARO_WINKLER_SIMILARITY    : any NULL           -> 0
 * - Half-transpositions are truncated towards zero (integer division),
 *   e.g. JARO_WINKLER_SIMILARITY('ABCDEF','BCADEF') = 94, not 92.
 * - The Winkler prefix boost is applied unconditionally (no boost
 *   threshold) and the common prefix is capped at 4 bytes, e.g.
 *   JARO_WINKLER('ABCCCCCCCCCC','ABDDDDDDDDDD') = 0.5555... and
 *   JARO_WINKLER('AAAAAAB','AAAAAAC')           = 0.9428...
 * - The Jaro match window is floor(max(len1,len2) / 2) - 1, e.g.
 *   JARO_WINKLER('aaaa','aaabbba') = 0.8083...
 * - Similarity results are rounded half-up, e.g.
 *   EDIT_DISTANCE_SIMILARITY('saturday','sunday') = 63.
 *
 * The algorithms also reproduce the golden values published in the
 * Oracle PL/SQL Packages and Types Reference:
 *   EDIT_DISTANCE('shackleford','shackelford')            = 2
 *   EDIT_DISTANCE_SIMILARITY('shackleford','shackelford') = 82
 *   JARO_WINKLER('shackleford','shackelford')             = 0.9818
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

/* Oracle-style rounding: round half away from zero (inputs are >= 0 here). */
static int
round_to_int(double v)
{
	return (int) floor(v + 0.5);
}

/*
 * Levenshtein edit distance (minimum number of single-byte insertions,
 * deletions or substitutions), two-row DP.  Memory usage stays O(min(n1,n2))
 * by making the shorter string the column dimension of the DP matrix.
 */
static int
edit_distance(const unsigned char *s1, int n1, const unsigned char *s2, int n2)
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
		const unsigned char *ts = s1;
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
 * clamped to a minimum of 0, where LEN1/LEN2 are the lengths in bytes
 * (as in Oracle).  Two empty strings are considered 100% similar.
 */
static int
edit_distance_similarity(const unsigned char *s1, int n1, const unsigned char *s2, int n2)
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

/* Jaro similarity (standard definition, range 0..1), byte-based. */
static double
jaro(const unsigned char *s1, int n1, const unsigned char *s2, int n2)
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

	/* Oracle uses the textbook window floor(max(n1,n2)/2) - 1. */
	window = (n1 > n2 ? n1 : n2) / 2;
	if (window > 0)
		window--;

	s1match = (int *) palloc0(n1 * sizeof(int));
	s2match = (int *) palloc0(n2 * sizeof(int));

	/*
	 * Count matching bytes: each byte of s1 can match a not yet used byte
	 * of s2 within the search window.
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

	/* Count transpositions: matching bytes that appear out of order. */
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
	 * Oracle truncates the number of half-transpositions towards zero
	 * (integer division), e.g. 3 displaced bytes count as 1, not 1.5:
	 * JARO_WINKLER_SIMILARITY('ABCDEF','BCADEF') = 94, not 92.
	 */
	res = ((double) m / (double) n1 + (double) m / (double) n2 +
		   (double) (m - t / 2) / (double) m) / 3.0;
	return res;
}

/*
 * Jaro-Winkler similarity: boosts the Jaro similarity for strings sharing
 * a common prefix (up to 4 bytes).  Oracle applies the boost
 * unconditionally, without the classic 0.7 boost threshold.
 */
static double
jaro_winkler(const unsigned char *s1, int n1, const unsigned char *s2, int n2)
{
	double		j = jaro(s1, n1, s2, n2);
	int			p = 0;
	int			max = n1 < n2 ? n1 : n2;

	while (p < max && p < 4 && s1[p] == s2[p])
		p++;
	j += (double) p * 0.1 * (1.0 - j);

	return j;
}

/*
 * sys.ora_utl_match_edit_distance(s1 text, s2 text) RETURNS integer
 *
 * Returns the minimum number of edits (insertion, deletion, substitution)
 * required to transform s1 into s2.  Like Oracle, returns -1 if either
 * input is NULL.
 */
Datum
ora_utl_match_edit_distance(PG_FUNCTION_ARGS)
{
	text	   *t1,
			   *t2;

	/* Oracle returns -1 for NULL input, it does not propagate NULL. */
	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		PG_RETURN_INT32(-1);

	t1 = PG_GETARG_TEXT_PP(0);
	t2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_INT32(edit_distance((const unsigned char *) VARDATA_ANY(t1),
								  VARSIZE_ANY_EXHDR(t1),
								  (const unsigned char *) VARDATA_ANY(t2),
								  VARSIZE_ANY_EXHDR(t2)));
}

/*
 * sys.ora_utl_match_edit_distance_similarity(s1 text, s2 text) RETURNS integer
 *
 * Returns a percentage (0..100) expressing the similarity of the two
 * strings.  Like Oracle: 100 if both inputs are NULL, 0 if exactly one is.
 */
Datum
ora_utl_match_edit_distance_similarity(PG_FUNCTION_ARGS)
{
	text	   *t1,
			   *t2;
	bool		n1null = PG_ARGISNULL(0);
	bool		n2null = PG_ARGISNULL(1);

	if (n1null && n2null)
		PG_RETURN_INT32(100);
	if (n1null || n2null)
		PG_RETURN_INT32(0);

	t1 = PG_GETARG_TEXT_PP(0);
	t2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_INT32(edit_distance_similarity((const unsigned char *) VARDATA_ANY(t1),
											 VARSIZE_ANY_EXHDR(t1),
											 (const unsigned char *) VARDATA_ANY(t2),
											 VARSIZE_ANY_EXHDR(t2)));
}

/*
 * sys.ora_utl_match_jaro_winkler(s1 text, s2 text) RETURNS float8
 *
 * Returns a value in the range 0..1 indicating how similar the strings are.
 * Like Oracle, returns 0 if either input is NULL.
 */
Datum
ora_utl_match_jaro_winkler(PG_FUNCTION_ARGS)
{
	text	   *t1,
			   *t2;
	double		res;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		PG_RETURN_FLOAT8(0.0);

	t1 = PG_GETARG_TEXT_PP(0);
	t2 = PG_GETARG_TEXT_PP(1);

	res = jaro_winkler((const unsigned char *) VARDATA_ANY(t1),
					   VARSIZE_ANY_EXHDR(t1),
					   (const unsigned char *) VARDATA_ANY(t2),
					   VARSIZE_ANY_EXHDR(t2));

	PG_RETURN_FLOAT8(res);
}

/*
 * sys.ora_utl_match_jaro_winkler_similarity(s1 text, s2 text) RETURNS integer
 *
 * Returns JARO_WINKLER(s1, s2) * 100, rounded to the nearest integer
 * (0..100).  Like Oracle, returns 0 if either input is NULL.
 */
Datum
ora_utl_match_jaro_winkler_similarity(PG_FUNCTION_ARGS)
{
	text	   *t1,
			   *t2;
	double		jw;
	int			res;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		PG_RETURN_INT32(0);

	t1 = PG_GETARG_TEXT_PP(0);
	t2 = PG_GETARG_TEXT_PP(1);

	jw = jaro_winkler((const unsigned char *) VARDATA_ANY(t1),
					  VARSIZE_ANY_EXHDR(t1),
					  (const unsigned char *) VARDATA_ANY(t2),
					  VARSIZE_ANY_EXHDR(t2));
	res = round_to_int(jw * 100.0);

	PG_RETURN_INT32(res);
}
