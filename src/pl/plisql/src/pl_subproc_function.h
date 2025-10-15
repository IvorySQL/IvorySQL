/*-------------------------------------------------------------------------
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
 * File:pl_subproc_function.h
 *
 * Overview:
 *   Interfaces and data structures for nested sub-functions/sub-procedures
 *   ("subprocs") in the PL/ISQL procedural language.
 *   This header serves as the canonical module overview to avoid duplication
 *   with the implementation file.
 *
 *
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_subproc_function.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef PL_SUBPROC_FUNCTION_H
#define PL_SUBPROC_FUNCTION_H
#include "funcapi.h"
#include "parser/parse_func.h"

/* the max nested level in inline function */
#define FUNC_MAX_NEST_LEVEL 200

enum
{
	ARGMODE_IN,					/* IN parameter */
	ARGMODE_OUT,				/* OUT parameter */
	ARGMODE_INOUT				/* INOUT parameter */
};

enum
{
	FUNC_PROPER_DETERMINISTIC,	/* DETERMINISTIC property */
	FUNC_PROPER_RESULT_CACHE,	/* RESULT_CACHE property */
	FUNC_PROPER_PARALLEL_ENABLE,	/* PARALLEL_ENABLE property */
	FUNC_PROPER_PIPELINED,		/* PIPELINED property */
	PROC_PROPER_ACCESSIBLE_BY,	/* ACCESSIBLE BY clause property */
	PROC_PROPER_DEFAULT_COLLATION,	/* DEFAULT COLLATION property */
	PROC_PROPER_INVOKER_RIGHT	/* INVOKER RIGHTS property */
};

/* Access property item kind */
typedef enum AccessProperItemType
{
	access_proper_function,
	access_proper_procedure,
	access_proper_package,
	access_proper_trigger,
	access_proper_type,
	access_proper_unknow
}			AccessProperItemType;

typedef struct AccessProperItem
{
	AccessProperItemType proper_type;
	char	   *schema_name;
	char	   *unit_name;
}			AccessProperItem;

/* Inline function argument item */
typedef struct PLiSQL_function_argitem
{
	char	   *argname;
	PLiSQL_type *type;
	int			argmode;
	bool		nocopy;
	PLiSQL_expr *defexpr;
	Node	   *default_sql_expr;
}			PLiSQL_function_argitem;

/*
 * Subproc function structure
 *
 * Example of a function that declares nested subprocs:
 * ------------------------------------------------------------
 * declare
 *    var1 integer;
 *	  xxxxxx;
 *    var2 integer;
 *    function test1(id integer) return integer;
 *    function test(id integer,xxx,xxx) return xxx is
 *       xxxx;
 *       var3 integer;
 *	     type udt_type is ref cursor;
 *       procedure test_proc() is
 *       is
 *        begin
 *             xxx;
 *         end;
 *    begin
 *		xxxxx;
 *	  end;
 *   function test1(id integer) return integer is
 *    begin
 *         return 23;
 *    end;
 * begin
 *    xxxx;
 * end;
 * ---------------------------------------------------------------
 * nargdefaults:
 *   	Number of function arguments that have default values.
 *
 * lastoutvardno:
 *		Initially we consider var2's dno as the lastoutvardno. However, if
 *a global variable is a composite type and its first field is initialized
 *		inside the subproc, we also need to account for that field
 *variable because it belongs to the parent variable. Therefore we record the
 *		final lastoutvardno including inline-function datums. In the
 *above example, lastoutvardno is var3's dno.
 *
 * lastassignvardno:
 *		Tracks initialization/assignment of OUT global variables. We
 *record var2's dno so we do not repeatedly assign the record field variable for
 *its first column in the inline function. Initialization/assignment is
 *performed only on the parent variable.
 *
 * lastoutsubprocfno:
 *		The last global subproc function fno that the current function can
 *use. In the example above, lastoutsubprocfno is the fno of test1.
 *
 */

typedef struct PLiSQL_subproc_function
{
	int		fno;				/* function dno */
	char	*func_name;				/* function name */
	List *arg;					/* function'args, list of PLiSQL_function_argitem */
	List *properties;				/* function propers, list of PLSQL_subproc_proper */
	PLiSQL_type *rettype;
	bool		is_proc;			/* wether it is procedure or function */
	bool		has_poly_argument;		/* wether it has poly argument */
	char		*src;				/* block src for polymorphic argtype function or procedure */
	PLiSQL_function *function;			/* function that save action and dautms */
	bool		has_declare;			/* has declare or not */
	int			nargdefaults;
	int			noutargs;		/* the number of out arguments */
	int			lastoutvardno;
	int			lastassignvardno;
	int			lastoutsubprocfno;	/* the last out subproc fno, which function can use */
	PLiSQL_nsitem *global_cur;			/* the namespace in which function searches for global var */
	HTAB		*poly_tab;			/* hash table for polymorphic argtype function or procedure */
	int			location;		/* nice errors position */
} PLiSQL_subproc_function;


typedef struct PLiSQL_subprocfunc_proper
{
	int			proper_type;
	void	   *value;
}			PLiSQL_subprocfunc_proper;

typedef struct proper_result_cache
{
	List	   *data_source;	/* list of names */
}			proper_result_cache;

extern PLiSQL_subproc_function * *plisql_subprocFuncs;
extern int	plisql_nsubprocFuncs;
extern int	subprocFuncs_alloc;
extern int	cur_compile_func_level;
extern PLiSQL_function * plisql_saved_compile[];
extern int	plisql_saved_datums_last[];
extern char *plisql_saved_error_funcname[];
extern int	plisql_saved_nsubprocfuncs[];
extern int	plisql_saved_subprocfunc_alloc[];
extern PLiSQL_subproc_function * *plisql_saved_subprocfuncs[];

/* Useful functions */
extern void plisql_start_subproc_func(void);
extern void plisql_finish_subproc_func(PLiSQL_function * function);
extern void plisql_push_subproc_func(void);
extern void plisql_pop_subproc_func(void);

extern void plisql_build_variable_from_funcargs(PLiSQL_subproc_function *subprocfunc,
							bool forValidator, FunctionCallInfo fcinfo,
							int found_varno);
extern void plisql_set_subprocfunc_action(PLiSQL_subproc_function *inlinefunc,
							PLiSQL_stmt_block *action);
extern void plisql_check_subprocfunc_properties(PLiSQL_subproc_function *subprocfunc,
							List *properties, bool isdeclare);
extern PLiSQL_subproc_function *plisql_build_subproc_function(char *funcname, List *args,
							PLiSQL_type *rettype, int location); 
extern void plisql_add_subproc_function(PLiSQL_subproc_function *inlinefunc);
extern void plisql_register_internal_func(void);
extern void plisql_unregister_internal_func(void);
extern TupleDesc plisql_get_func_result_tupdesc(FuncExpr *fexpr);
extern int get_subprocfunc_arg_info(FuncExpr *funcexpr, Oid **p_argtypes,
							char ***p_argnames, char **p_argmodes);
extern char *plisql_get_func_name(FuncExpr *fexpr);
extern TypeFuncClass
			plisql_get_subprocfunc_result_type(FuncExpr *fexpr, ReturnSetInfo *rsinfo,
											   Oid *resultTypeId,
											   TupleDesc *resultTupleDesc);
extern List *plisql_get_subprocfunc_outargs(FuncExpr *fexpr);
extern char *plisql_get_subprocfunc_result_name(FuncExpr *fexpr);

extern char plisql_function_from(FunctionCallInfo fcinfo);

extern PLiSQL_function * plisql_get_subproc_func(FunctionCallInfo fcinfo,
												 bool forValidator);

extern void plisql_init_subprocfunc_globalvar(PLiSQL_execstate *estate,
							FunctionCallInfo fcinfo);

extern void plisql_assign_out_subprocfunc_globalvar(PLiSQL_execstate * estate,
													FunctionCallInfo fcinfo);
extern int	plisql_subprocfunc_ref(ParseState *pstate, List *funcname,
								   List **fargs,	/* return value */
								   List *fargnames, int nargs, Oid *argtypes,
								   bool expand_variadic, bool expand_defaults,
								   bool include_out_arguments,
								   Oid *funcid, /* return value */
								   Oid *rettype,	/* return value */
								   bool *retset,	/* return value */
								   int *nvargs, /* return value */
								   Oid *vatype, /* return value */
								   Oid **true_typeids,	/* return value */
								   List **argdefaults,	/* return value */
								   void **pfunc);	/* return value */

extern void plisql_assign_out_subprocfunc_globalvar(PLiSQL_execstate *estate,
							FunctionCallInfo fcinfo);
extern int plisql_subprocfunc_ref(ParseState *pstate, List *funcname,
				List **fargs,	/* return value */
				List *fargnames,
				int nargs,
				Oid *argtypes,
				bool expand_variadic,
				bool expand_defaults,
				bool include_out_arguments,
				Oid *funcid,	/* return value */
				Oid *rettype,	/* return value */
				bool *retset,	/* return value */
				int *nvargs,	/* return value */
				Oid *vatype,	/* return value */
				Oid **true_typeids, /* return value */
				List **argdefaults,	/* return value */
				void **pfunc);	/* return value */

extern FuncDetailCode plisql_get_subprocfunc_detail(ParseState *pstate,
							PLiSQL_function *pfunc,
							PLiSQL_nsitem *nse,
							char *funcname, List **fargs,
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
							List **argdefaults);
extern int get_subprocfunc_arg_info_from_arguments(List *args, Oid **p_argtypes,
								char ***p_argnames, char **p_argmodes);
extern PLiSQL_function *plisql_subprocfunc_HashTableLookup(HTAB *hashp,
							PLiSQL_func_hashkey *func_key);
extern PLiSQL_function* plisql_dynamic_compile_subproc(FunctionCallInfo fcinfo,
								PLiSQL_subproc_function *subprocfunc,
								bool forValidator);

#endif   /* PL_SUBPROC_FUNCTION_H */

