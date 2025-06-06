/*
    pg_get_functiondef_no_input
        The achieve of pg_get_functiondef()c
*/
#include "postgres.h"
#include "fmgr.h"
#include "utils/elog.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(pg_get_functiondef_no_input);

Datum pg_get_functiondef_no_input(PG_FUNCTION_ARGS)
{
    if (PG_NARGS() <= 0)
    {
        ereport(ERROR, errmsg("Nothing Input"),
                errhint("target should be the name or the oid of the function."),
                errdetail("SELECT pg_get_functiondef(target, ...);"));
        PG_RETURN_NULL();
    }
    PG_RETURN_NULL();
}
