/*-------------------------------------------------------------------------
 *
 * File:packagecache.h
 *
 * Abstract:
 *		Definitions for the PLISQL Package cache
 *
 *
 * Copyright:
 * Copyright (c) 2024-2025, IvorySQL Global Development Team 
 *
 * IDENTIFICATION
 *	  src/include/utils/packagecache.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef PACKAGE_CACHE_H
#define PACKAGE_CACHE_H
#include "c.h"
#include "storage/itemptr.h"
#include "utils/palloc.h"
#include "lib/stringinfo.h"

/*
 * package cache status, to check package cache is invalid
 * at fast, if package cache status hasn't bee update,
 * we don't compile package and body tid and xid
 * we only use three bits at current,
 * first bit set for package specifications
 * the second bit set for wether it has a body
 * the three bit set for its body is updateed or not
 */
typedef char PackageCacheStatus;

#define PACKAGE_SPECIFICATION_UPDATE_FLAG 0x01
#define PACKGE_HAS_BODY_FLAG	0x02
#define PACKAGE_BODY_UPDATE_FLAG 0x04

#define PACKAGE_SPECIFICATION_IS_UPDATED(_status) \
	(_status & PACKAGE_SPECIFICATION_UPDATE_FLAG)
#define PACKAGE_BODY_IS_UPDATED(_status) \
	(_status & PACKAGE_BODY_UPDATE_FLAG)
#define PACKAGE_HAS_BODY(_status) (_status & PACKGE_HAS_BODY_FLAG)

#define PACKAGE_SET_SPECIFICATION_UPDATE_FLAG(_status) \
	(_status | PACKAGE_SPECIFICATION_UPDATE_FLAG)
#define PACKAGE_SET_BODY_FLAG(_status) (_status | PACKGE_HAS_BODY_FLAG)
#define PACKAGE_SET_BODY_UPDATE_FLAG(_status) (_status | PACKAGE_BODY_UPDATE_FLAG)

typedef Oid PackageCacheKey;

/*
 * if define PACKAGE_CHECK_INVALID_BY_TUPLE
 * we check package invalid like function which
 * check xmin and tid
 * we don't need use this, because we register a system catalog
 * invalid function to notify
 */

typedef struct PackageCacheItem
{
	PackageCacheKey pkey;
	MemoryContext	ctxt;			/* memory context for PackageCacheItem and its source */
	uint32			package_hash_value;	/* package'hash value in catcache of PKGOID */
	uint32			body_hash_value;	/* package body hash value int catcache of PKGBODYOID */
	bool			intable;			/* cachitem is inserted in package hash table or not */
	PackageCacheStatus	cachestatus;	/* pg_package or pg_package_body has bee updated */
	void			*source;		/* see pl_package.h for PLiSQL_package struct */
} PackageCacheItem;

typedef struct PackageCacheEntry
{
	PackageCacheKey key;
	PackageCacheItem *item;
} PackageCacheEntry;

/*
 * some userfull functions to compile package
 */
typedef enum
{
	PACKAGE_PARSE_TYPE,
	PACKAGE_PARSE_VAR,
	PACKAGE_PARSE_FUNC,
	PACKAGE_PARSE_PROC,
	PACKAGE_PARSE_ENTRY
} package_parse_flags;

extern PackageCacheItem *PackageCacheLookup(PackageCacheKey *key);
extern bool PackageCacheIsValid(PackageCacheKey *key, bool check_body);
extern void ValidatroPackage(Oid objectid, bool is_body);
extern PackageCacheItem *PackageHandle(Oid objectid, bool is_body);
extern void FreePackageCache(PackageCacheKey *key);
extern PackageCacheItem *PackageCacheDelete(PackageCacheKey *key);
extern void PackageCacheInsert(PackageCacheKey *key, PackageCacheItem *item);
extern PGDLLIMPORT MemoryContext PackageCacheContext;

extern void ResetPackageCaches(void);

extern void plisql_internel_funcs_init(void);

extern Oid get_top_function_info(FuncExpr *fexpr, bool *is_package);
extern void set_pkginfo_from_funcexpr(FuncExpr *funcexpr);
extern void set_pkgtype_from_funcexpr(FuncExpr *funcexpr);
#endif

