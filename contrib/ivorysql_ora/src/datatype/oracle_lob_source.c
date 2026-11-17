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
 * oracle_lob_source.c
 *
 * This file contains the parse-time hook that refuses a LOB source to the
 * Oracle *C string functions that Oracle itself refuses, whatever the rest
 * of the call looks like.
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/datatype/oracle_lob_source.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "catalog/namespace.h"
#include "catalog/pg_type.h"
#include "nodes/nodeFuncs.h"
#include "nodes/primnodes.h"
#include "parser/parse_func.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"

#include "../include/ivorysql_ora.h"

/*
 * The functions whose first argument Oracle refuses when it carries a LOB
 * type.  Each entry keeps the name as the caller may write it and the
 * canonical spelling the two messages below print, so the refusal reads the
 * same no matter which of the two paths raises it.  sys.blob is the binary
 * LOB and is not a character type at all, so it is not listed here.
 */
static const struct
{
	const char *const fname;
	const char *const upper;
} ora_lob_source_functions[] = {
	{"instrc", "INSTRC"},
	{"substrc", "SUBSTRC"},
	{NULL, NULL}
};

/*
 * The LOB types the source argument is refused for: sys.clob and sys.nclob.
 */
static const Oid ora_lob_source_types[] = {
	CLOBOID,
	NCLOBOID,
	InvalidOid
};

/*
 * ora_lob_source_exprtype --- the type an argument expression carries at
 * parse time, with the domain identity kept.
 *
 * exprType() answers the domain OID for every shape the source can take at
 * the point func_get_detail() sees the call:
 *
 *   - CAST('abc' AS CLOB) is a CoerceToDomain whose resulttype is the CLOB
 *     OID;
 *   - TO_CLOB('abc') is a FuncExpr whose return type is the CLOB OID;
 *   - a column of type CLOB is a Var whose vartype is the CLOB OID.
 *
 * The point of doing this while the call is still being resolved is that
 * resolution imposes the winning overload's parameter type on the argument,
 * and the optimizer folds a constant -- its domain coercion included --
 * into a bare constant of that parameter type.  A constant LOB source that
 * resolved onto a text-typed row would reach the C function as plain text,
 * invisible to the run-time check in ora_reject_lob_args().  Seeing the raw
 * argument expressions is the only place the domain identity of such a
 * constant is still visible, and it is visible here whatever the rest of
 * the call is spelled as.
 */
static Oid
ora_lob_source_exprtype(Node *arg)
{
	/*
	 * A named argument wraps the real expression; look through it.
	 */
	if (arg != NULL && IsA(arg, NamedArgExpr))
		arg = (Node *) ((NamedArgExpr *) arg)->arg;

	if (arg == NULL)
		return InvalidOid;

	return exprType(arg);
}

/*
 * pg_oracle_lob_source_hook --- refuse a LOB source to the *C string
 * functions while the call is still being resolved.
 *
 * This is the hook core's func_get_detail() calls before it looks at the
 * overload candidates.  Because the refusal happens here, it does not
 * depend on which overload wins: there is no rejection row per (source
 * type x pattern type x position type) combination to maintain, and none
 * to add when a new position spelling shows up.
 *
 * Returns true when it has raised the error itself; returning false lets
 * the resolution carry on as usual.
 */
bool
pg_oracle_lob_source_hook(List *funcname, List *fargs, Oid *argtypes,
						  int nargs)
{
	const char *lower = NULL;
	const char *upper = NULL;
	char	   *fname = NULL;
	char	   *schema = NULL;
	Node	   *arg0;
	Oid			argtype;
	int			i;

	/*
	 * Only the first argument is the source; the pattern may be a LOB in
	 * Oracle, so it is not refused.
	 */
	if (nargs < 1 || fargs == NIL)
		return false;

	DeconstructQualifiedName(funcname, &schema, &fname);
	if (fname == NULL)
		return false;

	for (i = 0; ora_lob_source_functions[i].fname != NULL; i++)
	{
		if (pg_strcasecmp(fname, ora_lob_source_functions[i].fname) == 0)
		{
			lower = ora_lob_source_functions[i].fname;
			upper = ora_lob_source_functions[i].upper;
			break;
		}
	}
	if (upper == NULL)
		return false;

	arg0 = (Node *) linitial(fargs);
	argtype = ora_lob_source_exprtype(arg0);

	for (i = 0; ora_lob_source_types[i] != InvalidOid; i++)
	{
		if (argtype == ora_lob_source_types[i])
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("inconsistent datatypes: %s() does not accept %s",
							lower, format_type_be(argtype)),
					 errdetail("Oracle's %s accepts only character types, not CLOB or NCLOB.",
							   upper)));
	}

	return false;
}
