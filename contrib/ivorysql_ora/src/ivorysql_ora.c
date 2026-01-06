/*-------------------------------------------------------------------------
 * Copyright 2025 IvorySQL Global Development Team
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ivorysql_ora.c
 *
 * Ivorysql_ora main entrypoint.
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * contrib/ivorysql_ora/src/ivorysql_ora.c
 *
 * add the file for Oracle's built-in data types
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/heapam.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "nodes/parsenodes.h"
#include "parser/parse_oper.h"
#include "parser/parse_merge.h"
#include "tcop/utility.h"

/* Begin - ReqID:SRS-SQL-XML */
#include "executor/execExpr.h"
/* End - ReqID:SRS-SQL-XML */

#include "include/guc.h"
#include "include/ivorysql_ora.h"

/* Only include it once in any C file */
PG_MODULE_MAGIC_EXT(
					.name = "ivorysql_ora",
					.version = PG_VERSION
);


/* Saved hook value in case of unload */
static oracle_datatype_precedence_hook_type pre_oracle_datatype_precedence_hook = NULL;

/* The hook of the merge command */
static exec_merge_matched_hook_type pre_exec_merge_matched_hook = NULL;
static transform_merge_stmt_hook_type pre_transform_merge_stmt_hook = NULL;

/* Begin - ReqID:SRS-SQL-XML */
static ora_updatexml_hook_type pre_ora_updatexml_hook = NULL;
/* End - ReqID:SRS-SQL-XML */

/* ProcessUtility hook for DISCARD ALL/PACKAGES handling */
static ProcessUtility_hook_type prev_ProcessUtility_hook = NULL;

/* Forward declaration */
static void ivorysql_ora_ProcessUtility(PlannedStmt *pstmt,
										const char *queryString,
										bool readOnlyTree,
										ProcessUtilityContext context,
										ParamListInfo params,
										QueryEnvironment *queryEnv,
										DestReceiver *dest,
										QueryCompletion *qc);

void _PG_init(void);
void _PG_fini(void);

/*
 * Module initialization function.
 */
void
_PG_init(void)
{
#if 0
	/* Must be loaded with shared_preload_libaries */
	if (!process_shared_preload_libraries_in_progress)
		ereport(ERROR, (errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
				errmsg("ivorysql_ora must be loaded via shared_preload_libraries")));
#endif

	/* Define custom GUC variables */
	IvorysqlOraDefineGucs();

	/* Install Hooks */
	pre_oracle_datatype_precedence_hook = oracle_datatype_precedence_hook;
	oracle_datatype_precedence_hook = pg_compatible_oracle_precedence;

	ora_exec_merge_matched_hook = IvyExecMergeMatched;
	ora_transform_merge_stmt_hook = IvytransformMergeStmt;

	pre_exec_merge_matched_hook = pg_exec_merge_matched_hook;
	pg_exec_merge_matched_hook = ora_exec_merge_matched_hook;
	pre_transform_merge_stmt_hook = pg_transform_merge_stmt_hook;
	pg_transform_merge_stmt_hook = ora_transform_merge_stmt_hook;

	/* Begin - ReqID:SRS-SQL-XML */
	pre_ora_updatexml_hook = ora_updatexml_hook;
	ora_updatexml_hook = updatexml;
	/* End - ReqID:SRS-SQL-XML */

	/* ProcessUtility hook for DISCARD ALL/PACKAGES */
	prev_ProcessUtility_hook = ProcessUtility_hook;
	ProcessUtility_hook = ivorysql_ora_ProcessUtility;
}

/*
 * Module finalization function.
 *
 * Note that _PG_fini will only be called during an unload of the module,
 * not during process termination. Presently, unloads are disabled and
 * will never occur, but this may change in the future.
 */
void
_PG_fini(void)
{
	/* Uninstall Hooks */
	oracle_datatype_precedence_hook = pre_oracle_datatype_precedence_hook;

	pg_exec_merge_matched_hook = pre_exec_merge_matched_hook;
	pg_transform_merge_stmt_hook = pre_transform_merge_stmt_hook;

	/* Begin - ReqID:SRS-SQL-XML */
	ora_updatexml_hook = pre_ora_updatexml_hook;
	/* End - ReqID:SRS-SQL-XML */

	/* ProcessUtility hook */
	ProcessUtility_hook = prev_ProcessUtility_hook;
}

/*
 * ProcessUtility hook to intercept DISCARD ALL/PACKAGES commands.
 * Resets DBMS_OUTPUT buffer state after these commands execute.
 */
static void
ivorysql_ora_ProcessUtility(PlannedStmt *pstmt,
							const char *queryString,
							bool readOnlyTree,
							ProcessUtilityContext context,
							ParamListInfo params,
							QueryEnvironment *queryEnv,
							DestReceiver *dest,
							QueryCompletion *qc)
{
	Node	   *parsetree = pstmt->utilityStmt;
	bool		is_discard_reset = false;

	/* Check if this is DISCARD ALL or DISCARD PACKAGES */
	if (nodeTag(parsetree) == T_DiscardStmt)
	{
		DiscardStmt *stmt = (DiscardStmt *) parsetree;

		if (stmt->target == DISCARD_ALL || stmt->target == DISCARD_PACKAGES)
			is_discard_reset = true;
	}

	/* Call the previous hook or standard function */
	if (prev_ProcessUtility_hook)
		(*prev_ProcessUtility_hook)(pstmt, queryString, readOnlyTree,
									context, params, queryEnv, dest, qc);
	else
		standard_ProcessUtility(pstmt, queryString, readOnlyTree,
								context, params, queryEnv, dest, qc);

	/* Reset DBMS_OUTPUT buffer after DISCARD ALL/PACKAGES */
	if (is_discard_reset)
		ora_dbms_output_reset();
}
