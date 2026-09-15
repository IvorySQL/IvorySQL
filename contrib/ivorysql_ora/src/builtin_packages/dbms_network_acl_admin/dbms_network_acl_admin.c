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
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "catalog/pg_type.h"
#include "commands/packagecmds.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "parser/parse_func.h"
#include "utils/acl.h"

PG_FUNCTION_INFO_V1(ivorysql_network_acl_admin);

/* Authorize the effective invoker before calling the private SECURITY DEFINER function. */
Datum
ivorysql_network_acl_admin(PG_FUNCTION_ARGS)
{
	LOCAL_FCINFO(inner, 12);
	Oid			argtypes[12] = {
		TEXTOID, TEXTOID, TEXTOID, BOOLOID,
		TEXTOID, INT4OID, TIMESTAMPTZOID, TIMESTAMPTZOID,
		TEXTOID, INT4OID, INT4OID, TEXTOID
	};
	Oid			package;
	Oid			implementation;
	FmgrInfo	flinfo;
	Datum		result;
	int			i;

	package = LookupPackageByNames(list_make2(makeString("sys"),
											  makeString("dbms_network_acl_admin")),
								   false);
	if (pg_package_aclcheck(package, GetUserId(), ACL_EXECUTE) != ACLCHECK_OK)
		ereport(ERROR,
				(errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
				 errmsg("permission denied for package dbms_network_acl_admin")));

	implementation = LookupFuncName(list_make2(makeString("sys"),
											   makeString("network_acl_admin_impl")),
									12, argtypes, false);
	fmgr_info(implementation, &flinfo);
	InitFunctionCallInfoData(*inner, &flinfo, 12, fcinfo->fncollation, NULL, NULL);
	for (i = 0; i < 12; i++)
		inner->args[i] = fcinfo->args[i];
	result = FunctionCallInvoke(inner);
	fcinfo->isnull = inner->isnull;
	return result;
}
