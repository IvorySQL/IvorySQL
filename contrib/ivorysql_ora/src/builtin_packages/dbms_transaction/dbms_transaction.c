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
 * Implementation of Oracle's DBMS_TRANSACTION package (savepoint subset).
 * This module is part of ivorysql_ora extension.
 *
 * COMMIT, ROLLBACK, READ ONLY/READ WRITE and the metadata readers are plain
 * PL/iSQL wrappers (see dbms_transaction--1.0.sql) around statements the
 * language already supports natively.  Only the named-savepoint operations
 * need a C-level bridge, because PL/iSQL has no SAVEPOINT/ROLLBACK TO
 * SAVEPOINT statement of its own.
 *
 * These bridge functions call DefineSavepoint()/RollbackToSavepoint()
 * (declared in access/xact.h) directly rather than going through SPI.
 * Unlike SPI_commit()/SPI_rollback(), a savepoint operation never
 * terminates the current top-level transaction -- it only marks the
 * transaction state so a subtransaction is started/ended when control
 * returns to CommitTransactionCommand() at the end of the current
 * top-level command, exactly as happens for a plain SQL SAVEPOINT /
 * ROLLBACK TO SAVEPOINT statement.  That means none of SPI's machinery
 * (connection stack, atomic-context checks, the PG_TRY/
 * StartTransactionCommand dance SPI_commit()/SPI_rollback() need) is
 * relevant here, so there is nothing to gain from routing through SPI --
 * standard_ProcessUtility() calls these same xact.c functions directly
 * for a plain SQL SAVEPOINT statement, and this bridge does the same.
 *
 * "control returns to CommitTransactionCommand() at the end of the current
 * top-level command" above is not just descriptive, it is load-bearing:
 * DefineSavepoint()/RollbackToSavepoint() only push a placeholder
 * transaction-state node (blockState TBLOCK_SUBBEGIN, or a pending restart
 * for rollback) -- xact.c's own comment on StartSubTransaction() explains
 * that finishing the job is deliberately deferred because "the SAVEPOINT
 * utility command will be executed inside a Portal", so the real
 * subtransaction setup has to wait for CommitTransactionCommand() to run
 * once that Portal's top-level command has fully finished.  A bare SQL
 * SAVEPOINT/ROLLBACK TO SAVEPOINT statement is always its own complete
 * top-level command, so that handoff always happens before anything else
 * can run.  When SAVEPOINT/ROLLBACK_SAVEPOINT is called from *inside*
 * another already-executing PL/iSQL routine, though, the enclosing routine
 * keeps running -- and can invoke more package/PL code -- before that
 * top-level command ever finishes.  Any such call (even something with no
 * relation to transactions at all, like DBMS_OUTPUT.PUT_LINE) needs a
 * catalog/relcache lookup, and doing that while the pushed transaction
 * state is still just a placeholder trips an Assert(IsTransactionState())
 * in relcache.c and takes the whole backend down with SIGABRT.
 *
 * (A tempting-looking alternative -- calling CommitTransactionCommand()/
 * StartTransactionCommand() ourselves right away, to finish that handoff
 * immediately instead of refusing the nested call -- was tried and
 * discarded: doing so from mid-command, underneath an already-open SPI
 * connection, desyncs resource-owner bookkeeping ("snapshot reference ...
 * is not owned by resource owner SubTransaction") instead of fixing
 * anything. check_not_nested_in_pl_call() below just refuses the
 * combination up front with an ordinary ERROR instead.)
 *
 * check_not_nested_in_pl_call() applies unconditionally, with no exemption
 * for PRAGMA AUTONOMOUS_TRANSACTION.  An earlier version tried to carve one
 * out by reading the plisql.inside_autonomous_transaction GUC (set by the
 * autonomous-transaction machinery, see pl_autonomous.c/pl_handler.c) and
 * skipping this check when it was "on" -- but that GUC is PGC_USERSET (it
 * has to be, so dblink's own separate connection can set it via plain SQL;
 * see the comment on its DefineCustomBoolVariable() call in pl_handler.c),
 * meaning any ordinary session can just "SET plisql.inside_autonomous_
 * transaction = true" before making a nested call and walk straight past
 * this guard into the unsafe DefineSavepoint()/RollbackToSavepoint() path
 * it exists to block.  There is no session-local state here that only the
 * real dblink machinery can set, so no such exemption can be made safely.
 *
 * The exemption was also unnecessary for the case it targeted: a genuine
 * autonomous-transaction call arrives over a fresh, single-use dblink
 * connection (dblink_exec()/dblink() with no connection name always open-
 * execute-close a brand new session) that never has an explicit transaction
 * block open, so RequireTransactionBlock(true, ...) -- which runs *before*
 * check_not_nested_in_pl_call() in both entry points below -- already
 * rejects it with "SAVEPOINT can only be used in transaction blocks" every
 * time, regardless of this check.  Removing the exemption changes nothing
 * for that legitimate case and closes the bypass for every other one.
 *
 * Portions Copyright (c) 2025-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_transaction/dbms_transaction.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"
#include "access/xact.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "utils/builtins.h"

/*
 * Oracle limits a savepoint identifier to 30 bytes; we are more generous but
 * still reject absurdly long names up front rather than let them flow into
 * TopTransactionContext-allocated savepoint bookkeeping.
 */
#define DBMS_TRANSACTION_SAVEPOINT_NAME_LEN	256

PG_FUNCTION_INFO_V1(ora_dbms_transaction_savepoint);
PG_FUNCTION_INFO_V1(ora_dbms_transaction_rollback_savepoint);

static char *
get_savepoint_name(FunctionCallInfo fcinfo)
{
	char	   *name;

	if (PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
				 errmsg("DBMS_TRANSACTION savepoint name must not be NULL")));

	name = text_to_cstring(PG_GETARG_TEXT_PP(0));

	if (strlen(name) >= DBMS_TRANSACTION_SAVEPOINT_NAME_LEN)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("DBMS_TRANSACTION savepoint name too long (max %d bytes)",
						DBMS_TRANSACTION_SAVEPOINT_NAME_LEN - 1)));

	return name;
}

/*
 * check_not_nested_in_pl_call
 *
 * Reject SAVEPOINT/ROLLBACK_SAVEPOINT when this call is nested inside
 * another already-executing PL/iSQL routine, rather than being the direct
 * result of a top-level CALL to DBMS_TRANSACTION.SAVEPOINT/
 * ROLLBACK_SAVEPOINT itself.  See the file header comment for why, and for
 * why this has no exemption for PRAGMA AUTONOMOUS_TRANSACTION.
 *
 * plisql_call_handler() (and every other PL/iSQL entry point) calls
 * SPI_connect_ext() once per invocation, so SPI_get_connected() reports 0
 * only when the routine currently running -- here, DBMS_TRANSACTION's own
 * SAVEPOINT/ROLLBACK_SAVEPOINT wrapper procedure -- is itself the outermost
 * SPI-connected call, i.e. was reached directly from a top-level CALL.  Any
 * higher value means one or more PL/iSQL routines are already running
 * underneath us, and control will return to them (not to
 * CommitTransactionCommand()) once we're done.
 */
static void
check_not_nested_in_pl_call(const char *stmtType)
{
	if (SPI_get_connected() > 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_TRANSACTION_STATE),
				 errmsg("DBMS_TRANSACTION.%s cannot be called from within another PL/iSQL routine",
						stmtType),
				 errdetail("It must be the direct result of a top-level CALL, the same way a bare SQL "
						   "SAVEPOINT/ROLLBACK TO SAVEPOINT statement must be its own complete statement."),
				 errhint("Move the call to DBMS_TRANSACTION.%s out to its own top-level CALL statement.",
						 stmtType)));
}

/*
 * DBMS_TRANSACTION.SAVEPOINT(name)
 *
 * Establishes a named savepoint in the current transaction.  Requires an
 * explicit transaction block to already be open, same as a bare SQL
 * SAVEPOINT statement -- unlike COMMIT/ROLLBACK, this has nothing to do
 * with atomic vs. non-atomic CALL context.
 */
Datum
ora_dbms_transaction_savepoint(PG_FUNCTION_ARGS)
{
	char	   *name = get_savepoint_name(fcinfo);

	RequireTransactionBlock(true, "SAVEPOINT");
	check_not_nested_in_pl_call("SAVEPOINT");
	DefineSavepoint(name);

	PG_RETURN_VOID();
}

/*
 * DBMS_TRANSACTION.ROLLBACK_SAVEPOINT(name)
 *
 * Rolls back to a previously established savepoint without ending the
 * transaction.  Requires an explicit transaction block for the same reason
 * SAVEPOINT does: RollbackToSavepoint() asserts the transaction state is
 * already TBLOCK_INPROGRESS (or a subtransaction thereof), which is only
 * true once a transaction block has been started.  Without this guard,
 * calling ROLLBACK_SAVEPOINT as a standalone top-level statement hits that
 * state-machine assertion and crashes the backend instead of raising a
 * normal error -- standard_ProcessUtility() guards the equivalent plain SQL
 * ROLLBACK TO SAVEPOINT statement the same way.
 */
Datum
ora_dbms_transaction_rollback_savepoint(PG_FUNCTION_ARGS)
{
	char	   *name = get_savepoint_name(fcinfo);

	RequireTransactionBlock(true, "ROLLBACK TO SAVEPOINT");
	check_not_nested_in_pl_call("ROLLBACK_SAVEPOINT");
	RollbackToSavepoint(name);

	PG_RETURN_VOID();
}
