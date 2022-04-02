/*-------------------------------------------------------------------------
 *
 * parse_type.c
 *		handle type operations for parser
 *
 * Portions Copyright (c) 1996-2021, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/backend/parser/parse_type.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/htup_details.h"
#include "catalog/namespace.h"
#include "catalog/pg_type.h"
#include "lib/stringinfo.h"
#include "nodes/makefuncs.h"
#include "parser/parse_type.h"
#include "parser/parser.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"
#include "commands/packagecmds.h"
#include "catalog/pg_package.h"
#include "access/table.h"
#include "catalog/pg_synonym.h"
#include "commands/dbcommands.h"
#include "miscadmin.h"

/* Hook for typmod to get typename in typenameTypeMod() */
TypenameTypeModIn_hook_type TypenameTypeModIn_hook = NULL;


static int32 typenameTypeMod(ParseState *pstate, const TypeName *typeName,
							 Type typ);


/*
 * LookupTypeName
 *		Wrapper for typical case.
 */
Type
LookupTypeName(ParseState *pstate, const TypeName *typeName,
			   int32 *typmod_p, bool missing_ok)
{
	Type tup;
	
	tup =  LookupTypeNameExtended(pstate,
								  typeName, typmod_p, true, missing_ok);

	/* add begin by qinshiyu 2021.06.16 */
	if (tup == NULL)
		tup = LookupTypeNameFromSynonym(pstate, typeName, typmod_p, missing_ok);
	/* add end by qinshiyu 2021.06.16 */

	return tup;
}

/*
 * LookupTypeNameExtended
 *		Given a TypeName object, lookup the pg_type syscache entry of the type.
 *		Returns NULL if no such type can be found.  If the type is found,
 *		the typmod value represented in the TypeName struct is computed and
 *		stored into *typmod_p.
 *
 * NB: on success, the caller must ReleaseSysCache the type tuple when done
 * with it.
 *
 * NB: direct callers of this function MUST check typisdefined before assuming
 * that the type is fully valid.  Most code should go through typenameType
 * or typenameTypeId instead.
 *
 * typmod_p can be passed as NULL if the caller does not care to know the
 * typmod value, but the typmod decoration (if any) will be validated anyway,
 * except in the case where the type is not found.  Note that if the type is
 * found but is a shell, and there is typmod decoration, an error will be
 * thrown --- this is intentional.
 *
 * If temp_ok is false, ignore types in the temporary namespace.  Pass false
 * when the caller will decide, using goodness of fit criteria, whether the
 * typeName is actually a type or something else.  If typeName always denotes
 * a type (or denotes nothing), pass true.
 *
 * pstate is only used for error location info, and may be NULL.
 */
Type
LookupTypeNameExtended(ParseState *pstate,
					   const TypeName *typeName, int32 *typmod_p,
					   bool temp_ok, bool missing_ok)
{
	Oid			typoid;
	HeapTuple	tup;
	int32		typmod;

	if (typeName->names == NIL)
	{
		/* We have the OID already if it's an internally generated TypeName */
		typoid = typeName->typeOid;
	}
	else if (typeName->pct_type)
	{
		/* Handle %TYPE reference to type of an existing field */
		RangeVar   *rel = makeRangeVar(NULL, NULL, typeName->location);
		char	   *field = NULL;
		Oid			relid;
		AttrNumber	attnum;

		/* deconstruct the name list */
		switch (list_length(typeName->names))
		{
			case 1:
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("improper %%TYPE reference (too few dotted names): %s",
								NameListToString(typeName->names)),
						 parser_errposition(pstate, typeName->location)));
				break;
			case 2:
				rel->relname = strVal(linitial(typeName->names));
				field = strVal(lsecond(typeName->names));
				break;
			case 3:
				rel->schemaname = strVal(linitial(typeName->names));
				rel->relname = strVal(lsecond(typeName->names));
				field = strVal(lthird(typeName->names));
				break;
			case 4:
				rel->catalogname = strVal(linitial(typeName->names));
				rel->schemaname = strVal(lsecond(typeName->names));
				rel->relname = strVal(lthird(typeName->names));
				field = strVal(lfourth(typeName->names));
				break;
			default:
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("improper %%TYPE reference (too many dotted names): %s",
								NameListToString(typeName->names)),
						 parser_errposition(pstate, typeName->location)));
				break;
		}

		/*
		 * Look up the field.
		 *
		 * XXX: As no lock is taken here, this might fail in the presence of
		 * concurrent DDL.  But taking a lock would carry a performance
		 * penalty and would also require a permissions check.
		 */
		relid = RangeVarGetRelid(rel, NoLock, missing_ok);
		attnum = get_attnum(relid, field);
		if (attnum == InvalidAttrNumber)
		{
			if (missing_ok)
				typoid = InvalidOid;
			else
				ereport(ERROR,
						(errcode(ERRCODE_UNDEFINED_COLUMN),
						 errmsg("column \"%s\" of relation \"%s\" does not exist",
								field, rel->relname),
						 parser_errposition(pstate, typeName->location)));
		}
		else
		{
			typoid = get_atttype(relid, attnum);

			/* this construct should never have an array indicator */
			Assert(typeName->arrayBounds == NIL);

			if (!(pstate && OidIsValid(pstate->p_pkgoid)))
			{
				/* emit nuisance notice (intentionally not errposition'd) */
				ereport(NOTICE,
						(errmsg("type reference %s converted to %s",
								TypeNameToString(typeName),
								format_type_be(typoid))));
			}
		}
	}
	else
	{
		/* Normal reference to a type name */
		QualifiedName qu;
		int			num;

		typoid = InvalidOid;
		num = ExtractQualifiedName(typeName->names, &qu);
		switch (num)
		{
			case 1:
				{
					/* Unqualified type name, so search the search path */
					typoid = TypenameGetTypidExtended(qu.func, temp_ok);

					/* If the previous typoid is invalid, We need to check
					 * whether it is a package's refcursor types.
					 */
					if (!OidIsValid(typoid))
						if (typeName->t_pkgoid)
							typoid = GetSysCacheOid2(TYPENAMENSP, Anum_pg_type_oid,
												 PointerGetDatum(qu.func),
												 ObjectIdGetDatum(typeName->t_pkgoid));
				}
				break;
			case 2:
				{
					Oid			namespaceId;
					ParseCallbackState pcbstate;

					setup_parser_errposition_callback(&pcbstate, pstate, typeName->location);
					namespaceId = get_package_oid(list_make1(linitial(typeName->names)), true);
					if (OidIsValid(namespaceId))
						typoid = GetSysCacheOid2(TYPENAMENSP, Anum_pg_type_oid,
												 PointerGetDatum(qu.func),
												 ObjectIdGetDatum(namespaceId));
					else
					{
						/* Look in specific schema only */
						namespaceId = LookupExplicitNamespace(qu.package, missing_ok);
						if (OidIsValid(namespaceId))
							typoid = GetSysCacheOid2(TYPENAMENSP, Anum_pg_type_oid,
													 PointerGetDatum(qu.func),
													 ObjectIdGetDatum(namespaceId));
						else
							typoid = InvalidOid;
					}
					cancel_parser_errposition_callback(&pcbstate);
				}
				break;
			case 3:
				if (SearchSysCacheExists1(NAMESPACENAME, PointerGetDatum(qu.dbname)))	/* select
																						 * schema.pkg.func() */
				{
					Oid			np_id;

					np_id = get_package_oid(list_make1(lsecond(typeName->names)), true);
					if (OidIsValid(np_id))
						typoid = InvalidOid;
				}
				else			/* select db.schema.fun() */
				{
					if (strcmp(qu.dbname, get_database_name(MyDatabaseId)) != 0)
						ereport(ERROR,
								(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
								 errmsg("cross-database references are not implemented.")));
					else
					{
						/* Look in specific schema only */
						Oid			namespaceId;
						ParseCallbackState pcbstate;

						setup_parser_errposition_callback(&pcbstate, pstate, typeName->location);

						namespaceId = LookupExplicitNamespace(qu.package, missing_ok);
						if (OidIsValid(namespaceId))
							typoid = GetSysCacheOid2(TYPENAMENSP, Anum_pg_type_oid,
													 PointerGetDatum(qu.func),
													 ObjectIdGetDatum(namespaceId));
						else
							typoid = InvalidOid;

						cancel_parser_errposition_callback(&pcbstate);
					}
				}
				break;
			case 4:
				if (SearchSysCacheExists1(NAMESPACENAME, PointerGetDatum(qu.schema)))
				{
					Oid			np_id;

					np_id = get_package_oid(list_make1(lthird(typeName->names)), true);
					if (OidIsValid(np_id))
						typoid = InvalidOid;
				}
				break;
			default:
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("improper qualified name (too many dotted names).")));
				break;
		}

		/* If an array reference, return the array type instead */
		if (typeName->arrayBounds != NIL)
			typoid = get_array_type(typoid);
	}

	if (!OidIsValid(typoid))
	{
		if (typmod_p)
			*typmod_p = -1;
		return NULL;
	}

	tup = SearchSysCache1(TYPEOID, ObjectIdGetDatum(typoid));
	if (!HeapTupleIsValid(tup)) /* should not happen */
		elog(ERROR, "cache lookup failed for type %u", typoid);

	typmod = typenameTypeMod(pstate, typeName, (Type) tup);

	if (typmod_p)
		*typmod_p = typmod;

	return (Type) tup;
}

/*
 * LookupTypeNameOid
 *		Given a TypeName object, lookup the pg_type syscache entry of the type.
 *		Returns InvalidOid if no such type can be found.  If the type is found,
 *		return its Oid.
 *
 * NB: direct callers of this function need to be aware that the type OID
 * returned may correspond to a shell type.  Most code should go through
 * typenameTypeId instead.
 *
 * pstate is only used for error location info, and may be NULL.
 */
Oid
LookupTypeNameOid(ParseState *pstate, const TypeName *typeName, bool missing_ok)
{
	Oid			typoid;
	Type		tup;

	tup = LookupTypeName(pstate, typeName, NULL, missing_ok);
	if (tup == NULL)
	{
		if (!missing_ok)
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("type \"%s\" does not exist",
							TypeNameToString(typeName)),
					 parser_errposition(pstate, typeName->location)));

		return InvalidOid;
	}

	typoid = ((Form_pg_type) GETSTRUCT(tup))->oid;
	ReleaseSysCache(tup);

	return typoid;
}

/*
 * typenameType - given a TypeName, return a Type structure and typmod
 *
 * This is equivalent to LookupTypeName, except that this will report
 * a suitable error message if the type cannot be found or is not defined.
 * Callers of this can therefore assume the result is a fully valid type.
 */
Type
typenameType(ParseState *pstate, const TypeName *typeName, int32 *typmod_p)
{
	Type		tup;

	tup = LookupTypeName(pstate, typeName, typmod_p, false);
	if (tup == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("type \"%s\" does not exist",
						TypeNameToString(typeName)),
				 parser_errposition(pstate, typeName->location)));
	if (!((Form_pg_type) GETSTRUCT(tup))->typisdefined)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("type \"%s\" is only a shell",
						TypeNameToString(typeName)),
				 parser_errposition(pstate, typeName->location)));
	return tup;
}

/*
 * typenameTypeId - given a TypeName, return the type's OID
 *
 * This is similar to typenameType, but we only hand back the type OID
 * not the syscache entry.
 */
Oid
typenameTypeId(ParseState *pstate, const TypeName *typeName)
{
	Oid			typoid;
	Type		tup;

	tup = typenameType(pstate, typeName, NULL);
	typoid = ((Form_pg_type) GETSTRUCT(tup))->oid;
	ReleaseSysCache(tup);

	return typoid;
}

/*
 * typenameTypeIdAndMod - given a TypeName, return the type's OID and typmod
 *
 * This is equivalent to typenameType, but we only hand back the type OID
 * and typmod, not the syscache entry.
 */
void
typenameTypeIdAndMod(ParseState *pstate, const TypeName *typeName,
					 Oid *typeid_p, int32 *typmod_p)
{
	Type		tup;

	tup = typenameType(pstate, typeName, typmod_p);
	*typeid_p = ((Form_pg_type) GETSTRUCT(tup))->oid;
	ReleaseSysCache(tup);
}

void
LookupType(ParseState *pstate, const TypeName *typeName,
					 Oid *typeid_p, int32 *typmod_p, bool missing_ok)
{
	Type		tup;

	tup = LookupTypeName(NULL, typeName, typmod_p, missing_ok);
	if (tup == NULL)
	{
		if (!missing_ok)
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("type \"%s\" does not exist",
							TypeNameToString(typeName)),
					 parser_errposition(pstate, typeName->location)));
		*typeid_p = InvalidOid;
	}
	else
	{
		Form_pg_type typ = (Form_pg_type) GETSTRUCT(tup);

		if (!typ->typisdefined)
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("type \"%s\" is only a shell",
							TypeNameToString(typeName)),
					 parser_errposition(pstate, typeName->location)));
		*typeid_p = typ->oid;
		ReleaseSysCache(tup);
	}
}

/*
 * typenameTypeMod - given a TypeName, return the internal typmod value
 *
 * This will throw an error if the TypeName includes type modifiers that are
 * illegal for the data type.
 *
 * The actual type OID represented by the TypeName must already have been
 * looked up, and is passed as "typ".
 *
 * pstate is only used for error location info, and may be NULL.
 */
static int32
typenameTypeMod(ParseState *pstate, const TypeName *typeName, Type typ)
{
	int32		result;
	Oid			typmodin;
	Datum	   *datums;
	int			n;
	ListCell   *l;
	ArrayType  *arrtypmod;
	ParseCallbackState pcbstate;

	/* Return prespecified typmod if no typmod expressions */
	if (typeName->typmods == NIL)
		return typeName->typemod;

	/*
	 * Else, type had better accept typmods.  We give a special error message
	 * for the shell-type case, since a shell couldn't possibly have a
	 * typmodin function.
	 */
	if (!((Form_pg_type) GETSTRUCT(typ))->typisdefined)
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("type modifier cannot be specified for shell type \"%s\"",
						TypeNameToString(typeName)),
				 parser_errposition(pstate, typeName->location)));

	typmodin = ((Form_pg_type) GETSTRUCT(typ))->typmodin;

	if (typmodin == InvalidOid)
		ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				 errmsg("type modifier is not allowed for type \"%s\"",
						TypeNameToString(typeName)),
				 parser_errposition(pstate, typeName->location)));

	/*
	 * Convert the list of raw-grammar-output expressions to a cstring array.
	 * Currently, we allow simple numeric constants, string literals, and
	 * identifiers; possibly this list could be extended.
	 */
	datums = (Datum *) palloc(list_length(typeName->typmods) * sizeof(Datum));
	n = 0;
	foreach(l, typeName->typmods)
	{
		Node	   *tm = (Node *) lfirst(l);
		char	   *cstr = NULL;

		if (IsA(tm, A_Const))
		{
			A_Const    *ac = (A_Const *) tm;

			if (IsA(&ac->val, Integer))
			{
				cstr = psprintf("%ld", (long) ac->val.val.ival);
			}
			else if (IsA(&ac->val, Float) ||
					 IsA(&ac->val, String))
			{
				/* we can just use the str field directly. */
				cstr = ac->val.val.str;
			}
		}
		else if (IsA(tm, ColumnRef))
		{
			ColumnRef  *cr = (ColumnRef *) tm;

			if (list_length(cr->fields) == 1 &&
				IsA(linitial(cr->fields), String))
				cstr = strVal(linitial(cr->fields));
		}
		if (!cstr)
			ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					 errmsg("type modifiers must be simple constants or identifiers"),
					 parser_errposition(pstate, typeName->location)));
		datums[n++] = CStringGetDatum(cstr);
	}

	/* hardwired knowledge about cstring's representation details here */
	arrtypmod = construct_array(datums, n, CSTRINGOID,
								-2, false, TYPALIGN_CHAR);

	/* arrange to report location if type's typmodin function fails */
	setup_parser_errposition_callback(&pcbstate, pstate, typeName->location);

	result = DatumGetInt32(OidFunctionCall1(typmodin,
											PointerGetDatum(arrtypmod)));

	cancel_parser_errposition_callback(&pcbstate);

	pfree(datums);
	pfree(arrtypmod);

	return result;
}

/*
 * appendTypeNameToBuffer
 *		Append a string representing the name of a TypeName to a StringInfo.
 *		This is the shared guts of TypeNameToString and TypeNameListToString.
 *
 * NB: this must work on TypeNames that do not describe any actual type;
 * it is mostly used for reporting lookup errors.
 */
static void
appendTypeNameToBuffer(const TypeName *typeName, StringInfo string)
{
	if (typeName->names != NIL)
	{
		/* Emit possibly-qualified name as-is */
		ListCell   *l;

		foreach(l, typeName->names)
		{
			if (l != list_head(typeName->names))
				appendStringInfoChar(string, '.');
			appendStringInfoString(string, strVal(lfirst(l)));
		}
	}
	else
	{
		/* Look up internally-specified type */
		appendStringInfoString(string, format_type_be(typeName->typeOid));
	}

	/*
	 * Add decoration as needed, but only for fields considered by
	 * LookupTypeName
	 */
	if (typeName->pct_type)
		appendStringInfoString(string, "%TYPE");

	if (typeName->arrayBounds != NIL)
		appendStringInfoString(string, "[]");
}

/*
 * TypeNameToString
 *		Produce a string representing the name of a TypeName.
 *
 * NB: this must work on TypeNames that do not describe any actual type;
 * it is mostly used for reporting lookup errors.
 */
char *
TypeNameToString(const TypeName *typeName)
{
	StringInfoData string;

	initStringInfo(&string);
	appendTypeNameToBuffer(typeName, &string);
	return string.data;
}

/*
 * TypeNameListToString
 *		Produce a string representing the name(s) of a List of TypeNames
 */
char *
TypeNameListToString(List *typenames)
{
	StringInfoData string;
	ListCell   *l;

	initStringInfo(&string);
	foreach(l, typenames)
	{
		TypeName   *typeName = lfirst_node(TypeName, l);

		if (l != list_head(typenames))
			appendStringInfoChar(&string, ',');
		appendTypeNameToBuffer(typeName, &string);
	}
	return string.data;
}

/*
 * LookupCollation
 *
 * Look up collation by name, return OID, with support for error location.
 */
Oid
LookupCollation(ParseState *pstate, List *collnames, int location)
{
	Oid			colloid;
	ParseCallbackState pcbstate;

	if (pstate)
		setup_parser_errposition_callback(&pcbstate, pstate, location);

	colloid = get_collation_oid(collnames, false);

	if (pstate)
		cancel_parser_errposition_callback(&pcbstate);

	return colloid;
}

/*
 * GetColumnDefCollation
 *
 * Get the collation to be used for a column being defined, given the
 * ColumnDef node and the previously-determined column type OID.
 *
 * pstate is only used for error location purposes, and can be NULL.
 */
Oid
GetColumnDefCollation(ParseState *pstate, ColumnDef *coldef, Oid typeOid)
{
	Oid			result;
	Oid			typcollation = get_typcollation(typeOid);
	int			location = coldef->location;

	if (coldef->collClause)
	{
		/* We have a raw COLLATE clause, so look up the collation */
		location = coldef->collClause->location;
		result = LookupCollation(pstate, coldef->collClause->collname,
								 location);
	}
	else if (OidIsValid(coldef->collOid))
	{
		/* Precooked collation spec, use that */
		result = coldef->collOid;
	}
	else
	{
		/* Use the type's default collation if any */
		result = typcollation;
	}

	/* Complain if COLLATE is applied to an uncollatable type */
	if (OidIsValid(result) && !OidIsValid(typcollation))
		ereport(ERROR,
				(errcode(ERRCODE_DATATYPE_MISMATCH),
				 errmsg("collations are not supported by type %s",
						format_type_be(typeOid)),
				 parser_errposition(pstate, location)));

	return result;
}

/* return a Type structure, given a type id */
/* NB: caller must ReleaseSysCache the type tuple when done with it */
Type
typeidType(Oid id)
{
	HeapTuple	tup;

	tup = SearchSysCache1(TYPEOID, ObjectIdGetDatum(id));
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for type %u", id);
	return (Type) tup;
}

/* given type (as type struct), return the type OID */
Oid
typeTypeId(Type tp)
{
	if (tp == NULL)				/* probably useless */
		elog(ERROR, "typeTypeId() called with NULL type struct");
	return ((Form_pg_type) GETSTRUCT(tp))->oid;
}

/* given type (as type struct), return the length of type */
int16
typeLen(Type t)
{
	Form_pg_type typ;

	typ = (Form_pg_type) GETSTRUCT(t);
	return typ->typlen;
}

/* given type (as type struct), return its 'byval' attribute */
bool
typeByVal(Type t)
{
	Form_pg_type typ;

	typ = (Form_pg_type) GETSTRUCT(t);
	return typ->typbyval;
}

/* given type (as type struct), return the type's name */
char *
typeTypeName(Type t)
{
	Form_pg_type typ;

	typ = (Form_pg_type) GETSTRUCT(t);
	/* pstrdup here because result may need to outlive the syscache entry */
	return pstrdup(NameStr(typ->typname));
}

/* given type (as type struct), return its 'typrelid' attribute */
Oid
typeTypeRelid(Type typ)
{
	Form_pg_type typtup;

	typtup = (Form_pg_type) GETSTRUCT(typ);
	return typtup->typrelid;
}

/* given type (as type struct), return its 'typcollation' attribute */
Oid
typeTypeCollation(Type typ)
{
	Form_pg_type typtup;

	typtup = (Form_pg_type) GETSTRUCT(typ);
	return typtup->typcollation;
}

/*
 * Given a type structure and a string, returns the internal representation
 * of that string.  The "string" can be NULL to perform conversion of a NULL
 * (which might result in failure, if the input function rejects NULLs).
 */
Datum
stringTypeDatum(Type tp, char *string, int32 atttypmod)
{
	Form_pg_type typform = (Form_pg_type) GETSTRUCT(tp);
	Oid			typinput = typform->typinput;
	Oid			typioparam = getTypeIOParam(tp);

	return OidInputFunctionCall(typinput, string, typioparam, atttypmod);
}

/*
 * Given a typeid, return the type's typrelid (associated relation), if any.
 * Returns InvalidOid if type is not a composite type.
 */
Oid
typeidTypeRelid(Oid type_id)
{
	HeapTuple	typeTuple;
	Form_pg_type type;
	Oid			result;

	typeTuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(type_id));
	if (!HeapTupleIsValid(typeTuple))
		elog(ERROR, "cache lookup failed for type %u", type_id);
	type = (Form_pg_type) GETSTRUCT(typeTuple);
	result = type->typrelid;
	ReleaseSysCache(typeTuple);
	return result;
}

/*
 * Given a typeid, return the type's typrelid (associated relation), if any.
 * Returns InvalidOid if type is not a composite type or a domain over one.
 * This is the same as typeidTypeRelid(getBaseType(type_id)), but faster.
 */
Oid
typeOrDomainTypeRelid(Oid type_id)
{
	HeapTuple	typeTuple;
	Form_pg_type type;
	Oid			result;

	for (;;)
	{
		typeTuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(type_id));
		if (!HeapTupleIsValid(typeTuple))
			elog(ERROR, "cache lookup failed for type %u", type_id);
		type = (Form_pg_type) GETSTRUCT(typeTuple);
		if (type->typtype != TYPTYPE_DOMAIN)
		{
			/* Not a domain, so done looking through domains */
			break;
		}
		/* It is a domain, so examine the base type instead */
		type_id = type->typbasetype;
		ReleaseSysCache(typeTuple);
	}
	result = type->typrelid;
	ReleaseSysCache(typeTuple);
	return result;
}

/*
 * error context callback for parse failure during parseTypeString()
 */
static void
pts_error_callback(void *arg)
{
	const char *str = (const char *) arg;

	errcontext("invalid type name \"%s\"", str);
}

/*
 * Given a string that is supposed to be a SQL-compatible type declaration,
 * such as "int4" or "integer" or "character varying(32)", parse
 * the string and return the result as a TypeName.
 * If the string cannot be parsed as a type, an error is raised.
 */
TypeName *
typeStringToTypeName(const char *str)
{
	List	   *raw_parsetree_list;
	TypeName   *typeName;
	ErrorContextCallback ptserrcontext;

	/* make sure we give useful error for empty input */
	if (strspn(str, " \t\n\r\f") == strlen(str))
		goto fail;

	/*
	 * Setup error traceback support in case of ereport() during parse
	 */
	ptserrcontext.callback = pts_error_callback;
	ptserrcontext.arg = unconstify(char *, str);
	ptserrcontext.previous = error_context_stack;
	error_context_stack = &ptserrcontext;

	raw_parsetree_list = raw_parser(str, RAW_PARSE_TYPE_NAME);

	error_context_stack = ptserrcontext.previous;

	/* We should get back exactly one TypeName node. */
	Assert(list_length(raw_parsetree_list) == 1);
	typeName = linitial_node(TypeName, raw_parsetree_list);

	/* The grammar allows SETOF in TypeName, but we don't want that here. */
	if (typeName->setof)
		goto fail;

	return typeName;

fail:
	ereport(ERROR,
			(errcode(ERRCODE_SYNTAX_ERROR),
			 errmsg("invalid type name \"%s\"", str)));
	return NULL;				/* keep compiler quiet */
}

/*
 * Given a string that is supposed to be a SQL-compatible type declaration,
 * such as "int4" or "integer" or "character varying(32)", parse
 * the string and convert it to a type OID and type modifier.
 * If missing_ok is true, InvalidOid is returned rather than raising an error
 * when the type name is not found.
 */
void
parseTypeString(const char *str, Oid *typeid_p, int32 *typmod_p, bool missing_ok)
{
	TypeName   *typeName;
	Type		tup;

	typeName = typeStringToTypeName(str);

	tup = LookupTypeName(NULL, typeName, typmod_p, missing_ok);
	if (tup == NULL)
	{
		if (!missing_ok)
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("type \"%s\" does not exist",
							TypeNameToString(typeName)),
					 parser_errposition(NULL, typeName->location)));
		*typeid_p = InvalidOid;
	}
	else
	{
		Form_pg_type typ = (Form_pg_type) GETSTRUCT(tup);

		if (!typ->typisdefined)
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("type \"%s\" is only a shell",
							TypeNameToString(typeName)),
					 parser_errposition(NULL, typeName->location)));
		*typeid_p = typ->oid;
		ReleaseSysCache(tup);
	}
}

/************************************************************
 * Funcname: LookupTypeNameFromSynonym
 * Description: Look up the type name from the synonym name
 * Return: Type
 * Author: qingshiyu
 * Date: 2021.06.10
 ************************************************************/
Type 
LookupTypeNameFromSynonym(ParseState *pstate, const TypeName *typeName, int32 *typmod_p, bool missing_ok)
{
	Relation	pg_synonym_rel;
	List   		*synnamelist = typeName->names;
	char	   	*synname = NULL;
	char		*schemaname = NULL;
	Oid			scheamoid = InvalidOid;
	HeapTuple	tuple = NULL;
	bool		pubflg = false;
	Form_pg_synonym synonymform = NULL;
	const TypeName 	*temptypeName = NULL;
	Form_pg_type formpgtype = NULL;
	Type		tup;
	
	pg_synonym_rel = table_open(SynonymRelationId, RowExclusiveLock);

	if (typeName->names == NIL)
	{
		table_close(pg_synonym_rel, NoLock);
		return NULL;
	}
	else
	{
		DeconstructQualifiedName(typeName->names, &schemaname, &synname);
		if (schemaname)
			scheamoid = LookupExplicitNamespace(schemaname, missing_ok);
		else
			scheamoid = QualifiedNameGetCreationNamespace(synnamelist, &synname);
	}

	tuple = SearchSysCache3(SYNONYMNAMENSPPUB, PointerGetDatum(synname),
								PointerGetDatum(scheamoid), PointerGetDatum(pubflg));

	temptypeName = copyObject(typeName);

	if (!HeapTupleIsValid(tuple))
	{
		pubflg = true;
		tuple = SearchSysCache3(SYNONYMNAMENSPPUB, PointerGetDatum(synname),
									PointerGetDatum(scheamoid), PointerGetDatum(pubflg));
	}

	if (!HeapTupleIsValid(tuple))
	{
		/*ereport(ERROR,
			(errcode(ERRCODE_UNDEFINED_OBJECT),
			 errmsg("type \"%s\" does not exist",
					TypeNameToString(typeName)),
			 parser_errposition(pstate, typeName->location)));*/
		table_close(pg_synonym_rel, NoLock);
		return NULL;
	}
	else
	{	
		synonymform = (Form_pg_synonym) GETSTRUCT(tuple);

		if (synonymform != NULL)
		{
			Datum 	typeDatum;
			bool	isnull;
			char 	*typname;
			Oid		CurUsrId;

			CurUsrId = GetUserId();

			if (synonymform->synowner != CurUsrId)
			{
				ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("type \"%s\" does not exist",
							TypeNameToString(typeName)),
					 parser_errposition(pstate, temptypeName->location)));
			}

			/* get schema and type name */
			typeDatum = SysCacheGetAttr(SYNONYMNAMENSPPUB, tuple,
										  Anum_pg_synonym_synobjname, &isnull);

			if (isnull)
				elog(ERROR, "null synobjname");

			typname = pstrdup(TextDatumGetCString(typeDatum));

			/* judge the name list length */
			
			/* deconstruct the name list */
			switch (list_length(temptypeName->names))
			{
				case 1:
					strVal(linitial(temptypeName->names)) = typname;
					break;
				case 2:
					strVal(lsecond(temptypeName->names)) = typname;
					break;
				case 3:
					strVal(lthird(temptypeName->names)) = typname;
					break;
				default:
					ereport(ERROR,
							(errcode(ERRCODE_SYNTAX_ERROR),
							 errmsg("improper %%TYPE reference (too many dotted names): %s",
									NameListToString(temptypeName->names)),
							 parser_errposition(pstate, temptypeName->location)));
					break;
			}
		}

		tup = LookupTypeName(pstate, temptypeName, typmod_p, false);

		if (tup == NULL)
			tup = LookupTypeNameFromSynonym(pstate, temptypeName, typmod_p, missing_ok);

		if (tup == NULL)
		{
			table_close(pg_synonym_rel, NoLock);
			return NULL;
		}

		formpgtype = (Form_pg_type) GETSTRUCT(tup);

		if (formpgtype != NULL)
		{
			/* the only support compsite type */
			if (formpgtype->typtype == 'b' || formpgtype->typtype  == 'd'  
				|| formpgtype->typtype  == 'e' || formpgtype->typtype  == 'p'
				|| formpgtype->typtype  == 'r')
			{
				ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("type \"%s\" does not exist",
						TypeNameToString(typeName)),
				 parser_errposition(pstate, typeName->location)));
			}
		}
	}

	ReleaseSysCache(tuple);

	table_close(pg_synonym_rel, NoLock);

	return tup;
}
