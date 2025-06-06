/*-------------------------------------------------------------------------
 *
 * File:pg_package.h
 *
 * Abstract:
 *		Definitions for the PLISQL Package
 *
 *
 * Copyright:
 * Copyright (c) 2024-2025, IvorySQL Global Development Team 
 *
 * IDENTIFICATION
 *	  src/include/catalog/pg_package.h
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

CATALOG(pg_package,9111,PackageRelationId)
{
	Oid			oid;			 /* oid */
	NameData	pkgname;
	Oid		 	pkgnamespace BKI_DEFAULT(pg_catalog) BKI_LOOKUP(pg_namespace);
	Oid		 	pkgowner BKI_DEFAULT(POSTGRES) BKI_LOOKUP(pg_authid);
	bool		define_invok BKI_DEFAULT(f);
	bool		editable BKI_DEFAULT(t);
	bool		use_collation BKI_DEFAULT(f);

#ifdef CATALOG_VARLEN			/* variable-length fields start here */
	aclitem	 	pkgacl[1] BKI_DEFAULT(_null_);
	pg_node_tree	accesssource  BKI_DEFAULT(_null_);
	text		pkgsrc BKI_DEFAULT(_null_);
#endif
} FormData_pg_package;

/* ----------------
 * 	 Form_pg_package corresponds to a pointer to a tuple with
 * 	 the format of pg_package relation.
 * ----------------
 */
typedef FormData_pg_package *Form_pg_package;

DECLARE_TOAST(pg_package, 9112, 9113);

DECLARE_UNIQUE_INDEX_PKEY(pg_package_oid_index, 9114, PackageObjectIndexId, pg_package, btree(oid oid_ops));
#define PackageObjectIndexId 9114
DECLARE_UNIQUE_INDEX(pg_package_pkgname_nsp_index, 9115, PackageNameArgsNspIndexId, pg_package, btree(pkgname name_ops, pkgnamespace oid_ops));
#define PackageNameArgsNspIndexId 9115

MAKE_SYSCACHE(PKGOID, pg_package_oid_index, 8);
MAKE_SYSCACHE(PKGNAMEARGSNSP, pg_package_pkgname_nsp_index, 8);

#endif			/* PG_PACKAGE_H */

