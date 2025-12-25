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
 * DBMS_OUTPUT buffer structure
 *
 * This is a per-backend global buffer that stores output lines.
 * The buffer is session-scoped and persists across transactions (Oracle behavior).
 *
 * Uses a contiguous ring buffer with length-prefixed strings to allow buffer
 * space recycling when lines are read via GET_LINE/GET_LINES (Oracle behavior).
 *
 * Each line is stored as: [2-byte length][data bytes]
 * NULL lines use length = 0xFFFF as a marker.
 *
 * The buffer grows dynamically when internal storage is full but user-perceived
 * content limit is not reached (length prefixes don't count toward user limit).
 */
typedef struct DbmsOutputBuffer
{
	char	   *buffer;			/* Contiguous ring buffer */
	int			capacity;		/* Current internal buffer size (bytes) */
	int			head;			/* Next write position (byte offset) */
	int			tail;			/* Next read position (byte offset) */
	int64		buffer_size;	/* User-specified content limit, -1 = unlimited */
	int			buffer_used;	/* Content bytes only (user-perceived usage) */
	int			line_count;		/* Number of lines currently in buffer */
	bool		enabled;		/* Buffer enabled/disabled state */
	StringInfo	current_line;	/* Accumulator for PUT calls (not yet a line) */
	MemoryContext buffer_mcxt;	/* Memory context for buffer allocations */
} DbmsOutputBuffer;

/* Global buffer - one per backend process */
static DbmsOutputBuffer *output_buffer = NULL;

/* Oracle line length limit: 32767 bytes per line (fits in 2-byte length prefix) */
#define DBMS_OUTPUT_MAX_LINE_LENGTH 32767

/* Buffer size constants */
#define DBMS_OUTPUT_MIN_BUFFER_SIZE 2000
#define DBMS_OUTPUT_DEFAULT_BUFFER_SIZE 20000
#define DBMS_OUTPUT_UNLIMITED ((int64) -1)

/* Length prefix size and NULL marker */
#define DBMS_OUTPUT_LENGTH_PREFIX_SIZE 2
#define DBMS_OUTPUT_NULL_MARKER 0xFFFF

/* Dynamic growth factor */
#define DBMS_OUTPUT_GROWTH_FACTOR 0.20

/* Internal function declarations */
static void init_output_buffer(int64 buffer_size);
static void cleanup_output_buffer(void);
static void expand_buffer(int needed_space);
static void add_line_to_buffer(const char *line, int line_len);
static void ring_write(int pos, const char *data, int len);
static void ring_read(int pos, char *data, int len);
static uint16 ring_read_uint16(int pos);
static void ring_write_uint16(int pos, uint16 value);

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
 * Initial allocation strategy:
 * - For fixed size: allocate buffer_size bytes initially
 * - For unlimited (-1): allocate DBMS_OUTPUT_DEFAULT_BUFFER_SIZE bytes initially
 *
 * The buffer grows dynamically when internal storage is full but user limit
 * is not reached.
 *
 * IvorySQL behavior: ENABLE always clears existing buffer.
 * Note: Oracle preserves buffer on re-ENABLE; this is an intentional
 * IvorySQL simplification.
 */
static void
init_output_buffer(int64 buffer_size)
{
	MemoryContext oldcontext;
	int			initial_capacity;

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

	/* Store buffer size (user limit, or -1 for unlimited) */
	output_buffer->buffer_size = buffer_size;

	/*
	 * Initial capacity: allocate claimed size, or default for unlimited.
	 * Buffer will grow dynamically if internal storage fills up before
	 * user-perceived content limit is reached.
	 */
	if (buffer_size == DBMS_OUTPUT_UNLIMITED)
		initial_capacity = DBMS_OUTPUT_DEFAULT_BUFFER_SIZE;
	else
		initial_capacity = (int) buffer_size;

	output_buffer->capacity = initial_capacity;
	output_buffer->buffer = (char *) palloc(output_buffer->capacity);
	output_buffer->current_line = makeStringInfo();
	output_buffer->enabled = true;
	output_buffer->head = 0;
	output_buffer->tail = 0;
	output_buffer->buffer_used = 0;
	output_buffer->line_count = 0;

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

	/* Delete memory context (automatically frees buffer and current_line) */
	MemoryContextDelete(output_buffer->buffer_mcxt);

	/* Free buffer structure itself */
	pfree(output_buffer);
	output_buffer = NULL;
}

/*
 * expand_buffer
 *
 * Expand the internal buffer capacity when it's full but user-perceived
 * content limit is not reached.
 *
 * Growth strategy:
 * - Fixed buffer: min(buffer_size, max(DEFAULT_BUFFER_SIZE, capacity * GROWTH_FACTOR))
 * - Unlimited: max(DEFAULT_BUFFER_SIZE, capacity * GROWTH_FACTOR)
 *
 * This involves "packing" the ring buffer: linearizing any wrapped data
 * into a new larger buffer.
 */
static void
expand_buffer(int needed_space)
{
	MemoryContext oldcontext;
	int			growth;
	int			new_capacity;
	char	   *new_buffer;
	int			internal_used;

	/* Calculate current internal usage */
	internal_used = output_buffer->buffer_used +
		(output_buffer->line_count * DBMS_OUTPUT_LENGTH_PREFIX_SIZE);

	/* Calculate base growth: max(DEFAULT_BUFFER_SIZE, capacity * GROWTH_FACTOR) */
	growth = (int) (output_buffer->capacity * DBMS_OUTPUT_GROWTH_FACTOR);
	if (growth < DBMS_OUTPUT_DEFAULT_BUFFER_SIZE)
		growth = DBMS_OUTPUT_DEFAULT_BUFFER_SIZE;

	/* For fixed-size buffers, cap growth at buffer_size */
	if (output_buffer->buffer_size != DBMS_OUTPUT_UNLIMITED)
	{
		if (growth > output_buffer->buffer_size)
			growth = (int) output_buffer->buffer_size;
	}

	/* Ensure we grow enough to fit needed_space */
	while (output_buffer->capacity + growth < internal_used + needed_space)
	{
		if (output_buffer->buffer_size != DBMS_OUTPUT_UNLIMITED)
			growth += (int) output_buffer->buffer_size;
		else
			growth += DBMS_OUTPUT_DEFAULT_BUFFER_SIZE;
	}

	new_capacity = output_buffer->capacity + growth;

	/* Allocate new buffer in buffer memory context */
	oldcontext = MemoryContextSwitchTo(output_buffer->buffer_mcxt);
	new_buffer = (char *) palloc(new_capacity);
	MemoryContextSwitchTo(oldcontext);

	/*
	 * Pack (linearize) the ring buffer data into new buffer.
	 * Ring buffer may have wrapped: [....DATA2....][head] [tail][DATA1....]
	 * After packing: [DATA1....DATA2....]
	 */
	if (internal_used > 0)
	{
		int			tail_wrap = output_buffer->tail % output_buffer->capacity;
		int			head_wrap = output_buffer->head % output_buffer->capacity;

		if (tail_wrap < head_wrap)
		{
			/* Data is contiguous: tail to head */
			memcpy(new_buffer, output_buffer->buffer + tail_wrap, internal_used);
		}
		else
		{
			/* Data wraps around: tail to end, then start to head */
			int			first_chunk = output_buffer->capacity - tail_wrap;

			memcpy(new_buffer, output_buffer->buffer + tail_wrap, first_chunk);
			memcpy(new_buffer + first_chunk, output_buffer->buffer, head_wrap);
		}
	}

	/* Free old buffer and update pointers */
	pfree(output_buffer->buffer);
	output_buffer->buffer = new_buffer;
	output_buffer->capacity = new_capacity;
	output_buffer->tail = 0;
	output_buffer->head = internal_used;
}

/*
 * ring_write
 *
 * Write data to the ring buffer at the given position, handling wrap-around.
 */
static void
ring_write(int pos, const char *data, int len)
{
	int			wrap_pos = pos % output_buffer->capacity;
	int			first_chunk = output_buffer->capacity - wrap_pos;

	if (first_chunk >= len)
	{
		/* No wrap needed */
		memcpy(output_buffer->buffer + wrap_pos, data, len);
	}
	else
	{
		/* Data wraps around */
		memcpy(output_buffer->buffer + wrap_pos, data, first_chunk);
		memcpy(output_buffer->buffer, data + first_chunk, len - first_chunk);
	}
}

/*
 * ring_read
 *
 * Read data from the ring buffer at the given position, handling wrap-around.
 */
static void
ring_read(int pos, char *data, int len)
{
	int			wrap_pos = pos % output_buffer->capacity;
	int			first_chunk = output_buffer->capacity - wrap_pos;

	if (first_chunk >= len)
	{
		/* No wrap needed */
		memcpy(data, output_buffer->buffer + wrap_pos, len);
	}
	else
	{
		/* Data wraps around */
		memcpy(data, output_buffer->buffer + wrap_pos, first_chunk);
		memcpy(data + first_chunk, output_buffer->buffer, len - first_chunk);
	}
}

/*
 * ring_read_uint16
 *
 * Read a 2-byte unsigned integer from the ring buffer, handling wrap-around.
 */
static uint16
ring_read_uint16(int pos)
{
	unsigned char bytes[2];

	ring_read(pos, (char *) bytes, 2);
	return (uint16) bytes[0] | ((uint16) bytes[1] << 8);
}

/*
 * ring_write_uint16
 *
 * Write a 2-byte unsigned integer to the ring buffer.
 */
static void
ring_write_uint16(int pos, uint16 value)
{
	unsigned char bytes[2];

	bytes[0] = value & 0xFF;
	bytes[1] = (value >> 8) & 0xFF;
	ring_write(pos, (char *) bytes, 2);
}

/*
 * add_line_to_buffer
 *
 * Add a completed line to the ring buffer.
 *
 * Overflow check (Oracle behavior):
 * 1. Check user-perceived limit (content bytes only, not counting length prefixes)
 * 2. If internal storage is full but user limit not reached, expand buffer
 *
 * NULL lines use a special marker (0xFFFF) as length.
 */
static void
add_line_to_buffer(const char *line, int line_len)
{
	int			entry_size;
	int			internal_used;
	int			internal_needed;

	/*
	 * Check user-perceived buffer limit BEFORE adding (Oracle behavior).
	 * Only content bytes count toward limit, not length prefixes.
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

	/* Calculate total entry size: 2-byte length prefix + data */
	entry_size = DBMS_OUTPUT_LENGTH_PREFIX_SIZE + (line != NULL ? line_len : 0);

	/*
	 * Check if internal buffer needs expansion.
	 * Internal storage = content bytes + (line_count * 2 bytes for prefixes)
	 */
	internal_used = output_buffer->buffer_used +
		(output_buffer->line_count * DBMS_OUTPUT_LENGTH_PREFIX_SIZE);
	internal_needed = internal_used + entry_size;

	if (internal_needed > output_buffer->capacity)
	{
		/* Expand buffer to accommodate the new entry */
		expand_buffer(entry_size);
	}

	/* Write length prefix (or NULL marker) */
	if (line == NULL)
	{
		ring_write_uint16(output_buffer->head, DBMS_OUTPUT_NULL_MARKER);
	}
	else
	{
		ring_write_uint16(output_buffer->head, (uint16) line_len);
		/* Write line data */
		if (line_len > 0)
			ring_write(output_buffer->head + DBMS_OUTPUT_LENGTH_PREFIX_SIZE, line, line_len);
	}

	output_buffer->head += entry_size;
	output_buffer->buffer_used += line_len;
	output_buffer->line_count++;
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
 * Retrieve one line from buffer and recycle its space (Oracle behavior).
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

	if (output_buffer == NULL || output_buffer->line_count == 0)
	{
		/* No more lines available - return NULL, not empty string (Oracle behavior) */
		nulls[0] = true;		/* line = NULL */
		values[0] = (Datum) 0;
		values[1] = Int32GetDatum(1);	/* status = 1 (no more lines) */
	}
	else
	{
		/* Read length prefix from ring buffer */
		uint16		line_len = ring_read_uint16(output_buffer->tail);
		int			entry_size;

		if (line_len == DBMS_OUTPUT_NULL_MARKER)
		{
			/* NULL line */
			nulls[0] = true;
			values[0] = (Datum) 0;
			entry_size = DBMS_OUTPUT_LENGTH_PREFIX_SIZE;
			/* NULL lines don't count toward buffer_used */
		}
		else
		{
			/* Read line data */
			char	   *line_data = palloc(line_len + 1);

			ring_read(output_buffer->tail + DBMS_OUTPUT_LENGTH_PREFIX_SIZE,
					  line_data, line_len);
			line_data[line_len] = '\0';
			values[0] = CStringGetTextDatum(line_data);
			pfree(line_data);
			entry_size = DBMS_OUTPUT_LENGTH_PREFIX_SIZE + line_len;
			output_buffer->buffer_used -= line_len;
		}
		values[1] = Int32GetDatum(0);	/* status = 0 (success) */

		/* Advance tail to recycle buffer space */
		output_buffer->tail += entry_size;
		output_buffer->line_count--;
	}

	tuple = heap_form_tuple(tupdesc, values, nulls);
	PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
}

/*
 * ora_dbms_output_get_lines
 *
 * Retrieve multiple lines from buffer and recycle their space (Oracle behavior).
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

	if (output_buffer == NULL)
	{
		/* No buffer, return empty array */
		lines_array = construct_empty_array(TEXTOID);
		actual_lines = 0;
	}
	else
	{
		/* Calculate how many lines we can actually return */
		actual_lines = (requested_lines < output_buffer->line_count) ?
			requested_lines : output_buffer->line_count;

		if (actual_lines > 0)
		{
			bool	   *line_nulls;
			int			lbound = 1;  /* 1-based array indexing */

			line_datums = (Datum *) palloc(sizeof(Datum) * actual_lines);
			line_nulls = (bool *) palloc(sizeof(bool) * actual_lines);

			for (i = 0; i < actual_lines; i++)
			{
				/* Read length prefix from ring buffer */
				uint16		line_len = ring_read_uint16(output_buffer->tail);
				int			entry_size;

				if (line_len == DBMS_OUTPUT_NULL_MARKER)
				{
					/* NULL line */
					line_nulls[i] = true;
					line_datums[i] = (Datum) 0;
					entry_size = DBMS_OUTPUT_LENGTH_PREFIX_SIZE;
				}
				else
				{
					/* Read line data */
					char	   *line_data = palloc(line_len + 1);

					ring_read(output_buffer->tail + DBMS_OUTPUT_LENGTH_PREFIX_SIZE,
							  line_data, line_len);
					line_data[line_len] = '\0';
					line_nulls[i] = false;
					line_datums[i] = CStringGetTextDatum(line_data);
					pfree(line_data);
					entry_size = DBMS_OUTPUT_LENGTH_PREFIX_SIZE + line_len;
					output_buffer->buffer_used -= line_len;
				}

				/* Advance tail to recycle buffer space */
				output_buffer->tail += entry_size;
				output_buffer->line_count--;
			}

			lines_array = construct_md_array(line_datums, line_nulls, 1, &actual_lines, &lbound,
											 TEXTOID, -1, false, TYPALIGN_INT);
			pfree(line_datums);
			pfree(line_nulls);
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
