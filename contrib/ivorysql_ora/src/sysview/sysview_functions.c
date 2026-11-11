/*------------------------------------------------------------------
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
 * File: sysview_functions.c
 *
 * Abstract: 
 * 		Function which converts all-uppercase text to all-lowercase text 
 * 		and vice versa.
 *
 * Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * Identification:
 *		contrib/ivorysql_ora/src/sysview/sysview_functions.c
 *
 *------------------------------------------------------------------
 */

#include "postgres.h"

#include <sys/resource.h>
#include <sys/time.h>

#include "executor/instrument.h"
#include "fmgr.h"
#include "funcapi.h"
#include "parser/scansup.h"
#include "utils/builtins.h"
#include "utils/tuplestore.h"

PG_FUNCTION_INFO_V1(ora_case_trans);
Datum
ora_case_trans(PG_FUNCTION_ARGS)
{
	char	*string;
	char	*retval;

	if (PG_ARGISNULL(0))
		PG_RETURN_NULL();

	string = (char *) TextDatumGetCString(PG_GETARG_DATUM(0));

	retval = identifier_case_transform(string, strlen(string));

	PG_RETURN_TEXT_P(cstring_to_text(retval));
}

/*
 * ora_mystat_values: backend-local snapshot behind SYS.V$MYSTAT.
 *
 * Emits one row per tracked statistic as (statistic_no, value):
 *
 *   0  "redo size"               pgWalUsage.wal_bytes, in WAL record bytes;
 *                                returned as numeric so the uint64 counter
 *                                is never narrowed to a signed bigint
 *   1  "CPU used by this session" getrusage(RUSAGE_SELF) user+system CPU,
 *                                floored to units of 10ms like Oracle's
 *   2  "session logical reads"   pgBufferUsage shared/local buffer hit and
 *                                read acquisitions; approximates Oracle's
 *                                db block gets + consistent gets, which
 *                                this cannot tell apart
 *   3  "physical reads"          pgBufferUsage shared/local/temp blocks
 *                                read; buffer-manager accounting, not
 *                                necessarily device I/O
 *
 * All counters are process-local and never decrease for the lifetime of
 * the backend.  They are deliberately read directly instead of through
 * the cumulative-statistics machinery, whose transactional caching would
 * hide work done earlier in the same transaction.  The snapshot is taken
 * once, before any result row is built, so all four values belong to one
 * point in time.  The function accepts no arguments: a backend can only
 * ever observe itself.
 */
PG_FUNCTION_INFO_V1(ora_mystat_values);
Datum
ora_mystat_values(PG_FUNCTION_ARGS)
{
	ReturnSetInfo *rsinfo;
	WalUsage		wal_usage;
	BufferUsage		buf_usage;
	struct rusage	ru;
	Datum			values[2];
	bool			nulls[2] = {false, false};
	char			buf[32];
	uint64			cpu_usec;

	/* validates that the caller can accept a materialized set */
	InitMaterializedSRF(fcinfo, 0);
	rsinfo = (ReturnSetInfo *) fcinfo->resultinfo;

	/* one-shot snapshot: only these reads feed the result */
	wal_usage = pgWalUsage;
	buf_usage = pgBufferUsage;
	if (getrusage(RUSAGE_SELF, &ru) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_SYSTEM_ERROR),
				 errmsg("getrusage failed: %m")));

	/*
	 * 0: redo size.  wal_bytes is uint64 and may legitimately exceed
	 * PG_INT64_MAX over a long-lived backend, so it goes through a
	 * decimal string instead of Int64GetDatum.
	 */
	snprintf(buf, sizeof(buf), UINT64_FORMAT, wal_usage.wal_bytes);
	values[0] = Int32GetDatum(0);
	values[1] = DirectFunctionCall3(numeric_in,
									CStringGetDatum(buf),
									ObjectIdGetDatum(0),
									Int32GetDatum(-1));
	tuplestore_putvalues(rsinfo->setResult, rsinfo->setDesc, values, nulls);

	/* 1: CPU used by this session, user+system floored to 10ms units */
	cpu_usec = ((uint64) ru.ru_utime.tv_sec + (uint64) ru.ru_stime.tv_sec)
		* 1000000
		+ (uint64) ru.ru_utime.tv_usec + (uint64) ru.ru_stime.tv_usec;
	snprintf(buf, sizeof(buf), UINT64_FORMAT, cpu_usec / 10000);
	values[0] = Int32GetDatum(1);
	values[1] = DirectFunctionCall3(numeric_in,
									CStringGetDatum(buf),
									ObjectIdGetDatum(0),
									Int32GetDatum(-1));
	tuplestore_putvalues(rsinfo->setResult, rsinfo->setDesc, values, nulls);

	/*
	 * 2: session logical reads.  Summing in uint64 avoids signed
	 * overflow; the counters themselves never go negative.
	 */
	snprintf(buf, sizeof(buf), UINT64_FORMAT,
			 (uint64) buf_usage.shared_blks_hit
			 + (uint64) buf_usage.shared_blks_read
			 + (uint64) buf_usage.local_blks_hit
			 + (uint64) buf_usage.local_blks_read);
	values[0] = Int32GetDatum(2);
	values[1] = DirectFunctionCall3(numeric_in,
									CStringGetDatum(buf),
									ObjectIdGetDatum(0),
									Int32GetDatum(-1));
	tuplestore_putvalues(rsinfo->setResult, rsinfo->setDesc, values, nulls);

	/* 3: physical reads, including temp-file blocks */
	snprintf(buf, sizeof(buf), UINT64_FORMAT,
			 (uint64) buf_usage.shared_blks_read
			 + (uint64) buf_usage.local_blks_read
			 + (uint64) buf_usage.temp_blks_read);
	values[0] = Int32GetDatum(3);
	values[1] = DirectFunctionCall3(numeric_in,
									CStringGetDatum(buf),
									ObjectIdGetDatum(0),
									Int32GetDatum(-1));
	tuplestore_putvalues(rsinfo->setResult, rsinfo->setDesc, values, nulls);

	PG_RETURN_NULL();
}
