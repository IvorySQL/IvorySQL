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
 * Oracle-compatible LENGTH2 and LENGTH4.
 *
 * LENGTH4 counts UCS4 code points and LENGTH2 counts UCS2 code units, so a
 * supplementary character (above U+FFFF) counts once for LENGTH4 but twice
 * for LENGTH2.
 *
 * contrib/ivorysql_ora/src/builtin_functions/character_length_functions.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "fmgr.h"
#include "mb/pg_wchar.h"
#include "utils/builtins.h"
#include "varatt.h"

PG_FUNCTION_INFO_V1(ora_length2);
PG_FUNCTION_INFO_V1(ora_length4);

/*
 * ora_length4 - length in UCS4 code points
 *
 * For a single-byte encoding this is simply the byte count; otherwise one
 * code point per character.
 */
Datum
ora_length4(PG_FUNCTION_ARGS)
{
	text	   *str = PG_GETARG_TEXT_PP(0);
	int			len = VARSIZE_ANY_EXHDR(str);

	if (pg_database_encoding_max_length() != 1)
		len = pg_mbstrlen_with_len(VARDATA_ANY(str), len);

	PG_RETURN_INT32(len);
}

/*
 * ora_length2 - length in UCS2 code units
 *
 * A supplementary character needs one UCS4 code point but a surrogate pair
 * in UCS2, which is the only place where the two counts differ.
 */
Datum
ora_length2(PG_FUNCTION_ARGS)
{
	text	   *str = PG_GETARG_TEXT_PP(0);
	int			len = VARSIZE_ANY_EXHDR(str);
	int			units = 0;

	if (pg_database_encoding_max_length() == 1)
		PG_RETURN_INT32(len);

	{
		int			nchars = pg_mbstrlen_with_len(VARDATA_ANY(str), len);
		pg_wchar   *wstr = (pg_wchar *) palloc(sizeof(pg_wchar) * (nchars + 1));
		pg_wchar   *wp;
		int			n;

		/* pg_mb2wchar_with_len() stores one code point per character */
		n = pg_mb2wchar_with_len(VARDATA_ANY(str), wstr, len);

		for (wp = wstr; n-- > 0; wp++)
			units += (*wp > 0xFFFF) ? 2 : 1;

		pfree(wstr);
	}

	PG_RETURN_INT32(units);
}
