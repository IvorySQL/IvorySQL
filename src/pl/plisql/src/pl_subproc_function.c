/*-------------------------------------------------------------------------
 *
 * File:pl_subproc_function.c
 *
 * Abstract:
 *		Definitions for the PLISQL
 *			  procedural language nested sub function/procedure
 *
 * Authored by dwdai@highgo.com,20220627.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_subproc_function.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"
#include "plisql.h"
#include "pl_subproc_function.h"
#include "pl_package.h"
#include "parser/parse_coerce.h"
#include "parser/parse_target.h"
#include "parser/parse_expr.h"
#include "nodes/nodeFuncs.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "utils/builtins.h"
#include "utils/syscache.h"
#include "utils/lsyscache.h"
#include "commands/packagecmds.h"
#include "catalog/pg_package.h"
#include "miscadmin.h"


typedef struct _subprocFuncCandidateList
{
	struct _subprocFuncCandidateList *next;
	int		fno;
	int		nargs;
	int		ndargs;
	char	*argmodes;
	int		*argnumbers;
	Oid		args[FLEXIBLE_ARRAY_MEMBER];
} *subprocFuncCandidateList;

PLiSQL_subproc_function **plisql_subprocFuncs;
int plisql_nsubprocFuncs;
int subprocFuncs_alloc;
int cur_compile_func_level;
/*
 * saved subproc informations
 * plisql_saved_compile:
 *		save the last compile function
 * plisql_saved_last_datums:
 *		saved the last var'dno of block init var
 * plisql_saved_error_funcname
 *		saved the last Plisql_error_funcname
 * plisql_saved_nsubprocfuncs
 *		saved the last plisql_nsubprocFuncs
 * plisql_saved_subprocfunc_alloc
 *		saved the last subprocFuncs_alloc
 * plisql_saved_subprocfuncs
 * 		saved tha lst plisql_subprocFuncs
 */
PLiSQL_function *plisql_saved_compile[FUNC_MAX_NEST_LEVEL];
int plisql_saved_datums_last[FUNC_MAX_NEST_LEVEL];
char *plisql_saved_error_funcname[FUNC_MAX_NEST_LEVEL];
int plisql_saved_nsubprocfuncs[FUNC_MAX_NEST_LEVEL];
int plisql_saved_subprocfunc_alloc[FUNC_MAX_NEST_LEVEL];
PLiSQL_subproc_function **plisql_saved_subprocfuncs[FUNC_MAX_NEST_LEVEL];


/* user full functions */
static HTAB *plisql_subprocfunc_HashTableInit(void);

static int plisql_check_function_canreload(List *args,
						List *fnos, PLiSQL_type *rettype);
static PLiSQL_subproc_function * plisql_build_subproc_function_internal(char *funcname,
																	List *args,
																	PLiSQL_type *retype,
																	bool add2namespace,
																	int location); 
static bool plisql_match_function_argnames(List *funcargs, int nargs,
													List *argnames, int **argnumber);
static subprocFuncCandidateList plisql_getFuncCandidateListFromFunname(char *funcname,
																	PLiSQL_function *pfunc,
																	PLiSQL_nsitem *nse, int nargs,
																	List *fargname,
																	bool proc_call);
static int plisql_func_match_argtypes(int nargs, Oid *input_typeids,
												subprocFuncCandidateList raw_candidates,
												subprocFuncCandidateList *candidates);
static subprocFuncCandidateList plisql_func_select_candidate(int nargs,
																Oid *input_typeids,
																subprocFuncCandidateList candidates);
static List *plisql_expand_and_reorder_functionargs(ParseState *pstate,
																	PLiSQL_subproc_function *subprocfunc,
																	int funcnarg, List *fargs,
																	List *defaultnumber, List **argdefaults);
static TypeFuncClass internal_get_subprocfunc_result_type(PLiSQL_subproc_function *subprocfunc,
																		Node *call_expr,
																		ReturnSetInfo *rsinfo,
																		Oid *resultTypeId,
																		TupleDesc *resultTupleDesc);
static TupleDesc build_subprocfunction_result_tupdesc_t(PLiSQL_subproc_function *subprocfunc);

static void plisql_subprocfunc_HashTableInsert(HTAB *hashp,
						PLiSQL_function *function,
						PLiSQL_func_hashkey *func_key);
static Node *plisql_get_subprocfunc_argdefaults(ParseState *pstate,
											PLiSQL_subproc_function *subprocfunc, int argno);
static void plisql_init_subprocfunc_compile(PLiSQL_subproc_function *subprocfunc);

static void plsql_init_glovalvar_from_stack(PLiSQL_execstate *estate, int dno,
														int *start_level);
static void plsql_assign_out_glovalvar_from_stack(PLiSQL_execstate *estate,
													int dno, int *start_level);
static bool is_subprocfunc_argnum(PLiSQL_function *pfunc, int dno);

/*
 * like plisql_start_datums
 * we init subproc function some global
 * variables
 */
void
plisql_start_subproc_func(void)
{
	int pre_level = cur_compile_func_level - 1;
	int	pre_nnested_subproc;

	if (pre_level < 0)
		pre_nnested_subproc = -1;
	else
		pre_nnested_subproc = plisql_saved_nsubprocfuncs[pre_level];

	if (pre_nnested_subproc <= 4)
		subprocFuncs_alloc = 4;
	else
	{
		subprocFuncs_alloc = 4;
		while (subprocFuncs_alloc < pre_nnested_subproc)
			subprocFuncs_alloc = subprocFuncs_alloc * 2;
	}
	plisql_nsubprocFuncs = 0;
	/* This is short-lived, so needn't allocate in function's cxt */
	plisql_subprocFuncs = MemoryContextAlloc(plisql_compile_tmp_cxt,
									sizeof(PLiSQL_subproc_function *) * subprocFuncs_alloc);
	/* init global nested subproc */
	for (plisql_nsubprocFuncs = 0; plisql_nsubprocFuncs < pre_nnested_subproc; plisql_nsubprocFuncs++)
		plisql_subprocFuncs[plisql_nsubprocFuncs] = plisql_saved_subprocfuncs[pre_level][plisql_nsubprocFuncs];
}

/*
 * like plisql_finish_datums
 * we reset some global variables
 */
void
plisql_finish_subproc_func(PLiSQL_function *function)
{
	int			i;
	int			start_subproc = function->nsubprocfuncs;

	function->nsubprocfuncs = plisql_nsubprocFuncs;

	if (plisql_nsubprocFuncs <= 0)
		return;

	/*
	 * except package specification subproc
	 */
	Assert(start_subproc <= plisql_nsubprocFuncs);
	if (start_subproc == plisql_nsubprocFuncs)
		return;
	if (start_subproc != 0)
		function->subprocfuncs = repalloc(function->subprocfuncs,
									sizeof(PLiSQL_subproc_function *) * plisql_nsubprocFuncs);
	else
		function->subprocfuncs = palloc(sizeof(PLiSQL_subproc_function *) * plisql_nsubprocFuncs);
	for (i = start_subproc; i < plisql_nsubprocFuncs; i++)
		function->subprocfuncs[i] = plisql_subprocFuncs[i];
}


/*
 * saved current level subproc function
 * global variable into stack
 */
void
plisql_push_subproc_func(void)
{
	if (cur_compile_func_level > FUNC_MAX_NEST_LEVEL - 1)
		elog(ERROR, "function or procedure nested level more than: %d", FUNC_MAX_NEST_LEVEL);

	plisql_saved_compile[cur_compile_func_level] = plisql_curr_compile;
	plisql_saved_error_funcname[cur_compile_func_level] = plisql_error_funcname;
	plisql_saved_nsubprocfuncs[cur_compile_func_level] = plisql_nsubprocFuncs;
	plisql_saved_subprocfunc_alloc[cur_compile_func_level] = subprocFuncs_alloc;
	plisql_saved_subprocfuncs[cur_compile_func_level] = plisql_subprocFuncs;
	plisql_saved_datums_last[cur_compile_func_level] = datums_last;

	cur_compile_func_level++;
}

/*
 * when subproc function compile finish
 * we recover the last global variable from
 * stack
 */
void
plisql_pop_subproc_func(void)
{
	cur_compile_func_level--;

	if (cur_compile_func_level < 0)
		elog(ERROR, "invalid nested level %d", FUNC_MAX_NEST_LEVEL);

	plisql_curr_compile = plisql_saved_compile[cur_compile_func_level];
	plisql_error_funcname = plisql_saved_error_funcname[cur_compile_func_level];
	plisql_nsubprocFuncs = plisql_saved_nsubprocfuncs[cur_compile_func_level];
	subprocFuncs_alloc = plisql_saved_subprocfunc_alloc[cur_compile_func_level];
	plisql_subprocFuncs = plisql_saved_subprocfuncs[cur_compile_func_level];
	datums_last = plisql_saved_datums_last[cur_compile_func_level];

	return;
}


/*
 * build subproc function argument variables
 */
void
plisql_build_variable_from_funcargs(PLiSQL_subproc_function *subprocfunc, bool forValidator,
												FunctionCallInfo fcinfo, int found_varno)
{
	PLiSQL_function_argitem *argitem;
	ListCell *cell;
	PLiSQL_nsitem	*nse;
	int				noutargs = 0;
	PLiSQL_variable	**outvar;
	int				i;
	int				nargs = 0;
	int				nargdefaults = 0;
	MemoryContext	oldctx;
	Oid		   *argtypes;
	char	  **argnames;
	char	   *argmodes;
	PLiSQL_variable *argvariable;
	List		*args = subprocfunc->arg;
	PLiSQL_function *function = subprocfunc->function;
	Oid rettypeid;
	Oid origrettypeid;
	HeapTuple typeTup;
	Form_pg_type typeStruct;
	char	*detailmsg;
	Oid origargtypes[FUNC_MAX_ARGS];

	if (args == NIL)
		goto no_argument;

	/*
	 * Fetch info about the procedure's parameters. Allocations aren't
	 * needed permanently, so make them in tmp cxt.
	 *
	 * We also need to resolve any polymorphic input or output
	 * argument types.  In validation mode we won't be able to, so we
	 * arbitrarily assume we are dealing with integers.
	 */
	oldctx = MemoryContextSwitchTo(plisql_compile_tmp_cxt);

	nargs = get_subprocfunc_arg_info_from_arguments(args, &argtypes, &argnames, &argmodes);
	if (nargs > FUNC_MAX_ARGS)
		ereport(ERROR,
				(errcode(ERRCODE_TOO_MANY_ARGUMENTS),
				 errmsg_plural("cannot pass more than %d argument to a function",
							   "cannot pass more than %d arguments to a function",
							   FUNC_MAX_ARGS,
							   FUNC_MAX_ARGS)));
	if (nargs > 0)
		memcpy(origargtypes, argtypes, nargs * sizeof(Oid));

	plisql_resolve_polymorphic_argtypes(nargs, argtypes, argmodes,
										 fcinfo == NULL ? NULL : fcinfo->flinfo->fn_expr,
										 forValidator,
										 plisql_error_funcname);

	outvar = (PLiSQL_variable **) palloc(sizeof(PLiSQL_variable *) * nargs);
	i = 0;
	noutargs = 0;
	nargdefaults = 0;

	MemoryContextSwitchTo(oldctx);

	foreach (cell, args)
	{
		char		buf[32];
		Oid			argtypeid = argtypes[i];
		char		argmode = argmodes ? argmodes[i] : PROARGMODE_IN;
		PLiSQL_type *argdtype;
		PLiSQL_nsitem_type argitemtype;

		argitem = (PLiSQL_function_argitem *) lfirst(cell);

		nse = plisql_ns_lookup(plisql_ns_top(), true,
							argitem->argname, NULL, NULL,
							NULL);
		if (nse != NULL)
			elog(ERROR, "duplicate declaration in function args");

		snprintf(buf, sizeof(buf), "$%d", i + 1);
		if (IsPolymorphicType(argitem->type->typoid))
			argdtype = plisql_build_datatype(argtypes[i], -1,
							function->fn_input_collation, NULL);
		else
			argdtype = argitem->type;

		/* Disallow pseudotype argument */
		/* (note we already replaced polymorphic types) */
		/* (build_variable would do this, but wrong message) */
		if (argdtype->ttype == PLISQL_TTYPE_PSEUDO)
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("PL/iSQL functions cannot accept type %s",
							format_type_be(argtypeid))));

		argvariable = plisql_build_variable((argnames &&
											  argnames[i][0] != '\0') ?
											 argnames[i] : buf,
											 0, argdtype, false);
		if (argvariable->dtype == PLISQL_DTYPE_VAR)
		{
			argitemtype = PLISQL_NSTYPE_VAR;
		}
		else
		{
			Assert(argvariable->dtype == PLISQL_DTYPE_REC);
			argitemtype = PLISQL_NSTYPE_REC;
		}
		function->fn_argvarnos[i] = argvariable->dno;

		/* Remember arguments in appropriate arrays */
		if (argmode == PROARGMODE_OUT ||
			argmode == PROARGMODE_INOUT ||
			argmode == PROARGMODE_TABLE)
			outvar[noutargs++] = argvariable;

		/* Add to namespace under the $n name */
		add_parameter_name(argitemtype, argvariable->dno, buf);

		/* If there's a name for the argument, make an alias */
		if (argnames && argnames[i][0] != '\0')
			add_parameter_name(argitemtype, argvariable->dno,
							   argnames[i]);

		if (argitem->defexpr != NULL)
		{
			PLiSQL_expr *newexpr;

			newexpr = palloc0(sizeof(PLiSQL_expr));
			memcpy(newexpr, argitem->defexpr, sizeof(PLiSQL_expr));
			if (argitem->defexpr->query != NULL)
				newexpr->query = pstrdup(argitem->defexpr->query);
			argvariable->default_val = newexpr;
		}
		else
			argvariable->default_val = NULL;

		if (argitem->defexpr != NULL)
			nargdefaults++;
		i++;
	}

	/*
	 * If there's just one OUT parameter, out_param_varno points
	 * directly to it.  If there's more than one, build a row that
	 * holds all of them.  Procedures return a row even for one OUT
	 * parameter.
	 */
	if (noutargs > 1 ||
		(noutargs == 1 && function->fn_prokind == PROKIND_PROCEDURE))
	{
		PLiSQL_row *row = build_row_from_vars(outvar,
											   noutargs);

		plisql_adddatum((PLiSQL_datum *) row);
		function->out_param_varno = row->dno;
	}
	else if (noutargs == 1)
		function->out_param_varno = outvar[0]->dno;

	pfree(outvar);

no_argument:

	/*
	 * Check for a polymorphic returntype. If found, use the actual
	 * returntype type from the caller's FuncExpr node, if we have
	 * one.  (In validation mode we arbitrarily assume we are dealing
	 * with integers.)
	 *
	 * Note: errcode is FEATURE_NOT_SUPPORTED because it should always
	 * work; if it doesn't we're in some context that fails to make
	 * the info available.
	 */
	rettypeid = subprocfunc->rettype == NULL ? VOIDOID : subprocfunc->rettype->typoid;
	origrettypeid = rettypeid;
	if (IsPolymorphicType(rettypeid))
	{
		if (forValidator)
		{
			if (rettypeid == ANYARRAYOID ||
				rettypeid == ANYCOMPATIBLEARRAYOID)
				rettypeid = INT4ARRAYOID;
			else if (rettypeid == ANYRANGEOID ||
					 rettypeid == ANYCOMPATIBLERANGEOID)
				rettypeid = INT4RANGEOID;
			else if (rettypeid == ANYMULTIRANGEOID)
				rettypeid = INT4MULTIRANGEOID;
			else		/* ANYELEMENT or ANYNONARRAY or ANYCOMPATIBLE */
				rettypeid = INT4OID;
			/* XXX what could we use for ANYENUM? */
		}
		else
		{
			rettypeid = get_fn_expr_rettype(fcinfo->flinfo);
			if (!OidIsValid(rettypeid))
				ereport(ERROR,
						(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						 errmsg("could not determine actual return type "
								"for polymorphic function \"%s\"",
								plisql_error_funcname)));
		}
	}

	/*
	 * Normal function has a defined returntype
	 */
	function->fn_rettype = rettypeid;
	function->fn_retset = false;
	function->fn_nargs = nargs;

	/*
	 * Lookup the function's return type
	 */
	typeTup = SearchSysCache1(TYPEOID, ObjectIdGetDatum(rettypeid));
	if (!HeapTupleIsValid(typeTup))
		elog(ERROR, "cache lookup failed for type %u", rettypeid);
	typeStruct = (Form_pg_type) GETSTRUCT(typeTup);

	/* Disallow pseudotype result, except VOID or RECORD */
	/* (note we already replaced polymorphic types) */
	if (typeStruct->typtype == TYPTYPE_PSEUDO)
	{
		if (rettypeid == VOIDOID ||
			rettypeid == RECORDOID)
			 /* okay */ ;
		else if (rettypeid == TRIGGEROID || rettypeid == EVENT_TRIGGEROID)
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("trigger functions can only be called as triggers")));
		else
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("PL/iSQL functions cannot return type %s",
							format_type_be(rettypeid))));
	}

	function->fn_retistuple = type_is_rowtype(rettypeid);
	function->fn_retisdomain = (typeStruct->typtype == TYPTYPE_DOMAIN);
	function->fn_retbyval = typeStruct->typbyval;
	function->fn_rettyplen = typeStruct->typlen;

	/*
	 * install $0 reference, but only for polymorphic return types,
	 * and not when the return is specified through an output
	 * parameter.
	 */
	if (subprocfunc->rettype != NULL &&
		IsPolymorphicType(subprocfunc->rettype->typoid) &&
		noutargs == 0)
	{
		(void) plisql_build_variable("$0", 0,
									  plisql_build_datatype(rettypeid,
													 -1,
													 function->fn_input_collation,
													 NULL),
									  true);
	}

	subprocfunc->nargdefaults = nargdefaults;
	subprocfunc->noutargs = noutargs;

	ReleaseSysCache(typeTup);

	/*
	 * Do not allow polymorphic return type unless there is a polymorphic
	 * input argument that we can use to deduce the actual return type.
	 */
	detailmsg = check_valid_polymorphic_signature(origrettypeid,
												  origargtypes,
												  function->fn_nargs);
	if (detailmsg)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_FUNCTION_DEFINITION),
				 errmsg("cannot determine result data type"),
				 errdetail_internal("%s", detailmsg)));

	/*
	 * Also, do not allow return type INTERNAL unless at least one input
	 * argument is INTERNAL.
	 */
	detailmsg = check_valid_internal_signature(origrettypeid,
											   origargtypes,
											   function->fn_nargs);
	if (detailmsg)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_FUNCTION_DEFINITION),
				 errmsg("unsafe use of pseudo-type \"internal\""),
				 errdetail_internal("%s", detailmsg)));

	/*
	 * Apply the same tests to any OUT arguments.
	 */
	for (i = 0; i < nargs; i++)
	{
		if (argmodes == NULL ||
			argmodes[i] == PROARGMODE_IN ||
			argmodes[i] == PROARGMODE_VARIADIC)
			continue;		/* ignore input-only params */

		detailmsg = check_valid_polymorphic_signature(origargtypes[i],
													  origargtypes,
													  nargs);
		if (detailmsg)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_FUNCTION_DEFINITION),
					 errmsg("cannot determine result data type"),
					 errdetail_internal("%s", detailmsg)));
		detailmsg = check_valid_internal_signature(origargtypes[i],
												   origargtypes,
												   nargs);
		if (detailmsg)
			ereport(ERROR,
					(errcode(ERRCODE_INVALID_FUNCTION_DEFINITION),
					 errmsg("unsafe use of pseudo-type \"internal\""),
					 errdetail_internal("%s", detailmsg)));
	}

	/* Remember if function is STABLE/IMMUTABLE */
	function->fn_readonly = false;
	function->found_varno = found_varno;

	/* there, we insert function to hashtab */
	if (subprocfunc->has_poly_argument)
	{
		PLiSQL_func_hashkey hashkey;

		/* Make sure any unused bytes of the struct are zero */
		MemSet(&hashkey, 0, sizeof(PLiSQL_func_hashkey));

		/* get function OID */
		hashkey.funcOid =  (Oid ) subprocfunc->fno;

		/* get call context */
		hashkey.isTrigger = false;
		hashkey.isEventTrigger = false;
		hashkey.trigOid = InvalidOid;

		/* get input collation, if known */
		hashkey.inputCollation = function->fn_input_collation;

		memcpy(hashkey.argtypes, argtypes,
				   nargs * sizeof(Oid));
		if (subprocfunc->poly_tab == NULL)
			subprocfunc->poly_tab = plisql_subprocfunc_HashTableInit();
		plisql_subprocfunc_HashTableInsert(subprocfunc->poly_tab, function, &hashkey);
	}

	return;
}


/*
 * set subproc function action
 * this function call must be after define a function, so we record this
 * subproc function can use subprocfunctions,datums,udttypes.
 */
void
plisql_set_subprocfunc_action(PLiSQL_subproc_function *subprocfunc,
										PLiSQL_stmt_block *action)
{
	Assert(action != NULL && subprocfunc != NULL && subprocfunc->function->action == NULL);

	subprocfunc->function->action = action;

	/* add return stmt */
	/*
	 * If it has OUT parameters or returns VOID or returns a set, we allow
	 * control to fall off the end without an explicit RETURN statement. The
	 * easiest way to implement this is to add a RETURN statement to the end
	 * of the statement list during parsing.
	 */
	if (subprocfunc->noutargs > 0 || subprocfunc->function->fn_rettype == VOIDOID ||
		subprocfunc->function->fn_retset)
		add_dummy_return(subprocfunc->function);

	return;
}

/*
 * check function properties
 */
void
plisql_check_subprocfunc_properties(PLiSQL_subproc_function *subprocfunc,
												List *properties, bool isdeclare)
{
	ListCell *lc;
	bool	has_result_cache = false;
	bool	has_deterministic = false;

	/* check result_cache match */
	foreach (lc, subprocfunc->properties)
	{
		PLiSQL_subprocfunc_proper *proper = (PLiSQL_subprocfunc_proper *) lfirst(lc);
		ListCell *dlc;
		bool found = false;
		PLiSQL_subprocfunc_proper *dproper;

		/* deterministic proper can not match */
		if (proper->proper_type != FUNC_PROPER_RESULT_CACHE)
			continue;

		foreach (dlc, properties)
		{
			dproper = (PLiSQL_subprocfunc_proper *) lfirst(dlc);
			if (dproper->proper_type == proper->proper_type)
			{
				found = true;
				break;
			}
		}
		if (!found)
			elog(ERROR, "RESULT_CACHE must be specified on \"%s\" declaration and definition",
						subprocfunc->func_name);
	}

	/* check new proper */
	foreach (lc, properties)
	{
		PLiSQL_subprocfunc_proper *proper = (PLiSQL_subprocfunc_proper *) lfirst(lc);
		bool append = true;
		ListCell *dlc;
		PLiSQL_subprocfunc_proper *dproper;

		switch (proper->proper_type)
		{
			case FUNC_PROPER_RESULT_CACHE:
				if (isdeclare && proper->value != NULL)
					elog(ERROR, "RELIES_ON clause is disallowed on function declaration");
				if (has_result_cache)
					elog(ERROR, "at most one declaration for 'RESULT_CACHE' is permitted");
				has_result_cache = true;
				break;
			case FUNC_PROPER_DETERMINISTIC:
				if (has_deterministic)
					elog(ERROR, "at most one declaration for 'DETERMINISTIC' is permitted");
				has_deterministic = true;
				break;
			case FUNC_PROPER_PARALLEL_ENABLE:
				elog(ERROR, "illegal option for subprogram \"%s\"", subprocfunc->func_name);
				break;
			case FUNC_PROPER_PIPELINED:
				elog(ERROR, "aggregate/table functions are not allowed in PLi/SQL scope");
				break;
			case PROC_PROPER_ACCESSIBLE_BY:
				elog(ERROR, "Only schema-level programs allow ACCESSIBLE BY");
				break;
			case PROC_PROPER_DEFAULT_COLLATION:
				elog(ERROR, "Only package specification, a standalone type specification, "
					"and in standalone subprograms allow default collation");
				break;
			case PROC_PROPER_INVOKER_RIGHT:
				elog(ERROR, "Only schema-level programs allow AUTHID");
				break;
			default:
				elog(ERROR, "wrong type of function proper:%d", proper->proper_type);
				break;
		}
		/* check dest properties */
		foreach (dlc, subprocfunc->properties)
		{
			dproper = (PLiSQL_subprocfunc_proper *) lfirst(dlc);
			if (dproper->proper_type == proper->proper_type)
			{
				append = false;
				break;
			}
		}

		if (append)
		{
			if (proper->proper_type == FUNC_PROPER_RESULT_CACHE &&
				(!isdeclare) && subprocfunc->has_declare)
				elog(ERROR, "RESULT_CACHE must be specified on \"%s\" declaration and definition",
							subprocfunc->func_name);

			subprocfunc->properties = lappend(subprocfunc->properties, proper);
		}
		else if (proper->value != NULL && dproper->value == NULL)
			dproper->value = proper->value;
	}

	return;
}



/*
 * build a subproc function
 * subproc function can reload and support declare and define
 * so we should check wether a subproc function is define or a
 * new function, we support more than two times declare, but
 * we don't support more than two times define.
 */
PLiSQL_subproc_function *
plisql_build_subproc_function(char *funcname, List *args,
										PLiSQL_type *rettype, int location) 
{
	PLiSQL_subproc_function *funcs;
	PLiSQL_nsitem	*nse;
	int fno;

	if (strlen(funcname) > NAMEDATALEN)
		elog(ERROR, "funcname length more than :%d", NAMEDATALEN);

	/* lookup namespace */
	nse = plisql_ns_lookup(plisql_ns_top(), true,
							funcname, NULL, NULL,
							NULL);

	if (nse != NULL)
	{
		if (nse->itemtype != PLISQL_NSTYPE_SUBPROC_FUNC &&
			nse->itemtype != PLISQL_NSTYPE_SUBPROC_PROC)
			elog(ERROR, "\"%s\" duplicate declaration", funcname);

		fno = plisql_check_function_canreload(args, nse->subprocfunc, rettype);

		if (fno != -1)
			funcs = plisql_subprocFuncs[fno];
		else
		{
			/* define new function */
			funcs = plisql_build_subproc_function_internal(funcname, args, rettype, false, location); 
			nse->subprocfunc = lappend_int(nse->subprocfunc, funcs->fno);
		}
	}
	else
	{
		funcs = plisql_build_subproc_function_internal(funcname, args, rettype, true, location); 
		/* init subproc func hash tab */
		nse = plisql_ns_top();
		Assert(nse->itemno == funcs->fno);
		nse->subprocfunc = lappend_int(nse->subprocfunc, funcs->fno);
	}

	return funcs;
}

/*
 * add a new subprocfunction to global subprocfunctions var
 */
void
plisql_add_subproc_function(PLiSQL_subproc_function *new)
{
	if (plisql_nsubprocFuncs == subprocFuncs_alloc)
	{
		subprocFuncs_alloc *= 2;
		plisql_subprocFuncs = repalloc(plisql_subprocFuncs, sizeof(PLiSQL_subproc_function *) *
														subprocFuncs_alloc);
	}

	new->fno = plisql_nsubprocFuncs;
	plisql_subprocFuncs[plisql_nsubprocFuncs++] = new;
}


/*
 * register some usefull functions
 * for SQL to used
 */
void
plisql_register_internal_func(void)
{
	if (plisql_internal_funcs.isload)
		return;
	plisql_internal_funcs.get_internal_func_result_tupdesc = plisql_get_func_result_tupdesc;
	plisql_internal_funcs.get_internal_func_name = plisql_get_func_name;
	plisql_internal_funcs.get_internal_func_result_type = plisql_get_subprocfunc_result_type;
	plisql_internal_funcs.get_internal_func_outargs = plisql_get_subprocfunc_outargs;
	plisql_internal_funcs.get_inernal_func_result_name = plisql_get_subprocfunc_result_name;
	plisql_internal_funcs.package_validator = plisql_package_validator;
	plisql_internal_funcs.package_handle = plisql_package_handle;
	plisql_internal_funcs.package_parse = plisql_package_parse;
	plisql_internal_funcs.package_free_list = plisql_free_packagelist;
	plisql_internal_funcs.get_top_function_id = plisql_top_functin_oid;
	plisql_internal_funcs.package_free = plisql_free_package_function;
	plisql_internal_funcs.get_subprocs_from_package = plisql_get_subprocs_from_package;

	plisql_internal_funcs.isload = true;
}


/*
 * unrgister some usefull functions from SQL
 */
void
plisql_unregister_internal_func(void)
{
	plisql_internal_funcs.isload = false;
}


/*
 * get TupleDesc from internel function
 */
TupleDesc
plisql_get_func_result_tupdesc(FuncExpr *fexpr)
{
	PLiSQL_function *function;
	PLiSQL_subproc_function *subprocfunc;

	if (FUNC_EXPR_FROM_PG_PROC(fexpr->function_from))
		elog(ERROR, "FuncExpr is not a internal function");

	if (fexpr->parent_func == NULL)
		elog(ERROR, "parent_func has not set");

	function = (PLiSQL_function *) fexpr->parent_func;

	if (fexpr->funcid < 0 || fexpr->funcid >= function->nsubprocfuncs)
		elog(ERROR, "invalid fno %d", fexpr->funcid);

	subprocfunc = function->subprocfuncs[fexpr->funcid];

	return build_subprocfunction_result_tupdesc_t(subprocfunc);
}

/*
 * like get_func_arg_info
 * we get subprocfunc arg info
 */
int
get_subprocfunc_arg_info(FuncExpr *funcexpr, Oid **p_argtypes,
									char ***p_argnames, char **p_argmodes)
{
	PLiSQL_function *function;
	PLiSQL_subproc_function *subprocfunc;

	if (FUNC_EXPR_FROM_PG_PROC(funcexpr->function_from))
		elog(ERROR, "FuncExpr is not a internal function");

	if (funcexpr->parent_func == NULL)
		elog(ERROR, "parent_func has not set");

	function = (PLiSQL_function *) funcexpr->parent_func;

	if (funcexpr->funcid < 0 || funcexpr->funcid >= function->nsubprocfuncs)
		elog(ERROR, "invalid fno %d", funcexpr->funcid);

	subprocfunc = function->subprocfuncs[funcexpr->funcid];

	return get_subprocfunc_arg_info_from_arguments(subprocfunc->arg, p_argtypes,
												p_argnames, p_argmodes);

}
/*
 * get subproc function name
 * from FuncExpr
 */
char *
plisql_get_func_name(FuncExpr *fexpr)
{
	PLiSQL_function *function;
	PLiSQL_subproc_function *subprocfunc;

	if (FUNC_EXPR_FROM_PG_PROC(fexpr->function_from))
		elog(ERROR, "FuncExpr is not a internal function");

	if (fexpr->parent_func == NULL)
		return NULL;

	function = (PLiSQL_function *) fexpr->parent_func;

	if (fexpr->funcid < 0 || fexpr->funcid >= function->nsubprocfuncs)
		elog(ERROR, "invalid fno %d", fexpr->funcid);

	subprocfunc = function->subprocfuncs[fexpr->funcid];

	return subprocfunc->func_name;
}


/*
 * like get_call_result_type
 * we build subproc function result type
 */
TypeFuncClass
plisql_get_subprocfunc_result_type(FuncExpr *fexpr,
						 ReturnSetInfo *rsinfo,
						 Oid *resultTypeId,
						 TupleDesc *resultTupleDesc)
{
	PLiSQL_function *function;
	PLiSQL_subproc_function *subprocfunc;

	if (FUNC_EXPR_FROM_PG_PROC(fexpr->function_from))
		elog(ERROR, "FuncExpr is not a internal function");

	if (fexpr->parent_func == NULL)
		elog(ERROR, "parent_func has not set");

	function = (PLiSQL_function *) fexpr->parent_func;

	if (fexpr->funcid < 0 || fexpr->funcid >= function->nsubprocfuncs)
		elog(ERROR, "invalid fno %d", fexpr->funcid);

	subprocfunc = function->subprocfuncs[fexpr->funcid];

	return internal_get_subprocfunc_result_type(subprocfunc,
									(Node *) fexpr,
									rsinfo,
									resultTypeId,
									resultTupleDesc);
}


/*
 * return out arglist for subprocfunction
 * see details for transformCallStmt
 */
List *
plisql_get_subprocfunc_outargs(FuncExpr *fexpr)
{
	PLiSQL_function *function;
	PLiSQL_subproc_function *subprocfunc;
	ListCell *lc;
	List *outargs = NIL;
	int i = 0;

	if (FUNC_EXPR_FROM_PG_PROC(fexpr->function_from))
		elog(ERROR, "FuncExpr is not a internal function");

	if (fexpr->parent_func == NULL)
		elog(ERROR, "parent_func has not set");

	function = (PLiSQL_function *) fexpr->parent_func;

	if (fexpr->funcid < 0 || fexpr->funcid >= function->nsubprocfuncs)
		elog(ERROR, "invalid fno %d", fexpr->funcid);

	subprocfunc = function->subprocfuncs[fexpr->funcid];

	foreach (lc, subprocfunc->arg)
	{
		PLiSQL_function_argitem *argitem = (PLiSQL_function_argitem *) lfirst(lc);

		if (argitem->argmode == ARGMODE_OUT ||
			argitem->argmode == ARGMODE_INOUT)
		{
			outargs = lappend(outargs, copyObject(list_nth(fexpr->args, i)));
		}
		i++;
	}
	return outargs;
}


/*
 * like get_func_result_name
 * we return subproc func result name
 */
char *
plisql_get_subprocfunc_result_name(FuncExpr *fexpr)
{
	PLiSQL_function *function;
	PLiSQL_subproc_function *subprocfunc;
	ListCell *lc;

	if (FUNC_EXPR_FROM_PG_PROC(fexpr->function_from))
		elog(ERROR, "FuncExpr is not a internal function");

	if (fexpr->parent_func == NULL)
		elog(ERROR, "parent_func has not set");

	function = (PLiSQL_function *) fexpr->parent_func;

	if (fexpr->funcid < 0 || fexpr->funcid >= function->nsubprocfuncs)
		elog(ERROR, "invalid fno %d", fexpr->funcid);

	subprocfunc = function->subprocfuncs[fexpr->funcid];

	if (subprocfunc->noutargs != 1)
		return NULL;

	foreach (lc, subprocfunc->arg)
	{
		PLiSQL_function_argitem *argitem = (PLiSQL_function_argitem *) lfirst(lc);

		if (argitem->argmode == ARGMODE_OUT ||
			argitem->argmode == ARGMODE_INOUT)
		{
			return pstrdup(argitem->argname);
		}
	}
	return NULL;
}

/*
 * decide where the function
 * come from
 */
char
plisql_function_from(FunctionCallInfo fcinfo)
{
	FuncExpr *funexpr;

	if (fcinfo->flinfo == NULL || fcinfo->flinfo->fn_expr == NULL)
		return FUNC_FROM_PG_PROC;

	funexpr = (FuncExpr *) fcinfo->flinfo->fn_expr;

	if (nodeTag(funexpr) != T_FuncExpr)
		return FUNC_FROM_PG_PROC;

	return funexpr->function_from;
}


/*
 * get subproc func for call stmt
 */
PLiSQL_function *
plisql_get_subproc_func(FunctionCallInfo fcinfo, bool forValidator)
{
	PLiSQL_execstate *estate;
	PLiSQL_function *pfunc;
	PLiSQL_subproc_function *subprocfunc;
	FuncExpr *funcexpr;
	int	fno;
	PLiSQL_function *func;

	funcexpr = (FuncExpr *) fcinfo->flinfo->fn_expr;

	Assert(funcexpr->function_from == FUNC_FROM_SUBPROCFUNC);


	pfunc = (PLiSQL_function *) funcexpr->parent_func;

	if (pfunc == NULL)
		elog(ERROR, "subproc funcexpr has no init");

	estate = pfunc->cur_estate;
	fno = (int) funcexpr->funcid;

	if (estate == NULL)
		elog(ERROR, "subproc func estate is null");

	if (fno < 0 || fno >= pfunc->nsubprocfuncs)
		elog(ERROR, "invalid fno :%d", fno);

	subprocfunc = pfunc->subprocfuncs[fno];

	/* if not have poly arguments */
	if (subprocfunc->has_poly_argument)
	{
		int nargs;
		Oid *argtypes;
		char **argnames;
		char *argmodes;
		PLiSQL_func_hashkey hashkey;

		/* origin has no define */
		if (subprocfunc->function->action == NULL)
			elog(ERROR, "subproc function \"%s\" doesn't define",
				subprocfunc->func_name); 


		Assert(subprocfunc->poly_tab != NULL);

		nargs = get_subprocfunc_arg_info_from_arguments(subprocfunc->arg, &argtypes, &argnames, &argmodes);
		plisql_resolve_polymorphic_argtypes(nargs, argtypes, argmodes,
										 fcinfo->flinfo->fn_expr,
										 forValidator,
										 subprocfunc->func_name);

		/* Make sure any unused bytes of the struct are zero */
		MemSet(&hashkey, 0, sizeof(PLiSQL_func_hashkey));

		/* get function OID */
		hashkey.funcOid =  (Oid ) subprocfunc->fno;

		/* get call context */
		hashkey.isTrigger = false;
		hashkey.isEventTrigger = false;
		hashkey.trigOid = InvalidOid;

		/* get input collation, if known */
		hashkey.inputCollation = fcinfo->fncollation;;

		memcpy(hashkey.argtypes, argtypes,
				   nargs * sizeof(Oid));
		func = plisql_subprocfunc_HashTableLookup(subprocfunc->poly_tab, &hashkey);
		if (func == NULL)
		{
			/* function is not found, we shoud dynamic compile */
			Assert(subprocfunc->src != NULL);
			func = plisql_dynamic_compile_subproc(fcinfo, subprocfunc, forValidator);
		}
	}
	else
		func = subprocfunc->function;

	if (func->action == NULL)
		elog(ERROR, "subproc function \"%s\" doesn't define",
			func->fn_signature); 

	return func;
}

/*
 * this function init subprocfunction variable by its parent'variable value
 */
void
plisql_init_subprocfunc_globalvar(PLiSQL_execstate *estate, FunctionCallInfo fcinfo)
{
	PLiSQL_function *pfunc;
	PLiSQL_execstate *parestate;
	PLiSQL_subproc_function *subprocfunc;
	int			fno;
	int			i;
	FuncExpr	*funcexpr;
	int start_level = -1;

	funcexpr = (FuncExpr *) fcinfo->flinfo->fn_expr;
	Assert(funcexpr->function_from == FUNC_FROM_SUBPROCFUNC);

	fno = (int) funcexpr->funcid;
	pfunc = (PLiSQL_function *) funcexpr->parent_func;
	parestate = pfunc->cur_estate;

	Assert(parestate != NULL);
	Assert(fno >= 0 && fno < pfunc->nsubprocfuncs);

	subprocfunc = pfunc->subprocfuncs[fno];

	for (i = 0; i < subprocfunc->lastassignvardno; i++)
	{
		/* ignore package datum*/
		if (estate->datums[i]->dtype == PLISQL_DTYPE_PACKAGE_DATUM ||
			OidIsValid(estate->datums[i]->pkgoid))
			continue;

		if (is_const_datum(estate, estate->datums[i]))
			continue;

		/* ignore row variable which is internal */
		if (estate->datums[i]->dtype == PLISQL_DTYPE_ROW)
			continue;

		/* ignore some datums, which need not assign */
		if (is_subprocfunc_argnum(pfunc, i))
			continue;

		if (i < parestate->ndatums)
		{
			plisql_assign_in_global_var(estate, parestate, i);
		}
		else
		{
			if (start_level == -1)
				start_level = SPI_get_connected() - 1;
			plsql_init_glovalvar_from_stack(estate, i, &start_level);
		}
	}

	return;
}


/*
 * this function, when global variable is changed
 * we should assign its near out parent
 */
void
plisql_assign_out_subprocfunc_globalvar(PLiSQL_execstate *estate,
													FunctionCallInfo fcinfo)
{
	PLiSQL_function *pfunc;
	PLiSQL_execstate *parestate;
	PLiSQL_subproc_function *subprocfunc;
	int			fno;
	int			i;
	FuncExpr	*funcexpr;
	int start_level = -1;

	funcexpr = (FuncExpr *) fcinfo->flinfo->fn_expr;
	Assert(funcexpr->function_from == FUNC_FROM_SUBPROCFUNC);

	fno = (int) funcexpr->funcid;
	pfunc = (PLiSQL_function *) funcexpr->parent_func;
	parestate = pfunc->cur_estate;

	Assert(parestate != NULL);
	Assert(fno >= 0 && fno < pfunc->nsubprocfuncs);

	subprocfunc = pfunc->subprocfuncs[fno];

	for (i = 0; i < subprocfunc->lastassignvardno; i++)
	{
		/* ignore package datum*/
		if (estate->datums[i]->dtype == PLISQL_DTYPE_PACKAGE_DATUM ||
			OidIsValid(estate->datums[i]->pkgoid))
			continue;

		if (is_const_datum(estate, estate->datums[i]))
			continue;

		/* ignore row variable which is internal */
		if (estate->datums[i]->dtype == PLISQL_DTYPE_ROW)
			continue;

		/* ignore some datums, which need not assign */
		if (is_subprocfunc_argnum(pfunc, i))
			continue;

		if (i < parestate->ndatums)
			plisql_assign_out_global_var(estate, parestate, i, SPI_get_connected() - 1);
		else
		{
			if (start_level == -1)
				start_level = SPI_get_connected() - 1;
			plsql_assign_out_glovalvar_from_stack(estate, i, &start_level);
		}
	}

	return;
}


/*
 * init subproc function for arg has polymorphic
 * this hash table like plisql_HashTable
 */
static HTAB *
plisql_subprocfunc_HashTableInit(void)
{
	HASHCTL		ctl;
	HTAB		*htab;

	ctl.keysize = sizeof(PLiSQL_func_hashkey);
	ctl.entrysize = sizeof(plisql_HashEnt);
	ctl.hcxt= CurrentMemoryContext;

	htab = hash_create("PLiSQL subprocfunction hash for polyarg",
									128,
									&ctl,
									HASH_ELEM | HASH_BLOBS|HASH_CONTEXT);

	return htab;
}


/*
 * plsql_get_subprocfunc_detail like func_get_detail
 * but we get function details from subprocfunc
 */
FuncDetailCode
plisql_get_subprocfunc_detail(ParseState *pstate,
											PLiSQL_function *pfunc, PLiSQL_nsitem *nse,
											char *funcname, List **fargs, /* return value */
											bool proc_call,
											List *fargnames,
											int nargs,
											Oid *argtypes,
											Oid *funcid,	/* return value */
											Oid *rettype,	/* return value */
											bool *retset,	/* return value */
											int *nvargs,	/* return value */
											Oid *vatype,	/* return value */
											Oid **true_typeids, /* return value */
											List **argdefaults) /* return value */
{
	subprocFuncCandidateList raw_candidates;
	subprocFuncCandidateList best_candidate = NULL;
	subprocFuncCandidateList tmp_candidate;
	int						nbest;

	/* initialize output arguments to silence compiler warnings */
	*funcid = InvalidOid;
	*rettype = InvalidOid;
	*retset = false;
	*nvargs = 0;
	*vatype = InvalidOid;
	*true_typeids = NULL;
	if (argdefaults)
		*argdefaults = NIL;

	raw_candidates = plisql_getFuncCandidateListFromFunname(funcname, pfunc, nse, nargs, fargnames, proc_call);

	if (raw_candidates == NULL)
		return FUNCDETAIL_NOTFOUND;

	/*
	 * Quickly check if there is an exact match to the input datatypes (there
	 * can be only one)
	 */
	nbest = 0;
	for (tmp_candidate = raw_candidates;
		tmp_candidate != NULL;
		tmp_candidate = tmp_candidate->next)
	{
		/* if nargs==0, argtypes can be null; don't pass that to memcmp */
		if (nargs == 0 ||
			memcmp(argtypes, tmp_candidate->args, nargs * sizeof(Oid)) == 0)
		{
			nbest++;
			best_candidate = tmp_candidate;
		}
	}
	if (nbest > 1)
		elog(ERROR, "%d functions or procedures match this call", nbest);

	if (best_candidate == NULL)
	{
		subprocFuncCandidateList current_candidates;
		int 		ncandidates;

		ncandidates = plisql_func_match_argtypes(nargs,
										argtypes,
										raw_candidates,
										&current_candidates);

		/* one match only? then run with it... */
		if (ncandidates == 1)
			best_candidate = current_candidates;

		/*
		 * multiple candidates? then better decide or throw an error...
		 */
		else if (ncandidates > 1)
		{
			best_candidate = plisql_func_select_candidate(nargs,
												argtypes,
												current_candidates);

			/*
			 * If we were able to choose a best candidate, we're done.
			 * Otherwise, ambiguous function call.
			 */
			if (!best_candidate)
				elog(ERROR, "more than one functions or procedures match this call");
		}
	}
	if (best_candidate)
	{
		PLiSQL_subproc_function *subprocfunc;
		List *defaultnumber = NIL;

		subprocfunc = pfunc->subprocfuncs[best_candidate->fno];

		*funcid = subprocfunc->fno;
		*true_typeids = best_candidate->args;
		if (subprocfunc->rettype != NULL)
			*rettype = subprocfunc->rettype->typoid;
		else
			*rettype = VOIDOID;
		*retset = subprocfunc->function->fn_retset;

		if (best_candidate->argnumbers != NULL)
		{
			int 		i = 0;
			ListCell   *lc;

			foreach(lc, *fargs)
			{
				NamedArgExpr *na = (NamedArgExpr *) lfirst(lc);

				if (IsA(na, NamedArgExpr))
					na->argnumber = best_candidate->argnumbers[i];
				i++;
			}
		}
		/* saved defualt argnumber */
		if (argdefaults && best_candidate->ndargs > 0)
		{
			int i;
			/* saved default */
			if (best_candidate->argnumbers != NULL)
			{
				for (i = nargs; i < best_candidate->nargs; i++)
					defaultnumber = lappend_int(defaultnumber, best_candidate->argnumbers[i]);
			}
			else
			{
				for (i = nargs; i < best_candidate->nargs; i++)
					defaultnumber = lappend_int(defaultnumber, i);
			}
		}
		if (fargnames != NIL || defaultnumber != NIL)
			*fargs = plisql_expand_and_reorder_functionargs(pstate, subprocfunc, best_candidate->nargs,
									*fargs, defaultnumber, argdefaults);

		if (subprocfunc->is_proc)
			return FUNCDETAIL_PROCEDURE;
		else
			return FUNCDETAIL_NORMAL;

	}

	return FUNCDETAIL_NOTFOUND;
}



/*
 * check subproc function can reload
 * 1) different number of arguments
 * 2) different arguments'name
 * 3) different arguments'oid
 * 4) if arguments are udt type, but its types is different
 * 5) as define or declare we allow the rettype is not different
 * as long as meet one of the above five conditions, then
 * subproc function can reload.
 */
static int
plisql_check_function_canreload(List *args,
							List *fnos, PLiSQL_type *rettype)
{
	int resultfno = -1;
	ListCell *lc;

	foreach (lc, fnos)
	{
		int fno;
		PLiSQL_subproc_function *subprocfunc;
		ListCell *cell1;
		ListCell *cell2;
		bool	canreload = false;

		fno = lfirst_int(lc);

		if (fno < 0 || fno >= plisql_nsubprocFuncs)
			elog(ERROR, "invalid fno :%d", fno);

		subprocfunc = plisql_subprocFuncs[fno];

		/* compare nargs */
		if (list_length(args) != list_length(subprocfunc->arg))
			continue;

		/* compare rettype */
		if (rettype != NULL &&
			subprocfunc->rettype != NULL &&
			rettype->typoid != subprocfunc->rettype->typoid)
			continue;

		/* procedure and function call reload */
		if (rettype != NULL &&
			subprocfunc->rettype == NULL)
			continue;

		if (rettype == NULL &&
			subprocfunc->rettype != NULL)
			continue;

		/* compare arg item */
		forboth(cell1, args, cell2, subprocfunc->arg)
		{
			PLiSQL_function_argitem *srcitem;
			PLiSQL_function_argitem *dstitem;

			srcitem = lfirst(cell1);
			dstitem = lfirst(cell2);

			/* argname doesn't consistent */
			if (strcmp(srcitem->argname, dstitem->argname) != 0)
			{
				canreload = true;
				break;
			}

			/* compare type oid */
			if (srcitem->type->typoid != dstitem->type->typoid)
				canreload = true;

			if (canreload)
				break;
		}
		if (canreload)
			continue;

		/* all args match */
		if (subprocfunc->function->action != NULL)
			elog(ERROR, "function or procedure \"%s\" has already define", subprocfunc->func_name);

		if (resultfno != -1)
			elog(ERROR, "more than one function or procedure \"%s\" match", subprocfunc->func_name);
		resultfno = fno;
	}

	return resultfno;
}

/*
 * like plisql_build_variable
 *
 * this function build a subproc function and add it to namespace
 */
static PLiSQL_subproc_function *
plisql_build_subproc_function_internal(char *funcname, List *args,
													PLiSQL_type *rettype,
													bool add2namespace,
													int location) 
{
	PLiSQL_subproc_function *funcs;
	bool is_proc = (rettype == NULL ? true : false);
	PLiSQL_function *function;
	bool		has_poly_argument = false;
	MemoryContext func_cxt = plisql_curr_compile->fn_cxt;

	funcs = (PLiSQL_subproc_function *) palloc0(sizeof(PLiSQL_subproc_function));
	funcs->function = (PLiSQL_function *) palloc0(sizeof(PLiSQL_function));
	function = funcs->function;

	funcs->func_name = pstrdup(funcname);
	funcs->arg = args;
	funcs->nargdefaults = 0;
	funcs->rettype = rettype;
	funcs->has_declare = false;
	funcs->is_proc = is_proc;

	function->fn_signature = quote_qualified_identifier(NULL, funcname);
	function->fn_input_collation = plisql_curr_compile->fn_input_collation;
	function->fn_cxt = func_cxt;
	function->out_param_varno = -1; /* set up for no OUT param */
	function->resolve_option = plisql_curr_compile->resolve_option;
	function->print_strict_params = plisql_curr_compile->print_strict_params;
	/* only promote extra warnings and errors at CREATE FUNCTION time */
	function->extra_warnings = plisql_curr_compile->extra_warnings;
	function->extra_errors = plisql_curr_compile->extra_errors;

	function->fn_is_trigger = plisql_curr_compile->fn_is_trigger;

	function->nstatements = 0;
	function->requires_procedure_resowner = false;

	if (is_proc)
		function->fn_prokind = PROKIND_PROCEDURE;
	else
		function->fn_prokind = PROKIND_FUNCTION;

	function->fn_nargs = list_length(args);

	/*
	 * when parse a package function
	 * we don't compile package body
	 * but parse shoud use its argument defaults
	 * so we there record its defaults arguments
	 */
	if (args != NIL)
	{
		PLiSQL_function_argitem *argitem;
		ListCell *lc;

		if (list_length(args) > FUNC_MAX_ARGS)
			ereport(ERROR,
				(errcode(ERRCODE_TOO_MANY_ARGUMENTS),
			 errmsg_plural("cannot pass more than %d argument to a function or procedure",
						   "cannot pass more than %d arguments to a function or procedure",
						   FUNC_MAX_ARGS,
						   FUNC_MAX_ARGS),
				 parser_errposition(NULL, -1)));

		foreach (lc, args)
		{
			argitem = (PLiSQL_function_argitem *) lfirst(lc);

			if (argitem->defexpr != NULL)
				funcs->nargdefaults++;
			if (IsPolymorphicType(argitem->type->typoid))
				has_poly_argument = true;
		}
	}

	plisql_add_subproc_function(funcs);
	if (add2namespace)
	{
		if (is_proc)
			plisql_ns_additem(PLISQL_NSTYPE_SUBPROC_PROC,
							funcs->fno,
							funcname);
		else
			plisql_ns_additem(PLISQL_NSTYPE_SUBPROC_FUNC,
							funcs->fno,
							funcname);
	}
	funcs->has_poly_argument = has_poly_argument;

	/* if it comes from a package, record its PackageCacheItem */
	funcs->function->item = plisql_curr_compile->item;
	funcs->function->fn_oid = plisql_curr_compile->fn_oid;
	funcs->function->namelabel = pstrdup(funcname);
	funcs->location = location;

	return funcs;
}

/*
 * like MatchNamedCallFromFuncInfo
 * we map the NameCall to its argument position'number
 */
static bool
plisql_match_function_argnames(List *funcargs, int nargs,
										List *argnames, int **argnumber)
{
	int nnameargs;
	ListCell *lc;
	int	j;
	bool	*found = NULL;
	int		funcnargs;
	int		position_nargs;

	if (argnumber)
		*argnumber = NULL;

	funcnargs = list_length(funcargs);
	nnameargs = list_length(argnames);
	*argnumber = (int *) palloc(sizeof(int) * funcnargs);
	found = (bool *) palloc0(sizeof(bool) * funcnargs);

	position_nargs = nargs - nnameargs;
	for (j = 0; j < position_nargs; j++)
	{
		found[j] = true;
		(*argnumber)[j] = j;
	}

	foreach(lc, argnames)
	{
		char	   *argname = (char *) lfirst(lc);
		ListCell	*flc;
		int			i = 0;
		bool		match = false;

		foreach(flc, funcargs)
		{
			PLiSQL_function_argitem *argitem = (PLiSQL_function_argitem *) lfirst(flc);

			if (strcmp(argname, argitem->argname) == 0 && !found[i])
			{
				(*argnumber)[j] = i;
				found[i] = true;
				match = true;
				break;
			}
			i++;
		}
		if (!match)
		{
			pfree(*argnumber);
			pfree(found);
			*argnumber = NULL;
			return false;
		}
		j++;
	}

	Assert(j == nargs);
	/* find default value argnum */
	if (j < funcnargs)
	{
		for (; j < funcnargs; j++)
		{
			bool match = false;
			int i;

			for (i = 0; i < funcnargs; i++)
			{
				if (!found[i])
				{
					PLiSQL_function_argitem *argitem = (PLiSQL_function_argitem *) list_nth(funcargs, i);

					if (argitem->defexpr == NULL)
					{
						pfree(*argnumber);
						pfree(found);
						*argnumber = NULL;
						return false;
					}
					(*argnumber)[j] = i;
					found[i] = true;
					match = true;
					break;
				}
			}
			if (!match)
			{
				pfree(*argnumber);
				pfree(found);
				*argnumber = NULL;
				return false;
			}
		}
	}
	pfree(found);
	return true;
}

/*
 * like FuncnameGetCandidates
 * but we get function list from hashtab
 */
static subprocFuncCandidateList
plisql_getFuncCandidateListFromFunname(char *funcname, PLiSQL_function *pfunc,
													PLiSQL_nsitem *nse, int nargs,
													List *fargnames, bool proc_call)
{
	ListCell *lc;
	subprocFuncCandidateList resultList = NULL;

	foreach(lc, nse->subprocfunc)
	{
		PLiSQL_subproc_function *subprocfunc = NULL;
		List *args;
		ListCell	*l;
		int i;
		Oid *argoids = NULL;
		int *argnumber = NULL;
		char *argmode = NULL;
		int declare_nargs;
		int fno;
		subprocFuncCandidateList newResult;

		fno = lfirst_int(lc);

		if (fno < 0 || fno >= pfunc->nsubprocfuncs)
			elog(ERROR, "invalid fno :%d", fno);

		subprocfunc = pfunc->subprocfuncs[fno];
		args = subprocfunc->arg;
		declare_nargs = list_length(args);

		/* only find procedure */
		if (proc_call && !subprocfunc->is_proc)
			continue;

		/* only find function */
		if (!proc_call && subprocfunc->is_proc)
			continue;

		if (declare_nargs < nargs)
			continue;
		else if (declare_nargs == nargs ||
			declare_nargs <= nargs + subprocfunc->nargdefaults)
		{
			/* argname match */
			if (fargnames != NULL)
			{
				if (!plisql_match_function_argnames(args, nargs,
						fargnames, &argnumber))
					continue;
			}
			if (declare_nargs > nargs)
			{
				/* check argdefault */
				bool default_match = true;
				if (argnumber == NULL)
				{
					for (i = nargs; i < declare_nargs; i++)
					{
						PLiSQL_function_argitem *argitem;

						argitem = (PLiSQL_function_argitem *) list_nth(subprocfunc->arg, i);
						if (argitem->defexpr == NULL)
						{
							default_match = false;
							break;
						}
					}
				}
				if (!default_match)
				{
					if (argnumber)
						pfree(argnumber);
					continue;
				}
			}
			/* argtype match */
			if (declare_nargs > 0)
			{
				argoids = (Oid *) palloc(declare_nargs * sizeof(Oid));
				argmode = (char *) palloc(declare_nargs * sizeof(char));
			}

			i = 0;
			foreach(l, args)
			{
				PLiSQL_function_argitem *argitem = lfirst(l);

				argoids[i] = argitem->type->typoid;
				if (argitem->argmode == ARGMODE_IN)
					argmode[i++] =  FUNC_PARAM_IN;
				else if (argitem->argmode == ARGMODE_OUT)
					argmode[i++] = FUNC_PARAM_OUT;
				else
					argmode[i++] = FUNC_PARAM_INOUT;
			}

			if (argnumber != NULL)
			{
				Oid *using_oid = palloc(declare_nargs * sizeof(Oid));
				char *using_mode = palloc(declare_nargs * sizeof(char));

				for (i = 0; i < declare_nargs; i++)
				{
					using_oid[i] = argoids[argnumber[i]];
					using_mode[i] = argmode[argnumber[i]];
				}
				pfree(argoids);
				argoids = using_oid;
				pfree(argmode);
				argmode = using_mode;
			}
			newResult = (subprocFuncCandidateList)
				palloc(offsetof(struct _subprocFuncCandidateList, args) + declare_nargs * sizeof(Oid));
			newResult->argnumbers = argnumber;
			newResult->fno = subprocfunc->fno;
			newResult->nargs = declare_nargs;
			newResult->ndargs = declare_nargs - nargs;
			newResult->argmodes = argmode;
			if (newResult->nargs > 0)
			{
				memcpy(newResult->args, argoids, declare_nargs * sizeof(Oid));
				pfree(argoids);
			}
			newResult->next = resultList;
			resultList = newResult;
		}
	}

	/* nice error report */
	if (resultList == NULL && list_length(nse->subprocfunc) == 1)
	{
		int fno = linitial_int(nse->subprocfunc);
		PLiSQL_subproc_function *subprocfunc = pfunc->subprocfuncs[fno];

		if (proc_call && !subprocfunc->is_proc)
			ereport(ERROR,
					(errcode(ERRCODE_WRONG_OBJECT_TYPE),
					errmsg("'%s' is not a procedure",
					funcname),
					errhint("To call a function, use SELECT.")));
		else if (!proc_call && subprocfunc->is_proc)
			ereport(ERROR,
					(errcode(ERRCODE_WRONG_OBJECT_TYPE),
					errmsg("'%s' is a procedure", funcname),
					errhint("To call a procedure, use CALL.")));
	}

	return resultList;
}


/*
 * like func_match_argtypes()
 *
 */
static int
plisql_func_match_argtypes(int nargs,
					Oid *input_typeids,
					subprocFuncCandidateList raw_candidates,
					subprocFuncCandidateList *candidates)		/* return value */
{
	subprocFuncCandidateList current_candidate;
	subprocFuncCandidateList next_candidate;
	int			ncandidates = 0;

	*candidates = NULL;

	for (current_candidate = raw_candidates;
		 current_candidate != NULL;
		 current_candidate = next_candidate)
	{
		next_candidate = current_candidate->next;
		if (can_coerce_type(nargs, input_typeids, current_candidate->args,
							COERCION_IMPLICIT))
		{
			current_candidate->next = *candidates;
			*candidates = current_candidate;
			ncandidates++;
		}
	}

	return ncandidates;
}	/* plisql_func_match_argtypes() */



/*
 * like func_selec_candidate
 */
static subprocFuncCandidateList
plisql_func_select_candidate(int nargs,
					  Oid *input_typeids,
					  subprocFuncCandidateList candidates)
{
	subprocFuncCandidateList current_candidate,
				first_candidate,
				last_candidate;
	Oid		   *current_typeids;
	Oid			current_type;
	int			i;
	int			ncandidates;
	int			nbestMatch,
				nmatch,
				nunknowns;
	Oid			input_base_typeids[FUNC_MAX_ARGS];
	TYPCATEGORY slot_category[FUNC_MAX_ARGS],
				current_category;
	bool		current_is_preferred;
	bool		slot_has_preferred_type[FUNC_MAX_ARGS];
	bool		resolved_unknowns;

	/* protect local fixed-size arrays */
	if (nargs > FUNC_MAX_ARGS)
		ereport(ERROR,
				(errcode(ERRCODE_TOO_MANY_ARGUMENTS),
			 errmsg_plural("cannot pass more than %d argument to a function",
						   "cannot pass more than %d arguments to a function",
						   FUNC_MAX_ARGS,
						   FUNC_MAX_ARGS)));

	/*
	 * If any input types are domains, reduce them to their base types. This
	 * ensures that we will consider functions on the base type to be "exact
	 * matches" in the exact-match heuristic; it also makes it possible to do
	 * something useful with the type-category heuristics. Note that this
	 * makes it difficult, but not impossible, to use functions declared to
	 * take a domain as an input datatype.  Such a function will be selected
	 * over the base-type function only if it is an exact match at all
	 * argument positions, and so was already chosen by our caller.
	 *
	 * While we're at it, count the number of unknown-type arguments for use
	 * later.
	 */
	nunknowns = 0;
	for (i = 0; i < nargs; i++)
	{
		if (input_typeids[i] != UNKNOWNOID)
			input_base_typeids[i] = getBaseType(input_typeids[i]);
		else
		{
			/* no need to call getBaseType on UNKNOWNOID */
			input_base_typeids[i] = UNKNOWNOID;
			nunknowns++;
		}
	}

	/*
	 * Run through all candidates and keep those with the most matches on
	 * exact types. Keep all candidates if none match.
	 */
	ncandidates = 0;
	nbestMatch = 0;
	first_candidate = NULL;		/* ReqID:SRS-GKC-DATATYPE_001 */
	last_candidate = NULL;
	for (current_candidate = candidates;
		 current_candidate != NULL;
		 current_candidate = current_candidate->next)
	{
		current_typeids = current_candidate->args;
		nmatch = 0;
		for (i = 0; i < nargs; i++)
		{
			if (input_base_typeids[i] != UNKNOWNOID &&
				current_typeids[i] == input_base_typeids[i])
				nmatch++;
		}

		/* take this one as the best choice so far? */
		if ((nmatch > nbestMatch) || (last_candidate == NULL))
		{
			nbestMatch = nmatch;
			candidates = current_candidate;
			last_candidate = current_candidate;
			ncandidates = 1;
		}
		/* no worse than the last choice, so keep this one too? */
		else if (nmatch == nbestMatch)
		{
			last_candidate->next = current_candidate;
			last_candidate = current_candidate;
			ncandidates++;
		}
		/* otherwise, don't bother keeping this one... */
	}

	if (last_candidate)			/* terminate rebuilt list */
		last_candidate->next = NULL;

	if (ncandidates == 1)
		return candidates;

	/*
	 * Still too many candidates? Now look for candidates which have either
	 * exact matches or preferred types at the args that will require
	 * coercion. (Restriction added in 7.4: preferred type must be of same
	 * category as input type; give no preference to cross-category
	 * conversions to preferred types.)  Keep all candidates if none match.
	 */
	for (i = 0; i < nargs; i++) /* avoid multiple lookups */
		slot_category[i] = TypeCategory(input_base_typeids[i]);
	ncandidates = 0;
	nbestMatch = 0;
	last_candidate = NULL;
	for (current_candidate = candidates;
		 current_candidate != NULL;
		 current_candidate = current_candidate->next)
	{
		current_typeids = current_candidate->args;
		nmatch = 0;
		for (i = 0; i < nargs; i++)
		{
			if (input_base_typeids[i] != UNKNOWNOID)
			{
				if (current_typeids[i] == input_base_typeids[i] ||
					IsPreferredType(slot_category[i], current_typeids[i]))
					nmatch++;
			}
		}

		if ((nmatch > nbestMatch) || (last_candidate == NULL))
		{
			nbestMatch = nmatch;
			candidates = current_candidate;
			last_candidate = current_candidate;
			first_candidate = last_candidate;		/* ReqID:SRS-GKC-DATATYPE_001 */
			ncandidates = 1;
		}
		else if (nmatch == nbestMatch)
		{
			last_candidate->next = current_candidate;
			last_candidate = current_candidate;
			ncandidates++;
		}
	}

	if (last_candidate)			/* terminate rebuilt list */
		last_candidate->next = NULL;

	if (ncandidates == 1)
		return candidates;

	/*
	 * Still too many candidates?  Try assigning types for the unknown inputs.
	 *
	 * If there are no unknown inputs, we have no more heuristics that apply,
	 * and must fail.
	 */
	if (nunknowns == 0)
		return NULL;

	/*
	 * The next step examines each unknown argument position to see if we can
	 * determine a "type category" for it.  If any candidate has an input
	 * datatype of STRING category, use STRING category (this bias towards
	 * STRING is appropriate since unknown-type literals look like strings).
	 * Otherwise, if all the candidates agree on the type category of this
	 * argument position, use that category.  Otherwise, fail because we
	 * cannot determine a category.
	 *
	 * If we are able to determine a type category, also notice whether any of
	 * the candidates takes a preferred datatype within the category.
	 *
	 * Having completed this examination, remove candidates that accept the
	 * wrong category at any unknown position.  Also, if at least one
	 * candidate accepted a preferred type at a position, remove candidates
	 * that accept non-preferred types.  If just one candidate remains, return
	 * that one.  However, if this rule turns out to reject all candidates,
	 * keep them all instead.
	 */
	resolved_unknowns = false;
	for (i = 0; i < nargs; i++)
	{
		bool		have_conflict;

		if (input_base_typeids[i] != UNKNOWNOID)
			continue;
		resolved_unknowns = true;		/* assume we can do it */
		slot_category[i] = TYPCATEGORY_INVALID;
		slot_has_preferred_type[i] = false;
		have_conflict = false;
		for (current_candidate = candidates;
			 current_candidate != NULL;
			 current_candidate = current_candidate->next)
		{
			current_typeids = current_candidate->args;
			current_type = current_typeids[i];
			get_type_category_preferred(current_type,
										&current_category,
										&current_is_preferred);
			if (slot_category[i] == TYPCATEGORY_INVALID)
			{
				/* first candidate */
				slot_category[i] = current_category;
				slot_has_preferred_type[i] = current_is_preferred;
			}
			else if (current_category == slot_category[i])
			{
				/* more candidates in same category */
				slot_has_preferred_type[i] |= current_is_preferred;
			}
			else
			{
				/* category conflict! */
				if (current_category == TYPCATEGORY_STRING)
				{
					/* STRING always wins if available */
					slot_category[i] = current_category;
					slot_has_preferred_type[i] = current_is_preferred;
				}
				else
				{
					/*
					 * Remember conflict, but keep going (might find STRING)
					 */
					have_conflict = true;
				}
			}
		}
		if (have_conflict && slot_category[i] != TYPCATEGORY_STRING)
		{
			/* Failed to resolve category conflict at this position */
			resolved_unknowns = false;
			break;
		}
	}

	if (resolved_unknowns)
	{
		/* Strip non-matching candidates */
		ncandidates = 0;
		first_candidate = candidates;
		last_candidate = NULL;
		for (current_candidate = candidates;
			 current_candidate != NULL;
			 current_candidate = current_candidate->next)
		{
			bool		keepit = true;

			current_typeids = current_candidate->args;
			for (i = 0; i < nargs; i++)
			{
				if (input_base_typeids[i] != UNKNOWNOID)
					continue;
				current_type = current_typeids[i];
				get_type_category_preferred(current_type,
											&current_category,
											&current_is_preferred);
				if (current_category != slot_category[i])
				{
					keepit = false;
					break;
				}
				if (slot_has_preferred_type[i] && !current_is_preferred)
				{
					keepit = false;
					break;
				}
			}
			if (keepit)
			{
				/* keep this candidate */
				last_candidate = current_candidate;
				ncandidates++;
			}
			else
			{
				/* forget this candidate */
				if (last_candidate)
					last_candidate->next = current_candidate->next;
				else
					first_candidate = current_candidate->next;
			}
		}

		/* if we found any matches, restrict our attention to those */
		if (last_candidate)
		{
			candidates = first_candidate;
			/* terminate rebuilt list */
			last_candidate->next = NULL;
		}

		if (ncandidates == 1)
			return candidates;
	}

	/*
	 * Last gasp: if there are both known- and unknown-type inputs, and all
	 * the known types are the same, assume the unknown inputs are also that
	 * type, and see if that gives us a unique match.  If so, use that match.
	 *
	 * NOTE: for a binary operator with one unknown and one non-unknown input,
	 * we already tried this heuristic in binary_oper_exact().  However, that
	 * code only finds exact matches, whereas here we will handle matches that
	 * involve coercion, polymorphic type resolution, etc.
	 */
	if (nunknowns < nargs)
	{
		Oid			known_type = UNKNOWNOID;

		for (i = 0; i < nargs; i++)
		{
			if (input_base_typeids[i] == UNKNOWNOID)
				continue;
			if (known_type == UNKNOWNOID)		/* first known arg? */
				known_type = input_base_typeids[i];
			else if (known_type != input_base_typeids[i])
			{
				/* oops, not all match */
				known_type = UNKNOWNOID;
				break;
			}
		}

		if (known_type != UNKNOWNOID)
		{
			/* okay, just one known type, apply the heuristic */
			for (i = 0; i < nargs; i++)
				input_base_typeids[i] = known_type;
			ncandidates = 0;
			last_candidate = NULL;
			for (current_candidate = candidates;
				 current_candidate != NULL;
				 current_candidate = current_candidate->next)
			{
				current_typeids = current_candidate->args;
				if (can_coerce_type(nargs, input_base_typeids, current_typeids,
									COERCION_IMPLICIT))
				{
					if (++ncandidates > 1)
						break;	/* not unique, give up */
					last_candidate = current_candidate;
					/* Begin - ReqID:SRS-GKC-DATATYPE_001 */
					if (first_candidate == NULL)
						first_candidate = last_candidate;
					/* End - ReqID:SRS-GKC-DATATYPE_001 */
				}
			}
			if (ncandidates == 1)
			{
				/* successfully identified a unique match */
				last_candidate->next = NULL;
				return last_candidate;
			}
		}
	}

	return NULL;				/* failed to select a best candidate */
}	/* plisql_func_select_candidate() */

/*
 * like expand_function_arguments
 * we expand subproc function arguments and reorder
 * its arguments
 */
static List *
plisql_expand_and_reorder_functionargs(ParseState *pstate, PLiSQL_subproc_function *subprocfunc,
													int funcnarg, List *fargs,
													List *defaultnumber, List **argdefaults)
{
	Node	   *argarray[FUNC_MAX_ARGS];
	int i;
	ListCell   *lc;
	int provnargs = list_length(fargs);

	MemSet(argarray, 0, funcnarg * sizeof(Node *));

	i = 0;
	foreach(lc, fargs)
	{
		Node	   *arg = (Node *) lfirst(lc);

		if (!IsA(arg, NamedArgExpr))
		{
			/* positional argument, assumed to precede all named args */
			Assert(argarray[i] == NULL);
			argarray[i++] = arg;
		}
		else
		{
			NamedArgExpr *na = (NamedArgExpr *) arg;

			Assert(argarray[na->argnumber] == NULL);
			argarray[na->argnumber] = (Node *) na->arg;
		}
	}

	if (provnargs < funcnarg)
	{
		foreach(lc, defaultnumber)
		{
			int argno = lfirst_int(lc);
			Node		*argdefault;

			Assert(argarray[argno] == NULL);

			argdefault = plisql_get_subprocfunc_argdefaults(pstate, subprocfunc, argno);
			argarray[argno] = (Node *) copyObject(argdefault);
			if (argdefaults != NULL)
				*argdefaults = lappend(*argdefaults, argdefault);
		}
	}
	/* Now reconstruct the args list in proper order */
	fargs = NIL;
	for (i = 0; i < funcnarg; i++)
	{
		Assert(argarray[i] != NULL);
		fargs = lappend(fargs, argarray[i]);
	}

	return fargs;
}

/*
 * like internal_get_result_type
 * we build subprocfunc result type
 */
static TypeFuncClass
internal_get_subprocfunc_result_type(PLiSQL_subproc_function *subprocfunc,
									Node *call_expr,
									ReturnSetInfo *rsinfo,
									Oid *resultTypeId,
									TupleDesc *resultTupleDesc)
{
	TypeFuncClass result;
	Oid			rettype = (subprocfunc->rettype != NULL ? subprocfunc->rettype->typoid : InvalidOid);
	TupleDesc	tupdesc;
	Oid			base_rettype;

	tupdesc = build_subprocfunction_result_tupdesc_t(subprocfunc);
	if (tupdesc)
	{
		oidvector *oidvec;
		Oid			*argtypes;
		ListCell	*lc;
		int i = 0;

		argtypes = (Oid *) palloc(subprocfunc->function->fn_nargs * sizeof(Oid));
		foreach(lc, subprocfunc->arg)
		{
			PLiSQL_function_argitem *argitem = (PLiSQL_function_argitem *) lfirst(lc);

			argtypes[i++] = argitem->type->typoid;
		}
		Assert(i == subprocfunc->function->fn_nargs);
		oidvec = buildoidvector(argtypes, i);

		/*
		 * It has OUT parameters, so it's basically like a regular composite
		 * type, except we have to be able to resolve any polymorphic OUT
		 * parameters.
		 */
		if (resultTypeId)
			*resultTypeId = rettype;

		if (resolve_polymorphic_tupdesc(tupdesc,
										oidvec,
										call_expr))
		{
			if (tupdesc->tdtypeid == RECORDOID &&
				tupdesc->tdtypmod < 0)
				assign_record_type_typmod(tupdesc);
			if (resultTupleDesc)
				*resultTupleDesc = tupdesc;
			result = TYPEFUNC_COMPOSITE;
		}
		else
		{
			if (resultTupleDesc)
				*resultTupleDesc = NULL;
			result = TYPEFUNC_RECORD;
		}

		pfree(argtypes);
		pfree(oidvec);

		return result;
	}

	/*
	 * If scalar polymorphic result, try to resolve it.
	 */
	if (IsPolymorphicType(rettype))
	{
		Oid			newrettype = exprType(call_expr);

		if (newrettype == InvalidOid)	/* this probably should not happen */
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("could not determine actual result type for function \"%s\" declared to return type %s",
							subprocfunc->func_name,
							format_type_be(rettype))));
		rettype = newrettype;
	}

	if (resultTypeId)
		*resultTypeId = rettype;
	if (resultTupleDesc)
		*resultTupleDesc = NULL;	/* default result */

	/* Classify the result type */
	result = get_type_func_class(rettype, &base_rettype);
	switch (result)
	{
		case TYPEFUNC_COMPOSITE:
		case TYPEFUNC_COMPOSITE_DOMAIN:
			if (resultTupleDesc)
				*resultTupleDesc = lookup_rowtype_tupdesc_copy(base_rettype, -1);
			/* Named composite types can't have any polymorphic columns */
			break;
		case TYPEFUNC_SCALAR:
			break;
		case TYPEFUNC_RECORD:
			/* We must get the tupledesc from call context */
			if (rsinfo && IsA(rsinfo, ReturnSetInfo) &&
				rsinfo->expectedDesc != NULL)
			{
				result = TYPEFUNC_COMPOSITE;
				if (resultTupleDesc)
					*resultTupleDesc = rsinfo->expectedDesc;
				/* Assume no polymorphic columns here, either */
			}
			break;
		default:
			break;
	}

	return result;
}


/*
 * like build_function_result_tupdesc_t
 * we build subproc function result tupdesc
 */
static TupleDesc
build_subprocfunction_result_tupdesc_t(PLiSQL_subproc_function *subprocfunc)
{
	TupleDesc	desc;
	Oid			*outargtypes;
	char		**outargnames;
	int			numoutargs = subprocfunc->noutargs;
	int			i;
	int			j;
	ListCell	*lc;
	Oid			rettype = subprocfunc->function->fn_rettype;

	/* function no out arguments */
	if (numoutargs < 1 || (numoutargs == 1 && rettype == VOIDOID))
		return NULL;

	outargtypes = (Oid *) palloc0(numoutargs * sizeof(Oid));
	outargnames = (char **) palloc0(numoutargs * sizeof(char *));

	i = 0;
	foreach(lc, subprocfunc->arg)
	{
		PLiSQL_function_argitem *argitem = (PLiSQL_function_argitem *) lfirst(lc);

		if (argitem->argmode != ARGMODE_IN)
		{
			outargtypes[i] = argitem->type->typoid;
			outargnames[i++] = argitem->argname;
		}
	}

	Assert(i == numoutargs);

	desc = CreateTemplateTupleDesc(numoutargs);

	i = 0;
	/* result value after out parameters value */
	/* init out-parameters */
	for (j = 0; j < numoutargs; j++)
	{
		TupleDescInitEntry(desc, ++i,
						outargnames[j],
						outargtypes[j],
						-1,
						0);
	}

	pfree(outargtypes);
	pfree(outargnames);

	return desc;
}

/*
 * like get_func_arg_info
 * we get function argtypes from arguments
 * this is special for poly argument type
 */
int
get_subprocfunc_arg_info_from_arguments(List *args, Oid **p_argtypes,
								char ***p_argnames, char **p_argmodes)
{
	int numargs;
	ListCell *lc;
	int	i = 0;

	numargs = list_length(args);

	if (numargs == 0)
		return numargs;

	*p_argtypes = (Oid *) palloc(numargs * sizeof(Oid));
	*p_argnames = (char **) palloc(sizeof(char *) * numargs);
	*p_argmodes = (char *) palloc(numargs * sizeof(char));

	foreach (lc, args)
	{
		PLiSQL_function_argitem *argitem;

		argitem = (PLiSQL_function_argitem *) lfirst(lc);

		(*p_argtypes)[i] = argitem->type->typoid;
		(*p_argnames)[i] = argitem->argname;
		if (argitem->argmode == ARGMODE_IN)
			(*p_argmodes)[i] = PROARGMODE_IN;
		else if (argitem->argmode == ARGMODE_OUT)
			(*p_argmodes)[i] = PROARGMODE_OUT;
		else if (argitem->argmode == ARGMODE_INOUT)
			(*p_argmodes)[i] = PROARGMODE_INOUT;
		else
			elog(ERROR, "invalid argmode for subproc function or procedure");
		i++;
	}

	return numargs;
}

/*
 * look up for a subproc function
 */
PLiSQL_function *
plisql_subprocfunc_HashTableLookup(HTAB *hashp,
							PLiSQL_func_hashkey *func_key)
{
	plisql_HashEnt *hentry;

	hentry = (plisql_HashEnt *) hash_search(hashp,
											 (void *) func_key,
											 HASH_FIND,
											 NULL);
	if (hentry)
		return hentry->function;
	else
		return NULL;
}

/*
 * insert a subproc function into a hash table
 */
static void
plisql_subprocfunc_HashTableInsert(HTAB *hashp, PLiSQL_function *function,
						PLiSQL_func_hashkey *func_key)
{
	plisql_HashEnt *hentry;
	bool		found;

	hentry = (plisql_HashEnt *) hash_search(hashp,
											 (void *) func_key,
											 HASH_ENTER,
											 &found);
	if (found)
		elog(WARNING, "trying to insert a subproc function that already exists");

	hentry->function = function;
	/* prepare back link from function to hashtable key */
	function->fn_hashkey = &hentry->key;
}

/*
 * get subproc function
 * default expr
 */
static Node *
plisql_get_subprocfunc_argdefaults(ParseState *pstate, PLiSQL_subproc_function *subprocfunc, int argno)
{
	Node *default_node;
	PLiSQL_function_argitem *argitem = list_nth(subprocfunc->arg, argno);

	Assert(argitem != NULL && argitem->defexpr != NULL);

	if (argitem->default_sql_expr == NULL)
	{
		RawStmt *rawnode;
		List *rawlist;
		SelectStmt *selectnode;
		ResTarget *res;
		Node *sql_expr;
		MemoryContext oldctx;

		Assert(argitem->defexpr->query != NULL);

		rawlist = raw_parser(argitem->defexpr->query, RAW_PARSE_PLPGSQL_EXPR);
		if (list_length(rawlist) != 1)
			elog(ERROR, "invalid argitem default expr '%s'", argitem->defexpr->query);

		rawnode = (RawStmt *) linitial(rawlist);

		selectnode = (SelectStmt *) rawnode->stmt;

		Assert(nodeTag(selectnode) == T_SelectStmt);

		if (list_length(selectnode->targetList) != 1)
			elog(ERROR, "more than one target for argitem default expr '%s'", argitem->defexpr->query);

		res = (ResTarget*) linitial(selectnode->targetList);

		sql_expr = transformExpr(pstate, res->val, EXPR_KIND_FUNCTION_DEFAULT);
		Assert(sql_expr != NULL);

		/* saved in function memory context */
		oldctx = MemoryContextSwitchTo(subprocfunc->function->fn_cxt);
		argitem->default_sql_expr = (Node *) copyObject(sql_expr);
		MemoryContextSwitchTo(oldctx);
	}

	default_node = (Node *) copyObject(argitem->default_sql_expr);

	return default_node;
}

/*
 * before dynamic compile a subproc func
 * we should init something like namespace
 * and its global datums,subprocfunc
 */
static void
plisql_init_subprocfunc_compile(PLiSQL_subproc_function *subprocfunc)
{
	int i;

	plisql_set_ns(subprocfunc->global_cur);
	plisql_start_datums();
	plisql_start_subproc_func();

	/* init datums use origin function */
	for (i = 0; i < subprocfunc->lastoutvardno; i++)
		plisql_adddatum(subprocfunc->function->datums[i]);
	Assert(subprocfunc->lastoutvardno == plisql_nDatums);

	/* init subprocfunc use origin function */
	for (i = 0; i < subprocfunc->lastoutsubprocfno; i++)
		plisql_add_subproc_function(subprocfunc->function->subprocfuncs[i]);
	Assert(subprocfunc->lastoutsubprocfno == plisql_nsubprocFuncs);

	plisql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;
	return;
}


/*
 * like do_compile but only
 * compile a subproc function
 */
PLiSQL_function*
plisql_dynamic_compile_subproc(FunctionCallInfo fcinfo,
										PLiSQL_subproc_function *subprocfunc,
										bool forValidator)
{
	ErrorContextCallback plerrcontext;
	MemoryContext func_cxt;
	PLiSQL_function *function;
	int	parse_rc;
	int found_varno = subprocfunc->function->found_varno;
	Oid 		define_useid = InvalidOid;
	Oid 		save_userid;
	int 		save_sec_context;
	Oid			current_user = GetUserId();

	plisql_scanner_init(subprocfunc->src);

	plisql_error_funcname = pstrdup(subprocfunc->func_name);

	/*
	 * Setup error traceback support for ereport()
	 */
	plerrcontext.callback = plisql_compile_error_callback;
	plerrcontext.arg = NULL;
	plerrcontext.previous = error_context_stack;
	error_context_stack = &plerrcontext;

	/* append package namespace */
	if (subprocfunc->function->item != NULL)
	{
		HeapTuple	pkgTup;
		Form_pg_package pkgStruct;

		pkgTup = SearchSysCache1(PKGOID,
				ObjectIdGetDatum(subprocfunc->function->item->pkey));
		if (!HeapTupleIsValid(pkgTup))
			elog(ERROR, "cache lookup failed for package %u",
			subprocfunc->function->item->pkey);

		pkgStruct = (Form_pg_package) GETSTRUCT(pkgTup);

		if (current_user != pkgStruct->pkgowner)
		{
			define_useid = pkgStruct->pkgowner;
			GetUserIdAndSecContext(&save_userid, &save_sec_context);

			SetUserIdAndSecContext(define_useid,
						save_sec_context | SECURITY_LOCAL_USERID_CHANGE);
		}
		ReleaseSysCache(pkgTup);

		plerrcontext.callback = plisql_compile_package_error_callback;
	}

	/*
	 * Do extra syntax checks when validating the function definition. We skip
	 * this when actually compiling functions for execution, for performance
	 * reasons.
	 */
	plisql_check_syntax = false;

	function = (PLiSQL_function *)
			MemoryContextAllocZero(subprocfunc->function->fn_cxt, sizeof(PLiSQL_function));
	plisql_curr_compile = function;

	/* user origin function fn_cxt */
	func_cxt = subprocfunc->function->fn_cxt;

	plisql_compile_tmp_cxt = MemoryContextSwitchTo(func_cxt);

	function->fn_signature = quote_qualified_identifier(NULL, subprocfunc->func_name);
	function->fn_input_collation = fcinfo->fncollation;
	function->fn_cxt = func_cxt;
	function->out_param_varno = -1; /* set up for no OUT param */
	function->resolve_option = plisql_variable_conflict;
	function->print_strict_params = plisql_print_strict_params;
	/* only promote extra warnings and errors at CREATE FUNCTION time */
	function->extra_warnings =  0;
	function->extra_errors = 0;
	function->fn_is_trigger = subprocfunc->function->fn_is_trigger;

	function->fn_prokind = subprocfunc->function->fn_prokind;
	function->nstatements = 0;
	function->requires_procedure_resowner = false;
	function->fn_nargs = subprocfunc->function->fn_nargs;

	cur_compile_func_level = 0;

	function->item = subprocfunc->function->item;
	function->fn_oid = subprocfunc->function->fn_oid;
	plisql_saved_compile[cur_compile_func_level] = function;
	if (function->item != NULL)
		plisql_compile_packageitem = (PLiSQL_package *) function->item->source;
	else
		plisql_compile_packageitem = NULL;
	function->namelabel = pstrdup(subprocfunc->func_name);

	/* init subprocfunc */
	plisql_init_subprocfunc_compile(subprocfunc);
	plisql_DumpExecTree = false;

	/* replate origin function */
	subprocfunc->function = function;
	plisql_ns_push(subprocfunc->func_name, PLISQL_LABEL_BLOCK);

	plisql_build_variable_from_funcargs(subprocfunc, forValidator,
								fcinfo, found_varno);

	/*
	 * Now parse the function's text
	 */
	parse_rc = plisql_yyparse();
	if (parse_rc != 0)
		elog(ERROR, "plisql parser returned %d", parse_rc);

	plisql_set_subprocfunc_action(subprocfunc, plisql_parse_result);

	plisql_finish_datums(function);

	plisql_finish_subproc_func(function);

	plisql_scanner_finish();

	/*
	 * Pop the error context stack
	 */
	error_context_stack = plerrcontext.previous;
	plisql_error_funcname = NULL;

	plisql_check_syntax = false;

	MemoryContextSwitchTo(plisql_compile_tmp_cxt);

	if (OidIsValid(define_useid))
		SetUserIdAndSecContext(save_userid, save_sec_context);

	plisql_compile_tmp_cxt = NULL;

	return function;
}


/*
 * when variable define after subproc function definition
 * we shoule use parent stack function to
 * init global var for example:
 *
 * declare
 *   var1 integer;
 *   function test_f(id integer) return integer;
 *   function test_f1(id integer) return integer is
 *      var2 integer;
 *   begin
 *      var2 := test_f(23);
 *   end;
 *  var3 integer;
 *  function test_f(id integer) return integer is
 *  begin
 *    var3 := var3 + id;
 *  end;
 * begin
 *   var3 := 24;
 *   var1 := test_f1(23);
 * end;
 *
 *  when test_f1 invoke test_f, the var3 is not global var to test_f1
 *  but is global var to test_f, so we init var3 from test_f1 parent which
 * is the anonymous block
 */
static void
plsql_init_glovalvar_from_stack(PLiSQL_execstate *estate, int dno, int *start_level)
{
	bool match = false;
	int connected;
	PLiSQL_execstate *parestate;
	PLiSQL_function *func;

	for (connected = *start_level; connected >= 0; connected--)
	{
		func = (PLiSQL_function *) SPI_get_func(connected);

		/* maybe come from plpgsql */
		if (func == NULL)
			continue;
		parestate = func->cur_estate;

		/* dno not match */
		if (dno >= parestate->ndatums)
			continue;
		plisql_assign_in_global_var(estate, parestate, dno);
		match = true;
		*start_level = connected;
		break;
	}
	Assert(match);
	return;
}

/*
 * like plsql_init_glovalvar_from_stack, but we assign it out
 */
static void
plsql_assign_out_glovalvar_from_stack(PLiSQL_execstate *estate, int dno, int *start_level)
{
	bool match = false;
	int connected;
	PLiSQL_execstate *parestate;
	PLiSQL_function *func;

	for (connected = *start_level; connected >= 0; connected--)
	{
		func = (PLiSQL_function *) SPI_get_func(connected);

		/* maybe NULL ? */
		if (func == NULL)
			continue;
		parestate = func->cur_estate;

		/* dno not match */
		if (dno >= parestate->ndatums)
			continue;
		plisql_assign_out_global_var(estate, parestate, dno, connected);
		*start_level = connected;
		match = true;
		break;
	}
	Assert(match);
	return;
}


/*
 * decide wether the dno
 * is subprocfunc argnum
 */
static bool
is_subprocfunc_argnum(PLiSQL_function *pfunc, int dno)
{
	int i;

	for (i = 0; i < pfunc->nsubprocfuncs; i++)
	{
		PLiSQL_subproc_function *subprocfunc = pfunc->subprocfuncs[i];

		/* ignore no action function */
		if (subprocfunc->function->action != NULL)
		{
			int j;

			for (j = 0; j < subprocfunc->function->fn_nargs; j++)
			{
				if (subprocfunc->function->fn_argvarnos[j] == dno)
					return true;
			}
		}
	}
	return false;
}


/*
 * like plisql_param_ref
 * we handle subprocfunc, but its arguments like func_get_detail
 */
int
plisql_subprocfunc_ref(ParseState *pstate, List *funcname,
				List **fargs, /* return value */
				List *fargnames,
				int nargs,
				Oid *argtypes,
				bool expand_variadic,
				bool expand_defaults,
				bool proc_call,
				Oid *funcid,	/* return value */
				Oid *rettype,	/* return value */
				bool *retset,	/* return value */
				int *nvargs,	/* return value */
				Oid *vatype,	/* return value */
				Oid **true_typeids, /* return value */
				List **argdefaults, /* return value */
				void **pfunc) /* return value */
{
	PLiSQL_expr *expr = (PLiSQL_expr *) pstate->p_ref_hook_state;
	PLiSQL_nsitem *nse = NULL;
	char *func_name = NULL;
	char *name1 = NULL;
	char *name2 = NULL;
	char *name3 = NULL;
	int list_len = list_length(funcname);
	FuncDetailCode detail;

	switch(list_len)
	{
		case 1:
			name1 = strVal(linitial(funcname));
			func_name = name1;
			break;
		case 2:
			name1 = strVal(linitial(funcname));
			name2 = strVal(lsecond(funcname));
			func_name = name2;
			break;
		case 3:
			name1 = strVal(linitial(funcname));
			name2 = strVal(lsecond(funcname));
			name3 = strVal(list_nth(funcname, 2));
			func_name = name3;
			break;
		default:
			name1 = strVal(linitial(funcname));
			name2 = strVal(lsecond(funcname));
			name3 = strVal(list_nth(funcname, 2));
			func_name = strVal(list_nth(funcname, list_len - 1));
			break;
	}

	nse = plisql_ns_lookup(expr->ns, false,
							name1, name2, name3,
							NULL);

	if (nse == NULL || (nse->itemtype != PLISQL_NSTYPE_SUBPROC_FUNC &&
		nse->itemtype != PLISQL_NSTYPE_SUBPROC_PROC))
		return FUNCDETAIL_NOTFOUND;

	detail = plisql_get_subprocfunc_detail(pstate,expr->func, nse, func_name, fargs, /* return value */
											proc_call,
											fargnames,
											nargs,
											argtypes,
											funcid,	/* return value */
											rettype,	/* return value */
											retset,	/* return value */
											nvargs,	/* return value */
											vatype,	/* return value */
											true_typeids, /* return value */
											argdefaults); /* return value */
	if (detail != FUNCDETAIL_NORMAL &&
		detail != FUNCDETAIL_PROCEDURE)
		elog(ERROR, "wrong number or types of arguments in call to \"%s\"", func_name);

	*pfunc = (void *) expr->func;

	return detail;
}

