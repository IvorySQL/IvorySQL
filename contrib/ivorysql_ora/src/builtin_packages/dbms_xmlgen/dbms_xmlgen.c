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
 * Row-to-XML rendering and context handles for Oracle's DBMS_XMLGEN.
 * This module is part of ivorysql_ora extension.
 *
 * Two constraints shape this file:
 *
 *  1. A PL/iSQL package body cannot run dynamic SQL (no FOR ... IN EXECUTE in
 *     a body, no EXECUTE IMMEDIATE), so the query runs here through SPI.
 *  2. Assigning to a package-level array element from PL/iSQL is unreliable,
 *     so the context handles live here as backend-local slots and the package
 *     only forwards its arguments.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_xmlgen/dbms_xmlgen.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "executor/spi.h"
#include "utils/builtins.h"
#include "utils/memutils.h"

#define MAX_CONTEXTS 64

typedef struct XmlGenContext
{
	bool		used;
	char	   *query;
	int			max_rows;		/* -1 = no limit */
	int			skip_rows;
	char	   *rowset_tag;
	char	   *row_tag;
	int			processed;
	int			fetched_rows;	/* rows already returned in chunked mode */
} XmlGenContext;

static XmlGenContext contexts[MAX_CONTEXTS];

PG_FUNCTION_INFO_V1(ora_dbms_xmlgen_render);
PG_FUNCTION_INFO_V1(ora_dbms_xmlgen_newcontext);
PG_FUNCTION_INFO_V1(ora_dbms_xmlgen_render_ctx);
PG_FUNCTION_INFO_V1(ora_dbms_xmlgen_set_maxrows);
PG_FUNCTION_INFO_V1(ora_dbms_xmlgen_set_skiprows);
PG_FUNCTION_INFO_V1(ora_dbms_xmlgen_set_rowsettag);
PG_FUNCTION_INFO_V1(ora_dbms_xmlgen_set_rowtag);
PG_FUNCTION_INFO_V1(ora_dbms_xmlgen_closecontext);
PG_FUNCTION_INFO_V1(ora_dbms_xmlgen_numrows);

static XmlGenContext *
get_context(int32 handle)
{
	if (handle < 1 || handle > MAX_CONTEXTS || !contexts[handle - 1].used)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_XMLGEN: no such context handle %d", handle)));
	return &contexts[handle - 1];
}

static char *
context_strdup(const char *value)
{
	MemoryContext old;
	char	   *copy;

	if (value == NULL)
		return NULL;
	old = MemoryContextSwitchTo(TopMemoryContext);
	copy = pstrdup(value);
	MemoryContextSwitchTo(old);
	return copy;
}

static void
append_escaped(StringInfo out, const char *value)
{
	const char *p;

	for (p = value; *p; p++)
	{
		switch (*p)
		{
			case '&':
				appendStringInfoString(out, "&amp;");
				break;
			case '<':
				appendStringInfoString(out, "&lt;");
				break;
			case '>':
				appendStringInfoString(out, "&gt;");
				break;
			default:
				appendStringInfoChar(out, *p);
				break;
		}
	}
}

/*
 * Oracle folds unquoted column names to upper case, and DBMS_XMLGEN uses the
 * folded name as the element name, so <A>, not <a>.
 */
static void
append_column_tag(StringInfo out, const char *name)
{
	const char *p;

	for (p = name; *p; p++)
	{
		if (*p >= 'a' && *p <= 'z')
			appendStringInfoChar(out, *p - 'a' + 'A');
		else
			appendStringInfoChar(out, *p);
	}
}

/*
 * Run the query and return the document.  *emitted receives the number of rows
 * written, which GETNUMROWSPROCESSED reports.
 */
static char *
render_query(const char *query, int max_rows, int skip_rows,
			 const char *rowset_tag, const char *row_tag, int *emitted)
{
	StringInfoData out;
	MemoryContext caller_context = CurrentMemoryContext;
	char	   *result;
	int			rc;
	int			open_len;
	uint64		row;
	uint64		written = 0;

	if (query == NULL)
		return NULL;

	if (SPI_connect() != SPI_OK_CONNECT)
		elog(ERROR, "DBMS_XMLGEN: SPI_connect failed");

	rc = SPI_execute(query, true, 0);
	if (rc != SPI_OK_SELECT)
	{
		SPI_finish();
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_XMLGEN: the query must be a SELECT")));
	}

	initStringInfo(&out);
	appendStringInfo(&out, "<?xml version=\"1.0\"?>\n");
	open_len = out.len;
	appendStringInfo(&out, "<%s>", rowset_tag);

	for (row = 0; row < SPI_processed; row++)
	{
		HeapTuple	tuple = SPI_tuptable->vals[row];
		TupleDesc	desc = SPI_tuptable->tupdesc;
		int			col;

		if (row < (uint64) skip_rows)
			continue;
		if (max_rows >= 0 && written >= (uint64) max_rows)
			break;

		written++;
		appendStringInfo(&out, "\n  <%s>", row_tag);
		for (col = 1; col <= desc->natts; col++)
		{
			char	   *name = SPI_fname(desc, col);
			char	   *value = SPI_getvalue(tuple, desc, col);

			appendStringInfoString(&out, "\n    <");
			append_column_tag(&out, name);
			if (value == NULL)
			{
				appendStringInfoString(&out, "/>");
				continue;
			}
			appendStringInfoChar(&out, '>');
			append_escaped(&out, value);
			appendStringInfoString(&out, "</");
			append_column_tag(&out, name);
			appendStringInfoChar(&out, '>');
		}
		appendStringInfo(&out, "\n  </%s>", row_tag);
	}

	if (written == 0)
	{
		/* Oracle emits an empty document as <ROWSET/>. */
		out.len = open_len;
		out.data[out.len] = '\0';
		appendStringInfo(&out, "<%s/>", rowset_tag);
	}
	else
		appendStringInfo(&out, "\n</%s>", rowset_tag);

	/* SPI_finish() destroys the memory context initStringInfo() used. */
	MemoryContextSwitchTo(caller_context);
	result = pstrdup(out.data);
	SPI_finish();

	if (emitted)
		*emitted = (int) written;
	return result;
}

/* Stateless entry point: used by GETXML(query_string). */
Datum
ora_dbms_xmlgen_render(PG_FUNCTION_ARGS)
{
	char	   *query;
	int			max_rows;
	int			skip_rows;
	char	   *rowset_tag;
	char	   *row_tag;
	char	   *doc;

	/* GETXML(NULL) is a NULL document, not a crash. */
	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	query = text_to_cstring(PG_GETARG_TEXT_PP(0));
	max_rows = PG_ARGISNULL(1) ? -1 : PG_GETARG_INT32(1);
	skip_rows = PG_ARGISNULL(2) ? 0 : PG_GETARG_INT32(2);
	rowset_tag = PG_ARGISNULL(3) ? "ROWSET" :
		text_to_cstring(PG_GETARG_TEXT_PP(3));
	row_tag = PG_ARGISNULL(4) ? "ROW" :
		text_to_cstring(PG_GETARG_TEXT_PP(4));
	doc = render_query(query, max_rows, skip_rows, rowset_tag, row_tag, NULL);

	if (doc == NULL)
		PG_RETURN_NULL();
	PG_RETURN_TEXT_P(cstring_to_text(doc));
}

Datum
ora_dbms_xmlgen_newcontext(PG_FUNCTION_ARGS)
{
	char	   *query;
	int			i;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	query = text_to_cstring(PG_GETARG_TEXT_PP(0));

	for (i = 0; i < MAX_CONTEXTS; i++)
	{
		if (!contexts[i].used)
		{
			contexts[i].used = true;
			contexts[i].query = context_strdup(query);
			contexts[i].max_rows = -1;
			contexts[i].skip_rows = 0;
			contexts[i].rowset_tag = context_strdup("ROWSET");
			contexts[i].row_tag = context_strdup("ROW");
			contexts[i].processed = 0;
			contexts[i].fetched_rows = 0;
			PG_RETURN_INT32(i + 1);
		}
	}
	ereport(ERROR,
			(errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
			 errmsg("DBMS_XMLGEN: too many open contexts")));
	PG_RETURN_INT32(0);
}

Datum
ora_dbms_xmlgen_render_ctx(PG_FUNCTION_ARGS)
{
	XmlGenContext *ctx = get_context(PG_GETARG_INT32(0));
	int			skip = ctx->skip_rows;
	char	   *doc;

	/*
	 * With SETMAXROWS, Oracle treats GETXML as a chunked fetch: each call
	 * returns the next maxrows rows.  Without it, every call renders the whole
	 * result, so the offset stays at SETSKIPROWS.
	 */
	if (ctx->max_rows >= 0)
		skip += ctx->fetched_rows;

	doc = render_query(ctx->query, ctx->max_rows, skip,
					   ctx->rowset_tag, ctx->row_tag, &ctx->processed);

	if (ctx->max_rows >= 0)
		ctx->fetched_rows += ctx->processed;

	if (doc == NULL)
		PG_RETURN_NULL();
	PG_RETURN_TEXT_P(cstring_to_text(doc));
}

Datum
ora_dbms_xmlgen_set_maxrows(PG_FUNCTION_ARGS)
{
	XmlGenContext *ctx = get_context(PG_GETARG_INT32(0));

	ctx->max_rows = PG_ARGISNULL(1) ? -1 : PG_GETARG_INT32(1);
	ctx->fetched_rows = 0;
	PG_RETURN_VOID();
}

Datum
ora_dbms_xmlgen_set_skiprows(PG_FUNCTION_ARGS)
{
	XmlGenContext *ctx = get_context(PG_GETARG_INT32(0));

	ctx->skip_rows = PG_ARGISNULL(1) ? 0 : PG_GETARG_INT32(1);
	ctx->fetched_rows = 0;
	PG_RETURN_VOID();
}

Datum
ora_dbms_xmlgen_set_rowsettag(PG_FUNCTION_ARGS)
{
	XmlGenContext *ctx = get_context(PG_GETARG_INT32(0));
	char	   *tag = PG_ARGISNULL(1) ? "ROWSET" :
		text_to_cstring(PG_GETARG_TEXT_PP(1));

	if (ctx->rowset_tag)
		pfree(ctx->rowset_tag);
	ctx->rowset_tag = context_strdup(tag);
	PG_RETURN_VOID();
}

Datum
ora_dbms_xmlgen_set_rowtag(PG_FUNCTION_ARGS)
{
	XmlGenContext *ctx = get_context(PG_GETARG_INT32(0));
	char	   *tag = PG_ARGISNULL(1) ? "ROW" :
		text_to_cstring(PG_GETARG_TEXT_PP(1));

	if (ctx->row_tag)
		pfree(ctx->row_tag);
	ctx->row_tag = context_strdup(tag);
	PG_RETURN_VOID();
}

Datum
ora_dbms_xmlgen_closecontext(PG_FUNCTION_ARGS)
{
	XmlGenContext *ctx = get_context(PG_GETARG_INT32(0));

	if (ctx->query)
		pfree(ctx->query);
	if (ctx->rowset_tag)
		pfree(ctx->rowset_tag);
	if (ctx->row_tag)
		pfree(ctx->row_tag);
	MemSet(ctx, 0, sizeof(XmlGenContext));
	PG_RETURN_VOID();
}

Datum
ora_dbms_xmlgen_numrows(PG_FUNCTION_ARGS)
{
	XmlGenContext *ctx = get_context(PG_GETARG_INT32(0));

	PG_RETURN_INT32(ctx->processed);
}
