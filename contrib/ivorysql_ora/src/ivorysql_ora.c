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
 * Portions Copyright (c) 2023-2026, IvorySQL Global Development Team
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

extern char *utl_file_umask_str;
extern void utl_file_umask_assign_hook(const char *newvalue, void *extra);
extern bool utl_file_umask_check_hook(char **newval, void **extra, GucSource source);

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

	DefineCustomStringVariable("utl_file.umask",
								"Specify umask used by utl_file.fopen.",
								NULL,
								&utl_file_umask_str,
								"0077",
								PGC_USERSET,
								0,
								utl_file_umask_check_hook,
								utl_file_umask_assign_hook, NULL);

	MarkGUCPrefixReserved("ivorysql");
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
 * Reject ALTER ROLE ... SET ivorysql.dbtimezone = ... (with or without
 * IN DATABASE, and ALTER ROLE ALL ... SET) at the command level.
 *
 * check_dbtimezone() (src/guc/guc.c) already refuses to apply such a
 * value at connection time (GucSource PGC_S_USER / PGC_S_DATABASE_USER /
 * PGC_S_GLOBAL) -- but by then the ALTER ROLE command has already
 * succeeded and left a row in pg_db_role_setting that gets rejected (and
 * its WARNING re-printed) on *every* future connection for that
 * role/database, until manually cleaned up. Reject the command itself
 * instead of leaving that landmine behind.
 *
 * RESET / RESET ALL are let through: they remove a pg_db_role_setting
 * entry rather than adding one that can never take effect.
 */
static void
reject_alter_role_dbtimezone(Node *parsetree)
{
	AlterRoleSetStmt *stmt;
	VariableSetStmt *setstmt;

	if (nodeTag(parsetree) != T_AlterRoleSetStmt)
		return;

	stmt = (AlterRoleSetStmt *) parsetree;
	setstmt = stmt->setstmt;

	if (setstmt == NULL || setstmt->name == NULL)
		return;					/* RESET ALL, or malformed */

	if (setstmt->kind == VAR_RESET || setstmt->kind == VAR_RESET_ALL)
		return;					/* clearing an override is always fine */

	if (pg_strcasecmp(setstmt->name, "ivorysql.dbtimezone") == 0)
		ereport(ERROR,
				(errcode(ERRCODE_CANT_CHANGE_RUNTIME_PARAM),
				 errmsg("parameter \"ivorysql.dbtimezone\" cannot be set"),
				 errdetail("\"ivorysql.dbtimezone\" can only be set with "
						   "ALTER DATABASE ... SET, not within a session "
						   "or per-role."),
				 errhint("Use ALTER DATABASE ... SET ivorysql.dbtimezone "
						 "instead, or ALTER ROLE ... RESET "
						 "ivorysql.dbtimezone to remove a stale per-role "
						 "override.")));
}

/*
 * ProcessUtility hook to intercept DISCARD ALL/PACKAGES commands and
 * ALTER ROLE ... SET ivorysql.dbtimezone.
 * Resets DBMS_OUTPUT buffer state after DISCARD ALL/PACKAGES executes.
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

	reject_alter_role_dbtimezone(parsetree);

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

	/* Reset DBMS_OUTPUT buffer and DBMS_SESSION context after DISCARD ALL/PACKAGES */
	if (is_discard_reset)
	{
		ora_dbms_output_reset();
		ora_dbms_session_reset();
	}
}
