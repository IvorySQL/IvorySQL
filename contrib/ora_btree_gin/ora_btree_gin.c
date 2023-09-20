/*
 * contrib/ora_btree_gin/ora_btree_gin.c
 */
#include "postgres.h"
#include "varatt.h"
#include <limits.h>

#include "access/stratnum.h"
#include "utils/builtins.h"
#include "utils/bytea.h"
#include "utils/cash.h"
#include "utils/date.h"
#include "utils/float.h"
#include "utils/inet.h"
#include "utils/numeric.h"
#include "utils/timestamp.h"
#include "utils/uuid.h"
#include "utils/varbit.h"
#include "utils/varlena.h"


PG_MODULE_MAGIC;

typedef struct QueryInfo
{
	StrategyNumber strategy;
	Datum		datum;
	bool		is_varlena;
	Datum		(*typecmp) (FunctionCallInfo);
} QueryInfo;

/*** GIN support functions shared by all datatypes ***/

static Datum
gin_btree_extract_value(FunctionCallInfo fcinfo, bool is_varlena)
{
	Datum		datum = PG_GETARG_DATUM(0);
	int32	   *nentries = (int32 *) PG_GETARG_POINTER(1);
	Datum	   *entries = (Datum *) palloc(sizeof(Datum));

	if (is_varlena)
		datum = PointerGetDatum(PG_DETOAST_DATUM(datum));
	entries[0] = datum;
	*nentries = 1;

	PG_RETURN_POINTER(entries);
}

/*
 * For BTGreaterEqualStrategyNumber, BTGreaterStrategyNumber, and
 * BTEqualStrategyNumber we want to start the index scan at the
 * supplied query datum, and work forward. For BTLessStrategyNumber
 * and BTLessEqualStrategyNumber, we need to start at the leftmost
 * key, and work forward until the supplied query datum (which must be
 * sent along inside the QueryInfo structure).
 */
static Datum
gin_btree_extract_query(FunctionCallInfo fcinfo,
						bool is_varlena,
						Datum (*leftmostvalue) (void),
						Datum (*typecmp) (FunctionCallInfo))
{
	Datum		datum = PG_GETARG_DATUM(0);
	int32	   *nentries = (int32 *) PG_GETARG_POINTER(1);
	StrategyNumber strategy = PG_GETARG_UINT16(2);
	bool	  **partialmatch = (bool **) PG_GETARG_POINTER(3);
	Pointer   **extra_data = (Pointer **) PG_GETARG_POINTER(4);
	Datum	   *entries = (Datum *) palloc(sizeof(Datum));
	QueryInfo  *data = (QueryInfo *) palloc(sizeof(QueryInfo));
	bool	   *ptr_partialmatch;

	*nentries = 1;
	ptr_partialmatch = *partialmatch = (bool *) palloc(sizeof(bool));
	*ptr_partialmatch = false;
	if (is_varlena)
		datum = PointerGetDatum(PG_DETOAST_DATUM(datum));
	data->strategy = strategy;
	data->datum = datum;
	data->is_varlena = is_varlena;
	data->typecmp = typecmp;
	*extra_data = (Pointer *) palloc(sizeof(Pointer));
	**extra_data = (Pointer) data;

	switch (strategy)
	{
		case BTLessStrategyNumber:
		case BTLessEqualStrategyNumber:
			entries[0] = leftmostvalue();
			*ptr_partialmatch = true;
			break;
		case BTGreaterEqualStrategyNumber:
		case BTGreaterStrategyNumber:
			*ptr_partialmatch = true;
			/* FALLTHROUGH */
		case BTEqualStrategyNumber:
			entries[0] = datum;
			break;
		default:
			elog(ERROR, "unrecognized strategy number: %d", strategy);
	}

	PG_RETURN_POINTER(entries);
}

/*
 * Datum a is a value from extract_query method and for BTLess*
 * strategy it is a left-most value.  So, use original datum from QueryInfo
 * to decide to stop scanning or not.  Datum b is always from index.
 */
static Datum
gin_btree_compare_prefix(FunctionCallInfo fcinfo)
{
	Datum		a = PG_GETARG_DATUM(0);
	Datum		b = PG_GETARG_DATUM(1);
	QueryInfo  *data = (QueryInfo *) PG_GETARG_POINTER(3);
	int32		res,
				cmp;

	cmp = DatumGetInt32(CallerFInfoFunctionCall2(data->typecmp,
												 fcinfo->flinfo,
												 PG_GET_COLLATION(),
												 (data->strategy == BTLessStrategyNumber ||
												  data->strategy == BTLessEqualStrategyNumber)
												 ? data->datum : a,
												 b));

	switch (data->strategy)
	{
		case BTLessStrategyNumber:
			/* If original datum > indexed one then return match */
			if (cmp > 0)
				res = 0;
			else
				res = 1;
			break;
		case BTLessEqualStrategyNumber:
			/* The same except equality */
			if (cmp >= 0)
				res = 0;
			else
				res = 1;
			break;
		case BTEqualStrategyNumber:
			if (cmp != 0)
				res = 1;
			else
				res = 0;
			break;
		case BTGreaterEqualStrategyNumber:
			/* If original datum <= indexed one then return match */
			if (cmp <= 0)
				res = 0;
			else
				res = 1;
			break;
		case BTGreaterStrategyNumber:
			/* If original datum <= indexed one then return match */
			/* If original datum == indexed one then continue scan */
			if (cmp < 0)
				res = 0;
			else if (cmp == 0)
				res = -1;
			else
				res = 1;
			break;
		default:
			elog(ERROR, "unrecognized strategy number: %d",
				 data->strategy);
			res = 0;
	}

	PG_RETURN_INT32(res);
}

/* oravarcharchar_cmp()
 * Internal comparison function for oravarchar.
 * Returns -1, 0 or 1
 */
static int
oravarcharchar_cmp(VarChar *arg1, VarChar *arg2, Oid collid)
{
	char	   *a1p,
			   *a2p;
	int			len1,
				len2;

	a1p = VARDATA_ANY(arg1);
	a2p = VARDATA_ANY(arg2);

	len1 = VARSIZE_ANY_EXHDR(arg1);
	len2 = VARSIZE_ANY_EXHDR(arg2);

	return varstr_cmp(a1p, len1, a2p, len2, collid);
}

static Datum
oratimestamp_cmp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

static Datum
oratimestamptz_cmp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

static Datum
oratimestampltz_cmp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

static Datum
oradate_cmp(PG_FUNCTION_ARGS)
{
	Timestamp	dt1 = PG_GETARG_TIMESTAMP(0);
	Timestamp	dt2 = PG_GETARG_TIMESTAMP(1);

	PG_RETURN_INT32(timestamp_cmp_internal(dt1, dt2));
}

static Datum
bt_oravarchar_cmp(PG_FUNCTION_ARGS)
{
	VarChar	   *arg1 = PG_GETARG_VARCHAR_PP(0);
	VarChar	   *arg2 = PG_GETARG_VARCHAR_PP(1);
	int32		result;

	result = oravarcharchar_cmp(arg1, arg2, PG_GET_COLLATION());

	PG_FREE_IF_COPY(arg1, 0);
	PG_FREE_IF_COPY(arg2, 1);

	PG_RETURN_INT32(result);
}


PG_FUNCTION_INFO_V1(gin_btree_consistent);
Datum
gin_btree_consistent(PG_FUNCTION_ARGS)
{
	bool	   *recheck = (bool *) PG_GETARG_POINTER(5);

	*recheck = false;
	PG_RETURN_BOOL(true);
}

/*** GIN_SUPPORT macro defines the datatype specific functions ***/

#define GIN_SUPPORT(type, is_varlena, leftmostvalue, typecmp)				\
PG_FUNCTION_INFO_V1(gin_extract_value_##type);								\
Datum																		\
gin_extract_value_##type(PG_FUNCTION_ARGS)									\
{																			\
	return gin_btree_extract_value(fcinfo, is_varlena);						\
}	\
PG_FUNCTION_INFO_V1(gin_extract_query_##type);								\
Datum																		\
gin_extract_query_##type(PG_FUNCTION_ARGS)									\
{																			\
	return gin_btree_extract_query(fcinfo,									\
								   is_varlena, leftmostvalue, typecmp);		\
}	\
PG_FUNCTION_INFO_V1(gin_compare_prefix_##type);								\
Datum																		\
gin_compare_prefix_##type(PG_FUNCTION_ARGS)									\
{																			\
	return gin_btree_compare_prefix(fcinfo);								\
}


/*** Datatype specifications ***/

static Datum
leftmostvalue_varchar2(void)
{
	return PointerGetDatum(cstring_to_text_with_len("", 0));
}

GIN_SUPPORT(varchar2, true, leftmostvalue_varchar2, bt_oravarchar_cmp)


/*
 * Number type hasn't a real left-most value, so we use PointerGetDatum(NULL)
 * (*not* a SQL NULL) to represent that.  We can get away with that because
 * the value returned by our leftmostvalue function will never be stored in
 * the index nor passed to anything except our compare and prefix-comparison
 * functions.  The same trick could be used for other pass-by-reference types.
 */

#define NUMBER_IS_LEFTMOST(x)	((x) == NULL)

PG_FUNCTION_INFO_V1(gin_number_cmp);

Datum
gin_number_cmp(PG_FUNCTION_ARGS)
{
	Numeric		a = (Numeric) PG_GETARG_POINTER(0);
	Numeric		b = (Numeric) PG_GETARG_POINTER(1);
	int			res = 0;

	if (NUMBER_IS_LEFTMOST(a))
	{
		res = (NUMBER_IS_LEFTMOST(b)) ? 0 : -1;
	}
	else if (NUMBER_IS_LEFTMOST(b))
	{
		res = 1;
	}
	else
	{
		res = DatumGetInt32(DirectFunctionCall2(numeric_cmp,
												NumericGetDatum(a),
												NumericGetDatum(b)));
	}

	PG_RETURN_INT32(res);
}

static Datum
leftmostvalue_number(void)
{
	return PointerGetDatum(NULL);
}

GIN_SUPPORT(number, true, leftmostvalue_number, gin_number_cmp)

static Datum
leftmostvalue_binary_float(void)
{
	return Float4GetDatum(-get_float4_infinity());
}

GIN_SUPPORT(binary_float, false, leftmostvalue_binary_float, btfloat4cmp)

static Datum
leftmostvalue_binary_double(void)
{
	return Float8GetDatum(-get_float8_infinity());
}

GIN_SUPPORT(binary_double, false, leftmostvalue_binary_double, btfloat8cmp)

static Datum
leftmostvalue_timestamp(void)
{
	return TimestampGetDatum(DT_NOBEGIN);
}

GIN_SUPPORT(oratimestamp, false, leftmostvalue_timestamp, oratimestamp_cmp)

GIN_SUPPORT(oratimestamptz, false, leftmostvalue_timestamp, oratimestamptz_cmp)

GIN_SUPPORT(oratimestampltz, false, leftmostvalue_timestamp, oratimestampltz_cmp)

GIN_SUPPORT(oradate, false, leftmostvalue_timestamp, oradate_cmp)


