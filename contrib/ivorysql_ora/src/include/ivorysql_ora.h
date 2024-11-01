/*--------------------------------------------------------------------
 * 
 * File: ivorysql_ora.h
 *
 * Abstract: 
 * 		This file contains extern declarations for ivorysql_ora itself.
 *
 * Copyright:
 * Portions Copyright (c) 2024, Ivory SQL Global Development Team
 *
 * Identification:
 *		contrib/ivorysql_ora/src/include/ivorysql_ora.h
 *
 *--------------------------------------------------------------------
 */
#ifndef IVORYSQL_ORA_H_
#define IVORYSQL_ORA_H_

#include "postgres.h"
#include "parser/parse_node.h"
#include "executor/nodeModifyTable.h"


/* Hooks */
extern bool pg_compatible_oracle_precedence(Oid arg1, Oid arg2, char *opname_p, Oid *result_arg1, Oid *result_arg2);


extern int IvyOraGetAttrno(ParseState *pstate, ResTarget  *col);



extern bool IvyExecMergeMatched(ModifyTableContext *context, ResultRelInfo *resultRelInfo,
									ItemPointer tupleid, bool canSetTag);
extern Query* IvytransformMergeStmt(ParseState *pstate, MergeStmt *stmt);


#endif	/* IVORYSQL_ORA_H_ */
