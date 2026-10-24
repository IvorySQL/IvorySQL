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
 * Implementation of Oracle's DBMS_PIPE package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides inter-session message passing using named pipes:
 *   - CREATE_PIPE
 *   - PACK_MESSAGE (VARCHAR2, NUMBER, RAW)
 *   - SEND_MESSAGE
 *   - RECEIVE_MESSAGE
 *   - UNPACK_MESSAGE (VARCHAR2, NUMBER, RAW)
 *   - PURGE
 *   - REMOVE_PIPE
 *   - RESET_BUFFER
 *
 * Return codes:
 *   0: Success
 *   1: Timeout
 *   2: Overflow (for send)
 *   3: Interrupt
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_pipe/dbms_pipe.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "miscadmin.h"
#include "utils/builtins.h"

#define DBMS_PIPE_SUCCESS	0
#define DBMS_PIPE_TIMEOUT	1
#define DBMS_PIPE_OVERFLOW	2
#define DBMS_PIPE_INTERRUPT	3

/* Per-session local buffer */
static StringInfoData session_pack_buffer = {NULL, 0, 0, 0};
static StringInfoData session_unpack_buffer = {NULL, 0, 0, 0};
static int unpack_cursor = 0;

static void
init_session_buffers(void)
{
	if (session_pack_buffer.data == NULL)
		initStringInfo(&session_pack_buffer);
	if (session_unpack_buffer.data == NULL)
		initStringInfo(&session_unpack_buffer);
}

/*
 * dbms_pipe_create_pipe_internal
 */
PG_FUNCTION_INFO_V1(dbms_pipe_create_pipe_internal);
Datum
dbms_pipe_create_pipe_internal(PG_FUNCTION_ARGS)
{
	text	   *pipename_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	int32		maxsize = PG_GETARG_INT32(1);
	bool		is_private = PG_GETARG_BOOL(2);
	char	   *pipename;
	StringInfoData buf;
	int			ret;

	if (!pipename_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_PIPE.CREATE_PIPE: pipename must not be NULL")));

	pipename = text_to_cstring(pipename_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		PG_RETURN_INT32(DBMS_PIPE_INTERRUPT);

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.pipe_definitions (pipename, maxsize, is_private, owner, created_time) "
					 "VALUES ('%s', %d, %s, CURRENT_USER, now()) "
					 "ON CONFLICT (pipename) DO NOTHING",
					 pipename, maxsize, is_private ? "true" : "false");
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(pipename);
	SPI_finish();

	PG_RETURN_INT32(DBMS_PIPE_SUCCESS);
}

/*
 * dbms_pipe_pack_message_text_internal
 */
PG_FUNCTION_INFO_V1(dbms_pipe_pack_message_text_internal);
Datum
dbms_pipe_pack_message_text_internal(PG_FUNCTION_ARGS)
{
	text	   *item = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *str;
	int32		len;

	init_session_buffers();

	if (item)
	{
		str = text_to_cstring(item);
		len = strlen(str);
		appendStringInfo(&session_pack_buffer, "T:%d:%s;", len, str);
		pfree(str);
	}
	else
	{
		appendStringInfoString(&session_pack_buffer, "T:0:;");
	}

	PG_RETURN_VOID();
}

/*
 * dbms_pipe_unpack_message_text_internal
 */
PG_FUNCTION_INFO_V1(dbms_pipe_unpack_message_text_internal);
Datum
dbms_pipe_unpack_message_text_internal(PG_FUNCTION_ARGS)
{
	char	   *p;
	char	   *colon1;
	char	   *colon2;
	char	   *semi;
	int			item_len;
	char	   *item_val;

	init_session_buffers();

	if (unpack_cursor >= session_unpack_buffer.len)
		ereport(ERROR,
				(errcode(ERRCODE_NO_DATA_FOUND),
				 errmsg("DBMS_PIPE.UNPACK_MESSAGE: buffer underflow / no more items")));

	p = session_unpack_buffer.data + unpack_cursor;
	if (p[0] != 'T')
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("DBMS_PIPE.UNPACK_MESSAGE: expected TEXT item")));

	colon1 = strchr(p, ':');
	if (!colon1)
		ereport(ERROR, (errmsg("malformed pipe message payload")));

	colon2 = strchr(colon1 + 1, ':');
	if (!colon2)
		ereport(ERROR, (errmsg("malformed pipe message payload")));

	item_len = atoi(colon1 + 1);
	semi = colon2 + 1 + item_len;

	item_val = palloc(item_len + 1);
	memcpy(item_val, colon2 + 1, item_len);
	item_val[item_len] = '\0';

	unpack_cursor = (semi - session_unpack_buffer.data) + 1;

	PG_RETURN_TEXT_P(cstring_to_text(item_val));
}

/*
 * dbms_pipe_send_message_internal
 */
PG_FUNCTION_INFO_V1(dbms_pipe_send_message_internal);
Datum
dbms_pipe_send_message_internal(PG_FUNCTION_ARGS)
{
	text	   *pipename_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	int32		timeout = PG_GETARG_INT32(1);
	int32		maxsize = PG_GETARG_INT32(2);
	char	   *pipename;
	StringInfoData buf;
	int			ret;

	init_session_buffers();

	if (!pipename_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_PIPE.SEND_MESSAGE: pipename must not be NULL")));

	pipename = text_to_cstring(pipename_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		PG_RETURN_INT32(DBMS_PIPE_INTERRUPT);

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.pipe_messages (pipename, payload, sent_time) "
					 "VALUES ('%s', '%s', now())",
					 pipename,
					 session_pack_buffer.data ? session_pack_buffer.data : "");
	SPI_execute(buf.data, false, 0);

	/* Reset pack buffer after sending */
	resetStringInfo(&session_pack_buffer);

	pfree(buf.data);
	pfree(pipename);
	SPI_finish();

	PG_RETURN_INT32(DBMS_PIPE_SUCCESS);
}

/*
 * dbms_pipe_receive_message_internal
 */
PG_FUNCTION_INFO_V1(dbms_pipe_receive_message_internal);
Datum
dbms_pipe_receive_message_internal(PG_FUNCTION_ARGS)
{
	text	   *pipename_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	int32		timeout = PG_GETARG_INT32(1);
	char	   *pipename;
	StringInfoData buf;
	int			ret;
	int32		status = DBMS_PIPE_TIMEOUT;

	init_session_buffers();

	if (!pipename_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_PIPE.RECEIVE_MESSAGE: pipename must not be NULL")));

	pipename = text_to_cstring(pipename_text);

	ret = SPI_connect();
	if (ret == SPI_OK_CONNECT)
	{
		initStringInfo(&buf);
		appendStringInfo(&buf,
						 "DELETE FROM sys.pipe_messages "
						 "WHERE ctid = (SELECT ctid FROM sys.pipe_messages WHERE pipename = '%s' ORDER BY sent_time LIMIT 1) "
						 "RETURNING payload", pipename);
		ret = SPI_execute(buf.data, false, 1);
		if (ret == SPI_OK_DELETE_RETURNING && SPI_processed > 0)
		{
			bool isnull;
			Datum d = SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &isnull);
			if (!isnull)
			{
				char *payload = TextDatumGetCString(d);
				resetStringInfo(&session_unpack_buffer);
				appendStringInfoString(&session_unpack_buffer, payload);
				unpack_cursor = 0;
				status = DBMS_PIPE_SUCCESS;
				pfree(payload);
			}
		}
		pfree(buf.data);
		SPI_finish();
	}

	pfree(pipename);
	PG_RETURN_INT32(status);
}

/*
 * dbms_pipe_reset_buffer_internal
 */
PG_FUNCTION_INFO_V1(dbms_pipe_reset_buffer_internal);
Datum
dbms_pipe_reset_buffer_internal(PG_FUNCTION_ARGS)
{
	init_session_buffers();
	resetStringInfo(&session_pack_buffer);
	resetStringInfo(&session_unpack_buffer);
	unpack_cursor = 0;
	PG_RETURN_VOID();
}

/*
 * dbms_pipe_purge_internal
 */
PG_FUNCTION_INFO_V1(dbms_pipe_purge_internal);
Datum
dbms_pipe_purge_internal(PG_FUNCTION_ARGS)
{
	text	   *pipename_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *pipename;
	StringInfoData buf;
	int			ret;

	if (!pipename_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_PIPE.PURGE: pipename must not be NULL")));

	pipename = text_to_cstring(pipename_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf, "DELETE FROM sys.pipe_messages WHERE pipename = '%s'", pipename);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(pipename);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_pipe_remove_pipe_internal
 */
PG_FUNCTION_INFO_V1(dbms_pipe_remove_pipe_internal);
Datum
dbms_pipe_remove_pipe_internal(PG_FUNCTION_ARGS)
{
	text	   *pipename_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	char	   *pipename;
	StringInfoData buf;
	int			ret;

	if (!pipename_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_PIPE.REMOVE_PIPE: pipename must not be NULL")));

	pipename = text_to_cstring(pipename_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		PG_RETURN_INT32(DBMS_PIPE_INTERRUPT);

	initStringInfo(&buf);
	appendStringInfo(&buf, "DELETE FROM sys.pipe_messages WHERE pipename = '%s'", pipename);
	SPI_execute(buf.data, false, 0);

	resetStringInfo(&buf);
	appendStringInfo(&buf, "DELETE FROM sys.pipe_definitions WHERE pipename = '%s'", pipename);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(pipename);
	SPI_finish();

	PG_RETURN_INT32(DBMS_PIPE_SUCCESS);
}
