/*-------------------------------------------------------------------------
 *
 * ora_with_function.h
 *    Support for Oracle-compatible WITH FUNCTION / WITH PROCEDURE
 *    (inline subprograms defined in the SQL WITH clause).
 *
 * This header is included by both the main backend (for the parse-analysis
 * phase) and by plisql.so (for the execution phase).  It intentionally avoids
 * including PL/iSQL-internal headers so that files in the main backend do not
 * depend on plisql internals; forward declarations are used instead.
 *
 * Copyright 2025 IvorySQL Global Development Team
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License.  You may obtain
 * a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
 *
 * src/include/oracle_parser/ora_with_function.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef ORA_WITH_FUNCTION_H
#define ORA_WITH_FUNCTION_H

#include "nodes/parsenodes.h"
#include "nodes/plannodes.h"
#include "parser/parse_node.h"
#include "fmgr.h"

/* Forward declarations — full types are defined in their respective headers */
struct PLiSQL_function;			/* pl/plisql/src/plisql.h */
struct PLiSQL_subproc_function; /* pl/plisql/src/pl_subproc_function.h */
struct EState;					/* nodes/execnodes.h */

/*
 * WithFuncContainer — runtime container for compiled WITH clause functions.
 *
 * Created lazily on first invocation of any WITH-clause function within a
 * query and stored in EState.es_with_func_container.  Its memory context is a
 * child of EState.es_query_cxt so it is freed automatically when the query
 * ends.
 *
 * The funcs array uses a forward-declared pointer type so this header can be
 * included by the main backend without dragging in plisql internals.
 */
typedef struct WithFuncContainer
{
	int							nfuncs;		/* number of inline functions */
	struct PLiSQL_subproc_function **funcs;	/* compiled function array */
	MemoryContext				mcxt;		/* owning memory context */
	List					   *func_entries; /* WithFuncEntry list, for expr context */
} WithFuncContainer;

/*
 * WithFuncEntry — per-function descriptor kept in ParseState.p_with_func_list
 * during semantic analysis.  Carries only the information needed to resolve
 * call-sites; the full InlineFunctionDef (with body source) is preserved in
 * Query.withFuncDefs for later compilation.
 */
typedef struct WithFuncEntry
{
	char	   *funcname;		/* function/procedure name */
	List	   *argtypes;		/* Oid list of resolved argument types */
	Oid			rettype;		/* resolved return type OID */
	bool		is_proc;		/* true = procedure */
	int			funcindex;		/* sequential index (used as FuncExpr.funcid) */
	InlineFunctionDef *def;		/* back-pointer to parse node */
	int			ndefaults;		/* number of IN parameters that have DEFAULT exprs */
	List	   *analyzeddefaults; /* analyzed Expr list: one per IN param (NULL if no default) */
} WithFuncEntry;

/* -------------------------
 * Phase 1: parse-analysis
 * -------------------------
 * Defined in src/backend/parser/parse_with_plsql.c (main backend)
 */
extern void transformWithFuncDefs(ParseState *pstate, List *plsql_defs);

/* -------------------------
 * Phase 2: call-site resolution hook (ParseSubprocFuncHook signature)
 * -------------------------
 * Defined in src/backend/parser/parse_with_plsql.c (main backend)
 */
extern int withFuncLookupHook(ParseState *pstate,
							  List *funcname,
							  List **fargs,
							  List *fargnames,
							  int nargs,
							  Oid *argtypes,
							  bool expand_variadic,
							  bool expand_defaults,
							  bool proc_call,
							  Oid *funcid,
							  Oid *rettype,
							  bool *retset,
							  int *nvargs,
							  Oid *vatype,
							  Oid **true_typeids,
							  List **argdefaults,
							  void **pfunc);

/*
 * plisql_active_with_func_estate — EState of the outermost query that owns the
 * active WithFuncContainer.  Defined in parse_with_plsql.c (main backend) and
 * set/restored by plisql_call_handler() (plisql.so) around each WITH function
 * execution.  Used by ExecInitFunc() as a fallback when state->parent is NULL
 * (i.e., when a WITH function is called recursively from inside a PL/iSQL
 * simple-expression path that has no parent PlanState).
 */
extern struct EState *plisql_active_with_func_estate;

/* -------------------------
 * Phase 3: execution-time compilation
 * -------------------------
 * Defined in src/pl/plisql/src/pl_handler.c (plisql.so)
 */

/* Compile all WITH functions from estate->es_plannedstmt->withFuncDefs */
extern WithFuncContainer *buildWithFuncContainer(struct EState *estate);

/* Look up the compiled PLiSQL_function for a WITH-clause function call */
extern struct PLiSQL_function *plisql_get_with_func(FunctionCallInfo fcinfo);

#endif							/* ORA_WITH_FUNCTION_H */
