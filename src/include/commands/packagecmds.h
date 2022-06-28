/*-------------------------------------------------------------------------
 *
 * packagecmds.h
 *	  prototypes for packagecmds.c.
 *
 * Copyright (c) 2021-2022, IvorySQL
 *
 * src/include/commands/packagecmds.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef PACKAGECMDS_H
#define PACKAGECMDS_H

#include "catalog/objectaddress.h"
#include "nodes/parsenodes.h"

typedef void (*remove_package_state) (Oid pkgoid);

extern char *get_package_name(Oid packageid, bool missing_ok);
extern char *get_package_src(Oid packageid, bool spec_or_body, bool missing_ok);
extern bool is_package_exists(Oid packageid);

#endif							/* PACKAGECMDS_H */
