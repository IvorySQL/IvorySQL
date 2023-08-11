/*
 * contrib/btree_gist/btree_gist.c
 */
#include "postgres.h"

#include "utils/builtins.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(gbt_decompress);
PG_FUNCTION_INFO_V1(gbtreekey_in);
PG_FUNCTION_INFO_V1(gbtreekey_out);

/**************************************************
 * In/Out for keys
 **************************************************/


Datum
gbtreekey_in(PG_FUNCTION_ARGS)
{
	Oid			typioparam = PG_GETARG_OID(1);

	ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			 errmsg("cannot accept a value of type %s",
					format_type_extended(typioparam, -1,
										 FORMAT_TYPE_ALLOW_INVALID))));

	PG_RETURN_VOID();			/* keep compiler quiet */
}

Datum
gbtreekey_out(PG_FUNCTION_ARGS)
{
	/* Sadly, we do not receive any indication of the specific type */
	ereport(ERROR,
			(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
			 errmsg("cannot display a value of type %s", "gbtreekey?")));

	PG_RETURN_VOID();			/* keep compiler quiet */
}


/*
** GiST DeCompress methods
** do not do anything.
*/
Datum
gbt_decompress(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(PG_GETARG_POINTER(0));
}
