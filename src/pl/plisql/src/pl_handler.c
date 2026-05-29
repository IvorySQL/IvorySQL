/*-------------------------------------------------------------------------
 *
 * pl_handler.c		- Handler for the PL/iSQL
 *			  procedural language
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_handler.c
 *
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/htup_details.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "plisql.h"
#include "pl_subproc_function.h"
#include "pl_package.h"
#include "pl_autonomous.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"
#include "utils/varlena.h"
#include "commands/packagecmds.h"
#include "parser/parse_param.h"
#include "utils/datum.h"
#include "oracle_parser/ora_with_function.h"
#include "executor/executor.h"
#include "nodes/params.h"
#include "parser/parse_type.h"
#include "utils/typcache.h"


static bool plisql_extra_checks_check_hook(char **newvalue, void **extra, GucSource source);
static void plisql_extra_warnings_assign_hook(const char *newvalue, void *extra);
static void plisql_extra_errors_assign_hook(const char *newvalue, void *extra);
static void set_blocks_oraparam_level(PLiSQL_stmt_block * block, int top, int cur);

PG_MODULE_MAGIC_EXT(
					.name = "plisql",
					.version = PG_VERSION
);

/* Custom GUC variable */
static const struct config_enum_entry variable_conflict_options[] = {
	{"error", PLISQL_RESOLVE_ERROR, false},
	{"use_variable", PLISQL_RESOLVE_VARIABLE, false},
	{"use_column", PLISQL_RESOLVE_COLUMN, false},
	{NULL, 0, false}
};

int			plisql_variable_conflict = PLISQL_RESOLVE_ERROR;

bool		plisql_print_strict_params = false;

bool		plisql_check_asserts = true;

/* Flag to prevent recursive autonomous transaction execution */
bool		plisql_inside_autonomous_transaction = false;

static char *plisql_extra_warnings_string = NULL;
static char *plisql_extra_errors_string = NULL;
int			plisql_extra_warnings;
int			plisql_extra_errors;

/* Hook for plugins */
PLiSQL_plugin **plisql_plugin_ptr = NULL;

/* Active WITH-clause entries during WITH function execution (enables recursive calls) */
List *plisql_active_with_func_entries = NIL;


static bool
plisql_extra_checks_check_hook(char **newvalue, void **extra, GucSource source)
{
	char	   *rawstring;
	List	   *elemlist;
	ListCell   *l;
	int			extrachecks = 0;
	int		   *myextra;

	if (pg_strcasecmp(*newvalue, "all") == 0)
		extrachecks = PLISQL_XCHECK_ALL;
	else if (pg_strcasecmp(*newvalue, "none") == 0)
		extrachecks = PLISQL_XCHECK_NONE;
	else
	{
		/* Need a modifiable copy of string */
		rawstring = pstrdup(*newvalue);

		/* Parse string into list of identifiers */
		if (!SplitIdentifierString(rawstring, ',', &elemlist))
		{
			/* syntax error in list */
			GUC_check_errdetail("List syntax is invalid.");
			pfree(rawstring);
			list_free(elemlist);
			return false;
		}

		foreach(l, elemlist)
		{
			char	   *tok = (char *) lfirst(l);

			if (pg_strcasecmp(tok, "shadowed_variables") == 0)
				extrachecks |= PLISQL_XCHECK_SHADOWVAR;
			else if (pg_strcasecmp(tok, "too_many_rows") == 0)
				extrachecks |= PLISQL_XCHECK_TOOMANYROWS;
			else if (pg_strcasecmp(tok, "strict_multi_assignment") == 0)
				extrachecks |= PLISQL_XCHECK_STRICTMULTIASSIGNMENT;
			else if (pg_strcasecmp(tok, "all") == 0 || pg_strcasecmp(tok, "none") == 0)
			{
				GUC_check_errdetail("Key word \"%s\" cannot be combined with other key words.", tok);
				pfree(rawstring);
				list_free(elemlist);
				return false;
			}
			else
			{
				GUC_check_errdetail("Unrecognized key word: \"%s\".", tok);
				pfree(rawstring);
				list_free(elemlist);
				return false;
			}
		}

		pfree(rawstring);
		list_free(elemlist);
	}

	myextra = (int *) guc_malloc(LOG, sizeof(int));
	if (!myextra)
		return false;
	*myextra = extrachecks;
	*extra = myextra;

	return true;
}

static void
plisql_extra_warnings_assign_hook(const char *newvalue, void *extra)
{
	plisql_extra_warnings = *((int *) extra);
}

static void
plisql_extra_errors_assign_hook(const char *newvalue, void *extra)
{
	plisql_extra_errors = *((int *) extra);
}


/**
 * Initialize the PL/iSQL shared library at load time.
 *
 * Registers module GUC variables (including hooks for extra checks), reserves
 * the PL/iSQL GUC prefix, initializes module state and hash tables, registers
 * transaction and subtransaction callbacks, registers internal functions,
 * establishes the plugin rendezvous point, and initializes autonomous-transaction
 * support.
 *
 * DO NOT make this function static or rename it; PostgreSQL calls it at library
 * load time.
 */
void
_PG_init(void)
{
	/* Be sure we do initialization only once (should be redundant now) */
	static bool inited = false;

	if (inited)
		return;

	pg_bindtextdomain(TEXTDOMAIN);

	DefineCustomEnumVariable("plisql.variable_conflict",
							 gettext_noop("Sets handling of conflicts between PL/iSQL variable names and table column names."),
							 NULL,
							 &plisql_variable_conflict,
							 PLISQL_RESOLVE_ERROR,
							 variable_conflict_options,
							 PGC_SUSET, 0,
							 NULL, NULL, NULL);

	DefineCustomBoolVariable("plisql.print_strict_params",
							 gettext_noop("Print information about parameters in the DETAIL part of the error messages generated on INTO ... STRICT failures."),
							 NULL,
							 &plisql_print_strict_params,
							 false,
							 PGC_USERSET, 0,
							 NULL, NULL, NULL);

	DefineCustomBoolVariable("plisql.check_asserts",
							 gettext_noop("Perform checks given in ASSERT statements."),
							 NULL,
							 &plisql_check_asserts,
							 true,
							 PGC_USERSET, 0,
							 NULL, NULL, NULL);

	/*
	 * Note: Must use PGC_USERSET (not PGC_INTERNAL) because autonomous
	 * transactions execute via dblink in a separate connection, which must
	 * be able to SET this flag via SQL to prevent infinite recursion.
	 * Hidden from users via GUC_NOT_IN_SAMPLE | GUC_NO_SHOW_ALL | GUC_NO_RESET_ALL.
	 */
	DefineCustomBoolVariable("plisql.inside_autonomous_transaction",
							 gettext_noop("Internal flag to prevent recursive autonomous transaction execution."),
							 NULL,
							 &plisql_inside_autonomous_transaction,
							 false,
							 PGC_USERSET,
							 GUC_NOT_IN_SAMPLE | GUC_NO_SHOW_ALL | GUC_NO_RESET_ALL,
							 NULL, NULL, NULL);

	DefineCustomStringVariable("plisql.extra_warnings",
							   gettext_noop("List of programming constructs that should produce a warning."),
							   NULL,
							   &plisql_extra_warnings_string,
							   "none",
							   PGC_USERSET, GUC_LIST_INPUT,
							   plisql_extra_checks_check_hook,
							   plisql_extra_warnings_assign_hook,
							   NULL);

	DefineCustomStringVariable("plisql.extra_errors",
							   gettext_noop("List of programming constructs that should produce an error."),
							   NULL,
							   &plisql_extra_errors_string,
							   "none",
							   PGC_USERSET, GUC_LIST_INPUT,
							   plisql_extra_checks_check_hook,
							   plisql_extra_errors_assign_hook,
							   NULL);

	MarkGUCPrefixReserved("plisql");

	plisql_HashTableInit();
	RegisterXactCallback(plisql_xact_cb, NULL);
	RegisterSubXactCallback(plisql_subxact_cb, NULL);

	plisql_register_internal_func();

	/* Set up a rendezvous point with optional instrumentation plugin */
	plisql_plugin_ptr = (PLiSQL_plugin * *) find_rendezvous_variable("PLiSQL_plugin");

	/* Register invalidation callback for cached dblink OID */
	plisql_autonomous_init();

	inited = true;
}

/*
 * Cleanup: deregister internal routines.
 */
void _PG_fini(void);

void
_PG_fini(void)
{
	plisql_unregister_internal_func();
}

/* -----------------------------------------------------------------------
 * WITH clause inline function support (Phase 3: execution-time)
 *
 * buildWithFuncContainer and plisql_get_with_func live here (inside
 * plisql.so) so they can call plisql_compile_inline() without creating a
 * dependency from the main postgres binary on plisql internals.
 * ----------------------------------------------------------------------- */

/*
 * buildParamListForFunc — build a ParamListInfo for plisql_compile_inline.
 *
 * Supplies parameter names and types to the PL/iSQL compiler so that each
 * IN/INOUT parameter becomes a named variable accessible in the function body.
 */
static ParamListInfo
buildParamListForFunc(List *args)
{
	int			nparams = list_length(args);
	int			i;
	ListCell   *lc;
	ParamListInfo paramLI;

	if (nparams == 0)
		return NULL;

	paramLI = makeParamList(nparams);
	paramLI->paramnames = (char **) palloc0(nparams * sizeof(char *));

	i = 0;
	foreach(lc, args)
	{
		FunctionParameter *fp = (FunctionParameter *) lfirst(lc);
		Oid			ptype;
		int32		ptypmod;

		/*
		 * Resolve both the type OID and the typmod so that declarations like
		 * VARCHAR2(10) or NUMBER(5,2) are preserved on the parameter; using
		 * typenameTypeId() alone would drop the user-supplied modifier and
		 * leave ptypmod at its initial -1 ("no typmod") sentinel.
		 */
		typenameTypeIdAndMod(NULL, fp->argType, &ptype, &ptypmod);

		paramLI->paramnames[i]       = fp->name;
		paramLI->params[i].value     = (Datum) 0;
		paramLI->params[i].isnull    = true;
		paramLI->params[i].pflags    = 0;
		paramLI->params[i].ptype     = ptype;
		paramLI->params[i].ptypmod   = ptypmod;
		paramLI->params[i].pmode     = (char) fp->mode;
		i++;
	}

	return paramLI;
}

/*
 * buildWithFuncEntries — build a WithFuncEntry list from withFuncDefs.
 *
 * Creates the same descriptor structs that transformWithFuncDefs() builds at
 * parse time, but at execution time from the already-serialised InlineFunctionDef
 * list.  Stored in WithFuncContainer.func_entries so that
 * plisql_active_with_func_entries can be set while each WITH function executes,
 * allowing recursive and mutually-recursive calls (T10).
 */
static List *
buildWithFuncEntries(List *withFuncDefs)
{
	List	   *result = NIL;
	int			funcindex = 0;
	ListCell   *lc;

	foreach(lc, withFuncDefs)
	{
		InlineFunctionDef *ifd = (InlineFunctionDef *) lfirst(lc);
		WithFuncEntry *entry;
		List	   *argtypes = NIL;
		List	   *analyzeddefaults = NIL;
		ListCell   *alc;

		foreach(alc, ifd->args)
		{
			FunctionParameter *fp = (FunctionParameter *) lfirst(alc);

			if (fp->mode == FUNC_PARAM_OUT)
				continue;

			argtypes = lappend_oid(argtypes,
								   typenameTypeId(NULL, fp->argType));

			/*
			 * Default expressions are analyzed only at parse time
			 * (transformWithFuncDefs) where a real ParseState exists.  Here
			 * we have none, so record a NULL placeholder positionally aligned
			 * with argtypes.  withFuncLookupHook indexes analyzeddefaults by
			 * parameter position when nargs < nentryargs; without this the
			 * field would be uninitialized and list_nth() would read garbage.
			 */
			analyzeddefaults = lappend(analyzeddefaults, NULL);
		}

		entry = palloc(sizeof(WithFuncEntry));
		entry->funcname  = pstrdup(ifd->funcname);
		entry->argtypes  = argtypes;
		entry->rettype   = (ifd->rettype != NULL)
						   ? typenameTypeId(NULL, ifd->rettype)
						   : InvalidOid;
		entry->is_proc   = ifd->is_proc;
		entry->funcindex = funcindex++;
		entry->def       = ifd;
		entry->ndefaults = 0;
		entry->analyzeddefaults = analyzeddefaults;

		result = lappend(result, entry);
	}

	return result;
}

/*
 * fixupCompiledReturnType — patch fn_rettype after plisql_compile_inline.
 *
 * plisql_compile_inline always sets fn_rettype = VOIDOID.  We fix that up
 * so plisql_exec_function returns the correct type.
 */
static void
fixupCompiledReturnType(PLiSQL_function *func, Oid rettype, bool is_proc)
{
	int16	typlen;
	bool	typbyval;

	if (is_proc || rettype == InvalidOid)
	{
		func->fn_rettype    = VOIDOID;
		func->fn_retbyval   = true;
		func->fn_rettyplen  = sizeof(int32);
		func->fn_retistuple = false;
		func->fn_retisdomain = false;
		func->fn_prokind    = PROKIND_PROCEDURE;
		return;
	}

	func->fn_rettype    = rettype;
	func->fn_prokind    = PROKIND_FUNCTION;
	func->fn_retset     = false;

	get_typlenbyval(rettype, &typlen, &typbyval);
	func->fn_rettyplen  = typlen;
	func->fn_retbyval   = typbyval;
	func->fn_retistuple = (typlen == -2 || type_is_rowtype(rettype));
	func->fn_retisdomain = (get_typtype(rettype) == TYPTYPE_DOMAIN);
}

/* Error context callback for WITH FUNCTION compilation errors */
typedef struct
{
	const char *funcname;
	bool		is_proc;
} WithFuncCompileErrCtx;

static void
with_func_compile_error_callback(void *arg)
{
	WithFuncCompileErrCtx *ctx = (WithFuncCompileErrCtx *) arg;

	errcontext("while compiling WITH %s \"%s\"",
			   ctx->is_proc ? "PROCEDURE" : "FUNCTION",
			   ctx->funcname);
}

/*
 * buildWithFuncContainer — compile all WITH-clause functions and return a
 * container stored in EState.es_with_func_container.
 *
 * Called lazily on the first invocation of any WITH-clause function within
 * a query execution.  Subsequent calls within the same query reuse the
 * cached container.
 */
WithFuncContainer *
buildWithFuncContainer(EState *estate)
{
	PlannedStmt    *pstmt = estate->es_plannedstmt;
	MemoryContext   oldcxt;
	MemoryContext   mcxt;
	WithFuncContainer *container;
	int				nfuncs;
	int				i;
	ListCell	   *lc;

	Assert(pstmt->withFuncDefs != NIL);

	nfuncs = list_length(pstmt->withFuncDefs);

	mcxt = AllocSetContextCreate(estate->es_query_cxt,
								 "WITH function container",
								 ALLOCSET_DEFAULT_SIZES);
	oldcxt = MemoryContextSwitchTo(mcxt);

	container = palloc0(sizeof(WithFuncContainer));
	container->nfuncs = nfuncs;
	container->funcs  = palloc0(nfuncs * sizeof(PLiSQL_subproc_function *));
	container->mcxt   = mcxt;
	container->func_entries = buildWithFuncEntries(pstmt->withFuncDefs);

	i = 0;
	foreach(lc, pstmt->withFuncDefs)
	{
		InlineFunctionDef		*ifd = (InlineFunctionDef *) lfirst(lc);
		ParamListInfo			 paramLI;
		PLiSQL_function			*compiled;
		PLiSQL_subproc_function *subprocfunc;
		Oid						 rettype;
		ErrorContextCallback	 errcallback;
		WithFuncCompileErrCtx	 errctx;

		/*
		 * Set up error context so compilation errors name the function.
		 *
		 * Note: this push/pop pattern matches PG's plisql_compile in
		 * pl_comp.c (lines 345-1239) which similarly does NOT wrap in
		 * PG_TRY/PG_FINALLY.  If any of the calls below throws, the pop is
		 * skipped and error_context_stack carries a dangling pointer until
		 * postgres.c:4626 resets it at top-level command abort.  An earlier
		 * attempt to wrap in PG_TRY/PG_FINALLY caused a segfault in T11
		 * (interaction with PL/iSQL's internal EXCEPTION handler), so we
		 * follow PG's established convention here.
		 */
		errctx.funcname = ifd->funcname;
		errctx.is_proc  = ifd->is_proc;
		errcallback.callback = with_func_compile_error_callback;
		errcallback.arg		 = &errctx;
		errcallback.previous = error_context_stack;
		error_context_stack  = &errcallback;

		paramLI  = buildParamListForFunc(ifd->args);
		rettype = (ifd->rettype != NULL)
				  ? typenameTypeId(NULL, ifd->rettype)
				  : InvalidOid;
		compiled = plisql_compile_inline(ifd->src, paramLI, false,
										 rettype, ifd->is_proc);
		fixupCompiledReturnType(compiled, rettype, ifd->is_proc);

		/*
		 * Tag the compiled function so plisql_parser_setup knows this body
		 * is a WITH-clause inline subprogram and may see WITH-clause names.
		 * Without this tag, lexical scope leaks into catalog functions
		 * called from within a WITH-clause execution frame.
		 */
		compiled->is_with_clause_func = true;

		error_context_stack = errcallback.previous;

		subprocfunc = palloc0(sizeof(PLiSQL_subproc_function));
		subprocfunc->fno       = i;
		subprocfunc->func_name = pstrdup(ifd->funcname);
		subprocfunc->is_proc   = ifd->is_proc;
		subprocfunc->function  = compiled;
		subprocfunc->src       = pstrdup(ifd->src);

		container->funcs[i] = subprocfunc;
		i++;
	}

	MemoryContextSwitchTo(oldcxt);

	return container;
}

/*
 * plisql_get_with_func — look up the compiled PLiSQL_function for a WITH-
 * clause function call.
 *
 * Called from plisql_call_handler() when function_from == FUNC_FROM_WITH_CLAUSE.
 * Builds the WithFuncContainer lazily on first call within a query.
 */
PLiSQL_function *
plisql_get_with_func(FunctionCallInfo fcinfo)
{
	EState			  *estate;
	WithFuncContainer *container;
	int				   fno;

	estate = (EState *) fcinfo->flinfo->fn_extra;
	if (estate == NULL)
		elog(ERROR, "WITH clause function has no executor state");

	fno = (int) fcinfo->flinfo->fn_oid;

	if (estate->es_with_func_container == NULL)
		estate->es_with_func_container = buildWithFuncContainer(estate);

	container = (WithFuncContainer *) estate->es_with_func_container;

	if (fno < 0 || fno >= container->nfuncs)
		elog(ERROR, "invalid WITH function index %d", fno);

	return container->funcs[fno]->function;
}

/* ----------
 * plisql_call_handler
 *
 * The PostgreSQL function manager and trigger manager
 * call this function for execution of PL/iSQL procedures.
 * ----------
 */
PG_FUNCTION_INFO_V1(plisql_call_handler);

Datum
plisql_call_handler(PG_FUNCTION_ARGS)
{
	bool		nonatomic;
	PLiSQL_function *func;
	PLiSQL_execstate *save_cur_estate;
	ResourceOwner procedure_resowner;
	volatile Datum retval = (Datum) 0;
	int			rc;

	char		function_from = plisql_function_from(fcinfo);
	int			oraparam_top_level = -1;
	int			oraparam_cur_level = -1;
	volatile List *save_with_func_entries = NIL;
	volatile EState *save_with_func_estate = NULL;

	nonatomic = fcinfo->context &&
		IsA(fcinfo->context, CallContext) &&
		!castNode(CallContext, fcinfo->context)->atomic;

	/*
	 * Connect to SPI manager
	 */
	SPI_connect_ext(nonatomic ? SPI_OPT_NONATOMIC : 0);

	/* Find or compile the function */
	if (function_from == FUNC_FROM_SUBPROCFUNC)
		func = plisql_get_subproc_func(fcinfo, false);
	else if (function_from == FUNC_FROM_PACKAGE)
	{
		func = plisql_get_package_func(fcinfo, false);
	}
	else if (function_from == FUNC_FROM_WITH_CLAUSE)
	{
		func = plisql_get_with_func(fcinfo);

		/*
		 * Make WITH-clause entries and the owning EState visible during this
		 * function's execution so that recursive and mutually-recursive calls
		 * can be resolved.  We save/restore to handle nested WITH-clause
		 * calls correctly.
		 */
		{
			EState		   *wf_estate = (EState *) fcinfo->flinfo->fn_extra;
			WithFuncContainer *wc =
				(WithFuncContainer *) wf_estate->es_with_func_container;

			save_with_func_entries = plisql_active_with_func_entries;
			plisql_active_with_func_entries = wc->func_entries;

			save_with_func_estate = plisql_active_with_func_estate;
			plisql_active_with_func_estate = wf_estate;
		}
	}
	else
		func = plisql_compile(fcinfo, false);

	/* Record the active function for this SPI level. */
	SPI_remember_func(func);

	/* Must save and restore prior value of cur_estate */
	save_cur_estate = func->cur_estate;

	/* Mark the function as busy, so it can't be deleted from under us */
	func->use_count++;

	/*
	 * If we'll need a procedure-lifespan resowner to execute any CALL or DO
	 * statements, create it now.  Since this resowner is not tied to any
	 * parent, failing to free it would result in process-lifespan leaks.
	 * Therefore, be very wary of adding any code between here and the PG_TRY
	 * block.
	 */
	procedure_resowner =
		(nonatomic && func->requires_procedure_resowner) ?
		ResourceOwnerCreate(NULL, "PL/iSQL procedure resources") : NULL;

	push_oraparam_stack();
	get_oraparam_level(&oraparam_top_level, &oraparam_cur_level);
	set_blocks_oraparam_level(func->action, oraparam_top_level, oraparam_cur_level);

	PG_TRY();
	{
		/*
		 * Determine if called as function or trigger and call appropriate
		 * subhandler
		 */
		if (CALLED_AS_TRIGGER(fcinfo))
			retval = PointerGetDatum(plisql_exec_trigger(func,
														 (TriggerData *) fcinfo->context));
		else if (CALLED_AS_EVENT_TRIGGER(fcinfo))
		{
			plisql_exec_event_trigger(func,
									  (EventTriggerData *) fcinfo->context);
			/* there's no return value in this case */
		}
		else
			retval = plisql_exec_function(func, fcinfo,
										  NULL, NULL,
										  procedure_resowner,
										  !nonatomic);
	}
	PG_FINALLY();
	{
		pop_oraparam_stack(oraparam_top_level - 1, oraparam_cur_level);

		/* Restore WITH-clause globals saved before WITH function execution */
		if (function_from == FUNC_FROM_WITH_CLAUSE)
		{
			plisql_active_with_func_entries = (List *) save_with_func_entries;
			plisql_active_with_func_estate  = (EState *) save_with_func_estate;
		}

		/* Decrement use-count, restore cur_estate */
		func->use_count--;
		func->cur_estate = save_cur_estate;

		if (function_from == FUNC_FROM_PACKAGE)
		{
			release_package_func_usecount(fcinfo);
		}

		/* Be sure to release the procedure resowner if any */
		if (procedure_resowner)
		{
			ReleaseAllPlanCacheRefsInOwner(procedure_resowner);
			ResourceOwnerDelete(procedure_resowner);
		}
	}
	PG_END_TRY();

	/*
	 * Disconnect from SPI manager
	 */
	if ((rc = SPI_finish()) != SPI_OK_FINISH)
		elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(rc));

	return retval;
}

/* ----------
 * plisql_inline_handler
 *
 * Called by PostgreSQL to execute an anonymous code block
 * ----------
 */
PG_FUNCTION_INFO_V1(plisql_inline_handler);

Datum
plisql_inline_handler(PG_FUNCTION_ARGS)
{
	LOCAL_FCINFO(fake_fcinfo, FUNC_MAX_ARGS);
	InlineCodeBlock *codeblock = castNode(InlineCodeBlock, DatumGetPointer(PG_GETARG_DATUM(0)));
	PLiSQL_function *func;
	FmgrInfo	flinfo;
	EState	   *simple_eval_estate;
	ResourceOwner simple_eval_resowner;
	Datum		retval;
	int			rc;
	bool		ora_forward = false;
	int			oraparam_top_level = -1;
	int			oraparam_cur_level = -1;
	MemoryContext oldcontext = CurrentMemoryContext;

	/*
	 * Connect to SPI manager
	 */
	SPI_connect_ext(codeblock->atomic ? 0 : SPI_OPT_NONATOMIC);

	if (codeblock->params != NULL)
	{
		bool		check_var = get_doStmtCheckVar();

		set_ParseDynSql(true);
		set_parseDynDoStmt(true);
		set_haspgparam(false);
		set_ParseDynSql(true);
		set_doStmtCheckVar(check_var);

		if (codeblock->params->paramnames != NULL)
			set_bindByName(true);
	}

	/*
	 * Anonymous block has parameters, call forward_oraparam_stack, 
	 * so that we can check if the variable matches.
	 */
	if (codeblock->params != NULL &&
		SPI_get_connected() == 0)
	{
		forward_oraparam_stack();
		ora_forward = true;
	}

	/* Compile the anonymous code block */
	func = plisql_compile_inline(codeblock->source_text, codeblock->params, codeblock->do_from_call,
								VOIDOID, false);

	/* Record the active function for this SPI level. */
	SPI_remember_func(func);

	/* check variables */
	if (get_doStmtCheckVar() || ora_forward)
	{
		PG_TRY();
		{
			check_variables_does_match(codeblock->params == NULL ? 0 : codeblock->params->numParams);
		}

		PG_CATCH();
		{
			plisql_subxact_cb(SUBXACT_EVENT_ABORT_SUB,
							  GetCurrentSubTransactionId(),
							  0, NULL);

			plisql_free_function_memory(func, 0, 0);

			if (ora_forward)
				backward_oraparam_stack();

			/* throw out the error */
			PG_RE_THROW();
		}

		PG_END_TRY();
	}

	/* Mark the function as busy, just pro forma */
	func->use_count++;

	/*
	 * Set up a fake fcinfo with just enough info to satisfy
	 * plisql_exec_function().  In particular note that this sets things up
	 * with no arguments passed.
	 */
	if (codeblock->params)
		MemSet(fake_fcinfo, 0, SizeForFunctionCallInfo(codeblock->params->numParams));
	else
		MemSet(fake_fcinfo, 0, SizeForFunctionCallInfo(0));

	MemSet(&flinfo, 0, sizeof(flinfo));
	fake_fcinfo->flinfo = &flinfo;
	flinfo.fn_oid = InvalidOid;
	flinfo.fn_mcxt = CurrentMemoryContext;

	/*
	 * Create a private EState and resowner for simple-expression execution.
	 * Notice that these are NOT tied to transaction-level resources; they
	 * must survive any COMMIT/ROLLBACK the DO block executes, since we will
	 * unconditionally try to clean them up below.  (Hence, be wary of adding
	 * anything that could fail between here and the PG_TRY block.)  See the
	 * comments for shared_simple_eval_estate.
	 *
	 * Because this resowner isn't tied to the calling transaction, we can
	 * also use it as the "procedure" resowner for any CALL statements.  That
	 * helps reduce the opportunities for failure here.
	 */
	simple_eval_estate = CreateExecutorState();
	simple_eval_resowner =
		ResourceOwnerCreate(NULL, "PL/iSQL DO block simple expressions");

	if (codeblock->params)
	{
		int			i;

		fake_fcinfo->nargs = codeblock->params->numParams;
		for (i = 0; i < codeblock->params->numParams; ++i)
		{
			fake_fcinfo->args[i].value = codeblock->params->params[i].value;
			fake_fcinfo->args[i].isnull = codeblock->params->params[i].isnull;
		}
	}
	push_oraparam_stack();
	get_oraparam_level(&oraparam_top_level, &oraparam_cur_level);
	set_blocks_oraparam_level(func->action, oraparam_top_level, oraparam_cur_level);

	/* And run the function */
	PG_TRY();
	{
		retval = plisql_exec_function(func, fake_fcinfo,
									  simple_eval_estate,
									  simple_eval_resowner,
									  simple_eval_resowner, /* see above */
									  codeblock->atomic);
	}
	PG_CATCH();
	{
		if (codeblock->do_from_call && oldcontext != ErrorContext)
		{
			ErrorData  *edata;

			/* Save error info */
			MemoryContextSwitchTo(oldcontext);
			edata = CopyErrorData();
			FlushErrorState();
			
			/* For CALL statements expect only primary error message */
			if (edata->message)
				elog(ERROR, "%s", edata->message);
			else
				ThrowErrorData(edata);
			FreeErrorData(edata);
		}

		pop_oraparam_stack(oraparam_top_level - 1, oraparam_cur_level);
		if (ora_forward)
			backward_oraparam_stack();
		set_bindByName(false);

		/*
		 * We need to clean up what would otherwise be long-lived resources
		 * accumulated by the failed DO block, principally cached plans for
		 * statements (which can be flushed by plisql_free_function_memory),
		 * execution trees for simple expressions, which are in the private
		 * EState, and cached-plan refcounts held by the private resowner.
		 *
		 * Before releasing the private EState, we must clean up any
		 * simple_econtext_stack entries pointing into it, which we can do by
		 * invoking the subxact callback.  (It will be called again later if
		 * some outer control level does a subtransaction abort, but no harm
		 * is done.)  We cheat a bit knowing that plisql_subxact_cb does not
		 * pay attention to its parentSubid argument.
		 */
		plisql_subxact_cb(SUBXACT_EVENT_ABORT_SUB,
						  GetCurrentSubTransactionId(),
						  0, NULL);

		/* Clean up the private EState and resowner */
		FreeExecutorState(simple_eval_estate);
		ReleaseAllPlanCacheRefsInOwner(simple_eval_resowner);
		ResourceOwnerDelete(simple_eval_resowner);

		/* Function should now have no remaining use-counts ... */
		func->use_count--;
		Assert(func->use_count == 0);

		/* ... so we can free subsidiary storage */
		plisql_free_function_memory(func, 0, 0);

		/* And propagate the error */
		PG_RE_THROW();
	}
	PG_END_TRY();

	pop_oraparam_stack(oraparam_top_level - 1, oraparam_cur_level);
	if (ora_forward)
		backward_oraparam_stack();

	set_bindByName(false);

	if (codeblock->params != NULL && codeblock->params->haveout)
	{
		int			i;
		int16		typLen;
		bool		typByVal;
		MemoryContext old;

		/* use datumCopy to pass variables, first switch to saved memory context */
		old = MemoryContextSwitchTo(Ora_spi_saved_memorycontext());
		for (i = 0; i < fake_fcinfo->nargs; ++i)
		{
			if (!fake_fcinfo->args[i].isnull)
			{
				get_typlenbyval(codeblock->params->params[i].ptype, &typLen, &typByVal);

				/*
				 * use datumCopy because fake_fcinfo memory will be freed by
				 * FreeExecutorState
				 */
				codeblock->params->params[i].value = datumCopy(fake_fcinfo->args[i].value, typByVal, typLen);
				codeblock->params->params[i].isnull = fake_fcinfo->args[i].isnull;
			}
			else
			{
				codeblock->params->params[i].value = (Datum) 0;
				codeblock->params->params[i].isnull = fake_fcinfo->args[i].isnull;
			}
		}

		/* switch to old memory context */
		MemoryContextSwitchTo(old);
	}

	/* Clean up the private EState and resowner */
	FreeExecutorState(simple_eval_estate);
	ReleaseAllPlanCacheRefsInOwner(simple_eval_resowner);
	ResourceOwnerDelete(simple_eval_resowner);

	/* Function should now have no remaining use-counts ... */
	func->use_count--;
	Assert(func->use_count == 0);

	/* ... so we can free subsidiary storage */
	plisql_free_function_memory(func, 0, 0);

	/*
	 * Disconnect from SPI manager
	 */
	if ((rc = SPI_finish()) != SPI_OK_FINISH)
		elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(rc));

	return retval;
}

/* ----------
 * plisql_validator
 *
 * This function attempts to validate a PL/iSQL function at
 * CREATE FUNCTION time.
 * ----------
 */
PG_FUNCTION_INFO_V1(plisql_validator);

Datum
plisql_validator(PG_FUNCTION_ARGS)
{
	Oid			funcoid = PG_GETARG_OID(0);
	HeapTuple	tuple;
	Form_pg_proc proc;
	char		functyptype;
	int			numargs;
	Oid		   *argtypes;
	char	  **argnames;
	char	   *argmodes;
	bool		is_dml_trigger = false;
	bool		is_event_trigger = false;
	int			i;

	if (!CheckFunctionValidatorAccess(fcinfo->flinfo->fn_oid, funcoid))
		PG_RETURN_VOID();

	/* Get the new function's pg_proc entry */
	tuple = SearchSysCache1(PROCOID, ObjectIdGetDatum(funcoid));
	if (!HeapTupleIsValid(tuple))
		elog(ERROR, "cache lookup failed for function %u", funcoid);
	proc = (Form_pg_proc) GETSTRUCT(tuple);

	functyptype = get_typtype(proc->prorettype);

	/* Disallow pseudotype result */
	/* except for TRIGGER, EVTTRIGGER, RECORD, VOID, or polymorphic */
	if (functyptype == TYPTYPE_PSEUDO)
	{
		if (proc->prorettype == TRIGGEROID)
			is_dml_trigger = true;
		else if (proc->prorettype == EVENT_TRIGGEROID)
			is_event_trigger = true;
		else if (proc->prorettype != RECORDOID &&
				 proc->prorettype != VOIDOID &&
				 !IsPolymorphicType(proc->prorettype))
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("PL/iSQL functions cannot return type %s",
							format_type_be(proc->prorettype))));
	}

	/* Disallow pseudotypes in arguments (either IN or OUT) */
	/* except for RECORD and polymorphic */
	numargs = get_func_arg_info(tuple,
								&argtypes, &argnames, &argmodes);
	for (i = 0; i < numargs; i++)
	{
		if (get_typtype(argtypes[i]) == TYPTYPE_PSEUDO)
		{
			if (argtypes[i] != RECORDOID &&
				!IsPolymorphicType(argtypes[i]))
				ereport(ERROR,
						(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						 errmsg("PL/iSQL functions cannot accept type %s",
								format_type_be(argtypes[i]))));
		}
	}

	/* Postpone body checks if !check_function_bodies */
	if (check_function_bodies)
	{
		LOCAL_FCINFO(fake_fcinfo, 0);
		FmgrInfo	flinfo;
		int			rc;
		TriggerData trigdata;
		EventTriggerData etrigdata;

		/*
		 * Connect to SPI manager (is this needed for compilation?)
		 */
		if ((rc = SPI_connect()) != SPI_OK_CONNECT)
			elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(rc));

		/*
		 * Set up a fake fcinfo with just enough info to satisfy
		 * plisql_compile().
		 */
		MemSet(fake_fcinfo, 0, SizeForFunctionCallInfo(0));
		MemSet(&flinfo, 0, sizeof(flinfo));
		fake_fcinfo->flinfo = &flinfo;
		flinfo.fn_oid = funcoid;
		flinfo.fn_mcxt = CurrentMemoryContext;
		if (is_dml_trigger)
		{
			MemSet(&trigdata, 0, sizeof(trigdata));
			trigdata.type = T_TriggerData;
			fake_fcinfo->context = (Node *) &trigdata;
		}
		else if (is_event_trigger)
		{
			MemSet(&etrigdata, 0, sizeof(etrigdata));
			etrigdata.type = T_EventTriggerData;
			fake_fcinfo->context = (Node *) &etrigdata;
		}

		PG_TRY();
		{
			/* Test-compile the function */
			plisql_compile(fake_fcinfo, true);
		}
		PG_CATCH();
		{
			/*
			 * Disconnect from SPI manager
			 */
			if ((rc = SPI_finish()) != SPI_OK_FINISH)
				elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(rc));

			ReleaseSysCache(tuple);

			PG_RE_THROW();
		}
		PG_END_TRY();

		/*
		 * Disconnect from SPI manager
		 */
		if ((rc = SPI_finish()) != SPI_OK_FINISH)
			elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(rc));
	}

	ReleaseSysCache(tuple);

	PG_RETURN_VOID();
}

static void
set_blocks_oraparam_level(PLiSQL_stmt_block * block, int top, int cur)
{
	ListCell   *s;

	if (block == NULL || block->body == NIL)
	{
		return;
	}

	block->ora_param_stack_top_level = top;
	block->ora_param_stack_cur_level = cur;

	foreach(s, block->body)
	{
		PLiSQL_stmt *stmt = (PLiSQL_stmt *) lfirst(s);

		if (stmt != NULL && (enum PLiSQL_stmt_type) stmt->cmd_type == PLISQL_STMT_BLOCK)
		{
			set_blocks_oraparam_level((PLiSQL_stmt_block *) stmt, top, cur);
		}
	}

	return;
}
