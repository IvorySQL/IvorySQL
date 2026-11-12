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
 * Implementation of Oracle's DBMS_DDL package.
 *
 * This file implements the two value-independent DDL helpers:
 *   ALTER_COMPILE(type, schema, name)
 *   ANALYZE_OBJECT(type, schema, name, method)
 *
 * The Oracle-specific tuning options of ANALYZE_OBJECT and the deprecated
 * WRAP/CREATE_WRAPPED subprograms are out of scope; the package SQL comments
 * document this.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_ddl/dbms_ddl.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <ctype.h>

#include "access/htup_details.h"
#include "catalog/namespace.h"
#include "commands/packagecmds.h"
#include "executor/spi.h"
#include "miscadmin.h"
#include "nodes/parsenodes.h"
#include "utils/acl.h"
#include "utils/packagecache.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"

PG_FUNCTION_INFO_V1(ora_dbms_ddl_alter_compile);
PG_FUNCTION_INFO_V1(ora_dbms_ddl_analyze_object);

/*
 * normalize_ident
 *
 * Oracle stores unquoted identifiers in upper case, while PostgreSQL folds
 * them to lower case.  A name that consists only of upper-case characters is
 * therefore treated as an unquoted Oracle name and folded to lower case.
 * Mixed-case and lower-case names are treated as quoted identifiers and kept
 * as given.
 */
static char *
normalize_ident(const char *ident)
{
	char	   *result = pstrdup(ident);
	bool		has_lower = false;
	bool		has_upper = false;
	char	   *p;

	for (p = result; *p; p++)
	{
		if (islower((unsigned char) *p))
			has_lower = true;
		else if (isupper((unsigned char) *p))
			has_upper = true;
	}

	if (has_upper && !has_lower)
	{
		for (p = result; *p; p++)
			*p = pg_tolower((unsigned char) *p);
	}

	return result;
}

/*
 * upper_ascii
 *
 * Upper-case an Oracle keyword argument such as the object type or the
 * analyze method.  Only ASCII letters are folded; the value is compared
 * against a fixed set of keywords.
 */
static char *
upper_ascii(const char *value)
{
	char	   *result = pstrdup(value);
	char	   *p;

	for (p = result; *p; p++)
		*p = pg_toupper((unsigned char) *p);

	return result;
}

/*
 * check_nonempty_arg
 *
 * DBMS_DDL rejects NULL and empty arguments.  The C functions are not
 * STRICT so that a NULL argument reaches this check instead of silently
 * returning NULL.
 */
static void
check_nonempty_arg(FunctionCallInfo fcinfo, int argno, const char *argname)
{
	if (PG_ARGISNULL(argno))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("%s argument cannot be NULL", argname)));

	if (VARSIZE_ANY_EXHDR(PG_GETARG_TEXT_PP(argno)) == 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("%s argument cannot be empty", argname)));
}

/*
 * exec_utility
 *
 * Execute one generated DDL statement.  The caller has already built the
 * statement from a whitelisted object type and quoted identifiers.
 */
static void
exec_utility(const char *command)
{
	int			rc;

	rc = SPI_execute(command, false, 0);
	if (rc < 0)
		elog(ERROR, "SPI_execute failed: %s", SPI_result_code_string(rc));
}

/*
 * ora_dbms_ddl_alter_compile
 *
 * Compile a stored procedure, function, package or package body.  For
 * functions and procedures every overload matching the name is compiled,
 * mirroring Oracle's ALTER_COMPILE behaviour without requiring an argument
 * list.
 */
Datum
ora_dbms_ddl_alter_compile(PG_FUNCTION_ARGS)
{
	char	   *type;
	char	   *schema;
	char	   *name;
	int			rc;
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];
	char		nulls[2] = {0, 0};

	check_nonempty_arg(fcinfo, 0, "type");
	check_nonempty_arg(fcinfo, 1, "schema");
	check_nonempty_arg(fcinfo, 2, "name");

	type = upper_ascii(text_to_cstring(PG_GETARG_TEXT_PP(0)));
	schema = normalize_ident(text_to_cstring(PG_GETARG_TEXT_PP(1)));
	name = normalize_ident(text_to_cstring(PG_GETARG_TEXT_PP(2)));

	values[0] = CStringGetTextDatum(schema);
	values[1] = CStringGetTextDatum(name);

	if (SPI_connect() != SPI_OK_CONNECT)
		elog(ERROR, "SPI_connect failed");

	if (strcmp(type, "FUNCTION") == 0 || strcmp(type, "PROCEDURE") == 0)
	{
		const char *kind = (strcmp(type, "FUNCTION") == 0) ? "f" : "p";
		const char *query;
		List	   *commands = NIL;
		ListCell   *lc;
		int			i;

		query = psprintf("SELECT p.oid::regprocedure::text "
						 "FROM pg_catalog.pg_proc p "
						 "JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace "
						 "WHERE n.nspname = $1 AND p.proname = $2 "
						 "AND p.prokind = '%s'", kind);

		rc = SPI_execute_with_args(query, 2, argtypes, values, nulls,
								   false, 0);
		if (rc != SPI_OK_SELECT)
			elog(ERROR, "SPI_execute_with_args failed: %s",
				 SPI_result_code_string(rc));

		if (SPI_processed == 0)
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("object %s.%s does not exist", schema, name)));

		for (i = 0; i < (int) SPI_processed; i++)
		{
			char	   *ident = SPI_getvalue(SPI_tuptable->vals[i],
										 SPI_tuptable->tupdesc, 1);

			if (ident != NULL)
				commands = lappend(commands, psprintf("ALTER %s %s COMPILE",
													  type, ident));
		}

		foreach(lc, commands)
			exec_utility((char *) lfirst(lc));
	}
	else if (strcmp(type, "PACKAGE") == 0 ||
			 strcmp(type, "PACKAGE BODY") == 0)
	{
		List	   *pkgname;
		Oid			pkgoid;
		Oid			bodyid;

		/*
		 * ALTER PACKAGE ... COMPILE is not accepted by the Oracle grammar,
		 * so use the package-cache API the ALTER command itself uses.
		 */
		pkgname = list_make2(makeString(schema), makeString(name));
		pkgoid = LookupPackageByNames(pkgname, true);
		if (!OidIsValid(pkgoid))
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("object %s.%s does not exist", schema, name)));

		if (!pg_package_ownercheck(pkgoid, GetUserId()))
			aclcheck_error(ACLCHECK_NOT_OWNER, OBJECT_PACKAGE,
						   psprintf("%s.%s", schema, name));

		FreePackageCache(&pkgoid);
		bodyid = get_package_bodyid(pkgoid, true);

		if (strcmp(type, "PACKAGE BODY") == 0)
		{
			if (!OidIsValid(bodyid))
				ereport(ERROR,
						(errcode(ERRCODE_UNDEFINED_OBJECT),
						 errmsg("package body %s.%s does not exist",
								schema, name)));
			ValidatroPackage(bodyid, true);
		}
		else if (OidIsValid(bodyid))
			ValidatroPackage(bodyid, true);
		else
			ValidatroPackage(pkgoid, false);
	}
	else
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("invalid object type \"%s\"", type)));

	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * ora_dbms_ddl_analyze_object
 *
 * Update the statistics of a table.  Oracle's ESTIMATE_ROWS, ESTIMATE_PERCENT,
 * METHOD_OPT and PARTNAME tuning options are accepted by the package wrapper
 * but not forwarded: PostgreSQL chooses its own sample and has no per-column
 * method options.
 */
Datum
ora_dbms_ddl_analyze_object(PG_FUNCTION_ARGS)
{
	char	   *type;
	char	   *schema;
	char	   *name;
	char	   *method;
	char	   *command;
	int			rc;
	Oid			argtypes[2] = {TEXTOID, TEXTOID};
	Datum		values[2];
	char		nulls[2] = {0, 0};

	check_nonempty_arg(fcinfo, 0, "type");
	check_nonempty_arg(fcinfo, 1, "schema");
	check_nonempty_arg(fcinfo, 2, "name");
	check_nonempty_arg(fcinfo, 3, "method");

	type = upper_ascii(text_to_cstring(PG_GETARG_TEXT_PP(0)));
	schema = normalize_ident(text_to_cstring(PG_GETARG_TEXT_PP(1)));
	name = normalize_ident(text_to_cstring(PG_GETARG_TEXT_PP(2)));
	method = upper_ascii(text_to_cstring(PG_GETARG_TEXT_PP(3)));

	if (strcmp(type, "TABLE") != 0)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("analyze_object does not support object type \"%s\"",
						type)));

	if (strcmp(method, "COMPUTE") != 0 && strcmp(method, "ESTIMATE") != 0)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("analyze_object does not support method \"%s\"",
						method)));

	values[0] = CStringGetTextDatum(schema);
	values[1] = CStringGetTextDatum(name);

	if (SPI_connect() != SPI_OK_CONNECT)
		elog(ERROR, "SPI_connect failed");

	rc = SPI_execute_with_args("SELECT 1 FROM pg_catalog.pg_class c "
							   "JOIN pg_catalog.pg_namespace n "
							   "ON n.oid = c.relnamespace "
							   "WHERE n.nspname = $1 AND c.relname = $2 "
							   "AND c.relkind IN ('r','m','p','f')",
							   2, argtypes, values, nulls, false, 0);
	if (rc != SPI_OK_SELECT)
		elog(ERROR, "SPI_execute_with_args failed: %s",
			 SPI_result_code_string(rc));

	if (SPI_processed == 0)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("object %s.%s does not exist", schema, name)));

	command = psprintf("ANALYZE %s",
					   quote_qualified_identifier(schema, name));
	exec_utility(command);

	SPI_finish();

	PG_RETURN_VOID();
}
