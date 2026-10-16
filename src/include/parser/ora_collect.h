/*-------------------------------------------------------------------------
 *
 * ora_collect.h
 *	  IvorySQL: prototypes for Oracle nested-table collection constructor
 *	  transformation (see ora_collect.c).
 *
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 2025, IvorySQL Global Development Group
 *
 *	src/include/parser/ora_collect.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef ORA_COLLECT_H
#define ORA_COLLECT_H

#include "parser/parse_node.h"

extern Node *transform_oracle_collection_constructor(ParseState *pstate,
													 List *funcname,
													 List *fargs,
													 int location);

#endif							/* ORA_COLLECT_H */
