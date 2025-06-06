/*-------------------------------------------------------------------------
 *
 * File:parse_package.h
 *
 * Abstract:
 *		Definitions for the PLISQL Package parser
 *
 * Copyright:
 * Copyright (c) 2024-2025, IvorySQL Global Development Team 
 *
 * IDENTIFICATION
 *	  src/include/parser/parse_package.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef PARSE_PACKAGE_H
#define PARSE_PACKAGE_H
#include "nodes/parsenodes.h"
#include "nodes/pg_list.h"
#include "nodes/primnodes.h"
#include "parser/parse_node.h"
#include "parser/parse_func.h"
#include "access/tupdesc.h"
#include "funcapi.h"
#include "utils/packagecache.h"

typedef struct PkgType
{
	Oid pkgoid;	 /* package oid */
	Oid basetypid;  /* base of type id */
	int pkgname_startloc; /* pkgname start location */
	PackageCacheItem *item; /* package cache item */
	void *value;	 /* PLiSQL_type */
} PkgType;

typedef struct PkgVar
{
	Oid pkgoid;			 /* package oid */
	PackageCacheItem *item; /* package cache item */
	Datum value;			 /* a PLisql datum */
} PkgVar;

typedef enum
{
	PKG_VAR = 0,
	PKG_TYPE
} PkgEntryType;

typedef struct PkgEntry
{
	PkgEntryType type;
	PackageCacheItem *item;
	void *value;
} PkgEntry;


/* some usefull functions */
extern PkgType *LookupPkgTypeByTypename(const List *names, bool missing_ok);
extern PkgVar *LookupPkgVarByvarnames(const List *names, bool missing_ok);
extern PkgEntry *LookupPkgEntryByTypename(const List *names, bool missing_ok);
extern FuncDetailCode LookupPkgFunc(ParseState *pstate, List *funcname,
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
				bool missing_ok);
#endif

