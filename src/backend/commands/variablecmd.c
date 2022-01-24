/*-------------------------------------------------------------------------
 *
 * varaiblecmd.c
 *		package's variable
 *
 * Portions Copyright (c) 2021-2022, IvorySQL
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *		src/backend/commands/varaiblecmd.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "miscadmin.h"
#include "access/heapam.h"
#include "access/htup_details.h"
#include "access/xact.h"
#include "catalog/indexing.h"
#include "catalog/objectaddress.h"
#include "catalog/pg_package.h"
#include "catalog/pg_variable.h"
#include "catalog/namespace.h"
#include "catalog/pg_type.h"
#include "catalog/catalog.h"
#include "commands/variable.h"
#include "commands/typecmds.h"
#include "parser/parse_type.h"
#include "parser/parse_collate.h"
#include "parser/parse_coerce.h"
#include "parser/parse_expr.h"
#include "utils/lsyscache.h"
#include "utils/syscache.h"
#include "utils/fmgroids.h"



ObjectAddress
CreateVariable(ParseState *pstate, VarStmt *stmt, bool replace, bool isbody)
{
	Oid			namespaceid;
	AclResult	aclresult;
	Oid			typid;
	int32		typmod;
	Oid			varowner = GetUserId();
	Oid			collation;
	Oid			typcollation;
	Oid			variableoid = 0;
	ObjectAddress variable;
	HeapTuple	oldtup;
	Relation	rel;
	bool		ispkg = false;

	Node	   *cooked_default = NULL;

	namespaceid = pstate->p_pkgoid;
	if (namespaceid)
		ispkg = true;

	/*
	 * Check if variable exists
	 */
	if (stmt->varType)
	{
		Form_pg_type oldvar;
		rel = table_open(TypeRelationId, RowExclusiveLock);

		/* look for it in package variables */
		oldtup = SearchSysCache2(TYPENAMENSP,
								 PointerGetDatum(strVal(linitial(stmt->varType->names))),
								 ObjectIdGetDatum(namespaceid));
		if (!HeapTupleIsValid(oldtup))
		{
			/* look for it in system catalogs. */
			oldtup = LookupTypeName(pstate, stmt->varType, NULL, false);
		}

		if (!HeapTupleIsValid(oldtup))
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_OBJECT),
					 errmsg("type \"%s\" does not exist", strVal(linitial(stmt->varType->names)))));

		oldvar = (Form_pg_type) GETSTRUCT(oldtup);
		typid = oldvar->oid;
		typmod = oldvar->typtypmod;
		variableoid = GetNewOidWithIndex(rel, TypeOidIndexId,
										 Anum_pg_type_oid);
		ReleaseSysCache(oldtup);
		table_close(rel, RowExclusiveLock);
	}
	else
		elog(ERROR, "The syntax error at variable:%s", stmt->varname);
	typcollation = get_typcollation(typid);

	aclresult = pg_type_aclcheck(typid, GetUserId(), ACL_USAGE);
	if (aclresult != ACLCHECK_OK)
		aclcheck_error_type(aclresult, typid);

	collation = typcollation;
	if (stmt->defexpr)
	{
		cooked_default = transformExpr(pstate, stmt->defexpr,
									   EXPR_KIND_VARIABLE_DEFAULT);

		cooked_default = coerce_to_specific_type(pstate,
												 cooked_default, typid, "DEFAULT");
		assign_expr_collations(pstate, cooked_default);
	}


	variable = VariableCreate(stmt->varname,
							  namespaceid,
							  variableoid,
							  typid,
							  typmod,
							  varowner,
							  collation,
							  cooked_default,
							  VARIABLE_EOX_NOOP,
							  true,
							  false,
							  ispkg,
							  replace,
							  isbody);

	/*
	 * We must bump the command counter to make the newly-created variable
	 * tuple visible for any other operations.
	 */
	CommandCounterIncrement();

	return variable;
}

/*
 * Drop variable by OID
 */
void
RemoveVariable(Oid varid)
{
	Relation	rel;
	HeapTuple	tup;

	rel = table_open(VariableRelationId, RowExclusiveLock);

	tup = SearchSysCache1(VARIABLEOID, ObjectIdGetDatum(varid));

	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for variable %u", varid);

	CatalogTupleDelete(rel, &tup->t_self);

	ReleaseSysCache(tup);

	table_close(rel, RowExclusiveLock);
}

char *
get_variable_name(Oid varid, bool missing_ok)
{
	char	   *varname;
	HeapTuple	tup;
	Form_pg_variable varform;

	tup = SearchSysCache1(VARIABLEOID, ObjectIdGetDatum(varid));
	if (!HeapTupleIsValid(tup))
	{
		if (!missing_ok)
			elog(ERROR, "cache lookup failed for schema variable %u",
				 varid);
		return NULL;
	}

	varform = (Form_pg_variable) GETSTRUCT(tup);
	varname = pstrdup(NameStr(varform->varname));

	ReleaseSysCache(tup);

	return varname;
}

/*
 * Create cursor and store it in pg_type and pg_variable
 */

ObjectAddress
CreateCursor(ParseState *pstate, DeclareCursorStmt *cur, bool isbody)
{
	Oid			namespaceid;
	char	   *typename;
	char	   *ref_cur = "refcursor";
	Oid			catalogoid = 11;
	int16		internalLength = -1;
	char		category = TYPCATEGORY_USER;
	char		delimiter = DEFAULT_TYPDELIM;
	Oid			inputOid = F_RECORD_IN;
	Oid			outputOid = F_RECORD_OUT;
	Oid			receiveOid = F_RECORD_RECV;
	Oid			sendOid = F_RECORD_SEND;
	Oid			typmodinOid = InvalidOid;
	Oid			typmodoutOid = InvalidOid;
	Oid			analyzeOid = InvalidOid;
	Oid			elemType = InvalidOid;
	Oid			variableoid = InvalidOid;
	ObjectAddress address;
	ObjectAddress myself,
				referenced;
	char	   *defaultValue = NULL;
	bool		byValue = false;
	Oid			collation = InvalidOid;
	char		storage = TYPSTORAGE_EXTENDED;
	char		alignment = TYPALIGN_DOUBLE;
	Oid			array_oid;
	Node	   *cooked_default = cur->query;
	Oid			refoid;
	Oid			typoid;


	namespaceid = pstate->p_pkgoid;
	typename = cur->portalname;
	array_oid = AssignTypeArrayOid();

	/*
	 * Look to see if type already exists.
	 */
	typoid = GetSysCacheOid2(TYPENAMENSP, Anum_pg_type_oid,
							 CStringGetDatum(typename),
							 ObjectIdGetDatum(namespaceid));
	if (!OidIsValid(typoid))
	{
		/*
		 * store cursor type in pg_type.
		 */
		address =
			TypeCreate(InvalidOid,
					   typename,
					   namespaceid,
					   InvalidOid,
					   0,
					   GetUserId(),
					   internalLength,
					   TYPTYPE_COMPOSITE,
					   category,
					   false,
					   delimiter,
					   inputOid,
					   outputOid,
					   receiveOid,
					   sendOid,
					   typmodinOid,
					   typmodoutOid,
					   analyzeOid,
					   InvalidOid,
					   elemType,
					   false,
					   array_oid,
					   InvalidOid,
					   defaultValue,
					   NULL,
					   byValue,
					   alignment,
					   storage,
					   -1,
					   0,
					   false,
					   collation,
					   (isbody? PACKAGE_MEMBER_PRIVATE : PACKAGE_MEMBER_PUBLIC)
			);
		/* prevent error when processing duplicate objects */
		CommandCounterIncrement();
	}

	typoid = GetSysCacheOid2(TYPENAMENSP, Anum_pg_type_oid,
							 CStringGetDatum(typename),
							 ObjectIdGetDatum(namespaceid));

	myself.classId = TypeRelationId;
	myself.objectId = typoid;
	myself.objectSubId = 0;
	if (namespaceid)
	{
		referenced.classId = PackageRelationId;
		referenced.objectId = namespaceid;
		referenced.objectSubId = 0;
		recordDependencyOn(&myself, &referenced, DEPENDENCY_AUTO);
	}

	/*
	 * Look to see if refcursor already exists.
	 */
	refoid = GetSysCacheOid2(TYPENAMENSP, Anum_pg_type_oid,
							 CStringGetDatum(ref_cur),
							 ObjectIdGetDatum(catalogoid));
	if (!OidIsValid(refoid))
	{
		ereport(ERROR,
				(errcode(ERRCODE_DUPLICATE_OBJECT),
				 errmsg("type \"%s\" not exists", ref_cur)));
	}

	/*
	 * store cursor  in pg_variable.
	 */
	variableoid = GetSysCacheOid2(VARIABLENAMENSP, Anum_pg_variable_oid,
								  CStringGetDatum(typename),
								  ObjectIdGetDatum(namespaceid)
		);
	(void) VariableCreate(typename,
						  namespaceid,
						  variableoid,
						  refoid,
						  -1,
						  GetUserId(),
						  collation,
						  cooked_default,
						  VARIABLE_EOX_NOOP,
						  true,
						  false,
						  true,
						  true,
						  false);

	/* prevent error when processing duplicate objects */
	CommandCounterIncrement();
	return address;
}
