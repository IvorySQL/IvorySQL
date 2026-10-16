/*-------------------------------------------------------------------------
 *
 * parse_with_plsql.c
 *    Oracle-compatible WITH FUNCTION / WITH PROCEDURE support — parse phase.
 *
 * This file implements the two parse-time phases of WITH-clause inline
 * subprograms:
 *
 *   1. Parse-analysis (transformWithFuncDefs):
 *        Resolves argument and return types, registers each function
 *        signature in ParseState.p_with_func_list, and installs the
 *        withFuncLookupHook so that subsequent expression analysis can
 *        resolve calls to the inline functions before falling through to
 *        the catalog.
 *
 *   2. Function call resolution (withFuncLookupHook):
 *        Called from ParseFuncOrColumn() as the p_subprocfunc_hook.
 *        Returns FUNCDETAIL_NORMAL / FUNCDETAIL_PROCEDURE when a WITH-
 *        clause function matches, with funcid set to the function index
 *        (not a catalog OID) and function_from = FUNC_FROM_WITH_CLAUSE.
 *
 * The execution-time compilation phase (Phase 3) lives in
 * src/pl/plisql/src/pl_handler.c so that it can call plisql_compile_inline()
 * without creating a dependency from the main backend on plisql.so.
 *
 * Copyright 2025 IvorySQL Global Development Team
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * src/backend/parser/parse_with_plsql.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "catalog/namespace.h"
#include "oracle_parser/ora_with_function.h"
#include "parser/parse_coerce.h"
#include "parser/parse_expr.h"
#include "parser/parse_func.h"
#include "parser/parse_type.h"
#include "utils/guc.h"
#include "utils/ora_compatible.h"

/*
 * EState fallback for recursive WITH function calls.  Set by plisql.so when
 * executing a WITH function so that ExecInitFunc can use it when the
 * expression is evaluated via PL/iSQL's simple-expression path (which creates
 * ExprStates without a parent PlanState).
 */
struct EState *plisql_active_with_func_estate = NULL;

/* -----------------------------------------------------------------------
 * Internal helpers
 * ----------------------------------------------------------------------- */

/*
 * Oracle SQL single-row built-in function names that WITH FUNCTION must not
 * shadow.  These correspond to Oracle's documented SQL Functions (SQL Language
 * Reference, "Functions" chapter) that are part of the SQL language itself.
 *
 * When one of these names appears with a matching pg_catalog entry, the
 * catalog function wins — exactly as Oracle resolves its own built-ins before
 * any user-supplied query-level definition.
 *
 * PostgreSQL-specific catalog entries (e.g. factorial, array_append) are
 * intentionally absent so that WITH FUNCTION can still override them.
 *
 * Temporary: superseded once IvorySQL ships its STANDARD package.
 */
static const char *const oracle_builtin_func_names[] = {
	/* Numeric single-row functions */
	"abs", "acos", "asin", "atan", "atan2",
	"bitand", "ceil", "cos", "cosh",
	"exp", "floor", "greatest", "least",
	"ln", "log", "mod", "power",
	"round", "sign", "sin", "sinh", "sqrt",
	"tan", "tanh", "trunc", "width_bucket",
	/* Character single-row functions */
	"ascii", "chr", "concat", "initcap",
	"instr", "length", "lower", "lpad", "ltrim",
	"replace", "rpad", "rtrim", "soundex",
	"substr", "translate", "trim", "upper",
	/* Regular-expression functions */
	"regexp_count", "regexp_instr", "regexp_replace", "regexp_substr",
	/* NULL-handling */
	"coalesce", "nullif",
	/* Aggregate functions */
	"avg", "count", "max", "min", "stddev", "sum", "variance",
	NULL						/* sentinel */
};

static bool
is_oracle_builtin_name(const char *fname)
{
	for (int i = 0; oracle_builtin_func_names[i] != NULL; i++)
	{
		if (strcmp(oracle_builtin_func_names[i], fname) == 0)
			return true;
	}
	return false;
}

/*
 * resolveWithFuncArgTypes — resolve FunctionParameter list to an Oid list.
 *
 * Every parameter (IN, OUT, IN OUT) contributes to the argument type vector.
 * WITH FUNCTION only accepts IN parameters (enforced by
 * rejectNonInParamsInWithFunc); WITH PROCEDURE may also have OUT/IN OUT.
 */
static List *
resolveWithFuncArgTypes(ParseState *pstate, List *args)
{
	List	   *result = NIL;
	ListCell   *lc;

	foreach(lc, args)
	{
		FunctionParameter *fp = (FunctionParameter *) lfirst(lc);

		result = lappend_oid(result,
							 typenameTypeId(pstate, fp->argType));
	}

	return result;
}

/*
 * rejectNonInParamsInWithFunc — enforce Oracle's SQL-callable rule that
 * functions invoked from a SQL statement may not declare OUT or IN OUT
 * parameters.  WITH PROCEDURE definitions are exempt: Oracle allows OUT/IN OUT
 * parameters on WITH procedures because procedures are not called directly from
 * SQL expressions — they are invoked from other PL/SQL subprograms within the
 * same WITH block.
 *
 * Oracle raises ORA-06572 ("PL/SQL function string has OUT parameter in
 * argument list") for schema-level functions called from SQL, and the same
 * rule applies to WITH FUNCTION.  WITH PROCEDURE does not trigger ORA-06572.
 */
static void
rejectNonInParamsInWithFunc(ParseState *pstate, InlineFunctionDef *ifd)
{
	ListCell   *lc;

	/* Procedures may freely declare OUT / IN OUT parameters. */
	if (ifd->is_proc)
		return;

	foreach(lc, ifd->args)
	{
		FunctionParameter *fp = (FunctionParameter *) lfirst(lc);

		if (fp->mode == FUNC_PARAM_IN ||
			fp->mode == FUNC_PARAM_DEFAULT)
			continue;

		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("WITH FUNCTION \"%s\" cannot declare OUT or IN OUT parameters",
						ifd->funcname),
				 errdetail("WITH FUNCTION subprograms are invoked directly from SQL expressions, which only accept IN parameters."),
				 errhint("Remove the OUT/IN OUT/NOCOPY mode from parameter \"%s\", or move the subprogram into a schema-level PL/SQL block.",
						 fp->name ? fp->name : "?"),
				 parser_errposition(pstate, ifd->location)));
	}
}

/*
 * checkDuplicateWithFunc — error if funcname already registered with the
 * same argument types (same overload).
 */
static void
checkDuplicateWithFunc(List *func_list, WithFuncEntry * newentry)
{
	ListCell   *lc;

	foreach(lc, func_list)
	{
		WithFuncEntry *existing = (WithFuncEntry *) lfirst(lc);

		if (strcmp(existing->funcname, newentry->funcname) != 0)
			continue;

		if (list_length(existing->argtypes) != list_length(newentry->argtypes))
			continue;

		if (equal(existing->argtypes, newentry->argtypes))
			ereport(ERROR,
					(errcode(ERRCODE_DUPLICATE_FUNCTION),
					 errmsg("WITH clause function \"%s\" is defined more than once with the same argument types",
							newentry->funcname),
					 parser_errposition(NULL, newentry->def->location)));
	}
}

/* -----------------------------------------------------------------------
 * Phase 1: parse-analysis
 * ----------------------------------------------------------------------- */

/*
 * transformWithFuncDefs — process InlineFunctionDef nodes from the WITH
 * clause during query semantic analysis.
 *
 * Called from transformWithClause() when WithClause.plsql_defs is non-NIL.
 * Populates pstate->p_with_func_list and installs withFuncLookupHook.
 */
void
transformWithFuncDefs(ParseState *pstate, List *plsql_defs)
{
	int			funcindex = 0;
	ListCell   *lc;

	Assert(ORA_PARSER == compatible_db);

	foreach(lc, plsql_defs)
	{
		InlineFunctionDef *ifd = (InlineFunctionDef *) lfirst(lc);
		WithFuncEntry *entry;

		Assert(IsA(ifd, InlineFunctionDef));

		/*
		 * Oracle disallows OUT / IN OUT parameters on SQL-callable functions
		 * (ORA-06572).  WITH PROCEDURE is exempt because procedures are not
		 * called directly from SQL expressions.
		 */
		rejectNonInParamsInWithFunc(pstate, ifd);

		entry = palloc(sizeof(WithFuncEntry));
		entry->funcname = ifd->funcname;
		entry->is_proc = ifd->is_proc;
		entry->funcindex = funcindex++;
		entry->def = ifd;

		entry->argtypes = resolveWithFuncArgTypes(pstate, ifd->args);

		/*
		 * Pre-analyze each parameter's DEFAULT expression in the current
		 * ParseState context.  Storing analyzed expressions here avoids
		 * calling transformExpr inside the hook (which runs in a narrower
		 * context and can trigger a crash).
		 */
		{
			int			ndefaults = 0;
			List	   *analyzed = NIL;
			ListCell   *alc;

			foreach(alc, ifd->args)
			{
				FunctionParameter *fp = (FunctionParameter *) lfirst(alc);

				if (fp->defexpr != NULL)
				{
					Node	   *expr = transformExpr(pstate,
													 copyObject(fp->defexpr),
													 EXPR_KIND_FUNCTION_DEFAULT);

					analyzed = lappend(analyzed, expr);
					ndefaults++;
				}
				else
					analyzed = lappend(analyzed, NULL);
			}
			entry->ndefaults = ndefaults;
			entry->analyzeddefaults = analyzed;
		}

		if (ifd->rettype != NULL)
			entry->rettype = typenameTypeId(pstate, ifd->rettype);
		else
			entry->rettype = InvalidOid;

		checkDuplicateWithFunc(pstate->p_with_func_list, entry);

		pstate->p_with_func_list = lappend(pstate->p_with_func_list, entry);
	}

	if (pstate->p_subprocfunc_hook == NULL)
		pstate->p_subprocfunc_hook = withFuncLookupHook;
}

/* -----------------------------------------------------------------------
 * Phase 2: call-site resolution hook
 * ----------------------------------------------------------------------- */

/*
 * withFuncLookupHook — ParseSubprocFuncHook implementation.
 *
 * Called from ParseFuncOrColumn() before any catalog lookup.  Returns
 * FUNCDETAIL_NORMAL (or FUNCDETAIL_PROCEDURE) when a matching WITH-clause
 * function is found; FUNCDETAIL_NOTFOUND otherwise.
 */
int
withFuncLookupHook(ParseState *pstate,
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
				   void **pfunc)
{
	char	   *fname;
	ListCell   *lc;

	/* WITH-clause functions are always simple (unqualified) names */
	if (list_length(funcname) != 1)
		return FUNCDETAIL_NOTFOUND;

	fname = strVal(linitial(funcname));

	/*
	 * Oracle compatibility: Oracle SQL built-in functions take priority over
	 * WITH FUNCTION definitions with the same name.  In Oracle, documented
	 * single-row SQL functions (ABS, ROUND, SUBSTR, etc.) are always resolved
	 * before any query-local definitions; a WITH FUNCTION of the same name is
	 * silently bypassed.
	 *
	 * We gate on a whitelist of Oracle SQL function names so that PostgreSQL-
	 * specific pg_catalog entries (e.g. factorial) are still overridable.
	 *
	 * NOTE: this is a temporary bridge.  Once IvorySQL implements the STANDARD
	 * package, LookupPkgFunc("standard.name") will naturally win in
	 * ParseFuncOrColumn before this hook is reached, making this check
	 * redundant.
	 */
	if (is_oracle_builtin_name(fname))
	{
		List	   *pg_cat_name = list_make2(makeString("pg_catalog"),
											 makeString(fname));
		int			dummy_flags = 0;
		FuncCandidateList cands;

		cands = FuncnameGetCandidates(pg_cat_name, nargs, fargnames,
									  expand_variadic, expand_defaults,
									  false, true, &dummy_flags);
		list_free_deep(pg_cat_name);
		if (cands != NULL)
			return FUNCDETAIL_NOTFOUND;
	}

	foreach(lc, pstate->p_with_func_list)
	{
		WithFuncEntry *entry = (WithFuncEntry *) lfirst(lc);
		int			nentryargs;
		int			i;
		ListCell   *alc;

		if (strcmp(entry->funcname, fname) != 0)
			continue;

		nentryargs = list_length(entry->argtypes);

		/* Accept exact match or short call if every omitted param is a
		 * trailing defaulted parameter.  ndefaults alone is not sufficient:
		 * defaults may be interspersed, and we must reject calls that omit
		 * a parameter without a default. */
		if (nargs > nentryargs)
			continue;
		if (nargs < nentryargs)
		{
			int			omitted = nentryargs - nargs;
			int			trailing_defaults = 0;
			int			j;

			/*
			 * Defaults are recorded positionally in entry->analyzeddefaults
			 * (NULL where the IN/INOUT parameter has no default).  Scan from
			 * the end and count contiguous trailing non-NULL entries.
			 */
			for (j = nentryargs - 1; j >= 0; j--)
			{
				if (list_nth(entry->analyzeddefaults, j) == NULL)
					break;
				trailing_defaults++;
			}
			if (omitted > trailing_defaults)
				continue;
		}

		/* All provided argument types must be implicitly coercible */
		i = 0;
		foreach(alc, entry->argtypes)
		{
			Oid			expected = lfirst_oid(alc);

			if (i >= nargs)
				break;			/* remaining params covered by defaults */
			if (!can_coerce_type(1, &argtypes[i], &expected, COERCION_IMPLICIT))
				goto next_entry;
			i++;
		}

		/* Match found — populate output parameters */
		*funcid = (Oid) entry->funcindex;
		*rettype = entry->rettype;
		*retset = false;
		*nvargs = 0;
		*vatype = InvalidOid;
		*pfunc = NULL;

		/* Build true_typeids covering all nentryargs (provided + defaults) */
		if (nentryargs > 0)
		{
			*true_typeids = (Oid *) palloc(nentryargs * sizeof(Oid));
			i = 0;
			foreach(alc, entry->argtypes)
				(*true_typeids)[i++] = lfirst_oid(alc);
		}
		else
			*true_typeids = NULL;

		/*
		 * If the caller asked us to expand defaults and the call omits
		 * trailing defaulted parameters, append their pre-analyzed default
		 * expressions to *fargs so the FuncExpr carries all arguments.
		 * parse_func.c will sync actual_arg_types from declared_arg_types for
		 * these extra positions before coercion.
		 *
		 * The trailing-defaults check above guarantees every omitted position
		 * has a non-NULL default, so this loop never copies a NULL.
		 */
		if (expand_defaults && nargs < nentryargs)
		{
			int			skip = 0;	/* IN/INOUT params seen so far */
			ListCell   *dlc;

			foreach(dlc, entry->analyzeddefaults)
			{
				Node	   *defexpr = (Node *) lfirst(dlc);

				skip++;
				if (skip <= nargs)
					continue;	/* provided by caller */

				*fargs = lappend(*fargs, copyObject(defexpr));
			}
		}

		*argdefaults = NIL;

		return entry->is_proc ? FUNCDETAIL_PROCEDURE : FUNCDETAIL_NORMAL;

next_entry:;
	}

	return FUNCDETAIL_NOTFOUND;
}
