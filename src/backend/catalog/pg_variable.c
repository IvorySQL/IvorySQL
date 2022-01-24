/*-------------------------------------------------------------------------
 *
 * pg_varaible.c
 *		package's variable
 *
 * Portions Copyright (c) 2021-2022, IvorySQL
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *		src/backend/catalog/pg_varaible.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "catalog/pg_variable.h"
#include "catalog/pg_namespace.h"
#include "catalog/pg_package.h"
#include "catalog/dependency.h"
#include "catalog/pg_proc.h"
#include "utils/builtins.h"
#include "catalog/indexing.h"
#include "utils/syscache.h"
#include "catalog/pg_type.h"
#include "utils/rel.h"

#include "catalog/catalog.h"
#include "access/htup_details.h"
#include "access/table.h"
#include "catalog/objectaccess.h"





static VariableEOXActionCodes
to_eoxaction_code(VariableEOXAction action)
{
	switch (action)
	{
		case VARIABLE_EOX_NOOP:
			return VARIABLE_EOX_CODE_NOOP;

		case VARIABLE_EOX_DROP:
			return VARIABLE_EOX_CODE_DROP;

		case VARIABLE_EOX_RESET:
			return VARIABLE_EOX_CODE_RESET;

		default:
			elog(ERROR, "unexpected action");
	}
}


ObjectAddress
VariableCreate(const char *varName,
			   Oid varNamespace,
			   Oid variableoid,
			   Oid varType,
			   int32 varTypmod,
			   Oid varOwner,
			   Oid varCollation,
			   Node *varDefexpr,
			   VariableEOXAction eoxaction,
			   bool is_not_null,
			   bool is_immutable,
			   bool ispkg,
			   bool replace,
			   bool isbody)
{
	Acl		   *varacl = NULL;
	NameData	varname;
	bool		nulls[Natts_pg_variable];
	Datum		values[Natts_pg_variable];
	bool		replaces[Natts_pg_variable];
	Relation	rel;
	HeapTuple	tup,
				oldtup;
	TupleDesc	tupdesc;
	ObjectAddress myself,
				referenced;
	Oid			varid;
	int			i;

	for (i = 0; i < Natts_pg_variable; i++)
	{
		nulls[i] = false;
		values[i] = (Datum) 0;
		replaces[i] = false;
	}
	namestrcpy(&varname, varName);

	rel = table_open(VariableRelationId, RowExclusiveLock);

	/*
	 * if just update the variable,there in no need to update the oid of the
	 * variable.
	 */
	if (!variableoid)
		varid = GetNewOidWithIndex(rel, VariableObjectIndexId, Anum_pg_variable_oid);
	else
		varid = variableoid;
	values[Anum_pg_variable_oid - 1] = ObjectIdGetDatum(varid);
	values[Anum_pg_variable_varname - 1] = NameGetDatum(&varname);
	values[Anum_pg_variable_varnamespace - 1] = ObjectIdGetDatum(varNamespace);
	values[Anum_pg_variable_vartype - 1] = ObjectIdGetDatum(varType);
	values[Anum_pg_variable_vartypmod - 1] = Int32GetDatum(varTypmod);
	values[Anum_pg_variable_varowner - 1] = ObjectIdGetDatum(varOwner);
	values[Anum_pg_variable_varcollation - 1] = ObjectIdGetDatum(varCollation);
	values[Anum_pg_variable_vareoxaction - 1] = CharGetDatum((char) to_eoxaction_code(eoxaction));
	values[Anum_pg_variable_varisnotnull - 1] = BoolGetDatum(is_not_null);
	values[Anum_pg_variable_varisimmutable - 1] = BoolGetDatum(is_immutable);

	if (varDefexpr)
		values[Anum_pg_variable_vardefexpr - 1] = CStringGetTextDatum(nodeToString(varDefexpr));
	else
		nulls[Anum_pg_variable_vardefexpr - 1] = true;

	tupdesc = RelationGetDescr(rel);

	oldtup = SearchSysCache2(VARIABLENAMENSP,
							 PointerGetDatum(varName),
							 ObjectIdGetDatum(varNamespace));

	if (HeapTupleIsValid(oldtup))
	{
		/* there is one, okay replace it */
		Form_pg_variable oldpkg = (Form_pg_variable) GETSTRUCT(oldtup);

		if (!replace || oldpkg->oid != varid)
			ereport(ERROR,
					(errcode(ERRCODE_DUPLICATE_FUNCTION),
					 errmsg("at most one declaration for \"%s\" is permitted",
							varName)));

		if (!pg_variable_ownercheck(oldpkg->oid, varOwner))
			aclcheck_error(ACLCHECK_NOT_OWNER, OBJECT_VARIABLE, varName);

		replaces[Anum_pg_variable_vardefexpr - 1] = true;
		tup = heap_modify_tuple(oldtup, tupdesc, values, nulls, replaces);
		CatalogTupleUpdate(rel, &tup->t_self, tup);
		ReleaseSysCache(oldtup);
	}
	else
	{
		if (isbody)
			values[Anum_pg_variable_varaccess - 1] = CharGetDatum(PACKAGE_MEMBER_PRIVATE);
		else
			values[Anum_pg_variable_varaccess - 1] = CharGetDatum(PACKAGE_MEMBER_PUBLIC);
		varacl = acldefault(OBJECT_VARIABLE, varOwner);
		if (varacl != NULL)
			values[Anum_pg_variable_varacl - 1] = PointerGetDatum(varacl);
		else
			nulls[Anum_pg_variable_varacl - 1] = true;

		tup = heap_form_tuple(tupdesc, values, nulls);
		CatalogTupleInsert(rel, tup);
	}

	myself.classId = VariableRelationId;
	myself.objectId = varid;
	myself.objectSubId = 0;

	if (ispkg)
	{
		/* dependency on package */
		referenced.classId = PackageRelationId;
		referenced.objectId = varNamespace;
		referenced.objectSubId = 0;
		recordDependencyOn(&myself, &referenced, DEPENDENCY_AUTO);
	}
	else
	{
		/* dependency on namespace */
		referenced.classId = NamespaceRelationId;
		referenced.objectId = varNamespace;
		referenced.objectSubId = 0;
		recordDependencyOn(&myself, &referenced, DEPENDENCY_NORMAL);
	}

	/* dependency on any roles mentioned in ACL */
	if (varacl != NULL)
	{
		int			nnewmembers;
		Oid		   *newmembers;

		nnewmembers = aclmembers(varacl, &newmembers);
		updateAclDependencies(VariableRelationId, varid, 0,
							  varOwner,
							  0, NULL,
							  nnewmembers, newmembers);
	}

	/* dependency on extension */
	recordDependencyOnCurrentExtension(&myself, false);

	heap_freetuple(tup);
	table_close(rel, RowExclusiveLock);

	return myself;
}
