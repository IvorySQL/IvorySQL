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
 * Implementation of Oracle's UTL_RAW package.
 * This module is part of ivorysql_ora extension.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_raw/utl_raw.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"
#include "fmgr.h"
#include "varatt.h"
#include "utils/builtins.h"

PG_FUNCTION_INFO_V1(ora_utl_raw_cast_to_raw);

Datum
ora_utl_raw_cast_to_raw(PG_FUNCTION_ARGS)
{
	text	   *input;
	char	   *data;
	int			datalen;
	text	   *result;
	char	   *out;
	static const char hex[] = "0123456789ABCDEF";

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	input = PG_GETARG_TEXT_PP(0);
	data = VARDATA_ANY(input);
	datalen = VARSIZE_ANY_EXHDR(input);

	result = palloc(VARHDRSZ + datalen * 2);
	out = VARDATA(result);

	for (int i = 0; i < datalen; i++)
	{
		unsigned char b = (unsigned char) data[i];
		*out++ = hex[b >> 4];
		*out++ = hex[b & 0x0F];
	}

	SET_VARSIZE(result, VARHDRSZ + datalen * 2);
	PG_RETURN_TEXT_P(result);
}
