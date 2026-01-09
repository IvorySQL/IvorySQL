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
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_utility/dbms_utility.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "utils/errcodes.h"
#include "mb/pg_wchar.h"

#ifndef WIN32
#include <dlfcn.h>
#endif

PG_FUNCTION_INFO_V1(ora_format_error_backtrace);
PG_FUNCTION_INFO_V1(ora_format_error_stack);
PG_FUNCTION_INFO_V1(ora_format_call_stack);

/*
 * Function pointer types for plisql API functions.
 * We use dynamic lookup to avoid link-time dependency on plisql.so.
 */
typedef const char *(*plisql_get_context_fn)(void);
typedef const char *(*plisql_get_message_fn)(void);
typedef int (*plisql_get_sqlerrcode_fn)(void);
typedef char *(*plisql_get_call_stack_fn)(void);

/*
 * Cached function pointers for plisql functions.
 * Looked up once on first use.
 */
static plisql_get_context_fn get_exception_context_fn = NULL;
static plisql_get_message_fn get_exception_message_fn = NULL;
static plisql_get_sqlerrcode_fn get_exception_sqlerrcode_fn = NULL;
static plisql_get_call_stack_fn get_call_stack_fn = NULL;
static bool lookup_attempted = false;

/*
 * Look up the plisql API functions dynamically.
 * All lookups are attempted once and cached.
 */
static void
lookup_plisql_functions(void)
{
	if (lookup_attempted)
		return;

	lookup_attempted = true;

#ifndef WIN32
	/*
	 * Use RTLD_DEFAULT to search all loaded shared objects.
	 * plisql.so should already be loaded when these functions are called
	 * from within a PL/iSQL context.
	 */
	void *fn;

	fn = dlsym(RTLD_DEFAULT, "plisql_get_current_exception_context");
	if (fn != NULL)
		get_exception_context_fn = (plisql_get_context_fn) fn;

	fn = dlsym(RTLD_DEFAULT, "plisql_get_current_exception_message");
	if (fn != NULL)
		get_exception_message_fn = (plisql_get_message_fn) fn;

	fn = dlsym(RTLD_DEFAULT, "plisql_get_current_exception_sqlerrcode");
	if (fn != NULL)
		get_exception_sqlerrcode_fn = (plisql_get_sqlerrcode_fn) fn;

	fn = dlsym(RTLD_DEFAULT, "plisql_get_call_stack");
	if (fn != NULL)
		get_call_stack_fn = (plisql_get_call_stack_fn) fn;
#endif
	/* On Windows, function pointers remain NULL - features require plisql */
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

	/* Look up the PL/iSQL functions dynamically */
	lookup_plisql_functions();
	if (get_exception_context_fn == NULL)
	{
		/* plisql not loaded or function not found */
		PG_RETURN_NULL();
	}

	/* Get the current exception context from PL/iSQL */
	pg_context = get_exception_context_fn();

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

/*
 * Convert SQLSTATE error code to Oracle error number string.
 * Oracle uses "ORA-XXXXX" format for most errors.
 * For PL/SQL user-defined errors, uses "ORA-06510" (user-defined exception).
 */
static const char *
sqlstate_to_ora_errnum(int sqlerrcode)
{
	/*
	 * Map some common PostgreSQL SQLSTATE codes to Oracle error numbers.
	 * For most cases, we use a generic error number.
	 */
	switch (sqlerrcode)
	{
		case ERRCODE_DIVISION_BY_ZERO:
			return "ORA-01476";		/* divisor is equal to zero */
		case ERRCODE_NO_DATA_FOUND:
		case ERRCODE_NO_DATA:
			return "ORA-01403";		/* no data found */
		case ERRCODE_TOO_MANY_ROWS:
			return "ORA-01422";		/* exact fetch returns more than requested number of rows */
		case ERRCODE_NULL_VALUE_NOT_ALLOWED:
			return "ORA-06502";		/* PL/SQL: numeric or value error */
		case ERRCODE_INVALID_CURSOR_STATE:
			return "ORA-01001";		/* invalid cursor */
		case ERRCODE_RAISE_EXCEPTION:
			return "ORA-06510";		/* PL/SQL: unhandled user-defined exception */
		default:
			return "ORA-06502";		/* PL/SQL: numeric or value error (generic) */
	}
}

/*
 * ora_format_error_stack - FORMAT_ERROR_STACK implementation
 *
 * Returns formatted error stack string in Oracle format.
 * Returns NULL if not in exception handler context.
 *
 * Oracle format example:
 *   ORA-06510: PL/SQL: unhandled user-defined exception
 *   ORA-06512: at "SCOTT.TEST_PROC", line 5
 */
Datum
ora_format_error_stack(PG_FUNCTION_ARGS)
{
	const char *message;
	int sqlerrcode;
	StringInfoData result;

	/* Look up the PL/iSQL functions dynamically */
	lookup_plisql_functions();
	if (get_exception_message_fn == NULL || get_exception_sqlerrcode_fn == NULL)
	{
		/* plisql not loaded or function not found */
		PG_RETURN_NULL();
	}

	/* Get the current exception message and code from PL/iSQL */
	message = get_exception_message_fn();
	sqlerrcode = get_exception_sqlerrcode_fn();

	/* If no exception context (not in exception handler), return NULL */
	if (message == NULL || sqlerrcode == 0)
		PG_RETURN_NULL();

	initStringInfo(&result);

	/* Format: ORA-XXXXX: <message> */
	appendStringInfo(&result, "%s: %s\n", sqlstate_to_ora_errnum(sqlerrcode), message);

	PG_RETURN_TEXT_P(cstring_to_text(result.data));
}

/*
 * ora_format_call_stack - FORMAT_CALL_STACK implementation
 *
 * Returns formatted call stack string in Oracle format.
 * Returns NULL if not in any PL/iSQL function.
 *
 * Oracle format example:
 *   ----- PL/SQL Call Stack -----
 *     object      line  object
 *     handle    number  name
 *   0x7f8b0c0     5  procedure SCOTT.INNER_PROC
 *   0x7f8b0a0     3  procedure SCOTT.OUTER_PROC
 *   0x7f8b080     2  anonymous block
 */
Datum
ora_format_call_stack(PG_FUNCTION_ARGS)
{
	char *raw_stack;
	char *stack_copy;
	char *line;
	char *saveptr;
	StringInfoData result;
	int frame_count = 0;
	bool found_any = false;

	/* Look up the PL/iSQL functions dynamically */
	lookup_plisql_functions();
	if (get_call_stack_fn == NULL)
	{
		/* plisql not loaded or function not found */
		PG_RETURN_NULL();
	}

	/* Get the current call stack from PL/iSQL */
	raw_stack = get_call_stack_fn();

	/* If no call stack (not in any PL/iSQL function), return NULL */
	if (raw_stack == NULL)
		PG_RETURN_NULL();

	initStringInfo(&result);

	/* Add Oracle-style header */
	appendStringInfo(&result, "----- PL/SQL Call Stack -----\n");
	appendStringInfo(&result, "  object      line  object\n");
	appendStringInfo(&result, "  handle    number  name\n");

	/*
	 * Parse the raw stack returned by plisql_get_call_stack.
	 * Format from plisql: "handle\tlineno\tsignature" per line
	 *
	 * Skip the first frame which is the FORMAT_CALL_STACK package function.
	 */
	stack_copy = pstrdup(raw_stack);
	line = strtok_r(stack_copy, "\n", &saveptr);

	while (line != NULL)
	{
		char *handle_str;
		char *lineno_str;
		char *signature;
		char *tab1;
		char *tab2;
		char *func_upper;
		int i;

		frame_count++;

		/* Skip the first frame (FORMAT_CALL_STACK itself) */
		if (frame_count == 1)
		{
			line = strtok_r(NULL, "\n", &saveptr);
			continue;
		}

		/* Parse: handle\tlineno\tsignature */
		tab1 = strchr(line, '\t');
		if (!tab1)
		{
			line = strtok_r(NULL, "\n", &saveptr);
			continue;
		}

		handle_str = pnstrdup(line, tab1 - line);
		tab2 = strchr(tab1 + 1, '\t');
		if (!tab2)
		{
			pfree(handle_str);
			line = strtok_r(NULL, "\n", &saveptr);
			continue;
		}

		lineno_str = pnstrdup(tab1 + 1, tab2 - tab1 - 1);
		signature = tab2 + 1;

		/* Convert function name to uppercase for Oracle compatibility */
		func_upper = pstrdup(signature);
		for (i = 0; func_upper[i]; i++)
			func_upper[i] = pg_toupper((unsigned char) func_upper[i]);

		/* Format each stack frame */
		appendStringInfo(&result, "%s  %5s  function %s\n",
						 handle_str, lineno_str, func_upper);
		found_any = true;

		pfree(handle_str);
		pfree(lineno_str);
		pfree(func_upper);

		line = strtok_r(NULL, "\n", &saveptr);
	}

	pfree(stack_copy);
	pfree(raw_stack);

	/* If we only had the FORMAT_CALL_STACK frame, return NULL */
	if (!found_any)
	{
		pfree(result.data);
		PG_RETURN_NULL();
	}

	PG_RETURN_TEXT_P(cstring_to_text(result.data));
}
