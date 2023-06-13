/*-------------------------------------------------------------------------
 *
 * ivorysql_ora.h
 *
 * This file contains extern declarations for ivorysql_ora itself.
 *
 * Portions Copyright (c) 2023, Ivory SQL Global Development Team
 *
 * contrib/ivorysql_ora/src/include/ivorysql_ora.h
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */
#ifndef IVORYSQL_ORA_H_
#define IVORYSQL_ORA_H_

#include "postgres.h"
#include "parser/parse_node.h"
#include "executor/nodeModifyTable.h"


/* Hooks */
extern bool pg_compatible_oracle_precedence(Oid arg1, Oid arg2, char *opname_p, Oid *result_arg1, Oid *result_arg2);
extern bool IvyExecMergeMatched(ModifyTableContext *context, ResultRelInfo *resultRelInfo,
									ItemPointer tupleid, bool canSetTag);
extern Query* IvytransformMergeStmt(ParseState *pstate, MergeStmt *stmt);


#endif	/* IVORYSQL_ORA_H_ */
