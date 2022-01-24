/*-------------------------------------------------------------------------
 *
 * pg_package.c
 *		package
 *
 * Copyright (c) 2021-2022, IvorySQL
 *
 * IDENTIFICATION
 *		src/backend/catalog/pg_package.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"
#include "access/htup_details.h"
#include "access/table.h"
#include "catalog/catalog.h"
#include "catalog/dependency.h"
#include "catalog/indexing.h"
#include "catalog/objectaccess.h"
#include "catalog/pg_namespace.h"
#include "catalog/pg_package.h"
#include "utils/syscache.h"
#include "utils/builtins.h"
#include "utils/rel.h"

Oid
PackageCreate(const char *pkgname,
			  Oid pkgnamespace,
			  bool replace,
			  bool isbody,
			  const char *pkgspec,
			  const char *pkgbody,
			  Oid pkgowner,
			  bool pkgsecdef)
{
	bool		nulls[Natts_pg_package];
	Datum		values[Natts_pg_package];
	bool		replaces[Natts_pg_package];
	int			i;
	Relation	rel;
	Oid			packageoid;
	NameData	packname;
	TupleDesc	tupdesc;
	HeapTuple	tup,
				oldtup;
	Acl		   *pkgacl = NULL;
	bool		is_update;
	ObjectAddress myself,
				referenced;


	for (i = 0; i < Natts_pg_package; ++i)
	{
		nulls[i] = false;
		values[i] = (Datum) 0;
		replaces[i] = false;
	}

	namestrcpy(&packname, pkgname);
	values[Anum_pg_package_pkgname - 1] = NameGetDatum(&packname);
	values[Anum_pg_package_pkgnamespace - 1] = ObjectIdGetDatum(pkgnamespace);
	values[Anum_pg_package_pkgowner - 1] = ObjectIdGetDatum(pkgowner);
	values[Anum_pg_package_pkgsecdef - 1] = BoolGetDatum(pkgsecdef);

	if (!isbody)
	{
		values[Anum_pg_package_pkgspec - 1] = CStringGetTextDatum(pkgspec);
		nulls[Anum_pg_package_pkgbody - 1] = true;
	}
	else
	{
		values[Anum_pg_package_pkgbody - 1] = CStringGetTextDatum(pkgbody);
		replaces[Anum_pg_package_pkgbody - 1] = true;
	}
	nulls[Anum_pg_package_pkgaccessor - 1] = true;

	rel = table_open(PackageRelationId, RowExclusiveLock);
	tupdesc = RelationGetDescr(rel);
	oldtup = SearchSysCache2(PACKAGENAMENSP,
							 PointerGetDatum(pkgname),
							 ObjectIdGetDatum(pkgnamespace));
	if (HeapTupleIsValid(oldtup))
	{
		/* there is one, okay replace it */
		Form_pg_package oldpkg = (Form_pg_package) GETSTRUCT(oldtup);

		if (isbody)
		{
			bool		isnull;

			/*
			 * See if only package spec exist then we create the BODY, even
			 * "OR REPLACE" is not mentioned. However if a package body is
			 * already available, then make sure we have "OR REPLACE" clause
			 * present in query.
			 */
			SysCacheGetAttr(PACKAGENAMENSP, oldtup, Anum_pg_package_pkgbody,
							&isnull);
			if (!isnull && !replace)
			{
				ereport(ERROR,
						(errcode(ERRCODE_DUPLICATE_FUNCTION),
						 errmsg("package \"%s\" body already exists",
								pkgname)));
			}

			replaces[Anum_pg_package_pkgbody - 1] = true;
		}
		else
		{
			if (!replace)
				ereport(ERROR,
						(errcode(ERRCODE_DUPLICATE_FUNCTION),
						 errmsg("package \"%s\" already exists with same name",
								pkgname)));
			replaces[Anum_pg_package_pkgsecdef - 1] = true;
			replaces[Anum_pg_package_pkgspec - 1] = CStringGetTextDatum(pkgspec);
		}

		if (!pg_package_ownercheck(oldpkg->oid, pkgowner))
			aclcheck_error(ACLCHECK_NOT_OWNER, OBJECT_PACKAGE, pkgname);

		/* Okay, do it... */
		tup = heap_modify_tuple(oldtup, tupdesc, values, nulls, replaces);
		CatalogTupleUpdate(rel, &tup->t_self, tup);

		ReleaseSysCache(oldtup);
		is_update = true;
	}
	else
	{
		/* create a new package */
		Oid			newOid;

		/* a package spec must exist for package body. */
		if (isbody)
		{
			ereport(ERROR,
					(errcode(ERRCODE_DUPLICATE_FUNCTION),
					 errmsg("package \"%s\" does not exists",
							pkgname)));
		}

		pkgacl = get_user_default_acl(OBJECT_PACKAGE, pkgowner,
									  pkgnamespace);
		if (pkgacl != NULL)
			values[Anum_pg_package_pkgacl - 1] = PointerGetDatum(pkgacl);
		else
			nulls[Anum_pg_package_pkgacl - 1] = true;

		newOid = GetNewOidWithIndex(rel, PackageObjectIndexId,
									Anum_pg_package_oid);
		values[Anum_pg_package_oid - 1] = ObjectIdGetDatum(newOid);
		tup = heap_form_tuple(tupdesc, values, nulls);
		CatalogTupleInsert(rel, tup);
		is_update = false;
	}

	packageoid = ((Form_pg_package) GETSTRUCT(tup))->oid;

	if (is_update)
		deleteDependencyRecordsFor(PackageRelationId, packageoid, true);

	myself.classId = PackageRelationId;
	myself.objectId = packageoid;
	myself.objectSubId = 0;

	/* dependency on namespace */
	referenced.classId = NamespaceRelationId;
	referenced.objectId = pkgnamespace;
	referenced.objectSubId = 0;
	recordDependencyOn(&myself, &referenced, DEPENDENCY_AUTO);

	/* dependency on owner */
	if (!is_update)
		recordDependencyOnOwner(PackageRelationId, packageoid, pkgowner);

	/* dependency on any roles mentioned in ACL */
	if (!is_update)
		recordDependencyOnNewAcl(PackageRelationId, packageoid, 0,
								 pkgowner, pkgacl);

	heap_freetuple(tup);
	table_close(rel, RowExclusiveLock);

	return packageoid;
}
