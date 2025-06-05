/*-------------------------------------------------------------------------
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
#include "parser/parse_oper.h"
#include "parser/parse_merge.h"

/* Begin - ReqID:SRS-SQL-XML */
#include "executor/execExpr.h"
/* End - ReqID:SRS-SQL-XML */

#include "include/guc.h"
#include "include/ivorysql_ora.h"


/* Only include it once in any C file */
PG_MODULE_MAGIC;

/* Saved hook value in case of unload */
static oracle_datatype_precedence_hook_type pre_oracle_datatype_precedence_hook = NULL;

/* The hook of the merge command */
static exec_merge_matched_hook_type pre_exec_merge_matched_hook = NULL;
static transform_merge_stmt_hook_type pre_transform_merge_stmt_hook = NULL;

/* Begin - ReqID:SRS-SQL-XML */
static ora_updatexml_hook_type pre_ora_updatexml_hook = NULL;
/* End - ReqID:SRS-SQL-XML */

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
}
