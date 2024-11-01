/*-------------------------------------------------------------------------
 *
 * parse_merge.h
 *		handle MERGE statement in parser
 *
 *
 * Portions Copyright (c) 1996-2022, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/parser/parse_merge.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PARSE_MERGE_H
#define PARSE_MERGE_H

#include "parser/parse_node.h"

extern Query *transformMergeStmt(ParseState *pstate, MergeStmt *stmt);
extern void setNamespaceForMergeWhen(ParseState *pstate, MergeWhenClause *mergeWhenClause,
												Index targetRTI, Index sourceRTI);

typedef Query* (* transform_merge_stmt_hook_type)(ParseState *pstate, MergeStmt *stmt);
extern PGDLLIMPORT transform_merge_stmt_hook_type pg_transform_merge_stmt_hook;
extern PGDLLIMPORT transform_merge_stmt_hook_type ora_transform_merge_stmt_hook;

#endif							/* PARSE_MERGE_H */
