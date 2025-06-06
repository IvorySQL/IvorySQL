/*-------------------------------------------------------------------------
 *
 * File:packagecmds.c
 *
 * Abstract:
 *		Definitions for the PLISQL Package
 *
 *
 * Portions Copyright (c) 2024-2025, IvorySQL Global Development Team 
 *
 * IDENTIFICATION
 *	  src/backend/commands/packagecmds.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "miscadmin.h"
#include "c.h"
#include "nodes/pg_list.h"
#include "catalog/objectaddress.h"
#include "catalog/pg_package.h"
#include "catalog/pg_package_body.h"
#include "catalog/indexing.h"
#include "catalog/catalog.h"
#include "catalog/dependency.h"
#include "catalog/objectaccess.h"
#include "catalog/pg_namespace.h"
#include "catalog/pg_language.h"
#include "catalog/namespace.h"
#include "catalog/pg_proc.h"
#include "access/htup.h"
#include "access/table.h"
#include "access/xact.h"
#include "access/htup_details.h"
#include "utils/acl.h"
#include "utils/builtins.h"
#include "utils/rel.h"
#include "utils/syscache.h"
#include "utils/lsyscache.h"
#include "utils/inval.h"
#include "utils/guc.h"
#include "utils/packagecache.h"
#include "utils/catcache.h"
#include "commands/packagecmds.h"
#include "commands/proclang.h"
#include "commands/extension.h"

static void handle_package_proper(List *proper, bool *define_invok,
							char **access_source, bool *use_collation);
static ObjectAddress CreatePackage_internal(const char *pkgname,
										Oid namespaceid, Oid pkgowner,
										const char *pkgsrc,
										bool replace, bool define_invok,
										bool editable, const char *access_source,
										bool use_collation);
static ObjectAddress CreatePackageBody_internal(const char *pkgname,
										Oid namespaceid, const char *bodysrc,
										bool replace, bool editable);
static bool package_source_nochange(HeapTuple tuple, const char *src,
									bool define_invok, const char *access_source,
									bool use_collation);
/*
 * handle package proper
 */
static void
handle_package_proper(List *proper, bool *define_invok,
							char **access_source, bool *use_collation)
{
	ListCell *lc;
	bool has_invok_proper = false;
	bool has_access_source = false;
	bool has_default_collation = false;

	if (proper == NIL)
		return;
	foreach (lc, proper)
	{
		DefElem *def = (DefElem *) lfirst(lc);

		if (nodeTag(def) == T_DefElem)
		{
			if (def->defname == NULL)
				elog(ERROR, "invalid package proper");

			if (strcmp(def->defname, "authid") == 0)
			{
				Assert(nodeTag(def->arg) == T_Boolean);

				if (has_invok_proper)
					elog(ERROR, "at most one declaration 'AUTHID' in package");
				has_invok_proper = true;

				*define_invok = boolVal(def->arg);
			}
			else if (strcmp(def->defname, "collation") == 0)
			{
				if (has_default_collation)
					elog(ERROR, "at most one declaration 'DEFAULT COLLATION' in package");
				has_default_collation = true;
				*use_collation = true;
			}
			else if (strcmp(def->defname, "accessible") == 0)
			{
				AccessibleByClause *accessproper = (AccessibleByClause *) def->arg;

				if (has_access_source)
					elog(ERROR, "at most one declaration 'ACCESSIBLE BY' in package");
				has_access_source = true;
				*access_source = nodeToString(accessproper->accessors);
			}
		}
		else
			elog(ERROR, "unrecognized node type: %d",
					 (int) nodeTag(def));
	}
	return;
}

/*
 * insert or update pg_package
 */
static ObjectAddress
CreatePackage_internal(const char *pkgname,
					Oid namespaceId, Oid pkgowner,
					const char *pkgsrc,
					bool replace, bool define_invok,
					bool editable, const char *access_source,
					bool use_collation)
{
	Relation	rel;
	HeapTuple	tup;
	HeapTuple	oldtup;
	TupleDesc	tupDesc;
	bool		nulls[Natts_pg_package];
	Datum		values[Natts_pg_package];
	bool		replaces[Natts_pg_package];
	NameData	pg_pkgname;
	int			i;
	bool		is_update = false;
	Acl		   *pkgacl = NULL;
	ObjectAddress myself,
				referenced;
	Oid			packageoid;
	ObjectAddresses *addrs;

	/*
	 * All seems OK; prepare the data to be inserted into ora_package.
	 */

	for (i = 0; i < Natts_pg_package; ++i)
	{
		nulls[i] = false;
		values[i] = (Datum) 0;
		replaces[i] = false;
	}

	namestrcpy(&pg_pkgname, pkgname);
	values[Anum_pg_package_pkgname - 1] = NameGetDatum(&pg_pkgname);
	values[Anum_pg_package_pkgnamespace - 1] = ObjectIdGetDatum(namespaceId);
	values[Anum_pg_package_pkgowner - 1] = ObjectIdGetDatum(pkgowner);
	values[Anum_pg_package_define_invok - 1] = CharGetDatum(define_invok);
	values[Anum_pg_package_editable - 1] = BoolGetDatum(editable);
	values[Anum_pg_package_use_collation - 1] = BoolGetDatum(use_collation);
	values[Anum_pg_package_pkgsrc - 1] = CStringGetTextDatum(pkgsrc);
	if (access_source != NULL)
		values[Anum_pg_package_accesssource - 1] = CStringGetTextDatum(access_source);
	else
		nulls[Anum_pg_package_accesssource - 1] = true;

	rel = table_open(PackageRelationId, RowExclusiveLock);
	tupDesc = RelationGetDescr(rel);
	/* Check for pre-existing definition */
	oldtup = SearchSysCache2(PKGNAMEARGSNSP,
							 PointerGetDatum(pkgname),
							 ObjectIdGetDatum(namespaceId));

	if (HeapTupleIsValid(oldtup))
	{
		Form_pg_package oldpkg = (Form_pg_package) GETSTRUCT(oldtup);

		if (!replace)
			elog(ERROR, "package \"%s\" already exists", pkgname);

		/* doesn't allow to replace editable if it has define */
		if (editable != oldpkg->editable)
			elog(ERROR, "A CREATE OR REPLACE command may not change the EDITIONABLE "
						"property of an existing object");

		if (!pg_package_ownercheck(oldpkg->oid, pkgowner))
			aclcheck_error(ACLCHECK_NOT_OWNER, OBJECT_PACKAGE,
						   pkgname);
		/* if no change, we doesn't update the pg_package */
		if (package_source_nochange(oldtup, pkgsrc, define_invok,
								access_source, use_collation))
		{
			myself.classId = PackageRelationId;
			myself.objectId = oldpkg->oid;
			myself.objectSubId = 0;
			ReleaseSysCache(oldtup);
			table_close(rel, RowExclusiveLock);

			return myself;
		}
		/*
		 * Do not change existing ownership or permissions, either.  Note
		 * dependency-update code below has to agree with this decision.
		 */
		replaces[Anum_pg_package_define_invok - 1] = true;
		replaces[Anum_pg_package_use_collation - 1] = true;
		replaces[Anum_pg_package_pkgsrc - 1] = true;
		replaces[Anum_pg_package_accesssource - 1] = true;

		/* Okay, do it... */
		tup = heap_modify_tuple(oldtup, tupDesc, values, nulls, replaces);
		CatalogTupleUpdate(rel, &tup->t_self, tup);

		ReleaseSysCache(oldtup);
		is_update = true;
	}
	else
	{
		/* Creating a new package */
		Oid newOid;

		/* First, get default permissions and set up pkgacl */
		pkgacl = get_user_default_acl(OBJECT_PACKAGE, pkgowner,
									  namespaceId);
		if (pkgacl != NULL)
			values[Anum_pg_package_pkgacl - 1] = PointerGetDatum(pkgacl);
		else
			nulls[Anum_pg_package_pkgacl - 1] = true;

		newOid = GetNewOidWithIndex(rel, PackageObjectIndexId,
									Anum_pg_package_oid);
		values[Anum_pg_package_oid - 1] = ObjectIdGetDatum(newOid);

		tup = heap_form_tuple(tupDesc, values, nulls);
		CatalogTupleInsert(rel, tup);
		is_update = false;
	}

	packageoid = ((Form_pg_package) GETSTRUCT(tup))->oid;

	/*
	 * Create dependencies for the new package.  If we are updating an
	 * existing package, first delete any existing pg_depend entries.
	 * (However, since we are not changing ownership or permissions, the
	 * shared dependencies do *not* need to change, and we leave them alone.)
	 */
	if (is_update)
		deleteDependencyRecordsFor(PackageRelationId, packageoid, true);

	addrs = new_object_addresses();
	ObjectAddressSet(myself, PackageRelationId, packageoid);

	/* dependency on namespace */
	ObjectAddressSet(referenced, NamespaceRelationId, namespaceId);
	add_exact_object_address(&referenced, addrs);

	/* dependency on implementation language */
	ObjectAddressSet(referenced, LanguageRelationId,
		get_language_oid("plisql", false));
	add_exact_object_address(&referenced, addrs);

	record_object_address_dependencies(&myself, addrs,
			DEPENDENCY_NORMAL);
	free_object_addresses(addrs);

	/* dependency on owner */
	if (!is_update)
		recordDependencyOnOwner(PackageRelationId,
			packageoid, pkgowner);

	/* dependency on any roles mentioned in ACL */
	if (!is_update)
		recordDependencyOnNewAcl(PackageRelationId, packageoid, 0,
								 pkgowner, pkgacl);

	/* dependency on extension */
	recordDependencyOnCurrentExtension(&myself, is_update);

	heap_freetuple(tup);

	/* Post creation hook for new package */
	InvokeObjectPostCreateHook(PackageRelationId, packageoid, 0);

	/* compile a package */
	CommandCounterIncrement();

	/*
	 * pg_dump doesn't know the order of packages
	 * so when we restore package, we doesn't check its
	 * body and allow it to catalog
	 */
	if (check_function_bodies)
		ValidatroPackage(packageoid, false);

	table_close(rel, RowExclusiveLock);

	return myself;
}

/*
 * insert or update sys_package_body
 */
static ObjectAddress
CreatePackageBody_internal(const char *pkgname,
									Oid namespaceid, const char *bodysrc,
									bool replace, bool editable)
{
	Relation	rel;
	HeapTuple	tup;
	Relation	pkgrel;
	HeapTuple	oldtup;
	HeapTuple	pkgtup;
	TupleDesc	tupDesc;
	bool		nulls[Natts_pg_package_body];
	Datum		values[Natts_pg_package_body];
	bool		replaces[Natts_pg_package_body];
	Oid			pkgOid;
	int			i;
	bool		is_update = false;
	ObjectAddress myself,
				referenced;
	Oid			bodyid;
	Form_pg_package  pkgForm;
	Form_pg_package_body pkgbodyForm;
	char		pkg_editable;

	/*
	 * does package exist
	 */
	pkgrel = table_open(PackageRelationId, AccessShareLock);
	pkgtup = SearchSysCache2(PKGNAMEARGSNSP,
							 PointerGetDatum(pkgname),
							 ObjectIdGetDatum(namespaceid));
	if (!HeapTupleIsValid(pkgtup))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("package \"%s\" does not exist", pkgname)));

	pkgForm = (Form_pg_package) GETSTRUCT(pkgtup);
	pkgOid = ((Form_pg_package) GETSTRUCT(pkgtup))->oid;
	pkg_editable = pkgForm->editable;
	ReleaseSysCache(pkgtup);

	/* body editable must match its package */
	if (pkg_editable != editable)
		elog(ERROR, "The EDITIONABLE property of a TYPE or PACKAGE specification and its"
					" body must match");

	/*
	 * All seems OK; prepare the data to be inserted into sys_package_body.
	 */

	for (i = 0; i < Natts_pg_package_body; ++i)
	{
		nulls[i] = false;
		values[i] = (Datum) 0;
		replaces[i] = true;
	}

	values[Anum_pg_package_body_pkgoid - 1] = ObjectIdGetDatum(pkgOid);
	values[Anum_pg_package_body_bodysrc - 1] = CStringGetTextDatum(bodysrc);

	rel = table_open(PackageBodyRelationId, RowExclusiveLock);
	tupDesc = RelationGetDescr(rel);
	/* Check for pre-existing definition */
	oldtup = SearchSysCache1(PKGBODYPKGOID,
							 ObjectIdGetDatum(pkgOid));

	if (HeapTupleIsValid(oldtup))
	{
		Datum bodydatum;
		bool isnull;
		char *sbodysrc;

		if (!replace)
			elog(ERROR, "package \"%s\" body already exists", pkgname);

		if (!pg_package_ownercheck(pkgOid, GetUserId()))
			aclcheck_error(ACLCHECK_NOT_OWNER, OBJECT_PACKAGE_BODY,
						   pkgname);

		bodydatum = SysCacheGetAttr(PKGBODYOID, oldtup,
								  Anum_pg_package_body_bodysrc, &isnull);
		Assert(!isnull);

		sbodysrc = TextDatumGetCString(bodydatum);

		pkgbodyForm = (Form_pg_package_body) GETSTRUCT(oldtup);

		/* src doesn't change, we don't update catalog */
		if (strcmp(sbodysrc, bodysrc) == 0)
		{
			pfree(sbodysrc);
			myself.classId = PackageBodyRelationId;
			myself.objectId = pkgbodyForm->oid;
			myself.objectSubId = 0;
			ReleaseSysCache(oldtup);
			table_close(rel, RowExclusiveLock);
			table_close(pkgrel, AccessShareLock);

			return myself;
		}
		pfree(sbodysrc);

		/* Okay, do it... */
		replaces[Anum_pg_package_body_pkgoid - 1] = false;
		replaces[Anum_pg_package_body_oid - 1] = false;
		tup = heap_modify_tuple(oldtup, tupDesc, values, nulls, replaces);
		CatalogTupleUpdate(rel, &tup->t_self, tup);

		ReleaseSysCache(oldtup);
		is_update = true;
	}
	else
	{
		/* Creating a new package body */
		Oid newOid;

		newOid = GetNewOidWithIndex(rel, PackageBodyObjectIndexId,
									Anum_pg_package_body_oid);
		values[Anum_pg_package_body_oid - 1] = ObjectIdGetDatum(newOid);

		tup = heap_form_tuple(tupDesc, values, nulls);
		CatalogTupleInsert(rel, tup);
		is_update = false;
	}

	bodyid = ((Form_pg_package_body) GETSTRUCT(tup))->oid;

	myself.classId = PackageBodyRelationId;
	myself.objectId = bodyid;
	myself.objectSubId = 0;

	/*
	 * Create dependencies for the new package body.  If we are updating an
	 * existing package, first delete any existing pg_depend entries.
	 * (However, since we are not changing ownership or permissions, the
	 * shared dependencies do *not* need to change, and we leave them alone.)
	 */
	if (is_update)
		deleteDependencyRecordsFor(PackageBodyRelationId, bodyid, true);

	/* record dependency */
	/* dependency on package */
	referenced.classId = PackageRelationId;
	referenced.objectId = pkgOid;
	referenced.objectSubId = 0;
	recordDependencyOn(&myself, &referenced, DEPENDENCY_AUTO);

	/* dependency on extension */
	recordDependencyOnCurrentExtension(&myself, is_update);

	heap_freetuple(tup);

	/* Post creation hook for new package body */
	InvokeObjectPostCreateHook(PackageBodyRelationId, bodyid, 0);

	/* compile a package */
	CommandCounterIncrement();

	/*
	 * pg_dump doesn't know the order of packages
	 * so when we restore package, we doen't check its
	 * body and allow it to catalog
	 */
	if (check_function_bodies)
		ValidatroPackage(bodyid, true);

	table_close(rel, RowExclusiveLock);
	table_close(pkgrel, AccessShareLock);

	return myself;
}

/*
 * check package'properties and src is changed
 */
static bool
package_source_nochange(HeapTuple tuple, const char *src,
								bool define_invok, const char *access_source,
								bool use_collation)
{
	char *ssrc;
	char *saccess_source;
	bool isnull;
	Form_pg_package pkgStruct = (Form_pg_package) GETSTRUCT(tuple);
	Datum		pkgdatum;

	Assert(HeapTupleIsValid(tuple));

	if (pkgStruct->define_invok != define_invok)
		return false;
	if (pkgStruct->use_collation != use_collation)
		return false;

	pkgdatum = SysCacheGetAttr(PKGOID, tuple,
								  Anum_pg_package_pkgsrc, &isnull);
	if (isnull)
		elog(ERROR, "null pkgsrc");

	ssrc = TextDatumGetCString(pkgdatum);
	if (strcmp(ssrc, src) != 0)
	{
		pfree(ssrc);
		return false;
	}

	pfree(ssrc);
	pkgdatum = SysCacheGetAttr(PKGOID, tuple,
								Anum_pg_package_accesssource, &isnull);
	if (isnull)
	{
		if (access_source != NULL)
			return false;
		else if (access_source == NULL)
			return true;
	}
	else if (access_source == NULL)
		return false;

	saccess_source = TextDatumGetCString(pkgdatum);
	if (strcmp(saccess_source, access_source) != 0)
	{
		pfree(saccess_source);
		return false;
	}
	pfree(saccess_source);

	return true;

}


/*
 * create a package
 */
ObjectAddress
CreatePackage(CreatePackageStmt *stmt)
{
	char	   *pkgname;
	Oid			namespaceId;
	AclResult	aclresult;
	HeapTuple	languageTuple;
	char		*language = "plisql";
	Oid			languageOid;
	Form_pg_language languageStruct;
	bool		define_invok = true;
	bool		use_collation = false;
	char		*access_source = NULL;
	Oid			ownerId;

	ownerId = GetUserId();

	/* Convert list of names to a name and namespace */
	namespaceId = QualifiedNameGetCreationNamespace(stmt->pkgname,
													&pkgname);

	/*
	 * forbide some special name
	 */
	check_package_name(namespaceId, pkgname, NULL);

	/* Check we have creation rights in target namespace */
	aclresult = object_aclcheck(NamespaceRelationId, namespaceId, GetUserId(), ACL_CREATE);
	if (aclresult != ACLCHECK_OK)
		aclcheck_error(aclresult, OBJECT_SCHEMA,
					   get_namespace_name(namespaceId));

	/* package depends on plsql language */
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
		AclResult	aclresult_1;

		aclresult_1 = object_aclcheck(LanguageRelationId, languageOid, GetUserId(), ACL_USAGE);
		if (aclresult_1 != ACLCHECK_OK)
			aclcheck_error(aclresult_1, OBJECT_LANGUAGE,
						   NameStr(languageStruct->lanname));
	}
	else
	{
		/* if untrusted language, must be superuser */
		if (!superuser())
			aclcheck_error(ACLCHECK_NO_PRIV, OBJECT_LANGUAGE,
						   NameStr(languageStruct->lanname));
	}

	ReleaseSysCache(languageTuple);

	/* handle package proper */
	handle_package_proper(stmt->propers, &define_invok, &access_source, &use_collation);

	return CreatePackage_internal(pkgname,
								namespaceId,
								ownerId,
								stmt->pkgsrc,
								stmt->replace,
								define_invok,
								stmt->editable,
								access_source,
								use_collation);
}

/*
 * create a package body
 */
ObjectAddress
CreatePackageBody(CreatePackageBodyStmt *stmt)
{
	char	   *pkgname;
	Oid			namespaceId;
	AclResult	aclresult;

	/* Convert list of names to a name and namespace */
	namespaceId = QualifiedNameGetCreationNamespace(stmt->pkgname,
													&pkgname);

	/* Check we have creation rights in target namespace */
	aclresult = object_aclcheck(NamespaceRelationId, namespaceId, GetUserId(), ACL_CREATE);
	if (aclresult != ACLCHECK_OK)
		aclcheck_error(aclresult, OBJECT_SCHEMA,
					get_namespace_name(namespaceId));

	return CreatePackageBody_internal(pkgname,
									namespaceId,
									stmt->bodysrc,
									stmt->replace,
									stmt->editable);
}

/*
 * alter a package
 */
ObjectAddress
AlterPackage(AlterPackageStmt *stmt)
{
	Oid pkgoid;
	HeapTuple tup;
	Relation rel;
	ObjectAddress address;

	rel = table_open(PackageRelationId, RowExclusiveLock);
	pkgoid = LookupPackageByNames(stmt->pkgname, false);
	tup = SearchSysCacheCopy1(PKGOID, ObjectIdGetDatum(pkgoid));
	if (!HeapTupleIsValid(tup)) /* should not happen */
		elog(ERROR, "cache lookup failed for package %u", pkgoid);

	/*
	 * Permission check: must own package or superuser
	 */
	if (!pg_package_ownercheck(pkgoid, GetUserId()))
		aclcheck_error(ACLCHECK_NOT_OWNER, OBJECT_PACKAGE,
					   NameListToString(stmt->pkgname));

	switch (stmt->alter_flag)
	{
		case alter_editable_flag:
			{
				Datum		repl_val[Natts_pg_package];
				bool		repl_null[Natts_pg_package];
				bool		repl_repl[Natts_pg_package];

				/* update the tuple */
				memset(repl_repl, false, sizeof(repl_repl));
				repl_repl[Anum_pg_package_editable - 1] = true;
				repl_val[Anum_pg_package_editable - 1] = CharGetDatum(stmt->editable);
				repl_null[Anum_pg_package_editable - 1] = false;
				tup = heap_modify_tuple(tup, RelationGetDescr(rel),
								repl_val, repl_null, repl_repl);
				CatalogTupleUpdate(rel, &tup->t_self, tup);
				InvokeObjectPostAlterHook(PackageRelationId, pkgoid, 0);
			}
			break;
		case alter_compile_all:
		case alter_compile_package:
		case alter_compile_specification:
			{
				Oid bodyid;

				/* like create or replace package */
				CacheInvalidateHeapTuple(rel, tup, NULL);
				CommandCounterIncrement();
				/* free package cache */
				FreePackageCache(&pkgoid);
				/* if has body, we cimpile include body */
				bodyid = get_package_bodyid(pkgoid, true);
				if (OidIsValid(bodyid))
					ValidatroPackage(bodyid, true);
				else
					ValidatroPackage(pkgoid, false);
			}
			break;
		case alter_compile_body:
			/* like create or replace package body */
			{
				HeapTuple bodytup;
				Relation bodyrel;
				Oid bodyid;

				bodyrel = table_open(PackageBodyRelationId, RowExclusiveLock);
				bodytup = SearchSysCacheCopy1(PKGBODYPKGOID, ObjectIdGetDatum(pkgoid));
				if (!HeapTupleIsValid(bodytup))
					elog(ERROR, "cache lookup failed for package body %u", pkgoid);

				CacheInvalidateHeapTuple(bodyrel, bodytup, NULL);
				CommandCounterIncrement();
				/* free package cache */
				FreePackageCache(&pkgoid);
				bodyid = ((Form_pg_package_body) GETSTRUCT(bodytup))->oid;
				ValidatroPackage(bodyid, true);

				heap_freetuple(bodytup);
				table_close(bodyrel, NoLock);
			}
			break;
		case alter_compile_parameter:
			/* do nothing, only support grammer */
			break;
		default:
			elog(ERROR, "doesn't recognise alter flag:%d", stmt->alter_flag);
			break;
	}

	ObjectAddressSet(address, PackageRelationId, pkgoid);

	heap_freetuple(tup);
	table_close(rel, NoLock);

	return address;
}


/*
 * look package by namelist
 */
Oid
LookupPackageByNames(List *pkgname, bool missing_ok)
{
	char *schemaname;
	char *p_name;
	Oid namespaceId;
	Oid pkgOid;

	/* deconstruct the name list */
	DeconstructQualifiedName(pkgname, &schemaname, &p_name);

	if (schemaname != NULL)
	{
		namespaceId = LookupExplicitNamespace(schemaname, missing_ok);
		if (!OidIsValid(namespaceId))
			return InvalidOid;

		pkgOid = get_package_pkgid(p_name, namespaceId);
	}
	else
		pkgOid =  PkgnameGetPkgid(p_name);

	if (!OidIsValid(pkgOid) && !missing_ok)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("package \"%s\" does not exist", p_name)));

	return pkgOid;

}

/*
 * look package body by package'name
 */
Oid
LookupPackageBodyByNames(List *pkgname, bool missing_ok)
{
	Oid pkgOid;
	Oid bodyOid;
	char *schemaname;
	char *p_name;

	pkgOid = LookupPackageByNames(pkgname, missing_ok);

	if (!OidIsValid(pkgOid))
		return InvalidOid;

	DeconstructQualifiedName(pkgname, &schemaname, &p_name);

	bodyOid = GetSysCacheOid1(PKGBODYPKGOID, Anum_pg_package_body_oid,
						   ObjectIdGetDatum(pkgOid));

	if (!OidIsValid(bodyOid) && !missing_ok)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("package \"%s\" does not exist", p_name)));

	return bodyOid;
}

/*
 * like get_relname_relid
 */

Oid
get_package_pkgid(const char *pkgname, Oid pkgnamespace)
{
	return GetSysCacheOid2(PKGNAMEARGSNSP, Anum_pg_package_oid,
						   PointerGetDatum(pkgname),
						   ObjectIdGetDatum(pkgnamespace));
}

/*
 * like pg_type_ownercheck
 * check package owner
 */
bool
pg_package_ownercheck(Oid pkgid, Oid roleid)
{
	HeapTuple	tuple;
	Oid			ownerId;

	/* Superusers bypass all permission checking. */
	if (superuser_arg(roleid))
		return true;

	tuple = SearchSysCache1(PKGOID, ObjectIdGetDatum(pkgid));
	if (!HeapTupleIsValid(tuple))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("package with OID %u does not exist", pkgid)));

	ownerId = ((Form_pg_package) GETSTRUCT(tuple))->pkgowner;

	ReleaseSysCache(tuple);

	return has_privs_of_role(roleid, ownerId);
}


/*
 * check package body owner
 */
bool
pg_packagebody_ownercheck(Oid bodyid, Oid roleid)
{
	Oid pkgOid;
	HeapTuple tuple;

	if (superuser_arg(roleid))
		return true;

	tuple = SearchSysCache1(PKGBODYOID, ObjectIdGetDatum(bodyid));
	if (!HeapTupleIsValid(tuple))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("package body with OID %u does not exist", bodyid)));

	pkgOid = ((Form_pg_package_body) GETSTRUCT(tuple))->pkgoid;

	ReleaseSysCache(tuple);

	return pg_package_ownercheck(pkgOid, roleid);
}


/*
 * drop a package tuple
 */
void
DropPackageById(Oid pkgid)
{
	Relation	pkgrel;
	HeapTuple	tup;

	pkgrel = table_open(PackageRelationId, RowExclusiveLock);

	tup = SearchSysCache1(PKGOID, ObjectIdGetDatum(pkgid));
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for package %u", pkgid);

	CatalogTupleDelete(pkgrel, &tup->t_self);

	ReleaseSysCache(tup);

	/*
	 * we should remove package cache here, because syscache invalid
	 * function only set package cache invalid and doesn't drop it
	 * we do this, so shat only release memory
	 */
	FreePackageCache(&pkgid);

	table_close(pkgrel, RowExclusiveLock);
}

/*
 * drop a package body tuple
 */
void
DropPackageBodyById(Oid bodyid)
{
	Relation	bodyrel;
	HeapTuple	tup;
	PackageCacheKey pkey;
	Form_pg_package_body form_body;

	bodyrel = table_open(PackageBodyRelationId, RowExclusiveLock);

	tup = SearchSysCache1(PKGBODYOID, ObjectIdGetDatum(bodyid));
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for package body %u", bodyid);

	form_body = (Form_pg_package_body) GETSTRUCT(tup);
	pkey = form_body->pkgoid;

	CatalogTupleDelete(bodyrel, &tup->t_self);

	ReleaseSysCache(tup);

	/*
	 * we should remove package cache here, because syscache invalid
	 * function only set package cache invalid and doesn't drop it
	 * we do this, so shat when we drop a package body, its package
	 * should reinit.
	 */
	FreePackageCache(&pkey);

	table_close(bodyrel, RowExclusiveLock);
}

/*
 * get package schema and name by pkgoid
 * Returns a palloc'd copy of the string, or NULL if no such package.
 *
 */
void
get_package_nameinfo(Oid pkgid, char **pkgname, char **schema)
{
	HeapTuple tup;
	Form_pg_package pkg_Form;

	if (pkgname)
		*pkgname = NULL;
	if (schema)
		*schema = NULL;

	if (!OidIsValid(pkgid))
		elog(ERROR, "invalid package oid %u", pkgid);

	tup = SearchSysCache1(PKGOID, ObjectIdGetDatum(pkgid));
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for package %u", pkgid);

	pkg_Form = (Form_pg_package) GETSTRUCT(tup);

	if (schema)
		*schema = get_namespace_name(pkg_Form->pkgnamespace);
	if (pkgname)
		*pkgname = pstrdup(NameStr(pkg_Form->pkgname));
	ReleaseSysCache(tup);

	return;
}

/*
 * get package name
 */
char*
get_package_name(Oid pkgid)
{
	HeapTuple tup;
	Form_pg_package pkg_Form;
	char *pkgname;

	if (!OidIsValid(pkgid))
		elog(ERROR, "invalid package oid %u", pkgid);

	tup = SearchSysCache1(PKGOID, ObjectIdGetDatum(pkgid));
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for package %u", pkgid);

	pkg_Form = (Form_pg_package) GETSTRUCT(tup);

	pkgname = pstrdup(NameStr(pkg_Form->pkgname));
	ReleaseSysCache(tup);

	return pkgname;
}


/*
 * get package schema and name by bodyoid
 */
void
get_package_nameinfo_bybodyid(Oid bodyid, char **pkgname, char **schema)
{
	HeapTuple tup;
	Form_pg_package_body body_Form;
	Oid	pkgid;

	if (pkgname)
		*pkgname = NULL;
	if (schema)
		*schema = NULL;

	if (!OidIsValid(bodyid))
		elog(ERROR, "invalid package body oid %u", bodyid);

	tup = SearchSysCache1(PKGBODYOID, ObjectIdGetDatum(bodyid));
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for package body %u", bodyid);

	body_Form = (Form_pg_package_body) GETSTRUCT(tup);
	pkgid = body_Form->pkgoid;
	ReleaseSysCache(tup);

	get_package_nameinfo(pkgid, pkgname, schema);
	return;
}

/*
 * get package'namespace oid
 */
Oid
get_package_namespace(Oid pkgid)
{
	HeapTuple tup;
	Form_pg_package pkg_Form;
	Oid	namespaceId;

	if (!OidIsValid(pkgid))
		elog(ERROR, "invalid package oid %u", pkgid);

	tup = SearchSysCache1(PKGOID, ObjectIdGetDatum(pkgid));
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for package %u", pkgid);

	pkg_Form = (Form_pg_package) GETSTRUCT(tup);
	namespaceId = pkg_Form->pkgnamespace;
	ReleaseSysCache(tup);

	return namespaceId;
}


/*
 * get package body oid by its package'oid
 */
Oid
get_package_bodyid(Oid pkgoid, bool miss_ok)
{
	HeapTuple tup;
	Oid bodyid;

	if (!OidIsValid(pkgoid))
		elog(ERROR, "invalid package oid %u", pkgoid);

	tup = SearchSysCache1(PKGBODYPKGOID, ObjectIdGetDatum(pkgoid));
	if (!HeapTupleIsValid(tup))
	{
		if (miss_ok)
			return InvalidOid;
		elog(ERROR, "cache lookup package body failed for package  %u", pkgoid);
	}
	bodyid = ((Form_pg_package_body) GETSTRUCT(tup))->oid;
	ReleaseSysCache(tup);

	return bodyid;
}

/*
 * forbide some special names
 * we only allow standard name in sys at current
 */
void
check_package_name(Oid nspname, char *newpkgname, char *oldpkgname)
{
	if (nspname != PG_SYS_NAMESPACE &&
		strcmp(newpkgname, "standard") == 0)
		elog(ERROR, "this name is currently reserved for use by user SYS");
	if (oldpkgname != NULL &&
		strcmp(oldpkgname, "standard") == 0)
		elog(ERROR, "this name is currently reserved for use by user SYS");
}

/*
 * Subroutine for ALTER PACKAGE SET SCHEMA/RENAME
 *
 * Is there a package with the given name and signature already in the given
 * namespace?  If so, raise an appropriate error message.
 */
void
IsTherePackageInNamespace(char *new_name, Oid namespace)

{
	/* check for duplicate name (more friendly than unique-index failure) */
	if (SearchSysCacheExists2(PKGNAMEARGSNSP,
							  PointerGetDatum(new_name),
							  ObjectIdGetDatum(namespace)))
		ereport(ERROR,
				(errcode(ERRCODE_DUPLICATE_FUNCTION),
				 errmsg("package %s already exists in schema \"%s\"",
						new_name,
						get_namespace_name(namespace))));
}


/*
 * accord argtypenames to find functup
 * if return not null, should use ReleaseSysCache
 * to release
 */
HeapTuple
get_functup_bytypenames(Oid namespaceid,
						const char *func_name, Datum typenames,
						oidvector *parametertypes,
						Datum allParametertypes)
{
	CatCList   *catlist;
	int 		i;
	int 		n_match = 0;
	Oid			func_oid = InvalidOid;
	Oid			*all_param_proargtypes = NULL;
	int			n_all_param_types;
	int			n_param_typenames;
	Datum		*p_elems;
	char		**param_argtypenames = NULL;
	HeapTuple	tuple;

	Assert(typenames != PointerGetDatum(NULL));

	deconstruct_array(DatumGetArrayTypeP(typenames),
							TEXTOID, -1, false, 'i',
							&p_elems, NULL, &n_param_typenames);
	param_argtypenames = (char **) palloc(sizeof(char *) * n_param_typenames);
	for (i = 0; i < n_param_typenames; i++)
		param_argtypenames[i] = TextDatumGetCString(p_elems[i]);

	if (allParametertypes != PointerGetDatum(NULL))
	{
		ArrayType  *arr = DatumGetArrayTypeP(allParametertypes);

		n_all_param_types = ARR_DIMS(arr)[0];
		if (ARR_NDIM(arr) != 1 ||
			n_all_param_types < 0 ||
			ARR_HASNULL(arr) ||
			ARR_ELEMTYPE(arr) != OIDOID)
			elog(ERROR, "proallargtypes is not a 1-D Oid array or it contains nulls");
		all_param_proargtypes = (Oid *) ARR_DATA_PTR(arr);
	}
	else
		n_all_param_types = 0;

	/* Search syscache by name only */
	catlist = SearchSysCacheList1(PROCNAMEARGSNSP, CStringGetDatum(func_name));

	for (i = 0; i < catlist->n_members; i++)
	{
		HeapTuple	proctup = &catlist->members[i]->tuple;
		Form_pg_proc procform = (Form_pg_proc) GETSTRUCT(proctup);
		Oid 	   *proargtypes = procform->proargtypes.values;
		int 		pronargs = procform->pronargs;
		Datum		argtypedatum;
		char		**argtypenames = NULL;
		Datum		proallargtypes;
		bool		isNull;
		Oid 	   *all_proargtypes = NULL;
		int			all_pronargs;
		Datum	   *elems;
		int			n_all_nelems;

		if (procform->pronamespace != namespaceid)
			continue;

		/* args not match */
		if (pronargs != parametertypes->dim1)
			continue;

		argtypedatum = SysCacheGetAttr(PROCNAMEARGSNSP, proctup,
									Anum_pg_proc_protypenames,
									&isNull);
		if (isNull)
			continue;
		else
		{
			deconstruct_array(DatumGetArrayTypeP(argtypedatum),
							TEXTOID, -1, false, 'i',
							&elems, NULL, &n_all_nelems);

			/* all typenames not match */
			if (n_all_nelems != n_param_typenames)
				continue;
			argtypenames = (char **) palloc(sizeof(char *) * n_all_nelems);
			for (i = 0; i < n_all_nelems; i++)
				argtypenames[i] = TextDatumGetCString(elems[i]);
		}


		proallargtypes = SysCacheGetAttr(PROCNAMEARGSNSP, proctup,
										 Anum_pg_proc_proallargtypes,
										 &isNull);
		if (!isNull)
		{
			ArrayType  *arr = DatumGetArrayTypeP(proallargtypes);

			all_pronargs = ARR_DIMS(arr)[0];
			if (ARR_NDIM(arr) != 1 ||
				all_pronargs < 0 ||
				ARR_HASNULL(arr) ||
				ARR_ELEMTYPE(arr) != OIDOID)
				elog(ERROR, "proallargtypes is not a 1-D Oid array or it contains nulls");
			Assert(all_pronargs >= procform->pronargs);
			all_proargtypes = (Oid *) ARR_DATA_PTR(arr);
		}
		else
			all_pronargs = 0;

		if (all_pronargs != n_all_param_types)
			continue;

		/* check typnames match */
		for (i = 0; i < n_param_typenames; i++)
		{
			if (strcmp(argtypenames[i], param_argtypenames[i]) != 0)
				break;

			/* normal argtype should match */
			if (strcmp(argtypenames[i], "") == 0)
			{
				if (n_all_param_types != 0 &&
					all_proargtypes[i] != all_param_proargtypes[i])
					break;
				else if (proargtypes[i] != parametertypes->values[i])
					break;
			}
		}
		if (i != n_param_typenames)
			continue;
		n_match++;
		func_oid = procform->oid;
	}
	ReleaseSysCacheList(catlist);

	/* more than one match raise error ? */
	if (n_match != 1)
		return NULL;
	tuple = SearchSysCache1(PROCOID, ObjectIdGetDatum(func_oid));
	Assert(HeapTupleIsValid(tuple));

	return tuple;
}

