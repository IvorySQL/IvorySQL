/*
 * contrib/ora_btree_gist/btree_binary_double.c
 */
#include "postgres.h"

#include "btree_gist.h"
#include "btree_utils_num.h"
#include "utils/float.h"

typedef struct float8key
{
	float8		lower;
	float8		upper;
} float8KEY;

/*
** binary_double ops
*/
PG_FUNCTION_INFO_V1(gbt_binary_double_compress);
PG_FUNCTION_INFO_V1(gbt_binary_double_fetch);
PG_FUNCTION_INFO_V1(gbt_binary_double_union);
PG_FUNCTION_INFO_V1(gbt_binary_double_picksplit);
PG_FUNCTION_INFO_V1(gbt_binary_double_consistent);
PG_FUNCTION_INFO_V1(gbt_binary_double_distance);
PG_FUNCTION_INFO_V1(gbt_binary_double_penalty);
PG_FUNCTION_INFO_V1(gbt_binary_double_same);


static bool
gbt_binary_doublegt(const void *a, const void *b, FmgrInfo *flinfo)
{
	return (*((const float8 *) a) > *((const float8 *) b));
}
static bool
gbt_binary_doublege(const void *a, const void *b, FmgrInfo *flinfo)
{
	return (*((const float8 *) a) >= *((const float8 *) b));
}
static bool
gbt_binary_doubleeq(const void *a, const void *b, FmgrInfo *flinfo)
{
	return (*((const float8 *) a) == *((const float8 *) b));
}
static bool
gbt_binary_doublele(const void *a, const void *b, FmgrInfo *flinfo)
{
	return (*((const float8 *) a) <= *((const float8 *) b));
}
static bool
gbt_binary_doublelt(const void *a, const void *b, FmgrInfo *flinfo)
{
	return (*((const float8 *) a) < *((const float8 *) b));
}

static int
gbt_binary_doublekey_cmp(const void *a, const void *b, FmgrInfo *flinfo)
{
	float8KEY  *ia = (float8KEY *) (((const Nsrt *) a)->t);
	float8KEY  *ib = (float8KEY *) (((const Nsrt *) b)->t);

	if (ia->lower == ib->lower)
	{
		if (ia->upper == ib->upper)
			return 0;

		return (ia->upper > ib->upper) ? 1 : -1;
	}

	return (ia->lower > ib->lower) ? 1 : -1;
}

static float8
gbt_binary_double_dist(const void *a, const void *b, FmgrInfo *flinfo)
{
	float8		arg1 = *(const float8 *) a;
	float8		arg2 = *(const float8 *) b;
	float8		r;

	r = arg1 - arg2;
	if (unlikely(isinf(r)) && !isinf(arg1) && !isinf(arg2))
		float_overflow_error();
	return fabs(r);
}


static const gbtree_ninfo tinfo =
{
	gbt_t_float8,
	sizeof(float8),
	16,							/* sizeof(gbtreekey16) */
	gbt_binary_doublegt,
	gbt_binary_doublege,
	gbt_binary_doubleeq,
	gbt_binary_doublele,
	gbt_binary_doublelt,
	gbt_binary_doublekey_cmp,
	gbt_binary_double_dist
};


PG_FUNCTION_INFO_V1(binary_double_dist);
Datum
binary_double_dist(PG_FUNCTION_ARGS)
{
	float8		a = PG_GETARG_FLOAT8(0);
	float8		b = PG_GETARG_FLOAT8(1);
	float8		r;

	r = a - b;
	if (unlikely(isinf(r)) && !isinf(a) && !isinf(b))
		float_overflow_error();

	PG_RETURN_FLOAT8(fabs(r));
}

/**************************************************
 * binary_double ops
 **************************************************/


Datum
gbt_binary_double_compress(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);

	PG_RETURN_POINTER(gbt_num_compress(entry, &tinfo));
}

Datum
gbt_binary_double_fetch(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);

	PG_RETURN_POINTER(gbt_num_fetch(entry, &tinfo));
}

Datum
gbt_binary_double_consistent(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
	float8		query = PG_GETARG_FLOAT8(1);
	StrategyNumber strategy = (StrategyNumber) PG_GETARG_UINT16(2);

	/* Oid		subtype = PG_GETARG_OID(3); */
	bool	   *recheck = (bool *) PG_GETARG_POINTER(4);
	float8KEY  *kkk = (float8KEY *) DatumGetPointer(entry->key);
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
gbt_binary_double_distance(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
	float8		query = PG_GETARG_FLOAT8(1);

	/* Oid		subtype = PG_GETARG_OID(3); */
	float8KEY  *kkk = (float8KEY *) DatumGetPointer(entry->key);
	GBT_NUMKEY_R key;

	key.lower = (GBT_NUMKEY *) &kkk->lower;
	key.upper = (GBT_NUMKEY *) &kkk->upper;

	PG_RETURN_FLOAT8(gbt_num_distance(&key, (void *) &query, GIST_LEAF(entry),
									  &tinfo, fcinfo->flinfo));
}


Datum
gbt_binary_double_union(PG_FUNCTION_ARGS)
{
	GistEntryVector *entryvec = (GistEntryVector *) PG_GETARG_POINTER(0);
	void	   *out = palloc(sizeof(float8KEY));

	*(int *) PG_GETARG_POINTER(1) = sizeof(float8KEY);
	PG_RETURN_POINTER(gbt_num_union((void *) out, entryvec, &tinfo, fcinfo->flinfo));
}


Datum
gbt_binary_double_penalty(PG_FUNCTION_ARGS)
{
	float8KEY  *origentry = (float8KEY *) DatumGetPointer(((GISTENTRY *) PG_GETARG_POINTER(0))->key);
	float8KEY  *newentry = (float8KEY *) DatumGetPointer(((GISTENTRY *) PG_GETARG_POINTER(1))->key);
	float	   *result = (float *) PG_GETARG_POINTER(2);

	penalty_num(result, origentry->lower, origentry->upper, newentry->lower, newentry->upper);

	PG_RETURN_POINTER(result);
}

Datum
gbt_binary_double_picksplit(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(gbt_num_picksplit((GistEntryVector *) PG_GETARG_POINTER(0),
										(GIST_SPLITVEC *) PG_GETARG_POINTER(1),
										&tinfo, fcinfo->flinfo));
}

Datum
gbt_binary_double_same(PG_FUNCTION_ARGS)
{
	float8KEY  *b1 = (float8KEY *) PG_GETARG_POINTER(0);
	float8KEY  *b2 = (float8KEY *) PG_GETARG_POINTER(1);
	bool	   *result = (bool *) PG_GETARG_POINTER(2);

	*result = gbt_num_same((void *) b1, (void *) b2, &tinfo, fcinfo->flinfo);
	PG_RETURN_POINTER(result);
}
