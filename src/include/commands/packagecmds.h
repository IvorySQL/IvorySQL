/*-------------------------------------------------------------------------
 *
 * packagecmds.h
 *	  prototypes for packagecmds.c.
 *
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

extern Oid	get_package_oid(List *packagename, bool missing_ok);
extern char *get_package_name(Oid packageid, bool missing_ok);
extern char *get_package_src(Oid packageid, bool spec_or_body, bool missing_ok);

#endif							/* PACKAGECMDS_H */
