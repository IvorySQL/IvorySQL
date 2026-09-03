/*-------------------------------------------------------------------------
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
 * guc.c
 *
 * Ivorysql_ora GUC variables define.
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/guc/guc.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <ctype.h>

#include "pgtime.h"
#include "utils/guc.h"

#include "../include/guc.h"

/* Backing variable for ivorysql.dbtimezone, read by dbtimezone(). */
char	   *ivorysql_dbtimezone = NULL;

/*
 * check_dbtimezone: GUC check_hook for ivorysql.dbtimezone
 *
 * Accepts either a UTC offset in the form [+-]HH:MI within Oracle's
 * DBTIMEZONE range (-12:59 to +14:00), or a valid time zone region name.
 *
 * The GUC's context is PGC_SUSET, so only a superuser can change it by
 * default. A non-superuser database owner is NOT enough on its own --
 * owning the database only grants permission on ALTER DATABASE itself,
 * not on this GUC. To let a specific non-superuser role manage this
 * setting for their own database(s), a superuser must additionally run:
 *
 *     GRANT SET ON PARAMETER ivorysql.dbtimezone TO <role>;
 *
 * after which that role can run ALTER DATABASE <dbname> SET
 * ivorysql.dbtimezone = '...' (still not a plain SET; see the source
 * check below).
 */
static bool
check_dbtimezone(char **newval, void **extra, GucSource source)
{
	char	   *str = *newval;

	/*
	 * Oracle's DBTIMEZONE is fixed per-database via ALTER DATABASE ... SET
	 * TIME_ZONE and cannot be changed ad hoc within a session. Mirror that
	 * by rejecting any source other than ALTER DATABASE ... SET (applied at
	 * backend start as PGC_S_DATABASE; validated when the ALTER DATABASE
	 * command itself runs as PGC_S_TEST) and the administrative sources used
	 * to establish the cluster-wide default (boot default, postgresql.conf,
	 * postmaster command line/environment) or to replay an already-validated
	 * value (PGC_S_OVERRIDE, e.g. for parallel workers). A plain SET,
	 * ALTER ROLE ... SET, or a client-supplied startup option is refused.
	 */
	if (source == PGC_S_SESSION ||
		source == PGC_S_USER ||
		source == PGC_S_DATABASE_USER ||
		source == PGC_S_CLIENT ||
		source == PGC_S_GLOBAL)
	{
		GUC_check_errcode(ERRCODE_CANT_CHANGE_RUNTIME_PARAM);
		GUC_check_errmsg("parameter \"ivorysql.dbtimezone\" cannot be set");
		GUC_check_errdetail("\"ivorysql.dbtimezone\" can only be set with ALTER DATABASE ... SET, not within a session or per-role.");
		return false;
	}

	if (strlen(str) == 6 &&
		(str[0] == '+' || str[0] == '-') &&
		isdigit((unsigned char) str[1]) && isdigit((unsigned char) str[2]) &&
		str[3] == ':' &&
		isdigit((unsigned char) str[4]) && isdigit((unsigned char) str[5]))
	{
		int			hour = (str[1] - '0') * 10 + (str[2] - '0');
		int			min = (str[4] - '0') * 10 + (str[5] - '0');

		if (min > 59)
		{
			GUC_check_errdetail("invalid minute field in time zone offset \"%s\"", str);
			return false;
		}

		if (str[0] == '+' ? (hour > 14 || (hour == 14 && min != 0)) : (hour > 12))
		{
			GUC_check_errdetail("time zone offset \"%s\" is out of range for DBTIMEZONE (-12:59 to +14:00)", str);
			return false;
		}

		return true;
	}

	if (!pg_tzset(str))
	{
		GUC_check_errdetail("\"%s\" is not a valid UTC offset (+/-HH:MI) or time zone name.", str);
		return false;
	}

	return true;
}

/*
 * Define various GUC.
 */
void
IvorysqlOraDefineGucs(void)
{
	DefineCustomStringVariable("ivorysql.dbtimezone",
								"Sets the database time zone reported by dbtimezone().",
								"Can only be set with ALTER DATABASE ... SET, not with a "
								"plain SET or ALTER ROLE ... SET. Requires superuser, or a "
								"role granted permission via "
								"GRANT SET ON PARAMETER ivorysql.dbtimezone TO <role>.",
								&ivorysql_dbtimezone,
								"+00:00",
								PGC_SUSET,
								0,
								check_dbtimezone,
								NULL,
								NULL);
}
