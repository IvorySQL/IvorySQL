/*-------------------------------------------------------------------------------
 * 
 * File: misc_functions.c
 *
 * Abstract: 
 * 		This file contains the implementation of Oracle's
 *		datatype-independent built-in functions.
 *
 * Copyright:
 * Portions Copyright (c) 2024, Ivory SQL Global Development Team
 *
 * Identification:
 *		contrib/ivorysql_ora/src/builtin_functions/misc_functions.c
 *
 *-------------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/formatting.h"
#include "utils/numeric.h"

PG_FUNCTION_INFO_V1(uid);	



Datum
uid(PG_FUNCTION_ARGS)
{
	PG_RETURN_UINT32(GetUserId());
}

