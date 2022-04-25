/*-------------------------------------------------------------------------
 *
 * pg_synonym.c
 *	  Commands for compatible oracle synonym.
 *
 * Portions Copyright (c) 1996-2019,  highgo chengdu Group
 *
 * src/backend/catalog/pg_synonym,.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "miscadmin.h"

#include "access/genam.h"
#include "access/htup_details.h"
#include "access/table.h"
#include "access/xact.h"
#include "access/heapam.h"
#include "catalog/catalog.h"
#include "catalog/indexing.h"
#include "catalog/pg_synonym.h"
#include "catalog/namespace.h"
#include "catalog/binary_upgrade.h"
#include "catalog/dependency.h"
#include "catalog/pg_namespace_d.h"
#include "catalog/pg_tablespace_d.h"
#include "catalog/pg_type.h"
#include "catalog/heap.h"

#include "commands/user.h"
#include "commands/dbcommands.h"
#include "commands/tablespace.h"
#include "miscadmin.h"
#include "utils/acl.h"
#include "utils/builtins.h"
#include "utils/fmgroids.h"
#include "utils/syscache.h"
#include "utils/rel.h"
#include "utils/lsyscache.h"

/*************************************************************
 * Funcname: CreateSynonym
 * Description: Execute a CREATE SYNONYM utility statement.
 * Return: ObjectAddress
 *************************************************************/
ObjectAddress
CreateSynonym(CreateSynonymStmt *stmt)
{
	Relation		rel;
	TupleDesc		tupDesc;
	HeapTuple		heaptup;
	HeapTuple		oldtup;
	NameData		cname;
	int				i;
	bool			nulls[Natts_pg_synonym];
	Datum			values[Natts_pg_synonym];
	bool			replaces[Natts_pg_synonym];
	Oid				synnamespaceId;
	Oid				objtablespaceId;
	Oid				synoid;
	Oid				relid = InvalidOid;
	ObjectAddress	myself,
					referenced;
	RangeVar		*synNameNsp;
	RangeVar		*objNameNsp;
	bool			is_update;
	List			*names;
	char			*synrelname;
	Oid				synnamespaceoid;

	Assert(stmt->synonym);
	Assert(stmt->object);

	synNameNsp = stmt->synonym;
	objNameNsp = stmt->object;
	/*
	 * Look up the namespace in which we are supposed to create the relation,
	 * check we have permission to create there, lock it against concurrent
	 * drop, and mark stmt->relation as RELPERSISTENCE_TEMP if a temporary
	 * namespace is selected.
	 */
	synnamespaceId =
		RangeVarGetAndCheckCreationNamespace(synNameNsp, NoLock, NULL);

	if (stmt->synispub)
	{
		if (synNameNsp->schemaname)
		{
			if (strcasecmp(synNameNsp->schemaname, "public") != 0)
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_SCHEMA_NAME),
						 errmsg("error \"%s\" schema, public synonyms only be created in \"public\" schema",
								synNameNsp->schemaname)));
		}
	}

	/*
	 * Select tablespace to use: an explicitly indicated one, or (in the case
	 * of a partitioned table) the parent's, if it has one.
	 */
	if (objNameNsp->schemaname)
		objtablespaceId = get_tablespace_oid(objNameNsp->schemaname, true);
	else
		objtablespaceId = InvalidOid;

	/* still nothing? use the default */
	if (!OidIsValid(objtablespaceId))
		objtablespaceId = GetDefaultTablespace(objNameNsp->relpersistence,
											   false);

	/* Check permissions except when using database's default */
	if (OidIsValid(objtablespaceId) && objtablespaceId != MyDatabaseTableSpace)
	{
		AclResult	aclresult;

		aclresult = pg_tablespace_aclcheck(objtablespaceId, GetUserId(),
										   ACL_CREATE);
		if (aclresult != ACLCHECK_OK)
			aclcheck_error(aclresult, OBJECT_TABLESPACE,
						   get_tablespace_name(objtablespaceId));
	}

	/* In all cases disallow placing user relations in pg_global */
	if (objtablespaceId == GLOBALTABLESPACE_OID)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("only shared relations can be placed in pg_global tablespace")));

	/* sanity checks */
	synoid = GetSysCacheOid3(SYNONYMNAMENSPPUB, Anum_pg_synonym_oid, CStringGetDatum(synNameNsp->relname),
								CStringGetDatum(synNameNsp->schemaname), BoolGetDatum(stmt->synispub));
	if (OidIsValid(synoid))
	{
		ereport(ERROR,
				(errcode(ERRCODE_DUPLICATE_OBJECT),
				 errmsg("synonym \"%s\" already exists",
						synNameNsp->relname)));
	}

	/* open pg_synonym */
	rel = table_open(SynonymRelationId, RowExclusiveLock);
	tupDesc = RelationGetDescr(rel);

	/*
	 * All seems OK; prepare the data to be inserted into pg_synonym.
	 */
	for (i = 0; i < Natts_pg_synonym; ++i)
	{
		nulls[i] = false;
		values[i] = (Datum) 0;
	}

	/* form a tuple */
	namestrcpy(&cname, synNameNsp->relname);
	relid = GetNewOidWithIndex(rel, SynonymOidIndexId,
								Anum_pg_synonym_oid);
	values[Anum_pg_synonym_oid - 1] = ObjectIdGetDatum(relid);
	values[Anum_pg_synonym_synname - 1] = NameGetDatum(&cname);
	if (synNameNsp->schemaname)
		values[Anum_pg_synonym_synnamespace - 1] = ObjectIdGetDatum(get_namespace_oid(synNameNsp->schemaname, false));
	else
		values[Anum_pg_synonym_synnamespace - 1] = ObjectIdGetDatum(synnamespaceId);
	values[Anum_pg_synonym_synowner - 1] = ObjectIdGetDatum(GetUserId());
	values[Anum_pg_synonym_synispub - 1] = BoolGetDatum(stmt->synispub);
	if (objNameNsp->schemaname)
		values[Anum_pg_synonym_synobjschema - 1] = CStringGetTextDatum(objNameNsp->schemaname);
	else
		values[Anum_pg_synonym_synobjschema - 1] = CStringGetTextDatum("public");
	values[Anum_pg_synonym_synobjname - 1] = CStringGetTextDatum(objNameNsp->relname);
	if (stmt->dblinkname)
		values[Anum_pg_synonym_synlink - 1] = CStringGetTextDatum(stmt->dblinkname);
	else
		nulls[Anum_pg_synonym_synlink - 1] = true;

	if (synNameNsp->schemaname)
		names = list_make2(makeString(synNameNsp->schemaname), makeString(synNameNsp->relname));
	else
		names = list_make1(makeString(synNameNsp->relname));
	synnamespaceoid = QualifiedNameGetCreationNamespace(names, &synrelname);

	/* Check for pre-existing definition */
	oldtup = SearchSysCache3(SYNONYMNAMENSPPUB,
							 PointerGetDatum(synrelname),
							 PointerGetDatum(synnamespaceoid),
							 BoolGetDatum(stmt->synispub));
	if (HeapTupleIsValid(oldtup))
	{
		if (!stmt->replace)
		{
			if (synNameNsp->schemaname)
				ereport(ERROR,
						(errcode(ERRCODE_DUPLICATE_FUNCTION),
						 errmsg("synonym \"%s\" already exists with same name in scheme \"%s\"",
								synNameNsp->relname, synNameNsp->schemaname)));
			else
				ereport(ERROR,
						(errcode(ERRCODE_DUPLICATE_FUNCTION),
						 errmsg("synonym \"%s\" already exists with same name",
								synNameNsp->relname)));
		}

		replaces[Anum_pg_synonym_oid - 1] = false;
		replaces[Anum_pg_synonym_synowner - 1] = false;
		replaces[Anum_pg_synonym_synispub - 1] = false;

		/* Okay, do it... */
		heaptup = heap_modify_tuple(oldtup, tupDesc, values, nulls, replaces);
		CatalogTupleUpdate(rel, &heaptup->t_self, heaptup);

		ReleaseSysCache(oldtup);
		is_update = true;
	}
	else
	{
		heaptup = heap_form_tuple(tupDesc, values, nulls);

		Assert(HeapTupleIsValid(heaptup));

		/* insert a new tuple */
		CatalogTupleInsert(rel, heaptup);
		is_update = false;
	}

	if (is_update)
		deleteDependencyRecordsFor(SynonymRelationId, relid, true);

	myself.classId = SynonymRelationId;
	myself.objectId = relid;
	myself.objectSubId = 0;

	/* dependency on namespace */
	referenced.classId = NamespaceRelationId;
	referenced.objectId = synnamespaceId;
	referenced.objectSubId = 0;
	recordDependencyOn(&myself, &referenced, DEPENDENCY_NORMAL);

	/* dependency on owner */
	if (!is_update)
		recordDependencyOnOwner(SynonymRelationId, relid, GetUserId());

	heap_freetuple(heaptup);
	table_close(rel, RowExclusiveLock);

	/* Make the changes visible. */
	CommandCounterIncrement();

	return myself;
}

/************************************************************
 * DROP SYNONYM
 * Description: drop synonym(s)
 * Return: void
 ************************************************************/
void
DropSynonym(DropSynonymStmt *stmt)
{
	Relation	pg_synonym_rel;
	ListCell   *item;
	Oid			scheamoid = InvalidOid;
	bool		pubflg = stmt->pubflg;

	/*
	 * Scan the pg_authid relation to find the Oid of the role(s) to be
	 * deleted.
	 */
	pg_synonym_rel = table_open(SynonymRelationId, RowExclusiveLock);
	
	foreach(item, stmt->synonym)
	{
		List   *synnamelist = lfirst(item);
		char	   *synname = NULL;	
		HeapTuple	tuple = NULL;
		Form_pg_synonym synonymform = NULL;

		scheamoid = QualifiedNameGetCreationNamespace(synnamelist, &synname);
		tuple = SearchSysCache3(SYNONYMNAMENSPPUB, PointerGetDatum(synname), 
								PointerGetDatum(scheamoid), PointerGetDatum(pubflg));

		if (!HeapTupleIsValid(tuple))
		{
			if (!stmt->missing_ok)
			{
				if (stmt->pubflg)
					ereport(ERROR,
							(errcode(ERRCODE_UNDEFINED_OBJECT),
							 errmsg("The public synonym \"%s\" to be deleted does not exist", synname)));
				else
					ereport(ERROR,
							(errcode(ERRCODE_UNDEFINED_OBJECT),
							 errmsg("The special synonym \"%s\" to be deleted does not exist", synname)));
			}
			else
			{
				if (stmt->pubflg)
					ereport(NOTICE,
						(errmsg("The public synonym \"%s\" to be deleted does not exist, skipping",
						synname)));
				else
					ereport(NOTICE,
							(errmsg("The special synonym \"%s\" to be deleted does not exist, skipping",
							synname)));
			}

			continue;
		}

		synonymform = (Form_pg_synonym) GETSTRUCT(tuple);
		if (synonymform != NULL)
		{
			if (synonymform->synispub == true)
			{
				/* public synonym must use public, eg. drop public synonym xxx */
				if (!stmt->pubflg)
					ereport(ERROR,
							(errcode(ERRCODE_UNDEFINED_OBJECT),
							 errmsg("The special synonym \"%s\" to be deleted does not exist", synname)));
			}
			else
			{
				/* there deal with drop private synonym */
				Oid		CurUsrId;
				CurUsrId = GetUserId();

				/* only have the owner of private synonym create can delete */
				if (synonymform->synowner != CurUsrId)
				{
					if (stmt->pubflg)
						ereport(ERROR,
							(errcode(ERRCODE_UNDEFINED_OBJECT),
							 errmsg("The public synonym \"%s\" to be deleted does not exist", synname)));
					else
						ereport(ERROR,
							(errcode(ERRCODE_UNDEFINED_OBJECT),
							 errmsg("The special synonym \"%s\" to be deleted does not exist", synname)));
				}
				else
				{
					if (stmt->pubflg)
						ereport(ERROR,
							(errcode(ERRCODE_UNDEFINED_OBJECT),
							 errmsg("The public synonym \"%s\" to be deleted does not exist", synname)));
				}
			}
		}

		/*
		 * Remove the synonym from the pg_synonym table
		 */
		CatalogTupleDelete(pg_synonym_rel, &tuple->t_self);
		
		ReleaseSysCache(tuple);
	}

	/*
	 * Now we can clean up; but keep locks until commit.
	 */
	table_close(pg_synonym_rel, NoLock);
}

/************************************************************
 * GER SYNONYM OID
 * Description: get synonym oid
 * Return: oid
 ************************************************************/
Oid 
get_synonym_oid(List *synnamelist, bool pubflg, bool missing_ok)
{
	char	   *synname = NULL;
	char	   *schemaname = NULL;
	Oid			scheamoid = InvalidOid;
	Oid			oid = InvalidOid;

	DeconstructQualifiedName(synnamelist, &schemaname, &synname);
	if (schemaname)
	{
		scheamoid =  get_namespace_oid(schemaname, false);
		oid = GetSysCacheOid3(SYNONYMNAMENSPPUB, Anum_pg_synonym_oid,
							  PointerGetDatum(synname), 
							  PointerGetDatum(scheamoid), PointerGetDatum(pubflg));
	}
	else
	{
		scheamoid = QualifiedNameGetCreationNamespace(synnamelist, &synname);
		oid = GetSysCacheOid3(SYNONYMNAMENSPPUB, Anum_pg_synonym_oid,
							  PointerGetDatum(synname), 
							  PointerGetDatum(scheamoid), PointerGetDatum(pubflg));
	}

	if (!OidIsValid(oid) && !missing_ok)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_OBJECT),
				 errmsg("synonym \"%s\" does not exist", NameListToString(synnamelist))));
	
	return oid;
}

/*************************************************************
 * Funcname: get_synonym_name
 * Description: given a OID, look up the synonym name
 * Return: string or null
 *************************************************************/
/*
 * get_synonym_name - given a synonym OID, look up the name
 *
 * If missing_ok is false, throw an error if name not found.  If true, just
 * return NULL.
 */
char *
get_synonym_name(Oid synonymid, bool missing_ok)
{
	HeapTuple		tup;
	char			*synname;
	Form_pg_synonym	synform;

	tup = SearchSysCache1(SYNONYMOID, ObjectIdGetDatum(synonymid));

	if (!HeapTupleIsValid(tup))
	{
		if (!missing_ok)
			elog(ERROR, "cache lookup failed for synonym %u", synonymid);
		return NULL;
	}

	synform = (Form_pg_synonym) GETSTRUCT(tup);
	synname = pstrdup(NameStr(synform->synname));

	ReleaseSysCache(tup);

	return synname;
}

