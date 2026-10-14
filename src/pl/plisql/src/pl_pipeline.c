/*-------------------------------------------------------------------------
 *
 * pl_pipeline.c
 *	  IvorySQL: resumable execution for Oracle PIPELINED table functions.
 *
 * A pipelined function is executed by an explicit frame-stack interpreter
 * instead of the recursive exec_stmt machinery in pl_exec.c: the C call
 * stack never spans a yield.  One PipeInvocation owns a persistent
 * PLiSQL_execstate (allocated in the SRF's multi-call memory context)
 * plus a stack of PipeFrames; each frame records the statement list being
 * walked and the index of the next statement.  Every call of the
 * value-per-call SRF resumes the machine from the saved program counter
 * and runs until the next PIPE ROW (which yields one row) or a bare
 * RETURN / end of function (which ends the stream).  Nothing observed
 * before the yield is replayed on the next call.
 *
 * Supported frames: BLOCK, IF, CASE, LOOP, WHILE, integer FOR, query FOR
 * (static or cursor).  All other statements are leaves executed with the
 * regular pl_exec.c helpers, which are shared (not duplicated) with the
 * non-pipelined paths.
 *
 * Lifecycle:
 *
 *  - The compiled function's use_count is held for the whole invocation,
 *    so CREATE OR REPLACE cannot free it mid-stream.
 *  - A query-FOR portal stays open across calls; it is closed explicitly
 *    at natural end and on errors raised inside a call.  On transaction
 *    abort the ResourceOwner releases the portal and then our invocation
 *    record (registered through a custom resource kind); that release
 *    callback must not raise and must not touch already-freed resources.
 *  - An ExprContext shutdown callback covers the normal LIMIT/CLOSE
 *    teardown, where the executor stops calling the SRF without a final
 *    call.  A MemoryContextResetCallback on the invocation context backs
 *    the same idempotent release up if the context is reset (rather than
 *    deleted) by any cleanup path.
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 * Portions Copyright (c) 1996-2026, PostgreSQL Global Development Group
 *
 *	src/pl/plisql/src/pl_pipeline.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/tupconvert.h"
#include "access/xact.h"
#include "catalog/pg_type.h"
#include "commands/typecmds.h"
#include "executor/spi.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "parser/parse_coerce.h"
#include "plisql.h"
#include "pl_package.h"
#include "storage/lock.h"
#include "tcop/pquery.h"
#include "utils/datum.h"
#include "utils/expandeddatum.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/typcache.h"

/* --------------------------------------------------------------------------
 * Frames
 * --------------------------------------------------------------------------
 */
typedef enum PipeFrameKind
{
	PIPE_FRAME_BLOCK,			/* PLiSQL_stmt_block (no exception handlers:
								 * rejected at compile time) */
	PIPE_FRAME_IF,				/* chosen branch list */
	PIPE_FRAME_CASE,			/* chosen branch list */
	PIPE_FRAME_LOOP,
	PIPE_FRAME_WHILE,
	PIPE_FRAME_FORI,
	PIPE_FRAME_FORS,			/* static query FOR */
	PIPE_FRAME_FORC,			/* cursor FOR */
} PipeFrameKind;

typedef struct PipeFrame
{
	PipeFrameKind kind;
	PLiSQL_stmt *stmt;			/* owning control statement */
	char	   *label;			/* owning statement's label, or NULL */
	List	   *body;			/* statement list being walked */
	int			pc;				/* next statement index in body */

	/* integer FOR state */
	bool		fori_reverse;
	int32		fori_value;
	int32		fori_lower;
	int32		fori_upper;
	int32		fori_step;
	bool		fori_done;
	bool		loop_found;

	/* query FOR state */
	Portal		portal;			/* open across yields */
	bool		curvar_was_null;	/* FOR c: cursor variable was NULL */
	int			curvarno;		/* FOR c: datum dno of cursor variable */
} PipeFrame;

/*
 * Per-invocation state, allocated in the SRF's multi-call memory context.
 */
typedef struct PipeInvocation
{
	PLiSQL_function *func;		/* use_count held while this exists */
	PLiSQL_execstate estate;	/* persistent execution state */

	List	   *frames;			/* PipeFrame stack, innermost last */
	bool		started;		/* top-level block pushed? */
	bool		done;			/* stream finished */
	bool		released;		/* cleanup already performed */

	/* current yielded value (valid until the next yield) */
	Datum		retval;			/* scalar value or composite tuple pointer */
	bool		retisnull;
	bool		retbyval;
	int16		rettyplen;

	/*
	 * Per-yield allocation context: reset at the start of each call, after
	 * the executor has consumed the previous row.
	 */
	MemoryContext yieldcxt;

	/* expected composite tupdesc (from get_call_result_type) */
	TupleDesc	rettupdesc;

	/* element typmod inherited from the collection declaration, or -1 */
	int32		elemtypmod;

	/* the SRF multi-call context this invocation lives in */
	MemoryContext mcxt;

	/* idempotent release machinery */
	MemoryContextCallback mcb;	/* reset callback on mcxt */
	ResourceOwner resowner;		/* owner we registered with */
} PipeInvocation;

static const ResourceOwnerDesc pipe_invocation_resdesc;

static void pipe_release_invocation(PipeInvocation *inv, bool close_portal);
static void pipe_reset_cb(void *arg);
static void pipe_shutdown_cb(Datum arg);
static void pipe_owner_release(Datum res);
static void pipe_expr_cache_reset(PLiSQL_expr *expr, void *context);

/* --------------------------------------------------------------------------
 * Frame helpers
 * --------------------------------------------------------------------------
 */

static PipeFrame *
pipe_push_frame(PipeInvocation *inv, PipeFrameKind kind, PLiSQL_stmt *stmt,
				char *label, List *body)
{
	PipeFrame  *frame;

	frame = (PipeFrame *) palloc0_object(PipeFrame);
	frame->kind = kind;
	frame->stmt = stmt;
	frame->label = label;
	frame->body = body;
	frame->pc = 0;

	inv->frames = lappend(inv->frames, frame);
	return frame;
}

static void
pipe_close_frame_portal(PipeFrame *frame)
{
	if (frame->portal != NULL)
	{
		SPI_cursor_close(frame->portal);
		frame->portal = NULL;
	}
}

/* Unwind every discarded frame before shortening the stack. */
static void
pipe_discard_frames(PipeInvocation *inv, int keep)
{
	int			i;

	for (i = list_length(inv->frames) - 1; i >= keep; i--)
	{
		PipeFrame  *frame = (PipeFrame *) list_nth(inv->frames, i);

		pipe_close_frame_portal(frame);
		if (frame->kind == PIPE_FRAME_FORC && frame->curvar_was_null)
		{
			PLiSQL_var *curvar = (PLiSQL_var *)
				plisql_get_datum(&inv->estate,
								 inv->estate.datums[frame->curvarno]);

			assign_simple_var(&inv->estate, curvar, (Datum) 0, true, false);
		}
		if (frame->kind == PIPE_FRAME_FORI ||
			frame->kind == PIPE_FRAME_FORS ||
			frame->kind == PIPE_FRAME_FORC)
			exec_set_found(&inv->estate, frame->loop_found);
	}
	inv->frames = list_truncate(inv->frames, keep);
}

/* --------------------------------------------------------------------------
 * EXIT / CONTINUE handling
 * --------------------------------------------------------------------------
 */

/*
 * Handle RC_EXIT / RC_CONTINUE produced by a leaf statement.  Unlabeled
 * EXIT stops the innermost loop; labeled forms stop the block or loop
 * carrying the label.  CONTINUE restarts the innermost (or labeled) loop.
 */
static void
pipe_handle_exit(PipeInvocation *inv, int rc)
{
	char	   *label = inv->estate.exitlabel;
	int			i;

	inv->estate.exitlabel = NULL;

	for (i = list_length(inv->frames) - 1; i >= 0; i--)
	{
		PipeFrame  *frame = (PipeFrame *) list_nth(inv->frames, i);
		bool		is_loop = (frame->kind == PIPE_FRAME_LOOP ||
							   frame->kind == PIPE_FRAME_WHILE ||
							   frame->kind == PIPE_FRAME_FORI ||
							   frame->kind == PIPE_FRAME_FORS ||
							   frame->kind == PIPE_FRAME_FORC);

		if (label != NULL)
		{
			if (frame->label != NULL && strcmp(frame->label, label) == 0)
			{
				if (rc == PLISQL_RC_CONTINUE)
				{
					/* drop everything above the loop, restart it */
					pipe_discard_frames(inv, i + 1);
					frame->pc = list_length(frame->body);
				}
				else
					/* EXIT: drop the target frame and everything above */
					pipe_discard_frames(inv, i);
				return;
			}
			continue;			/* keep unwinding through non-matching frames */
		}

		if (rc == PLISQL_RC_CONTINUE)
		{
			if (is_loop)
			{
				pipe_discard_frames(inv, i + 1);
				frame->pc = list_length(frame->body);
				return;
			}
			/*
			 * CONTINUE inside a nested non-loop block (IF/CASE): pop the
			 * block and keep unwinding to the loop.
			 */
		}
		else
		{
			if (is_loop)
			{
				pipe_discard_frames(inv, i);
				return;
			}
			/* unlabeled EXIT through a block: pop it and keep going */
		}
	}

	elog(ERROR, "label \"%s\" does not exist", label ? label : "?");
}

/* --------------------------------------------------------------------------
 * Frame end-of-body handling
 *
 * Returns true if the frame stays (another iteration begins), false when
 * the frame is finished and must be popped.
 * --------------------------------------------------------------------------
 */
static bool
pipe_frame_iteration(PipeInvocation *inv, PipeFrame *frame)
{
	PLiSQL_execstate *estate = &inv->estate;

	switch (frame->kind)
	{
		case PIPE_FRAME_BLOCK:
		case PIPE_FRAME_IF:
		case PIPE_FRAME_CASE:
			return false;

		case PIPE_FRAME_LOOP:
			frame->pc = 0;
			return true;

		case PIPE_FRAME_WHILE:
			{
				PLiSQL_stmt_while *stmt = (PLiSQL_stmt_while *) frame->stmt;
				bool		value;
				bool		isnull;

				value = exec_eval_boolean(estate, stmt->cond, &isnull);
				exec_eval_cleanup(estate);
				if (isnull || !value)
					return false;
				frame->pc = 0;
				return true;
			}

		case PIPE_FRAME_FORI:
			{
				PLiSQL_stmt_fori *stmt = (PLiSQL_stmt_fori *) frame->stmt;
				PLiSQL_var *lvar;

				if (frame->fori_done)
				{
					exec_set_found(estate, frame->loop_found);
					return false;
				}

				if (frame->fori_reverse ?
					(frame->fori_value < PG_INT32_MIN + frame->fori_step) :
					(frame->fori_value > PG_INT32_MAX - frame->fori_step))
				{
					frame->fori_done = true;
					exec_set_found(estate, frame->loop_found);
					return false;
				}
				frame->fori_value += (frame->fori_reverse ?
									  -frame->fori_step : frame->fori_step);
				if (frame->fori_reverse ?
					(frame->fori_value < frame->fori_lower) :
					(frame->fori_value > frame->fori_upper))
				{
					frame->fori_done = true;
					exec_set_found(estate, frame->loop_found);
					return false;
				}
				/* assign the invocation's copy of the datum */
				lvar = (PLiSQL_var *)
					plisql_get_datum(estate,
									 estate->datums[stmt->var->dno]);
				assign_simple_var(estate, lvar,
								  Int32GetDatum(frame->fori_value),
								  false, false);
				frame->pc = 0;
				return true;
			}

		case PIPE_FRAME_FORS:
		case PIPE_FRAME_FORC:
			{
				PLiSQL_stmt_forq *stmt = (PLiSQL_stmt_forq *) frame->stmt;
				PLiSQL_variable *lvar;

				/* Fetch exactly one row per resumption (lazy). */
				SPI_cursor_fetch(frame->portal, true, 1);

				if (SPI_processed == 0)
				{
					/* exhausted */
					pipe_close_frame_portal(frame);
					exec_set_found(estate, frame->loop_found);
					return false;
				}
				frame->loop_found = true;

				/* assign the invocation's copy of the loop variable */
				lvar = (PLiSQL_variable *)
					plisql_get_datum(estate, estate->datums[stmt->var->dno]);
				exec_move_row(estate, lvar,
							  SPI_tuptable->vals[0],
							  SPI_tuptable->tupdesc);
				SPI_freetuptable(SPI_tuptable);
				SPI_tuptable = NULL;
				SPI_processed = 0;
				exec_eval_cleanup(estate);
				frame->pc = 0;
				return true;
			}
	}

	elog(ERROR, "unrecognized pipelined frame kind: %d", (int) frame->kind);
	return false;				/* not reached */
}

/* --------------------------------------------------------------------------
 * Query FOR frame setup
 * --------------------------------------------------------------------------
 */

static void
pipe_setup_fors(PipeInvocation *inv, PLiSQL_stmt_fors *stmt)
{
	PipeFrame  *frame;
	ParamListInfo paramLI;

	exec_prepare_plan(&inv->estate, stmt->query, 0);
	paramLI = setup_param_list(&inv->estate, stmt->query);

	frame = pipe_push_frame(inv, PIPE_FRAME_FORS, (PLiSQL_stmt *) stmt,
							stmt->label, stmt->body);
	frame->portal = SPI_cursor_open_with_paramlist(NULL, stmt->query->plan,
												   paramLI,
												   inv->estate.readonly_func);
	if (frame->portal == NULL)
		elog(ERROR, "could not open implicit cursor: %s",
			 SPI_result_code_string(SPI_result));

	/*
	 * Fetch the first row now: like exec_stmt_fors, the loop body must not
	 * run until a row has been assigned to the loop variable.  If the query
	 * produced no rows, drop the frame immediately.
	 */
	if (!pipe_frame_iteration(inv, frame))
	{
		inv->frames = list_delete_ptr(inv->frames, frame);
	}
}

static void
pipe_setup_forc(PipeInvocation *inv, PLiSQL_stmt_forc *stmt)
{
	PLiSQL_execstate *estate = &inv->estate;
	PipeFrame  *frame;
	PLiSQL_var *curvar;
	MemoryContext stmt_mcontext = NULL;
	char	   *curname = NULL;
	PLiSQL_expr *query;
	ParamListInfo paramLI;

	curvar = (PLiSQL_var *) plisql_get_datum(estate,
											 estate->datums[stmt->curvar]);
	if (!curvar->isnull)
	{
		MemoryContext oldcontext;

		/* We only need stmt_mcontext to hold the cursor name string */
		stmt_mcontext = get_stmt_mcontext(estate);
		oldcontext = MemoryContextSwitchTo(stmt_mcontext);
		curname = TextDatumGetCString(curvar->value);
		MemoryContextSwitchTo(oldcontext);

		if (SPI_cursor_find(curname) != NULL)
			ereport(ERROR,
					(errcode(ERRCODE_DUPLICATE_CURSOR),
					 errmsg("cursor \"%s\" already in use", curname)));
	}

	/* Bind cursor arguments, same as exec_stmt_forc. */
	if (stmt->argquery != NULL)
	{
		PLiSQL_stmt_execsql set_args;

		if (curvar->cursor_explicit_argrow < 0)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("arguments given for cursor without arguments")));

		memset(&set_args, 0, sizeof(set_args));
		set_args.cmd_type = PLISQL_STMT_EXECSQL;
		set_args.lineno = stmt->lineno;
		set_args.sqlstmt = stmt->argquery;
		set_args.into = true;
		/* XXX historically this has not been STRICT */
		if (OidIsValid(curvar->pkgoid))
			set_args.target = (PLiSQL_variable *)
				get_package_datum_bydno(estate, curvar->pkgoid,
										curvar->cursor_explicit_argrow);
		else
			set_args.target = (PLiSQL_variable *)
				(estate->datums[curvar->cursor_explicit_argrow]);

		if (exec_stmt_execsql(estate, &set_args) != PLISQL_RC_OK)
			elog(ERROR, "open cursor failed during argument processing");
	}
	else
	{
		if (curvar->cursor_explicit_argrow >= 0)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("arguments required for cursor")));
	}

	query = curvar->cursor_explicit_expr;
	Assert(query);
	if (query->plan == NULL)
		exec_prepare_plan(estate, query, curvar->cursor_options);

	paramLI = setup_param_list(estate, query);

	frame = pipe_push_frame(inv, PIPE_FRAME_FORC, (PLiSQL_stmt *) stmt,
							stmt->label, stmt->body);
	frame->portal = SPI_cursor_open_with_paramlist(curname, query->plan,
												   paramLI,
												   estate->readonly_func);
	if (frame->portal == NULL)
		elog(ERROR, "could not open cursor: %s",
			 SPI_result_code_string(SPI_result));
	frame->curvarno = stmt->curvar;
	frame->curvar_was_null = (curname == NULL);

	if (curname == NULL)
		assign_text_var(estate, curvar, frame->portal->name);

	exec_eval_cleanup(estate);
	if (stmt_mcontext)
		MemoryContextReset(stmt_mcontext);

	/* Fetch the first row before the body runs (see pipe_setup_fors). */
	if (!pipe_frame_iteration(inv, frame))
	{
		inv->frames = list_delete_ptr(inv->frames, frame);
		if (frame->curvar_was_null)
		{
			PLiSQL_var *curvar2 = (PLiSQL_var *)
				plisql_get_datum(estate, estate->datums[frame->curvarno]);

			assign_simple_var(estate, curvar2, (Datum) 0, true, false);
		}
	}
}

/* --------------------------------------------------------------------------
 * Yield machinery
 * --------------------------------------------------------------------------
 */

/*
 * Evaluate a PIPE ROW expression once, convert it to the element type and
 * park the result in the invocation so it outlives this call.
 *
 * All per-yield allocations go into inv->yieldcxt, which the driver resets
 * at the start of each call: the previous row has already been consumed by
 * then (the executor consumes each row synchronously before issuing the
 * next call), so no per-row pfree bookkeeping is needed.
 */
static void
pipe_do_yield(PipeInvocation *inv, PLiSQL_stmt_pipe_row *stmt)
{
	PLiSQL_execstate *estate = &inv->estate;
	MemoryContext oldcontext;
	Datum		value;
	bool		isnull;
	Oid			valtype;
	int32		valtypmod;

	value = exec_eval_expr(estate, stmt->expr, &isnull, &valtype, &valtypmod);

	oldcontext = MemoryContextSwitchTo(inv->yieldcxt);

	if (!estate->retistuple)
	{
		/* scalar element: coerce once to the declared element type */
		if (!isnull)
			value = exec_cast_value(estate, value, &isnull,
									valtype, valtypmod,
									estate->fn_rettype, inv->elemtypmod);
		inv->retbyval = estate->func->fn_retbyval;
		inv->rettyplen = estate->func->fn_rettyplen;
		if (!isnull && !inv->retbyval)
			value = datumCopy(value, false, inv->rettyplen);
		inv->retval = value;
		inv->retisnull = isnull;
	}
	else
	{
		/* composite element: build a matching heap tuple */
		if (!isnull)
		{
			HeapTupleData tmptup;
			TupleDesc	valuedesc;
			HeapTuple	tuple;
			TupleConversionMap *map;
			int			natts = inv->rettupdesc->natts;
			Datum	   *values;
			bool	   *nulls;

			if (!type_is_rowtype(valtype))
				ereport(ERROR,
						(errcode(ERRCODE_DATATYPE_MISMATCH),
						 errmsg("cannot return non-composite value from pipelined function returning composite type")));

			valuedesc = deconstruct_composite_datum(value, &tmptup);
			map = convert_tuples_by_position(valuedesc, inv->rettupdesc,
											  "PIPE ROW value has the wrong row type");

			/*
			 * Rebuild the tuple from its fields against the expected row
			 * type.  heap_form_tuple produces a fully initialized header
			 * (type OID / typmod from inv->rettupdesc) and clean payload,
			 * independent of the source datum's header state.
			 */
			if (map != NULL)
				tuple = execute_attr_map_tuple(&tmptup, map);
			else
			{
				values = (Datum *) palloc(natts * sizeof(Datum));
				nulls = (bool *) palloc(natts * sizeof(bool));
				heap_deform_tuple(&tmptup, valuedesc, values, nulls);
				tuple = heap_form_tuple(inv->rettupdesc, values, nulls);
				pfree(values);
				pfree(nulls);
			}
			HeapTupleHeaderSetDatumLength(tuple->t_data, tuple->t_len);
			HeapTupleHeaderSetTypeId(tuple->t_data, estate->fn_rettype);
			HeapTupleHeaderSetTypMod(tuple->t_data, inv->rettupdesc->tdtypmod);
			if (map != NULL)
				free_conversion_map(map);
			ReleaseTupleDesc(valuedesc);

			inv->retval = PointerGetDatum(tuple->t_data);
			inv->retisnull = false;
		}
		else
		{
			inv->retval = (Datum) 0;
			inv->retisnull = true;
		}
		inv->retbyval = false;
		inv->rettyplen = -1;
	}

	MemoryContextSwitchTo(oldcontext);
	exec_eval_cleanup(estate);
}

/*
 * Reparent or copy the variable values the suspended invocation still
 * points at into inv->mcxt, which lives until the invocation is released.
 *
 * exec_assign_value transfers ownership of by-reference values via
 * datumTransfer() into CurrentMemoryContext, and SPI leaves the current
 * context in procCxt after every query (_SPI_end_call does not restore
 * the caller's context).  plisql_call_handler SPI_finish()es at the end
 * of each call, destroying procCxt, so anything parked there must be
 * migrated before the executor gets control back.  Expanded objects are
 * reparented; plain varlena values are copied and the source (still
 * valid at this point) is freed.
 */
static void
pipe_migrate_values(PipeInvocation *inv)
{
	PLiSQL_execstate *estate = &inv->estate;
	MemoryContext oldcontext;
	int			i;

	oldcontext = MemoryContextSwitchTo(inv->mcxt);

	for (i = 0; i < estate->ndatums; i++)
	{
		PLiSQL_datum *d = estate->datums[i];

		if (d->dtype == PLISQL_DTYPE_VAR || d->dtype == PLISQL_DTYPE_PROMISE)
		{
			PLiSQL_var *var = (PLiSQL_var *) d;

			if (var->freeval && !var->isnull &&
				!var->datatype->typbyval)
			{
				Datum		newvalue;

				newvalue = datumTransfer(var->value, false,
										 var->datatype->typlen);
				if (newvalue != var->value)
				{
					pfree(DatumGetPointer(var->value));
					var->value = newvalue;
				}
			}
		}
		else if (d->dtype == PLISQL_DTYPE_REC)
		{
			PLiSQL_rec *rec = (PLiSQL_rec *) d;

			if (rec->erh != NULL &&
				rec->erh->hdr.eoh_context != inv->mcxt)
				TransferExpandedObject(EOHPGetRWDatum(&rec->erh->hdr),
									   inv->mcxt);
		}
	}

	MemoryContextSwitchTo(oldcontext);
}
/* --------------------------------------------------------------------------
 * CASE selection (evaluated once when the CASE frame is pushed)
 * --------------------------------------------------------------------------
 */

static void
pipe_setup_case(PipeInvocation *inv, PLiSQL_stmt_case *stmt)
{
	PLiSQL_execstate *estate = &inv->estate;
	PLiSQL_var *t_var;
	ListCell   *l;
	List	   *branch = NIL;
	bool		isnull = false;

	t_var = NULL;
	if (stmt->t_expr != NULL)
	{
		Datum		t_val;
		Oid			t_typoid;
		int32		t_typmod;

		t_val = exec_eval_expr(estate, stmt->t_expr,
							   &isnull, &t_typoid, &t_typmod);

		t_var = (PLiSQL_var *) plisql_get_datum(estate,
												estate->datums[stmt->t_varno]);

		/*
		 * When expected datatype is different from real, change it (same
		 * reasoning as exec_stmt_case: this modifies the execution copy).
		 */
		if (t_var->datatype->typoid != t_typoid ||
			t_var->datatype->atttypmod != t_typmod)
		{
			MemoryContext oldctx = NULL;

			if (OidIsValid(t_var->pkgoid))
				oldctx = MemoryContextSwitchTo(plisql_get_relevantContext(t_var->pkgoid,
																		  CurrentMemoryContext));

			t_var->datatype = plisql_build_datatype(t_typoid,
													t_typmod,
													estate->func->fn_input_collation,
													NULL);
			if (oldctx != NULL)
				MemoryContextSwitchTo(oldctx);
		}

		exec_assign_value(estate,
						  (PLiSQL_datum *) t_var,
						  t_val,
						  isnull,
						  t_typoid,
						  t_typmod);

		exec_eval_cleanup(estate);
	}

	/* Search for a successful WHEN clause. */
	foreach(l, stmt->case_when_list)
	{
		PLiSQL_case_when *cwt = (PLiSQL_case_when *) lfirst(l);
		bool		value;

		value = exec_eval_boolean(estate, cwt->expr, &isnull);
		exec_eval_cleanup(estate);
		if (!isnull && value)
		{
			branch = cwt->stmts;
			break;
		}
	}

	/* discard the temp variable's value, as exec_stmt_case does */
	if (t_var != NULL)
		assign_simple_var(estate, t_var, (Datum) 0, true, false);

	if (branch == NIL)
	{
		if (!stmt->have_else)
			ereport(ERROR,
					(errcode(ERRCODE_CASE_NOT_FOUND),
					 errmsg("case not found"),
					 errhint("CASE statement is missing ELSE part.")));
		branch = stmt->else_stmts;
	}

	pipe_push_frame(inv, PIPE_FRAME_CASE, (PLiSQL_stmt *) stmt,
					NULL, branch);
}

/*
 * pipe_expr_cache_reset
 *
 * The compiled function's simple-expression cache (expr_simple_state) is
 * built with ExecInitExprWithParams over the *creating invocation's*
 * ParamListInfo, whose hook arguments point back at that invocation's
 * estate.  Regular calls never notice because a materialized SRF is
 * invoked exactly once per statement, but a value-per-call pipelined
 * function is resumed by many invocations inside one transaction, so a
 * later invocation would evaluate expressions through a dead estate.
 * Each new invocation therefore invalidates the cache once, and the
 * expressions are re-prepared lazily against the current estate.
 */
static void
pipe_expr_cache_reset(PLiSQL_expr *expr, void *context)
{
	if (expr == NULL)
		return;
	expr->expr_simple_state = NULL;
	expr->expr_simple_lxid = InvalidLocalTransactionId;
}

/* --------------------------------------------------------------------------
 * The resumable interpreter
 * --------------------------------------------------------------------------
 */

typedef enum
{
	PIPE_STEP_YIELD,			/* a row is ready in inv->retval */
	PIPE_STEP_DONE,				/* stream finished */
} PipeStep;

static PipeStep
pipe_resume(PipeInvocation *inv)
{
	PLiSQL_execstate *estate = &inv->estate;

	if (inv->done)
		return PIPE_STEP_DONE;

	if (!inv->started)
	{
		inv->started = true;
		pipe_push_frame(inv, PIPE_FRAME_BLOCK,
						(PLiSQL_stmt *) inv->func->action,
						inv->func->action->label,
						inv->func->action->body);
		/* initialize variables declared in the top-level block */
		estate->err_text = gettext_noop("during initialization of execution state");
		plisql_exec_block_init(estate, inv->func->action);
		estate->err_text = NULL;
	}

	while (list_length(inv->frames) > 0)
	{
		PipeFrame  *frame = (PipeFrame *) llast(inv->frames);
		int			nstmts = list_length(frame->body);
		bool		rewound = false;

		while (frame->pc < nstmts)
		{
			PLiSQL_stmt *stmt = (PLiSQL_stmt *) list_nth(frame->body,
														 frame->pc);
			int			rc = PLISQL_RC_OK;

			frame->pc++;
			estate->err_stmt = stmt;

			if (*plisql_plugin_ptr && (*plisql_plugin_ptr)->stmt_beg)
				((*plisql_plugin_ptr)->stmt_beg) (estate, stmt);

			CHECK_FOR_INTERRUPTS();

			switch (stmt->cmd_type)
			{
				case PLISQL_STMT_BLOCK:
					{
						PLiSQL_stmt_block *block = (PLiSQL_stmt_block *) stmt;

						pipe_push_frame(inv, PIPE_FRAME_BLOCK, stmt,
										block->label, block->body);
						plisql_exec_block_init(estate, block);
					}
					rewound = true;
					break;

				case PLISQL_STMT_IF:
					{
						PLiSQL_stmt_if *if_stmt = (PLiSQL_stmt_if *) stmt;
						ListCell   *lc;
						List	   *branch = NIL;

						/* THEN branch */
						{
							bool		value;
							bool		isnull;

							value = exec_eval_boolean(estate, if_stmt->cond,
													  &isnull);
							exec_eval_cleanup(estate);
							if (!isnull && value)
								branch = if_stmt->then_body;
						}

						/* ELSIF branches */
						if (branch == NIL)
						{
							foreach(lc, if_stmt->elsif_list)
							{
								PLiSQL_if_elsif *elsif =
									(PLiSQL_if_elsif *) lfirst(lc);
								bool		value;
								bool		isnull;

								value = exec_eval_boolean(estate, elsif->cond,
														  &isnull);
								exec_eval_cleanup(estate);
								if (!isnull && value)
								{
									branch = elsif->stmts;
									break;
								}
							}
						}

						/* ELSE branch */
						if (branch == NIL)
							branch = if_stmt->else_body;

						if (branch != NIL)
							pipe_push_frame(inv, PIPE_FRAME_IF, stmt,
											NULL, branch);
					}
					rewound = true;
					break;

				case PLISQL_STMT_CASE:
					pipe_setup_case(inv, (PLiSQL_stmt_case *) stmt);
					rewound = true;
					break;

				case PLISQL_STMT_LOOP:
					{
						PLiSQL_stmt_loop *loop_stmt = (PLiSQL_stmt_loop *) stmt;

						pipe_push_frame(inv, PIPE_FRAME_LOOP, stmt,
										loop_stmt->label, loop_stmt->body);
					}
					rewound = true;
					break;

				case PLISQL_STMT_WHILE:
					{
						PLiSQL_stmt_while *while_stmt =
							(PLiSQL_stmt_while *) stmt;
						bool		value;
						bool		isnull;

						value = exec_eval_boolean(estate, while_stmt->cond,
												  &isnull);
						exec_eval_cleanup(estate);
						if (!isnull && value)
							pipe_push_frame(inv, PIPE_FRAME_WHILE, stmt,
											while_stmt->label,
											while_stmt->body);
					}
					rewound = true;
					break;


				case PLISQL_STMT_FORI:
					{
						PLiSQL_stmt_fori *stmt_i = (PLiSQL_stmt_fori *) stmt;
						PipeFrame  *fframe;
						bool		isnull = false;
						int32		lower;
						int32		upper;
						int32		step = 1;

						lower = exec_eval_integer(estate, stmt_i->lower,
												  &isnull);
						if (!isnull)
							upper = exec_eval_integer(estate, stmt_i->upper,
													  &isnull);
						if (isnull)
						{
							/* NULL bound: body never runs */
							exec_eval_cleanup(estate);
							continue;
						}
						if (stmt_i->step != NULL)
						{
							step = exec_eval_integer(estate, stmt_i->step,
													 &isnull);
							if (isnull)
							{
								exec_eval_cleanup(estate);
								continue;
							}
							if (step <= 0)
								ereport(ERROR,
										(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
										 errmsg("loop step must be positive")));
						}
						exec_eval_cleanup(estate);

						fframe = pipe_push_frame(inv, PIPE_FRAME_FORI, stmt,
												 stmt_i->label, stmt_i->body);
						fframe->fori_reverse = (stmt_i->reverse != 0);
						fframe->fori_lower = lower;
						fframe->fori_upper = upper;
						fframe->fori_step = step;
						fframe->fori_value = fframe->fori_reverse ? upper : lower;
						if (fframe->fori_reverse ?
							(fframe->fori_value < lower) :
							(fframe->fori_value > upper))
						{
							/* zero iterations: drop the frame at once */
							exec_set_found(estate, false);
							inv->frames = list_delete_ptr(inv->frames, fframe);
						}
						else
						{
							PLiSQL_var *lvar;

							fframe->loop_found = true;

							/* assign the invocation's copy of the datum,
							 * exactly as exec_stmt_fori does */
							lvar = (PLiSQL_var *)
								plisql_get_datum(estate,
												 estate->datums[stmt_i->var->dno]);
							assign_simple_var(estate, lvar,
											  Int32GetDatum(fframe->fori_value),
											  false, false);
						}
					}
					rewound = true;
					break;

				case PLISQL_STMT_FORS:
					pipe_setup_fors(inv, (PLiSQL_stmt_fors *) stmt);
					rewound = true;
					break;

				case PLISQL_STMT_FORC:
					pipe_setup_forc(inv, (PLiSQL_stmt_forc *) stmt);
					rewound = true;
					break;

				case PLISQL_STMT_PIPE_ROW:
					pipe_do_yield(inv, (PLiSQL_stmt_pipe_row *) stmt);
					estate->err_stmt = NULL;
					return PIPE_STEP_YIELD;

				case PLISQL_STMT_ASSIGN:
					rc = exec_stmt_assign(estate, (PLiSQL_stmt_assign *) stmt);
					break;

				case PLISQL_STMT_PERFORM:
					rc = exec_stmt_perform(estate, (PLiSQL_stmt_perform *) stmt);
					break;

				case PLISQL_STMT_CALL:
					rc = exec_stmt_call(estate, (PLiSQL_stmt_call *) stmt);
					break;

				case PLISQL_STMT_GETDIAG:
					rc = exec_stmt_getdiag(estate, (PLiSQL_stmt_getdiag *) stmt);
					break;

				case PLISQL_STMT_RAISE:
					rc = exec_stmt_raise(estate, (PLiSQL_stmt_raise *) stmt);
					break;

				case PLISQL_STMT_ASSERT:
					rc = exec_stmt_assert(estate, (PLiSQL_stmt_assert *) stmt);
					break;

				case PLISQL_STMT_EXECSQL:
					rc = exec_stmt_execsql(estate, (PLiSQL_stmt_execsql *) stmt);
					break;

				case PLISQL_STMT_DYNEXECUTE:
					rc = exec_stmt_dynexecute(estate,
											  (PLiSQL_stmt_dynexecute *) stmt);
					break;

				case PLISQL_STMT_OPEN:
					rc = exec_stmt_open(estate, (PLiSQL_stmt_open *) stmt);
					break;

				case PLISQL_STMT_FETCH:
					rc = exec_stmt_fetch(estate, (PLiSQL_stmt_fetch *) stmt);
					break;

				case PLISQL_STMT_CLOSE:
					rc = exec_stmt_close(estate, (PLiSQL_stmt_close *) stmt);
					break;

				case PLISQL_STMT_EXIT:
					rc = exec_stmt_exit(estate, (PLiSQL_stmt_exit *) stmt);
					break;

				case PLISQL_STMT_RETURN:
					rc = exec_stmt_return(estate, (PLiSQL_stmt_return *) stmt);
					break;

				case PLISQL_STMT_COMMIT:
					rc = exec_stmt_commit(estate, (PLiSQL_stmt_commit *) stmt);
					break;

				case PLISQL_STMT_ROLLBACK:
					rc = exec_stmt_rollback(estate, (PLiSQL_stmt_rollback *) stmt);
					break;

				default:
					ereport(ERROR,
							(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
							 errmsg("%s is not supported in a pipelined function",
									plisql_stmt_typename(stmt))));
					rc = PLISQL_RC_OK;	/* not reached */
					break;
			}

			/*
			 * A frame-pushing statement has already broken out of the
			 * switch with rc unset; re-enter the outer loop so the machine
			 * resumes at the new innermost frame.
			 */
			if (rewound)
			{
				estate->err_stmt = NULL;
				break;
			}

			if (*plisql_plugin_ptr && (*plisql_plugin_ptr)->stmt_end)
				((*plisql_plugin_ptr)->stmt_end) (estate, stmt);

			if (rc == PLISQL_RC_RETURN)
			{
				estate->err_stmt = NULL;
				inv->done = true;
				return PIPE_STEP_DONE;
			}
			if (rc == PLISQL_RC_EXIT || rc == PLISQL_RC_CONTINUE)
			{
				pipe_handle_exit(inv, rc);
				rewound = true; /* re-enter the outer loop with the new stack */
				break;
			}
			Assert(rc == PLISQL_RC_OK);
			estate->err_stmt = NULL;
		}

		/*
		 * Body exhausted (or EXIT/CONTINUE rewound the stack): apply the
		 * innermost frame's end-of-iteration logic; pop when finished.
		 */
		if (rewound)
			continue;

		if (frame->pc >= list_length(frame->body))
		{
			if (!pipe_frame_iteration(inv, frame))
			{
				/*
				 * The finished frame is not necessarily the innermost one:
				 * its last statement may have pushed a frame that is still
				 * running.  Remove exactly this frame.
				 */
				inv->frames = list_delete_ptr(inv->frames, frame);
				if (frame->kind == PIPE_FRAME_FORC && frame->curvar_was_null)
				{
					PLiSQL_var *curvar =
						(PLiSQL_var *) plisql_get_datum(estate,
														estate->datums[frame->curvarno]);

					assign_simple_var(estate, curvar, (Datum) 0, true, false);
				}
			}
		}
	}

	/* reached the end of the function without RETURN */
	ereport(ERROR,
			(errcode(ERRCODE_S_R_E_FUNCTION_EXECUTED_NO_RETURN_STATEMENT),
			 errmsg("control reached end of function without RETURN")));
	return PIPE_STEP_DONE;		/* not reached */
}

/* --------------------------------------------------------------------------
 * Release machinery
 * --------------------------------------------------------------------------
 */

static void
pipe_owner_release(Datum res)
{
	PipeInvocation *inv = (PipeInvocation *) DatumGetPointer(res);

	/* ResourceOwner has already removed this item from its array. */
	inv->resowner = NULL;
	pipe_release_invocation(inv, false);
}

static void
pipe_shutdown_cb(Datum arg)
{
	pipe_release_invocation((PipeInvocation *) DatumGetPointer(arg), true);
}

static void
pipe_reset_cb(void *arg)
{
	pipe_release_invocation((PipeInvocation *) arg, false);
}

/*
 * Idempotent, error-free release of an invocation.  close_portal is only
 * true on normal paths (inside a call, or the executor is tearing down
 * normally); on the abort path the portal is released by the
 * ResourceOwner itself and must not be touched here, and neither may the
 * eval_econtext, which dies with the shared simple-expression EState.
 */
static void
pipe_release_invocation(PipeInvocation *inv, bool close_portal)
{
	if (inv->released)
		return;
	inv->released = true;

	/* Forget the owner tracking so a later release cannot see us again. */
	if (inv->resowner != NULL)
	{
		ResourceOwnerForget(inv->resowner, PointerGetDatum(inv),
							&pipe_invocation_resdesc);
		inv->resowner = NULL;
	}

	/* Close every suspended query-FOR portal on normal paths only. */
	if (close_portal)
	{
		ListCell   *lc;

		foreach(lc, inv->frames)
			pipe_close_frame_portal((PipeFrame *) lfirst(lc));
	}

	/* Drop the persistent execution state's expression context.  Only
	 * safe on normal paths; guarded by the same flag as the portal. */
	if (close_portal && inv->estate.eval_econtext != NULL)
		plisql_destroy_econtext(&inv->estate);

	/* release the compiled function reference */
	inv->func->use_count--;
	inv->func->cur_estate = NULL;
}

static const ResourceOwnerDesc pipe_invocation_resdesc = {
	.name = "pipelined function invocation",
	.release_phase = RESOURCE_RELEASE_BEFORE_LOCKS,
	.release_priority = RELEASE_PRIO_LAST,
	.ReleaseResource = pipe_owner_release,
	.DebugPrint = NULL,
};

/* --------------------------------------------------------------------------
 * SRF driver
 * --------------------------------------------------------------------------
 */

Datum
plisql_exec_pipelined_function(PLiSQL_function * func, FunctionCallInfo fcinfo)
{
	ReturnSetInfo *rsi = (ReturnSetInfo *) fcinfo->resultinfo;
	PipeInvocation *inv;
	ExprContext_CB *cb;
	MemoryContext oldcontext;
	PipeStep	step;

	/* Check caller can handle a value-per-call set */
	if (!rsi || !IsA(rsi, ReturnSetInfo))
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("set-valued function called in context that cannot accept a set")));
	if (!(rsi->allowedModes & SFRM_ValuePerCall))
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("value-per-call mode required, but it is not allowed in this context")));
	if (rsi->econtext == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("pipelined function called in context without an expression context")));
	rsi->returnMode = SFRM_ValuePerCall;

	/*
	 * Find this query's invocation, if any.  We must NOT use
	 * fcinfo->flinfo->fn_extra for this: plisql_compile caches the compiled
	 * PLiSQL_function there, and overwriting it makes the next recompile
	 * mistake our state for a function struct.  Instead, anchor the state in
	 * the ExprContext callback list, which lives in the same query-lifespan
	 * context as the invocation itself, so a stale entry cannot outlive its
	 * query.
	 */
	inv = NULL;
	for (cb = rsi->econtext->ecxt_callbacks; cb != NULL; cb = cb->next)
	{
		if (cb->function == pipe_shutdown_cb)
		{
			inv = (PipeInvocation *) DatumGetPointer(cb->arg);
			break;
		}
	}

	/* A stale invocation from a previous execution of the same plan is
	 * unusable: its multi-call context is gone. */
	if (inv != NULL &&
		inv->mcxt != rsi->econtext->ecxt_per_query_memory)
		inv = NULL;


	if (inv == NULL)
	{
		oldcontext = MemoryContextSwitchTo(rsi->econtext->ecxt_per_query_memory);

		inv = (PipeInvocation *) palloc0_object(PipeInvocation);
		inv->mcxt = rsi->econtext->ecxt_per_query_memory;
		/* no prior yield exists yet; palloc0 would leave retisnull false
		 * and the first yield would try to free a NULL "previous value" */
		inv->retisnull = true;
		inv->yieldcxt = AllocSetContextCreate(inv->mcxt,
											  "PLiSQL pipelined yield",
											  ALLOCSET_DEFAULT_SIZES);

		/* hold the compiled function for the whole invocation */
		func->use_count++;
		inv->func = func;

		/*
		 * Invalidate simple-expression states baked by previous
		 * invocations (see pipe_expr_cache_reset).
		 */
		plisql_walk_stmt_exprs((PLiSQL_stmt *) func->action,
							   pipe_expr_cache_reset);

		/*
		 * Set up the persistent execution state inside the multi-call
		 * context so all local datums outlive a single call.
		 */
		plisql_estate_setup(&inv->estate, func, rsi, NULL, NULL);
		inv->estate.atomic = true;

		/* Make local execution copies of all the datums */
		copy_plisql_datums(&inv->estate, func);

		/* element typmod inherited from the collection declaration */
		inv->elemtypmod = -1;
		if (OidIsValid(func->fn_collectiontype))
		{
			Oid			elemOid;
			Oid			collation;

			if (get_oracle_collection_element(func->fn_collectiontype,
											  &elemOid, &inv->elemtypmod,
											  &collation))
				Assert(elemOid == func->fn_rettype);
		}

		/* expected composite tupdesc, if the element type is composite */
		if (func->fn_retistuple)
		{
			Oid			typoid;
			TupleDesc	tupdesc;

			if (get_call_result_type(fcinfo, &typoid, &tupdesc)
				!= TYPEFUNC_COMPOSITE)
				ereport(ERROR,
						(errcode(ERRCODE_DATATYPE_MISMATCH),
						 errmsg("could not determine rowtype of pipelined function result")));
			inv->rettupdesc = tupdesc;
		}

		/* bind call arguments into the persistent datums */
		plisql_bind_call_args(&inv->estate, func, fcinfo);
		exec_set_found(&inv->estate, false);

		/* register the idempotent release hooks */
		inv->mcb.func = pipe_reset_cb;
		inv->mcb.arg = inv;
		MemoryContextRegisterResetCallback(inv->mcxt, &inv->mcb);

		RegisterExprContextCallback(rsi->econtext, pipe_shutdown_cb,
									PointerGetDatum(inv));

		inv->resowner = CurrentResourceOwner;
		ResourceOwnerEnlarge(inv->resowner);
		ResourceOwnerRemember(inv->resowner, PointerGetDatum(inv),
							  &pipe_invocation_resdesc);

		MemoryContextSwitchTo(oldcontext);
	}

	if (inv->done || inv->released)
	{
		rsi->isDone = ExprEndResult;
		return (Datum) 0;
	}

	/*
	 * The previous row was consumed by the executor before this call, so
	 * recycle the per-yield allocation context now (before the machine may
	 * produce the next row into it).
	 */
	MemoryContextReset(inv->yieldcxt);

	/* make the invocation the current estate for error reporting */
	{
		PLiSQL_execstate *save_cur_estate = func->cur_estate;
		MemoryContext resumectx = CurrentMemoryContext;

		func->cur_estate = &inv->estate;

		/*
		 * Run the machine inside the invocation's context: the frame stack
		 * and everything it allocates must survive across calls, while the
		 * executor resets its per-tuple context between rows.
		 */
		MemoryContextSwitchTo(inv->mcxt);

		PG_TRY();
		{
			step = pipe_resume(inv);
		}
		PG_CATCH();
		{
			/*
			 * An error inside a call releases the invocation eagerly so
			 * the compiled function reference is not pinned until abort
			 * cleanup.  The portal is closed here because we are still in
			 * error recovery (same transaction); after PG_RE_THROW only
			 * the owner path runs, and it never touches the portal.
			 */
			MemoryContextSwitchTo(resumectx);
			func->cur_estate = save_cur_estate;
			pipe_release_invocation(inv, true);
			PG_RE_THROW();
		}
		PG_END_TRY();

		MemoryContextSwitchTo(resumectx);
		func->cur_estate = save_cur_estate;
	}

	if (step == PIPE_STEP_YIELD)
	{
		/* The executor consumes each returned row synchronously before
		 * issuing the next call, so inv->retval is safe to hand out as
		 * is.  Live variable values are a different matter: they may be
		 * parked in this call's SPI procedure context, which dies at
		 * SPI_finish, so migrate them now (see pipe_migrate_values). */
		pipe_migrate_values(inv);
		rsi->isDone = ExprMultipleResult;
		fcinfo->isnull = inv->retisnull;
		return inv->retval;
	}

	/* bare RETURN or normal end: stream finished */
	pipe_release_invocation(inv, true);
	rsi->isDone = ExprEndResult;
	return (Datum) 0;
}
