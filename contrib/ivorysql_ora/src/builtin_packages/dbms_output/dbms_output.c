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
 * GET_LINE, and GET_LINES functions with high Oracle compatibility.
 * See ora_dbms_output.sql tests for known behavioral differences.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_output/dbms_output.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "fmgr.h"
#include "funcapi.h"
#include "lib/stringinfo.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/memutils.h"

/*
 * DbmsOutputLine - a single line in the output buffer
 *
 * Lines are stored in a singly-linked list. Each node contains:
 * - next: pointer to next line (NULL for last line)
 * - len: length of line data (-1 indicates NULL line)
 * - data: flexible array member containing line content
 *
 * This design allows:
 * - O(1) append (via tail pointer)
 * - O(1) consume from head
 * - Immediate memory reclamation via pfree (AllocSet handles recycling)
 * - No buffer expansion overhead for large buffers
 */
typedef struct DbmsOutputLine
{
	struct DbmsOutputLine *next;
	int			len;			/* -1 for NULL line, else byte length */
	char		data[FLEXIBLE_ARRAY_MEMBER];
} DbmsOutputLine;

/*
 * DBMS_OUTPUT buffer structure
 *
 * This is a per-backend global buffer that stores output lines.
 * The buffer is session-scoped and persists across transactions (Oracle behavior).
 *
 * Uses a linked list of lines. Memory is allocated per-line and freed
 * immediately when lines are consumed via GET_LINE/GET_LINES.
 * PostgreSQL's AllocSet maintains internal free lists for efficient reuse.
 */
typedef struct DbmsOutputBuffer
{
	DbmsOutputLine *head;		/* First line (for reading) */
	DbmsOutputLine *tail;		/* Last line (for appending) */
	int64		buffer_size;	/* User-specified content limit, -1 = unlimited */
	int			buffer_used;	/* Content bytes only (user-perceived usage) */
	int			line_count;		/* Number of lines currently in buffer */
	bool		enabled;		/* Buffer enabled/disabled state */
	StringInfo	current_line;	/* Accumulator for PUT calls (not yet a line) */
	MemoryContext buffer_mcxt;	/* Memory context for buffer allocations */
} DbmsOutputBuffer;

/* Global buffer - one per backend process */
static DbmsOutputBuffer *output_buffer = NULL;

/* Oracle line length limit: 32767 bytes per line */
#define DBMS_OUTPUT_MAX_LINE_LENGTH 32767

/* Buffer size constants */
#define DBMS_OUTPUT_MIN_BUFFER_SIZE 2000
#define DBMS_OUTPUT_DEFAULT_BUFFER_SIZE 20000
#define DBMS_OUTPUT_UNLIMITED ((int64) -1)

/* Marker for NULL lines */
#define DBMS_OUTPUT_NULL_LINE_LEN (-1)

/* Internal function declarations */
static void init_output_buffer(int64 buffer_size);
static void cleanup_output_buffer(void);
static void add_line_to_buffer(const char *line, int line_len);
static DbmsOutputLine *pop_line_from_buffer(void);

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
 *
 * buffer_size: user-specified content limit in bytes, or -1 for unlimited.
 *
 * IvorySQL behavior: ENABLE always clears existing buffer.
 * Note: Oracle preserves buffer on re-ENABLE; this is an intentional
 * IvorySQL simplification.
 */
static void
init_output_buffer(int64 buffer_size)
{
	MemoryContext oldcontext;

	/* IvorySQL behavior: ENABLE clears existing buffer (differs from Oracle) */
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

	/* Initialize linked list as empty */
	output_buffer->head = NULL;
	output_buffer->tail = NULL;

	/* Store buffer size (user limit, or -1 for unlimited) */
	output_buffer->buffer_size = buffer_size;
	output_buffer->buffer_used = 0;
	output_buffer->line_count = 0;

	output_buffer->current_line = makeStringInfo();
	output_buffer->enabled = true;

	MemoryContextSwitchTo(oldcontext);
}

/*
 * cleanup_output_buffer
 *
 * Free all buffer resources and reset to NULL.
 * Called when ENABLE is called to re-initialize the buffer.
 */
static void
cleanup_output_buffer(void)
{
	if (output_buffer == NULL)
		return;

	/* Delete memory context (automatically frees all lines and current_line) */
	MemoryContextDelete(output_buffer->buffer_mcxt);

	/* Free buffer structure itself */
	pfree(output_buffer);
	output_buffer = NULL;
}

/*
 * add_line_to_buffer
 *
 * Add a completed line to the linked list buffer.
 *
 * line: pointer to line data, or NULL for a NULL line
 * line_len: length of line data (ignored if line is NULL)
 *
 * Overflow check (Oracle behavior):
 * - Only content bytes count toward user limit (not node overhead)
 * - Raises ORU-10027 if limit exceeded
 */
static void
add_line_to_buffer(const char *line, int line_len)
{
	MemoryContext oldcontext;
	DbmsOutputLine *node;
	Size		node_size;

	/*
	 * Check user-perceived buffer limit BEFORE adding (Oracle behavior).
	 * Only content bytes count toward limit, not node overhead.
	 * Skip check for unlimited buffer (buffer_size == -1).
	 */
	if (output_buffer->buffer_size != DBMS_OUTPUT_UNLIMITED)
	{
		/* Use subtraction to avoid potential integer overflow in addition */
		if (line_len > output_buffer->buffer_size - output_buffer->buffer_used)
			ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("ORU-10027: buffer overflow, limit of %lld bytes",
							(long long) output_buffer->buffer_size)));
	}

	/* Allocate node with embedded data in buffer memory context */
	oldcontext = MemoryContextSwitchTo(output_buffer->buffer_mcxt);

	if (line == NULL)
	{
		/* NULL line: just allocate the header */
		node_size = offsetof(DbmsOutputLine, data);
		node = (DbmsOutputLine *) palloc(node_size);
		node->len = DBMS_OUTPUT_NULL_LINE_LEN;
	}
	else
	{
		/* Regular line: allocate header + data */
		node_size = offsetof(DbmsOutputLine, data) + line_len;
		node = (DbmsOutputLine *) palloc(node_size);
		node->len = line_len;
		if (line_len > 0)
			memcpy(node->data, line, line_len);
	}
	node->next = NULL;

	MemoryContextSwitchTo(oldcontext);

	/* Append to linked list */
	if (output_buffer->tail == NULL)
	{
		/* Empty list */
		output_buffer->head = node;
		output_buffer->tail = node;
	}
	else
	{
		/* Append to end */
		output_buffer->tail->next = node;
		output_buffer->tail = node;
	}

	output_buffer->buffer_used += line_len;
	output_buffer->line_count++;
}

/*
 * pop_line_from_buffer
 *
 * Remove and return the first line from the buffer.
 * Caller is responsible for freeing the returned node with pfree().
 *
 * Returns NULL if buffer is empty.
 */
static DbmsOutputLine *
pop_line_from_buffer(void)
{
	DbmsOutputLine *node;

	if (output_buffer == NULL || output_buffer->head == NULL)
		return NULL;

	node = output_buffer->head;
	output_buffer->head = node->next;

	/* If list is now empty, clear tail pointer too */
	if (output_buffer->head == NULL)
		output_buffer->tail = NULL;

	/* Update usage tracking (NULL lines have len = -1, don't count) */
	if (node->len > 0)
		output_buffer->buffer_used -= node->len;

	output_buffer->line_count--;

	return node;
}

/*
 * ora_dbms_output_enable
 *
 * Enable output buffering with optional size limit.
 *
 * - NULL parameter: unlimited buffer (grows dynamically, Oracle behavior)
 * - Default (from SQL wrapper): DEFAULT_BUFFER_SIZE bytes
 * - Minimum: MIN_BUFFER_SIZE bytes (values below are clamped, Oracle behavior)
 *
 * Oracle behavior: silently clamps below-min values to MIN_BUFFER_SIZE.
 */
Datum
ora_dbms_output_enable(PG_FUNCTION_ARGS)
{
	int64		buffer_size;

	/* Handle NULL argument - unlimited buffer (Oracle behavior) */
	if (PG_ARGISNULL(0))
		buffer_size = DBMS_OUTPUT_UNLIMITED;
	else
	{
		buffer_size = PG_GETARG_INT32(0);

		/* Oracle behavior: silently clamp below-min values to 2000 */
		if (buffer_size < DBMS_OUTPUT_MIN_BUFFER_SIZE)
			buffer_size = DBMS_OUTPUT_MIN_BUFFER_SIZE;
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
 * Oracle behavior: NULL stores actual NULL in buffer (not empty string).
 * Oracle behavior: raises ORU-10028 if line exceeds 32767 bytes.
 */
Datum
ora_dbms_output_put_line(PG_FUNCTION_ARGS)
{
	char	   *line_str;
	bool		is_null = false;
	int			line_len = 0;

	/* Silently discard if buffer not enabled (Oracle behavior) */
	if (output_buffer == NULL || !output_buffer->enabled)
		PG_RETURN_VOID();

	/* Handle NULL argument - Oracle stores actual NULL */
	if (PG_ARGISNULL(0))
	{
		line_str = NULL;
		is_null = true;
	}
	else
	{
		text	   *line_text = PG_GETARG_TEXT_PP(0);
		line_str = text_to_cstring(line_text);
		line_len = strlen(line_str);
	}

	/* If there's pending PUT text, append it first (Oracle behavior) */
	if (output_buffer->current_line->len > 0)
	{
		/* Check line length limit BEFORE appending (Oracle behavior) */
		if (output_buffer->current_line->len + line_len > DBMS_OUTPUT_MAX_LINE_LENGTH)
			ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("ORU-10028: line length overflow, limit of %d bytes per line",
							DBMS_OUTPUT_MAX_LINE_LENGTH)));

		/* Append non-NULL text to current line */
		if (!is_null)
			appendStringInfoString(output_buffer->current_line, line_str);
		add_line_to_buffer(output_buffer->current_line->data,
						   output_buffer->current_line->len);
		resetStringInfo(output_buffer->current_line);
	}
	else
	{
		/* No pending PUT text - check line length for direct add */
		if (line_len > DBMS_OUTPUT_MAX_LINE_LENGTH)
			ereport(ERROR,
					(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
					 errmsg("ORU-10028: line length overflow, limit of %d bytes per line",
							DBMS_OUTPUT_MAX_LINE_LENGTH)));

		/* Just add the line (may be NULL) */
		add_line_to_buffer(line_str, line_len);
	}

	PG_RETURN_VOID();
}

/*
 * ora_dbms_output_put
 *
 * Output text without newline (accumulates in current_line).
 * Oracle behavior: not retrievable until NEW_LINE or PUT_LINE is called.
 * Oracle behavior: NULL is treated as empty string (appends nothing).
 * Oracle behavior: raises ORU-10028 if line exceeds 32767 bytes.
 */
Datum
ora_dbms_output_put(PG_FUNCTION_ARGS)
{
	char	   *str;
	int			str_len;

	/* Silently discard if buffer not enabled */
	if (output_buffer == NULL || !output_buffer->enabled)
		PG_RETURN_VOID();

	/* Handle NULL argument - treat as empty string (Oracle behavior) */
	if (PG_ARGISNULL(0))
		PG_RETURN_VOID();  /* NULL appends nothing */

	{
		text	   *text_arg = PG_GETARG_TEXT_PP(0);
		str = text_to_cstring(text_arg);
	}

	str_len = strlen(str);

	/* Check line length limit BEFORE appending (Oracle behavior) */
	if (output_buffer->current_line->len + str_len > DBMS_OUTPUT_MAX_LINE_LENGTH)
		ereport(ERROR,
				(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
				 errmsg("ORU-10028: line length overflow, limit of %d bytes per line",
						DBMS_OUTPUT_MAX_LINE_LENGTH)));

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
		add_line_to_buffer(output_buffer->current_line->data,
						   output_buffer->current_line->len);
		resetStringInfo(output_buffer->current_line);
	}
	else
	{
		/* Empty NEW_LINE creates empty string line (Oracle behavior) */
		add_line_to_buffer("", 0);
	}

	PG_RETURN_VOID();
}

/*
 * ora_dbms_output_get_line
 *
 * Retrieve one line from buffer and free its memory.
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
	DbmsOutputLine *node;

	/* Build tuple descriptor for return type */
	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function returning record called in context that cannot accept type record")));

	tupdesc = BlessTupleDesc(tupdesc);

	node = pop_line_from_buffer();

	if (node == NULL)
	{
		/* No more lines available - return NULL, not empty string (Oracle behavior) */
		nulls[0] = true;		/* line = NULL */
		values[0] = (Datum) 0;
		values[1] = Int32GetDatum(1);	/* status = 1 (no more lines) */
	}
	else
	{
		if (node->len == DBMS_OUTPUT_NULL_LINE_LEN)
		{
			/* NULL line */
			nulls[0] = true;
			values[0] = (Datum) 0;
		}
		else
		{
			/* Regular line - create text datum from embedded data */
			values[0] = PointerGetDatum(cstring_to_text_with_len(node->data, node->len));
		}
		values[1] = Int32GetDatum(0);	/* status = 0 (success) */

		/* Free the node - AllocSet will recycle the memory */
		pfree(node);
	}

	tuple = heap_form_tuple(tupdesc, values, nulls);
	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}

/*
 * ora_dbms_output_get_lines
 *
 * Retrieve multiple lines from buffer and free their memory.
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
	bool	   *line_nulls;
	int			i;
	TupleDesc	tupdesc;
	Datum		values[2];
	bool		nulls[2] = {false, false};
	HeapTuple	tuple;

	requested_lines = PG_GETARG_INT32(0);

	/* Normalize negative values to 0 (Oracle behavior) */
	if (requested_lines < 0)
		requested_lines = 0;

	/* Build tuple descriptor for return type */
	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function returning record called in context that cannot accept type record")));

	tupdesc = BlessTupleDesc(tupdesc);

	if (output_buffer == NULL || output_buffer->line_count == 0 || requested_lines == 0)
	{
		/* No buffer or no lines requested, return empty array */
		lines_array = construct_empty_array(TEXTOID);
		actual_lines = 0;
	}
	else
	{
		/* Calculate how many lines we can actually return */
		actual_lines = (requested_lines < output_buffer->line_count) ?
			requested_lines : output_buffer->line_count;

		line_datums = (Datum *) palloc(sizeof(Datum) * actual_lines);
		line_nulls = (bool *) palloc(sizeof(bool) * actual_lines);

		for (i = 0; i < actual_lines; i++)
		{
			DbmsOutputLine *node = pop_line_from_buffer();

			if (node == NULL)
			{
				/* Shouldn't happen, but handle gracefully */
				actual_lines = i;
				break;
			}

			if (node->len == DBMS_OUTPUT_NULL_LINE_LEN)
			{
				/* NULL line */
				line_nulls[i] = true;
				line_datums[i] = (Datum) 0;
			}
			else
			{
				/* Regular line */
				line_nulls[i] = false;
				line_datums[i] = PointerGetDatum(cstring_to_text_with_len(node->data, node->len));
			}

			/* Free the node - AllocSet will recycle the memory */
			pfree(node);
		}

		if (actual_lines > 0)
		{
			int		lbound = 1;  /* 1-based array indexing */

			lines_array = construct_md_array(line_datums, line_nulls, 1, &actual_lines, &lbound,
											 TEXTOID, -1, false, TYPALIGN_INT);
			pfree(line_datums);
			pfree(line_nulls);
		}
		else
		{
			lines_array = construct_empty_array(TEXTOID);
			pfree(line_datums);
			pfree(line_nulls);
		}
	}

	/* Return composite (lines[], count) */
	values[0] = PointerGetDatum(lines_array);
	values[1] = Int32GetDatum(actual_lines);

	tuple = heap_form_tuple(tupdesc, values, nulls);
	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}
