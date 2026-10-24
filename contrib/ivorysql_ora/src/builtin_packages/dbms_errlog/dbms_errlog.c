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
 * Implementation of Oracle's DBMS_ERRLOG package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides DML error logging table generation capabilities:
 *   - CREATE_ERROR_LOG: creates an error logging table for any base table
 *     to capture DML constraint and format violations without failing
 *     the whole transaction.
 *   - DROP_ERROR_LOG: removes an existing error log table.
 *   - PURGE_ERROR_LOG: truncates error records while keeping table structure.
 *   - VERIFY_ERROR_LOG: validates whether an existing error log table matches
 *     base table schema requirements.
 *
 * Default error log table schema format:
 *   - ORA_ERR_NUMBER$   bigint
 *   - ORA_ERR_MESG$     varchar2(2000)
 *   - ORA_ERR_ROWID$    text
 *   - ORA_ERR_OPTYP$    varchar2(2)
 *   - ORA_ERR_TAG$      varchar2(2000)
 *   - Followed by varchar2(4000) representations of base table columns.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_errlog/dbms_errlog.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/relation.h"
#include "catalog/namespace.h"
#include "catalog/pg_attribute.h"
#include "catalog/pg_class.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"
#include "utils/syscache.h"

/*
 * dbms_errlog_create_error_log_internal
 */
PG_FUNCTION_INFO_V1(dbms_errlog_create_error_log_internal);
Datum
dbms_errlog_create_error_log_internal(PG_FUNCTION_ARGS)
{
	text	   *dml_table_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *err_log_table_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	text	   *err_log_owner_text = PG_ARGISNULL(2) ? NULL : PG_GETARG_TEXT_PP(2);
	bool		skip_unsupported = PG_GETARG_BOOL(3);

	char	   *dml_table_name;
	char	   *err_log_table_name;
	char	   *err_log_owner;
	Oid			relid = InvalidOid;
	Relation	rel;
	TupleDesc	tupdesc;
	StringInfoData buf;
	int			i;
	int			ret;

	if (!dml_table_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_ERRLOG.CREATE_ERROR_LOG: dml_table_name must not be NULL")));

	dml_table_name = text_to_cstring(dml_table_text);

	/* Determine target error log table name (default: ERR$_<dml_table_name>) */
	if (err_log_table_text)
		err_log_table_name = text_to_cstring(err_log_table_text);
	else
	{
		initStringInfo(&buf);
		appendStringInfo(&buf, "ERR$_%s", dml_table_name);
		err_log_table_name = pstrdup(buf.data);
		pfree(buf.data);
	}

	err_log_owner = err_log_owner_text ? text_to_cstring(err_log_owner_text) : "public";

	/* Resolve base DML table */
	relid = RelnameGetRelid(dml_table_name);
	if (!OidIsValid(relid))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_TABLE),
				 errmsg("DBMS_ERRLOG: table \"%s\" does not exist", dml_table_name)));

	rel = relation_open(relid, AccessShareLock);
	tupdesc = RelationGetDescr(rel);

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "CREATE TABLE %s.%s ("
					 "ora_err_number$ bigint, "
					 "ora_err_mesg$   varchar2(2000), "
					 "ora_err_rowid$  text, "
					 "ora_err_optyp$  varchar2(2), "
					 "ora_err_tag$    varchar2(2000)",
					 err_log_owner, err_log_table_name);

	/* Append user columns as varchar2(4000) */
	for (i = 0; i < tupdesc->natts; i++)
	{
		Form_pg_attribute att = TupleDescAttr(tupdesc, i);

		if (att->attisdropped || att->attnum < 0)
			continue;

		appendStringInfo(&buf, ", %s varchar2(4000)", NameStr(att->attname));
	}

	appendStringInfoString(&buf, ")");

	relation_close(rel, AccessShareLock);

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	SPI_execute(buf.data, false, 0);

	/* Record registration into sys.errlog_tables */
	resetStringInfo(&buf);
	appendStringInfo(&buf,
					 "INSERT INTO sys.errlog_tables (dml_table_name, err_log_table_name, err_log_owner, created_time) "
					 "VALUES ('%s', '%s', '%s', now()) "
					 "ON CONFLICT (dml_table_name, err_log_table_name) DO NOTHING",
					 dml_table_name, err_log_table_name, err_log_owner);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(dml_table_name);
	pfree(err_log_table_name);
	if (err_log_owner_text)
		pfree(err_log_owner);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_errlog_drop_error_log_internal
 */
PG_FUNCTION_INFO_V1(dbms_errlog_drop_error_log_internal);
Datum
dbms_errlog_drop_error_log_internal(PG_FUNCTION_ARGS)
{
	text	   *dml_table_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *err_log_table_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	char	   *dml_table_name;
	char	   *err_log_table_name;
	StringInfoData buf;
	int			ret;

	if (!dml_table_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_ERRLOG.DROP_ERROR_LOG: dml_table_name must not be NULL")));

	dml_table_name = text_to_cstring(dml_table_text);
	if (err_log_table_text)
		err_log_table_name = text_to_cstring(err_log_table_text);
	else
	{
		initStringInfo(&buf);
		appendStringInfo(&buf, "ERR$_%s", dml_table_name);
		err_log_table_name = pstrdup(buf.data);
		pfree(buf.data);
	}

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf, "DROP TABLE IF EXISTS %s", err_log_table_name);
	SPI_execute(buf.data, false, 0);

	resetStringInfo(&buf);
	appendStringInfo(&buf,
					 "DELETE FROM sys.errlog_tables WHERE dml_table_name = '%s' AND err_log_table_name = '%s'",
					 dml_table_name, err_log_table_name);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(dml_table_name);
	pfree(err_log_table_name);
	SPI_finish();

	PG_RETURN_VOID();
}

/*
 * dbms_errlog_purge_error_log_internal
 */
PG_FUNCTION_INFO_V1(dbms_errlog_purge_error_log_internal);
Datum
dbms_errlog_purge_error_log_internal(PG_FUNCTION_ARGS)
{
	text	   *dml_table_text = PG_ARGISNULL(0) ? NULL : PG_GETARG_TEXT_PP(0);
	text	   *err_log_table_text = PG_ARGISNULL(1) ? NULL : PG_GETARG_TEXT_PP(1);
	char	   *dml_table_name;
	char	   *err_log_table_name;
	StringInfoData buf;
	int			ret;

	if (!dml_table_text)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_ERRLOG.PURGE_ERROR_LOG: dml_table_name must not be NULL")));

	dml_table_name = text_to_cstring(dml_table_text);
	if (err_log_table_text)
		err_log_table_name = text_to_cstring(err_log_table_text);
	else
	{
		initStringInfo(&buf);
		appendStringInfo(&buf, "ERR$_%s", dml_table_name);
		err_log_table_name = pstrdup(buf.data);
		pfree(buf.data);
	}

	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
		ereport(ERROR, (errmsg("SPI_connect failed")));

	initStringInfo(&buf);
	appendStringInfo(&buf, "TRUNCATE TABLE %s", err_log_table_name);
	SPI_execute(buf.data, false, 0);

	pfree(buf.data);
	pfree(dml_table_name);
	pfree(err_log_table_name);
	SPI_finish();

	PG_RETURN_VOID();
}
