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
 * dbms_utility.c
 *
 * Implementation of Oracle's DBMS_UTILITY package functions.
 * This module is part of ivorysql_ora extension but calls the PL/iSQL
 * API to access exception context information.
 *
 * Portions Copyright (c) 2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_utility/dbms_utility.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "mb/pg_wchar.h"

#ifndef WIN32
#include <dlfcn.h>
#endif

PG_FUNCTION_INFO_V1(ora_format_error_backtrace);

/*
 * Function pointer type for plisql_get_current_exception_context.
 * We use dynamic lookup to avoid link-time dependency on plisql.so.
 */
typedef const char *(*plisql_get_context_fn)(void);

/*
 * Cached function pointer for plisql_get_current_exception_context.
 * Looked up once on first use.
 */
static plisql_get_context_fn get_exception_context_fn = NULL;
static bool lookup_attempted = false;

/*
 * Look up the plisql_get_current_exception_context function dynamically.
 * Returns the function pointer, or NULL if not found.
 */
static plisql_get_context_fn
lookup_plisql_get_exception_context(void)
{
	void *fn;

	if (lookup_attempted)
		return get_exception_context_fn;

	lookup_attempted = true;

#ifndef WIN32
	/*
	 * Use RTLD_DEFAULT to search all loaded shared objects.
	 * plisql.so should already be loaded when this function is called
	 * from within a PL/iSQL exception handler.
	 */
	fn = dlsym(RTLD_DEFAULT, "plisql_get_current_exception_context");
	if (fn != NULL)
		get_exception_context_fn = (plisql_get_context_fn) fn;
#else
	/*
	 * On Windows, we'd need to use GetProcAddress with the module handle.
	 * For now, just return NULL - this feature requires plisql.
	 */
	fn = NULL;
#endif

	return get_exception_context_fn;
}

/*
 * Transform a single line from PostgreSQL error context format to Oracle format.
 *
 * PostgreSQL format examples:
 *   "PL/pgSQL function test_level3() line 3 at RAISE"
 *   "PL/iSQL function test_level3() line 3 at RAISE"
 *   "PL/iSQL function inline_code_block line 5 at CALL"
 *   "SQL statement \"CALL test_level3()\""
 *
 * Oracle format:
 *   "ORA-06512: at \"SCHEMA.TEST_LEVEL3\", line 3"
 *   "ORA-06512: at line 5"
 *
 * Returns true if line was transformed and appended, false if line should be skipped.
 */
static bool
transform_and_append_line(StringInfo result, const char *line)
{
	const char *p = line;
	const char *func_start;
	const char *func_end;
	const char *line_num_start;
	const char *line_marker;
	int line_num;
	char *func_name;
	char *schema_name;
	char *func_upper;
	char *schema_upper;
	int i;

	/* Skip SQL statement lines */
	if (strncmp(line, "SQL statement", 13) == 0)
		return false;

	/* Look for "PL/pgSQL function" or "PL/iSQL function" */
	if (strncmp(p, "PL/pgSQL function ", 18) == 0)
		p += 18;
	else if (strncmp(p, "PL/iSQL function ", 17) == 0)
		p += 17;
	else
		return false;	/* Unknown format, skip */

	func_start = p;

	/* Find the end of the function name (before the opening parenthesis or space for inline blocks) */
	func_end = strchr(p, '(');
	if (!func_end)
	{
		/* No parenthesis - might be inline_code_block which has format "inline_code_block line N" */
		func_end = strstr(p, " line ");
		if (!func_end)
			return false;
	}

	/* Extract function name */
	func_name = pnstrdup(func_start, func_end - func_start);

	/* Check if this is an inline/anonymous block */
	if (strcmp(func_name, "inline_code_block") == 0)
	{
		/* For anonymous blocks, just show line number */
		/* Find " line " */
		line_marker = strstr(func_end, " line ");
		if (!line_marker)
		{
			pfree(func_name);
			return false;
		}

		line_num_start = line_marker + 6; /* Skip " line " */
		line_num = atoi(line_num_start);

		appendStringInfo(result, "ORA-06512: at line %d\n", line_num);
		pfree(func_name);
		return true;
	}

	/* For named functions/procedures, lookup schema */
	/* Find " line " */
	line_marker = strstr(func_end, " line ");
	if (!line_marker)
	{
		pfree(func_name);
		return false;
	}

	line_num_start = line_marker + 6; /* Skip " line " */
	line_num = atoi(line_num_start);

	/* For now, just use PUBLIC as the default schema */
	/* TODO: Look up the actual schema from pg_proc catalog */
	schema_name = pstrdup("PUBLIC");

	/* Convert function name to uppercase for Oracle compatibility */
	/* Use simple ASCII uppercase conversion */
	func_upper = pstrdup(func_name);
	for (i = 0; func_upper[i]; i++)
		func_upper[i] = pg_toupper((unsigned char) func_upper[i]);

	schema_upper = pstrdup(schema_name);
	for (i = 0; schema_upper[i]; i++)
		schema_upper[i] = pg_toupper((unsigned char) schema_upper[i]);

	/* Format: ORA-06512: at "SCHEMA.FUNCTION", line N */
	appendStringInfo(result, "ORA-06512: at \"%s.%s\", line %d\n",
					 schema_upper, func_upper, line_num);

	pfree(func_name);
	pfree(func_upper);
	pfree(schema_upper);
	pfree(schema_name);

	return true;
}

/*
 * ora_format_error_backtrace - FORMAT_ERROR_BACKTRACE implementation
 *
 * Returns formatted error backtrace string in Oracle format.
 * Returns NULL if not in exception handler context.
 *
 * This Oracle-compatible function retrieves the exception context from
 * PL/iSQL via dynamic lookup of plisql_get_current_exception_context().
 */
Datum
ora_format_error_backtrace(PG_FUNCTION_ARGS)
{
	const char *pg_context;
	char	   *context_copy;
	char	   *line;
	char	   *saveptr;
	StringInfoData result;
	plisql_get_context_fn get_context;

	/* Look up the PL/iSQL function dynamically */
	get_context = lookup_plisql_get_exception_context();
	if (get_context == NULL)
	{
		/* plisql not loaded or function not found */
		PG_RETURN_NULL();
	}

	/* Get the current exception context from PL/iSQL */
	pg_context = get_context();

	/* If no context available (not in exception handler), return NULL */
	if (pg_context == NULL || pg_context[0] == '\0')
		PG_RETURN_NULL();

	initStringInfo(&result);

	/* Make a copy since strtok_r modifies the string */
	context_copy = pstrdup(pg_context);

	/* Parse and transform each line */
	line = strtok_r(context_copy, "\n", &saveptr);
	while (line != NULL)
	{
		/* Skip empty lines */
		if (line[0] != '\0')
			transform_and_append_line(&result, line);

		line = strtok_r(NULL, "\n", &saveptr);
	}

	pfree(context_copy);

	PG_RETURN_TEXT_P(cstring_to_text(result.data));
}
