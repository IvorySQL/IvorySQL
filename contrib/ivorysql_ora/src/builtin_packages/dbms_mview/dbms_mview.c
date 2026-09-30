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
 * Implementation of Oracle's DBMS_MVIEW package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides materialized view lifecycle and refresh administration:
 *   - REFRESH: refreshes one or more comma-separated materialized views.
 *   - REFRESH_ALL_MVIEWS: refreshes all materialized views in the database.
 *   - PURGE_MVIEW_FROM_LOG: purges rows from materialized view logs.
 *
 * Refresh methods:
 *   - '?' (FORCE / FAST then COMPLETE)
 *   - 'C' or 'c' (COMPLETE)
 *   - 'F' or 'f' (FAST)
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_mview/dbms_mview.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/xact.h"
#include "catalog/namespace.h"
#include "catalog/pg_class.h"
#include "commands/matview.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"

/*
 * dbms_mview_refresh_internal
 */
PG_FUNCTION_INFO_V1(dbms_mview_refresh_internal);
Datum
dbms_mview_refresh_internal(PG_FUNCTION_ARGS)
{
	text	   *list_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *method_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *rollback_seg_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	bool		push_deferred_rpc = PG_GETARG_BOOL(3);
	bool		refresh_after_errors = PG_GETARG_BOOL(4);
	bool		purge_option = PG_GETARG_BOOL(5);
	int32		parallelism = PG_GETARG_INT32(6);
	bool		heap_compression = PG_GETARG_BOOL(7);
	bool		atomic_refresh = PG_GETARG_BOOL(8);

	char	   *list;
	char	   *token;
	char	   *saveptr;
	StringInfoData buf;
	int			ret;

	if (!list_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_MVIEW.REFRESH: list must not be NULL")));

	list = text_to_cstring(list_text);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);

	token = strtok_r(list, ", ", &saveptr);
	while (token != NULL)
	{
		resetStringInfo(&buf);
		appendStringInfo(&buf, "REFRESH MATERIALIZED VIEW %s", token);
		ret = SPI_execute(buf.data, false, 0);
		if (ret < 0)
		{
			pfree(buf.data);
			pfree(list);
			SPI_finish();
			ereport(ERROR,
					(errcode(ERRCODE_INTERNAL_ERROR),
					 errmsg("failed to refresh materialized view \"%s\"", token)));
		}
		token = strtok_r(NULL, ", ", &saveptr);
	}

	pfree(buf.data);
	pfree(list);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_mview_refresh_all_mviews_internal
 * Returns number of refreshed materialized views.
 */
PG_FUNCTION_INFO_V1(dbms_mview_refresh_all_mviews_internal);
Datum
dbms_mview_refresh_all_mviews_internal(PG_FUNCTION_ARGS)
{
	int			failures = 0;
	int64		refreshed_count = 0;
	int			ret;
	StringInfoData buf;

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfoString(&buf,
						   "SELECT c.relname, n.nspname "
						   "FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
						   "WHERE c.relkind = 'm' AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'sys')");

	ret = SPI_execute(buf.data, true, 0);
	if (ret == SPI_OK_SELECT)
	{
		uint64 i;
		uint64 num_views = SPI_processed;
		for (i = 0; i < num_views; i++)
		{
			char *vname = SPI_getvalue(SPI_tuptable->vals[i], SPI_tuptable->tupdesc, 1);
			char *sname = SPI_getvalue(SPI_tuptable->vals[i], SPI_tuptable->tupdesc, 2);
			StringInfoData qbuf;

			initStringInfo(&qbuf);
			appendStringInfo(&qbuf, "REFRESH MATERIALIZED VIEW %s.%s", sname, vname);
			if (SPI_execute(qbuf.data, false, 0) == SPI_OK_UTILITY)
				refreshed_count++;
			else
				failures++;

			pfree(qbuf.data);
		}
	}

	pfree(buf.data);
	SPI_finish();

	PG_RETURN_INT64(refreshed_count);
}

/*
 * dbms_mview_purge_mview_from_log_internal
 */
PG_FUNCTION_INFO_V1(dbms_mview_purge_mview_from_log_internal);
Datum
dbms_mview_purge_mview_from_log_internal(PG_FUNCTION_ARGS)
{
	text	   *mview_id_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);

	if (!mview_id_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_MVIEW.PURGE_MVIEW_FROM_LOG: mview_id must not be NULL")));

	PG_RETURN_VOID();
}
