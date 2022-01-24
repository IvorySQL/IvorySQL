/*-------------------------------------------------------------------------
 *
 * pg_package.h
 *	  definition of package system catalog (pg_package)
 *
 * Copyright (c) 2021-2022, IvorySQL
 *
 * src/include/catalog/pg_package.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PG_PACKAGE_H
#define PG_PACKAGE_H

#include "catalog/genbki.h"
#include "catalog/objectaddress.h"
#include "catalog/pg_package_d.h"
#include "utils/acl.h"


/* ----------------
 *		pg_package definition.  cpp turns this into
 *		typedef struct FormData_pg_package
 * ----------------
 */
CATALOG(pg_package,564,PackageRelationId)
{
	Oid			oid;			/* oid */
	NameData	pkgname;		/* name of the package */
	Oid			pkgnamespace;	/* Package namespace */
	Oid			pkgowner BKI_DEFAULT(PGUID);	/* package owner */
	bool		pkgsecdef BKI_DEFAULT(f);	/* Package security clause */

#ifdef CATALOG_VARLEN			/* variable-length fields start here */
	text		pkgspec BKI_FORCE_NOT_NULL; /* Text string of package
											 * specification */
	text		pkgbody BKI_DEFAULT(_null_);	/* Text string of package body */
	anyarray	pkgaccessor BKI_DEFAULT(_null_);	/* package accessor's list */
	aclitem		pkgacl[1] BKI_DEFAULT(_null_);	/* package access permissions */
#endif
} FormData_pg_package;

/* ----------------
 *      Form_pg_package corresponds to a pointer to a row with
 *      the format of pg_package relation.
 * ----------------
 */
typedef FormData_pg_package * Form_pg_package;
DECLARE_TOAST(pg_package, 4544, 4545);

DECLARE_UNIQUE_INDEX_PKEY(pg_package_oid_index, 565, PackageObjectIndexId, on pg_package using btree(oid oid_ops));
DECLARE_UNIQUE_INDEX(pg_package_pkgname_nsp_index, 566, PackageNameNspIndexId, on pg_package using btree(pkgname name_ops, pkgnamespace oid_ops));

extern Oid	PackageCreate(const char *pkgname,
						  Oid pkgnamespace,
						  bool replace,
						  bool isbody,
						  const char *pkgspec,
						  const char *pkgbody,
						  Oid pkgowner,
						  bool pkgsecdef);

#endif							/* PG_PACKAGE_H */
