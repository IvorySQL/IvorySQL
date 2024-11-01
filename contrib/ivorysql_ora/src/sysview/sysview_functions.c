/*------------------------------------------------------------------
 * 
 * File: sysview_functions.c
 *
 * Abstract: 
 * 		Function which converts all-uppercase text to all-lowercase text 
 * 		and vice versa.
 *
 * Copyright:
 * Portions Copyright (c) 2024, Ivory SQL Global Development Team
 *
 * Identification:
 *		contrib/ivorysql_ora/src/sysview/sysview_functions.c
 *
 *------------------------------------------------------------------
 */

#include "postgres.h"

#include "fmgr.h"
#include "parser/scansup.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/ora_compatible.h"



PG_FUNCTION_INFO_V1(ora_case_trans);
Datum
ora_case_trans(PG_FUNCTION_ARGS)
{
	char	*string,
			*retval;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	string = (char *) TextDatumGetCString(PG_GETARG_DATUM(0));

	/* if identifier_case_switch is NORMAL, return it directly. */
	if (NORMAL == identifier_case_switch)
		PG_RETURN_DATUM(PG_GETARG_DATUM(0));

	/* if identifier_case_switch is LOWERCASE, return all-lowercase text. */
	if (LOWERCASE == identifier_case_switch)
	{
		retval = downcase_identifier(string, strlen(string), true, true);
		PG_RETURN_TEXT_P(CStringGetTextDatum(retval));
	}

	/* otherwise, performs the transformation. */
	retval = identifier_case_transform(string, strlen(string));
	PG_RETURN_TEXT_P(CStringGetTextDatum(retval));
}


