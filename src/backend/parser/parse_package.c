/*-------------------------------------------------------------------------
 *
 * File:parse_package.c
 *
 * Abstract:
 *		Definitions for the PLISQL Package parser
 *
 *
 * Portions Copyright (c) 2024-2025, IvorySQL Global Development Team 
 *
 * IDENTIFICATION
 *	  src/backend/parser/parse_package.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "parser/parse_package.h"
#include "utils/packagecache.h"
#include "utils/acl.h"
#include "utils/guc.h"
#include "utils/ora_compatible.h"
#include "catalog/namespace.h"
#include "commands/packagecmds.h"
#include "commands/dbcommands.h"
#include "miscadmin.h"

/* usefull functions */
static bool package_resolve_names(List *names, PackageCacheKey *pkey,
									int *pkgname_startloc);
static PkgType *parse_package_type(List *names, PackageCacheKey *pkey,
				 int typename_startloc, bool missing_ok);
static PkgVar *parse_package_var(List *names, PackageCacheKey *pkey,
			 int varname_startloc, bool missing_ok);
static PkgEntry *parse_package_entry(List *names, PackageCacheKey *pkey,
			 int name_startloc, bool missing_ok);
static FuncDetailCode parse_package_func(ParseState *pstate, PackageCacheKey *pkey,
										 List *names, int varname_startloc,
										 List **fargs, /* return value */
										 List *fargnames,
										 int nargs,
										 Oid *argtypes,
										 bool expand_variadic,
										 bool expand_defaults,
										 bool proc_call,
										 Oid *funcid,	/* return value */
										 Oid *rettype,	/* return value */
										 bool *retset,	/* return value */
										 int *nvargs,	/* return value */
										 Oid *vatype,	/* return value */
										 Oid **true_typeids, /* return value */
										 List **argdefaults, /* return value */
										 void **pfunc,
										 bool missing_ok);


/*
 * reslove to find name in a package
 * first:	we search for package.xxx
 * second: we search for schema.package.xxx
 * third: we search for database.schemaname.package.xx
 */
static bool
package_resolve_names(List *names, PackageCacheKey *pkey, int *pkgname_startloc)
{
	char *first_name;
	int list_size;
	Oid pkgoid;
	List *tmp;

	list_size = list_length(names);

	Assert(pkey != NULL);

	switch (list_size)
	{
		case 0:
		case 1:
			/* doesn't support reference a package type exclude pkg name */
			return false;
		case 2:
			 {
				 /* must be pkgname and typename */
				 pkgoid = PkgnameGetPkgid(strVal(linitial(names)));
				 if (OidIsValid(pkgoid))
				 {
					 *pkey = pkgoid;
					 *pkgname_startloc = 1;
					 return true;
				 }
				 else
					 return false;
			 }
			break;
		default:
			break;
	}

	first_name = strVal(linitial(names));

	/* treate first name as package name */
	pkgoid = PkgnameGetPkgid(first_name);
	if (OidIsValid(pkgoid))
	{
		*pkey = pkgoid;
		*pkgname_startloc = 1;
		return true;
	}

	/* treate first name as schema name and second as package name */
	tmp = lappend(list_make1(linitial(names)), lsecond(names));
	pkgoid = LookupPackageByNames(tmp, true);
	if (OidIsValid(pkgoid))
	{
		*pkey = pkgoid;
		list_free(tmp);
		*pkgname_startloc = 2;
		return true;
	}
	list_free(tmp);

	/* first name is the database'name */
	if (strcmp(first_name, get_database_name(MyDatabaseId)) == 0)
	{
		/* must be database.schema.package.xxx */
		if (list_size != 3)
		{
			tmp = lappend(list_make1(lsecond(names)), lthird(names));
			pkgoid = LookupPackageByNames(tmp, true);
			if (OidIsValid(pkgoid))
			{
				*pkey = pkgoid;
				*pkgname_startloc = 3;
				list_free(tmp);
				return true;
			}
			list_free(tmp);
			return false;
		}
		/* others */
		return false;
	}
	return false;
}


/*
 * according pkey to parse package type
 *
 */

static PkgType *
parse_package_type(List *names, PackageCacheKey *pkey,
		 int typename_startloc, bool missing_ok)
{
	PackageCacheItem *item;
	Oid basetypeid;
	void *type;
	PkgType *pkgtype;

	if (PackageCacheIsValid(pkey, false))
		item = PackageCacheLookup(pkey);
	else
		item = PackageHandle(*pkey, false);

	Assert(item != NULL);
	plisql_internel_funcs_init();
	type = plisql_internal_funcs.package_parse(NULL, item, names, typename_startloc,
							 PACKAGE_PARSE_TYPE, &basetypeid, NULL,
							 NULL, NULL, 0, NULL, false, false,
							 NULL, NULL, NULL, NULL, NULL, NULL,
							 NULL, NULL,
							 missing_ok);
	if (type == NULL)
		return NULL;

	pkgtype = palloc(sizeof(PkgType));
	pkgtype->pkgoid = *pkey;
	pkgtype->basetypid = basetypeid;
	pkgtype->item = item;
	pkgtype->value = type;

	return pkgtype;
 }


/*
 * according to pkey to parse package var
 *
 */

static PkgVar *
parse_package_var(List *names, PackageCacheKey *pkey,
			 int varname_startloc, bool missing_ok)
{
	PackageCacheItem *item;
	void *var;
	PkgVar *pkgvar;


	if (PackageCacheIsValid(pkey, false))
		item = PackageCacheLookup(pkey);
	else
		item = PackageHandle(*pkey, false);

	Assert(item != NULL);
	plisql_internel_funcs_init();
	var = plisql_internal_funcs.package_parse(NULL, item, names, varname_startloc,
									 PACKAGE_PARSE_VAR, NULL, NULL,
									 NULL, NULL, 0, NULL, false, false,
									 NULL, NULL, NULL, NULL, NULL, NULL,
									 NULL, NULL,
									 missing_ok);
	if (var == NULL)
		return NULL;

	pkgvar = palloc(sizeof(PkgVar));
	pkgvar->pkgoid = *pkey;
	pkgvar->value = (Datum) var;
	pkgvar->item = item;

	return pkgvar;
}

/*
 * according to pkey to parse package'var or type
 *
 */
PkgEntry *
parse_package_entry(List *names, PackageCacheKey *pkey,
				 int name_startloc, bool missing_ok)
{
	PackageCacheItem *item;
	int	 entry_type;
	PkgEntry *entry;
	void *value;

	if (PackageCacheIsValid(pkey, false))
		item = PackageCacheLookup(pkey);
	else
		item = PackageHandle(*pkey, false);

	Assert(item != NULL);
	plisql_internel_funcs_init();
	value = plisql_internal_funcs.package_parse(NULL, item, names, name_startloc,
									 PACKAGE_PARSE_ENTRY, NULL, &entry_type,
									 NULL, NULL, 0, NULL, false, false,
									 NULL, NULL, NULL, NULL, NULL, NULL,
									 NULL, NULL,
									 missing_ok);

	if (value == NULL)
		return NULL;

	entry = palloc0(sizeof(PkgEntry));

	entry->type = entry_type;
	entry->value = value;
	entry->item = item;

	return entry;
}


/*
 * according to pkey,parsing a func in package
 *
 */
static FuncDetailCode
parse_package_func(ParseState *pstate, PackageCacheKey *pkey,
						List *names, int varname_startloc,
						List **fargs, /* return value */
						List *fargnames,
						int nargs,
						Oid *argtypes,
						bool expand_variadic,
						bool expand_defaults,
						bool proc_call,
						Oid *funcid,	/* return value */
						Oid *rettype,	/* return value */
						bool *retset,	/* return value */
						int *nvargs,	/* return value */
						Oid *vatype,	/* return value */
						Oid **true_typeids, /* return value */
						List **argdefaults, /* return value */
						void **pfunc,		/* return value */
						bool missing_ok)
{
	PackageCacheItem *item;
	FuncDetailCode result;
	package_parse_flags flags;

	if (PackageCacheIsValid(pkey, false))
		item = PackageCacheLookup(pkey);
	else
		item = PackageHandle(*pkey, false);

	Assert(item != NULL);
	if (proc_call)
		flags = PACKAGE_PARSE_PROC;
	else
		flags = PACKAGE_PARSE_FUNC;
	plisql_internel_funcs_init();
	result = (FuncDetailCode ) plisql_internal_funcs.package_parse(pstate,
										item, names,
										varname_startloc,
										flags,
										NULL,
										NULL,
										fargs, /* return value */
										fargnames,
										nargs,
										argtypes,
										expand_variadic,
										expand_defaults,
										funcid,	/* return value */
										rettype,	/* return value */
										retset,	/* return value */
										nvargs,	/* return value */
										vatype,	/* return value */
										true_typeids, /* return value */
										argdefaults, /* return value */
										pfunc,		/* return value */
										missing_ok);

	return result;
}


/*
 * find typname in a package
 */
PkgType *
LookupPkgTypeByTypename(const List *names, bool missing_ok)
{
	PackageCacheKey pkey;
	int pkgname_startloc = 0;
	PkgType *pkgtype;
	AclResult aclresult;

	if (ORA_PARSER != compatible_db)
		return NULL;

	if (!package_resolve_names((List *) names, &pkey, &pkgname_startloc))
		return NULL;

	/* check package usage */
	aclresult = pg_package_aclcheck(pkey, GetUserId(), ACL_EXECUTE);
	if (aclresult != ACLCHECK_OK)
		aclcheck_error(aclresult, OBJECT_PACKAGE, get_package_name(pkey));

	pkgtype = parse_package_type((List *) names, &pkey,
							pkgname_startloc, missing_ok);
	if (pkgtype != NULL)
		pkgtype->pkgname_startloc = pkgname_startloc;

	return pkgtype;
}


/*
 * find var in a package
 */
PkgVar *
LookupPkgVarByvarnames(const List *names, bool missing_ok)
{
	PackageCacheKey pkey;
	int varname_startloc = 0;
	AclResult aclresult;

	if (ORA_PARSER != compatible_db)
		return NULL;

	if (!package_resolve_names((List *) names, &pkey, &varname_startloc))
		return NULL;

	/* check package usage */
	aclresult = pg_package_aclcheck(pkey, GetUserId(), ACL_EXECUTE);
	if (aclresult != ACLCHECK_OK)
		aclcheck_error(aclresult, OBJECT_PACKAGE, get_package_name(pkey));

	return parse_package_var((List *) names, &pkey,
			 varname_startloc, missing_ok);
}


/*
 * find type or var in a package
 * we support this function, because
 * plsql support this : array := pkg.collect_type(var1)
 * to use type to construct
 *
 */
PkgEntry *
LookupPkgEntryByTypename(const List *names, bool missing_ok)
{
	PackageCacheKey pkey;
	int name_startloc;
	AclResult aclresult;

	if (ORA_PARSER != compatible_db)
		return NULL;

	if (!package_resolve_names((List *) names, &pkey, &name_startloc))
		return NULL;

	/* check package usage */
	aclresult = pg_package_aclcheck(pkey, GetUserId(), ACL_EXECUTE);
	if (aclresult != ACLCHECK_OK)
		aclcheck_error(aclresult, OBJECT_PACKAGE, get_package_name(pkey));

	return parse_package_entry((List *) names, &pkey,
			 name_startloc, missing_ok);
}


/*
 * find a func in package
 */
FuncDetailCode
LookupPkgFunc(ParseState *pstate, List *funcname,
					List **fargs, /* return value */
					List *fargnames,
					int nargs,
					Oid *argtypes,
					bool expand_variadic,
					bool expand_defaults,
					bool proc_call,
					Oid *funcid,	/* return value */
					Oid *rettype,	/* return value */
					bool *retset,	/* return value */
					int *nvargs,	/* return value */
					Oid *vatype,	/* return value */
					Oid **true_typeids, /* return value */
					List **argdefaults, /* return value */
					void **pfunc,		/* return value */
					Oid *pkgoid,		/* return value */
					bool missing_ok)

{
	PackageCacheKey pkey;
	int funcname_startloc;
	AclResult aclresult;

	if (ORA_PARSER != compatible_db)
		return FUNCDETAIL_NOTFOUND;

	if (!package_resolve_names(funcname, &pkey, &funcname_startloc))
		return FUNCDETAIL_NOTFOUND;

	*pkgoid = pkey;

	/* check package usage */
	aclresult = pg_package_aclcheck(pkey, GetUserId(), ACL_EXECUTE);
	if (aclresult != ACLCHECK_OK)
		aclcheck_error(aclresult, OBJECT_PACKAGE, get_package_name(pkey));

	return parse_package_func(pstate, &pkey, funcname,
			 funcname_startloc, fargs, fargnames, nargs,
			 argtypes, expand_variadic, expand_defaults,
			 proc_call, funcid, rettype, retset,
			 nvargs, vatype, true_typeids, argdefaults,
			 pfunc, missing_ok);
}

