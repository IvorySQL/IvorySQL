/*-------------------------------------------------------------------------
 *
 * ivorysql_ora.h
 *
 * This file contains extern declarations for ivorysql_ora itself.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
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

/* Begin - ReqID:SRS-SQL-XML */
#include "utils/xml.h"
/* End - ReqID:SRS-SQL-XML */

/* Hooks */
extern bool pg_compatible_oracle_precedence(Oid arg1, Oid arg2, char *opname_p, Oid *result_arg1, Oid *result_arg2);
extern TupleTableSlot *IvyExecMergeMatched(IvyModifyTableContext *context,
										ResultRelInfo *resultRelInfo,
										ItemPointer tupleid,
										HeapTuple oldtuple,
										bool canSetTag,
										bool *matched);
extern Query* IvytransformMergeStmt(ParseState *pstate, MergeStmt *stmt);

/* Begin - ReqID:SRS-SQL-XML */
extern xmltype* updatexml(List *args);
/* End - ReqID:SRS-SQL-XML */

#endif	/* IVORYSQL_ORA_H_ */
