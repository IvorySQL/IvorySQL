/*-------------------------------------------------------------------------
 *
 * File:packagecache.c
 *
 * Abstract:
 *		Definitions for the PLISQL Package cache
 *
 *
 * Authored by dwdai@highgo.com,20220929.
 *
 * Copyright (c) 2022-2025, IvorySQL Global Development Team
 *
 * IDENTIFICATION
 *	  src/backend/utils/cache/packagecache.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "c.h"
#include "utils/memutils.h"
#include "utils/catcache.h"
#include "utils/packagecache.h"
#include "utils/hsearch.h"
#include "utils/syscache.h"
#include "utils/lsyscache.h"
#include "utils/inval.h"
#include "utils/guc.h"
#include "utils/plancache.h"
#include "utils/builtins.h"
#include "catalog/pg_package.h"
#include "catalog/pg_package_body.h"
#include "catalog/pg_language.h"
#include "catalog/pg_proc.h"
#include "access/htup_details.h"
#include "access/genam.h"
#include "access/table.h"
#include "commands/packagecmds.h"
#include "commands/extension.h"
#include "parser/parse_func.h"


static HTAB *PackageCache = NULL;
MemoryContext PackageCacheContext = NULL;

static void BuildPackageCache(void);
static void InvalidatePackageCacheCallback(Datum arg,
						  int cacheid, uint32 hashvalue);
static Oid get_plisql_validator(void);


/*
 * lookup a package in cache
 */
PackageCacheItem *
PackageCacheLookup(PackageCacheKey *key)
{
	PackageCacheEntry *entry;

	if (PackageCache == NULL)
		BuildPackageCache();

	entry = hash_search(PackageCache, key, HASH_FIND, NULL);

	return entry == NULL ? NULL : entry->item;
}

/*
* check package cache whether is valid
*/

bool
PackageCacheIsValid(PackageCacheKey *key, bool check_body)
{
	PackageCacheItem *item;
	HeapTuple tuple;
	bool is_valid = true;

	Assert(key != NULL);
	tuple = SearchSysCache1(PKGOID, ObjectIdGetDatum(*key));
	if (!HeapTupleIsValid(tuple))
		return false;

	item = PackageCacheLookup(key);
	if (item == NULL)
	{
		is_valid = false;
	}
	else
	{
		/* package specification isn't updated */
		if (PACKAGE_SPECIFICATION_IS_UPDATED(item->cachestatus))
			is_valid = false;
	}

	ReleaseSysCache(tuple);
	if (!is_valid)
		return false;

	if (check_body)
	{
		/* has no body or body has been updated */
		if (!PACKAGE_HAS_BODY(item->cachestatus) ||
			PACKAGE_BODY_IS_UPDATED(item->cachestatus))
			is_valid = false;
	}
	return is_valid;
}


/*
 * like validate function
 * we validate package
 */
void
ValidatroPackage(Oid objectid, bool is_body)
{
	plisql_internel_funcs_init();

	plisql_internal_funcs.package_validator(objectid, is_body);
}


/*
 * found package'var and type
 * we should compile it
 */
PackageCacheItem *
PackageHandle(Oid objectid, bool is_body)
{
	plisql_internel_funcs_init();

	return plisql_internal_funcs.package_handle(objectid, is_body);
}

/*
 * free a package from cache
 * which include delete and free its memory
 */
void
FreePackageCache(PackageCacheKey *key)
{
	PackageCacheItem *item = PackageCacheDelete(key);

	if (item == NULL)
		return;

	plisql_internel_funcs_init();

	plisql_internal_funcs.package_free(item);
}


/*
* Delete a package from cache
*/
PackageCacheItem *
PackageCacheDelete(PackageCacheKey *key)
{
	 PackageCacheEntry *entry;

	 /* package cache doesn't init */
	 if (PackageCache == NULL)
		 return NULL;

	 entry = (PackageCacheEntry *) hash_search(PackageCache,
											 (void *) key,
											 HASH_REMOVE,
											 NULL);

	 if (entry != NULL)
	 {
		 elog(DEBUG1, "PackCache Delete %u", entry->item->pkey);
		 setPlanCacheInvalidForPackage(*key);
		 return entry->item;
	 }
	 return NULL;
}

/*
* Insert a Package into cache
*/
void
PackageCacheInsert(PackageCacheKey *key, PackageCacheItem *item)
{
	PackageCacheEntry *entry;
	bool	 found;

	/* if doesn't init, we init cache */
	if (PackageCache == NULL)
		BuildPackageCache();

	entry = (PackageCacheEntry *) hash_search(PackageCache,
										 (void *) key,
										 HASH_ENTER,
										 &found);
	if (found)
	{
		plisql_internel_funcs_init();
		plisql_internal_funcs.package_free(item);
		elog(ERROR, "trying to insert a package that already exists");
	}
	entry->item = item;
	entry->key = *key;
	item->intable = true;

	return;
}


/*
* release all package cache in this session
*
* we don't free package during seq search in
* hash table, but we build list during seq search
* and after seq search then we free package list
*/
void
ResetPackageCaches(void)
{
	HASH_SEQ_STATUS status;
	PackageCacheEntry *entry;
	List *pkglist = NIL;

	if (PackageCache == NULL)
		return;

	plisql_internel_funcs_init();

	hash_seq_init(&status, PackageCache);
	while ((entry = (PackageCacheEntry *) hash_seq_search(&status)) != NULL)
	{
		pkglist = lappend(pkglist, entry->item);
		/* Now we can remove the hash table entry */
		hash_search(PackageCache, (void *) &entry->key, HASH_REMOVE, NULL);
	}
	plisql_internel_funcs_init();
	plisql_internal_funcs.package_free_list(pkglist);

	return;
}


/*
* build a hash tab for package
*/
static void
BuildPackageCache(void)
{
	HASHCTL	 ctl;
	HTAB		*cache;
	MemoryContext oldcontext;

	Assert(PackageCacheContext == NULL);

	/*
	* This is our first time attempting to build the cache, so we need to
	* set up the memory context.
	*/
	if (CacheMemoryContext == NULL)
		CreateCacheMemoryContext();

	PackageCacheContext =
		 AllocSetContextCreate(CacheMemoryContext, "PackageCache",
							 ALLOCSET_DEFAULT_SIZES);

	/* register invalid cache */
	CacheRegisterSyscacheCallback(PKGBODYOID, InvalidatePackageCacheCallback, (Datum) 0);
	CacheRegisterSyscacheCallback(PKGOID, InvalidatePackageCacheCallback, (Datum) 0);

	/* Switch to correct memory context. */
	oldcontext = MemoryContextSwitchTo(PackageCacheContext);

	/* Create new hash table. */
	MemSet(&ctl, 0, sizeof(ctl));
	ctl.keysize = sizeof(PackageCacheKey);
	ctl.entrysize = sizeof(PackageCacheEntry);
	ctl.hcxt = PackageCacheContext;
	cache = hash_create("Package Cache", 32, &ctl,
					 HASH_ELEM | HASH_BLOBS | HASH_CONTEXT);
	/* Restore previous memory context. */
	MemoryContextSwitchTo(oldcontext);

	/* Install new cache. */
	PackageCache = cache;

	return;
}

/*
* when ora_package or ora_package_body update or delete
* we should remove package'cache
*/
static void
InvalidatePackageCacheCallback(Datum arg,
						  int cacheid, uint32 hashvalue)
{
	HASH_SEQ_STATUS status;
	PackageCacheEntry *entry;
	bool	 invalid = false;

	hash_seq_init(&status, PackageCache);
	while ((entry = (PackageCacheEntry *) hash_seq_search(&status)) != NULL)
	{
		invalid = false;

		if (hashvalue == 0)
			invalid = true;
		else if (cacheid == PKGOID && entry->item->package_hash_value == hashvalue)
			invalid = true;
		else if (cacheid == PKGBODYOID && entry->item->body_hash_value == hashvalue)
			invalid = true;

		if (invalid)
		{
			if (cacheid == PKGOID)
				entry->item->cachestatus =
					PACKAGE_SET_SPECIFICATION_UPDATE_FLAG(entry->item->cachestatus);
			else
				entry->item->cachestatus = PACKAGE_SET_BODY_UPDATE_FLAG(entry->item->cachestatus);
		 }
	}
	return;
}


/*
 * get plisq language validator
 */
static Oid
get_plisql_validator(void)
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

		aclresult = object_aclcheck(LanguageRelationId, languageOid, GetUserId(), ACL_USAGE);
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
 * init plisql_internel funcs
 */
void
plisql_internel_funcs_init(void)
{
	 if (!plisql_internal_funcs.isload)
	 {
		 FmgrInfo flifo;
		 /* load plsql library */
		 fmgr_info(get_plisql_validator(), &flifo);
		 Assert(plisql_internal_funcs.isload);
	 }
	 return;
}


/*
 * construct funcexpr maybe it is from a view
 */
void
set_pkginfo_from_funcexpr(FuncExpr *expr)
{
	Assert(expr->function_from == FUNC_FROM_PACKAGE);

	/*
	 * expr maybe from a view and doesn't transform
	 * we should according function name to reconstruct
	 * funcexpr
	 */
	if (expr->parent_func == NULL && expr->function_name != NULL)
	{
		ParseState *pstate;
		FuncCall	 *fn;
		FuncExpr	 *funcexpr;

		fn = makeNode(FuncCall);
		pstate = make_parsestate(NULL);

		fn->funcname = (List *) stringToNode(expr->function_name);
		funcexpr = (FuncExpr *) ParseFuncOrColumn(pstate,
							 fn->funcname,
							 expr->args,
							 NULL,
							 fn,
							 false,
							 fn->location);
		if (funcexpr->function_from != FUNC_FROM_PACKAGE)
			elog(ERROR, "maybe search_path has changed from view create");

		expr->parent_func = funcexpr->parent_func;
		expr->funcid = funcexpr->funcid;
		expr->funcresulttype = funcexpr->funcresulttype;
		expr->funcvariadic = funcexpr->funcvariadic;
		expr->pkgoid = funcexpr->pkgoid;
		list_free(fn->funcname);
		pfree(fn);
		pfree(pstate);
		pfree(funcexpr);
	}
	return;
}

/*
 * construct funcexpr maybe it is from view
 * if it references pakcage'type
 */
void
set_pkgtype_from_funcexpr(FuncExpr *expr)
{
	Assert(expr->function_from == FUNC_FROM_PG_PROC);

	/*
	 * expr maybe from a view and doesn't transform
	 * we should according funcid and function name
	 */
	if (expr->ref_pkgtype)
	{
		ParseState *pstate;
		FuncCall	 *fn;
		FuncExpr	 *funcexpr;
		char 		*func_name = get_func_name(expr->funcid);
		char		*chema_name = get_namespace_name(get_func_namespace(expr->funcid));
		Oid			funcrettype;
		TupleDesc	tupdesc;
		char		f_kind = get_func_prokind(expr->funcid);

		fn = makeNode(FuncCall);
		pstate = make_parsestate(NULL);

		fn->funcname = list_make2(makeString(chema_name), makeString(func_name));
		funcexpr = (FuncExpr *) ParseFuncOrColumn(pstate,
							 fn->funcname,
							 expr->args,
							 NULL,
							 fn,
							 f_kind == PROKIND_PROCEDURE ? true : false,
							 fn->location);
		if (funcexpr->function_from != FUNC_FROM_PG_PROC ||
			funcexpr->funcid != expr->funcid)
			elog(ERROR, "maybe search_path has changed from view create");

		/*
		 * maybe out parameter has change its resulttype
		 */
		get_expr_result_type((Node *)funcexpr,
							&funcrettype,
							&tupdesc);
		expr->funcresulttype = funcexpr->funcresulttype;
		expr->funcvariadic = funcexpr->funcvariadic;
		list_free(fn->funcname);
		pfree(fn);
		pfree(pstate);
		pfree(funcexpr);
		pfree(func_name);
		pfree(chema_name);
	}
	return;
}



/*
 * get top function or package oid
 */
Oid
get_top_function_info(FuncExpr *fexpr, bool *is_package)
{
	plisql_internel_funcs_init();

	if (FUNC_EXPR_FROM_PACKAGE(fexpr->function_from))
		set_pkginfo_from_funcexpr(fexpr);

	if (fexpr->parent_func == NULL)
		return InvalidOid;

	return plisql_internal_funcs.get_top_function_id(fexpr->parent_func,
									is_package);
}

/*
 * get all subprocs in package
 */
Datum
pg_get_subprocs_in_package(PG_FUNCTION_ARGS)
{
	ReturnSetInfo *rsinfo = (ReturnSetInfo *) fcinfo->resultinfo;
	TupleDesc	tupdesc;
	Tuplestorestate *tupstore;
	MemoryContext per_query_ctx;
	MemoryContext oldcontext;
	Relation pkg_rel;
	SysScanDesc pkg_sd;
	HeapTuple pkg_tuple;
	bool init = false;

	/* check to see if caller supports us returning a tuplestore */
	if (rsinfo == NULL || !IsA(rsinfo, ReturnSetInfo))
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("set-valued function called in context that cannot accept a set")));
	if (!(rsinfo->allowedModes & SFRM_Materialize))
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("materialize mode required, but it is not allowed in this context")));

	/* need to build tuplestore in query context */
	per_query_ctx = rsinfo->econtext->ecxt_per_query_memory;
	oldcontext = MemoryContextSwitchTo(per_query_ctx);

	/*
	 * build tupdesc for result tuples.
	 */
	tupdesc = CreateTemplateTupleDesc(17);
	TupleDescInitEntry(tupdesc, (AttrNumber) 1, "oid",
					   OIDOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 2, "namespace",
					   OIDOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 3, "owner",
					   OIDOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 4, "package_name",
					   TEXTOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 5, "proc_name",
					   TEXTOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 6, "fno",
					   INT4OID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 7, "kind",
					   CHAROID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 8, "nargs",
					   INT4OID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 9, "ndefaults",
					   INT4OID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 10, "rettype",
					   OIDOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 11, "rettypname",
					   TEXTOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 12, "argtypes",
					   OIDVECTOROID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 13, "argtypenames",
					   TEXTARRAYOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 14, "argmodes",
					   CHARARRAYOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 15, "argnames",
					   TEXTARRAYOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 16, "argdefaults",
					   TEXTARRAYOID, -1, 0);
	TupleDescInitEntry(tupdesc, (AttrNumber) 17, "prosecdef",
					   BOOLOID, -1, 0);

	/*
	 * We put all the tuples into a tuplestore in one scan of the hashtable.
	 * This avoids any issue of the hashtable possibly changing between calls.
	 */
	tupstore =
		tuplestore_begin_heap(rsinfo->allowedModes & SFRM_Materialize_Random,
							  false, work_mem);

	/* generate junk in short-term context */
	MemoryContextSwitchTo(oldcontext);

	pkg_rel = table_open(PackageRelationId, AccessShareLock);

	pkg_sd = systable_beginscan(pkg_rel, InvalidOid, false,
							NULL, 0, NULL);

	while ((pkg_tuple = systable_getnext(pkg_sd)) != NULL)
	{
		Form_pg_package form_pkg = (Form_pg_package) GETSTRUCT(pkg_tuple);

		if (!init)
		{
			plisql_internel_funcs_init();
			init = true;
		}
		plisql_internal_funcs.get_subprocs_from_package(form_pkg->oid,
									tupdesc, tupstore);
	}

	systable_endscan(pkg_sd);

	/* clean up and return the tuplestore */
	table_close(pkg_rel, NoLock);

	rsinfo->returnMode = SFRM_Materialize;
	rsinfo->setResult = tupstore;
	rsinfo->setDesc = tupdesc;

	return (Datum) 0;
}


