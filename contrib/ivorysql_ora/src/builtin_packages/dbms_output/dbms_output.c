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
 * dbms_output.c
 *
 * This file contains the native implementation of Oracle's DBMS_OUTPUT
 * package for IvorySQL.
 *
 * Provides session-level buffering for PUT_LINE, PUT, NEW_LINE,
 * GET_LINE, and GET_LINES functions with full Oracle compatibility.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_output/dbms_output.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/xact.h"
#include "fmgr.h"
#include "funcapi.h"
#include "lib/stringinfo.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/memutils.h"

/*
 * DBMS_OUTPUT buffer structure
 *
 * This is a per-backend global buffer that stores output lines.
 * The buffer is transaction-scoped and cleared on COMMIT/ROLLBACK.
 */
typedef struct DbmsOutputBuffer
{
	char	  **lines;			/* Array of completed line strings */
	int			line_count;		/* Current number of lines in buffer */
	int			buffer_size;	/* Max bytes allowed (Oracle uses bytes) */
	int			buffer_used;	/* Current bytes used in buffer */
	bool		enabled;		/* Buffer enabled/disabled state */
	StringInfo	current_line;	/* Accumulator for PUT calls (not yet a line) */
	int			read_position;	/* Current position for GET_LINE/GET_LINES */
	bool		callback_registered; /* Track if xact callback is registered */
	MemoryContext buffer_mcxt;	/* Memory context for buffer allocations */
	int			lines_allocated; /* Size of lines array */
} DbmsOutputBuffer;

/* Global buffer - one per backend process */
static DbmsOutputBuffer *output_buffer = NULL;

/* Internal function declarations */
static void init_output_buffer(int buffer_size);
static void cleanup_output_buffer(void);
static void add_line_to_buffer(const char *line);
static void dbms_output_xact_callback(XactEvent event, void *arg);
static void ensure_lines_capacity(void);

/* SQL-callable function declarations */
PG_FUNCTION_INFO_V1(ora_dbms_output_enable);
PG_FUNCTION_INFO_V1(ora_dbms_output_disable);
PG_FUNCTION_INFO_V1(ora_dbms_output_put_line);
PG_FUNCTION_INFO_V1(ora_dbms_output_put);
PG_FUNCTION_INFO_V1(ora_dbms_output_new_line);
PG_FUNCTION_INFO_V1(ora_dbms_output_get_line);
PG_FUNCTION_INFO_V1(ora_dbms_output_get_lines);


/*
 * init_output_buffer
 *
 * Initialize or re-initialize the output buffer.
 * CRITICAL: Oracle behavior - ENABLE always clears existing buffer.
 */
static void
init_output_buffer(int buffer_size)
{
	MemoryContext oldcontext;

	/* Oracle behavior: ENABLE always clears existing buffer */
	if (output_buffer != NULL)
		cleanup_output_buffer();

	/* Allocate buffer structure in TopMemoryContext */
	oldcontext = MemoryContextSwitchTo(TopMemoryContext);

	output_buffer = (DbmsOutputBuffer *) palloc0(sizeof(DbmsOutputBuffer));

	/* Create dedicated memory context for buffer contents */
	output_buffer->buffer_mcxt = AllocSetContextCreate(
		TopMemoryContext,
		"DBMS_OUTPUT buffer",
		ALLOCSET_DEFAULT_SIZES);

	MemoryContextSwitchTo(output_buffer->buffer_mcxt);

	/* Oracle tracks buffer in BYTES, not lines */
	if (buffer_size < 0)
		output_buffer->buffer_size = INT_MAX;  /* NULL = unlimited (Oracle 10g R2+) */
	else
		output_buffer->buffer_size = buffer_size;

	/*
	 * Pre-allocate line array with reasonable initial size.
	 * For unlimited (INT_MAX), don't allocate huge array upfront -
	 * we'll grow dynamically via ensure_lines_capacity().
	 */
	if (output_buffer->buffer_size == INT_MAX)
		output_buffer->lines_allocated = 1000;  /* Start with 1000 lines for unlimited */
	else
	{
		output_buffer->lines_allocated = output_buffer->buffer_size / 80;
		if (output_buffer->lines_allocated < 100)
			output_buffer->lines_allocated = 100;  /* Minimum array size */
	}

	output_buffer->lines = (char **) palloc0(sizeof(char *) * output_buffer->lines_allocated);
	output_buffer->current_line = makeStringInfo();
	output_buffer->enabled = true;
	output_buffer->line_count = 0;
	output_buffer->buffer_used = 0;
	output_buffer->read_position = 0;
	output_buffer->callback_registered = false;

	MemoryContextSwitchTo(oldcontext);

	/* Register transaction callback (only once per buffer lifecycle) */
	if (!output_buffer->callback_registered)
	{
		RegisterXactCallback(dbms_output_xact_callback, NULL);
		output_buffer->callback_registered = true;
	}
}

/*
 * cleanup_output_buffer
 *
 * Free all buffer resources and reset to NULL.
 * Called on transaction end (COMMIT/ROLLBACK) and when ENABLE is called.
 */
static void
cleanup_output_buffer(void)
{
	if (output_buffer == NULL)
		return;

	/* Unregister callback if it was registered */
	if (output_buffer->callback_registered)
	{
		UnregisterXactCallback(dbms_output_xact_callback, NULL);
		output_buffer->callback_registered = false;
	}

	/* Delete memory context (automatically frees all lines and current_line) */
	MemoryContextDelete(output_buffer->buffer_mcxt);

	/* Free buffer structure itself */
	pfree(output_buffer);
	output_buffer = NULL;
}

/*
 * ensure_lines_capacity
 *
 * Grow the lines array if needed to accommodate more lines.
 */
static void
ensure_lines_capacity(void)
{
	MemoryContext oldcontext;
	int			new_capacity;
	char	  **new_lines;

	if (output_buffer->line_count < output_buffer->lines_allocated)
		return;  /* Still have space */

	/* Grow by 50% */
	new_capacity = output_buffer->lines_allocated + (output_buffer->lines_allocated / 2);
	if (new_capacity < output_buffer->lines_allocated + 100)
		new_capacity = output_buffer->lines_allocated + 100;

	oldcontext = MemoryContextSwitchTo(output_buffer->buffer_mcxt);
	new_lines = (char **) repalloc(output_buffer->lines, sizeof(char *) * new_capacity);
	output_buffer->lines = new_lines;
	output_buffer->lines_allocated = new_capacity;
	MemoryContextSwitchTo(oldcontext);
}

/*
 * add_line_to_buffer
 *
 * Add a completed line to the buffer.
 * Checks for buffer overflow based on byte usage (Oracle behavior).
 */
static void
add_line_to_buffer(const char *line)
{
	MemoryContext oldcontext;
	int			line_bytes;
	char	   *line_copy;

	/* Calculate bytes for this line (Oracle counts actual bytes) */
	line_bytes = strlen(line);

	/* Check buffer overflow BEFORE adding (Oracle behavior) */
	if (output_buffer->buffer_used + line_bytes > output_buffer->buffer_size)
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("ORU-10027: buffer overflow, limit of %d bytes",
						output_buffer->buffer_size)));

	/* Ensure we have space in lines array */
	ensure_lines_capacity();

	/* Store line in buffer memory context */
	oldcontext = MemoryContextSwitchTo(output_buffer->buffer_mcxt);
	line_copy = pstrdup(line);
	output_buffer->lines[output_buffer->line_count++] = line_copy;
	output_buffer->buffer_used += line_bytes;
	MemoryContextSwitchTo(oldcontext);
}

/*
 * dbms_output_xact_callback
 *
 * Transaction callback to clean up buffer on COMMIT/ROLLBACK.
 * Oracle behavior: buffer is transaction-scoped, not session-scoped.
 */
static void
dbms_output_xact_callback(XactEvent event, void *arg)
{
	switch (event)
	{
		case XACT_EVENT_ABORT:
		case XACT_EVENT_COMMIT:
		case XACT_EVENT_PREPARE:
			/* Clean up buffer at transaction end */
			cleanup_output_buffer();
			break;

		default:
			/* XACT_EVENT_PRE_COMMIT, etc. - ignore */
			break;
	}
}

/*
 * ora_dbms_output_enable
 *
 * Enable output buffering with optional size limit.
 * NULL parameter means UNLIMITED (Oracle 10g R2+).
 * Oracle constraints: 2000 to 1000000 bytes when explicitly specified.
 * Default (from SQL): 20000 bytes.
 */
Datum
ora_dbms_output_enable(PG_FUNCTION_ARGS)
{
	int32		buffer_size;

	/* Handle NULL argument (means UNLIMITED) */
	if (PG_ARGISNULL(0))
		buffer_size = -1;  /* -1 = unlimited */
	else
	{
		buffer_size = PG_GETARG_INT32(0);

		/* Oracle constraints: 2000 to 1000000 bytes when explicitly specified */
		if (buffer_size < 2000 || buffer_size > 1000000)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
					 errmsg("buffer size must be between 2000 and 1000000")));
	}

	/* Initialize buffer (clears existing if present) */
	init_output_buffer(buffer_size);

	PG_RETURN_VOID();
}

/*
 * ora_dbms_output_disable
 *
 * Disable output buffering.
 * Oracle behavior: buffer persists (can still GET_LINE), but PUT_LINE is ignored.
 */
Datum
ora_dbms_output_disable(PG_FUNCTION_ARGS)
{
	if (output_buffer != NULL)
		output_buffer->enabled = false;

	PG_RETURN_VOID();
}

/*
 * ora_dbms_output_put_line
 *
 * Output a line to the buffer (with newline).
 * If there's pending PUT text, append it first (Oracle behavior).
 * Oracle behavior: NULL is treated as empty string.
 */
Datum
ora_dbms_output_put_line(PG_FUNCTION_ARGS)
{
	char	   *line_str;

	/* Silently discard if buffer not enabled (Oracle behavior) */
	if (output_buffer == NULL || !output_buffer->enabled)
		PG_RETURN_VOID();

	/* Handle NULL argument - treat as empty string (Oracle behavior) */
	if (PG_ARGISNULL(0))
		line_str = "";
	else
	{
		text	   *line_text = PG_GETARG_TEXT_PP(0);
		line_str = text_to_cstring(line_text);
	}

	/* If there's pending PUT text, append it first (Oracle behavior) */
	if (output_buffer->current_line->len > 0)
	{
		appendStringInfoString(output_buffer->current_line, line_str);
		add_line_to_buffer(output_buffer->current_line->data);
		resetStringInfo(output_buffer->current_line);
	}
	else
	{
		/* No pending PUT text, just add the line */
		add_line_to_buffer(line_str);
	}

	PG_RETURN_VOID();
}

/*
 * ora_dbms_output_put
 *
 * Output text without newline (accumulates in current_line).
 * Oracle behavior: not retrievable until NEW_LINE or PUT_LINE is called.
 * Oracle behavior: NULL is treated as empty string (appends nothing).
 */
Datum
ora_dbms_output_put(PG_FUNCTION_ARGS)
{
	char	   *str;

	/* Silently discard if buffer not enabled */
	if (output_buffer == NULL || !output_buffer->enabled)
		PG_RETURN_VOID();

	/* Handle NULL argument - treat as empty string (Oracle behavior) */
	if (PG_ARGISNULL(0))
		str = "";
	else
	{
		text	   *text_arg = PG_GETARG_TEXT_PP(0);
		str = text_to_cstring(text_arg);
	}

	/* Accumulate in current_line without creating a line yet */
	appendStringInfoString(output_buffer->current_line, str);

	PG_RETURN_VOID();
}

/*
 * ora_dbms_output_new_line
 *
 * Flush accumulated PUT text as a line.
 * Oracle behavior: creates empty line if no PUT text accumulated.
 */
Datum
ora_dbms_output_new_line(PG_FUNCTION_ARGS)
{
	/* Silently discard if buffer not enabled */
	if (output_buffer == NULL || !output_buffer->enabled)
		PG_RETURN_VOID();

	/* Flush current_line to buffer as a completed line */
	if (output_buffer->current_line->len > 0)
	{
		add_line_to_buffer(output_buffer->current_line->data);
		resetStringInfo(output_buffer->current_line);
	}
	else
	{
		/* Empty NEW_LINE creates empty string line (Oracle behavior) */
		add_line_to_buffer("");
	}

	PG_RETURN_VOID();
}

/*
 * ora_dbms_output_get_line
 *
 * Retrieve one line from buffer.
 * Returns: (line TEXT, status INTEGER)
 * - status = 0: success, line contains data
 * - status = 1: no more lines, line is NULL (Oracle behavior)
 */
Datum
ora_dbms_output_get_line(PG_FUNCTION_ARGS)
{
	TupleDesc	tupdesc;
	Datum		values[2];
	bool		nulls[2] = {false, false};
	HeapTuple	tuple;

	/* Build tuple descriptor for return type */
	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function returning record called in context that cannot accept type record")));

	tupdesc = BlessTupleDesc(tupdesc);

	if (output_buffer == NULL ||
		output_buffer->read_position >= output_buffer->line_count)
	{
		/* No more lines available - return NULL, not empty string (Oracle behavior) */
		nulls[0] = true;		/* line = NULL */
		values[0] = (Datum) 0;
		values[1] = Int32GetDatum(1);	/* status = 1 (no more lines) */
	}
	else
	{
		/* Return next line */
		char	   *line = output_buffer->lines[output_buffer->read_position++];

		values[0] = CStringGetTextDatum(line);
		values[1] = Int32GetDatum(0);	/* status = 0 (success) */
	}

	tuple = heap_form_tuple(tupdesc, values, nulls);
	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}

/*
 * ora_dbms_output_get_lines
 *
 * Retrieve multiple lines from buffer.
 * Input: numlines (max lines to retrieve)
 * Returns: (lines TEXT[], actual_count INTEGER)
 * - actual_count is set to number of lines actually retrieved
 */
Datum
ora_dbms_output_get_lines(PG_FUNCTION_ARGS)
{
	int32		requested_lines;
	int32		actual_lines = 0;
	ArrayType  *lines_array;
	Datum	   *line_datums;
	int			available_lines;
	int			i;
	TupleDesc	tupdesc;
	Datum		values[2];
	bool		nulls[2] = {false, false};
	HeapTuple	tuple;

	requested_lines = PG_GETARG_INT32(0);

	/* Build tuple descriptor for return type */
	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function returning record called in context that cannot accept type record")));

	tupdesc = BlessTupleDesc(tupdesc);

	if (output_buffer == NULL)
	{
		/* No buffer, return empty array */
		lines_array = construct_empty_array(TEXTOID);
		actual_lines = 0;
	}
	else
	{
		/* Calculate how many lines we can actually return */
		available_lines = output_buffer->line_count - output_buffer->read_position;
		actual_lines = (requested_lines < available_lines) ? requested_lines : available_lines;

		if (actual_lines > 0)
		{
			line_datums = (Datum *) palloc(sizeof(Datum) * actual_lines);

			for (i = 0; i < actual_lines; i++)
			{
				char	   *line = output_buffer->lines[output_buffer->read_position++];

				line_datums[i] = CStringGetTextDatum(line);
			}

			lines_array = construct_array(line_datums, actual_lines, TEXTOID, -1, false, TYPALIGN_INT);
			pfree(line_datums);
		}
		else
		{
			lines_array = construct_empty_array(TEXTOID);
		}
	}

	/* Return composite (lines[], count) */
	values[0] = PointerGetDatum(lines_array);
	values[1] = Int32GetDatum(actual_lines);

	tuple = heap_form_tuple(tupdesc, values, nulls);
	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}
