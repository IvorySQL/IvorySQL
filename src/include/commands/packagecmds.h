/*-------------------------------------------------------------------------
 *
 * File:packagecmds.h
 *
 * Abstract:
 *		Definitions for the PLISQL Package
 *
 *
 * Copyright:
 * Copyright (c) 2024-2025, IvorySQL Global Development Team 
 *
 * IDENTIFICATION
 *	  src/include/commands/packagecmds.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef PACKAGECMDS_H
#define PACKAGECMDS_H
#include "nodes/parsenodes.h"
#include "catalog/objectaddress.h"
#include "access/htup.h"


extern ObjectAddress CreatePackage(CreatePackageStmt *stmt);
extern ObjectAddress CreatePackageBody(CreatePackageBodyStmt *stmt);
extern ObjectAddress AlterPackage(AlterPackageStmt *stmt);
extern Oid LookupPackageByNames(List *pkgname, bool missing_ok);
extern Oid LookupPackageBodyByNames(List *pkgname, bool missing_ok);
extern Oid get_package_pkgid(const char *pkgname, Oid pkgnamespace);
extern bool pg_package_ownercheck(Oid pkgid, Oid roleid);
extern bool pg_packagebody_ownercheck(Oid bodyid, Oid roleid);
extern void DropPackageById(Oid pkgid);
extern void DropPackageBodyById(Oid bodyid);
extern void get_package_nameinfo(Oid pkgid, char **pkgname, char **schema);
extern char *get_package_name(Oid pkgid);
extern void get_package_nameinfo_bybodyid(Oid bodyid, char **pkgname,
										char **schema);
extern Oid get_package_namespace(Oid pkgid);
extern Oid get_package_bodyid(Oid pkgoid, bool miss_ok);
extern void check_package_name(Oid nspname, char *newpkgname, char *oldpkgname);
extern void IsTherePackageInNamespace(char *new_name, Oid namespace);
extern HeapTuple get_functup_bytypenames(Oid namespaceid,
						const char *func_name, Datum typenames,
						oidvector *parametertypes,
						Datum allParametertypes);
#endif

