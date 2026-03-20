/*-------------------------------------------------------------------------
 * Copyright 2025 IvorySQL Global Development Team
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * File:packagecmds.h
 *
 * Abstract:
 *		Definitions for the PLISQL Package
 *
 *
 * Copyright (c) 2024-2026, IvorySQL Global Development Team
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

