/*-------------------------------------------------------------------------
 *
 * packagecmds.c
 *
 *    Routines for CREATE and DROP packge commands and CREATE and DROP
 *    CAST commands.
 *
 *
 *
 * IDENTIFICATION
 *    src/backend/commands/packagecmds.c
 *
 * DESCRIPTION
 *    These routines take the parse tree, and pass the results to the
 *    corresponding "FooDefine" routines (in src/catalog) that do
 *    the actual catalog-munging.  These routines also verify permission
 *    of the user to execute the command.
 *
 * NOTES
 *    These things must be defined and committed in the following order:
 *      "create package":
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"
#include "access/genam.h"
#include "access/heapam.h"
#include "access/htup_details.h"
#include "access/sysattr.h"
#include "access/tableam.h"
#include "access/xact.h"
#include "catalog/catalog.h"
#include "catalog/dependency.h"
#include "catalog/indexing.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "catalog/pg_authid.h"
#include "catalog/namespace.h"
#include "catalog/objectaccess.h"
#include "catalog/pg_package.h"
#include "catalog/pg_language.h"
#include "catalog/pg_variable.h"
#include "commands/defrem.h"
#include "commands/extension.h"
#include "commands/variable.h"
#include "commands/packagecmds.h"
#include "commands/typecmds.h"
#include "commands/tablecmds.h"
#include "utils/builtins.h"
#include "utils/fmgroids.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"
#include "utils/syscache.h"
#include "utils/ruleutils.h"
#include "parser/analyze.h"
#include "parser/parser.h"
#include "parser/parse_type.h"
#include "parser/parse_coerce.h"
#include "parser/parse_expr.h"
#include "parser/parse_collate.h"

#include "nodes/makefuncs.h"
#include "nodes/nodes.h"
#include "miscadmin.h"


static void CreatePackageElems(ParseState *pstate, char *nspname, char *pkgname,
							   List *pkgelements, bool replace, bool isbody);
static void RemovePackageFunctions(Oid packageOid, char proaccess, bool replace);
static void RemovePackageVariables(Oid packageOid, char varaccess);
static void RemoveVariabletype(Oid packageOid, char typaccess);
static void ValidatePackageElems(Oid packageOid, char proaccess, Oid *funcid);
static void update_function_src(Relation rel, HeapTuple tuple, char *src);
static char *build_cons_prosrc(ParseState *pstate, List *specelems, CreatePackageStmt *stmt);
static CreateFunctionStmt *make_cons_stmt(CreatePackageStmt *stmt, char *prosrc);
static char *get_func_src(CreateFunctionStmt *fn);
static Oid	get_lang_validator(void);
static void	create_constructor(ParseState *pstate, CreatePackageStmt *stmt);
static char *get_cursor_query(List *variables, DeclareCursorStmt *cur);
static void update_package_src(Relation rel, HeapTuple tuple, char *src);



/*
 * CreatePackage
 *   Execute a CREATE PACKAGE/CREATE PACKAGE BODY utility statement.
 */
ObjectAddress
CreatePackage(ParseState *pstate, CreatePackageStmt *stmt)
{
	char	   *packagename;
	char	   *pkgspec = NULL;
	char	   *pkgbody = NULL;
	Oid			namespaceId;
	Oid			funcid = InvalidOid;
	Oid			languageValidator;
	Oid			pkgoid;
	ObjectAddress myself;
	remove_package_state remove_pkgstate;

	namespaceId = QualifiedNameGetCreationNamespace(stmt->name,
													&packagename);
	pkgspec = stmt->specsrc;
	pkgbody = stmt->bodysrc;

	pkgoid = PackageCreate(packagename, namespaceId, stmt->replace,
						   stmt->isbody, pkgspec, pkgbody, GetUserId(),
						   stmt->secdef);
	pstate->p_pkgoid = pkgoid;

	/* remove package state from PL hashtable, if any */
	remove_pkgstate = (remove_package_state)
						*find_rendezvous_variable("remove_package_state");
	if (remove_pkgstate != NULL)
		remove_pkgstate(pkgoid);

	if (stmt->isbody && stmt->replace)
	{
		RemovePackageFunctions(pkgoid, PACKAGE_MEMBER_PRIVATE, false);
		RemovePackageVariables(pkgoid, PACKAGE_MEMBER_PRIVATE);
		RemoveVariabletype(pkgoid, PACKAGE_MEMBER_PRIVATE);
	}

	if (pkgspec && stmt->replace)
	{
		RemovePackageFunctions(pkgoid, PACKAGE_MEMBER_PUBLIC, false);
		RemovePackageVariables(pkgoid, PACKAGE_MEMBER_PUBLIC);
		RemoveVariabletype(pkgoid, PACKAGE_MEMBER_PUBLIC);
	}

	/*
	 * We must bump the command counter to make the newly-created package
	 * tuple visible for package elements.
	 */
	CommandCounterIncrement();

	CreatePackageElems(pstate, get_namespace_name(namespaceId),
					   packagename, stmt->elems, stmt->replace, stmt->isbody);

	/*
	 * bump the command counter to make the newly-created package elements
	 * visible.
	 */
	CommandCounterIncrement();

	/* create the constructor function. */
	create_constructor(pstate, stmt);

	if (stmt->isbody)
		ValidatePackageElems(pkgoid, PACKAGE_MEMBER_PUBLIC, &funcid);

	myself.classId = PackageRelationId;
	myself.objectId = pkgoid;
	myself.objectSubId = 0;

	/* call the validator function to validate package source. */
	languageValidator = get_lang_validator();
	if (stmt->isbody &&
		OidIsValid(languageValidator) &&
		OidIsValid(funcid))
		OidFunctionCall1(languageValidator, ObjectIdGetDatum(funcid));

	return myself;
}


static void
CreatePackageElems(ParseState *pstate, char *nspname, char *pkgname,
				   List *pkgelements, bool replace, bool isbody)
{
	ListCell   *lc;

	foreach(lc, pkgelements)
	{
		Node	   *elem = (Node *) lfirst(lc);

		switch (nodeTag(elem))
		{
			case T_CreateFunctionStmt:
				{
					CreateFunctionStmt *stmt = (CreateFunctionStmt *) elem;
					List	   *funcname;

					funcname = list_make2(makeString(pkgname),
										  llast(stmt->funcname));
					stmt->funcname = funcname;
					if (isbody)
						stmt->replace = true;
					else
						stmt->replace = replace;
					(void) CreateFunction(pstate, stmt);
				}
				break;
			case T_VarStmt:
				{
					VarStmt    *var = (VarStmt *) elem;

					(void) CreateVariable(pstate, var, replace, isbody);
				}
				break;
			case T_DeclareCursorStmt:
				{
					DeclareCursorStmt *cur = (DeclareCursorStmt *) elem;

					(void) CreateCursor(pstate, cur, isbody);
				}
				break;
			case T_CompositeTypeStmt:	/* TYPE IS RECORD */
				{
					CompositeTypeStmt *rec = (CompositeTypeStmt *) elem;

					(void) DefineRecord(pstate, rec, isbody);
				}
				break;
			case T_CreateDomainStmt:	/* REF CURSOR */
				{
					CreateDomainStmt *refcur = (CreateDomainStmt *) elem;

					(void) DefineRefCursor(pstate, refcur, isbody);
				}
				break;
			default:
				ereport(ERROR,
						(errmsg("no such package element: %d", nodeTag(elem))));
		}

	}
}

/*
 * get the variable name and initial from VarStmt.
 */
static char *
build_cons_prosrc(ParseState *pstate, List *specelems, CreatePackageStmt *stmt)
{
	ListCell   *lc;
	StringInfoData buf;
	List	   *variables;
	bool		add_decl = false;
	List	   *bodyelems = stmt->elems;

	initStringInfo(&buf);

	variables = list_concat_copy(specelems, bodyelems);
	foreach(lc, variables)
	{
		Node	   *elem = (Node *) lfirst(lc);

		if (IsA(elem, VarStmt))
		{
			VarStmt    *var = (VarStmt *) elem;
			Oid			typid = 0;
			int32		typmod = -1;
			HeapTuple	oldtup;

			if (!add_decl)		/* only add DECLARE section if there are
								 * atleast one variable. */
			{
				appendStringInfo(&buf, "DECLARE\n");
				add_decl = true;
			}
			if(var->varType->pct_rowtype)
			{
				char	*vartype = strVal(linitial(var->varType->names));
				appendStringInfo(&buf, "   %s %s",var->varname,vartype);
				appendStringInfo(&buf, "%s\n","%rowtype;");
				continue;
			}

			LookupType(pstate, var->varType, &typid, &typmod, true);
			if (!OidIsValid(typid))
			{
				oldtup = SearchSysCache2(TYPENAMENSP,
									PointerGetDatum(strVal(linitial(var->varType->names))),
									ObjectIdGetDatum(pstate->p_pkgoid));
				if (HeapTupleIsValid(oldtup))
				{
					Form_pg_type oldvar = (Form_pg_type) GETSTRUCT(oldtup);

					typid = oldvar->oid;
					if (oldvar->typtype == 'd' && oldvar->typbasetype == REFCURSOROID)
						typmod = -1;
					else
						typmod = oldvar->typtypmod;
					ReleaseSysCache(oldtup);
				}
				else
				{
					ereport(ERROR,
							(errcode(ERRCODE_UNDEFINED_OBJECT),
							 errmsg("type \"%s\" does not exist",
									TypeNameToString(var->varType)),
							 parser_errposition(pstate, var->varType->location)));
				}
			}

			if (var->defexpr != NULL)
			{
				char	   *varstr = NULL;
				Node	   *cooked_default = NULL;

				cooked_default = transformExpr(pstate, var->defexpr,
											   EXPR_KIND_VARIABLE_DEFAULT);
				cooked_default = coerce_to_specific_type(pstate,
														 cooked_default, typid, "DEFAULT");
				assign_expr_collations(pstate, cooked_default);

				/* get the string from the expr */
				varstr = deparse_expression(cooked_default, NIL, false, false);

				/* add to buffer */
				appendStringInfo(&buf, "    %s %s := %s;\n", var->varname,
								 format_type_with_typemod(typid, typmod), varstr);
			}
			else
			{
				appendStringInfo(&buf, "    %s %s;\n", var->varname,
								 format_type_with_typemod(typid, typmod));
			}
		}

		if (IsA(elem, DeclareCursorStmt))
		{
			DeclareCursorStmt *cur = (DeclareCursorStmt *) elem;
			char	*cursorQuery = NULL;

			if (!add_decl)		/* only add DECLARE section if there are
								 * atleast one variable. */
			{
				appendStringInfo(&buf, "DECLARE\n");
				add_decl = true;
			}
			cursorQuery = get_cursor_query(variables, cur);
			if(cursorQuery != NULL)
				appendStringInfoString(&buf, cursorQuery);
		}
	}

	/* add the initializer body or create an empty one. */
	if (stmt->initializer)
	{
		char	   *src = get_func_src((CreateFunctionStmt *) stmt->initializer);

		if (src)
			appendStringInfo(&buf, "%s;\n", src);
		else					/* shouldn't happen */
			ereport(ERROR,
					(errmsg("package initializer source not found")));
	}
	else
	{
		appendStringInfo(&buf, "BEGIN\n");
		appendStringInfo(&buf, "    NULL;\n");
		appendStringInfo(&buf, "END;\n");
	}

	return buf.data;
}

/*
 *	create the constructor function for this package
 */
static CreateFunctionStmt *
make_cons_stmt(CreatePackageStmt *stmt, char *prosrc)
{
	CreateFunctionStmt *n = makeNode(CreateFunctionStmt);

	n->is_procedure = true;
	n->replace = stmt->replace;
	n->funcname = list_make1(llast(stmt->name));
	n->parameters = NIL;
	n->returnType = NULL;
	n->proaccess = PACKAGE_MEMBER_PRIVATE;
	n->options = NIL;
	n->options = lappend(n->options,
						 makeDefElem("language", (Node *) makeString("plisql"), 0));
	n->options = lappend(n->options,
						 makeDefElem("as", (Node *) list_make1(makeString(prosrc)), 0));
	return n;
}

/*
 *	create the constructor function for this package
 */
static char *
get_func_src(CreateFunctionStmt *fn)
{
	ListCell   *option;
	DefElem    *as_or_is_item = NULL;
	List	   *options = fn->options;

	foreach(option, options)
	{
		DefElem    *defel = (DefElem *) lfirst(option);

		if ((strcmp(defel->defname, "as") == 0) || (strcmp(defel->defname, "is") == 0))
		{
			as_or_is_item = defel;
			break;
		}
	}

	if (as_or_is_item)
	{
		List	   *as_or_is = (List *) as_or_is_item->arg;

		return strVal(linitial(as_or_is));
	}

	return NULL;
}

/*
 * Guts of package deletion.
 */
void
DropPackageById(Oid packageOid)
{
	remove_package_state remove_pkgstate;
	Relation	relation;
	HeapTuple	tup;

	relation = table_open(PackageRelationId, RowExclusiveLock);

	tup = SearchSysCache1(PACKAGEOID,
						  ObjectIdGetDatum(packageOid));
	if (!HeapTupleIsValid(tup)) /* should not happen */
		elog(ERROR, "cache lookup failed for package %u", packageOid);

	CatalogTupleDelete(relation, &tup->t_self);

	ReleaseSysCache(tup);

	table_close(relation, RowExclusiveLock);

	/* remove package state from PL hashtable, if any */
	remove_pkgstate = (remove_package_state)
						*find_rendezvous_variable("remove_package_state");
	if (remove_pkgstate != NULL)
		remove_pkgstate(packageOid);
}

void
DropPackagebody(Oid packageOid)
{
	remove_package_state remove_pkgstate;
	Relation	relation;
	HeapTuple	tup;
	bool		isnull;

	relation = table_open(PackageRelationId, RowExclusiveLock);

	tup = SearchSysCache1(PACKAGEOID,
						  ObjectIdGetDatum(packageOid));
	if (!HeapTupleIsValid(tup)) /* should not happen */
		elog(ERROR, "cache lookup failed for package %u", packageOid);
	(void) SysCacheGetAttr(PACKAGEOID, tup, Anum_pg_package_pkgbody, &isnull);
	if (isnull)
		elog(ERROR, "The package body does not exist");
	/* update package src attribute to null */
	update_package_src(relation, tup, "");

	/* remove packages private elements */
	RemovePackageFunctions(packageOid, PACKAGE_MEMBER_PRIVATE, true);
	RemovePackageVariables(packageOid, PACKAGE_MEMBER_PRIVATE);
	RemoveVariabletype(packageOid, PACKAGE_MEMBER_PRIVATE);

	ReleaseSysCache(tup);
	table_close(relation, RowExclusiveLock);

	/* remove package state from PL hashtable, if any */
	remove_pkgstate = (remove_package_state)
						*find_rendezvous_variable("remove_package_state");
	if (remove_pkgstate != NULL)
		remove_pkgstate(packageOid);
}

/*
 * remove function and procedures of a given package.
 */
static void
RemovePackageFunctions(Oid packageOid, char proaccess, bool updatesrc)
{
	ScanKeyData key[2];
	int			keycount;
	Relation	rel;
	TableScanDesc scan;
	HeapTuple	tuple;

	keycount = 0;
	ScanKeyInit(&key[keycount++],
				Anum_pg_proc_pronamespace,
				BTEqualStrategyNumber, F_OIDEQ,
				ObjectIdGetDatum(packageOid));

	ScanKeyInit(&key[keycount++],
				Anum_pg_proc_proaccess,
				BTEqualStrategyNumber, F_CHAREQ,
				CharGetDatum(proaccess));

	rel = table_open(ProcedureRelationId, AccessShareLock);
	scan = table_beginscan_catalog(rel, keycount, key);

	while ((tuple = heap_getnext(scan, ForwardScanDirection)) != NULL)
	{
		if (updatesrc)
			update_function_src(rel, tuple, "");
		else
		{
			Oid			funcoid = ((Form_pg_proc) GETSTRUCT(tuple))->oid;

			deleteDependencyRecordsFor(ProcedureRelationId, funcoid, true);

			/*
			 * Remove dependency on owner.
			 */
			deleteSharedDependencyRecordsFor(ProcedureRelationId, funcoid, 0);
			simple_heap_delete(rel, &tuple->t_self);
		}
	}

	table_endscan(scan);
	table_close(rel, AccessShareLock);
}


/*
 * validate that a function or procedure declared in the package spec was also
 * defined in the package body.
 */
static void
ValidatePackageElems(Oid packageOid, char proaccess, Oid *funcid)
{
	ScanKeyData key[2];
	int			keycount;
	Relation	rel;
	TableScanDesc scan;
	HeapTuple	tuple;

	keycount = 0;
	ScanKeyInit(&key[keycount++],
				Anum_pg_proc_pronamespace,
				BTEqualStrategyNumber, F_OIDEQ,
				ObjectIdGetDatum(packageOid));

	ScanKeyInit(&key[keycount++],
				Anum_pg_proc_proaccess,
				BTEqualStrategyNumber, F_CHAREQ,
				CharGetDatum(proaccess));

	rel = table_open(ProcedureRelationId, AccessShareLock);
	scan = table_beginscan_catalog(rel, keycount, key);

	while ((tuple = heap_getnext(scan, ForwardScanDirection)) != NULL)
	{
		bool		isnull;
		Datum		srcdt;
		Datum		namedt;
		char	   *prosrc;
		char	   *proname;

		srcdt = SysCacheGetAttr(PROCOID, tuple, Anum_pg_proc_prosrc, &isnull);
		if (isnull)
			elog(ERROR, "null prosrc");
		prosrc = TextDatumGetCString(srcdt);

		namedt = SysCacheGetAttr(PROCOID, tuple, Anum_pg_proc_proname, &isnull);
		if (isnull)
			elog(ERROR, "null proname");
		proname = NameStr(*(DatumGetName(namedt)));

		if (strlen(prosrc) == 0)
			ereport(ERROR,
					(errmsg("no defination for package element: %s", proname)));

		if (funcid)
			*funcid = ((Form_pg_proc) GETSTRUCT(tuple))->oid;
	}

	table_endscan(scan);
	table_close(rel, AccessShareLock);
}

static void
update_function_src(Relation rel, HeapTuple tuple, char *src)
{
	TupleDesc	tupdesc;
	HeapTuple	newtuple;
	bool		nulls[Natts_pg_proc];
	Datum		values[Natts_pg_proc];
	bool		replaces[Natts_pg_proc];
	int			i;

	for (i = 0; i < Natts_pg_proc; ++i)
	{
		nulls[i] = false;
		values[i] = (Datum) 0;
		replaces[i] = false;
	}

	values[Anum_pg_proc_prosrc - 1] = CStringGetTextDatum(src);
	replaces[Anum_pg_proc_prosrc - 1] = true;

	tupdesc = RelationGetDescr(rel);
	newtuple = heap_modify_tuple(tuple, tupdesc, values, nulls, replaces);
	CatalogTupleUpdate(rel, &newtuple->t_self, newtuple);

	heap_freetuple(newtuple);
}

static void
update_package_src(Relation rel, HeapTuple tuple, char *src)
{
	TupleDesc	tupdesc;
	HeapTuple	newtuple;
	bool		nulls[Natts_pg_package];
	Datum		values[Natts_pg_package];
	bool		replaces[Natts_pg_package];
	int			i;

	for (i = 0; i < Natts_pg_package; ++i)
	{
		nulls[i] = false;
		values[i] = (Datum) 0;
		replaces[i] = false;
	}

	values[Anum_pg_package_pkgbody - 1] = CStringGetTextDatum(src);
	replaces[Anum_pg_package_pkgbody - 1] = true;

	tupdesc = RelationGetDescr(rel);
	newtuple = heap_modify_tuple(tuple, tupdesc, values, nulls, replaces);
	CatalogTupleUpdate(rel, &newtuple->t_self, newtuple);

	heap_freetuple(newtuple);
}

/*
 * remove variables defined for a given package.
 */
static void
RemovePackageVariables(Oid packageOid, char varaccess)
{
	ScanKeyData key[2];
	int			keycount;
	Relation	rel;
	TableScanDesc scan;
	HeapTuple	tuple;

	keycount = 0;
	ScanKeyInit(&key[keycount++],
				Anum_pg_variable_varnamespace,
				BTEqualStrategyNumber, F_OIDEQ,
				ObjectIdGetDatum(packageOid));

	ScanKeyInit(&key[keycount++],
				Anum_pg_variable_varaccess,
				BTEqualStrategyNumber, F_CHAREQ,
				CharGetDatum(varaccess));

	rel = table_open(VariableRelationId, AccessShareLock);
	scan = table_beginscan_catalog(rel, keycount, key);

	while ((tuple = heap_getnext(scan, ForwardScanDirection)) != NULL)
	{
		Oid			varoid = ((Form_pg_proc) GETSTRUCT(tuple))->oid;

		deleteDependencyRecordsFor(VariableRelationId, varoid, true);
		simple_heap_delete(rel, &tuple->t_self);
	}

	table_endscan(scan);
	table_close(rel, AccessShareLock);
}

/*
 * remove variables defined for a given package.
 */
static void
RemoveVariabletype(Oid packageOid, char typaccess)
{
	ScanKeyData key[3];
	int			keycount;
	Relation	rel;
	TableScanDesc scan;
	HeapTuple	tuple;

	ObjectAddress object;
	keycount = 0;
	ScanKeyInit(&key[keycount++],
				Anum_pg_type_typnamespace,
				BTEqualStrategyNumber, F_OIDEQ,
				ObjectIdGetDatum(packageOid));

	ScanKeyInit(&key[keycount++],
				Anum_pg_type_typcategory,
				BTEqualStrategyNumber, F_CHAREQ,
				CharGetDatum(TYPCATEGORY_COMPOSITE));

	ScanKeyInit(&key[keycount++],
				Anum_pg_type_typaccess,
				BTEqualStrategyNumber, F_CHAREQ,
				CharGetDatum(typaccess));

	rel = table_open(TypeRelationId, AccessShareLock);
	scan = table_beginscan_catalog(rel, keycount, key);
	object.classId = TypeRelationId;
	object.objectSubId = 0;
	while ((tuple = heap_getnext(scan, ForwardScanDirection)) != NULL)
	{
		Oid			varoid = ((Form_pg_type) GETSTRUCT(tuple))->oid;

		object.objectId = varoid;
		performDeletion(&object, DROP_RESTRICT, PERFORM_DELETION_INTERNAL);
	}

	table_endscan(scan);
	table_close(rel, AccessShareLock);
}


/*
 * get_package_oid - given a package name, look up the OID
 *
 * If missing_ok is false, throw an error if name not found.  If true, just
 * return InvalidOid.
 */
Oid
get_package_oid(List *packagename, bool missing_ok)
{
	Oid			oid = InvalidOid;
	char	   *schema;
	char	   *package;
	Oid			namespaceId;

	DeconstructQualifiedName(packagename, &schema, &package);

	if (schema)
	{
		namespaceId = get_namespace_oid(schema, false);
		oid = GetSysCacheOid2(PACKAGENAMENSP, Anum_pg_package_oid,
							  CStringGetDatum(package),
							  ObjectIdGetDatum(namespaceId));
	}
	else
	{
		ListCell   *l;
		List	   *activeSearchPath = fetch_search_path(false);

		foreach(l, activeSearchPath)
		{
			namespaceId = lfirst_oid(l);

			if (isTempNamespace(namespaceId))
				continue;		/* do not look in temp namespace */

			oid = GetSysCacheOid2(PACKAGENAMENSP, Anum_pg_package_oid,
								  CStringGetDatum(package),
								  ObjectIdGetDatum(namespaceId));
			if (OidIsValid(oid))
				break;
		}

		list_free(activeSearchPath);
	}

	if (!OidIsValid(oid) && !missing_ok)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("package \"%s\" does not exist", NameListToString(packagename))));
	return oid;
}

/*
 * get_package_name - given a package OID, look up the name
 *
 * If missing_ok is false, throw an error if name not found.  If true, just
 * return NULL.
 */
char *
get_package_name(Oid packageid, bool missing_ok)
{
	HeapTuple	tup;
	char	   *pkgname;
	Form_pg_package pkgform;

	tup = SearchSysCache1(PACKAGEOID, ObjectIdGetDatum(packageid));

	if (!HeapTupleIsValid(tup))
	{
		if (!missing_ok)
			elog(ERROR, "cache lookup failed for package %u", packageid);
		return NULL;
	}

	pkgform = (Form_pg_package) GETSTRUCT(tup);
	pkgname = pstrdup(NameStr(pkgform->pkgname));

	ReleaseSysCache(tup);

	return pkgname;
}

/*
 * get_package_src - given a package OID, return the package spec or body
 * source.
 *
 * If missing_ok is false, throw an error if package not found.  If true, just
 * return NULL.
 */
char *
get_package_src(Oid packageid, bool spec_or_body, bool missing_ok)
{
	HeapTuple	tup;
	char	   *pkgsrc = NULL;
	bool		isnull;
	Datum		datum;

	tup = SearchSysCache1(PACKAGEOID, ObjectIdGetDatum(packageid));
	if (!HeapTupleIsValid(tup))
	{
		if (!missing_ok)
			elog(ERROR, "cache lookup failed for package %u", packageid);
		return NULL;
	}

	datum = SysCacheGetAttr(PACKAGEOID,
							tup,
							(spec_or_body ?
							 Anum_pg_package_pkgspec : Anum_pg_package_pkgbody),
							&isnull);

	if (!isnull)
		pkgsrc = TextDatumGetCString(datum);

	ReleaseSysCache(tup);
	return pkgsrc;
}

static Oid
get_lang_validator(void)
{
	char	   *language = "plisql";
	HeapTuple	languageTuple;
	Form_pg_language languageStruct;
	Oid			languageOid;
	Oid			languageValidator;

	/* Look up the language and validate permissions */
	languageTuple = SearchSysCache1(LANGNAME, PointerGetDatum(language));
	if (!HeapTupleIsValid(languageTuple))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("language \"%s\" does not exist", language),
				 (extension_file_exists(language) ?
				  errhint("Use CREATE EXTENSION to load the language into the database.") : 0)));

	languageStruct = (Form_pg_language) GETSTRUCT(languageTuple);
	languageOid = languageStruct->oid;

	if (languageStruct->lanpltrusted)
	{
		/* if trusted language, need USAGE privilege */
		AclResult	aclresult;

		aclresult = pg_language_aclcheck(languageOid, GetUserId(), ACL_USAGE);
		if (aclresult != ACLCHECK_OK)
			aclcheck_error(aclresult, OBJECT_LANGUAGE,
						   NameStr(languageStruct->lanname));
	}
	else
	{
		/* if untrusted language, must be superuser */
		if (!superuser())
			aclcheck_error(ACLCHECK_NO_PRIV, OBJECT_LANGUAGE,
						   NameStr(languageStruct->lanname));
	}

	languageValidator = languageStruct->lanvalidator;
	ReleaseSysCache(languageTuple);

	return languageValidator;
}

/*
 * this function creates the constructor function for the package.
 */
static void
create_constructor(ParseState *pstate, CreatePackageStmt *stmt)
{
	CreateFunctionStmt	   *consstmt;
	char	   *pkgname;
	char	   *prosrc;

	pkgname = strVal(llast(stmt->name));
	/*
	 * create implicit initializer only if no explicit initializer was
	 * provided.
	 */
	if (stmt->isbody)
	{
		CreatePackageStmt *specStmt;
		List	   *raw_parsetree_list;
		RawStmt    *parsetree;
		char	   *spec_or_body;

		spec_or_body = get_package_src(pstate->p_pkgoid, true, false);

		/* parse the spec source to get the elems list of package spec. */
		raw_parsetree_list = raw_parser(spec_or_body, RAW_PARSE_DEFAULT);
		parsetree = linitial_node(RawStmt, raw_parsetree_list);
		specStmt = (CreatePackageStmt *) parsetree->stmt;

		prosrc = build_cons_prosrc(pstate, specStmt->elems, stmt);
		consstmt = make_cons_stmt(stmt, prosrc);
	}
	else
	{
		prosrc = build_cons_prosrc(pstate, NIL, stmt);
		consstmt = make_cons_stmt(stmt, prosrc);
	}

	consstmt->funcname = list_make2(makeString(pkgname),
						  llast(consstmt->funcname));
	consstmt->replace = true;
	CreateFunction(pstate, consstmt);
}

static char *
get_cursor_query(List *variables, DeclareCursorStmt *cur)
{
	ListCell   *lc1;
	StringInfoData buf;

	initStringInfo(&buf);
	/* deparse and add cursor query */
	if (cur->query != NULL)
	{
		/* add cursor name */
		appendStringInfo(&buf, "CURSOR %s ", cur->portalname);
		/* add cursor arguments */
		if (cur->params != NULL)
		{
			appendStringInfo(&buf, "( ");
			appendStringInfoString(&buf,
									deparse_expression((Node *) cur->params, NIL, false, false));
			appendStringInfo(&buf, " )");
		}
		appendStringInfo(&buf, " IS %s",  cur->sourcedesc);
	}
	else
	{
		foreach(lc1, variables)
		{
			Node	   *elem = (Node *) lfirst(lc1);
			if (IsA(elem, DeclareCursorStmt))
			{
				DeclareCursorStmt *cur1 = (DeclareCursorStmt *) elem;
				if(strcmp(cur->portalname,cur1->portalname)==0 && cur1->query != NULL)
				{
					appendStringInfo(&buf, "CURSOR %s ", cur1->portalname);
					if (cur1->params != NULL)
					{
						appendStringInfo(&buf, "( ");
						appendStringInfoString(&buf,
											deparse_expression((Node *) cur1->params, NIL, false, false));
						appendStringInfo(&buf, " )");
					}
					appendStringInfo(&buf, " IS %s",  cur1->sourcedesc);
					variables = foreach_delete_current(variables,lc1);
				}
			}
		}
	}
	return buf.data;
}

