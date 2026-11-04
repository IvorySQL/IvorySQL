/*
 * Portions Copyright (c) 2026, PostgreSQL Global Development Group
 *
 * contrib/ora_btree_gist/btree_binary_float.c
 */
#include "postgres.h"

#include "btree_gist.h"
#include "btree_utils_num.h"
#include "utils/float.h"


typedef struct float4key
{
	float4		lower;
	float4		upper;
} float4KEY;

/*
** binary_float ops
*/
PG_FUNCTION_INFO_V1(gbt_binary_float_compress);
PG_FUNCTION_INFO_V1(gbt_binary_float_fetch);
PG_FUNCTION_INFO_V1(gbt_binary_float_union);
PG_FUNCTION_INFO_V1(gbt_binary_float_picksplit);
PG_FUNCTION_INFO_V1(gbt_binary_float_consistent);
PG_FUNCTION_INFO_V1(gbt_binary_float_distance);
PG_FUNCTION_INFO_V1(gbt_binary_float_penalty);
PG_FUNCTION_INFO_V1(gbt_binary_float_same);

/*
 * Use the NaN-aware comparators so that GiST agrees with the SQL operators
 * and B-tree indexes.  Penalty and distance must handle NaNs as well.
 */
static bool
gbt_binary_floatgt(const void *a, const void *b, FmgrInfo *flinfo)
{
	(void) flinfo;		/* not used */
	return float4_gt(*((const float4 *) a), *((const float4 *) b));
}
static bool
gbt_binary_floatge(const void *a, const void *b, FmgrInfo *flinfo)
{
	(void) flinfo;		/* not used */
	return float4_ge(*((const float4 *) a), *((const float4 *) b));
}
static bool
gbt_binary_floateq(const void *a, const void *b, FmgrInfo *flinfo)
{
	(void) flinfo;		/* not used */
	return float4_eq(*((const float4 *) a), *((const float4 *) b));
}
static bool
gbt_binary_floatle(const void *a, const void *b, FmgrInfo *flinfo)
{
	(void) flinfo;		/* not used */
	return float4_le(*((const float4 *) a), *((const float4 *) b));
}
static bool
gbt_binary_floatlt(const void *a, const void *b, FmgrInfo *flinfo)
{
	(void) flinfo;		/* not used */
	return float4_lt(*((const float4 *) a), *((const float4 *) b));
}

static int
gbt_binary_floatkey_cmp(const void *a, const void *b, FmgrInfo *flinfo)
{
	float4KEY  *ia = (float4KEY *) (((const Nsrt *) a)->t);
	float4KEY  *ib = (float4KEY *) (((const Nsrt *) b)->t);
	int			res;

	(void) flinfo;		/* not used */
	res = float4_cmp_internal(ia->lower, ib->lower);
	if (res != 0)
		return res;
	return float4_cmp_internal(ia->upper, ib->upper);
}

static float8
gbt_binary_float_dist(const void *a, const void *b, FmgrInfo *flinfo)
{
	float8		arg1 = *(const float4 *) a;
	float8		arg2 = *(const float4 *) b;
	float8		r;

	(void) flinfo;		/* not used */
	r = arg1 - arg2;
	/* With float4 inputs, infinity cannot be due to overflow here. */
	if (unlikely(isnan(r)))
	{
		if (isnan(arg1) && isnan(arg2))
			r = 0.0;			/* treat NaNs as equal */
		else if (isnan(arg1) || isnan(arg2))
			r = get_float8_infinity();	/* max dist for NaN vs non-NaN */
		else
			r = 0.0;			/* must be Inf - Inf case */
	}
	return fabs(r);
}


static const gbtree_ninfo tinfo =
{
	gbt_t_float4,
	sizeof(float4),
	8,							/* sizeof(gbtreekey8) */
	gbt_binary_floatgt,
	gbt_binary_floatge,
	gbt_binary_floateq,
	gbt_binary_floatle,
	gbt_binary_floatlt,
	gbt_binary_floatkey_cmp,
	gbt_binary_float_dist
};


PG_FUNCTION_INFO_V1(binary_float_dist);
Datum
binary_float_dist(PG_FUNCTION_ARGS)
{
	float4		a = PG_GETARG_FLOAT4(0);
	float4		b = PG_GETARG_FLOAT4(1);
	float4		r;

	r = a - b;
	if (unlikely(isinf(r)) && !isinf(a) && !isinf(b))
		float_overflow_error();

	if (unlikely(isnan(r)))
	{
		if (isnan(a) && isnan(b))
			r = 0.0;			/* treat NaNs as equal */
		else if (isnan(a) || isnan(b))
			r = get_float4_infinity();	/* max dist for NaN vs non-NaN */
		else
			r = 0.0;			/* must be Inf - Inf case */
	}
	PG_RETURN_FLOAT4(fabsf(r));
}


/**************************************************
 * binary_float ops
 **************************************************/


Datum
gbt_binary_float_compress(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);

	PG_RETURN_POINTER(gbt_num_compress(entry, &tinfo));
}

Datum
gbt_binary_float_fetch(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);

	PG_RETURN_POINTER(gbt_num_fetch(entry, &tinfo));
}

Datum
gbt_binary_float_consistent(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
	float4		query = PG_GETARG_FLOAT4(1);
	StrategyNumber strategy = (StrategyNumber) PG_GETARG_UINT16(2);

	/* Oid		subtype = PG_GETARG_OID(3); */
	bool	   *recheck = (bool *) PG_GETARG_POINTER(4);
	float4KEY  *kkk = (float4KEY *) DatumGetPointer(entry->key);
	GBT_NUMKEY_R key;

	/* All cases served by this function are exact */
	*recheck = false;

	key.lower = (GBT_NUMKEY *) &kkk->lower;
	key.upper = (GBT_NUMKEY *) &kkk->upper;

	PG_RETURN_BOOL(gbt_num_consistent(&key, (void *) &query, &strategy,
									  GIST_LEAF(entry), &tinfo,
									  fcinfo->flinfo));
}


Datum
gbt_binary_float_distance(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
	float4		query = PG_GETARG_FLOAT4(1);

	/* Oid		subtype = PG_GETARG_OID(3); */
	float4KEY  *kkk = (float4KEY *) DatumGetPointer(entry->key);
	GBT_NUMKEY_R key;

	key.lower = (GBT_NUMKEY *) &kkk->lower;
	key.upper = (GBT_NUMKEY *) &kkk->upper;

	PG_RETURN_FLOAT8(gbt_num_distance(&key, (void *) &query, GIST_LEAF(entry),
									  &tinfo, fcinfo->flinfo));
}


Datum
gbt_binary_float_union(PG_FUNCTION_ARGS)
{
	GistEntryVector *entryvec = (GistEntryVector *) PG_GETARG_POINTER(0);
	void	   *out = palloc(sizeof(float4KEY));

	*(int *) PG_GETARG_POINTER(1) = sizeof(float4KEY);
	PG_RETURN_POINTER(gbt_num_union((void *) out, entryvec, &tinfo, fcinfo->flinfo));
}


Datum
gbt_binary_float_penalty(PG_FUNCTION_ARGS)
{
	float4KEY  *origentry = (float4KEY *) DatumGetPointer(((GISTENTRY *) PG_GETARG_POINTER(0))->key);
	float4KEY  *newentry = (float4KEY *) DatumGetPointer(((GISTENTRY *) PG_GETARG_POINTER(1))->key);
	float	   *result = (float *) PG_GETARG_POINTER(2);

	float_penalty_num(result, origentry->lower, origentry->upper, newentry->lower, newentry->upper);

	PG_RETURN_POINTER(result);
}

Datum
gbt_binary_float_picksplit(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(gbt_num_picksplit((GistEntryVector *) PG_GETARG_POINTER(0),
										(GIST_SPLITVEC *) PG_GETARG_POINTER(1),
										&tinfo, fcinfo->flinfo));
}

Datum
gbt_binary_float_same(PG_FUNCTION_ARGS)
{
	float4KEY  *b1 = (float4KEY *) PG_GETARG_POINTER(0);
	float4KEY  *b2 = (float4KEY *) PG_GETARG_POINTER(1);
	bool	   *result = (bool *) PG_GETARG_POINTER(2);

	*result = gbt_num_same((void *) b1, (void *) b2, &tinfo, fcinfo->flinfo);
	PG_RETURN_POINTER(result);
}
