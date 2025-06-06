/*-------------------------------------------------------------------------
 *
 * File:pl_subproc_function.h
 *
 * Abstract:
 *		Definitions for the PLISQL
 *			  procedural language nested sub function/procedure
 *
 *
 * Authored by dwdai@highgo.com,20220627.
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
	ARGMODE_IN,		/* in parameter */
	ARGMODE_OUT,	/* out parameter */
	ARGMODE_INOUT	/* inout parameter */
};

enum
{
	FUNC_PROPER_DETERMINISTIC,	/* DETERMINISTIC proper */
	FUNC_PROPER_RESULT_CACHE,		/* RESULT_CACHE proper */
	FUNC_PROPER_PARALLEL_ENABLE,	/* PARALLEL_ENABLE proper */
	FUNC_PROPER_PIPELINED,			/* pipelined proper */
	PROC_PROPER_ACCESSIBLE_BY,		/* accessible by clause proper */
	PROC_PROPER_DEFAULT_COLLATION,	/* default collation proper */
	PROC_PROPER_INVOKER_RIGHT		/* invoke right proper */
};


typedef enum AccessProperItemType
{
	access_proper_function,
	access_proper_procedure,
	access_proper_package,
	access_proper_trigger,
	access_proper_type,
	access_proper_unknow
} AccessProperItemType;

typedef struct AccessProperItem
{
	AccessProperItemType	proper_type;
	char *schema_name;
	char *unit_name;
} AccessProperItem;


/* inline function argitem struct */
typedef struct PLiSQL_function_argitem
{
	char		*argname;
	PLiSQL_type	*type;
	int			argmode;
	bool		nocopy;
	PLiSQL_expr	*defexpr;
	Node		*default_sql_expr;
} PLiSQL_function_argitem;

/*
 * subproc function struct
 * subproc function saves test function like
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
 *   	the number of the function arg which has default value.
 *
 * lastoutvardno:
 *		first, we consider the var2'dno as the lastoutvardno, but if
 *		global var is compisite type var and init its firistcol in
 *		subprocfunc, we should include this rec_filedvar because it
 *		also a member of the parent variable.
 *		so finial,we record lastoutvardno which include the inlinefunc
 *		datum, so in the above example, the lastoutvardno is var3'dno
 *
 * lastassignvardno
 *		the init and assign out global var, we consider the var2'dno
 *		we record this ,so that we don't repeate assign rec_filedvar
 *		for its firsitcol in inlinefunc, we only init and assign in
 *		its parent'var
 *
 * lastoutsubprocfno:
 *		the last global subproc function'fno the test function maybe use
 *		in the above example, the lastoutinlinefno is the test1'fno
 *
 */

typedef struct PLiSQL_subproc_function
{
	int		fno;					/* function dno */
	char	*func_name;				/* function name */
	List *arg;						/* function'args, list of PLiSQL_function_argitem */
	List *properties;				/* function propers, list of PLSQL_subproc_proper */
	PLiSQL_type *rettype;
	bool		is_proc;			/* wether it is procedure or function */
	bool		has_poly_argument;	/* wether it has poly argument */
	char		*src;				/* block src for polymorphic argtype function or procedure */
	PLiSQL_function *function;		/* function save action and dautms */
	bool		has_declare;		/* has declare */
	int			nargdefaults;
	int			noutargs;			/* the number of out arguments */
	int			lastoutvardno;
	int			lastassignvardno;
	int			lastoutsubprocfno;	/* the last out subproc fno, which function can use */
	PLiSQL_nsitem *global_cur;		/* the namespace which the function to search global var */
	HTAB		*poly_tab;			/* hash table for polymorphic argtype function or procedure */
	int			location;			/* nice errors position */
} PLiSQL_subproc_function;


typedef struct PLiSQL_subprocfunc_proper
{
	int proper_type;
	void *value;
} PLiSQL_subprocfunc_proper;

typedef struct proper_result_cache
{
	List *data_source;			/* list of names */
} proper_result_cache;


extern PLiSQL_subproc_function **plisql_subprocFuncs;
extern int plisql_nsubprocFuncs;
extern int subprocFuncs_alloc;
extern int cur_compile_func_level;
extern PLiSQL_function *plisql_saved_compile[];
extern int plisql_saved_datums_last[];
extern char *plisql_saved_error_funcname[];
extern int plisql_saved_nsubprocfuncs[];
extern int plisql_saved_subprocfunc_alloc[];
extern PLiSQL_subproc_function **plisql_saved_subprocfuncs[];


/* some userfull funcs */
extern void plisql_start_subproc_func(void);
extern void plisql_finish_subproc_func(PLiSQL_function *function);
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
extern TypeFuncClass plisql_get_subprocfunc_result_type(FuncExpr *fexpr,
						 ReturnSetInfo *rsinfo,
						 Oid *resultTypeId,
						 TupleDesc *resultTupleDesc);
extern List *plisql_get_subprocfunc_outargs(FuncExpr *fexpr);
extern char *plisql_get_subprocfunc_result_name(FuncExpr *fexpr);

extern char plisql_function_from(FunctionCallInfo fcinfo);

extern PLiSQL_function *plisql_get_subproc_func(FunctionCallInfo fcinfo, bool forValidator);

extern void plisql_init_subprocfunc_globalvar(PLiSQL_execstate *estate,
														FunctionCallInfo fcinfo);


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

