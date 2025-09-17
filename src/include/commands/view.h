/*-------------------------------------------------------------------------
 *
 * view.h
 *
 *
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/commands/view.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef VIEW_H
#define VIEW_H

#include "catalog/objectaddress.h"
#include "nodes/parsenodes.h"

extern ObjectAddress DefineView(ViewStmt *stmt, const char *queryString,
								int stmt_location, int stmt_len);

extern void StoreViewQuery(Oid viewOid, Query *viewParse, bool replace);

extern void StoreForceViewQuery(Oid viewOid, bool replace, char ident_case, const char *queryString);
extern void DeleteForceView(Oid forceviewid);
extern bool rel_is_force_view(Oid relid);
extern char *get_force_view_def(Oid viewoid);
extern bool compile_force_view(Oid viewoid);
extern bool make_view_invalid(Oid viewid);
extern bool make_view_valid(List *tlist, Oid viewOid, List *options, Query *viewParse);

#endif							/* VIEW_H */
