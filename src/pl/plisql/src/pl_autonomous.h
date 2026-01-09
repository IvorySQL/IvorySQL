/*-------------------------------------------------------------------------
 *
 * pl_autonomous.h
 *	  Definitions for autonomous transaction support in PL/iSQL
 *
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
 * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *	  src/pl/plisql/src/pl_autonomous.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef PL_AUTONOMOUS_H
#define PL_AUTONOMOUS_H

#include "plisql.h"

/*
 * Initialize autonomous transaction support (register callbacks)
 */
extern void plisql_autonomous_init(void);

/*
 * Mark current function as autonomous
 */
extern void plisql_mark_autonomous_transaction(PLiSQL_function *func,
											   int location,
											   void *yyscanner);

/*
 * Execute function in autonomous transaction using dblink
 */
extern Datum plisql_exec_autonomous_function(PLiSQL_function *func,
											 FunctionCallInfo fcinfo,
											 EState *simple_eval_estate,
											 ResourceOwner simple_eval_resowner);

/*
 * Check if dblink extension is available
 */
extern bool plisql_check_dblink_available(void);

#endif							/* PL_AUTONOMOUS_H */
