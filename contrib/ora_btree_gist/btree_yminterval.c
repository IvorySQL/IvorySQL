/*
 * contrib/ora_btree_gist/btree_yminterval.c
 */
#include "postgres.h"

#include "btree_gist.h"
#include "btree_utils_num.h"
#include "utils/builtins.h"
#include "utils/timestamp.h"
#include "../ivorysql_ora/src/include/common_datatypes.h"

typedef struct
{
	Interval	lower,
				upper;
} intvKEY;


/*
** interval year to month ops
*/
PG_FUNCTION_INFO_V1(gbt_ymintv_compress);
PG_FUNCTION_INFO_V1(gbt_ymintv_fetch);
PG_FUNCTION_INFO_V1(gbt_ymintv_decompress);
PG_FUNCTION_INFO_V1(gbt_ymintv_union);
PG_FUNCTION_INFO_V1(gbt_ymintv_picksplit);
PG_FUNCTION_INFO_V1(gbt_ymintv_consistent);
PG_FUNCTION_INFO_V1(gbt_ymintv_distance);
PG_FUNCTION_INFO_V1(gbt_ymintv_penalty);
PG_FUNCTION_INFO_V1(gbt_ymintv_same);


static bool
gbt_ymintvgt(const void *a, const void *b, FmgrInfo *flinfo)
{
	return DatumGetBool(DirectFunctionCall2(yminterval_gt, IntervalPGetDatum(a), IntervalPGetDatum(b)));
}

static bool
gbt_ymintvge(const void *a, const void *b, FmgrInfo *flinfo)
{
	return DatumGetBool(DirectFunctionCall2(yminterval_ge, IntervalPGetDatum(a), IntervalPGetDatum(b)));
}

static bool
gbt_ymintveq(const void *a, const void *b, FmgrInfo *flinfo)
{
	return DatumGetBool(DirectFunctionCall2(yminterval_eq, IntervalPGetDatum(a), IntervalPGetDatum(b)));
}

static bool
gbt_ymintvle(const void *a, const void *b, FmgrInfo *flinfo)
{
	return DatumGetBool(DirectFunctionCall2(yminterval_le, IntervalPGetDatum(a), IntervalPGetDatum(b)));
}

static bool
gbt_ymintvlt(const void *a, const void *b, FmgrInfo *flinfo)
{
	return DatumGetBool(DirectFunctionCall2(yminterval_lt, IntervalPGetDatum(a), IntervalPGetDatum(b)));
}

static int
gbt_ymintvkey_cmp(const void *a, const void *b, FmgrInfo *flinfo)
{
	intvKEY    *ia = (intvKEY *) (((const Nsrt *) a)->t);
	intvKEY    *ib = (intvKEY *) (((const Nsrt *) b)->t);
	int			res;

	res = DatumGetInt32(DirectFunctionCall2(yminterval_cmp, IntervalPGetDatum(&ia->lower), IntervalPGetDatum(&ib->lower)));
	if (res == 0)
		return DatumGetInt32(DirectFunctionCall2(yminterval_cmp, IntervalPGetDatum(&ia->upper), IntervalPGetDatum(&ib->upper)));

	return res;
}


static double
intr2num(const Interval *i)
{
	return INTERVAL_TO_SEC(i);
}

static float8
gbt_ymintv_dist(const void *a, const void *b, FmgrInfo *flinfo)
{
	return fabs(intr2num((const Interval *) a) - intr2num((const Interval *) b));
}

/*
 * INTERVALSIZE should be the actual size-on-disk of an Interval, as shown
 * in pg_type.  This might be less than sizeof(Interval) if the compiler
 * insists on adding alignment padding at the end of the struct.  (Note:
 * this concern is obsolete with the current definition of Interval, but
 * was real before a separate "day" field was added to it.)
 */
#define INTERVALSIZE 16

static const gbtree_ninfo tinfo =
{
	gbt_t_intv,
	sizeof(Interval),
	32,							/* sizeof(gbtreekey32) */
	gbt_ymintvgt,
	gbt_ymintvge,
	gbt_ymintveq,
	gbt_ymintvle,
	gbt_ymintvlt,
	gbt_ymintvkey_cmp,
	gbt_ymintv_dist
};


Interval *
abs_yminterval(Interval *a)
{
	static Interval zero = {0, 0, 0};

	if (DatumGetBool(DirectFunctionCall2(yminterval_lt,
										 IntervalPGetDatum(a),
										 IntervalPGetDatum(&zero))))
		a = DatumGetIntervalP(DirectFunctionCall1(interval_um,
												  IntervalPGetDatum(a)));

	return a;
}

PG_FUNCTION_INFO_V1(yminterval_dist);
Datum
yminterval_dist(PG_FUNCTION_ARGS)
{
	Datum		diff = DirectFunctionCall2(yminterval_mi,
										   PG_GETARG_DATUM(0),
										   PG_GETARG_DATUM(1));

	PG_RETURN_INTERVAL_P(abs_yminterval(DatumGetIntervalP(diff)));
}


/**************************************************
 * interval ops
 **************************************************/


Datum
gbt_ymintv_compress(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
	GISTENTRY  *retval = entry;

	if (entry->leafkey || INTERVALSIZE != sizeof(Interval))
	{
		char	   *r = (char *) palloc(2 * INTERVALSIZE);

		retval = palloc(sizeof(GISTENTRY));

		if (entry->leafkey)
		{
			Interval   *key = DatumGetIntervalP(entry->key);

			memcpy(r, key, INTERVALSIZE);
			memcpy(r + INTERVALSIZE, key, INTERVALSIZE);
		}
		else
		{
			intvKEY    *key = (intvKEY *) DatumGetPointer(entry->key);

			memcpy(r, &key->lower, INTERVALSIZE);
			memcpy(r + INTERVALSIZE, &key->upper, INTERVALSIZE);
		}
		gistentryinit(*retval, PointerGetDatum(r),
					  entry->rel, entry->page,
					  entry->offset, false);
	}

	PG_RETURN_POINTER(retval);
}

Datum
gbt_ymintv_fetch(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);

	PG_RETURN_POINTER(gbt_num_fetch(entry, &tinfo));
}

Datum
gbt_ymintv_decompress(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
	GISTENTRY  *retval = entry;

	if (INTERVALSIZE != sizeof(Interval))
	{
		intvKEY    *r = palloc(sizeof(intvKEY));
		char	   *key = DatumGetPointer(entry->key);

		retval = palloc(sizeof(GISTENTRY));
		memcpy(&r->lower, key, INTERVALSIZE);
		memcpy(&r->upper, key + INTERVALSIZE, INTERVALSIZE);

		gistentryinit(*retval, PointerGetDatum(r),
					  entry->rel, entry->page,
					  entry->offset, false);
	}
	PG_RETURN_POINTER(retval);
}


Datum
gbt_ymintv_consistent(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
	Interval   *query = PG_GETARG_INTERVAL_P(1);
	StrategyNumber strategy = (StrategyNumber) PG_GETARG_UINT16(2);

	/* Oid		subtype = PG_GETARG_OID(3); */
	bool	   *recheck = (bool *) PG_GETARG_POINTER(4);
	intvKEY    *kkk = (intvKEY *) DatumGetPointer(entry->key);
	GBT_NUMKEY_R key;

	/* All cases served by this function are exact */
	*recheck = false;

	key.lower = (GBT_NUMKEY *) &kkk->lower;
	key.upper = (GBT_NUMKEY *) &kkk->upper;

	PG_RETURN_BOOL(gbt_num_consistent(&key, (void *) query, &strategy,
									  GIST_LEAF(entry), &tinfo, fcinfo->flinfo));
}


Datum
gbt_ymintv_distance(PG_FUNCTION_ARGS)
{
	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
	Interval   *query = PG_GETARG_INTERVAL_P(1);

	/* Oid		subtype = PG_GETARG_OID(3); */
	intvKEY    *kkk = (intvKEY *) DatumGetPointer(entry->key);
	GBT_NUMKEY_R key;

	key.lower = (GBT_NUMKEY *) &kkk->lower;
	key.upper = (GBT_NUMKEY *) &kkk->upper;

	PG_RETURN_FLOAT8(gbt_num_distance(&key, (void *) query, GIST_LEAF(entry),
									  &tinfo, fcinfo->flinfo));
}


Datum
gbt_ymintv_union(PG_FUNCTION_ARGS)
{
	GistEntryVector *entryvec = (GistEntryVector *) PG_GETARG_POINTER(0);
	void	   *out = palloc(sizeof(intvKEY));

	*(int *) PG_GETARG_POINTER(1) = sizeof(intvKEY);
	PG_RETURN_POINTER(gbt_num_union((void *) out, entryvec, &tinfo, fcinfo->flinfo));
}


Datum
gbt_ymintv_penalty(PG_FUNCTION_ARGS)
{
	intvKEY    *origentry = (intvKEY *) DatumGetPointer(((GISTENTRY *) PG_GETARG_POINTER(0))->key);
	intvKEY    *newentry = (intvKEY *) DatumGetPointer(((GISTENTRY *) PG_GETARG_POINTER(1))->key);
	float	   *result = (float *) PG_GETARG_POINTER(2);
	double		iorg[2],
				inew[2];

	iorg[0] = intr2num(&origentry->lower);
	iorg[1] = intr2num(&origentry->upper);
	inew[0] = intr2num(&newentry->lower);
	inew[1] = intr2num(&newentry->upper);

	penalty_num(result, iorg[0], iorg[1], inew[0], inew[1]);

	PG_RETURN_POINTER(result);
}

Datum
gbt_ymintv_picksplit(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(gbt_num_picksplit((GistEntryVector *) PG_GETARG_POINTER(0),
										(GIST_SPLITVEC *) PG_GETARG_POINTER(1),
										&tinfo, fcinfo->flinfo));
}

Datum
gbt_ymintv_same(PG_FUNCTION_ARGS)
{
	intvKEY    *b1 = (intvKEY *) PG_GETARG_POINTER(0);
	intvKEY    *b2 = (intvKEY *) PG_GETARG_POINTER(1);
	bool	   *result = (bool *) PG_GETARG_POINTER(2);

	*result = gbt_num_same((void *) b1, (void *) b2, &tinfo, fcinfo->flinfo);
	PG_RETURN_POINTER(result);
}
