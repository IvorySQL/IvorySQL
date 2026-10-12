/*-------------------------------------------------------------------------
 *
 * ora_collect.c
 *	  IvorySQL: Oracle nested-table collection constructor calls.
 *
 * In Oracle mode a call "num_tab(a, b, ...)" where the name resolves to a
 * schema-level nested-table type (pg_type.typoranestedtable) is a
 * collection constructor, not a function call.  The elements are converted
 * one by one to the declared element type/typmod, assembled into an
 * ArrayExpr over the collection's base array type, and wrapped in a
 * CoerceToDomain so the result is a value of the collection domain.  The
 * empty call "num_tab()" builds an empty (non-NULL) collection; the two
 * stay distinct from each other and from NULL.
 *
 * The constructor is only reached from the function-not-found path of
 * ParseFuncOrColumn, so real functions and PostgreSQL array functions are
 * never shadowed.
 *
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 2025, IvorySQL Global Development Group
 *
 *	src/backend/parser/ora_collect.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "catalog/pg_type.h"
#include "commands/typecmds.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "nodes/primnodes.h"
#include "parser/parse_coerce.h"
#include "parser/parse_collate.h"
#include "parser/parse_expr.h"
#include "parser/parse_type.h"
#include "parser/ora_collect.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "utils/ora_compatible.h"
#include "utils/typcache.h"

/*
 * transform_oracle_collection_constructor
 *
 * If funcname resolves to an Oracle nested-table type, transform the call
 * into ArrayExpr + CoerceToDomain and return it; otherwise return NULL and
 * let the caller report its own error (typically "function does not
 * exist").  The fargs are already-transformed parse expressions, exactly
 * as ParseFuncOrColumn receives them.
 */
Node *
transform_oracle_collection_constructor(ParseState *pstate,
										List *funcname, List *fargs,
										int location)
{
	TypeName   *tname;
	Oid			collOid;
	Oid			arrayOid;
	Oid			elemOid;
	int32		elemTypmod;
	Oid			collation = InvalidOid;
	ArrayExpr  *newarray;
	CoerceToDomain *domainexpr;
	List	   *newargs = NIL;
	ListCell   *lc;
	TypeCacheEntry *typentry;

	/* The constructor syntax only exists in the Oracle parser. */
	if (ORA_PARSER != compatible_db)
		return NULL;

	/* Resolve the call name as a type; ignore anything that is not a
	 * flagged Oracle collection (invalid, a plain function name, an
	 * ordinary domain or array, ...). */
	tname = makeTypeNameFromNameList(funcname);
	collOid = LookupTypeNameOid(pstate, tname, true);	/* missing_ok */
	if (!OidIsValid(collOid))
		return NULL;
	if (!get_oracle_collection_element(collOid, &elemOid, &elemTypmod,
									   &collation))
		return NULL;

	arrayOid = getBaseType(collOid);
	if (!OidIsValid(arrayOid))
		return NULL;

	typentry = lookup_type_cache(elemOid, 0);

	/* Convert each argument to the declared element type/typmod. */
	foreach(lc, fargs)
	{
		Node	   *arg = (Node *) lfirst(lc);
		Oid			argtype = exprType(arg);

		if (argtype == InvalidOid)
			return NULL;	/* void args cannot construct a collection */

		arg = coerce_to_target_type(pstate, arg, argtype, elemOid,
									elemTypmod, COERCION_ASSIGNMENT,
									COERCE_IMPLICIT_CAST, -1);
		if (arg == NULL)
			ereport(ERROR,
					(errcode(ERRCODE_DATATYPE_MISMATCH),
					 errmsg("element type of collection \"%s\" does not match argument type %s",
							NameListToString(funcname),
							format_type_be(argtype)),
					 parser_errposition(pstate, location)));

		newargs = lappend(newargs, arg);
	}

	/* Assemble the array over the collection's base array type. */
	newarray = makeNode(ArrayExpr);
	newarray->array_typeid = arrayOid;
	newarray->array_collid = get_typcollation(arrayOid);
	newarray->element_typeid = elemOid;
	newarray->elements = newargs;
	newarray->multidims = false;
	newarray->location = location;

	/* And coerce it to the collection domain. */
	domainexpr = makeNode(CoerceToDomain);
	domainexpr->arg = (Expr *) newarray;
	domainexpr->resulttype = collOid;
	domainexpr->resulttypmod = -1;
	domainexpr->resultcollid =
		(typentry->typtype == TYPTYPE_DOMAIN) ? typentry->typcollation :
		InvalidOid;
	domainexpr->coercionformat = COERCE_EXPLICIT_CALL;
	domainexpr->location = location;

	assign_expr_collations(pstate, (Node *) domainexpr);
	return (Node *) domainexpr;
}
