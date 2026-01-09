/*------------------------------------------------------------------
 * Copyright 2025 IvorySQL Global Development Team
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
 * File: sysview_functions.c
 *
 * Abstract: 
 * 		Function which converts all-uppercase text to all-lowercase text 
 * 		and vice versa.
 *
 * Copyright (c) 2023-2026, IvorySQL Global Development Team
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

PG_FUNCTION_INFO_V1(ora_case_trans);
Datum
ora_case_trans(PG_FUNCTION_ARGS)
{
	char	*string;
	char	*retval;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	string = (char *) TextDatumGetCString(PG_GETARG_DATUM(0));

	retval = identifier_case_transform(string, strlen(string));

	PG_RETURN_TEXT_P(cstring_to_text(retval));
}

