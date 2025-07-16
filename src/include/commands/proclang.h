/*-------------------------------------------------------------------------
 *
 * proclang.h
 *	  prototypes for proclang.c.
 *
 * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/commands/proclang.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PROCLANG_H
#define PROCLANG_H

#include "catalog/objectaddress.h"
#include "nodes/parsenodes.h"

extern ObjectAddress CreateProceduralLanguage(CreatePLangStmt *stmt);

extern Oid	get_language_oid(const char *langname, bool missing_ok);

extern Oid  get_plisql_language_oid(void);
#define LANG_PLISQL_OID	get_plisql_language_oid()

#endif							/* PROCLANG_H */
