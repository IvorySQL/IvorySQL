/*-------------------------------------------------------------------------
 *
 * pl_comp.c		- Compiler part of the PL/iSQL
 *			  procedural language
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_comp.c
 *
 * add the file for requirement "SQL PARSER"
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <ctype.h>

#include "access/htup_details.h"
#include "catalog/namespace.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "funcapi.h"
#include "nodes/makefuncs.h"
#include "parser/parse_type.h"
#include "plisql.h"
#include "pl_subproc_function.h"
#include "pl_package.h"
#include "utils/builtins.h"
#include "utils/fmgroids.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/regproc.h"
#include "utils/rel.h"
#include "utils/syscache.h"
#include "utils/typcache.h"

/* ----------
 * Our own local and global variables
 * ----------
 */
PLiSQL_stmt_block *plisql_parse_result;

int	datums_alloc; 
int			plisql_nDatums;
PLiSQL_datum **plisql_Datums;
int	datums_last;

char	   *plisql_error_funcname;
bool		plisql_DumpExecTree = false;
bool		plisql_check_syntax = false;

PLiSQL_function *plisql_curr_compile;

/* A context appropriate for short-term allocs during compilation */
MemoryContext plisql_compile_tmp_cxt;

/* ----------
 * Hash table for compiled functions
 * ----------
 */
static HTAB *plisql_HashTable = NULL;

#define FUNCS_PER_USER		128 /* initial table size */

/* ----------
 * Lookup table for EXCEPTION condition names
 * ----------
 */
typedef struct
{
	const char *label;
	int			sqlerrstate;
} ExceptionLabelMap;

static const ExceptionLabelMap exception_label_map[] = {
#include "plerrcodes.h"			/* pgrminclude ignore */
	{NULL, 0}
};


/* ----------
 * static prototypes
 * ----------
 */
static PLiSQL_function *do_compile(FunctionCallInfo fcinfo,
									HeapTuple procTup,
									PLiSQL_function *function,
									PLiSQL_func_hashkey *hashkey,
									bool forValidator);
static Node *plisql_pre_column_ref(ParseState *pstate, ColumnRef *cref);
static Node *plisql_post_column_ref(ParseState *pstate, ColumnRef *cref, Node *var);
static Node *plisql_param_ref(ParseState *pstate, ParamRef *pref);
static Node *resolve_column_ref(ParseState *pstate, PLiSQL_expr *expr,
								ColumnRef *cref, bool error_if_no_field);
static Node *make_datum_param(PLiSQL_expr *expr, int dno, int location);
static PLiSQL_type *build_datatype(HeapTuple typeTup, int32 typmod,
									Oid collation, TypeName *origtypname);
static void compute_function_hashkey(FunctionCallInfo fcinfo,
									 Form_pg_proc procStruct,
									 PLiSQL_func_hashkey *hashkey,
									 bool forValidator,
									 HeapTuple procTup); 
static PLiSQL_function *plisql_HashTableLookup(PLiSQL_func_hashkey *func_key);
static void plisql_HashTableInsert(PLiSQL_function *function,
									PLiSQL_func_hashkey *func_key);
static void plisql_HashTableDelete(PLiSQL_function *function);
void delete_function(PLiSQL_function *func);

/* ----------
 * plisql_compile		Make an execution tree for a PL/iSQL function.
 *
 * If forValidator is true, we're only compiling for validation purposes,
 * and so some checks are skipped.
 *
 * Note: it's important for this to fall through quickly if the function
 * has already been compiled.
 * ----------
 */
PLiSQL_function *
plisql_compile(FunctionCallInfo fcinfo, bool forValidator)
{
	Oid			funcOid = fcinfo->flinfo->fn_oid;
	HeapTuple	procTup;
	Form_pg_proc procStruct;
	PLiSQL_function *function;
	PLiSQL_func_hashkey hashkey;
	bool		function_valid = false;
	bool		hashkey_valid = false;
	Oid rettypeoid = InvalidOid;

	/*
	 * Lookup the pg_proc tuple by Oid; we'll need it in any case
	 */
	procTup = SearchSysCache1(PROCOID, ObjectIdGetDatum(funcOid));
	if (!HeapTupleIsValid(procTup))
		elog(ERROR, "cache lookup failed for function %u", funcOid);
	procStruct = (Form_pg_proc) GETSTRUCT(procTup);

	rettypeoid = get_func_real_rettype(procTup);

	/*
	 * See if there's already a cache entry for the current FmgrInfo. If not,
	 * try to find one in the hash table.
	 */
	function = (PLiSQL_function *) fcinfo->flinfo->fn_extra;

recheck:
	if (!function)
	{
		/* Compute hashkey using function signature and actual arg types */
		compute_function_hashkey(fcinfo, procStruct, &hashkey, forValidator, procTup); 
		hashkey_valid = true;

		/* And do the lookup */
		function = plisql_HashTableLookup(&hashkey);
	}

	if (function)
	{
		/* We have a compiled function, but is it still valid? */
		if (function->fn_xmin == HeapTupleHeaderGetRawXmin(procTup->t_data) &&
			ItemPointerEquals(&function->fn_tid, &procTup->t_self) &&
			(!OidIsValid(rettypeoid) || rettypeoid == function->fn_rettype)) 
			function_valid = true;
		else
		{
			/*
			 * Nope, so remove it from hashtable and try to drop associated
			 * storage (if not done already).
			 */
			delete_function(function);

			/*
			 * If the function isn't in active use then we can overwrite the
			 * func struct with new data, allowing any other existing fn_extra
			 * pointers to make use of the new definition on their next use.
			 * If it is in use then just leave it alone and make a new one.
			 * (The active invocations will run to completion using the
			 * previous definition, and then the cache entry will just be
			 * leaked; doesn't seem worth adding code to clean it up, given
			 * what a corner case this is.)
			 *
			 * If we found the function struct via fn_extra then it's possible
			 * a replacement has already been made, so go back and recheck the
			 * hashtable.
			 */
			if (function->use_count != 0)
			{
				function = NULL;
				if (!hashkey_valid)
					goto recheck;
			}
		}
	}

	/*
	 * If the function wasn't found or was out-of-date, we have to compile it
	 */
	if (!function_valid)
	{
		/*
		 * Calculate hashkey if we didn't already; we'll need it to store the
		 * completed function.
		 */
		if (!hashkey_valid)
			compute_function_hashkey(fcinfo, procStruct, &hashkey,
									 forValidator, procTup); 

		/*
		 * Do the hard part.
		 */
		function = do_compile(fcinfo, procTup, function,
							  &hashkey, forValidator);
	}

	ReleaseSysCache(procTup);

	/*
	 * Save pointer in FmgrInfo to avoid search on subsequent calls
	 */
	fcinfo->flinfo->fn_extra = (void *) function;

	/*
	 * Finally return the compiled function
	 */
	return function;
}

/*
 * This is the slow part of plisql_compile().
 *
 * The passed-in "function" pointer is either NULL or an already-allocated
 * function struct to overwrite.
 *
 * While compiling a function, the CurrentMemoryContext is the
 * per-function memory context of the function we are compiling. That
 * means a palloc() will allocate storage with the same lifetime as
 * the function itself.
 *
 * Because palloc()'d storage will not be immediately freed, temporary
 * allocations should either be performed in a short-lived memory
 * context or explicitly pfree'd. Since not all backend functions are
 * careful about pfree'ing their allocations, it is also wise to
 * switch into a short-term context before calling into the
 * backend. An appropriate context for performing short-term
 * allocations is the plisql_compile_tmp_cxt.
 *
 * NB: this code is not re-entrant.  We assume that nothing we do here could
 * result in the invocation of another plisql function.
 */
static PLiSQL_function *
do_compile(FunctionCallInfo fcinfo,
		   HeapTuple procTup,
		   PLiSQL_function *function,
		   PLiSQL_func_hashkey *hashkey,
		   bool forValidator)
{
	Form_pg_proc procStruct = (Form_pg_proc) GETSTRUCT(procTup);
	bool		is_dml_trigger = CALLED_AS_TRIGGER(fcinfo);
	bool		is_event_trigger = CALLED_AS_EVENT_TRIGGER(fcinfo);
	Datum		prosrcdatum;
	char	   *proc_source;
	HeapTuple	typeTup;
	Form_pg_type typeStruct;
	PLiSQL_variable *var;
	PLiSQL_rec *rec;
	int			i;
	ErrorContextCallback plerrcontext;
	int			parse_rc;
	Oid			rettypeid;
	int			numargs;
	int			num_in_args = 0;
	int			num_out_args = 0;
	Oid		   *argtypes;
	char	  **argnames;
	char	   *argmodes;
	int		   *in_arg_varnos = NULL;
	PLiSQL_variable **out_arg_variables;
	MemoryContext func_cxt;

	char		**argtypenames = NULL;
	char		*rettypename = NULL;
	PLiSQL_type	*rettype = NULL;

	/*
	 * Setup the scanner input and error info.  We assume that this function
	 * cannot be invoked recursively, so there's no need to save and restore
	 * the static variables used here.
	 */
	prosrcdatum = SysCacheGetAttrNotNull(PROCOID, procTup, Anum_pg_proc_prosrc);
	proc_source = TextDatumGetCString(prosrcdatum);
	plisql_scanner_init(proc_source);

	plisql_error_funcname = pstrdup(NameStr(procStruct->proname));

	/*
	 * Setup error traceback support for ereport()
	 */
	plerrcontext.callback = plisql_compile_error_callback;
	plerrcontext.arg = forValidator ? proc_source : NULL;
	plerrcontext.previous = error_context_stack;
	error_context_stack = &plerrcontext;

	/*
	 * Do extra syntax checks when validating the function definition. We skip
	 * this when actually compiling functions for execution, for performance
	 * reasons.
	 */
	plisql_check_syntax = forValidator;

	/*
	 * Create the new function struct, if not done already.  The function
	 * structs are never thrown away, so keep them in TopMemoryContext.
	 */
	if (function == NULL)
	{
		function = (PLiSQL_function *)
			MemoryContextAllocZero(TopMemoryContext, sizeof(PLiSQL_function));
	}
	else
	{
		/* re-using a previously existing struct, so clear it out */
		memset(function, 0, sizeof(PLiSQL_function));
	}
	plisql_curr_compile = function;

	/*
	 * All the permanent output of compilation (e.g. parse tree) is kept in a
	 * per-function memory context, so it can be reclaimed easily.
	 */
	func_cxt = AllocSetContextCreate(TopMemoryContext,
									 "PL/iSQL function",
									 ALLOCSET_DEFAULT_SIZES);
	plisql_compile_tmp_cxt = MemoryContextSwitchTo(func_cxt);

	function->fn_signature = format_procedure(fcinfo->flinfo->fn_oid);
	MemoryContextSetIdentifier(func_cxt, function->fn_signature);
	function->fn_oid = fcinfo->flinfo->fn_oid;
	function->fn_xmin = HeapTupleHeaderGetRawXmin(procTup->t_data);
	function->fn_tid = procTup->t_self;
	function->fn_input_collation = fcinfo->fncollation;
	function->fn_cxt = func_cxt;
	function->out_param_varno = -1; /* set up for no OUT param */
	function->resolve_option = plisql_variable_conflict;
	function->print_strict_params = plisql_print_strict_params;
	/* only promote extra warnings and errors at CREATE FUNCTION time */
	function->extra_warnings = forValidator ? plisql_extra_warnings : 0;
	function->extra_errors = forValidator ? plisql_extra_errors : 0;

	if (is_dml_trigger)
		function->fn_is_trigger = PLISQL_DML_TRIGGER;
	else if (is_event_trigger)
		function->fn_is_trigger = PLISQL_EVENT_TRIGGER;
	else
		function->fn_is_trigger = PLISQL_NOT_TRIGGER;

	function->fn_prokind = procStruct->prokind;

	function->nstatements = 0;
	function->requires_procedure_resowner = false;

	function->namelabel = pstrdup(NameStr(procStruct->proname));

	/*
	 * Initialize the compiler, particularly the namespace stack.  The
	 * outermost namespace contains function parameters and other special
	 * variables (such as FOUND), and is named after the function itself.
	 */
	plisql_ns_init();
	plisql_ns_push(NameStr(procStruct->proname), PLISQL_LABEL_BLOCK);
	plisql_DumpExecTree = false;
	plisql_start_datums();
	cur_compile_func_level = 0;
	plisql_start_subproc_func();
	plisql_compile_packageitem = NULL;
	plisql_saved_compile[cur_compile_func_level] = function;
	Assert(plisql_curr_global_proper_level == 0);
	plisql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;

	switch (function->fn_is_trigger)
	{
		case PLISQL_NOT_TRIGGER:

			/*
			 * Fetch info about the procedure's parameters. Allocations aren't
			 * needed permanently, so make them in tmp cxt.
			 *
			 * We also need to resolve any polymorphic input or output
			 * argument types.  In validation mode we won't be able to, so we
			 * arbitrarily assume we are dealing with integers.
			 */
			MemoryContextSwitchTo(plisql_compile_tmp_cxt);

			numargs = get_func_arg_info(procTup,
										&argtypes, &argnames, &argmodes);

			get_func_typename_info(procTup,
									&argtypenames, &rettypename);

			plisql_resolve_polymorphic_argtypes(numargs, argtypes, argmodes,
												 fcinfo->flinfo->fn_expr,
												 forValidator,
												 plisql_error_funcname);

			in_arg_varnos = (int *) palloc(numargs * sizeof(int));
			out_arg_variables = (PLiSQL_variable **) palloc(numargs * sizeof(PLiSQL_variable *));

			MemoryContextSwitchTo(func_cxt);

			/*
			 * Create the variables for the procedure's parameters.
			 */
			for (i = 0; i < numargs; i++)
			{
				char		buf[32];
				Oid			argtypeid = argtypes[i];
				char		argmode = argmodes ? argmodes[i] : PROARGMODE_IN;
				PLiSQL_type *argdtype;
				PLiSQL_variable *argvariable;
				PLiSQL_nsitem_type argitemtype;

				/* Create $n name for variable */
				snprintf(buf, sizeof(buf), "$%d", i + 1);

				/* Create datatype info */
				/* consider the argument type comes from a package */
				if (argtypenames != NULL && strcmp(argtypenames[i], "") != 0)
				{
					TypeName	*tname;

					tname = (TypeName *) stringToNode(argtypenames[i]);

					if (tname->pct_type)
						argdtype = plisql_parse_package_type(tname, parse_by_var_type, false);
					else
						argdtype = plisql_parse_package_type(tname, parse_by_pkg_type, false);
					if (argdtype == NULL)
					{
						elog(ERROR, "doesn't recognise package type %s", TypeNameToString(tname));
					}
					pfree(tname);
				}
				else
				{
					argdtype = plisql_build_datatype(argtypeid,
									  -1,
									  function->fn_input_collation,
									  NULL);
				}


				/* Disallow pseudotype argument */
				/* (note we already replaced polymorphic types) */
				/* (build_variable would do this, but wrong message) */
				if (argdtype->ttype == PLISQL_TTYPE_PSEUDO)
					ereport(ERROR,
							(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
							 errmsg("PL/iSQL functions cannot accept type %s",
									format_type_be(argtypeid))));

				/*
				 * Build variable and add to datum list.  If there's a name
				 * for the argument, use that as refname, else use $n name.
				 */
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

				/* Remember arguments in appropriate arrays */
				if (argmode == PROARGMODE_IN ||
					argmode == PROARGMODE_INOUT ||
					argmode == PROARGMODE_VARIADIC)
					in_arg_varnos[num_in_args++] = argvariable->dno;
				if (argmode == PROARGMODE_OUT ||
					argmode == PROARGMODE_INOUT ||
					argmode == PROARGMODE_TABLE)
					out_arg_variables[num_out_args++] = argvariable;

				/* Add to namespace under the $n name */
				add_parameter_name(argitemtype, argvariable->dno, buf);

				/* If there's a name for the argument, make an alias */
				if (argnames && argnames[i][0] != '\0')
					add_parameter_name(argitemtype, argvariable->dno,
									   argnames[i]);
			}

			if (rettypename != NULL)
			{
				TypeName		*tname;

				tname = (TypeName *) stringToNode(rettypename);
				if (tname->pct_type)
					rettype = plisql_parse_package_type(tname, parse_by_var_type, false);
				else
					rettype = plisql_parse_package_type(tname, parse_by_pkg_type, false);

				if (rettype == NULL)
				{
					elog(ERROR, "doesn't recognise package type %s", TypeNameToString(tname));
				}
				pfree(tname);
				rettypeid = rettype->typoid;
			}
			else
				rettypeid = procStruct->prorettype;

			/*
			 * If there's just one OUT parameter, out_param_varno points
			 * directly to it.  If there's more than one, build a row that
			 * holds all of them.  Procedures return a row even for one OUT
			 * parameter.
			 */
			if (num_out_args > 1 ||
				(num_out_args == 1 && function->fn_prokind == PROKIND_PROCEDURE))
			{
				PLiSQL_row *row = build_row_from_vars(out_arg_variables,
													   num_out_args);

				plisql_adddatum((PLiSQL_datum *) row);
				function->out_param_varno = row->dno;
			}
			else if (num_out_args == 1)
				function->out_param_varno = out_arg_variables[0]->dno;

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
			function->fn_retset = procStruct->proretset;

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
			if (IsPolymorphicType(procStruct->prorettype) &&
				num_out_args == 0)
			{
				(void) plisql_build_variable("$0", 0,
											  build_datatype(typeTup,
															 -1,
															 function->fn_input_collation,
															 NULL),
											  true);
			}

			ReleaseSysCache(typeTup);
			break;

		case PLISQL_DML_TRIGGER:
			/* Trigger procedure's return type is unknown yet */
			function->fn_rettype = InvalidOid;
			function->fn_retbyval = false;
			function->fn_retistuple = true;
			function->fn_retisdomain = false;
			function->fn_retset = false;

			/* shouldn't be any declared arguments */
			if (procStruct->pronargs != 0)
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_FUNCTION_DEFINITION),
						 errmsg("trigger functions cannot have declared arguments"),
						 errhint("The arguments of the trigger can be accessed through TG_NARGS and TG_ARGV instead.")));

			/* Add the record for referencing NEW ROW */
			rec = plisql_build_record("new", 0, NULL, RECORDOID, true);
			function->new_varno = rec->dno;

			/* Add the record for referencing OLD ROW */
			rec = plisql_build_record("old", 0, NULL, RECORDOID, true);
			function->old_varno = rec->dno;

			/* Add the variable tg_name */
			var = plisql_build_variable("tg_name", 0,
										 plisql_build_datatype(NAMEOID,
																-1,
																function->fn_input_collation,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_NAME;

			/* Add the variable tg_when */
			var = plisql_build_variable("tg_when", 0,
										 plisql_build_datatype(TEXTOID,
																-1,
																function->fn_input_collation,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_WHEN;

			/* Add the variable tg_level */
			var = plisql_build_variable("tg_level", 0,
										 plisql_build_datatype(TEXTOID,
																-1,
																function->fn_input_collation,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_LEVEL;

			/* Add the variable tg_op */
			var = plisql_build_variable("tg_op", 0,
										 plisql_build_datatype(TEXTOID,
																-1,
																function->fn_input_collation,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_OP;

			/* Add the variable tg_relid */
			var = plisql_build_variable("tg_relid", 0,
										 plisql_build_datatype(OIDOID,
																-1,
																InvalidOid,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_RELID;

			/* Add the variable tg_relname */
			var = plisql_build_variable("tg_relname", 0,
										 plisql_build_datatype(NAMEOID,
																-1,
																function->fn_input_collation,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_TABLE_NAME;

			/* tg_table_name is now preferred to tg_relname */
			var = plisql_build_variable("tg_table_name", 0,
										 plisql_build_datatype(NAMEOID,
																-1,
																function->fn_input_collation,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_TABLE_NAME;

			/* add the variable tg_table_schema */
			var = plisql_build_variable("tg_table_schema", 0,
										 plisql_build_datatype(NAMEOID,
																-1,
																function->fn_input_collation,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_TABLE_SCHEMA;

			/* Add the variable tg_nargs */
			var = plisql_build_variable("tg_nargs", 0,
										 plisql_build_datatype(INT4OID,
																-1,
																InvalidOid,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_NARGS;

			/* Add the variable tg_argv */
			var = plisql_build_variable("tg_argv", 0,
										 plisql_build_datatype(TEXTARRAYOID,
																-1,
																function->fn_input_collation,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_ARGV;

			break;

		case PLISQL_EVENT_TRIGGER:
			function->fn_rettype = VOIDOID;
			function->fn_retbyval = false;
			function->fn_retistuple = true;
			function->fn_retisdomain = false;
			function->fn_retset = false;

			/* shouldn't be any declared arguments */
			if (procStruct->pronargs != 0)
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_FUNCTION_DEFINITION),
						 errmsg("event trigger functions cannot have declared arguments")));

			/* Add the variable tg_event */
			var = plisql_build_variable("tg_event", 0,
										 plisql_build_datatype(TEXTOID,
																-1,
																function->fn_input_collation,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_EVENT;

			/* Add the variable tg_tag */
			var = plisql_build_variable("tg_tag", 0,
										 plisql_build_datatype(TEXTOID,
																-1,
																function->fn_input_collation,
																NULL),
										 true);
			Assert(var->dtype == PLISQL_DTYPE_VAR);
			var->dtype = PLISQL_DTYPE_PROMISE;
			((PLiSQL_var *) var)->promise = PLISQL_PROMISE_TG_TAG;

			break;

		default:
			elog(ERROR, "unrecognized function typecode: %d",
				 (int) function->fn_is_trigger);
			break;
	}

	/* Remember if function is STABLE/IMMUTABLE */
	function->fn_readonly = (procStruct->provolatile != PROVOLATILE_VOLATILE);

	/*
	 * Create the magic FOUND variable.
	 */
	var = plisql_build_variable("found", 0,
								 plisql_build_datatype(BOOLOID,
														-1,
														InvalidOid,
														NULL),
								 true);
	function->found_varno = var->dno;

	/*
	 * Now parse the function's text
	 */
	parse_rc = plisql_yyparse();
	if (parse_rc != 0)
		elog(ERROR, "plisql parser returned %d", parse_rc);
	function->action = plisql_parse_result;

	/*
	 * If it has OUT parameters or returns VOID or returns a set, we allow
	 * control to fall off the end without an explicit RETURN statement. The
	 * easiest way to implement this is to add a RETURN statement to the end
	 * of the statement list during parsing.
	 */
	if (num_out_args > 0 || function->fn_rettype == VOIDOID ||
		function->fn_retset)
		add_dummy_return(function);

	/*
	 * Complete the function's info
	 */
	function->fn_nargs = procStruct->pronargs;
	for (i = 0; i < function->fn_nargs; i++)
		function->fn_argvarnos[i] = in_arg_varnos[i];

	plisql_finish_datums(function);

	plisql_finish_subproc_func(function);

	plisql_check_subproc_define(function);

	/*
	 * after plisql_check_subproc_define for nice error message
	 */
	plisql_scanner_finish();
	pfree(proc_source);

	/* Debug dump for completed functions */
	if (plisql_DumpExecTree)
		plisql_dumptree(function, 0, 0); 

	/*
	 * add it to the hash table
	 */
	plisql_HashTableInsert(function, hashkey);

	/*
	 * Pop the error context stack
	 */
	error_context_stack = plerrcontext.previous;
	plisql_error_funcname = NULL;

	plisql_check_syntax = false;

	MemoryContextSwitchTo(plisql_compile_tmp_cxt);
	plisql_compile_tmp_cxt = NULL;
	return function;
}

/* ----------
 * plisql_compile_inline	Make an execution tree for an anonymous code block.
 *
 * Note: this is generally parallel to do_compile(); is it worth trying to
 * merge the two?
 *
 * Note: we assume the block will be thrown away so there is no need to build
 * persistent data structures.
 * ----------
 */
PLiSQL_function *
plisql_compile_inline(char *proc_source)
{
	char	   *func_name = "inline_code_block";
	PLiSQL_function *function;
	ErrorContextCallback plerrcontext;
	PLiSQL_variable *var;
	int			parse_rc;
	MemoryContext func_cxt;

	/*
	 * Setup the scanner input and error info.  We assume that this function
	 * cannot be invoked recursively, so there's no need to save and restore
	 * the static variables used here.
	 */
	plisql_scanner_init(proc_source);

	plisql_error_funcname = func_name;

	/*
	 * Setup error traceback support for ereport()
	 */
	plerrcontext.callback = plisql_compile_error_callback;
	plerrcontext.arg = proc_source;
	plerrcontext.previous = error_context_stack;
	error_context_stack = &plerrcontext;

	/* Do extra syntax checking if check_function_bodies is on */
	plisql_check_syntax = check_function_bodies;

	/* Function struct does not live past current statement */
	function = (PLiSQL_function *) palloc0(sizeof(PLiSQL_function));

	plisql_curr_compile = function;

	/*
	 * All the rest of the compile-time storage (e.g. parse tree) is kept in
	 * its own memory context, so it can be reclaimed easily.
	 */
	func_cxt = AllocSetContextCreate(CurrentMemoryContext,
									 "PL/iSQL inline code context",
									 ALLOCSET_DEFAULT_SIZES);
	plisql_compile_tmp_cxt = MemoryContextSwitchTo(func_cxt);

	function->fn_signature = pstrdup(func_name);
	function->fn_is_trigger = PLISQL_NOT_TRIGGER;
	function->fn_input_collation = InvalidOid;
	function->fn_cxt = func_cxt;
	function->out_param_varno = -1; /* set up for no OUT param */
	function->resolve_option = plisql_variable_conflict;
	function->print_strict_params = plisql_print_strict_params;

	/*
	 * don't do extra validation for inline code as we don't want to add spam
	 * at runtime
	 */
	function->extra_warnings = 0;
	function->extra_errors = 0;

	function->nstatements = 0;
	function->requires_procedure_resowner = false;

	function->namelabel = NULL;

	plisql_ns_init();
	plisql_ns_push(func_name, PLISQL_LABEL_BLOCK);
	plisql_DumpExecTree = false;
	plisql_start_datums();
	cur_compile_func_level = 0;
	plisql_start_subproc_func();
	plisql_compile_packageitem = NULL;
	Assert(plisql_curr_global_proper_level == 0);
	plisql_saved_compile[cur_compile_func_level] = function;

	/* Set up as though in a function returning VOID */
	function->fn_rettype = VOIDOID;
	function->fn_retset = false;
	function->fn_retistuple = false;
	function->fn_retisdomain = false;
	function->fn_prokind = PROKIND_FUNCTION;
	/* a bit of hardwired knowledge about type VOID here */
	function->fn_retbyval = true;
	function->fn_rettyplen = sizeof(int32);

	/*
	 * Remember if function is STABLE/IMMUTABLE.  XXX would it be better to
	 * set this true inside a read-only transaction?  Not clear.
	 */
	function->fn_readonly = false;

	/*
	 * Create the magic FOUND variable.
	 */
	var = plisql_build_variable("found", 0,
								 plisql_build_datatype(BOOLOID,
														-1,
														InvalidOid,
														NULL),
								 true);
	function->found_varno = var->dno;

	/*
	 * Now parse the function's text
	 */
	parse_rc = plisql_yyparse();
	if (parse_rc != 0)
		elog(ERROR, "plisql parser returned %d", parse_rc);
	function->action = plisql_parse_result;

	/*
	 * If it returns VOID (always true at the moment), we allow control to
	 * fall off the end without an explicit RETURN statement.
	 */
	if (function->fn_rettype == VOIDOID)
		add_dummy_return(function);

	/*
	 * Complete the function's info
	 */
	function->fn_nargs = 0;

	plisql_finish_datums(function);

	plisql_finish_subproc_func(function);

	plisql_check_subproc_define(function);

	/*
	 * after plisql_check_subproc_define for nice error message
	 */
	plisql_scanner_finish();

	/*
	 * Pop the error context stack
	 */
	error_context_stack = plerrcontext.previous;
	plisql_error_funcname = NULL;

	plisql_check_syntax = false;

	MemoryContextSwitchTo(plisql_compile_tmp_cxt);
	plisql_compile_tmp_cxt = NULL;
	return function;
}


/*
 * error context callback to let us supply a call-stack traceback.
 * If we are validating or executing an anonymous code block, the function
 * source text is passed as an argument.
 */
void
plisql_compile_error_callback(void *arg)
{
	if (arg)
	{
		/*
		 * Try to convert syntax error position to reference text of original
		 * CREATE FUNCTION or DO command.
		 */
		if (function_parse_error_transpose((const char *) arg))
			return;

		/*
		 * Done if a syntax error position was reported; otherwise we have to
		 * fall back to a "near line N" report.
		 */
	}

	if (plisql_error_funcname)
		errcontext("compilation of PL/iSQL function \"%s\" near line %d",
				   plisql_error_funcname, plisql_latest_lineno());
}


/*
 * Add a name for a function parameter to the function's namespace
 */
void
add_parameter_name(PLiSQL_nsitem_type itemtype, int itemno, const char *name)
{
	/*
	 * Before adding the name, check for duplicates.  We need this even though
	 * functioncmds.c has a similar check, because that code explicitly
	 * doesn't complain about conflicting IN and OUT parameter names.  In
	 * plisql, such names are in the same namespace, so there is no way to
	 * disambiguate.
	 */
	if (plisql_ns_lookup(plisql_ns_top(), true,
						  name, NULL, NULL,
						  NULL) != NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_FUNCTION_DEFINITION),
				 errmsg("parameter name \"%s\" used more than once",
						name)));

	/* OK, add the name */
	plisql_ns_additem(itemtype, itemno, name);
}

/*
 * Add a dummy RETURN statement to the given function's body
 */
void
add_dummy_return(PLiSQL_function *function)
{
	/*
	 * If the outer block has an EXCEPTION clause, we need to make a new outer
	 * block, since the added RETURN shouldn't act like it is inside the
	 * EXCEPTION clause.  Likewise, if it has a label, wrap it in a new outer
	 * block so that EXIT doesn't skip the RETURN.
	 */
	if (function->action->exceptions != NULL ||
		function->action->label != NULL)
	{
		PLiSQL_stmt_block *new;

		new = palloc0(sizeof(PLiSQL_stmt_block));
		new->cmd_type = PLISQL_STMT_BLOCK;
		new->stmtid = ++function->nstatements;
		new->body = list_make1(function->action);

		function->action = new;
	}
	if (function->action->body == NIL ||
		((PLiSQL_stmt *) llast(function->action->body))->cmd_type != PLISQL_STMT_RETURN)
	{
		PLiSQL_stmt_return *new;

		new = palloc0(sizeof(PLiSQL_stmt_return));
		new->cmd_type = PLISQL_STMT_RETURN;
		new->stmtid = ++function->nstatements;
		new->expr = NULL;
		new->retvarno = function->out_param_varno;

		function->action->body = lappend(function->action->body, new);
	}
}


/*
 * plisql_parser_setup		set up parser hooks for dynamic parameters
 *
 * Note: this routine, and the hook functions it prepares for, are logically
 * part of plisql parsing.  But they actually run during function execution,
 * when we are ready to evaluate a SQL query or expression that has not
 * previously been parsed and planned.
 */
void
plisql_parser_setup(struct ParseState *pstate, PLiSQL_expr *expr)
{
	pstate->p_pre_columnref_hook = plisql_pre_column_ref;
	pstate->p_post_columnref_hook = plisql_post_column_ref;
	pstate->p_paramref_hook = plisql_param_ref;
	pstate->p_subprocfunc_hook = plisql_subprocfunc_ref;
	/* no need to use p_coerce_param_hook */
	pstate->p_ref_hook_state = (void *) expr;
}

/*
 * plisql_pre_column_ref		parser callback before parsing a ColumnRef
 */
static Node *
plisql_pre_column_ref(ParseState *pstate, ColumnRef *cref)
{
	PLiSQL_expr *expr = (PLiSQL_expr *) pstate->p_ref_hook_state;

	if (expr->func->resolve_option == PLISQL_RESOLVE_VARIABLE)
		return resolve_column_ref(pstate, expr, cref, false);
	else
		return NULL;
}

/*
 * plisql_post_column_ref		parser callback after parsing a ColumnRef
 */
static Node *
plisql_post_column_ref(ParseState *pstate, ColumnRef *cref, Node *var)
{
	PLiSQL_expr *expr = (PLiSQL_expr *) pstate->p_ref_hook_state;
	Node	   *myvar;

	if (expr->func->resolve_option == PLISQL_RESOLVE_VARIABLE)
		return NULL;			/* we already found there's no match */

	if (expr->func->resolve_option == PLISQL_RESOLVE_COLUMN && var != NULL)
		return NULL;			/* there's a table column, prefer that */

	/*
	 * If we find a record/row variable but can't match a field name, throw
	 * error if there was no core resolution for the ColumnRef either.  In
	 * that situation, the reference is inevitably going to fail, and
	 * complaining about the record/row variable is likely to be more on-point
	 * than the core parser's error message.  (It's too bad we don't have
	 * access to transformColumnRef's internal crerr state here, as in case of
	 * a conflict with a table name this could still be less than the most
	 * helpful error message possible.)
	 */
	myvar = resolve_column_ref(pstate, expr, cref, (var == NULL));

	if (myvar != NULL && var != NULL)
	{
		/*
		 * We could leave it to the core parser to throw this error, but we
		 * can add a more useful detail message than the core could.
		 */
		ereport(ERROR,
				(errcode(ERRCODE_AMBIGUOUS_COLUMN),
				 errmsg("column reference \"%s\" is ambiguous",
						NameListToString(cref->fields)),
				 errdetail("It could refer to either a PL/iSQL variable or a table column."),
				 parser_errposition(pstate, cref->location)));
	}

	return myvar;
}

/*
 * plisql_param_ref		parser callback for ParamRefs ($n symbols)
 */
static Node *
plisql_param_ref(ParseState *pstate, ParamRef *pref)
{
	PLiSQL_expr *expr = (PLiSQL_expr *) pstate->p_ref_hook_state;
	char		pname[32];
	PLiSQL_nsitem *nse;

	snprintf(pname, sizeof(pname), "$%d", pref->number);

	nse = plisql_ns_lookup(expr->ns, false,
							pname, NULL, NULL,
							NULL);

	if (nse == NULL)
		return NULL;			/* name not known to plisql */

	return make_datum_param(expr, nse->itemno, pref->location);
}

/*
 * resolve_column_ref		attempt to resolve a ColumnRef as a plisql var
 *
 * Returns the translated node structure, or NULL if name not found
 *
 * error_if_no_field tells whether to throw error or quietly return NULL if
 * we are able to match a record/row name but don't find a field name match.
 */
static Node *
resolve_column_ref(ParseState *pstate, PLiSQL_expr *expr,
				   ColumnRef *cref, bool error_if_no_field)
{
	PLiSQL_execstate *estate;
	PLiSQL_nsitem *nse;
	const char *name1;
	const char *name2 = NULL;
	const char *name3 = NULL;
	const char *colname = NULL;
	int			nnames;
	int			nnames_scalar = 0;
	int			nnames_wholerow = 0;
	int			nnames_field = 0;

	/*
	 * We use the function's current estate to resolve parameter data types.
	 * This is really pretty bogus because there is no provision for updating
	 * plans when those types change ...
	 */
	estate = expr->func->cur_estate;

	/*----------
	 * The allowed syntaxes are:
	 *
	 * A		Scalar variable reference, or whole-row record reference.
	 * A.B		Qualified scalar or whole-row reference, or field reference.
	 * A.B.C	Qualified record field reference.
	 * A.*		Whole-row record reference.
	 * A.B.*	Qualified whole-row record reference.
	 *----------
	 */
	switch (list_length(cref->fields))
	{
		case 1:
			{
				Node	   *field1 = (Node *) linitial(cref->fields);

				name1 = strVal(field1);
				nnames_scalar = 1;
				nnames_wholerow = 1;
				break;
			}
		case 2:
			{
				Node	   *field1 = (Node *) linitial(cref->fields);
				Node	   *field2 = (Node *) lsecond(cref->fields);

				name1 = strVal(field1);

				/* Whole-row reference? */
				if (IsA(field2, A_Star))
				{
					/* Set name2 to prevent matches to scalar variables */
					name2 = "*";
					nnames_wholerow = 1;
					break;
				}

				name2 = strVal(field2);
				colname = name2;
				nnames_scalar = 2;
				nnames_wholerow = 2;
				nnames_field = 1;
				break;
			}
		case 3:
			{
				Node	   *field1 = (Node *) linitial(cref->fields);
				Node	   *field2 = (Node *) lsecond(cref->fields);
				Node	   *field3 = (Node *) lthird(cref->fields);

				name1 = strVal(field1);
				name2 = strVal(field2);

				/* Whole-row reference? */
				if (IsA(field3, A_Star))
				{
					/* Set name3 to prevent matches to scalar variables */
					name3 = "*";
					nnames_wholerow = 2;
					break;
				}

				name3 = strVal(field3);
				colname = name3;
				nnames_field = 2;
				break;
			}
		default:
			/* too many names, ignore */
			return NULL;
	}

	nse = plisql_ns_lookup(expr->ns, false,
							name1, name2, name3,
							&nnames);
	/* maybe a package var */
	if (nse == NULL)
	{
		char		*refname;

		refname = NameListToString(cref->fields);

		nse = plisql_ns_lookup(expr->ns, false,
							refname, NULL, NULL,
							&nnames);
		pfree(refname);
		if (nse != NULL)
		{
			Assert(nse->itemtype == PLISQL_NSTYPE_VAR);
			return make_datum_param(expr, nse->itemno, cref->location);
		}
	}

	if (nse == NULL)
		return NULL;			/* name not known to plisql */

	switch (nse->itemtype)
	{
		case PLISQL_NSTYPE_VAR:
			if (nnames == nnames_scalar)
				return make_datum_param(expr, nse->itemno, cref->location);
			break;
		case PLISQL_NSTYPE_REC:
			if (nnames == nnames_wholerow)
				return make_datum_param(expr, nse->itemno, cref->location);
			if (nnames == nnames_field)
			{
				/* colname could be a field in this record */
				PLiSQL_rec *rec = (PLiSQL_rec *) estate->datums[nse->itemno];
				int			i;

				/* search for a datum referencing this field */
				i = rec->firstfield;
				while (i >= 0)
				{
					PLiSQL_recfield *fld = (PLiSQL_recfield *) estate->datums[i];

					Assert(fld->dtype == PLISQL_DTYPE_RECFIELD &&
						   fld->recparentno == nse->itemno);
					if (strcmp(fld->fieldname, colname) == 0)
					{
						return make_datum_param(expr, i, cref->location);
					}
					i = fld->nextfield;
				}

				/*
				 * We should not get here, because a RECFIELD datum should
				 * have been built at parse time for every possible qualified
				 * reference to fields of this record.  But if we do, handle
				 * it like field-not-found: throw error or return NULL.
				 */
				if (error_if_no_field)
					ereport(ERROR,
							(errcode(ERRCODE_UNDEFINED_COLUMN),
							 errmsg("record \"%s\" has no field \"%s\"",
									(nnames_field == 1) ? name1 : name2,
									colname),
							 parser_errposition(pstate, cref->location)));
			}
			break;
		case PLISQL_NSTYPE_SUBPROC_FUNC:
		case PLISQL_NSTYPE_SUBPROC_PROC:
			break;
		default:
			elog(ERROR, "unrecognized plisql itemtype: %d", nse->itemtype);
	}

	/* Name format doesn't match the plisql variable type */
	return NULL;
}

/*
 * Helper for columnref parsing: build a Param referencing a plisql datum,
 * and make sure that that datum is listed in the expression's paramnos.
 */
static Node *
make_datum_param(PLiSQL_expr *expr, int dno, int location)
{
	PLiSQL_execstate *estate;
	PLiSQL_datum *datum;
	Param	   *param;
	MemoryContext oldcontext;

	/* see comment in resolve_column_ref */
	estate = expr->func->cur_estate;
	Assert(dno >= 0 && dno < estate->ndatums);
	datum = estate->datums[dno];

	/*
	 * Bitmapset must be allocated in function's permanent memory context
	 */
	oldcontext = MemoryContextSwitchTo(expr->func->fn_cxt);
	expr->paramnos = bms_add_member(expr->paramnos, dno);
	MemoryContextSwitchTo(oldcontext);

	param = makeNode(Param);
	param->paramkind = PARAM_EXTERN;
	param->paramid = dno + 1;
	plisql_exec_get_datum_type_info(estate,
									 datum,
									 &param->paramtype,
									 &param->paramtypmod,
									 &param->paramcollid);
	param->location = location;

	return (Node *) param;
}


/* ----------
 * plisql_parse_word		The scanner calls this to postparse
 *				any single word that is not a reserved keyword.
 *
 * word1 is the downcased/dequoted identifier; it must be palloc'd in the
 * function's long-term memory context.
 *
 * yytxt is the original token text; we need this to check for quoting,
 * so that later checks for unreserved keywords work properly.
 *
 * We attempt to recognize the token as a variable only if lookup is true
 * and the plisql_IdentifierLookup context permits it.
 *
 * If recognized as a variable, fill in *wdatum and return true;
 * if not recognized, fill in *word and return false.
 * (Note: those two pointers actually point to members of the same union,
 * but for notational reasons we pass them separately.)
 * ----------
 */
bool
plisql_parse_word(char *word1, const char *yytxt, bool lookup,
				   PLwdatum *wdatum, PLword *word)
{
	PLiSQL_nsitem *ns;

	/*
	 * We should not lookup variables in DECLARE sections.  In SQL
	 * expressions, there's no need to do so either --- lookup will happen
	 * when the expression is compiled.
	 */
	if (lookup && plisql_IdentifierLookup == IDENTIFIER_LOOKUP_NORMAL)
	{
		/*
		 * Do a lookup in the current namespace stack
		 */
		ns = plisql_ns_lookup(plisql_ns_top(), false,
							   word1, NULL, NULL,
							   NULL);

		if (ns != NULL)
		{
			switch (ns->itemtype)
			{
				case PLISQL_NSTYPE_VAR:
				case PLISQL_NSTYPE_REC:
					wdatum->datum = plisql_Datums[ns->itemno];
					wdatum->ident = word1;
					wdatum->quoted = (yytxt[0] == '"');
					wdatum->nname_used = 1;
					wdatum->idents = NIL;
					return true;

					case PLISQL_NSTYPE_SUBPROC_FUNC:
					case PLISQL_NSTYPE_SUBPROC_PROC:
						break;

				default:
					/* plisql_ns_lookup should never return anything else */
					elog(ERROR, "unrecognized plisql itemtype: %d",
						 ns->itemtype);
			}
		}
		else if (!is_compile_standard_package())
		{
			/*
			 * handle var come from standard.xxx
			 * maybe a udt type construct func like udt_type(xx)
			 * so we should parse package entry
			 */
			PkgEntry *entry;
			size_t len = 8 + strlen(word1) + 2;
			char *refname = (char *) palloc0(len);
			List *idents =  list_make2(makeString("standard"),
						makeString(word1));

			snprintf(refname, len, "standard.%s", word1);

			entry = plisql_parse_package_entry(refname, -1, idents, true, true);
			pfree(refname);
			if (entry != NULL)
			{
				switch (entry->type)
				{
					case PKG_VAR:
						wdatum->datum = (PLiSQL_datum *) entry->value;
						wdatum->ident = word1;
						wdatum->quoted = false;
						wdatum->idents = NIL;
						wdatum->nname_used = 1;
						/* add namespace */
						if (plisql_ns_lookup(plisql_ns_top(), true,
							word1, NULL, NULL,
							NULL) == NULL)
							add_parameter_name(PLISQL_NSTYPE_VAR, wdatum->datum->dno, word1);
						return true;
						break;
					case PKG_TYPE:
						break;
					default:
						break;
				}
				pfree(entry);
			}
		}
	}
	/*
	 * there, make sure the local namespace has not found or
	 * we lookup standard'package first than local, which will
	 * result mistake.
	 * for example: exit when not found which then found, we
	 * mustn't use standard'found
	 */
	if (lookup &&
		plisql_IdentifierLookup != IDENTIFIER_LOOKUP_DECLARE &&
		!is_compile_standard_package() &&
		plisql_ns_lookup(plisql_ns_top(), false,
							   word1, NULL, NULL,
							   NULL) == NULL)
	{
		PkgEntry *entry;
		size_t len = 8 + strlen(word1) + 2;
		char *refname = (char *) palloc0(len);
		List *idents =  list_make2(makeString("standard"),
					makeString(word1));

		snprintf(refname, len, "standard.%s", word1);

		entry = plisql_parse_package_entry(refname, -1, idents, true, true);
		pfree(refname);
		if (entry != NULL)
		{
			switch (entry->type)
			{
				case PKG_VAR:
					wdatum->datum = (PLiSQL_datum *) entry->value;
					wdatum->ident = word1;
					wdatum->quoted = false;
					wdatum->idents = NIL;
					wdatum->nname_used = 1;
					/* add namespace */
					if (plisql_ns_lookup(plisql_ns_top(), true,
						word1, NULL, NULL,
						NULL) == NULL)
						add_parameter_name(PLISQL_NSTYPE_VAR,
										wdatum->datum->dno,
										word1);
					return true;
					break;
				case PKG_TYPE:
					break;
				default:
					break;
			}
			pfree(entry);
		}
	}

	/*
	 * Nothing found - up to now it's a word without any special meaning for
	 * us.
	 */
	word->ident = word1;
	word->quoted = (yytxt[0] == '"');
	return false;
}


/* ----------
 * plisql_parse_dblword		Same lookup for two words
 *					separated by a dot.
 * ----------
 */
bool
plisql_parse_dblword(char *word1, char *word2,
					  PLwdatum *wdatum, PLcword *cword)
{
	PLiSQL_nsitem *ns;
	List	   *idents;
	int			nnames;

	idents = list_make2(makeString(word1),
						makeString(word2));

	/*
	 * We should do nothing in DECLARE sections.  In SQL expressions, we
	 * really only need to make sure that RECFIELD datums are created when
	 * needed.  In all the cases handled by this function, returning a T_DATUM
	 * with a two-word idents string is the right thing.
	 */
	if (plisql_IdentifierLookup != IDENTIFIER_LOOKUP_DECLARE)
	{
		/*
		 * Do a lookup in the current namespace stack
		 */
		ns = plisql_ns_lookup(plisql_ns_top(), false,
							   word1, word2, NULL,
							   &nnames);
		if (ns != NULL)
		{
			switch (ns->itemtype)
			{
				case PLISQL_NSTYPE_VAR:
					/* Block-qualified reference to scalar variable. */
					wdatum->datum = plisql_Datums[ns->itemno];
					wdatum->ident = NULL;
					wdatum->quoted = false; /* not used */
					wdatum->idents = idents;
					wdatum->nname_used = nnames;
					return true;

				case PLISQL_NSTYPE_REC:
					if (nnames == 1)
					{
						/*
						 * First word is a record name, so second word could
						 * be a field in this record.  We build a RECFIELD
						 * datum whether it is or not --- any error will be
						 * detected later.
						 */
						PLiSQL_rec *rec;
						PLiSQL_recfield *new;

						rec = (PLiSQL_rec *) (plisql_Datums[ns->itemno]);
						new = plisql_build_recfield(rec, word2);

						wdatum->datum = (PLiSQL_datum *) new;
					}
					else
					{
						/* Block-qualified reference to record variable. */
						wdatum->datum = plisql_Datums[ns->itemno];
					}
					wdatum->ident = NULL;
					wdatum->quoted = false; /* not used */
					wdatum->idents = idents;
					wdatum->nname_used = nnames;
					return true;

				default:
					break;
			}
		}
		else
		{
			/*
			 * handle var come from package
			 * maybe a udt type construct func like udt_type(xx)
			 * so we should parse package entry
			 */
			PkgEntry *entry;
			size_t len = strlen(word1) + strlen(word2) + 2;
			char *refname = (char *) palloc0(len);

			snprintf(refname, len, "%s.%s", word1, word2);

			entry = plisql_parse_package_entry(refname, -1, idents, true, false);
			pfree(refname);
			if (entry != NULL)
			{
				switch (entry->type)
				{
					case PKG_VAR:
						wdatum->datum = (PLiSQL_datum *) entry->value;
						wdatum->ident = NULL;
						wdatum->quoted = false;
						wdatum->idents = idents;
						wdatum->nname_used = 2;
						return true;
						break;
					case PKG_TYPE:
						break;
					default:
						break;
				}
				pfree(entry);
			}
		}
	}

	/* Nothing found */
	cword->idents = idents;
	return false;
}


/* ----------
 * plisql_parse_tripword		Same lookup for three words
 *					separated by dots.
 * ----------
 */
bool
plisql_parse_tripword(char *word1, char *word2, char *word3,
					   PLwdatum *wdatum, PLcword *cword)
{
	PLiSQL_nsitem *ns;
	List	   *idents;
	int			nnames;

	/*
	 * We should do nothing in DECLARE sections.  In SQL expressions, we need
	 * to make sure that RECFIELD datums are created when needed, and we need
	 * to be careful about how many names are reported as belonging to the
	 * T_DATUM: the third word could be a sub-field reference, which we don't
	 * care about here.
	 */
	if (plisql_IdentifierLookup != IDENTIFIER_LOOKUP_DECLARE)
	{
		/*
		 * Do a lookup in the current namespace stack.  Must find a record
		 * reference, else ignore.
		 */
		ns = plisql_ns_lookup(plisql_ns_top(), false,
							   word1, word2, word3,
							   &nnames);
		if (ns != NULL)
		{
			switch (ns->itemtype)
			{
				case PLISQL_NSTYPE_REC:
					{
						PLiSQL_rec *rec;
						PLiSQL_recfield *new;

						rec = (PLiSQL_rec *) (plisql_Datums[ns->itemno]);
						if (nnames == 1)
						{
							/*
							 * First word is a record name, so second word
							 * could be a field in this record (and the third,
							 * a sub-field).  We build a RECFIELD datum
							 * whether it is or not --- any error will be
							 * detected later.
							 */
							new = plisql_build_recfield(rec, word2);
							idents = list_make2(makeString(word1),
												makeString(word2));
						}
						else
						{
							/* Block-qualified reference to record variable. */
							new = plisql_build_recfield(rec, word3);
							idents = list_make3(makeString(word1),
												makeString(word2),
												makeString(word3));
						}
						wdatum->datum = (PLiSQL_datum *) new;
						wdatum->ident = NULL;
						wdatum->quoted = false; /* not used */
						wdatum->idents = idents;
						wdatum->nname_used = nnames;
						return true;
					}

				default:
					break;
			}
		}
		else
		{
			/*
			 * handle var come from package
			 * it maybe is udt_type constructor func
			 * so we should parse package entry
			 */
			PkgEntry *entry;
			size_t len = strlen(word1) + strlen(word2) + strlen(word3) + 3;
			char *refname = (char *) palloc0(len);

			snprintf(refname, len, "%s.%s.%s", word1, word2, word3);
			idents = list_make3(makeString(word1),
								makeString(word2),
								makeString(word3));
			entry = plisql_parse_package_entry(refname, -1, idents, true, false);
			pfree(refname);
			if (entry != NULL)
			{
				switch (entry->type)
				{
					case PKG_VAR:
						wdatum->datum = (PLiSQL_datum *) entry->value;
						wdatum->ident = NULL;
						wdatum->quoted = false; /* not used */
						wdatum->idents = idents;
						wdatum->nname_used = 3;
						break;
					case PKG_TYPE:
						break;
					default:
						break;
				}
				pfree(entry);
				return true;
			}
		}
	}

	/* Nothing found */
	idents = list_make3(makeString(word1),
						makeString(word2),
						makeString(word3));
	cword->idents = idents;
	return false;
}


/* ----------
 * plisql_parse_wordtype	The scanner found word%TYPE. word should be
 *				a pre-existing variable name.
 *
 * Returns datatype struct.  Throws error if no match found for word.
 * ----------
 */
PLiSQL_type *
plisql_parse_wordtype(char *ident)
{
	PLiSQL_nsitem *nse;
	List		*idents;
	PLiSQL_type 	*dtype;

	/*
	 * Do a lookup in the current namespace stack
	 */
	nse = plisql_ns_lookup(plisql_ns_top(), false,
							ident, NULL, NULL,
							NULL);

	if (nse != NULL)
	{
		switch (nse->itemtype)
		{
			case PLISQL_NSTYPE_VAR:
				return ((PLiSQL_var *) (plisql_Datums[nse->itemno]))->datatype;
			case PLISQL_NSTYPE_REC:
				return ((PLiSQL_rec *) (plisql_Datums[nse->itemno]))->datatype;
			default:
				break;
		}
	}
	else
	{
		/* maybe type comes from standard package */
		if (!is_compile_standard_package())
		{
			idents = list_make2(makeString("standard"), makeString(ident));
			if ((dtype = plisql_parse_package_type(makeTypeNameFromNameList(idents),
					parse_by_var_type, true)) != NULL)
			{
				list_free(idents);
				return dtype;
			}
			list_free(idents);
		}
	}

	/* No match, complain */
	ereport(ERROR,
			(errcode(ERRCODE_UNDEFINED_OBJECT),
			 errmsg("variable \"%s\" does not exist", ident)));
	return NULL;				/* keep compiler quiet */
}


/* ----------
 * plisql_parse_cwordtype		Same lookup for compositeword%TYPE
 *
 * Here, we allow either a block-qualified variable name, or a reference
 * to a column of some table.  (If we must throw error, we assume that the
 * latter case was intended.)
 * ----------
 */
PLiSQL_type *
plisql_parse_cwordtype(List *idents)
{
	PLiSQL_type *dtype = NULL;
	PLiSQL_nsitem *nse;
	int			nnames;
	RangeVar   *relvar = NULL;
	const char *fldname = NULL;
	Oid			classOid;
	HeapTuple	attrtup = NULL;
	HeapTuple	typetup = NULL;
	Form_pg_attribute attrStruct;
	MemoryContext oldCxt;

	/* Avoid memory leaks in the long-term function context */
	oldCxt = MemoryContextSwitchTo(plisql_compile_tmp_cxt);

	if (list_length(idents) == 2)
	{
		/*
		 * Do a lookup in the current namespace stack
		 */
		nse = plisql_ns_lookup(plisql_ns_top(), false,
								strVal(linitial(idents)),
								strVal(lsecond(idents)),
								NULL,
								&nnames);

		if (nse != NULL && nse->itemtype == PLISQL_NSTYPE_VAR)
		{
			/* Block-qualified reference to scalar variable. */
			dtype = ((PLiSQL_var *) (plisql_Datums[nse->itemno]))->datatype;
			goto done;
		}
		else if (nse != NULL && nse->itemtype == PLISQL_NSTYPE_REC &&
				 nnames == 2)
		{
			/* Block-qualified reference to record variable. */
			dtype = ((PLiSQL_rec *) (plisql_Datums[nse->itemno]))->datatype;
			goto done;
		}

		/* maybe type comes from package */
		if ((dtype = plisql_parse_package_type(makeTypeNameFromNameList(idents),
				parse_by_var_type, false)) != NULL)
		{
			goto done;
		}

		/*
		 * First word could also be a table name
		 */
		relvar = makeRangeVar(NULL,
							  strVal(linitial(idents)),
							  -1);
		fldname = strVal(lsecond(idents));
	}
	else
	{
		/*
		 * We could check for a block-qualified reference to a field of a
		 * record variable, but %TYPE is documented as applying to variables,
		 * not fields of variables.  Things would get rather ambiguous if we
		 * allowed either interpretation.
		 */
		List	   *rvnames;

		Assert(list_length(idents) > 2);

		if (list_length(idents) == 3)
		{
			if ((dtype = plisql_parse_package_type(makeTypeNameFromNameList(idents),
							parse_by_var_type, false)) != NULL)
			{
				goto done;
			}
		}

		rvnames = list_delete_last(list_copy(idents));
		relvar = makeRangeVarFromNameList(rvnames);
		fldname = strVal(llast(idents));
	}

	/* Look up relation name.  Can't lock it - we might not have privileges. */
	classOid = RangeVarGetRelid(relvar, NoLock, false);

	/*
	 * Fetch the named table field and its type
	 */
	attrtup = SearchSysCacheAttName(classOid, fldname);
	if (!HeapTupleIsValid(attrtup))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_COLUMN),
				 errmsg("column \"%s\" of relation \"%s\" does not exist",
						fldname, relvar->relname)));
	attrStruct = (Form_pg_attribute) GETSTRUCT(attrtup);

	typetup = SearchSysCache1(TYPEOID,
							  ObjectIdGetDatum(attrStruct->atttypid));
	if (!HeapTupleIsValid(typetup))
		elog(ERROR, "cache lookup failed for type %u", attrStruct->atttypid);

	/*
	 * Found that - build a compiler type struct in the caller's cxt and
	 * return it.  Note that we treat the type as being found-by-OID; no
	 * attempt to re-look-up the type name will happen during invalidations.
	 */
	MemoryContextSwitchTo(oldCxt);
	dtype = build_datatype(typetup,
						   attrStruct->atttypmod,
						   attrStruct->attcollation,
						   NULL);
	MemoryContextSwitchTo(plisql_compile_tmp_cxt);

done:
	if (HeapTupleIsValid(attrtup))
		ReleaseSysCache(attrtup);
	if (HeapTupleIsValid(typetup))
		ReleaseSysCache(typetup);

	MemoryContextSwitchTo(oldCxt);
	return dtype;
}

/* ----------
 * plisql_parse_wordrowtype		Scanner found word%ROWTYPE.
 *					So word must be a table name.
 * ----------
 */
PLiSQL_type *
plisql_parse_wordrowtype(char *ident)
{
	Oid			classOid;
	Oid			typOid;
	PLiSQL_type	*result;
	TypeName	*typname;
	bool		missing_ok = false;

	typname = typeStringToTypeName(ident, NULL);
	if (list_length(typname->names) < 2 &&
		!is_compile_standard_package())
	{
		/* may be a standard.type */
		size_t len = 8 + strlen(ident) + 2;
		char *refname = (char *) palloc0(len);

		snprintf(refname, len, "standard.%s", ident);
		pfree(typname);
		typname = typeStringToTypeName(refname, NULL);
		pfree(refname);
		missing_ok = true;
	}
	result = plisql_parse_package_type(typname, parse_by_var_rowtype, missing_ok);
	if (result != NULL)
	{	pfree(typname);
		return result;
	}
	pfree(typname);

	/*
	 * Look up the relation.  Note that because relation rowtypes have the
	 * same names as their relations, this could be handled as a type lookup
	 * equally well; we use the relation lookup code path only because the
	 * errors thrown here have traditionally referred to relations not types.
	 * But we'll make a TypeName in case we have to do re-look-up of the type.
	 */
	classOid = RelnameGetRelid(ident);
	if (!OidIsValid(classOid))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_TABLE),
				 errmsg("relation \"%s\" does not exist", ident)));

	/* Some relkinds lack type OIDs */
	typOid = get_rel_type_id(classOid);
	if (!OidIsValid(typOid))
		ereport(ERROR,
				(errcode(ERRCODE_WRONG_OBJECT_TYPE),
				 errmsg("relation \"%s\" does not have a composite type",
						ident)));

	/* Build and return the row type struct */
	return plisql_build_datatype(typOid, -1, InvalidOid,
								  makeTypeName(ident));
}

/* ----------
 * plisql_parse_cwordrowtype		Scanner found compositeword%ROWTYPE.
 *			So word must be a namespace qualified table name.
 * ----------
 */
PLiSQL_type *
plisql_parse_cwordrowtype(List *idents)
{
	Oid			classOid;
	Oid			typOid;
	RangeVar   *relvar;
	MemoryContext oldCxt;
	PLiSQL_type	*result;

	result = plisql_parse_package_type(makeTypeNameFromNameList(idents),
							parse_by_var_rowtype, false);
	if (result != NULL)
		return result;

	/*
	 * As above, this is a relation lookup but could be a type lookup if we
	 * weren't being backwards-compatible about error wording.
	 */

	/* Avoid memory leaks in long-term function context */
	oldCxt = MemoryContextSwitchTo(plisql_compile_tmp_cxt);

	/* Look up relation name.  Can't lock it - we might not have privileges. */
	relvar = makeRangeVarFromNameList(idents);
	classOid = RangeVarGetRelid(relvar, NoLock, false);

	/* Some relkinds lack type OIDs */
	typOid = get_rel_type_id(classOid);
	if (!OidIsValid(typOid))
		ereport(ERROR,
				(errcode(ERRCODE_WRONG_OBJECT_TYPE),
				 errmsg("relation \"%s\" does not have a composite type",
						relvar->relname)));

	MemoryContextSwitchTo(oldCxt);

	/* Build and return the row type struct */
	return plisql_build_datatype(typOid, -1, InvalidOid,
								  makeTypeNameFromNameList(idents));
}

/*
 * plisql_build_variable - build a datum-array entry of a given
 * datatype
 *
 * The returned struct may be a PLiSQL_var or PLiSQL_rec
 * depending on the given datatype, and is allocated via
 * palloc.  The struct is automatically added to the current datum
 * array, and optionally to the current namespace.
 */
PLiSQL_variable *
plisql_build_variable(const char *refname, int lineno, PLiSQL_type *dtype,
					   bool add2namespace)
{
	PLiSQL_variable *result;

	switch (dtype->ttype)
	{
		case PLISQL_TTYPE_SCALAR:
			{
				/* Ordinary scalar datatype */
				PLiSQL_var *var;

				var = palloc0(sizeof(PLiSQL_var));
				var->dtype = PLISQL_DTYPE_VAR;
				var->refname = pstrdup(refname);
				var->lineno = lineno;
				var->datatype = dtype;
				/* other fields are left as 0, might be changed by caller */

				/* preset to NULL */
				var->value = 0;
				var->isnull = true;
				var->freeval = false;
				var->pkgoid = (plisql_compile_packageitem == NULL ? InvalidOid : plisql_compile_packageitem->source.fn_oid);

				plisql_adddatum((PLiSQL_datum *) var);
				if (add2namespace)
					plisql_ns_additem(PLISQL_NSTYPE_VAR,
									   var->dno,
									   refname);
				result = (PLiSQL_variable *) var;
				break;
			}
		case PLISQL_TTYPE_REC:
			{
				/* Composite type -- build a record variable */
				PLiSQL_rec *rec;

				rec = plisql_build_record(refname, lineno,
										   dtype, dtype->typoid,
										   add2namespace);
				result = (PLiSQL_variable *) rec;
				break;
			}
		case PLISQL_TTYPE_PSEUDO:
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("variable \"%s\" has pseudo-type %s",
							refname, format_type_be(dtype->typoid))));
			result = NULL;		/* keep compiler quiet */
			break;
		default:
			elog(ERROR, "unrecognized ttype: %d", dtype->ttype);
			result = NULL;		/* keep compiler quiet */
			break;
	}

	return result;
}

/*
 * Build empty named record variable, and optionally add it to namespace
 */
PLiSQL_rec *
plisql_build_record(const char *refname, int lineno,
					 PLiSQL_type *dtype, Oid rectypeid,
					 bool add2namespace)
{
	PLiSQL_rec *rec;

	rec = palloc0(sizeof(PLiSQL_rec));
	rec->dtype = PLISQL_DTYPE_REC;
	rec->refname = pstrdup(refname);
	rec->lineno = lineno;
	/* other fields are left as 0, might be changed by caller */
	rec->datatype = dtype;
	rec->rectypeid = rectypeid;
	rec->firstfield = -1;
	rec->erh = NULL;
	plisql_adddatum((PLiSQL_datum *) rec);
	if (add2namespace)
		plisql_ns_additem(PLISQL_NSTYPE_REC, rec->dno, rec->refname);

	rec->pkgoid = (plisql_compile_packageitem == NULL ? InvalidOid : plisql_compile_packageitem->source.fn_oid);
	/*
	 * there, if we compile package, and build a rec like table%rowtype
	 * but others function or package first reference it first filed and then
	 * lookup it in package, but its doesn't find, because compile package
	 * doesn't references it, should we add datum during exec?
	 * this is not fine, so we add all recfiled in compile
	 * maybe it can expand out of package
	 */
	if (OidIsValid(rec->pkgoid))
		plisql_expand_rec_field(rec);

	return rec;
}

/*
 * Build a row-variable data structure given the component variables.
 * Include a rowtupdesc, since we will need to materialize the row result.
 */
PLiSQL_row *
build_row_from_vars(PLiSQL_variable **vars, int numvars)
{
	PLiSQL_row *row;
	int			i;

	row = palloc0(sizeof(PLiSQL_row));
	row->dtype = PLISQL_DTYPE_ROW;
	row->refname = "(unnamed row)";
	row->lineno = -1;
	row->rowtupdesc = CreateTemplateTupleDesc(numvars);
	row->nfields = numvars;
	row->fieldnames = palloc(numvars * sizeof(char *));
	row->varnos = palloc(numvars * sizeof(int));

	for (i = 0; i < numvars; i++)
	{
		PLiSQL_variable *var = vars[i];
		Oid			typoid;
		int32		typmod;
		Oid			typcoll;

		/* Member vars of a row should never be const */
		Assert(!var->isconst);

		switch (var->dtype)
		{
			case PLISQL_DTYPE_VAR:
			case PLISQL_DTYPE_PROMISE:
				typoid = ((PLiSQL_var *) var)->datatype->typoid;
				typmod = ((PLiSQL_var *) var)->datatype->atttypmod;
				typcoll = ((PLiSQL_var *) var)->datatype->collation;
				break;

			case PLISQL_DTYPE_REC:
				/* shouldn't need to revalidate rectypeid already... */
				typoid = ((PLiSQL_rec *) var)->rectypeid;
				typmod = -1;	/* don't know typmod, if it's used at all */
				typcoll = InvalidOid;	/* composite types have no collation */
				break;

			default:
				elog(ERROR, "unrecognized dtype: %d", var->dtype);
				typoid = InvalidOid;	/* keep compiler quiet */
				typmod = 0;
				typcoll = InvalidOid;
				break;
		}

		row->fieldnames[i] = var->refname;
		row->varnos[i] = var->dno;

		TupleDescInitEntry(row->rowtupdesc, i + 1,
						   var->refname,
						   typoid, typmod,
						   0);
		TupleDescInitEntryCollation(row->rowtupdesc, i + 1, typcoll);
	}

	return row;
}

/*
 * Build a RECFIELD datum for the named field of the specified record variable
 *
 * If there's already such a datum, just return it; we don't need duplicates.
 */
PLiSQL_recfield *
plisql_build_recfield(PLiSQL_rec *rec, const char *fldname)
{
	PLiSQL_recfield *recfield;
	int			i;

	/* search for an existing datum referencing this field */
	i = rec->firstfield;
	while (i >= 0)
	{
		PLiSQL_recfield *fld = (PLiSQL_recfield *) plisql_Datums[i];

		Assert(fld->dtype == PLISQL_DTYPE_RECFIELD &&
			   fld->recparentno == rec->dno);
		if (strcmp(fld->fieldname, fldname) == 0)
			return fld;
		i = fld->nextfield;
	}

	/* nope, so make a new one */
	recfield = palloc0(sizeof(PLiSQL_recfield));
	recfield->dtype = PLISQL_DTYPE_RECFIELD;
	recfield->fieldname = pstrdup(fldname);
	recfield->recparentno = rec->dno;
	recfield->rectupledescid = INVALID_TUPLEDESC_IDENTIFIER;
	recfield->pkgoid = (plisql_compile_packageitem == NULL ? InvalidOid : plisql_compile_packageitem->source.fn_oid);

	plisql_adddatum((PLiSQL_datum *) recfield);

	/* now we can link it into the parent's chain */
	recfield->nextfield = rec->firstfield;
	rec->firstfield = recfield->dno;

	return recfield;
}

/*
 * plisql_build_datatype
 *		Build PLiSQL_type struct given type OID, typmod, collation,
 *		and type's parsed name.
 *
 * If collation is not InvalidOid then it overrides the type's default
 * collation.  But collation is ignored if the datatype is non-collatable.
 *
 * origtypname is the parsed form of what the user wrote as the type name.
 * It can be NULL if the type could not be a composite type, or if it was
 * identified by OID to begin with (e.g., it's a function argument type).
 */
PLiSQL_type *
plisql_build_datatype(Oid typeOid, int32 typmod,
					   Oid collation, TypeName *origtypname)
{
	HeapTuple	typeTup;
	PLiSQL_type *typ;

	typeTup = SearchSysCache1(TYPEOID, ObjectIdGetDatum(typeOid));
	if (!HeapTupleIsValid(typeTup))
		elog(ERROR, "cache lookup failed for type %u", typeOid);

	typ = build_datatype(typeTup, typmod, collation, origtypname);

	ReleaseSysCache(typeTup);

	return typ;
}

/*
 * Utility subroutine to make a PLiSQL_type struct given a pg_type entry
 * and additional details (see comments for plisql_build_datatype).
 */
static PLiSQL_type *
build_datatype(HeapTuple typeTup, int32 typmod,
			   Oid collation, TypeName *origtypname)
{
	Form_pg_type typeStruct = (Form_pg_type) GETSTRUCT(typeTup);
	PLiSQL_type *typ;

	if (!typeStruct->typisdefined)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("type \"%s\" is only a shell",
						NameStr(typeStruct->typname))));

	typ = (PLiSQL_type *) palloc(sizeof(PLiSQL_type));

	typ->typname = pstrdup(NameStr(typeStruct->typname));
	typ->typoid = typeStruct->oid;
	switch (typeStruct->typtype)
	{
		case TYPTYPE_BASE:
		case TYPTYPE_ENUM:
		case TYPTYPE_RANGE:
		case TYPTYPE_MULTIRANGE:
			typ->ttype = PLISQL_TTYPE_SCALAR;
			break;
		case TYPTYPE_COMPOSITE:
			typ->ttype = PLISQL_TTYPE_REC;
			break;
		case TYPTYPE_DOMAIN:
			if (type_is_rowtype(typeStruct->typbasetype))
				typ->ttype = PLISQL_TTYPE_REC;
			else
				typ->ttype = PLISQL_TTYPE_SCALAR;
			break;
		case TYPTYPE_PSEUDO:
			if (typ->typoid == RECORDOID)
				typ->ttype = PLISQL_TTYPE_REC;
			else
				typ->ttype = PLISQL_TTYPE_PSEUDO;
			break;
		default:
			elog(ERROR, "unrecognized typtype: %d",
				 (int) typeStruct->typtype);
			break;
	}
	typ->typlen = typeStruct->typlen;
	typ->typbyval = typeStruct->typbyval;
	typ->typtype = typeStruct->typtype;
	typ->collation = typeStruct->typcollation;
	if (OidIsValid(collation) && OidIsValid(typ->collation))
		typ->collation = collation;
	/* Detect if type is true array, or domain thereof */
	/* NB: this is only used to decide whether to apply expand_array */
	if (typeStruct->typtype == TYPTYPE_BASE)
	{
		/*
		 * This test should include what get_element_type() checks.  We also
		 * disallow non-toastable array types (i.e. oidvector and int2vector).
		 */
		typ->typisarray = (IsTrueArrayType(typeStruct) &&
						   typeStruct->typstorage != TYPSTORAGE_PLAIN);
	}
	else if (typeStruct->typtype == TYPTYPE_DOMAIN)
	{
		/* we can short-circuit looking up base types if it's not varlena */
		typ->typisarray = (typeStruct->typlen == -1 &&
						   typeStruct->typstorage != TYPSTORAGE_PLAIN &&
						   OidIsValid(get_base_element_type(typeStruct->typbasetype)));
	}
	else
		typ->typisarray = false;
	typ->atttypmod = typmod;

	/*
	 * If it's a named composite type (or domain over one), find the typcache
	 * entry and record the current tupdesc ID, so we can detect changes
	 * (including drops).  We don't currently support on-the-fly replacement
	 * of non-composite types, else we might want to do this for them too.
	 */
	if (typ->ttype == PLISQL_TTYPE_REC && typ->typoid != RECORDOID)
	{
		TypeCacheEntry *typentry;

		typentry = lookup_type_cache(typ->typoid,
									 TYPECACHE_TUPDESC |
									 TYPECACHE_DOMAIN_BASE_INFO);
		if (typentry->typtype == TYPTYPE_DOMAIN)
			typentry = lookup_type_cache(typentry->domainBaseType,
										 TYPECACHE_TUPDESC);
		if (typentry->tupDesc == NULL)
			ereport(ERROR,
					(errcode(ERRCODE_WRONG_OBJECT_TYPE),
					 errmsg("type %s is not composite",
							format_type_be(typ->typoid))));

		typ->origtypname = origtypname;
		typ->tcache = typentry;
		typ->tupdesc_id = typentry->tupDesc_identifier;
	}
	else
	{
		typ->origtypname = NULL;
		typ->tcache = NULL;
		typ->tupdesc_id = 0;
	}

	return typ;
}

/*
 * Build an array type for the element type specified as argument.
 */
PLiSQL_type *
plisql_build_datatype_arrayof(PLiSQL_type *dtype)
{
	Oid			array_typeid;

	/*
	 * If it's already an array type, use it as-is: Postgres doesn't do nested
	 * arrays.
	 */
	if (dtype->typisarray)
		return dtype;

	array_typeid = get_array_type(dtype->typoid);
	if (!OidIsValid(array_typeid))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("could not find array type for data type %s",
						format_type_be(dtype->typoid))));

	/* Note we inherit typmod and collation, if any, from the element type */
	return plisql_build_datatype(array_typeid, dtype->atttypmod,
								  dtype->collation, NULL);
}

/*
 *	plisql_recognize_err_condition
 *		Check condition name and translate it to SQLSTATE.
 *
 * Note: there are some cases where the same condition name has multiple
 * entries in the table.  We arbitrarily return the first match.
 */
int
plisql_recognize_err_condition(const char *condname, bool allow_sqlstate)
{
	int			i;

	if (allow_sqlstate)
	{
		if (strlen(condname) == 5 &&
			strspn(condname, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ") == 5)
			return MAKE_SQLSTATE(condname[0],
								 condname[1],
								 condname[2],
								 condname[3],
								 condname[4]);
	}

	for (i = 0; exception_label_map[i].label != NULL; i++)
	{
		if (strcmp(condname, exception_label_map[i].label) == 0)
			return exception_label_map[i].sqlerrstate;
	}

	ereport(ERROR,
			(errcode(ERRCODE_UNDEFINED_OBJECT),
			 errmsg("unrecognized exception condition \"%s\"",
					condname)));
	return 0;					/* keep compiler quiet */
}

/*
 * plisql_parse_err_condition
 *		Generate PLiSQL_condition entry(s) for an exception condition name
 *
 * This has to be able to return a list because there are some duplicate
 * names in the table of error code names.
 */
PLiSQL_condition *
plisql_parse_err_condition(char *condname)
{
	int			i;
	PLiSQL_condition *new;
	PLiSQL_condition *prev;

	/*
	 * XXX Eventually we will want to look for user-defined exception names
	 * here.
	 */

	/*
	 * OTHERS is represented as code 0 (which would map to '00000', but we
	 * have no need to represent that as an exception condition).
	 */
	if (strcmp(condname, "others") == 0)
	{
		new = palloc(sizeof(PLiSQL_condition));
		new->sqlerrstate = 0;
		new->condname = condname;
		new->next = NULL;
		return new;
	}

	prev = NULL;
	for (i = 0; exception_label_map[i].label != NULL; i++)
	{
		if (strcmp(condname, exception_label_map[i].label) == 0)
		{
			new = palloc(sizeof(PLiSQL_condition));
			new->sqlerrstate = exception_label_map[i].sqlerrstate;
			new->condname = condname;
			new->next = prev;
			prev = new;
		}
	}

	if (!prev)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("unrecognized exception condition \"%s\"",
						condname)));

	return prev;
}

/* ----------
 * plisql_start_datums			Initialize datum list at compile startup.
 * ----------
 */
void
plisql_start_datums(void)
{
	datums_alloc = 128;
	plisql_nDatums = 0;
	/* This is short-lived, so needn't allocate in function's cxt */
	plisql_Datums = MemoryContextAlloc(plisql_compile_tmp_cxt,
										sizeof(PLiSQL_datum *) * datums_alloc);
	/* datums_last tracks what's been seen by plisql_add_initdatums() */
	datums_last = 0;
}

/* ----------
 * plisql_adddatum			Add a variable, record or row
 *					to the compiler's datum list.
 * ----------
 */
void
plisql_adddatum(PLiSQL_datum *newdatum)
{
	if (plisql_nDatums == datums_alloc)
	{
		datums_alloc *= 2;
		plisql_Datums = repalloc(plisql_Datums, sizeof(PLiSQL_datum *) * datums_alloc);
	}

	newdatum->dno = plisql_nDatums;
	plisql_Datums[plisql_nDatums++] = newdatum;
}

/* ----------
 * plisql_finish_datums	Copy completed datum info into function struct.
 * ----------
 */
void
plisql_finish_datums(PLiSQL_function *function)
{
	Size		copiable_size = 0;
	int			i;

	/*
	 * maybe compile a package body which function->ndatums not null
	 */
	if (function->item != NULL)
	{
		Assert(function->ndatums <= plisql_nDatums);

		if (function->ndatums == plisql_nDatums)
			return;
		if (function->ndatums != 0)
			function->datums = repalloc(function->datums,
									sizeof(PLiSQL_datum *) * plisql_nDatums);
		else
			function->datums = palloc(sizeof(PLiSQL_datum *) * plisql_nDatums);
		function->ndatums = plisql_nDatums;
	}
	else
	{
		function->ndatums = plisql_nDatums;
		function->datums = palloc(sizeof(PLiSQL_datum *) * plisql_nDatums);
	}
	for (i = 0; i < plisql_nDatums; i++)
	{
		function->datums[i] = plisql_Datums[i];

		/* This must agree with copy_plisql_datums on what is copiable */
		switch (function->datums[i]->dtype)
		{
			case PLISQL_DTYPE_VAR:
			case PLISQL_DTYPE_PROMISE:
				copiable_size += MAXALIGN(sizeof(PLiSQL_var));
				break;
			case PLISQL_DTYPE_REC:
				copiable_size += MAXALIGN(sizeof(PLiSQL_rec));
				break;
			default:
				break;
		}
	}
	function->copiable_size = copiable_size;
}


/* ----------
 * plisql_add_initdatums		Make an array of the datum numbers of
 *					all the initializable datums created since the last call
 *					to this function.
 *
 * If varnos is NULL, we just forget any datum entries created since the
 * last call.
 *
 * This is used around a DECLARE section to create a list of the datums
 * that have to be initialized at block entry.  Note that datums can also
 * be created elsewhere than DECLARE, eg by a FOR-loop, but it is then
 * the responsibility of special-purpose code to initialize them.
 * ----------
 */
int
plisql_add_initdatums(int **varnos)
{
	int			i;
	int			n = 0;

	/*
	 * The set of dtypes recognized here must match what exec_stmt_block()
	 * cares about (re)initializing at block entry.
	 */
	for (i = datums_last; i < plisql_nDatums; i++)
	{
		switch (plisql_Datums[i]->dtype)
		{
			case PLISQL_DTYPE_VAR:
			case PLISQL_DTYPE_REC:
				n++;
				break;

			default:
				break;
		}
	}

	if (varnos != NULL)
	{
		if (n > 0)
		{
			*varnos = (int *) palloc(sizeof(int) * n);

			n = 0;
			for (i = datums_last; i < plisql_nDatums; i++)
			{
				switch (plisql_Datums[i]->dtype)
				{
					case PLISQL_DTYPE_VAR:
					case PLISQL_DTYPE_REC:
						(*varnos)[n++] = plisql_Datums[i]->dno;

					default:
						break;
				}
			}
		}
		else
			*varnos = NULL;
	}

	datums_last = plisql_nDatums;
	return n;
}


/*
 * Compute the hashkey for a given function invocation
 *
 * The hashkey is returned into the caller-provided storage at *hashkey.
 */
static void
compute_function_hashkey(FunctionCallInfo fcinfo,
						 Form_pg_proc procStruct,
						 PLiSQL_func_hashkey *hashkey,
						 bool forValidator, 
						 HeapTuple procTup) 
{
	/* Make sure any unused bytes of the struct are zero */
	MemSet(hashkey, 0, sizeof(PLiSQL_func_hashkey));

	/* get function OID */
	hashkey->funcOid = fcinfo->flinfo->fn_oid;

	/* get call context */
	hashkey->isTrigger = CALLED_AS_TRIGGER(fcinfo);
	hashkey->isEventTrigger = CALLED_AS_EVENT_TRIGGER(fcinfo);

	/*
	 * If DML trigger, include trigger's OID in the hash, so that each trigger
	 * usage gets a different hash entry, allowing for e.g. different relation
	 * rowtypes or transition table names.  In validation mode we do not know
	 * what relation or transition table names are intended to be used, so we
	 * leave trigOid zero; the hash entry built in this case will never be
	 * used for any actual calls.
	 *
	 * We don't currently need to distinguish different event trigger usages
	 * in the same way, since the special parameter variables don't vary in
	 * type in that case.
	 */
	if (hashkey->isTrigger && !forValidator)
	{
		TriggerData *trigdata = (TriggerData *) fcinfo->context;

		hashkey->trigOid = trigdata->tg_trigger->tgoid;
	}

	/* get input collation, if known */
	hashkey->inputCollation = fcinfo->fncollation;

	if (procStruct->pronargs > 0)
	{
		/* get the argument types */
		Datum protypenames;
		bool	isNull;
		Datum	   *elems;
		int			nelems;
		char **argtypenames = NULL;
		int i;

		protypenames = SysCacheGetAttr(PROCOID, procTup,
									Anum_pg_proc_protypenames,
									&isNull);
		if (!isNull)
		{
			deconstruct_array(DatumGetArrayTypeP(protypenames),
								TEXTOID, -1, false, 'i',
								&elems, NULL, &nelems);
			argtypenames = (char **) palloc(sizeof(char *) * nelems);
			for (i = 0; i < nelems; i++)
				argtypenames[i] = TextDatumGetCString(elems[i]);
		}
		if (argtypenames != NULL)
		{
			for (i = 0; i < procStruct->pronargs; i++)
			{
				hashkey->argtypes[i] = procStruct->proargtypes.values[i];
				if (strcmp(argtypenames[i], "") != 0)
				{
					TypeName	*tname;
					PkgType *pkgtype;

					tname = (TypeName *) stringToNode(argtypenames[i]);

					pkgtype = LookupPkgTypeByTypename(tname->names, false);
					if (pkgtype == NULL)
						elog(ERROR, "package doesn't exist");
					hashkey->argtypes[i] = pkgtype->basetypid;
					pfree(tname);
					pfree(pkgtype);
				}
			}
		}
		else
			memcpy(hashkey->argtypes, procStruct->proargtypes.values,
				procStruct->pronargs * sizeof(Oid));

		/* resolve any polymorphic argument types */
		plisql_resolve_polymorphic_argtypes(procStruct->pronargs,
											 hashkey->argtypes,
											 NULL,
											 fcinfo->flinfo->fn_expr,
											 forValidator,
											 NameStr(procStruct->proname));
	}
}

/*
 * This is the same as the standard resolve_polymorphic_argtypes() function,
 * except that:
 * 1. We go ahead and report the error if we can't resolve the types.
 * 2. We treat RECORD-type input arguments (not output arguments) as if
 *    they were polymorphic, replacing their types with the actual input
 *    types if we can determine those.  This allows us to create a separate
 *    function cache entry for each named composite type passed to such an
 *    argument.
 * 3. In validation mode, we have no inputs to look at, so assume that
 *    polymorphic arguments are integer, integer-array or integer-range.
 */
void
plisql_resolve_polymorphic_argtypes(int numargs,
									 Oid *argtypes, char *argmodes,
									 Node *call_expr, bool forValidator,
									 const char *proname)
{
	int			i;

	if (!forValidator)
	{
		int			inargno;

		/* normal case, pass to standard routine */
		if (!resolve_polymorphic_argtypes(numargs, argtypes, argmodes,
										  call_expr))
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("could not determine actual argument "
							"type for polymorphic function \"%s\"",
							proname)));
		/* also, treat RECORD inputs (but not outputs) as polymorphic */
		inargno = 0;
		for (i = 0; i < numargs; i++)
		{
			char		argmode = argmodes ? argmodes[i] : PROARGMODE_IN;

			if (argmode == PROARGMODE_OUT || argmode == PROARGMODE_TABLE)
				continue;
			if (argtypes[i] == RECORDOID || argtypes[i] == RECORDARRAYOID)
			{
				Oid			resolvedtype = get_call_expr_argtype(call_expr,
																 inargno);

				if (OidIsValid(resolvedtype))
					argtypes[i] = resolvedtype;
			}
			inargno++;
		}
	}
	else
	{
		/* special validation case (no need to do anything for RECORD) */
		for (i = 0; i < numargs; i++)
		{
			switch (argtypes[i])
			{
				case ANYELEMENTOID:
				case ANYNONARRAYOID:
				case ANYENUMOID:	/* XXX dubious */
				case ANYCOMPATIBLEOID:
				case ANYCOMPATIBLENONARRAYOID:
					argtypes[i] = INT4OID;
					break;
				case ANYARRAYOID:
				case ANYCOMPATIBLEARRAYOID:
					argtypes[i] = INT4ARRAYOID;
					break;
				case ANYRANGEOID:
				case ANYCOMPATIBLERANGEOID:
					argtypes[i] = INT4RANGEOID;
					break;
				case ANYMULTIRANGEOID:
					argtypes[i] = INT4MULTIRANGEOID;
					break;
				default:
					break;
			}
		}
	}
}

/*
 * delete_function - clean up as much as possible of a stale function cache
 *
 * We can't release the PLiSQL_function struct itself, because of the
 * possibility that there are fn_extra pointers to it.  We can release
 * the subsidiary storage, but only if there are no active evaluations
 * in progress.  Otherwise we'll just leak that storage.  Since the
 * case would only occur if a pg_proc update is detected during a nested
 * recursive call on the function, a leak seems acceptable.
 *
 * Note that this can be called more than once if there are multiple fn_extra
 * pointers to the same function cache.  Hence be careful not to do things
 * twice.
 */
void
delete_function(PLiSQL_function *func)
{
	/* remove function from hash table (might be done already) */
	plisql_HashTableDelete(func);

	/* release the function's storage if safe and not done already */
	if (func->use_count == 0)
		plisql_free_function_memory(func, 0, 0);
}

/* exported so we can call it from _PG_init() */
void
plisql_HashTableInit(void)
{
	HASHCTL		ctl;

	/* don't allow double-initialization */
	Assert(plisql_HashTable == NULL);

	ctl.keysize = sizeof(PLiSQL_func_hashkey);
	ctl.entrysize = sizeof(plisql_HashEnt);
	plisql_HashTable = hash_create("PLiSQL function hash",
									FUNCS_PER_USER,
									&ctl,
									HASH_ELEM | HASH_BLOBS);
}

static PLiSQL_function *
plisql_HashTableLookup(PLiSQL_func_hashkey *func_key)
{
	plisql_HashEnt *hentry;

	hentry = (plisql_HashEnt *) hash_search(plisql_HashTable,
											 func_key,
											 HASH_FIND,
											 NULL);
	if (hentry)
		return hentry->function;
	else
		return NULL;
}

static void
plisql_HashTableInsert(PLiSQL_function *function,
						PLiSQL_func_hashkey *func_key)
{
	plisql_HashEnt *hentry;
	bool		found;

	hentry = (plisql_HashEnt *) hash_search(plisql_HashTable,
											 func_key,
											 HASH_ENTER,
											 &found);
	if (found)
		elog(WARNING, "trying to insert a function that already exists");

	hentry->function = function;
	/* prepare back link from function to hashtable key */
	function->fn_hashkey = &hentry->key;
}

static void
plisql_HashTableDelete(PLiSQL_function *function)
{
	plisql_HashEnt *hentry;

	/* do nothing if not in table */
	if (function->fn_hashkey == NULL)
		return;

	hentry = (plisql_HashEnt *) hash_search(plisql_HashTable,
											 function->fn_hashkey,
											 HASH_REMOVE,
											 NULL);
	if (hentry == NULL)
		elog(WARNING, "trying to delete function that does not exist");

	/* remove back link, which no longer points to allocated storage */
	function->fn_hashkey = NULL;
}
