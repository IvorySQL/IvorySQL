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
 * pl_dbms_utility.c
 *
 * This file contains the implementation of Oracle's DBMS_UTILITY package
 * functions. These functions are part of the PL/iSQL language runtime
 * because they need access to PL/iSQL internals (exception context, etc.)
 *
 * Portions Copyright (c) 2025, IvorySQL Global Development Team
 *
 * src/pl/plisql/src/pl_dbms_utility.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "funcapi.h"
#include "catalog/pg_collation.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_namespace.h"
#include "utils/builtins.h"
#include "utils/elog.h"
#include "utils/formatting.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"
#include "mb/pg_wchar.h"
#include "plisql.h"

PG_FUNCTION_INFO_V1(ora_format_error_backtrace);

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
	if (schema_name)
		pfree(schema_name);

	return true;
}

/*
 * ora_format_error_backtrace - FORMAT_ERROR_BACKTRACE implementation
 *
 * Returns formatted error backtrace string in Oracle format.
 * Returns NULL if not in exception handler context.
 *
 * This Oracle-compatible function automatically retrieves the exception
 * context from PL/iSQL's session storage, which is set when entering
 * an exception handler.
 */
Datum
ora_format_error_backtrace(PG_FUNCTION_ARGS)
{
	const char *pg_context;
	char	   *context_copy;
	char	   *line;
	char	   *saveptr;
	StringInfoData result;

	/* Get the current exception context from PL/iSQL session storage */
	pg_context = plisql_get_current_exception_context();

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

	/* Oracle always ends with a newline - don't remove it */
	/* The transform_and_append_line function already adds newlines */

	PG_RETURN_TEXT_P(cstring_to_text(result.data));
}
