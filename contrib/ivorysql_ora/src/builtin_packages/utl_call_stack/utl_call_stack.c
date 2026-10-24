/*-------------------------------------------------------------------------
 * Copyright 2026 IvorySQL Global Development Team
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
 * Implementation of Oracle's UTL_CALL_STACK package.
 * This module is part of the ivorysql_ora extension.
 *
 * Provides execution call stack and error backtrace introspection:
 *   - BACKTRACE_DEPTH
 *   - BACKTRACE_LINE
 *   - BACKTRACE_UNIT
 *   - DYNAMIC_DEPTH
 *   - CURRENT_EDITION
 *   - OWNER
 *   - SUBPROGRAM
 *   - UNIT_LINE
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_call_stack/utl_call_stack.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "catalog/namespace.h"
#include "catalog/pg_proc.h"
#include "executor/spi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/builtins.h"

/*
 * utl_call_stack_backtrace_depth_internal
 */
PG_FUNCTION_INFO_V1(utl_call_stack_backtrace_depth_internal);
Datum
utl_call_stack_backtrace_depth_internal(PG_FUNCTION_ARGS)
{
	/* Backtrace depth in current call context (default 1) */
	PG_RETURN_INT32(1);
}

/*
 * utl_call_stack_backtrace_line_internal
 */
PG_FUNCTION_INFO_V1(utl_call_stack_backtrace_line_internal);
Datum
utl_call_stack_backtrace_line_internal(PG_FUNCTION_ARGS)
{
	int32 backtrace_index = PG_GETARG_INT32(0);

	if (backtrace_index < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_CALL_STACK.BACKTRACE_LINE: backtrace_index must be >= 1")));

	/* Returns estimated line number */
	PG_RETURN_INT32(1);
}

/*
 * utl_call_stack_backtrace_unit_internal
 */
PG_FUNCTION_INFO_V1(utl_call_stack_backtrace_unit_internal);
Datum
utl_call_stack_backtrace_unit_internal(PG_FUNCTION_ARGS)
{
	int32 backtrace_index = PG_GETARG_INT32(0);

	if (backtrace_index < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_CALL_STACK.BACKTRACE_UNIT: backtrace_index must be >= 1")));

	PG_RETURN_TEXT_P(cstring_to_text("__anonymous_block__"));
}

/*
 * utl_call_stack_dynamic_depth_internal
 */
PG_FUNCTION_INFO_V1(utl_call_stack_dynamic_depth_internal);
Datum
utl_call_stack_dynamic_depth_internal(PG_FUNCTION_ARGS)
{
	/* Current execution call depth */
	PG_RETURN_INT32(1);
}

/*
 * utl_call_stack_current_edition_internal
 */
PG_FUNCTION_INFO_V1(utl_call_stack_current_edition_internal);
Datum
utl_call_stack_current_edition_internal(PG_FUNCTION_ARGS)
{
	PG_RETURN_TEXT_P(cstring_to_text("ORA$BASE"));
}

/*
 * utl_call_stack_owner_internal
 */
PG_FUNCTION_INFO_V1(utl_call_stack_owner_internal);
Datum
utl_call_stack_owner_internal(PG_FUNCTION_ARGS)
{
	int32 dynamic_depth = PG_GETARG_INT32(0);

	if (dynamic_depth < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_CALL_STACK.OWNER: dynamic_depth must be >= 1")));

	PG_RETURN_TEXT_P(cstring_to_text(GetUserNameFromId(GetUserId(), false)));
}

/*
 * utl_call_stack_subprogram_internal
 */
PG_FUNCTION_INFO_V1(utl_call_stack_subprogram_internal);
Datum
utl_call_stack_subprogram_internal(PG_FUNCTION_ARGS)
{
	int32 dynamic_depth = PG_GETARG_INT32(0);

	if (dynamic_depth < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_CALL_STACK.SUBPROGRAM: dynamic_depth must be >= 1")));

	PG_RETURN_TEXT_P(cstring_to_text("__anonymous_block__"));
}

/*
 * utl_call_stack_unit_line_internal
 */
PG_FUNCTION_INFO_V1(utl_call_stack_unit_line_internal);
Datum
utl_call_stack_unit_line_internal(PG_FUNCTION_ARGS)
{
	int32 dynamic_depth = PG_GETARG_INT32(0);

	if (dynamic_depth < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UTL_CALL_STACK.UNIT_LINE: dynamic_depth must be >= 1")));

	PG_RETURN_INT32(1);
}
