/*-------------------------------------------------------------------------
 *
 * File:pl_package.c
 *
 * Abstract:
 * 	 Executor for the PLiSQL package
 *
 * Copyright:
 * Copyright (c) 2024-2025, IvorySQL Global Development Team 
 *
 * IDENTIFICATION
 *    src/pl/plisql/src/pl_package.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include <ctype.h>

#include "plisql.h"
#include "pl_package.h"
#include "parser/parse_type.h"
#include "catalog/pg_package.h"
#include "catalog/pg_package_body.h"
#include "catalog/pg_proc.h"
#include "utils/syscache.h"
#include "utils/builtins.h"
#include "commands/packagecmds.h"
#include "miscadmin.h"
#include "utils/array.h"


PLiSQL_package *plisql_compile_packageitem;
static PLiSQL_compile_global_proper *plisql_saved_compile_proper = NULL;
int plisql_curr_global_proper_level = 0;
static int plisql_global_proper_alloc = 0;


static PLiSQL_datum *plisql_parse_recvar(PLiSQL_function *func, PLiSQL_rec *rec,
										List *names, int match_start_loc);
static PLiSQL_type * plisql_get_package_datum_rowtype(const char *typename,
														PLiSQL_function *func,
														PLiSQL_datum *datum, int localno,
														parse_pkgtype_flag flag);
static void plisql_remove_function_references(PLiSQL_function *func,
														PackageCacheItem *item);
static void plisql_addfunction_references(PLiSQL_function *func,
														PackageCacheItem *item);
static void plisql_get_package_depends(PLiSQL_function *func,
								List **funclist, List **itemlist);

static List *plisql_package_sort(List *pkglist);

static void resolve_package_interdependence(PackageCacheItem *item,
											List *lclist,
											ListCell *lc);
static void package_body_init(PLiSQL_package *source);
static void package_body_doCompile(HeapTuple pkgbodyTup,
											PackageCacheItem *item,
											bool forValidator);

static PackageCacheItem *package_doCompile(HeapTuple pkgTup,
											bool forValidator);
static PackageCacheItem *plisql_package_compile(Oid pkgoid,
												bool forValidator,
												bool execcheck);
static PackageCacheItem *plisql_package_body_compile(Oid bodyoid,
												bool forValidator,
												bool execcheck);
static void plisql_exec_package_init(FunctionCallInfo fcinfo,
											PLiSQL_function *package_func);
static void plisql_check_package_status(PLiSQL_execstate *estate,
											PLiSQL_pkg_datum *pkgdatum);

static void plisql_check_subproc_define_recurse(PLiSQL_function *function, List **already_checks);
static TupleDesc get_plisql_rec_tupdesc(PLiSQL_rec *rec);
static void plisql_addpackage_references(PLiSQL_function *func, PackageCacheItem *item);
static PLiSQL_variable *plisql_build_package_local_variable(const char *refname,
					int lineno,
					List *idents,
					bool add2namespace,
					bool missing_ok);
static void plisql_push_compile_global_proper(void);
static void plisql_pop_compile_global_proper(void);


/*
 * find var,type,func in package specifiction
 *
 */
void *
plisql_package_parse(ParseState *parsestate, PackageCacheItem *item, List *names,
							int name_start, package_parse_flags flags,
							Oid *basetypeid,
							int *entry_type,
							List **fargs, /* return value */
							List *fargnames,
							int nargs,
							Oid *argtypes,
							bool expand_variadic,
							bool expand_defaults,
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
	int list_size;
	char *parse_first_name;
	PLiSQL_package *psource;
	PLiSQL_nsitem *nse;
	void *value = NULL;

	Assert(item != NULL && item->source != NULL);

	psource = (PLiSQL_package *) item->source;

	list_size = list_length(names);
	Assert(name_start < list_size);

	parse_first_name = strVal(list_nth(names, name_start));

	nse = plisql_ns_lookup(psource->special_cur, true,
									parse_first_name, NULL, NULL,
									NULL);
	if (nse == NULL)
	{
		if (!missing_ok)
			elog(ERROR, "\"%s\" doesn't exist in package \"%s\"", parse_first_name,
			psource->source.fn_signature);
		return value;
	}

	/* support cursor%isopen notfound found rowcount */
	if (nse->itemtype == PLISQL_NSTYPE_VAR && list_size != name_start + 1)
	{
		PLiSQL_var *var = (PLiSQL_var *) psource->source.datums[nse->itemno];
		char *lastname = strVal(list_nth(names, list_size - 1));

		if (flags == PACKAGE_PARSE_VAR && list_size == name_start + 2 &&
			(var->datatype->typoid == REFCURSOROID) &&
			(strcmp(lastname, "isopen") == 0 ||
			strcmp(lastname, "found") == 0 ||
			strcmp(lastname, "notfound") == 0 ||
			strcmp(lastname, "rowcount") == 0))
			return var;

		elog(ERROR, "\"%s\" is scalar variable", parse_first_name);
	}
	/* only row or record, cursorvar, then name doesn't match */
	else if (nse->itemtype != PLISQL_NSTYPE_REC &&
		list_size != name_start + 1)
		elog(ERROR, "\"%s\" is not a row var", parse_first_name);

	/* not a function or procedure */
	if ((flags == PACKAGE_PARSE_FUNC ||
		flags == PACKAGE_PARSE_PROC) &&
		(nse->itemtype != PLISQL_NSTYPE_SUBPROC_FUNC &&
		nse->itemtype != PLISQL_NSTYPE_SUBPROC_PROC))
		elog(ERROR, "\"%s\" is not a function or procedure", parse_first_name);

	if ((nse->itemtype == PLISQL_NSTYPE_SUBPROC_FUNC ||
		nse->itemtype == PLISQL_NSTYPE_SUBPROC_PROC) &&
		(flags != PACKAGE_PARSE_FUNC &&
		flags != PACKAGE_PARSE_PROC &&
		flags != PACKAGE_PARSE_ENTRY))
		elog(ERROR, "\"%s\" is a function or procedure", parse_first_name);

	switch (nse->itemtype)
	{
		case PLISQL_NSTYPE_VAR:
			{
				PLiSQL_var *var = (PLiSQL_var *) psource->source.datums[nse->itemno];

				if (flags == PACKAGE_PARSE_TYPE)
				{
					if (basetypeid != NULL)
						*basetypeid = var->datatype->typoid;

					value = (void *) var->datatype;
				}
				else if (flags == PACKAGE_PARSE_VAR)
					value = (void *) var;
				else if (flags == PACKAGE_PARSE_ENTRY)
				{
					value = (void *) var;
					*entry_type = PKG_VAR;
				}
			}
			break;
		case PLISQL_NSTYPE_REC:
			{
				PLiSQL_rec *rec = (PLiSQL_rec *) psource->source.datums[nse->itemno];

				if (flags == PACKAGE_PARSE_VAR || flags == PACKAGE_PARSE_ENTRY)
				{
					if (name_start == list_size - 1)
						value = (void *) rec;
					else
						value = (void *) plisql_parse_recvar(&psource->source, rec,
											names, name_start + 1);

					if (flags == PACKAGE_PARSE_ENTRY)
						*entry_type = PKG_VAR;
				}
				else if (flags == PACKAGE_PARSE_TYPE)
				{
					if (rec->erh == NULL || rec->rectypeid != RECORDOID)
					{
						/* Report variable's declared type */
						if (basetypeid != NULL)
							*basetypeid = rec->rectypeid;
					}
					else
					{
						/* Report record's actual type if declared RECORD */
						if (basetypeid != NULL)
							*basetypeid = rec->erh->er_typeid;
					}
					value = (void *) rec->datatype;
				}
				else
					elog(ERROR, "\"%s\" is a record", parse_first_name);
			}
			break;
		case PLISQL_NSTYPE_SUBPROC_FUNC:
		case PLISQL_NSTYPE_SUBPROC_PROC:
			{
				if (flags == PACKAGE_PARSE_FUNC ||
					flags == PACKAGE_PARSE_PROC)
				{
					FuncDetailCode detail;

					detail = plisql_get_subprocfunc_detail(parsestate,
														&psource->source,
														nse, parse_first_name,
														fargs, /* return value */
														flags == PACKAGE_PARSE_FUNC ? false : true,
														fargnames,
														nargs,
														argtypes,
														funcid,	/* return value */
														rettype,	/* return value */
														retset,	/* return value */
														nvargs,	/* return value */
														vatype,	/* return value */
														true_typeids, /* return value */
														argdefaults); /* return value */

					if (detail != FUNCDETAIL_NORMAL &&
						detail != FUNCDETAIL_PROCEDURE)
						elog(ERROR, "wrong number or types of arguments in call to \"%s\"", parse_first_name);

					*pfunc = (void *) &psource->source;
					value = (void *) detail;
				}
			}
			break;
		default:
			elog(ERROR, "package doesn't support this nstype :%u", nse->itemtype);
			break;
	}

	return value;
}


/*
 * according to names to find rec fileds'var
 * like recvar.xxx1
 */
static PLiSQL_datum *
plisql_parse_recvar(PLiSQL_function *func,
						PLiSQL_rec *rec, List *names,
						int match_start_loc)
{
	int list_size;
	int i;
	char *parse_name;

	list_size = list_length(names);
	Assert(match_start_loc < list_size);

	parse_name = strVal(list_nth(names, match_start_loc));

	i = rec->firstfield;
	while (i >= 0)
	{
		PLiSQL_recfield *fld = (PLiSQL_recfield *) func->datums[i];

		Assert(fld->dtype == PLISQL_DTYPE_RECFIELD &&
			   fld->recparentno == rec->dno);
		if (strcmp(fld->fieldname, parse_name) == 0)
		{
			if (match_start_loc == list_size - 1)
				return (PLiSQL_datum *) fld;
			else
				elog(ERROR, "\"%s\" is not a recfield var and doesn't support recfield.xx",
						parse_name);
		}
		i = fld->nextfield;
	}

	elog(ERROR, "\"%s\" doesn't in record var \"%s\"", parse_name,
								rec->refname);
	return NULL;
}


/*
 * find type of a package'var
 */
static PLiSQL_type *
plisql_get_package_datum_rowtype(const char *typename, PLiSQL_function *func,
											PLiSQL_datum *datum, int localvarno,
											parse_pkgtype_flag flag)
{
	switch (datum->dtype)
	{
		case PLISQL_DTYPE_VAR:
			{
				PLiSQL_var *var = (PLiSQL_var *) datum;

				if (flag == parse_by_var_type)
					return var->datatype;
			}
			break;
		case PLISQL_DTYPE_REC:
			{
				PLiSQL_rec *rec = (PLiSQL_rec *) datum;

				if (rec->datatype != NULL)
					return rec->datatype;
				else
					elog(ERROR, "\"%s\" is a record", typename);
			}
			break;
		case PLISQL_DTYPE_PACKAGE_DATUM:
			{
				PLiSQL_pkg_datum *pkgdatum = (PLiSQL_pkg_datum *) datum;
				PLiSQL_package *psource = (PLiSQL_package *) pkgdatum->item->source;
				PLiSQL_function *function = (PLiSQL_function *) &psource->source;

				return plisql_get_package_datum_rowtype(typename, function,
												pkgdatum->pkgvar,
												localvarno, flag);
			}
			break;
		case PLISQL_DTYPE_RECFIELD:
			{
				PLiSQL_recfield *recfield = (PLiSQL_recfield *) datum;
				PLiSQL_rec *rec = (PLiSQL_rec *) func->datums[recfield->recparentno];
				TupleDesc tupdesc;
				int i;

				if (rec->erh != NULL)
					tupdesc = expanded_record_get_tupdesc(rec->erh);
				else
					tupdesc = get_plisql_rec_tupdesc(rec);

				if (tupdesc == NULL)
					elog(ERROR, "recvar \"%s\" is has not tupdesc", rec->refname);

				for (i = 0; i < tupdesc->natts; i++)
				{
					Form_pg_attribute attr = TupleDescAttr(tupdesc, i);

					if (namestrcmp(&attr->attname, recfield->fieldname) == 0 &&
						!attr->attisdropped)
					{
						return plisql_build_datatype(attr->atttypid, attr->atttypmod,
													attr->attcollation, NULL);
					}
				}
				elog(ERROR, "record \"%s\" has no filed \"%s\"",
							rec->refname, recfield->fieldname);
			}
			break;
		default:
			elog(ERROR, "unrecognized data type: %d", datum->dtype);
			break;
	}

	return NULL;
}


/*
 * when we delete a package cache, we use this
 * function to free its package_function
 */
void
plisql_free_package_function(PackageCacheItem *items)
{
	PLiSQL_package *psources = (PLiSQL_package *) items->source;
	List *funclist = NIL;
	ListCell *lc;
	List	*itemlist = list_make1(items);

	Assert(psources->source.use_count >= 0);

	/*
	 * when a function or package references this package
	 *
	 * we get its PLQL_function address
	 */
	plisql_get_package_depends(&psources->source, &funclist, &itemlist);

	itemlist = plisql_package_sort(itemlist);
	foreach (lc, itemlist)
	{
		PackageCacheItem *item = (PackageCacheItem *) lfirst(lc);

		PackageCacheDelete(&item->pkey);
		/*
		 * set it to true, so that delete_function
		 * doesn't free package memory
		 */
		item->intable = true;
	}

	/* remove depends funcs*/
	foreach (lc, funclist)
	{
		PLiSQL_function *dfunc = (PLiSQL_function *) lfirst(lc);

		/* remove function */
		elog(DEBUG1, "realy free function %u", dfunc->fn_oid);
		delete_function(dfunc);
	}

	/* free packages */
	foreach (lc, itemlist)
	{
		PackageCacheItem *item = (PackageCacheItem *) lfirst(lc);
		PLiSQL_package *psource = (PLiSQL_package *) item->source;
		Oid pkgoid = item->pkey;

		/* finally free itself */
		if (psource->source.use_count == 0)
		{
			elog(DEBUG1, "realy free package %u start", pkgoid);
			plisql_free_function_memory(&psource->source, 0, 0);
			elog(DEBUG1, "realy free package %u end", pkgoid);
		}
		else
		{
			elog(DEBUG1, "resolve package %u interdependence", pkgoid);
			resolve_package_interdependence(item, itemlist, lnext(itemlist, lc));
			if (psource->source.use_count == 0)
			{
				elog(DEBUG1, "realy free package %u start", pkgoid);
				plisql_free_function_memory(&psource->source, 0, 0);
				elog(DEBUG1, "realy free package %u end", pkgoid);
			}
			else
			{
				/*
				 * there, some function reference it, we only set intable
				 * to false, so that it can be freed when function is freed
				 */
				item->intable = false;
			}
		}
	}

	return;
}


/*
 * free list of packages
 * used by discard package
 * must make sure package in the pkglist
 * has been delete from PackageCache
 */
void
plisql_free_packagelist(List *pkglist)
{
	ListCell *lc;
	PLiSQL_package *psource;
	PackageCacheItem *item;
	List *funclist = NIL;
	List *dfunclist = NIL;
	PLiSQL_function *dfunc = NULL;


	pkglist = plisql_package_sort(pkglist);


	/* find function rely on package */
	foreach (lc, pkglist)
	{
		ListCell *llc;
		List *itemlist = NIL;

		item = (PackageCacheItem *) lfirst(lc);

		psource = (PLiSQL_package *) item->source;


		itemlist = list_make1(item);
		plisql_get_package_depends(&psource->source, &funclist, &itemlist);
		list_free(itemlist);

		foreach (llc, funclist)
		{
			dfunc = (PLiSQL_function *) lfirst(llc);

			Assert(dfunc->item == NULL);
			dfunclist = list_append_unique(dfunclist, dfunc);
		}
		list_free(funclist);
		funclist = NIL;
	}

	foreach (lc, pkglist)
	{
		PackageCacheItem *my_item = (PackageCacheItem *) lfirst(lc);

		PackageCacheDelete(&my_item->pkey);
		/* set to true, so that not reference free */
		my_item->intable = true;
	}

	/* first delete functions */
	foreach (lc, dfunclist)
	{
		dfunc = (PLiSQL_function *) lfirst(lc);

		elog(DEBUG1, "realy free function %u", dfunc->fn_oid);
		delete_function(dfunc);
	}

	/* second delete packages */
	foreach (lc, pkglist)
	{
		Oid pkgoid;

		item = (PackageCacheItem *) lfirst(lc);
		pkgoid = item->pkey;

		psource = (PLiSQL_package *) item->source;

		/* finally free itself */
		if (psource->source.use_count == 0)
		{
			elog(DEBUG1, "realy free package %u start", pkgoid);
			plisql_free_function_memory(&psource->source, 0, 0);
			elog(DEBUG1, "realy free package %u end", pkgoid);
		}
		else
		{
			elog(DEBUG1, "resolve package %u interdependence", pkgoid);
			resolve_package_interdependence(item, pkglist, lnext(pkglist, lc));
			if (psource->source.use_count == 0)
			{
				elog(DEBUG1, "realy free package %u start", pkgoid);
				plisql_free_function_memory(&psource->source, 0, 0);
				elog(DEBUG1, "realy free package %u end", pkgoid);
			}
			else
				item->intable = false;
		}
	}
}



/*
 * package has references, we should sort it
 */
static List *
plisql_package_sort(List *pkglist)
{
	int origin_len;
	List *result = NIL;
	List *retlist = NIL;
	ListCell *lc;
	PackageCacheItem *item;
	PLiSQL_package *psource;
	PLiSQL_function *func;
	int i;

	origin_len = list_length(pkglist);

	/* loop utils pkglist is null */
	while (list_length(pkglist) != 0)
	{
		bool add = false;
		List *delete_list = NIL;

		for (lc = list_head(pkglist); lc != NULL;)
		{
			ListCell *llc;

			item = (PackageCacheItem *) lfirst(lc);
			psource = (PLiSQL_package *) item->source;
			func = &psource->source;

			/* add all rely on result */
			foreach (llc, func->pkgcachelist)
			{
				PackageCacheItem *litem = (PackageCacheItem *) lfirst(llc);

				if (!list_member_ptr(result, litem))
					break;
			}

			if (llc == NULL)
			{
				add = true;
				result = list_append_unique(result, item);
				delete_list = list_append_unique(delete_list, item);
			}
			lc = lnext(pkglist, lc);
		}
		if (delete_list != NIL)
		{
			pkglist = list_difference(pkglist, delete_list);
			list_free(delete_list);
		}
		if (!add)
		{
			result = list_union(result, pkglist);
			break;
		}
	}
	Assert(list_length(result) == origin_len);

	/* finially, we reorder it */
	for(i = origin_len - 1; i >= 0; i--)
		retlist = lappend(retlist, list_nth(result, i));

	list_free(result);

	return retlist;
}


/*
 * package maybe interdependence each other
 * like pkg1->pkg2 and pkg2->pkg1
 */
static void
resolve_package_interdependence(PackageCacheItem *item,
											List *itemlist,
											ListCell *itemcell)
{
	ListCell *tmp = itemcell;

	while (tmp != NULL)
	{
		PackageCacheItem *itemtmp = (PackageCacheItem *) lfirst(tmp);
		ListCell *lc = NULL;
		PLiSQL_package *psource = (PLiSQL_package *) itemtmp->source;
		List *remove_item = NIL;

		foreach (lc, psource->source.pkgcachelist)
		{
			PackageCacheItem *itemtmp1 = (PackageCacheItem *) lfirst(lc);

			if (itemtmp1->pkey == item->pkey)
			{
				plisql_remove_function_references(&psource->source, itemtmp1);
				remove_item = lappend(remove_item, itemtmp1);
			}
		}
		foreach (lc, remove_item)
		{
			psource->source.pkgcachelist = list_delete_ptr(
											psource->source.pkgcachelist,
											lfirst(lc));
		}
		list_free(remove_item);
		tmp = lnext(itemlist, tmp);
	}
}



/*
 * find refernce function or package depands this functions
 *
 * split package deplist and function deplist, so that we can
 * handle package rely on each other
 *
 */
static void
plisql_get_package_depends(PLiSQL_function *func, List **funclist,
					List **itemlist)
{
	ListCell *lc;
	bool	iscompiling = false;
	int i;

	foreach (lc, func->funclist)
	{
		PLiSQL_function *funcs = (PLiSQL_function *) lfirst(lc);

		iscompiling = false;

		/*
		 * if funcs is compiling, we doesn't free its memory, this
		 * situation like this:
		 * when a package is invalid, and we compile a anonymouns and it
		 * references packages'type first, we add relationships, and later
		 * we reference packages'var, then we find package is invalid,
		 * and free package memory, then we must not free this anonymous
		 * memory context, because it may be used later.
		 */
		for (i = 0; i < plisql_curr_global_proper_level; i++)
		{
			if (plisql_saved_compile_proper[i].plisql_saved_compile[0] == funcs)
			{
				iscompiling = true;
				break;
			}
		}
		if (iscompiling)
			continue;

		if (funcs->item != NULL)
		{
			if (!list_member_ptr(*itemlist, (void *) funcs->item))
			{
				*itemlist = list_append_unique(*itemlist, funcs->item);
				plisql_get_package_depends(funcs, funclist, itemlist);
			}
			continue;
		}
		*funclist = list_append_unique(*funclist, funcs);
	}
	return;
}



/*
 * when compile a package body
 * we should init its specification
 */
static void
package_body_init(PLiSQL_package *source)
{
	PLiSQL_function *pfunction = &source->source;
	int i;

	/* init ns */
	plisql_set_ns(source->special_cur);

	/* init datums use origin function */
	for (i = 0; i < pfunction->ndatums; i++)
		plisql_adddatum(pfunction->datums[i]);
	Assert(pfunction->ndatums == plisql_nDatums);

	/* init subprocfunc use origin function */
	for (i = 0; i < pfunction->nsubprocfuncs; i++)
		plisql_add_subproc_function(pfunction->subprocfuncs[i]);
	Assert(pfunction->nsubprocfuncs == plisql_nsubprocFuncs);

	/* remove the last return stmt */
	if (pfunction->action->body != NIL &&
		((PLiSQL_stmt *) llast(pfunction->action->body))->cmd_type == PLISQL_STMT_RETURN)
	{
		PLiSQL_stmt *stmt = llast(pfunction->action->body);
		pfunction->action->body = list_delete_last(pfunction->action->body);
		pfree(stmt);
	}

	plisql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;

	return;
}




/*
 * do compile for a package body
 */
static void
package_body_doCompile(HeapTuple pkgbodyTup,
								PackageCacheItem *item,
								bool forValidator)
{
	Datum		pkgbodydatum;
	Form_pg_package_body bodyStruct = (Form_pg_package_body) GETSTRUCT(pkgbodyTup);
	bool		isnull;
	char	   *body_source;
	ErrorContextCallback plerrcontext;
	PLiSQL_function *function;
	int			parse_rc;
	PLiSQL_package *psource;
	Oid 		define_useid = InvalidOid;
	Oid 		save_userid;
	int 		save_sec_context;
	Oid		current_user = GetUserId();
	HeapTuple	pkgTup;
	Form_pg_package pkgStruct;


	/*
	 * Setup the scanner input and error info.  We assume that this package
	 * cannot be invoked recursively, so there's no need to save and restore
	 * the static variables used here.
	 */
	pkgbodydatum = SysCacheGetAttr(PKGBODYOID, pkgbodyTup,
								  Anum_pg_package_body_bodysrc, &isnull);
	if (isnull)
		elog(ERROR, "null bodysrc");
	body_source = TextDatumGetCString(pkgbodydatum);
	plisql_scanner_init(body_source);

	item->body_hash_value = GetSysCacheHashValue1(PKGBODYOID,
									ObjectIdGetDatum(bodyStruct->oid));
	psource = (PLiSQL_package *) item->source;
	function = &psource->source;

	/* append package namespace */
	pkgTup = SearchSysCache1(PKGOID, ObjectIdGetDatum(item->pkey));
	if (!HeapTupleIsValid(pkgTup))
		elog(ERROR, "cache lookup failed for package %u", item->pkey);

	pkgStruct = (Form_pg_package) GETSTRUCT(pkgTup);

	if (current_user != pkgStruct->pkgowner)
	{
		define_useid = pkgStruct->pkgowner;
		GetUserIdAndSecContext(&save_userid, &save_sec_context);

		SetUserIdAndSecContext(define_useid,
					save_sec_context | SECURITY_LOCAL_USERID_CHANGE);
	}
	ReleaseSysCache(pkgTup);

	plisql_error_funcname = pstrdup(function->fn_signature);


	/*
	 * Setup error traceback support for ereport()
	 */
	plerrcontext.callback = plisql_compile_package_error_callback;
	plerrcontext.arg = forValidator ? body_source : NULL;
	plerrcontext.previous = error_context_stack;
	error_context_stack = &plerrcontext;

	/*
	 * Do extra syntax checks when validating the package definition. We skip
	 * this when actually compiling functions for execution, for performance
	 * reasons.
	 */
	plisql_check_syntax = forValidator;

	plisql_compile_tmp_cxt = MemoryContextSwitchTo(function->fn_cxt);

	plisql_curr_compile = (PLiSQL_function *) function;

	/* init datums */
	plisql_start_datums();
	cur_compile_func_level = 0;
	plisql_start_subproc_func();
	plisql_saved_compile[cur_compile_func_level] = function;

	package_body_init(psource);

	plisql_compile_packageitem = psource;

	PG_TRY();
	{
		/*
		 * Now parse the function's text
		 */
		parse_rc = plisql_yyparse();
		if (parse_rc != 0)
			elog(ERROR, "plsql parser returned %d", parse_rc);

		/* append body to package struct */
		psource->source.action->body = lappend(psource->source.action->body,
							plisql_parse_result);
	}
	PG_CATCH();
	{
		/*
		 * package body compile failed, we drop package cache at best
		 * because it may affect others packages
		 */
		PackageCacheDelete(&item->pkey);
		plisql_free_package_function(item);
		PG_RE_THROW();
	}
	PG_END_TRY();

	add_dummy_return(&psource->source);

	item->cachestatus = PACKAGE_SET_BODY_FLAG(item->cachestatus);

	plisql_finish_datums(function);
	plisql_finish_subproc_func(function);
	plisql_check_subproc_define(function);

	plisql_scanner_finish();
	pfree(body_source);

	/* Debug dump for completed functions */
	if (plisql_DumpExecTree)
		plisql_dumptree(&psource->source, 0, 0);

	/*
	 * Pop the error context stack
	 */
	error_context_stack = plerrcontext.previous;
	plisql_error_funcname = NULL;

	plisql_check_syntax = false;

	MemoryContextSwitchTo(plisql_compile_tmp_cxt);
	plisql_compile_tmp_cxt = NULL;

	if (OidIsValid(define_useid))
		SetUserIdAndSecContext(save_userid, save_sec_context);
	return;
}



/*
 * do compile for a package
 */
static PackageCacheItem *
package_doCompile(HeapTuple pkgTup, bool forValidator)
{
	Form_pg_package pkgStruct = (Form_pg_package) GETSTRUCT(pkgTup);
	Datum		pkgdatum;
	bool		isnull;
	char	   *pkg_source;
	ErrorContextCallback plerrcontext;
	MemoryContext pkg_cxt;
	PackageCacheItem *item;
	int			parse_rc;
	PLiSQL_package *psource;
	PackageCacheKey pkey;
	PLiSQL_variable	*var;
	PLiSQL_function *function;
	Oid 		define_useid = InvalidOid;
	Oid 		save_userid;
	int 		save_sec_context;
	Oid			current_user = GetUserId();

	/*
	 * Setup the scanner input and error info.  We assume that this package
	 * cannot be invoked recursively, so there's no need to save and restore
	 * the static variables used here.
	 */
	pkgdatum = SysCacheGetAttr(PKGOID, pkgTup,
								  Anum_pg_package_pkgsrc, &isnull);
	if (isnull)
		elog(ERROR, "null pkgsrc");
	pkg_source = TextDatumGetCString(pkgdatum);
	plisql_scanner_init(pkg_source);

	/*
	 * invoke as define in compiling, we should
	 * switch current user for plsql
	 */
	if(current_user != pkgStruct->pkgowner)
	{
		define_useid = pkgStruct->pkgowner;
		GetUserIdAndSecContext(&save_userid, &save_sec_context);

		SetUserIdAndSecContext(define_useid,
					save_sec_context | SECURITY_LOCAL_USERID_CHANGE);
	}

	plisql_error_funcname = pstrdup(NameStr(pkgStruct->pkgname));

	/*
	 * Setup error traceback support for ereport()
	 */
	plerrcontext.callback = plisql_compile_package_error_callback;
	plerrcontext.arg = forValidator ? pkg_source : NULL;
	plerrcontext.previous = error_context_stack;
	error_context_stack = &plerrcontext;

	/*
	 * Do extra syntax checks when validating the package definition. We skip
	 * this when actually compiling functions for execution, for performance
	 * reasons.
	 */
	plisql_check_syntax = forValidator;

	/*
	 * create the new package item struct
	 * we keep it at PackageCacheContext
	 */
	Assert(PackageCacheContext != NULL);

	/* init a pkg_cxt to saved PackageCacheItem and its package_source */
	pkg_cxt = AllocSetContextCreate(PackageCacheContext,
									"Package context",
									ALLOCSET_DEFAULT_SIZES);
	plisql_compile_tmp_cxt = MemoryContextSwitchTo(pkg_cxt);
	item = (PackageCacheItem *) palloc0(sizeof(PackageCacheItem));
	item->ctxt = pkg_cxt;
	item->intable = false;
	pkey = pkgStruct->oid;
	item->pkey = pkey;
	item->package_hash_value = GetSysCacheHashValue1(PKGOID,
												   ObjectIdGetDatum(pkey));
	psource = (PLiSQL_package *) palloc0(sizeof(PLiSQL_package));

	/* init package source like plsql_function */
	item->source = (void *) psource;
	function = &psource->source;
	function->fn_cxt = pkg_cxt;
	function->fn_signature = pstrdup(NameStr(pkgStruct->pkgname));
	MemoryContextSetIdentifier(pkg_cxt, function->fn_signature);
	function->fn_oid = pkey;
	function->fn_xmin = HeapTupleHeaderGetRawXmin(pkgTup->t_data);
	function->fn_tid = pkgTup->t_self;
	function->out_param_varno = -1; /* set up for no OUT param */
	function->resolve_option = plisql_variable_conflict;
	function->print_strict_params = plisql_print_strict_params;
	/* only promote extra warnings and errors at CREATE FUNCTION time */
	function->extra_warnings = forValidator ? plisql_extra_warnings : 0;
	function->extra_errors = forValidator ? plisql_extra_errors : 0;
	function->nstatements = 0;
	function->requires_procedure_resowner = false;
	function->fn_is_trigger = PLISQL_NOT_TRIGGER;
	function->namelabel = pstrdup(NameStr(pkgStruct->pkgname));
	plisql_compile_packageitem = psource;

	plisql_curr_compile = (PLiSQL_function *) function;
	plisql_curr_compile->item = item;

	/*
	 * Initialize the compiler, particularly the namespace stack.  The
	 * outermost namespace contains function parameters and other special
	 * variables (such as FOUND), and is named after the function itself.
	 */
	plisql_ns_init();
	plisql_ns_push(NameStr(pkgStruct->pkgname), PLISQL_LABEL_BLOCK);
	plisql_DumpExecTree = false;
	plisql_start_datums();
	cur_compile_func_level = 0;
	plisql_start_subproc_func();
	plisql_saved_compile[cur_compile_func_level] = function;
	plisql_IdentifierLookup = IDENTIFIER_LOOKUP_DECLARE;

	/* Remember if function is STABLE/IMMUTABLE */
	function->fn_readonly = false;

	/*
	 * Create the magic FOUND variable.
	 */
	var = plisql_build_variable("found", 0,
								 plisql_build_datatype(BOOLOID,
														-1,
														InvalidOid,
														NULL),
								 true);
	function->found_varno = var->dno;

	PG_TRY();
	{
		/*
		 * Now parse the function's text
		 */
		parse_rc = plisql_yyparse();
		if (parse_rc != 0)
			elog(ERROR, "plisql parser returned %d", parse_rc);
		function->action = plisql_parse_result;

		plisql_scanner_finish();
		pfree(pkg_source);
	}
	PG_CATCH();
	{
		plisql_free_package_function(item);
		PG_RE_THROW();
	}
	PG_END_TRY();

	/*
	 * Complete the function's info
	 */
	function->fn_nargs = 0;

	add_dummy_return(function);

	psource->finish_compile_special = true;
	plisql_finish_datums(function);

	psource->last_specialfno = plisql_nsubprocFuncs;
	plisql_finish_subproc_func(function);

	/* Debug dump for completed functions */
	if (plisql_DumpExecTree)
		plisql_dumptree(function, 0, 0);

	/*
	 * Pop the error context stack
	 */
	error_context_stack = plerrcontext.previous;
	plisql_error_funcname = NULL;

	plisql_check_syntax = false;

	MemoryContextSwitchTo(plisql_compile_tmp_cxt);
	plisql_compile_tmp_cxt = NULL;

	/* set package status */
	item->cachestatus = 0;

	if (OidIsValid(define_useid))
		SetUserIdAndSecContext(save_userid, save_sec_context);

	/*
	 * create package, we doesn't push it
	 * to the cache, because create package will
	 * send invalid message to all backends, which
	 * will result this build invalid, next referencing,
	 * it will rebuild, that is a problem, if we first
	 * references a package type and later references its
	 * function, when we references its type, we doesn't check
	 * its body status, and get the address of type, but
	 * when we references its func, we check its body, then
	 * find its body is invalid, then we rebuild package, it
	 * will result previous type address is freed.
	 * it is no problem for not creating, because we will report
	 * package rebuilding error for not forvalid
	 */
	if (!forValidator)
		PackageCacheInsert(&pkey, item);

	return item;
}


/*
 * compile a package
 */
static PackageCacheItem*
plisql_package_compile(Oid pkgoid,
								bool forValidator,
								bool execcheck)
{
	HeapTuple pkgTup;
	PackageCacheItem *item;
	PackageCacheKey pkey;
	bool	package_valid = false;
	PLiSQL_package_status oldstatus = PLISQL_PACKAGE_NO_STATUS;

	/*
	 * Lookup the pg_package tuple by Oid
	 */
	pkgTup = SearchSysCache1(PKGOID, ObjectIdGetDatum(pkgoid));
	if (!HeapTupleIsValid(pkgTup))
		elog(ERROR, "cache lookup failed for package %u", pkgoid);

	/* getpackage cache */
	pkey = pkgoid;

	item = PackageCacheLookup(&pkey);
	if (item != NULL)
	{
		/* see cache is valid */
		if (!forValidator && !PACKAGE_SPECIFICATION_IS_UPDATED(item->cachestatus))
			package_valid = true;
		else
		{
			PackageCacheItem *olditem = NULL;

			olditem = PackageCacheDelete(&pkey);
			if (olditem != NULL)
			{
				PLiSQL_package *oldpsource = (PLiSQL_package *) olditem->source;

				oldstatus = oldpsource->status;
				plisql_free_package_function(olditem);
			}
		}
	}

	/* no valid */
	if (!package_valid)
	{
		PLiSQL_package *newpsource;

		item = package_doCompile(pkgTup, forValidator);
		newpsource = (PLiSQL_package *) item->source;

		/*
		 * new status has status and old has status
		 * we should set package has rebuild
		 */
		if (execcheck)
			newpsource->status = PLISQL_PACKAGE_REBUILD;
		else if (!forValidator &&
			newpsource->status == PLISQL_PACKAGE_NO_INIT &&
			(oldstatus == PLISQL_PACKAGE_STATUSED))
			newpsource->status = PLISQL_PACKAGE_REBUILD;
	}

	ReleaseSysCache(pkgTup);

	return item;
}


/*
 * compile a package body
 */
static PackageCacheItem *
plisql_package_body_compile(Oid bodyoid,
										bool forValidator,
										bool execheck)
{
	HeapTuple pkgTup;
	HeapTuple pkgbodyTup;
	PackageCacheItem *item;
	PackageCacheItem *olditem;
	PackageCacheKey pkey;
	Form_pg_package_body pkgbodyStruct;
	Oid pkgoid;
	bool	package_valid = true;
	bool	package_body_valid = true;
	PLiSQL_package *newpsource;

	/*
	 * Lookup the pg_package_body tuple by Oid
	 */
	pkgbodyTup = SearchSysCache1(PKGBODYOID, ObjectIdGetDatum(bodyoid));
	if (!HeapTupleIsValid(pkgbodyTup))
		elog(ERROR, "cache lookup failed for package body %u", bodyoid);

	pkgbodyStruct = (Form_pg_package_body) GETSTRUCT(pkgbodyTup);
	pkgoid = pkgbodyStruct->pkgoid;

	/*
	 * Lookup the ora_package tuple by Oid
	 */
	pkgTup = SearchSysCache1(PKGOID, ObjectIdGetDatum(pkgoid));
	if (!HeapTupleIsValid(pkgTup))
		elog(ERROR, "cache lookup failed for package %u", pkgoid);

	/* get	package cache */
	pkey = pkgoid;

	item = PackageCacheLookup(&pkey);
	if (item != NULL)
	{
		/* see package cache is valid */
		if (forValidator || PACKAGE_SPECIFICATION_IS_UPDATED(item->cachestatus))
			package_valid = false;

		if (forValidator || PACKAGE_BODY_IS_UPDATED(item->cachestatus))
			package_body_valid = false;
	}
	else
	{
		package_valid = false;
	}

	if (!package_body_valid || !package_valid)
	{
		bool	hasbody = false;
		PLiSQL_package_status oldstatus = PLISQL_PACKAGE_NO_STATUS;

		/* body rely on package, so we rebuild package at best */
		olditem = PackageCacheDelete(&pkey);
		if (olditem != NULL)
		{
			PLiSQL_package *oldpsource = (PLiSQL_package *) olditem->source;

			hasbody = (bool) PACKAGE_HAS_BODY(olditem->cachestatus);
			oldstatus = oldpsource->status;
			plisql_free_package_function(olditem);
		}

		item = package_doCompile(pkgTup, forValidator);
		newpsource = (PLiSQL_package *) item->source;

		/*
		 * if package rebuild, we set its status to
		 * PLSQL_PACKAGE_REBUILD when meeting the following
		 * conditions:
		 * 1) package or body doesn't replace by this session
		 * 2) new package has status
		 * 3) previous has been init
		 * 4) doesn't create a package body
		 */
		if (execheck)
			newpsource->status = PLISQL_PACKAGE_REBUILD;
		else if (!forValidator &&
			newpsource->status == PLISQL_PACKAGE_NO_INIT &&
			oldstatus == PLISQL_PACKAGE_STATUSED &&
			hasbody)
			newpsource->status = PLISQL_PACKAGE_REBUILD;
	}
	/* package body has been compile */
	else if (PACKAGE_HAS_BODY(item->cachestatus))
		goto finish;

	package_body_doCompile(pkgbodyTup, item, forValidator);

	/* if we rebuild body, we should re init */
	newpsource = (PLiSQL_package *) item->source;
	if (newpsource->status == PLISQL_PACKAGE_INIT ||
		newpsource->status == PLISQL_PACKAGE_STATUSED)
		newpsource->status = PLISQL_PACKAGE_NO_INIT;

finish:
	ReleaseSysCache(pkgTup);
	ReleaseSysCache(pkgbodyTup);

	return item;

}


/*
 * like plisql_call_handler
 *
 * if package has a init block, when we first
 * references to a var or function, we should
 * init a block
 */
static void
plisql_exec_package_init(FunctionCallInfo fcinfo, PLiSQL_function *func)
{
	bool		nonatomic;
	PLiSQL_execstate *save_cur_estate;
	ResourceOwner procedure_resowner;
	int			rc;
	Oid 		define_useid = InvalidOid;
	Oid 		save_userid;
	int 		save_sec_context;
	HeapTuple	pkgTup;
	Form_pg_package pkgStruct;
	Oid			current_user = GetUserId();

	nonatomic = fcinfo->context &&
		IsA(fcinfo->context, CallContext) &&
		!castNode(CallContext, fcinfo->context)->atomic;

	/*
	 * Connect to SPI manager
	 */
	if ((rc = SPI_connect_ext(nonatomic ? SPI_OPT_NONATOMIC : 0)) != SPI_OK_CONNECT)
		elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(rc));


	/* Begin - SRS-PLSQL-SUBPROC */
	/* rember current func in SPI */
	SPI_remember_func(func);
	/* End - SRS-PLSQL-SUBPROC */

	/*
	 * check wether invoke define, we should
	 * switch current user for package init
	 */
	pkgTup = SearchSysCache1(PKGOID, ObjectIdGetDatum(func->item->pkey));
	if (!HeapTupleIsValid(pkgTup))
		elog(ERROR, "cache lookup failed for package %u", func->item->pkey);

	pkgStruct = (Form_pg_package) GETSTRUCT(pkgTup);
	if (pkgStruct->define_invok &&
		current_user != pkgStruct->pkgowner)
		define_useid = pkgStruct->pkgowner;
	ReleaseSysCache(pkgTup);

	if (OidIsValid(define_useid))
	{
		GetUserIdAndSecContext(&save_userid, &save_sec_context);

		SetUserIdAndSecContext(define_useid,
							save_sec_context | SECURITY_LOCAL_USERID_CHANGE);
	}

	/* Must save and restore prior value of cur_estate */
	save_cur_estate = func->cur_estate;

	/* Mark the function as busy, so it can't be deleted from under us */
	func->use_count++;

	/*
	 * If we'll need a procedure-lifespan resowner to execute any CALL or DO
	 * statements, create it now.  Since this resowner is not tied to any
	 * parent, failing to free it would result in process-lifespan leaks.
	 * Therefore, be very wary of adding any code between here and the PG_TRY
	 * block.
	 */
	procedure_resowner =
		(nonatomic && func->requires_procedure_resowner) ?
		ResourceOwnerCreate(NULL, "PL/iSQL procedure resources") : NULL;

	PG_TRY();
	{
		plisql_exec_function(func, fcinfo,
									NULL, NULL,
									procedure_resowner,
									!nonatomic);
	}
	PG_FINALLY();
	{
		/* Decrement use-count, restore cur_estate */
		func->use_count--;
		func->cur_estate = save_cur_estate;

		/* Be sure to release the procedure resowner if any */
		if (procedure_resowner)
		{
			ReleaseAllPlanCacheRefsInOwner(procedure_resowner);
			ResourceOwnerDelete(procedure_resowner);
		}

		if (OidIsValid(define_useid))
			SetUserIdAndSecContext(save_userid, save_sec_context);
	}
	PG_END_TRY();

	/*
	 * Disconnect from SPI manager
	 */
	if ((rc = SPI_finish()) != SPI_OK_FINISH)
		elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(rc));
	return;
}


/*
 * when referencing to package'var and func
 * we first check package'status
 */
static void
plisql_check_package_status(PLiSQL_execstate *estate,
									PLiSQL_pkg_datum *pkgdatum)
{
	bool isconst = false;
	PLiSQL_package *newpsource;

	/*
	 * if package has status and if first referencing to var or function, we
	 * should init its status and invok init function
	 */
	Assert(pkgdatum->dtype == PLISQL_DTYPE_PACKAGE_DATUM);

	isconst = is_const_datum(estate, (PLiSQL_datum *) pkgdatum);

	/*
	 * there, if package no valid or has no body
	 * we should compile package body
	 */
	if (!isconst &&
		(!PackageCacheIsValid(&pkgdatum->item->pkey, false) ||
		!PACKAGE_HAS_BODY(pkgdatum->item->cachestatus)))
	{
		/*
		 * we should build package body
		 */
		PackageCacheItem *newitem;
		Oid bodyoid = get_package_bodyid(pkgdatum->item->pkey, true);

		if (OidIsValid(bodyoid))
			newitem = plisql_package_body_compile(bodyoid, false, true);
		else
			newitem = plisql_package_compile(pkgdatum->item->pkey, false, true);

		newpsource = (PLiSQL_package *) newitem->source;

		if (newpsource->status == PLISQL_PACKAGE_REBUILD ||
			newpsource->status  == PLISQL_PACKAGE_REBUILD_INIT)
		{
			newpsource->status = PLISQL_PACKAGE_NO_INIT;
			elog(ERROR, "existing state of packages has been discarded");
		}
	}
	else
	{
		newpsource = (PLiSQL_package *) pkgdatum->item->source;
	}

	Assert(newpsource == pkgdatum->item->source);
	if (newpsource->status == PLISQL_PACKAGE_NO_INIT ||
		newpsource->status == PLISQL_PACKAGE_NO_STATUS ||
		newpsource->status == PLISQL_PACKAGE_REBUILD)
	{
		LOCAL_FCINFO(fake_fcinfo, 0);
		FmgrInfo	flinfo;

		/*
		 * Set up a fake fcinfo with just enough info to satisfy
		 * plisql_compile().
		 */
		MemSet(fake_fcinfo, 0, SizeForFunctionCallInfo(0));
		MemSet(&flinfo, 0, sizeof(flinfo));
		fake_fcinfo->flinfo = &flinfo;
		flinfo.fn_oid = InvalidOid;
		flinfo.fn_mcxt = CurrentMemoryContext;

		plisql_exec_package_init(fake_fcinfo, &newpsource->source);
		if (newpsource->status == PLISQL_PACKAGE_NO_INIT)
			newpsource->status = PLISQL_PACKAGE_INIT;
		else if (newpsource->status == PLISQL_PACKAGE_NO_STATUS)
			newpsource->status = PLISQL_PACKAGE_NO_STATUS_INIT;
		else
			newpsource->status = PLISQL_PACKAGE_REBUILD_INIT;
	}

	/*
	 * accessed by var not const
	 */
	if (!isconst && newpsource->status == PLISQL_PACKAGE_INIT)
		newpsource->status = PLISQL_PACKAGE_STATUSED;

	return;
}


/*
 * internel function to check subproc wether has define
 */
static void
plisql_check_subproc_define_recurse(PLiSQL_function *function, List **already_checks)
{
	int i;

	for (i = 0; i < function->nsubprocfuncs; i++)
	{
		PLiSQL_subproc_function *subproc = function->subprocfuncs[i];

		if (list_member_ptr(*already_checks, subproc))
			continue;

		if (subproc->function->action == NULL)
		{
			if (subproc->function->item != NULL)
			{
				int j;
				PLiSQL_package *psource = (PLiSQL_package *) subproc->function->item->source;

				for (j = 0; j < psource->last_specialfno; j++)
				{
					if (subproc == psource->source.subprocfuncs[j])
						ereport(ERROR,
							(errcode(ERRCODE_DATA_EXCEPTION),
							 errmsg("subprogram or cursor '%s', is declared in a package "
									"specification and must be defined in the package body",
									subproc->func_name)));
				}
			}
			ereport(ERROR,
					(errcode(ERRCODE_DATA_EXCEPTION),
					 errmsg("A subprogram body must be defined for the forward declaration of %s",
					 subproc->func_name),
					 plisql_scanner_errposition(subproc->location)));
		}
		*already_checks = lappend(*already_checks, subproc);
		plisql_check_subproc_define_recurse(subproc->function, already_checks);
	}
}


/*
 * get Tupdesc for record variable
 */
static TupleDesc
get_plisql_rec_tupdesc(PLiSQL_rec *rec)
{
	TypeCacheEntry *typentry;

	/* doesn't consider recordoid and invalidoid */
	if (rec->rectypeid == RECORDOID || !OidIsValid(rec->rectypeid))
		return NULL;

	/*
	 * Consult the typcache to see if it's a domain over composite, and in
	 * any case to get the tupdesc and tupdesc identifier.
	 */
	typentry = lookup_type_cache(rec->rectypeid,
									 TYPECACHE_TUPDESC |
									 TYPECACHE_DOMAIN_BASE_INFO);
	if (typentry->typtype == TYPTYPE_DOMAIN)
	{
		typentry = lookup_type_cache(typentry->domainBaseType,
									 TYPECACHE_TUPDESC);
	}
	if (typentry->tupDesc == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_WRONG_OBJECT_TYPE),
				 errmsg("type %s is not composite",
						format_type_be(rec->rectypeid))));
	return typentry->tupDesc;
}



/*
 * when a function or package referencing a package,
 * we record package'cache in function pkgcachelist, so that
 * when package rebuild or delete, we can set the
 * function or package invalid
 */
static void
plisql_addpackage_references(PLiSQL_function *func,
									PackageCacheItem *item)
{
	List *pkgcachelist = func->pkgcachelist;
	MemoryContext old;

	/*
	 * if package reference its self like schema.pkg.xxx
	 * we must not add references
	 *
	 * Anonymous Blocks, we must not add because its function
	 * memory is temp
	 */
	if ((func->item == NULL &&
		!OidIsValid(func->fn_oid)) ||
		(func->item != NULL &&
		func->item->pkey == item->pkey))
		return;

	/*
	 * we must make true to alloc in function memory context
	 * so we force to switch to function memory context, some times
	 * it maybe come from plsql_compile_tmp_cxt
	 * for example, when we found pkg.var1%type
	 */
	old = MemoryContextSwitchTo(func->fn_cxt);

	/* append it */
	pkgcachelist = list_append_unique(pkgcachelist, item);
	plisql_addfunction_references(func, item);

	/* recover memory context */
	MemoryContextSwitchTo(old);

	func->pkgcachelist = pkgcachelist;

	return;
}


/*
 * like plsql_build_variable
 * mapping package'var to function locale'var
 */
static PLiSQL_variable *
plisql_build_package_local_variable(const char *refname, int lineno,
												List *idents,
												bool add2namespace,
												bool missing_ok)
{
	PLiSQL_pkg_datum *pkg_datum;
	int i;
	PkgVar *pkgvar;
	MemoryContext old;

	/* first, find this package datums if exists */
	for (i = 0; i < plisql_nDatums; i++)
	{
		PLiSQL_datum *datum = plisql_Datums[i];
		PLiSQL_pkg_datum *tmp_pkg_datum;

		if (datum->dtype != PLISQL_DTYPE_PACKAGE_DATUM)
			continue;
		tmp_pkg_datum = (PLiSQL_pkg_datum *) datum;

		/* compare its refname */
		if (strcmp(tmp_pkg_datum->refname, refname) == 0)
			return (PLiSQL_variable *) tmp_pkg_datum;
	}

	/* may be compile package,  so we use SPI_push */
	old = MemoryContextSwitchTo(plisql_compile_tmp_cxt);
	plisql_push_compile_global_proper();

	/*
	 * we should recover gloval variable when
	 * errors happen
	 */
	PG_TRY();
	{
		pkgvar = LookupPkgVarByvarnames(idents, missing_ok);
	}
	PG_CATCH();
	{
		plisql_pop_compile_global_proper();
		PG_RE_THROW();
	}
	PG_END_TRY();

	plisql_pop_compile_global_proper();
	MemoryContextSwitchTo(old);

	/* not found */
	if (pkgvar == NULL)
		return NULL;

	/*
	 * we must make true to alloc in function memory context
	 * so we force to switch to function memory context, some times
	 * it maybe come from plsql_compile_tmp_cxt
	 * for example, when we found pkg.var1%type
	 */
	old = MemoryContextSwitchTo(plisql_saved_compile[0]->fn_cxt);

	pkg_datum = (PLiSQL_pkg_datum *) palloc(sizeof(PLiSQL_pkg_datum));

	pkg_datum->dtype = PLISQL_DTYPE_PACKAGE_DATUM;
	pkg_datum->lineno = lineno;
	pkg_datum->refname = pstrdup(refname);
	pkg_datum->item = pkgvar->item;
	pkg_datum->pkgvar = (PLiSQL_datum *) pkgvar->value;

	plisql_adddatum((PLiSQL_datum *) pkg_datum);
	if (add2namespace)
		plisql_ns_additem(PLISQL_NSTYPE_VAR,
							pkg_datum->dno,
							refname);

	/* record reference to first level function */
	plisql_addpackage_references(plisql_saved_compile[0],
								pkgvar->item);

	pfree(pkgvar);

	/* recover memory context */
	MemoryContextSwitchTo(old);

	return (PLiSQL_variable *) pkg_datum;
}


/*
 * may be we will compile a package during compile a function or package
 * so we saved some global inforamtions, after we compile, we use
 * pop function to recover
 */
static void
plisql_push_compile_global_proper(void)
{
	int i;
	int neste_level;

	/* init plisql_saved_compile_proper */
	if (plisql_global_proper_alloc == 0)
	{
		MemoryContext old;

		/* use top MemoryContext */
		old = MemoryContextSwitchTo(TopMemoryContext);

		plisql_global_proper_alloc = 8;
		plisql_saved_compile_proper = palloc(sizeof(PLiSQL_compile_global_proper) *
										plisql_global_proper_alloc);
		MemoryContextSwitchTo(old);
	}

	if (plisql_curr_global_proper_level == plisql_global_proper_alloc)
	{
		plisql_global_proper_alloc *= 2;
		plisql_saved_compile_proper = repalloc(plisql_saved_compile_proper,
						sizeof(PLiSQL_compile_global_proper) * plisql_global_proper_alloc);
	}

	/* come from plisql.h */
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_IdentifierLookup = plisql_IdentifierLookup;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_variable_conflict = plisql_variable_conflict;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_print_strict_params = plisql_print_strict_params;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_check_asserts = plisql_check_asserts;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_extra_warnings = plisql_extra_warnings;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_extra_errors = plisql_extra_errors;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_check_syntax = plisql_check_syntax;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_DumpExecTree = plisql_DumpExecTree;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_parse_result = plisql_parse_result;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_nDatums = plisql_nDatums;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_Datums = plisql_Datums;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].datums_last = datums_last;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_error_funcname = plisql_error_funcname;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_curr_compile = plisql_curr_compile;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_compile_tmp_cxt = plisql_compile_tmp_cxt;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].datums_alloc = datums_alloc;

	/* come from pl_subproc_function.h */
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_subprocFuncs = plisql_subprocFuncs;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_nsubprocFuncs = plisql_nsubprocFuncs;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].subprocFuncs_alloc = subprocFuncs_alloc;
	plisql_saved_compile_proper[plisql_curr_global_proper_level].cur_compile_func_level = cur_compile_func_level;
	/*
	 * there, we must make plisql_saved_compile[0] is valid,
	 * because we use ite for some place
	 */
	neste_level = 1;
	if (neste_level < cur_compile_func_level)
		neste_level = cur_compile_func_level;

	for (i = 0; i < neste_level; i++)
	{
		plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_compile[i] = plisql_saved_compile[i];
		plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_datums_last[i] = plisql_saved_datums_last[i];
		plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_error_funcname[i] = plisql_saved_error_funcname[i];
		plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_nsubprocfuncs[i] = plisql_saved_nsubprocfuncs[i];
		plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_subprocfunc_alloc[i] = plisql_saved_subprocfunc_alloc[i];
		plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_subprocfuncs[i] = plisql_saved_subprocfuncs[i];
	}

	/* come from pl_package.h */
	plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_compile_packageitem = plisql_compile_packageitem;

	/* come from pl_scanner.c */
	plisql_saved_compile_proper[plisql_curr_global_proper_level].yylex_data = plisql_get_yylex_global_proper();

	/* come from pl_funcs.c */
	plisql_saved_compile_proper[plisql_curr_global_proper_level].ns_top = plisql_ns_top();

	/* maybe add pl_udttype.h in further */
	plisql_curr_global_proper_level++;

	return;
}


/*
 * pop global compile informations
 */
static void
plisql_pop_compile_global_proper()
{
	int i;
	int neste_level;

	if (plisql_curr_global_proper_level-- < 0)
		elog(ERROR, "compile proper stack wrong");

	/* come from plisql.h */
	plisql_IdentifierLookup = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_IdentifierLookup;
	plisql_variable_conflict = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_variable_conflict;
	plisql_print_strict_params = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_print_strict_params;
	plisql_check_asserts = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_check_asserts;
	plisql_extra_warnings = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_extra_warnings;
	plisql_extra_errors = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_extra_errors;
	plisql_check_syntax = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_check_syntax;
	plisql_DumpExecTree = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_DumpExecTree;
	plisql_parse_result = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_parse_result;
	plisql_nDatums = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_nDatums;
	plisql_Datums = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_Datums;
	datums_last = plisql_saved_compile_proper[plisql_curr_global_proper_level].datums_last;
	plisql_error_funcname = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_error_funcname;
	plisql_curr_compile = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_curr_compile;
	plisql_compile_tmp_cxt = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_compile_tmp_cxt;
	datums_alloc = plisql_saved_compile_proper[plisql_curr_global_proper_level].datums_alloc;

	/* come from pl_subproc_function.h */
	plisql_subprocFuncs = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_subprocFuncs;
	plisql_nsubprocFuncs = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_nsubprocFuncs;
	subprocFuncs_alloc = plisql_saved_compile_proper[plisql_curr_global_proper_level].subprocFuncs_alloc;
	cur_compile_func_level = plisql_saved_compile_proper[plisql_curr_global_proper_level].cur_compile_func_level;
	/*
	 * there, we must make plisql_saved_compile[0] is valid,
	 * because we use ite for some place
	 */
	neste_level = 1;
	if (neste_level < cur_compile_func_level)
		neste_level = cur_compile_func_level;
	for (i = 0; i < neste_level; i++)
	{
		plisql_saved_compile[i] = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_compile[i];
		plisql_saved_datums_last[i] = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_datums_last[i];
		plisql_saved_error_funcname[i] = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_error_funcname[i];
		plisql_saved_nsubprocfuncs[i] = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_nsubprocfuncs[i];
		plisql_saved_subprocfunc_alloc[i] = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_subprocfunc_alloc[i];
		plisql_saved_subprocfuncs[i] = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_saved_subprocfuncs[i];
	}

	/* come from pl_package.h */
	plisql_compile_packageitem = plisql_saved_compile_proper[plisql_curr_global_proper_level].plisql_compile_packageitem;

	/* come from pl_scanner.c */
	plisql_recover_yylex_global_proper(plisql_saved_compile_proper[plisql_curr_global_proper_level].yylex_data);
	pfree(plisql_saved_compile_proper[plisql_curr_global_proper_level].yylex_data);

	/* come from pl_funcs.c */
	plisql_set_ns(plisql_saved_compile_proper[plisql_curr_global_proper_level].ns_top);

	return;
}



/*
 * like plsql_build_package_local_variable
 * but if we found it is a package'type we
 * doesn't raise error, and return a PkgEntry which
 * include it, this is because we support pkg.collect_type()
 * if we found it is a package datum
 * we handle it like plsql_build_package_local_variable
 */
PkgEntry *
plisql_parse_package_entry(const char *refname, int lineno,
						List *idents, bool add2namespace,
						bool missing_ok)
{
	PLiSQL_pkg_datum *pkg_datum;
	int i;
	PkgEntry *pkgentry;
	MemoryContext old;

	/* first, find this package datums if exists */
	for (i = 0; i < plisql_nDatums; i++)
	{
		PLiSQL_datum *datum = plisql_Datums[i];
		PLiSQL_pkg_datum *tmp_pkg_datum;

		if (datum->dtype != PLISQL_DTYPE_PACKAGE_DATUM)
			continue;
		tmp_pkg_datum = (PLiSQL_pkg_datum *) datum;

		/* compare its refname */
		if (strcmp(tmp_pkg_datum->refname, refname) == 0)
		{
			pkgentry = palloc0(sizeof(PkgEntry));

			pkgentry->type = PKG_VAR;
			pkgentry->value = (void *) tmp_pkg_datum;
			return	pkgentry;
		}
	}

	old = MemoryContextSwitchTo(plisql_compile_tmp_cxt);
	plisql_push_compile_global_proper();
	/*
	 *
	 * when errors happend, we should recover
	 * some global variables
	 */
	PG_TRY();
	{
		pkgentry = LookupPkgEntryByTypename(idents, missing_ok);
	}
	PG_CATCH();
	{
		plisql_pop_compile_global_proper();
		PG_RE_THROW();
	}
	PG_END_TRY();

	plisql_pop_compile_global_proper();
	MemoryContextSwitchTo(old);

	/* not found */
	if (pkgentry == NULL)
		return NULL;

	/*
	 * we must make true to alloc in function memory context
	 * so we force to switch to function memory context, some times
	 * it maybe come from plisql_compile_tmp_cxt
	 * for example, when we found pkg.var1%type
	 */
	old = MemoryContextSwitchTo(plisql_saved_compile[0]->fn_cxt);

	/* if we parse a type */
	if (pkgentry->type == PKG_TYPE)
	{
		/* record reference to first level function */
		plisql_addpackage_references(plisql_saved_compile[0],
									pkgentry->item);

		MemoryContextSwitchTo(old);
		return pkgentry;
	}

	Assert(pkgentry->type == PKG_VAR);

	pkg_datum = (PLiSQL_pkg_datum *) palloc(sizeof(PLiSQL_pkg_datum));

	pkg_datum->dtype = PLISQL_DTYPE_PACKAGE_DATUM;
	pkg_datum->lineno = lineno;
	pkg_datum->refname = pstrdup(refname);
	pkg_datum->item = pkgentry->item;
	pkg_datum->pkgvar = (PLiSQL_datum *) pkgentry->value;

	plisql_adddatum((PLiSQL_datum *) pkg_datum);
	if (add2namespace)
		plisql_ns_additem(PLISQL_NSTYPE_VAR,
							pkg_datum->dno,
							refname);

	/* record reference to first level function */
	plisql_addpackage_references(plisql_saved_compile[0],
								pkgentry->item);

	/* recover memory context */
	MemoryContextSwitchTo(old);

	/* replace pkgentry value to new datum */
	pkgentry->value = (void *) pkg_datum;

	return pkgentry;
}


/*
 * find package type
 * flag:  see plsql_package.h
 * we find udt type which define in a package
 */
PLiSQL_type *
plisql_parse_package_type(TypeName *typeName,
									parse_pkgtype_flag flag,
									bool missing_ok)
{
	PLiSQL_type *package_type;
	char	*rawstring;

	Assert(typeName->names != NIL);

	if (list_length(typeName->names) < 2)
		return NULL;

	rawstring = TypeNameToString(typeName);

	if (flag < parse_by_pkg_type)
	{
		PLiSQL_package *psource;
		PLiSQL_function *func;
		PLiSQL_pkg_datum *var;

		var = (PLiSQL_pkg_datum *) plisql_build_package_local_variable(rawstring,
												0,
												typeName->names,
												true,
												missing_ok);
		if (var == NULL)
		{
			pfree(rawstring);
			return NULL;
		}

		psource = (PLiSQL_package *) var->item->source;
		func = (PLiSQL_function *) &psource->source;

		package_type =  plisql_get_package_datum_rowtype(rawstring, func, var->pkgvar,
														var->dno, flag);
	}
	else
	{
		PkgType *pkgtype;
		MemoryContext old;

		/* maybe compile package, so we use SPI_push */
		old = MemoryContextSwitchTo(plisql_compile_tmp_cxt);
		plisql_push_compile_global_proper();
		/*
		 *
		 * when errors happen, we should recover gloabl
		 * variables
		 */
		PG_TRY();
		{
			pkgtype = LookupPkgTypeByTypename(typeName->names, missing_ok);
		}
		PG_CATCH();
		{
			plisql_pop_compile_global_proper();
			pfree(rawstring);
			PG_RE_THROW();
		}
		PG_END_TRY();

		plisql_pop_compile_global_proper();
		MemoryContextSwitchTo(old);

		if (pkgtype == NULL)
		{
			pfree(rawstring);
			return NULL;
		}

		/* record reference to first level function */
		plisql_addpackage_references(plisql_saved_compile[0],
									pkgtype->item);

		package_type = (PLiSQL_type *) pkgtype->value;
		pfree(pkgtype);
	}

	pfree(rawstring);

	return package_type;

}


/*
 * like plisql_get_subproc_func
 * we get func from a package
 */
PLiSQL_function *
plisql_get_package_func(FunctionCallInfo fcinfo, bool forValidator)
{
	PLiSQL_function *pfunc;
	PLiSQL_subproc_function *subprocfunc;
	FuncExpr *funcexpr;
	int	fno;
	PLiSQL_function *func;
	PLiSQL_package *psource;
	PackageCacheItem *item = NULL;

	funcexpr = (FuncExpr *) fcinfo->flinfo->fn_expr;

	Assert(funcexpr->function_from == FUNC_FROM_PACKAGE);

	if (!OidIsValid(funcexpr->pkgoid))
		elog(ERROR, "funcexpr include invalid pkgoid");
	item = PackageCacheLookup(&(funcexpr->pkgoid));
	if (item == NULL)
		elog(ERROR, "package %u cache is not found", funcexpr->pkgoid);
	psource = (PLiSQL_package *) item->source;
	/*
	 * maybe others already rebuild
	 */
	if (psource->status == PLISQL_PACKAGE_REBUILD)
	{
		psource->status = PLISQL_PACKAGE_NO_INIT;
		elog(ERROR, "existing state of packages has been discarded");
	}
	pfunc = &psource->source;

	pfunc = (PLiSQL_function *) funcexpr->parent_func;
	fno = (int) funcexpr->funcid;

	if (pfunc == NULL)
		elog(ERROR, "package funcexpr has no init");

	if (fno < 0 || fno >= pfunc->nsubprocfuncs)
		elog(ERROR, "invalid fno :%d", fno);

	subprocfunc = pfunc->subprocfuncs[fno];

	/*
	 * we should build package body
	 */
	if (!PackageCacheIsValid(&pfunc->item->pkey, true))
	{
		PackageCacheItem *newitem;
		PLiSQL_package *newpsource;
		Oid bodyoid = get_package_bodyid(pfunc->item->pkey, true);

		if (!OidIsValid(bodyoid))
			elog(ERROR, "package \"%s\" has no body", pfunc->fn_signature);

		newitem = plisql_package_body_compile(bodyoid, forValidator, true);

		newpsource = (PLiSQL_package *) newitem->source;

		if (newpsource->status == PLISQL_PACKAGE_REBUILD ||
			newpsource->status == PLISQL_PACKAGE_REBUILD_INIT)
		{
			newpsource->status = PLISQL_PACKAGE_NO_INIT;
			elog(ERROR, "existing state of packages has been discarded");
		}
	}

	/* check package status */
	psource = (PLiSQL_package *) pfunc->item->source;

	if (psource->status == PLISQL_PACKAGE_REBUILD ||
		psource->status == PLISQL_PACKAGE_REBUILD_INIT)
	{
		psource->status = PLISQL_PACKAGE_NO_INIT;
		elog(ERROR, "existing state of packages has been discarded");
	}

	/* if not have poly arguments */
	if (subprocfunc->has_poly_argument)
	{
		int nargs;
		Oid *argtypes;
		char **argnames;
		char *argmodes;
		PLiSQL_func_hashkey hashkey;

		/* origin has no define */
		if (subprocfunc->function->action == NULL)
			elog(ERROR, "subproc function \"%s\" doesn't define",
				subprocfunc->func_name);

		Assert(subprocfunc->poly_tab != NULL);

		nargs = get_subprocfunc_arg_info_from_arguments(subprocfunc->arg, &argtypes,
														&argnames, &argmodes);
		plisql_resolve_polymorphic_argtypes(nargs, argtypes, argmodes,
										 fcinfo->flinfo->fn_expr,
										 forValidator,
										 subprocfunc->func_name);

		/* Make sure any unused bytes of the struct are zero */
		MemSet(&hashkey, 0, sizeof(PLiSQL_func_hashkey));

		/* get function OID */
		hashkey.funcOid =  (Oid ) subprocfunc->fno;

		/* get call context */
		hashkey.isTrigger = false;
		hashkey.isEventTrigger = false;
		hashkey.trigOid = InvalidOid;

		/* get input collation, if known */
		hashkey.inputCollation = fcinfo->fncollation;;

		memcpy(hashkey.argtypes, argtypes,
				   nargs * sizeof(Oid));
		func = plisql_subprocfunc_HashTableLookup(subprocfunc->poly_tab, &hashkey);
		if (func == NULL)
		{
			/* function is not found, we shoud dynamic compile */
			Assert(subprocfunc->src != NULL);
			func = plisql_dynamic_compile_subproc(fcinfo, subprocfunc, forValidator);
		}
	}
	else
		func = subprocfunc->function;

	if (func->action == NULL)
		elog(ERROR, "subproc function \"%s\" doesn't define",
		func->fn_signature);

	if (psource->status == PLISQL_PACKAGE_NO_INIT)
	{
		plisql_exec_package_init(fcinfo, &psource->source);
		psource->status = PLISQL_PACKAGE_STATUSED;
	}

	/* record pfunc counts */
	pfunc->use_count++;

	return func;
}


/*
 * when a function to be free
 * we remove its references package relations ship
 *
 */
void
plisql_remove_function_relations(PLiSQL_function *func)
{
	ListCell *lc;

	foreach (lc, func->pkgcachelist)
	{
		PackageCacheItem *refcache = (PackageCacheItem *) lfirst(lc);

		plisql_remove_function_references(func, refcache);
	}

	return;
}


/*
 * check package specification and body gloabl var doesn't allow
 * to have ref cursor vars
 */
void
plisql_check_package_refcursor_var(int sqlvarno)
{
	PLiSQL_nsitem *nse;

	for (nse = plisql_ns_top(); nse != NULL; nse = nse->prev)
	{
		PLiSQL_var *var;

		if (nse->itemtype != PLISQL_NSTYPE_VAR)
			continue;

		/* doesn't consider sql varno */
		if (nse->itemno == sqlvarno)
			continue;

		var = (PLiSQL_var *) plisql_Datums[nse->itemno];

		/*
		 * maybe PLSQL_pkg_dataum, so there
		 * we ignore others type datum
		 */
		if (var->dtype != PLISQL_DTYPE_VAR)
			continue;

		if (var->datatype->typoid == REFCURSOROID && var->cursor_explicit_expr == NULL)
		{
			/*
			 * there may be change in further
			 * to support explicit cursor declare in package specification
			 */
			elog(ERROR, "Cursor Variables cannot be declared as part of a package");
		}
	}

	return;
}

/*
 * get package last global dno
 */
int
plisql_get_package_last_globaldno(int sqlstate_dno, int sqlerrm_dno)
{
	PLiSQL_nsitem *nse;
	int lastdno = -1;

	for (nse = plisql_ns_top(); nse != NULL; nse = nse->prev)
	{
		/* we only consider variable */
		if (nse->itemtype != PLISQL_NSTYPE_VAR &&
			nse->itemtype != PLISQL_NSTYPE_REC)
			continue;

		/* ignore some special var */
		if (nse->itemno == sqlstate_dno ||
			nse->itemno == sqlerrm_dno)
			continue;

		Assert(nse->itemno >= 0 && nse->itemno < plisql_nDatums);
		lastdno =  nse->itemno;
		break;
	}
	/* check lastdno before the global function define */
	if (nse != NULL)
	{
		for (nse = nse->prev; nse != NULL; nse = nse->prev)
		{
			if ((nse->itemtype == PLISQL_NSTYPE_SUBPROC_FUNC ||
				nse->itemtype == PLISQL_NSTYPE_SUBPROC_PROC) &&
				plisql_subprocFuncs[nse->itemno]->function->action != NULL &&
				plisql_subprocFuncs[nse->itemno]->lastoutvardno <= lastdno)
				elog(ERROR, "package global var define after function define");
		}
	}
	return lastdno;
}

/*
 * set package compile status
 * if package specification only type and constant, then
 * package is no status others package has a status
 */
PLiSQL_package_status
plisql_set_package_compile_status(void)
{
	PLiSQL_nsitem *nse;
	PLiSQL_package_status status = PLISQL_PACKAGE_NO_STATUS;
	PLiSQL_variable *var;

	for (nse = plisql_ns_top(); nse != NULL; nse = nse->prev)
	{
		/* label */
		if (nse->itemtype == PLISQL_NSTYPE_LABEL)
			continue;

		if (nse->itemtype != PLISQL_NSTYPE_VAR &&
			nse->itemtype != PLISQL_NSTYPE_REC)
		{
			status = PLISQL_PACKAGE_NO_INIT;
			break;
		}

		/* ignore found dno */
		if (nse->itemno == plisql_curr_compile->found_varno)
			continue;

		Assert(nse->itemno >= 0 && nse->itemno < plisql_nDatums);
		var = (PLiSQL_variable *) plisql_Datums[nse->itemno];

		if (!var->isconst)
		{
			status = PLISQL_PACKAGE_NO_INIT;
			break;
		}
	}

	return status;
}


/*
 * this function like exec_stmt_close
 * when we rebuild a package and free previous
 * pakcage instations, we should use this
 * function to close package open cursor and
 * release resource
 */
void
plisql_close_package_cursorvar(PLiSQL_var *var)
{
	Portal		portal;
	char	   *curname;

	Assert(var->datatype->typoid == REFCURSOROID);

	curname = plisql_get_portal_from_var(var);
	portal = SPI_cursor_find(curname);

	if (portal == NULL)
	{
		pfree(curname);
		return;
	}

	pfree(curname);
	SPI_cursor_close(portal);

	return;
}



/*
 * get current compile package cacheitem accroding
 * PackageCacheKey
 */
PackageCacheItem *
get_current_compile_package(PackageCacheKey key)
{
	int i;
	int j;
	PackageCacheItem *item;
	MemoryContext saved;
	PLiSQL_package *psource;
	int			pkg_ndatums;
	int			pkg_nsubprocfuncs;

	for (i = 0; i < plisql_curr_global_proper_level; i++)
		if (plisql_saved_compile_proper[i].plisql_saved_compile[0]->item != NULL &&
			plisql_saved_compile_proper[i].plisql_saved_compile[0]->item->pkey == key)
			break;

	/* doesn't found */
	if (i == plisql_curr_global_proper_level)
		return NULL;

	/*
	 * init some usefull message
	 * which plisql_package_parse
	 * will use
	 */
	item = plisql_saved_compile_proper[i].plisql_saved_compile[0]->item;
	psource = (PLiSQL_package *) item->source;

	/* package special has been compiled */
	if (psource->finish_compile_special)
		return item;

	saved = MemoryContextSwitchTo(psource->source.fn_cxt);

	pkg_ndatums = psource->source.ndatums;
	pkg_nsubprocfuncs = psource->source.nsubprocfuncs;

	psource->source.ndatums = plisql_saved_compile_proper[i].plisql_nDatums;

	if (pkg_ndatums < psource->source.ndatums)
	{
		if (pkg_ndatums == 0)
			psource->source.datums = palloc(sizeof(PLiSQL_datum *) * psource->source.ndatums);
		else
			psource->source.datums = repalloc(psource->source.datums,
								sizeof(PLiSQL_datum *) * psource->source.ndatums);
	}
	for (j = pkg_ndatums; j < psource->source.ndatums; j++)
		psource->source.datums[j] = plisql_saved_compile_proper[i].plisql_Datums[j];


	psource->source.nsubprocfuncs = plisql_saved_compile_proper[i].plisql_nsubprocFuncs;
	if (psource->source.nsubprocfuncs > 0)
	{
		if (pkg_nsubprocfuncs > 0)
		{
			if (pkg_nsubprocfuncs < psource->source.nsubprocfuncs)
				psource->source.subprocfuncs = repalloc(psource->source.subprocfuncs,
						sizeof(PLiSQL_subproc_function *) * psource->source.nsubprocfuncs);
		}
		else
			psource->source.subprocfuncs = palloc(sizeof(PLiSQL_subproc_function *) *
													psource->source.nsubprocfuncs);
	}
	for (j = 0; j < psource->source.nsubprocfuncs; j++)
		psource->source.subprocfuncs[j] = plisql_saved_compile_proper[i].plisql_subprocFuncs[j];

	psource->special_cur = plisql_saved_compile_proper[i].ns_top;
	MemoryContextSwitchTo(saved);

	return item;
}



/*
 * minuse package references
 */
static void
plisql_remove_function_references(PLiSQL_function *func, PackageCacheItem *item)
{
	PLiSQL_package *psource = (PLiSQL_package *) item->source;
	int pre_len;

	pre_len = list_length(psource->source.funclist);

	psource->source.funclist = list_delete_ptr(psource->source.funclist, (void *) func);

	Assert(pre_len == list_length(psource->source.funclist) + 1);

	psource->source.use_count--;

	/*
	 * when this item doesn't in hash table and its use_counts is zero,
	 * we free its memory
	 */
	if (!item->intable && psource->source.use_count == 0)
	{
		elog(DEBUG1, "free a package %u doesn't in hashtab start", item->pkey);
		plisql_free_package_function(item);
	}

	return;
}


/*
 * add package usecounts
 */
static void
plisql_addfunction_references(PLiSQL_function *func, PackageCacheItem *item)
{
	int presize;
	PLiSQL_package *psource = (PLiSQL_package *) item->source;
	MemoryContext old;

	/* change to package memorycontext */
	old = MemoryContextSwitchTo(psource->source.fn_cxt);

	presize = list_length(psource->source.funclist);
	psource->source.funclist = list_append_unique(psource->source.funclist, func);
	if (presize != list_length(psource->source.funclist))
		psource->source.use_count++;

	MemoryContextSwitchTo(old);

	return;
}


/*
 * get package or subproc function its top oid
 */
Oid
plisql_top_functin_oid(void *func, bool *is_package)
{
	PLiSQL_function *pfunc;
	Oid func_id;

	pfunc = (PLiSQL_function *) func;
	*is_package = false;

	if (pfunc == NULL)
		return InvalidOid;

	if (pfunc->item != NULL)
	{
		*is_package = true;
		func_id = pfunc->item->pkey;
	}
	else
		func_id = pfunc->fn_oid;

	return func_id;
}



/*
 * like plisql_validator
 * we handle only for package
 */
void
plisql_package_validator(Oid objectid, bool is_body)
{
	int 		rc;
	PackageCacheItem *item;

	/*
	 * Connect to SPI manager (is this needed for compilation?)
	 */
	if ((rc = SPI_connect()) != SPI_OK_CONNECT)
		elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(rc));


	/* Test-compile the function */
	if (is_body)
		item = plisql_package_body_compile(objectid, true, false);
	else
		item = plisql_package_compile(objectid, true, false);

	plisql_free_package_function(item);

	/*
	 * Disconnect from SPI manager
	 */
	if ((rc = SPI_finish()) != SPI_OK_FINISH)
		elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(rc));

	return;
}



/*
 * search for a package item we should compile
 * package and store it to memroy
 */
PackageCacheItem *
plisql_package_handle(Oid objectid, bool is_body)
{
	int 		rc;
	PackageCacheItem *item;

	/*
	 * maybe package is compiling, for example,
	 * a package references its var like schema.pkg.xx
	 * we should check current compile
	 */
	if (!is_body)
	{
		item = get_current_compile_package(objectid);
		if (item != NULL)
			return item;
	}

	/*
	 * Connect to SPI manager (is this needed for compilation?)
	 */
	if ((rc = SPI_connect()) != SPI_OK_CONNECT)
		elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(rc));

	/* Test-compile the function */
	if (is_body)
		item = plisql_package_body_compile(objectid, false, false);
	else
		item = plisql_package_compile(objectid, false, false);


	/*
	 * Disconnect from SPI manager
	 */
	if ((rc = SPI_finish()) != SPI_OK_FINISH)
		elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(rc));

	return item;
}


/*
 * cursor var is open
 */
bool
plisql_cursor_is_open(PLiSQL_var *var)
{
	bool isopen = false;

	if (var->datatype->typoid == REFCURSOROID)
		isopen = !var->isnull;

	return isopen;
}


/*
 * get portal name from cursor var
 */
char *
plisql_get_portal_from_var(PLiSQL_var *var)
{
	return TextDatumGetCString(var->value);
}

/*
 * get package datum
 */
PLiSQL_datum *
plisql_get_datum(PLiSQL_execstate *estate, PLiSQL_datum *pkgdatum)
{
	if (pkgdatum->dtype == PLISQL_DTYPE_PACKAGE_DATUM)
	{
		PLiSQL_pkg_datum *pkg_datum = (PLiSQL_pkg_datum *) pkgdatum;

		plisql_check_package_status(estate, pkg_datum);
		return pkg_datum->pkgvar;
	}
	else
		return pkgdatum;
}


/*
 * get package dno accroding package'oid and
 * variable dno
 */
PLiSQL_datum *
get_package_datum_bydno(PLiSQL_execstate *estate,
								Oid pkgoid, int dno)
{
	/*
	 * there maybe a package function which has polymorphic
	 * arguments type, its datum dno maybe not in psource
	 * its datums is added during dynamic comping
	 */
	if (estate->func->item != NULL &&
		estate->func->item->pkey == pkgoid)
	{
		Assert(dno < estate->func->ndatums);
		return estate->func->datums[dno];
	}
	else
	{
		PLiSQL_package *psource;
		PackageCacheItem *item = NULL;

		item = PackageCacheLookup(&pkgoid);
		Assert(item != NULL);
		psource = (PLiSQL_package *) item->source;
		Assert(dno < psource->source.ndatums);

		return psource->source.datums[dno];
	}
}



/*
 * get given package's context
 */
MemoryContext
plisql_get_relevantContext(Oid pkgoid, MemoryContext orig)
{
	PackageCacheItem *item = NULL;

	if (OidIsValid(pkgoid))
		item = PackageCacheLookup(&pkgoid);

	if (item != NULL)
		return item->ctxt;

	return orig;
}

/*
 * given a var, return wether
 * it is a global var in package
 */
bool
is_package_global_var(PLiSQL_var *var)
{
	PackageCacheItem *item;
	PLiSQL_package *psource;
	bool ret = false;

	if (!OidIsValid(var->pkgoid))
		return false;

	item = PackageCacheLookup(&var->pkgoid);
	psource = (PLiSQL_package *) item->source;

	switch (var->dtype)
	{
		case PLISQL_DTYPE_RECFIELD:
			{
				PLiSQL_recfield *rfield = (PLiSQL_recfield *) var;

				ret = (rfield->recparentno <= psource->last_globaldno ? true : false);
			}
			break;
		default:
			ret = (var->dno <= psource->last_globaldno ? true : false);
			break;
	}

	return ret;
}


/*
 * decide wether datum is a const
 */
bool
is_const_datum(PLiSQL_execstate *estate, PLiSQL_datum *datum)
{
	bool isconst = false;

	switch (datum->dtype)
	{
		case PLISQL_DTYPE_PROMISE:
		case PLISQL_DTYPE_VAR:
			{
				PLiSQL_var *var = (PLiSQL_var *) datum;

				isconst = var->isconst;
			}
			break;
		case PLISQL_DTYPE_ROW:
			{
				PLiSQL_row *row = (PLiSQL_row *) datum;

				isconst = row->isconst;
			}
			break;
		case PLISQL_DTYPE_REC:
			{
				PLiSQL_rec *rec = (PLiSQL_rec *) datum;

				isconst = rec->isconst;
			}
			break;
		case PLISQL_DTYPE_RECFIELD:
			{
				PLiSQL_recfield *recfield = (PLiSQL_recfield *) datum;
				PLiSQL_rec *rec;

				if (OidIsValid(recfield->pkgoid))
					rec = (PLiSQL_rec *) get_package_datum_bydno(estate,
												recfield->pkgoid,
												recfield->recparentno);
				else
					rec = (PLiSQL_rec *) (estate->datums[recfield->recparentno]);
				isconst = rec->isconst;
			}
			break;
		case PLISQL_DTYPE_PACKAGE_DATUM:
			{
				PLiSQL_pkg_datum *pkgdatum = (PLiSQL_pkg_datum *) datum;

				isconst = is_const_datum(estate, pkgdatum->pkgvar);
			}
			break;
		default:
			elog(ERROR, "unrecognized dtype: %d", datum->dtype);
			break;
	}
	return isconst;
}


/*
 * expand all recfiled of rec
 */
void
plisql_expand_rec_field(PLiSQL_rec *rec)
{
	TupleDesc tupdesc = get_plisql_rec_tupdesc(rec);
	int i;

	if (tupdesc == NULL)
		return;

	for (i = 0; i < tupdesc->natts; i++)
	{
		Form_pg_attribute attr = TupleDescAttr(tupdesc, i);

		if (!attr->attisdropped)
			plisql_build_recfield(rec, NameStr(tupdesc->attrs[i].attname));
	}
}

/*
 * check wether subproc has a action
 */
void
plisql_check_subproc_define(PLiSQL_function *function)
{
	List *already_checks = NIL;

	plisql_check_subproc_define_recurse(function, &already_checks);
	list_free(already_checks);

	return;
}
/*
 * like plisql_compile_error_callback
 * we only change error message
 */
void
plisql_compile_package_error_callback(void *arg)
{
	if (arg)
	{
		/*
		 * Try to convert syntax error position to reference text of original
		 * CREATE FUNCTION or DO command.
		 */
		if (function_parse_error_transpose((const char *) arg))
			return;

		/*
		 * Done if a syntax error position was reported; otherwise we have to
		 * fall back to a "near line N" report.
		 */
	}

	if (plisql_error_funcname)
		errcontext("compilation of PL/iSQL package \"%s\" near line %d",
				   plisql_error_funcname, plisql_latest_lineno());
}


/*
 * like SPI_datumTransfer, but handle special
 */
Datum
package_datumTransfer(Datum value, bool typByVal,
						int typLen, bool isnull)
{
	/*
	 * special for expand object we should record its read only
	 * so that, it doesn't been assigned to others use its origin
	 * value
	 */
	if (!typByVal && typLen == -1 &&
		VARATT_IS_EXTERNAL_EXPANDED_RW(DatumGetPointer(value)))
		return MakeExpandedObjectReadOnly(value, isnull, typLen);

	return SPI_datumTransfer(value, typByVal, typLen);
}

/*
 * is compile standard package ?
 * standard package is speical, which can be referenced without
 * package'name
 */
bool
is_compile_standard_package(void)
{
	if (plisql_saved_compile[0]->item != NULL &&
		strcmp(plisql_saved_compile[0]->fn_signature, "standard") == 0)
		return true;
	else
		return false;
}

/*
 * get package specification subprocs
 */
void
plisql_get_subprocs_from_package(Oid pkgoid,
											TupleDesc tupdesc,
											Tuplestorestate *tupstore)
{
	PackageCacheItem *item;
	PLiSQL_package *psource;
	int j;
	Oid namespaceid;
	Oid owner;
	Oid *oids;
	HeapTuple tup;
	Form_pg_package pkg_Form;
	bool define_invok;

	item = PackageCacheLookup(&pkgoid);

	if (item == NULL)
		item = plisql_package_compile(pkgoid, false, false);
	if (item == NULL)
		return;

	tup = SearchSysCache1(PKGOID, ObjectIdGetDatum(pkgoid));
	if (!HeapTupleIsValid(tup))
		elog(ERROR, "cache lookup failed for package %u", pkgoid);

	pkg_Form = (Form_pg_package) GETSTRUCT(tup);

	namespaceid = pkg_Form->pkgnamespace;
	owner = pkg_Form->pkgowner;
	define_invok = pkg_Form->define_invok;
	psource = (PLiSQL_package *) item->source;

	for (j = 0; j < psource->last_specialfno; j++)
	{
		Datum		values[17];
		bool		nulls[17];
		PLiSQL_subproc_function *subproc = psource->source.subprocfuncs[j];
		oidvector *parameterTypes;
		Datum	*paramModes;
		Datum	*paramNames;
		Datum	*paramTypNames;
		Datum	*paramDefaults;
		ArrayType  *parameterModes;
		ArrayType  *parameterNames;
		ArrayType  *parameterTypeNames;
		ArrayType  *parameterdefaults;
		ListCell *lc;
		int nargs;
		int i = 0;

		MemSet(nulls, 0, sizeof(nulls));

		nargs = list_length(subproc->arg);
		values[0] = ObjectIdGetDatum(pkgoid);
		values[1] = ObjectIdGetDatum(namespaceid);
		values[2] = ObjectIdGetDatum(owner);
		values[3] = CStringGetTextDatum(psource->source.fn_signature);
		values[4] = CStringGetTextDatum(subproc->func_name);
		values[5] = Int32GetDatum(subproc->fno);
		if (subproc->is_proc)
			values[6] = CharGetDatum(PROKIND_PROCEDURE);
		else
			values[6] = CharGetDatum(PROKIND_FUNCTION);
		values[7] = Int32GetDatum(nargs);
		values[8] = Int32GetDatum(subproc->nargdefaults);
		if (subproc->rettype != NULL)
		{
			values[9] = ObjectIdGetDatum(subproc->rettype->typoid);
			values[10] = CStringGetTextDatum(format_type_be(subproc->rettype->typoid));
		}
		else
		{
			nulls[9] = true;
			nulls[10] = true;
		}
		oids = (Oid *) palloc(sizeof(Oid) * nargs);
		paramModes = (Datum *) palloc(nargs * sizeof(Datum));
		paramNames = (Datum *) palloc(nargs * sizeof(Datum));
		paramTypNames = (Datum *) palloc(nargs * sizeof(Datum));
		paramDefaults = (Datum *) palloc(nargs * sizeof(Datum));
		foreach (lc, subproc->arg)
		{
			PLiSQL_function_argitem *argitem = (PLiSQL_function_argitem *) lfirst(lc);

			oids[i] = argitem->type->typoid;
			switch (argitem->argmode)
			{
				case ARGMODE_IN:
					paramModes[i] = CharGetDatum(FUNC_PARAM_IN);
					break;
				case ARGMODE_OUT:
					paramModes[i] = CharGetDatum(FUNC_PARAM_OUT);
					break;
				case ARGMODE_INOUT:
					paramModes[i] = CharGetDatum(FUNC_PARAM_INOUT);
					break;
				default:
					elog(ERROR, "invalid argmode %u", argitem->argmode);
					break;
			}
			paramNames[i] = CStringGetTextDatum(argitem->argname);
			paramTypNames[i] = CStringGetTextDatum(format_type_be(oids[i]));
			if (argitem->defexpr != NULL)
				paramDefaults[i] = CStringGetTextDatum(argitem->defexpr->query);
			else
				paramDefaults[i] = CStringGetTextDatum(pstrdup("_NULL_"));
			i++;
		}
		parameterTypes = buildoidvector(oids, nargs);
		parameterModes = construct_array(paramModes, nargs, CHAROID,
										  1, true, TYPALIGN_CHAR);
		parameterNames = construct_array(paramNames, nargs, TEXTOID,
										  -1, false, TYPALIGN_INT);
		parameterTypeNames = construct_array(paramTypNames, nargs, TEXTOID,
										  -1, false, TYPALIGN_INT);
		parameterdefaults = construct_array(paramDefaults, nargs, TEXTOID,
										  -1, false, TYPALIGN_INT);
		values[11] = PointerGetDatum(parameterTypes);
		if (parameterTypeNames != NULL)
			values[12] = PointerGetDatum(parameterTypeNames);
		else
			nulls[12] = true;
		if (parameterModes != NULL)
			values[13] = PointerGetDatum(parameterModes);
		else
			nulls[13] = true;
		if (parameterNames != NULL)
			values[14] = PointerGetDatum(parameterNames);
		else
			nulls[14] = true;
		if (parameterdefaults != NULL)
			values[15] = PointerGetDatum(parameterdefaults);
		else
			nulls[15] = true;
		values[16] = BoolGetDatum(define_invok);

		tuplestore_putvalues(tupstore, tupdesc, values, nulls);
	}

	ReleaseSysCache(tup);

	return;
}

/*
 * check the datum is PLiSQL_row or
 * PLiSQL_record variable in package
 */
bool
is_row_record_datum(PLiSQL_datum * datum)
{
	PLiSQL_datum *real_datum = datum;

	if (real_datum->dtype == PLISQL_DTYPE_PACKAGE_DATUM)
		real_datum = ((PLiSQL_pkg_datum *) datum)->pkgvar;

	if (real_datum->dtype == PLISQL_DTYPE_ROW ||
		real_datum->dtype == PLISQL_DTYPE_REC)
		return true;
	else
		return false;
}

/*
 * release package function use_count
 */
void
release_package_func_usecount(FunctionCallInfo fcinfo)
{
	PackageCacheItem *item;
	PLiSQL_package *psource;
	FuncExpr *funcexpr;

	funcexpr = (FuncExpr *) fcinfo->flinfo->fn_expr;

	Assert(funcexpr->function_from == FUNC_FROM_PACKAGE);

	if (!OidIsValid(funcexpr->pkgoid))
		elog(ERROR, "invalid pkgoid");
	item = PackageCacheLookup(&(funcexpr->pkgoid));
	if (item == NULL)
		elog(ERROR, "package %u cache is not found", funcexpr->pkgoid);
	psource = (PLiSQL_package *) item->source;

	psource->source.use_count--;

	return;
}

