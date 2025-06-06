/*-------------------------------------------------------------------------
 *
 * pl_funcs.c		- Misc functions for the PL/iSQL
 *			  procedural language
 *
 * Portions Copyright (c) 2024-2025, IvorySQL Global Development Team
 * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_funcs.c
 *
 * add the file for requirement "SQL PARSER"
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "plisql.h"
#include "pl_subproc_function.h"
#include "pl_package.h"
#include "utils/memutils.h"

/* ----------
 * Local variables for namespace handling
 *
 * The namespace structure actually forms a tree, of which only one linear
 * list or "chain" (from the youngest item to the root) is accessible from
 * any one plisql statement.  During initial parsing of a function, ns_top
 * points to the youngest item accessible from the block currently being
 * parsed.  We store the entire tree, however, since at runtime we will need
 * to access the chain that's relevant to any one statement.
 *
 * Block boundaries in the namespace chain are marked by PLISQL_NSTYPE_LABEL
 * items.
 * ----------
 */
static PLiSQL_nsitem *ns_top = NULL;


/* ----------
 * plisql_ns_init			Initialize namespace processing for a new function
 * ----------
 */
void
plisql_ns_init(void)
{
	ns_top = NULL;
}

void
plisql_set_ns(PLiSQL_nsitem *cur)
{
	ns_top = cur;
}

/* ----------
 * plisql_ns_push			Create a new namespace level
 * ----------
 */
void
plisql_ns_push(const char *label, PLiSQL_label_type label_type)
{
	if (label == NULL)
		label = "";
	plisql_ns_additem(PLISQL_NSTYPE_LABEL, (int) label_type, label);
}


/* ----------
 * plisql_ns_pop			Pop entries back to (and including) the last label
 * ----------
 */
void
plisql_ns_pop(void)
{
	Assert(ns_top != NULL);
	while (ns_top->itemtype != PLISQL_NSTYPE_LABEL)
		ns_top = ns_top->prev;
	ns_top = ns_top->prev;
}


/* ----------
 * plisql_ns_top			Fetch the current namespace chain end
 * ----------
 */
PLiSQL_nsitem *
plisql_ns_top(void)
{
	return ns_top;
}


/* ----------
 * plisql_ns_additem		Add an item to the current namespace chain
 * ----------
 */
void
plisql_ns_additem(PLiSQL_nsitem_type itemtype, int itemno, const char *name)
{
	PLiSQL_nsitem *nse;

	Assert(name != NULL);
	/* first item added must be a label */
	Assert(ns_top != NULL || itemtype == PLISQL_NSTYPE_LABEL);

	nse = palloc(offsetof(PLiSQL_nsitem, name) + strlen(name) + 1);
	nse->itemtype = itemtype;
	nse->itemno = itemno;
	nse->subprocfunc = NIL;
	nse->prev = ns_top;
	strcpy(nse->name, name);
	ns_top = nse;
}


/* ----------
 * plisql_ns_lookup		Lookup an identifier in the given namespace chain
 *
 * Note that this only searches for variables, not labels.
 *
 * If localmode is true, only the topmost block level is searched.
 *
 * name1 must be non-NULL.  Pass NULL for name2 and/or name3 if parsing a name
 * with fewer than three components.
 *
 * If names_used isn't NULL, *names_used receives the number of names
 * matched: 0 if no match, 1 if name1 matched an unqualified variable name,
 * 2 if name1 and name2 matched a block label + variable name.
 *
 * Note that name3 is never directly matched to anything.  However, if it
 * isn't NULL, we will disregard qualified matches to scalar variables.
 * Similarly, if name2 isn't NULL, we disregard unqualified matches to
 * scalar variables.
 * ----------
 */
PLiSQL_nsitem *
plisql_ns_lookup(PLiSQL_nsitem *ns_cur, bool localmode,
				  const char *name1, const char *name2, const char *name3,
				  int *names_used)
{
	/* Outer loop iterates once per block level in the namespace chain */
	while (ns_cur != NULL)
	{
		PLiSQL_nsitem *nsitem;

		/* Check this level for unqualified match to variable name */
		for (nsitem = ns_cur;
			 nsitem->itemtype != PLISQL_NSTYPE_LABEL;
			 nsitem = nsitem->prev)
		{
			if (strcmp(nsitem->name, name1) == 0)
			{
				if (name2 == NULL ||
					nsitem->itemtype != PLISQL_NSTYPE_VAR)
				{
					if (names_used)
						*names_used = 1;
					return nsitem;
				}
			}
		}

		/* Check this level for qualified match to variable name */
		if (name2 != NULL &&
			strcmp(nsitem->name, name1) == 0)
		{
			for (nsitem = ns_cur;
				 nsitem->itemtype != PLISQL_NSTYPE_LABEL;
				 nsitem = nsitem->prev)
			{
				if (strcmp(nsitem->name, name2) == 0)
				{
					if (name3 == NULL ||
						nsitem->itemtype != PLISQL_NSTYPE_VAR)
					{
						if (names_used)
							*names_used = 2;
						return nsitem;
					}
				}
			}
		}

		if (localmode)
			break;				/* do not look into upper levels */

		ns_cur = nsitem->prev;
	}

	/* This is just to suppress possibly-uninitialized-variable warnings */
	if (names_used)
		*names_used = 0;
	return NULL;				/* No match found */
}


/* ----------
 * plisql_ns_lookup_label		Lookup a label in the given namespace chain
 * ----------
 */
PLiSQL_nsitem *
plisql_ns_lookup_label(PLiSQL_nsitem *ns_cur, const char *name)
{
	while (ns_cur != NULL)
	{
		if (ns_cur->itemtype == PLISQL_NSTYPE_LABEL &&
			strcmp(ns_cur->name, name) == 0)
			return ns_cur;
		ns_cur = ns_cur->prev;
	}

	return NULL;				/* label not found */
}


/* ----------
 * plisql_ns_find_nearest_loop		Find innermost loop label in namespace chain
 * ----------
 */
PLiSQL_nsitem *
plisql_ns_find_nearest_loop(PLiSQL_nsitem *ns_cur)
{
	while (ns_cur != NULL)
	{
		if (ns_cur->itemtype == PLISQL_NSTYPE_LABEL &&
			ns_cur->itemno == PLISQL_LABEL_LOOP)
			return ns_cur;
		ns_cur = ns_cur->prev;
	}

	return NULL;				/* no loop found */
}


/*
 * Statement type as a string, for use in error messages etc.
 */
const char *
plisql_stmt_typename(PLiSQL_stmt *stmt)
{
	switch (stmt->cmd_type)
	{
		case PLISQL_STMT_BLOCK:
			return _("statement block");
		case PLISQL_STMT_ASSIGN:
			return _("assignment");
		case PLISQL_STMT_IF:
			return "IF";
		case PLISQL_STMT_CASE:
			return "CASE";
		case PLISQL_STMT_LOOP:
			return "LOOP";
		case PLISQL_STMT_WHILE:
			return "WHILE";
		case PLISQL_STMT_FORI:
			return _("FOR with integer loop variable");
		case PLISQL_STMT_FORS:
			return _("FOR over SELECT rows");
		case PLISQL_STMT_FORC:
			return _("FOR over cursor");
		case PLISQL_STMT_FOREACH_A:
			return _("FOREACH over array");
		case PLISQL_STMT_EXIT:
			return ((PLiSQL_stmt_exit *) stmt)->is_exit ? "EXIT" : "CONTINUE";
		case PLISQL_STMT_RETURN:
			return "RETURN";
		case PLISQL_STMT_RETURN_NEXT:
			return "RETURN NEXT";
		case PLISQL_STMT_RETURN_QUERY:
			return "RETURN QUERY";
		case PLISQL_STMT_RAISE:
			return "RAISE";
		case PLISQL_STMT_ASSERT:
			return "ASSERT";
		case PLISQL_STMT_EXECSQL:
			return _("SQL statement");
		case PLISQL_STMT_DYNEXECUTE:
			return "EXECUTE";
		case PLISQL_STMT_DYNFORS:
			return _("FOR over EXECUTE statement");
		case PLISQL_STMT_GETDIAG:
			return ((PLiSQL_stmt_getdiag *) stmt)->is_stacked ?
				"GET STACKED DIAGNOSTICS" : "GET DIAGNOSTICS";
		case PLISQL_STMT_OPEN:
			return "OPEN";
		case PLISQL_STMT_FETCH:
			return ((PLiSQL_stmt_fetch *) stmt)->is_move ? "MOVE" : "FETCH";
		case PLISQL_STMT_CLOSE:
			return "CLOSE";
		case PLISQL_STMT_PERFORM:
			return "PERFORM";
		case PLISQL_STMT_CALL:
			return ((PLiSQL_stmt_call *) stmt)->is_call ? "CALL" : "DO";
		case PLISQL_STMT_COMMIT:
			return "COMMIT";
		case PLISQL_STMT_ROLLBACK:
			return "ROLLBACK";
	}

	return "unknown";
}

/*
 * GET DIAGNOSTICS item name as a string, for use in error messages etc.
 */
const char *
plisql_getdiag_kindname(PLiSQL_getdiag_kind kind)
{
	switch (kind)
	{
		case PLISQL_GETDIAG_ROW_COUNT:
			return "ROW_COUNT";
		case PLISQL_GETDIAG_ROUTINE_OID:
			return "PG_ROUTINE_OID";
		case PLISQL_GETDIAG_CONTEXT:
			return "PG_CONTEXT";
		case PLISQL_GETDIAG_ERROR_CONTEXT:
			return "PG_EXCEPTION_CONTEXT";
		case PLISQL_GETDIAG_ERROR_DETAIL:
			return "PG_EXCEPTION_DETAIL";
		case PLISQL_GETDIAG_ERROR_HINT:
			return "PG_EXCEPTION_HINT";
		case PLISQL_GETDIAG_RETURNED_SQLSTATE:
			return "RETURNED_SQLSTATE";
		case PLISQL_GETDIAG_COLUMN_NAME:
			return "COLUMN_NAME";
		case PLISQL_GETDIAG_CONSTRAINT_NAME:
			return "CONSTRAINT_NAME";
		case PLISQL_GETDIAG_DATATYPE_NAME:
			return "PG_DATATYPE_NAME";
		case PLISQL_GETDIAG_MESSAGE_TEXT:
			return "MESSAGE_TEXT";
		case PLISQL_GETDIAG_TABLE_NAME:
			return "TABLE_NAME";
		case PLISQL_GETDIAG_SCHEMA_NAME:
			return "SCHEMA_NAME";
	}

	return "unknown";
}


/**********************************************************************
 * Release memory when a PL/iSQL function is no longer needed
 *
 * The code for recursing through the function tree is really only
 * needed to locate PLiSQL_expr nodes, which may contain references
 * to saved SPI Plans that must be freed.  The function tree itself,
 * along with subsidiary data, is freed in one swoop by freeing the
 * function's permanent memory context.
 **********************************************************************/
static void free_stmt(PLiSQL_stmt *stmt);
static void free_block(PLiSQL_stmt_block *block);
static void free_assign(PLiSQL_stmt_assign *stmt);
static void free_if(PLiSQL_stmt_if *stmt);
static void free_case(PLiSQL_stmt_case *stmt);
static void free_loop(PLiSQL_stmt_loop *stmt);
static void free_while(PLiSQL_stmt_while *stmt);
static void free_fori(PLiSQL_stmt_fori *stmt);
static void free_fors(PLiSQL_stmt_fors *stmt);
static void free_forc(PLiSQL_stmt_forc *stmt);
static void free_foreach_a(PLiSQL_stmt_foreach_a *stmt);
static void free_exit(PLiSQL_stmt_exit *stmt);
static void free_return(PLiSQL_stmt_return *stmt);
static void free_return_next(PLiSQL_stmt_return_next *stmt);
static void free_return_query(PLiSQL_stmt_return_query *stmt);
static void free_raise(PLiSQL_stmt_raise *stmt);
static void free_assert(PLiSQL_stmt_assert *stmt);
static void free_execsql(PLiSQL_stmt_execsql *stmt);
static void free_dynexecute(PLiSQL_stmt_dynexecute *stmt);
static void free_dynfors(PLiSQL_stmt_dynfors *stmt);
static void free_getdiag(PLiSQL_stmt_getdiag *stmt);
static void free_open(PLiSQL_stmt_open *stmt);
static void free_fetch(PLiSQL_stmt_fetch *stmt);
static void free_close(PLiSQL_stmt_close *stmt);
static void free_perform(PLiSQL_stmt_perform *stmt);
static void free_call(PLiSQL_stmt_call *stmt);
static void free_commit(PLiSQL_stmt_commit *stmt);
static void free_rollback(PLiSQL_stmt_rollback *stmt);
static void free_expr(PLiSQL_expr *expr);


static void
free_stmt(PLiSQL_stmt *stmt)
{
	switch (stmt->cmd_type)
	{
		case PLISQL_STMT_BLOCK:
			free_block((PLiSQL_stmt_block *) stmt);
			break;
		case PLISQL_STMT_ASSIGN:
			free_assign((PLiSQL_stmt_assign *) stmt);
			break;
		case PLISQL_STMT_IF:
			free_if((PLiSQL_stmt_if *) stmt);
			break;
		case PLISQL_STMT_CASE:
			free_case((PLiSQL_stmt_case *) stmt);
			break;
		case PLISQL_STMT_LOOP:
			free_loop((PLiSQL_stmt_loop *) stmt);
			break;
		case PLISQL_STMT_WHILE:
			free_while((PLiSQL_stmt_while *) stmt);
			break;
		case PLISQL_STMT_FORI:
			free_fori((PLiSQL_stmt_fori *) stmt);
			break;
		case PLISQL_STMT_FORS:
			free_fors((PLiSQL_stmt_fors *) stmt);
			break;
		case PLISQL_STMT_FORC:
			free_forc((PLiSQL_stmt_forc *) stmt);
			break;
		case PLISQL_STMT_FOREACH_A:
			free_foreach_a((PLiSQL_stmt_foreach_a *) stmt);
			break;
		case PLISQL_STMT_EXIT:
			free_exit((PLiSQL_stmt_exit *) stmt);
			break;
		case PLISQL_STMT_RETURN:
			free_return((PLiSQL_stmt_return *) stmt);
			break;
		case PLISQL_STMT_RETURN_NEXT:
			free_return_next((PLiSQL_stmt_return_next *) stmt);
			break;
		case PLISQL_STMT_RETURN_QUERY:
			free_return_query((PLiSQL_stmt_return_query *) stmt);
			break;
		case PLISQL_STMT_RAISE:
			free_raise((PLiSQL_stmt_raise *) stmt);
			break;
		case PLISQL_STMT_ASSERT:
			free_assert((PLiSQL_stmt_assert *) stmt);
			break;
		case PLISQL_STMT_EXECSQL:
			free_execsql((PLiSQL_stmt_execsql *) stmt);
			break;
		case PLISQL_STMT_DYNEXECUTE:
			free_dynexecute((PLiSQL_stmt_dynexecute *) stmt);
			break;
		case PLISQL_STMT_DYNFORS:
			free_dynfors((PLiSQL_stmt_dynfors *) stmt);
			break;
		case PLISQL_STMT_GETDIAG:
			free_getdiag((PLiSQL_stmt_getdiag *) stmt);
			break;
		case PLISQL_STMT_OPEN:
			free_open((PLiSQL_stmt_open *) stmt);
			break;
		case PLISQL_STMT_FETCH:
			free_fetch((PLiSQL_stmt_fetch *) stmt);
			break;
		case PLISQL_STMT_CLOSE:
			free_close((PLiSQL_stmt_close *) stmt);
			break;
		case PLISQL_STMT_PERFORM:
			free_perform((PLiSQL_stmt_perform *) stmt);
			break;
		case PLISQL_STMT_CALL:
			free_call((PLiSQL_stmt_call *) stmt);
			break;
		case PLISQL_STMT_COMMIT:
			free_commit((PLiSQL_stmt_commit *) stmt);
			break;
		case PLISQL_STMT_ROLLBACK:
			free_rollback((PLiSQL_stmt_rollback *) stmt);
			break;
		default:
			elog(ERROR, "unrecognized cmd_type: %d", stmt->cmd_type);
			break;
	}
}

static void
free_stmts(List *stmts)
{
	ListCell   *s;

	foreach(s, stmts)
	{
		free_stmt((PLiSQL_stmt *) lfirst(s));
	}
}

static void
free_block(PLiSQL_stmt_block *block)
{
	free_stmts(block->body);
	if (block->exceptions)
	{
		ListCell   *e;

		foreach(e, block->exceptions->exc_list)
		{
			PLiSQL_exception *exc = (PLiSQL_exception *) lfirst(e);

			free_stmts(exc->action);
		}
	}
}

static void
free_assign(PLiSQL_stmt_assign *stmt)
{
	free_expr(stmt->expr);
}

static void
free_if(PLiSQL_stmt_if *stmt)
{
	ListCell   *l;

	free_expr(stmt->cond);
	free_stmts(stmt->then_body);
	foreach(l, stmt->elsif_list)
	{
		PLiSQL_if_elsif *elif = (PLiSQL_if_elsif *) lfirst(l);

		free_expr(elif->cond);
		free_stmts(elif->stmts);
	}
	free_stmts(stmt->else_body);
}

static void
free_case(PLiSQL_stmt_case *stmt)
{
	ListCell   *l;

	free_expr(stmt->t_expr);
	foreach(l, stmt->case_when_list)
	{
		PLiSQL_case_when *cwt = (PLiSQL_case_when *) lfirst(l);

		free_expr(cwt->expr);
		free_stmts(cwt->stmts);
	}
	free_stmts(stmt->else_stmts);
}

static void
free_loop(PLiSQL_stmt_loop *stmt)
{
	free_stmts(stmt->body);
}

static void
free_while(PLiSQL_stmt_while *stmt)
{
	free_expr(stmt->cond);
	free_stmts(stmt->body);
}

static void
free_fori(PLiSQL_stmt_fori *stmt)
{
	free_expr(stmt->lower);
	free_expr(stmt->upper);
	free_expr(stmt->step);
	free_stmts(stmt->body);
}

static void
free_fors(PLiSQL_stmt_fors *stmt)
{
	free_stmts(stmt->body);
	free_expr(stmt->query);
}

static void
free_forc(PLiSQL_stmt_forc *stmt)
{
	free_stmts(stmt->body);
	free_expr(stmt->argquery);
}

static void
free_foreach_a(PLiSQL_stmt_foreach_a *stmt)
{
	free_expr(stmt->expr);
	free_stmts(stmt->body);
}

static void
free_open(PLiSQL_stmt_open *stmt)
{
	ListCell   *lc;

	free_expr(stmt->argquery);
	free_expr(stmt->query);
	free_expr(stmt->dynquery);
	foreach(lc, stmt->params)
	{
		free_expr((PLiSQL_expr *) lfirst(lc));
	}
}

static void
free_fetch(PLiSQL_stmt_fetch *stmt)
{
	free_expr(stmt->expr);
}

static void
free_close(PLiSQL_stmt_close *stmt)
{
}

static void
free_perform(PLiSQL_stmt_perform *stmt)
{
	free_expr(stmt->expr);
}

static void
free_call(PLiSQL_stmt_call *stmt)
{
	free_expr(stmt->expr);
}

static void
free_commit(PLiSQL_stmt_commit *stmt)
{
}

static void
free_rollback(PLiSQL_stmt_rollback *stmt)
{
}

static void
free_exit(PLiSQL_stmt_exit *stmt)
{
	free_expr(stmt->cond);
}

static void
free_return(PLiSQL_stmt_return *stmt)
{
	free_expr(stmt->expr);
}

static void
free_return_next(PLiSQL_stmt_return_next *stmt)
{
	free_expr(stmt->expr);
}

static void
free_return_query(PLiSQL_stmt_return_query *stmt)
{
	ListCell   *lc;

	free_expr(stmt->query);
	free_expr(stmt->dynquery);
	foreach(lc, stmt->params)
	{
		free_expr((PLiSQL_expr *) lfirst(lc));
	}
}

static void
free_raise(PLiSQL_stmt_raise *stmt)
{
	ListCell   *lc;

	foreach(lc, stmt->params)
	{
		free_expr((PLiSQL_expr *) lfirst(lc));
	}
	foreach(lc, stmt->options)
	{
		PLiSQL_raise_option *opt = (PLiSQL_raise_option *) lfirst(lc);

		free_expr(opt->expr);
	}
}

static void
free_assert(PLiSQL_stmt_assert *stmt)
{
	free_expr(stmt->cond);
	free_expr(stmt->message);
}

static void
free_execsql(PLiSQL_stmt_execsql *stmt)
{
	free_expr(stmt->sqlstmt);
}

static void
free_dynexecute(PLiSQL_stmt_dynexecute *stmt)
{
	ListCell   *lc;

	free_expr(stmt->query);
	foreach(lc, stmt->params)
	{
		free_expr((PLiSQL_expr *) lfirst(lc));
	}
}

static void
free_dynfors(PLiSQL_stmt_dynfors *stmt)
{
	ListCell   *lc;

	free_stmts(stmt->body);
	free_expr(stmt->query);
	foreach(lc, stmt->params)
	{
		free_expr((PLiSQL_expr *) lfirst(lc));
	}
}

static void
free_getdiag(PLiSQL_stmt_getdiag *stmt)
{
}

static void
free_expr(PLiSQL_expr *expr)
{
	if (expr && expr->plan)
	{
		SPI_freeplan(expr->plan);
		expr->plan = NULL;
	}
}

void
plisql_free_function_memory(PLiSQL_function *func,
							int start_datum, int start_subprocfunc)
{
	int			i;

	/* Better not call this on an in-use function */
	Assert(func->use_count == 0);

	plisql_remove_function_relations(func);

	/* Release plans associated with variable declarations */
	for (i = start_datum; i < func->ndatums; i++)
	{
		PLiSQL_datum *d = func->datums[i];

		switch (d->dtype)
		{
			case PLISQL_DTYPE_VAR:
			case PLISQL_DTYPE_PROMISE:
				{
					PLiSQL_var *var = (PLiSQL_var *) d;

					free_expr(var->default_val);
					free_expr(var->cursor_explicit_expr);
					/* we should close package explicit cursor */
					if (OidIsValid(var->pkgoid) &&
						var->datatype->typoid == REFCURSOROID &&
						plisql_cursor_is_open(var))
						plisql_close_package_cursorvar(var);
				}
				break;
			case PLISQL_DTYPE_ROW:
				break;
			case PLISQL_DTYPE_REC:
				{
					PLiSQL_rec *rec = (PLiSQL_rec *) d;

					free_expr(rec->default_val);
				}
				break;
			case PLISQL_DTYPE_RECFIELD:
				break;
			case PLISQL_DTYPE_PACKAGE_DATUM:
				break;
			default:
				elog(ERROR, "unrecognized data type: %d", d->dtype);
		}
	}
	func->ndatums = 0;

	/* Release plans in statement tree */
	if (func->action)
		free_block(func->action);
	func->action = NULL;

	/* release subproc function */
	for (i = start_subprocfunc; i < func->nsubprocfuncs; i++)
	{
		ListCell *lc;
		PLiSQL_subproc_function *subprocfunc = func->subprocfuncs[i];

		foreach(lc, subprocfunc->arg)
		{
			PLiSQL_function_argitem *argitem = (PLiSQL_function_argitem *) lfirst(lc);

			free_expr(argitem->defexpr);
		}
		if (!subprocfunc->has_poly_argument ||
			subprocfunc->poly_tab == NULL)
		{
			/*
			 * if no action, the lastoutvardno and lastoutinlinefno is invalid
			 * we must not free its context
			 */
			if (subprocfunc->function->action != NULL)
				plisql_free_function_memory(subprocfunc->function, subprocfunc->lastoutvardno,
								subprocfunc->lastoutsubprocfno);
		}
		else
		{
			/* free inline function from  hashtable */
			HASH_SEQ_STATUS status;
			plisql_HashEnt *entry;

			Assert(subprocfunc->poly_tab != NULL);

			/*
			 * if no action, the lastoutvardno and lastoutinlinefno is invalid
			 * we must not free its context
			 */
			if (subprocfunc->function->action != NULL)
			{
				hash_seq_init(&status, subprocfunc->poly_tab);

				while ((entry = (plisql_HashEnt *) hash_seq_search(&status)) != NULL)
				{
					hash_search(subprocfunc->poly_tab, (void *)(&(entry->key)), HASH_REMOVE, NULL);
					plisql_free_function_memory(entry->function, subprocfunc->lastoutvardno, subprocfunc->lastoutsubprocfno);
				}
			}
			hash_destroy(subprocfunc->poly_tab);
		}
	}
	func->nsubprocfuncs = 0;

	/*
	 * And finally, release all memory except the PLiSQL_function struct
	 * itself (which has to be kept around because there may be multiple
	 * fn_extra pointers to it).
	 */
	if (func->fn_cxt &&
		start_datum == 0 && start_subprocfunc == 0)
		MemoryContextDelete(func->fn_cxt);
	func->fn_cxt = NULL;
}


/**********************************************************************
 * Debug functions for analyzing the compiled code
 **********************************************************************/
static int	dump_indent;

static void dump_ind(void);
static void dump_stmt(PLiSQL_stmt *stmt);
static void dump_block(PLiSQL_stmt_block *block);
static void dump_assign(PLiSQL_stmt_assign *stmt);
static void dump_if(PLiSQL_stmt_if *stmt);
static void dump_case(PLiSQL_stmt_case *stmt);
static void dump_loop(PLiSQL_stmt_loop *stmt);
static void dump_while(PLiSQL_stmt_while *stmt);
static void dump_fori(PLiSQL_stmt_fori *stmt);
static void dump_fors(PLiSQL_stmt_fors *stmt);
static void dump_forc(PLiSQL_stmt_forc *stmt);
static void dump_foreach_a(PLiSQL_stmt_foreach_a *stmt);
static void dump_exit(PLiSQL_stmt_exit *stmt);
static void dump_return(PLiSQL_stmt_return *stmt);
static void dump_return_next(PLiSQL_stmt_return_next *stmt);
static void dump_return_query(PLiSQL_stmt_return_query *stmt);
static void dump_raise(PLiSQL_stmt_raise *stmt);
static void dump_assert(PLiSQL_stmt_assert *stmt);
static void dump_execsql(PLiSQL_stmt_execsql *stmt);
static void dump_dynexecute(PLiSQL_stmt_dynexecute *stmt);
static void dump_dynfors(PLiSQL_stmt_dynfors *stmt);
static void dump_getdiag(PLiSQL_stmt_getdiag *stmt);
static void dump_open(PLiSQL_stmt_open *stmt);
static void dump_fetch(PLiSQL_stmt_fetch *stmt);
static void dump_cursor_direction(PLiSQL_stmt_fetch *stmt);
static void dump_close(PLiSQL_stmt_close *stmt);
static void dump_perform(PLiSQL_stmt_perform *stmt);
static void dump_call(PLiSQL_stmt_call *stmt);
static void dump_commit(PLiSQL_stmt_commit *stmt);
static void dump_rollback(PLiSQL_stmt_rollback *stmt);
static void dump_expr(PLiSQL_expr *expr);


static void
dump_ind(void)
{
	int			i;

	for (i = 0; i < dump_indent; i++)
		printf(" ");
}

static void
dump_stmt(PLiSQL_stmt *stmt)
{
	printf("%3d:", stmt->lineno);
	switch (stmt->cmd_type)
	{
		case PLISQL_STMT_BLOCK:
			dump_block((PLiSQL_stmt_block *) stmt);
			break;
		case PLISQL_STMT_ASSIGN:
			dump_assign((PLiSQL_stmt_assign *) stmt);
			break;
		case PLISQL_STMT_IF:
			dump_if((PLiSQL_stmt_if *) stmt);
			break;
		case PLISQL_STMT_CASE:
			dump_case((PLiSQL_stmt_case *) stmt);
			break;
		case PLISQL_STMT_LOOP:
			dump_loop((PLiSQL_stmt_loop *) stmt);
			break;
		case PLISQL_STMT_WHILE:
			dump_while((PLiSQL_stmt_while *) stmt);
			break;
		case PLISQL_STMT_FORI:
			dump_fori((PLiSQL_stmt_fori *) stmt);
			break;
		case PLISQL_STMT_FORS:
			dump_fors((PLiSQL_stmt_fors *) stmt);
			break;
		case PLISQL_STMT_FORC:
			dump_forc((PLiSQL_stmt_forc *) stmt);
			break;
		case PLISQL_STMT_FOREACH_A:
			dump_foreach_a((PLiSQL_stmt_foreach_a *) stmt);
			break;
		case PLISQL_STMT_EXIT:
			dump_exit((PLiSQL_stmt_exit *) stmt);
			break;
		case PLISQL_STMT_RETURN:
			dump_return((PLiSQL_stmt_return *) stmt);
			break;
		case PLISQL_STMT_RETURN_NEXT:
			dump_return_next((PLiSQL_stmt_return_next *) stmt);
			break;
		case PLISQL_STMT_RETURN_QUERY:
			dump_return_query((PLiSQL_stmt_return_query *) stmt);
			break;
		case PLISQL_STMT_RAISE:
			dump_raise((PLiSQL_stmt_raise *) stmt);
			break;
		case PLISQL_STMT_ASSERT:
			dump_assert((PLiSQL_stmt_assert *) stmt);
			break;
		case PLISQL_STMT_EXECSQL:
			dump_execsql((PLiSQL_stmt_execsql *) stmt);
			break;
		case PLISQL_STMT_DYNEXECUTE:
			dump_dynexecute((PLiSQL_stmt_dynexecute *) stmt);
			break;
		case PLISQL_STMT_DYNFORS:
			dump_dynfors((PLiSQL_stmt_dynfors *) stmt);
			break;
		case PLISQL_STMT_GETDIAG:
			dump_getdiag((PLiSQL_stmt_getdiag *) stmt);
			break;
		case PLISQL_STMT_OPEN:
			dump_open((PLiSQL_stmt_open *) stmt);
			break;
		case PLISQL_STMT_FETCH:
			dump_fetch((PLiSQL_stmt_fetch *) stmt);
			break;
		case PLISQL_STMT_CLOSE:
			dump_close((PLiSQL_stmt_close *) stmt);
			break;
		case PLISQL_STMT_PERFORM:
			dump_perform((PLiSQL_stmt_perform *) stmt);
			break;
		case PLISQL_STMT_CALL:
			dump_call((PLiSQL_stmt_call *) stmt);
			break;
		case PLISQL_STMT_COMMIT:
			dump_commit((PLiSQL_stmt_commit *) stmt);
			break;
		case PLISQL_STMT_ROLLBACK:
			dump_rollback((PLiSQL_stmt_rollback *) stmt);
			break;
		default:
			elog(ERROR, "unrecognized cmd_type: %d", stmt->cmd_type);
			break;
	}
}

static void
dump_stmts(List *stmts)
{
	ListCell   *s;

	dump_indent += 2;
	foreach(s, stmts)
		dump_stmt((PLiSQL_stmt *) lfirst(s));
	dump_indent -= 2;
}

static void
dump_block(PLiSQL_stmt_block *block)
{
	char	   *name;

	if (block->label == NULL)
		name = "*unnamed*";
	else
		name = block->label;

	dump_ind();
	printf("BLOCK <<%s>>\n", name);

	dump_stmts(block->body);

	if (block->exceptions)
	{
		ListCell   *e;

		foreach(e, block->exceptions->exc_list)
		{
			PLiSQL_exception *exc = (PLiSQL_exception *) lfirst(e);
			PLiSQL_condition *cond;

			dump_ind();
			printf("    EXCEPTION WHEN ");
			for (cond = exc->conditions; cond; cond = cond->next)
			{
				if (cond != exc->conditions)
					printf(" OR ");
				printf("%s", cond->condname);
			}
			printf(" THEN\n");
			dump_stmts(exc->action);
		}
	}

	dump_ind();
	printf("    END -- %s\n", name);
}

static void
dump_assign(PLiSQL_stmt_assign *stmt)
{
	dump_ind();
	printf("ASSIGN var %d := ", stmt->varno);
	dump_expr(stmt->expr);
	printf("\n");
}

static void
dump_if(PLiSQL_stmt_if *stmt)
{
	ListCell   *l;

	dump_ind();
	printf("IF ");
	dump_expr(stmt->cond);
	printf(" THEN\n");
	dump_stmts(stmt->then_body);
	foreach(l, stmt->elsif_list)
	{
		PLiSQL_if_elsif *elif = (PLiSQL_if_elsif *) lfirst(l);

		dump_ind();
		printf("    ELSIF ");
		dump_expr(elif->cond);
		printf(" THEN\n");
		dump_stmts(elif->stmts);
	}
	if (stmt->else_body != NIL)
	{
		dump_ind();
		printf("    ELSE\n");
		dump_stmts(stmt->else_body);
	}
	dump_ind();
	printf("    ENDIF\n");
}

static void
dump_case(PLiSQL_stmt_case *stmt)
{
	ListCell   *l;

	dump_ind();
	printf("CASE %d ", stmt->t_varno);
	if (stmt->t_expr)
		dump_expr(stmt->t_expr);
	printf("\n");
	dump_indent += 6;
	foreach(l, stmt->case_when_list)
	{
		PLiSQL_case_when *cwt = (PLiSQL_case_when *) lfirst(l);

		dump_ind();
		printf("WHEN ");
		dump_expr(cwt->expr);
		printf("\n");
		dump_ind();
		printf("THEN\n");
		dump_indent += 2;
		dump_stmts(cwt->stmts);
		dump_indent -= 2;
	}
	if (stmt->have_else)
	{
		dump_ind();
		printf("ELSE\n");
		dump_indent += 2;
		dump_stmts(stmt->else_stmts);
		dump_indent -= 2;
	}
	dump_indent -= 6;
	dump_ind();
	printf("    ENDCASE\n");
}

static void
dump_loop(PLiSQL_stmt_loop *stmt)
{
	dump_ind();
	printf("LOOP\n");

	dump_stmts(stmt->body);

	dump_ind();
	printf("    ENDLOOP\n");
}

static void
dump_while(PLiSQL_stmt_while *stmt)
{
	dump_ind();
	printf("WHILE ");
	dump_expr(stmt->cond);
	printf("\n");

	dump_stmts(stmt->body);

	dump_ind();
	printf("    ENDWHILE\n");
}

static void
dump_fori(PLiSQL_stmt_fori *stmt)
{
	dump_ind();
	printf("FORI %s %s\n", stmt->var->refname, (stmt->reverse) ? "REVERSE" : "NORMAL");

	dump_indent += 2;
	dump_ind();
	printf("    lower = ");
	dump_expr(stmt->lower);
	printf("\n");
	dump_ind();
	printf("    upper = ");
	dump_expr(stmt->upper);
	printf("\n");
	if (stmt->step)
	{
		dump_ind();
		printf("    step = ");
		dump_expr(stmt->step);
		printf("\n");
	}
	dump_indent -= 2;

	dump_stmts(stmt->body);

	dump_ind();
	printf("    ENDFORI\n");
}

static void
dump_fors(PLiSQL_stmt_fors *stmt)
{
	dump_ind();
	printf("FORS %s ", stmt->var->refname);
	dump_expr(stmt->query);
	printf("\n");

	dump_stmts(stmt->body);

	dump_ind();
	printf("    ENDFORS\n");
}

static void
dump_forc(PLiSQL_stmt_forc *stmt)
{
	dump_ind();
	printf("FORC %s ", stmt->var->refname);
	printf("curvar=%d\n", stmt->curvar);

	dump_indent += 2;
	if (stmt->argquery != NULL)
	{
		dump_ind();
		printf("  arguments = ");
		dump_expr(stmt->argquery);
		printf("\n");
	}
	dump_indent -= 2;

	dump_stmts(stmt->body);

	dump_ind();
	printf("    ENDFORC\n");
}

static void
dump_foreach_a(PLiSQL_stmt_foreach_a *stmt)
{
	dump_ind();
	printf("FOREACHA var %d ", stmt->varno);
	if (stmt->slice != 0)
		printf("SLICE %d ", stmt->slice);
	printf("IN ");
	dump_expr(stmt->expr);
	printf("\n");

	dump_stmts(stmt->body);

	dump_ind();
	printf("    ENDFOREACHA");
}

static void
dump_open(PLiSQL_stmt_open *stmt)
{
	dump_ind();
	printf("OPEN curvar=%d\n", stmt->curvar);

	dump_indent += 2;
	if (stmt->argquery != NULL)
	{
		dump_ind();
		printf("  arguments = '");
		dump_expr(stmt->argquery);
		printf("'\n");
	}
	if (stmt->query != NULL)
	{
		dump_ind();
		printf("  query = '");
		dump_expr(stmt->query);
		printf("'\n");
	}
	if (stmt->dynquery != NULL)
	{
		dump_ind();
		printf("  execute = '");
		dump_expr(stmt->dynquery);
		printf("'\n");

		if (stmt->params != NIL)
		{
			ListCell   *lc;
			int			i;

			dump_indent += 2;
			dump_ind();
			printf("    USING\n");
			dump_indent += 2;
			i = 1;
			foreach(lc, stmt->params)
			{
				dump_ind();
				printf("    parameter $%d: ", i++);
				dump_expr((PLiSQL_expr *) lfirst(lc));
				printf("\n");
			}
			dump_indent -= 4;
		}
	}
	dump_indent -= 2;
}

static void
dump_fetch(PLiSQL_stmt_fetch *stmt)
{
	dump_ind();

	if (!stmt->is_move)
	{
		printf("FETCH curvar=%d\n", stmt->curvar);
		dump_cursor_direction(stmt);

		dump_indent += 2;
		if (stmt->target != NULL)
		{
			dump_ind();
			printf("    target = %d %s\n",
				   stmt->target->dno, stmt->target->refname);
		}
		dump_indent -= 2;
	}
	else
	{
		printf("MOVE curvar=%d\n", stmt->curvar);
		dump_cursor_direction(stmt);
	}
}

static void
dump_cursor_direction(PLiSQL_stmt_fetch *stmt)
{
	dump_indent += 2;
	dump_ind();
	switch (stmt->direction)
	{
		case FETCH_FORWARD:
			printf("    FORWARD ");
			break;
		case FETCH_BACKWARD:
			printf("    BACKWARD ");
			break;
		case FETCH_ABSOLUTE:
			printf("    ABSOLUTE ");
			break;
		case FETCH_RELATIVE:
			printf("    RELATIVE ");
			break;
		default:
			printf("??? unknown cursor direction %d", stmt->direction);
	}

	if (stmt->expr)
	{
		dump_expr(stmt->expr);
		printf("\n");
	}
	else
		printf("%ld\n", stmt->how_many);

	dump_indent -= 2;
}

static void
dump_close(PLiSQL_stmt_close *stmt)
{
	dump_ind();
	printf("CLOSE curvar=%d\n", stmt->curvar);
}

static void
dump_perform(PLiSQL_stmt_perform *stmt)
{
	dump_ind();
	printf("PERFORM expr = ");
	dump_expr(stmt->expr);
	printf("\n");
}

static void
dump_call(PLiSQL_stmt_call *stmt)
{
	dump_ind();
	printf("%s expr = ", stmt->is_call ? "CALL" : "DO");
	dump_expr(stmt->expr);
	printf("\n");
}

static void
dump_commit(PLiSQL_stmt_commit *stmt)
{
	dump_ind();
	if (stmt->chain)
		printf("COMMIT AND CHAIN\n");
	else
		printf("COMMIT\n");
}

static void
dump_rollback(PLiSQL_stmt_rollback *stmt)
{
	dump_ind();
	if (stmt->chain)
		printf("ROLLBACK AND CHAIN\n");
	else
		printf("ROLLBACK\n");
}

static void
dump_exit(PLiSQL_stmt_exit *stmt)
{
	dump_ind();
	printf("%s", stmt->is_exit ? "EXIT" : "CONTINUE");
	if (stmt->label != NULL)
		printf(" label='%s'", stmt->label);
	if (stmt->cond != NULL)
	{
		printf(" WHEN ");
		dump_expr(stmt->cond);
	}
	printf("\n");
}

static void
dump_return(PLiSQL_stmt_return *stmt)
{
	dump_ind();
	printf("RETURN ");
	if (stmt->retvarno >= 0)
		printf("variable %d", stmt->retvarno);
	else if (stmt->expr != NULL)
		dump_expr(stmt->expr);
	else
		printf("NULL");
	printf("\n");
}

static void
dump_return_next(PLiSQL_stmt_return_next *stmt)
{
	dump_ind();
	printf("RETURN NEXT ");
	if (stmt->retvarno >= 0)
		printf("variable %d", stmt->retvarno);
	else if (stmt->expr != NULL)
		dump_expr(stmt->expr);
	else
		printf("NULL");
	printf("\n");
}

static void
dump_return_query(PLiSQL_stmt_return_query *stmt)
{
	dump_ind();
	if (stmt->query)
	{
		printf("RETURN QUERY ");
		dump_expr(stmt->query);
		printf("\n");
	}
	else
	{
		printf("RETURN QUERY EXECUTE ");
		dump_expr(stmt->dynquery);
		printf("\n");
		if (stmt->params != NIL)
		{
			ListCell   *lc;
			int			i;

			dump_indent += 2;
			dump_ind();
			printf("    USING\n");
			dump_indent += 2;
			i = 1;
			foreach(lc, stmt->params)
			{
				dump_ind();
				printf("    parameter $%d: ", i++);
				dump_expr((PLiSQL_expr *) lfirst(lc));
				printf("\n");
			}
			dump_indent -= 4;
		}
	}
}

static void
dump_raise(PLiSQL_stmt_raise *stmt)
{
	ListCell   *lc;
	int			i = 0;

	dump_ind();
	printf("RAISE level=%d", stmt->elog_level);
	if (stmt->condname)
		printf(" condname='%s'", stmt->condname);
	if (stmt->message)
		printf(" message='%s'", stmt->message);
	printf("\n");
	dump_indent += 2;
	foreach(lc, stmt->params)
	{
		dump_ind();
		printf("    parameter %d: ", i++);
		dump_expr((PLiSQL_expr *) lfirst(lc));
		printf("\n");
	}
	if (stmt->options)
	{
		dump_ind();
		printf("    USING\n");
		dump_indent += 2;
		foreach(lc, stmt->options)
		{
			PLiSQL_raise_option *opt = (PLiSQL_raise_option *) lfirst(lc);

			dump_ind();
			switch (opt->opt_type)
			{
				case PLISQL_RAISEOPTION_ERRCODE:
					printf("    ERRCODE = ");
					break;
				case PLISQL_RAISEOPTION_MESSAGE:
					printf("    MESSAGE = ");
					break;
				case PLISQL_RAISEOPTION_DETAIL:
					printf("    DETAIL = ");
					break;
				case PLISQL_RAISEOPTION_HINT:
					printf("    HINT = ");
					break;
				case PLISQL_RAISEOPTION_COLUMN:
					printf("    COLUMN = ");
					break;
				case PLISQL_RAISEOPTION_CONSTRAINT:
					printf("    CONSTRAINT = ");
					break;
				case PLISQL_RAISEOPTION_DATATYPE:
					printf("    DATATYPE = ");
					break;
				case PLISQL_RAISEOPTION_TABLE:
					printf("    TABLE = ");
					break;
				case PLISQL_RAISEOPTION_SCHEMA:
					printf("    SCHEMA = ");
					break;
			}
			dump_expr(opt->expr);
			printf("\n");
		}
		dump_indent -= 2;
	}
	dump_indent -= 2;
}

static void
dump_assert(PLiSQL_stmt_assert *stmt)
{
	dump_ind();
	printf("ASSERT ");
	dump_expr(stmt->cond);
	printf("\n");

	dump_indent += 2;
	if (stmt->message != NULL)
	{
		dump_ind();
		printf("    MESSAGE = ");
		dump_expr(stmt->message);
		printf("\n");
	}
	dump_indent -= 2;
}

static void
dump_execsql(PLiSQL_stmt_execsql *stmt)
{
	dump_ind();
	printf("EXECSQL ");
	dump_expr(stmt->sqlstmt);
	printf("\n");

	dump_indent += 2;
	if (stmt->target != NULL)
	{
		dump_ind();
		printf("    INTO%s target = %d %s\n",
			   stmt->strict ? " STRICT" : "",
			   stmt->target->dno, stmt->target->refname);
	}
	dump_indent -= 2;
}

static void
dump_dynexecute(PLiSQL_stmt_dynexecute *stmt)
{
	dump_ind();
	printf("EXECUTE ");
	dump_expr(stmt->query);
	printf("\n");

	dump_indent += 2;
	if (stmt->target != NULL)
	{
		dump_ind();
		printf("    INTO%s target = %d %s\n",
			   stmt->strict ? " STRICT" : "",
			   stmt->target->dno, stmt->target->refname);
	}
	if (stmt->params != NIL)
	{
		ListCell   *lc;
		int			i;

		dump_ind();
		printf("    USING\n");
		dump_indent += 2;
		i = 1;
		foreach(lc, stmt->params)
		{
			dump_ind();
			printf("    parameter %d: ", i++);
			dump_expr((PLiSQL_expr *) lfirst(lc));
			printf("\n");
		}
		dump_indent -= 2;
	}
	dump_indent -= 2;
}

static void
dump_dynfors(PLiSQL_stmt_dynfors *stmt)
{
	dump_ind();
	printf("FORS %s EXECUTE ", stmt->var->refname);
	dump_expr(stmt->query);
	printf("\n");
	if (stmt->params != NIL)
	{
		ListCell   *lc;
		int			i;

		dump_indent += 2;
		dump_ind();
		printf("    USING\n");
		dump_indent += 2;
		i = 1;
		foreach(lc, stmt->params)
		{
			dump_ind();
			printf("    parameter $%d: ", i++);
			dump_expr((PLiSQL_expr *) lfirst(lc));
			printf("\n");
		}
		dump_indent -= 4;
	}
	dump_stmts(stmt->body);
	dump_ind();
	printf("    ENDFORS\n");
}

static void
dump_getdiag(PLiSQL_stmt_getdiag *stmt)
{
	ListCell   *lc;

	dump_ind();
	printf("GET %s DIAGNOSTICS ", stmt->is_stacked ? "STACKED" : "CURRENT");
	foreach(lc, stmt->diag_items)
	{
		PLiSQL_diag_item *diag_item = (PLiSQL_diag_item *) lfirst(lc);

		if (lc != list_head(stmt->diag_items))
			printf(", ");

		printf("{var %d} = %s", diag_item->target,
			   plisql_getdiag_kindname(diag_item->kind));
	}
	printf("\n");
}

static void
dump_expr(PLiSQL_expr *expr)
{
	printf("'%s'", expr->query);
}

void
plisql_dumptree(PLiSQL_function *func, int start_datum, int start_subprocfunc) 
{
	int			i;
	PLiSQL_datum *d;

	printf("\nExecution tree of successfully compiled PL/iSQL function %s:\n",
		   func->fn_signature);

	printf("\nFunction's data area:\n");

	for (i = start_datum; i < func->ndatums; i++)
	{
		d = func->datums[i];

		printf("    entry %d: ", i);
		switch (d->dtype)
		{
			case PLISQL_DTYPE_VAR:
			case PLISQL_DTYPE_PROMISE:
				{
					PLiSQL_var *var = (PLiSQL_var *) d;

					printf("VAR %-16s type %s (typoid %u) atttypmod %d\n",
						   var->refname, var->datatype->typname,
						   var->datatype->typoid,
						   var->datatype->atttypmod);
					if (var->isconst)
						printf("                                  CONSTANT\n");
					if (var->notnull)
						printf("                                  NOT NULL\n");
					if (var->default_val != NULL)
					{
						printf("                                  DEFAULT ");
						dump_expr(var->default_val);
						printf("\n");
					}
					if (var->cursor_explicit_expr != NULL)
					{
						if (var->cursor_explicit_argrow >= 0)
							printf("                                  CURSOR argument row %d\n", var->cursor_explicit_argrow);

						printf("                                  CURSOR IS ");
						dump_expr(var->cursor_explicit_expr);
						printf("\n");
					}
					if (var->promise != PLISQL_PROMISE_NONE)
						printf("                                  PROMISE %d\n",
							   (int) var->promise);
				}
				break;
			case PLISQL_DTYPE_ROW:
				{
					PLiSQL_row *row = (PLiSQL_row *) d;

					printf("ROW %-16s fields", row->refname);
					for (int j = 0; j < row->nfields; j++)
					{
						printf(" %s=var %d", row->fieldnames[j],
							   row->varnos[j]);
					}
					printf("\n");
				}
				break;
			case PLISQL_DTYPE_REC:
				printf("REC %-16s typoid %u\n",
					   ((PLiSQL_rec *) d)->refname,
					   ((PLiSQL_rec *) d)->rectypeid);
				if (((PLiSQL_rec *) d)->isconst)
					printf("                                  CONSTANT\n");
				if (((PLiSQL_rec *) d)->notnull)
					printf("                                  NOT NULL\n");
				if (((PLiSQL_rec *) d)->default_val != NULL)
				{
					printf("                                  DEFAULT ");
					dump_expr(((PLiSQL_rec *) d)->default_val);
					printf("\n");
				}
				break;
			case PLISQL_DTYPE_RECFIELD:
				printf("RECFIELD %-16s of REC %d\n",
					   ((PLiSQL_recfield *) d)->fieldname,
					   ((PLiSQL_recfield *) d)->recparentno);
				break;
			case PLISQL_DTYPE_PACKAGE_DATUM:
				{
					PLiSQL_pkg_datum *pkg_datum = (PLiSQL_pkg_datum *) d;

					printf("PACKAGE VAR :%s\n", pkg_datum->refname);
				}
				break;
			default:
				printf("??? unknown data type %d\n", d->dtype);
		}
	}

	printf("\nSubprocFuncs:\n");
	for (i = start_subprocfunc; i < func->nsubprocfuncs; i++)
	{
		PLiSQL_subproc_function *subprocfunc = (PLiSQL_subproc_function *) func->subprocfuncs[i];

		printf("    entry %d: ", i);
		printf("SubprocFunc: name:%s\n", subprocfunc->func_name);
		if (subprocfunc->arg == NIL)
			printf("Arguments: 0\n");
		else
		{
			ListCell *lc;
			int j = 0;

			printf("Arguments: %d\n", list_length(subprocfunc->arg));
			foreach (lc, subprocfunc->arg)
			{
				PLiSQL_function_argitem *argitem = (PLiSQL_function_argitem *) lfirst(lc);
				char *typname;

				printf("    entry %d: ", j);
				typname = argitem->type->typname;

				printf("Argument: argno:%d, argname:%s, argtype:%s\n",
						j++, argitem->argname, typname);
			}
		}
		plisql_dumptree(subprocfunc->function, subprocfunc->lastoutvardno,
								subprocfunc->lastoutsubprocfno);
		printf("\nEnd of subprocfunction %s\n\n", subprocfunc->func_name);
	}

	if (func->action != NULL)
	{
		printf("\nFunction's statements:\n");

		dump_indent = 0;
		printf("%3d:", func->action->lineno);
		dump_block(func->action);
	}

	printf("\nEnd of execution tree of function %s\n\n", func->fn_signature);
	fflush(stdout);
}
