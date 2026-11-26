/*-------------------------------------------------------------------------
 *
 * parse_func.h
 *
 *
 *
 * Portions Copyright (c) 1996-2026, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/parser/parse_func.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PARSE_FUNC_H
#define PARSE_FUNC_H

#include "catalog/namespace.h"
#include "parser/parse_node.h"


/* Result codes for func_get_detail */
typedef enum
{
	FUNCDETAIL_NOTFOUND,		/* no matching function */
	FUNCDETAIL_MULTIPLE,		/* too many matching functions */
	FUNCDETAIL_NORMAL,			/* found a matching regular function */
	FUNCDETAIL_PROCEDURE,		/* found a matching procedure */
	FUNCDETAIL_AGGREGATE,		/* found a matching aggregate function */
	FUNCDETAIL_WINDOWFUNC,		/* found a matching window function */
	FUNCDETAIL_COERCION,		/* it's a type coercion request */
} FuncDetailCode;

/*
 * oracle_lob_source_hook_type --- a parse-time hook that gets to see the
 * argument expressions of a function call before the call is resolved and
 * before the planner folds any constant away.
 *
 * The hook is called with the raw argument list of the call (the expressions
 * exactly as the caller wrote them, before any coercion is applied), the
 * parallel argument-name list (NIL when every argument was written
 * positionally), and the argument types the parser derived for them.  It is
 * meant for the Oracle compatibility layer to refuse argument types that
 * Oracle refuses while the call is still being resolved, so that the refusal
 * does not depend on which overload happens to win the resolution.
 *
 * The hook raises an error for a call it refuses and returns normally for
 * every other call; there is no return value to interpret.
 */
typedef void (*oracle_lob_source_hook_type) (List *funcname, List *fargs,
											  List *fargnames, Oid *argtypes,
											  int nargs);
extern PGDLLIMPORT oracle_lob_source_hook_type oracle_lob_source_hook;


extern Node *ParseFuncOrColumn(ParseState *pstate, List *funcname, List *fargs,
							   Node *last_srf, FuncCall *fn, bool proc_call,
							   int location);

extern FuncDetailCode func_get_detail(List *funcname,
									  List *fargs, List *fargnames,
									  int nargs, Oid *argtypes,
									  bool expand_variadic, bool expand_defaults,
									  bool include_out_arguments,
									  int *fgc_flags,
									  Oid *funcid, Oid *rettype,
									  bool *retset, int *nvargs, Oid *vatype,
									  Oid **true_typeids, List **argdefaults);

extern int	func_match_argtypes(int nargs,
								Oid *input_typeids,
								FuncCandidateList raw_candidates,
								FuncCandidateList *candidates);

extern FuncCandidateList func_select_candidate(int nargs,
											   Oid *input_typeids,
											   FuncCandidateList candidates);

extern void make_fn_arguments(ParseState *pstate,
							  List *fargs,
							  Oid *actual_arg_types,
							  Oid *declared_arg_types);

extern const char *funcname_signature_string(const char *funcname, int nargs,
											 List *argnames, const Oid *argtypes);
extern const char *func_signature_string(List *funcname, int nargs,
										 List *argnames, const Oid *argtypes);

extern Oid	LookupFuncName(List *funcname, int nargs, const Oid *argtypes,
						   bool missing_ok);
extern Oid	LookupFuncWithArgs(ObjectType objtype, ObjectWithArgs *func,
							   bool missing_ok);

extern void check_srf_call_placement(ParseState *pstate, Node *last_srf,
									 int location);

#endif							/* PARSE_FUNC_H */
