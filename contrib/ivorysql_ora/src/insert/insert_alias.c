/*------------------------------------------------------------------
 *
 * File: insert_alias.c
 *
 * Abstract:
 * 		Compatible with Oracle's INSERT alias.col
 *
 *
 * Copyright:
 * Portions Copyright (c) 2024, Ivory SQL Global Development Team
 *
 * Identification:
 *		contrib/ivorysql_ora/src/insert/insert_alias.c
 *
 *------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/sysattr.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "optimizer/optimizer.h"
#include "parser/parse_agg.h"
#include "parser/parse_clause.h"
#include "parser/parse_coerce.h"
#include "parser/parse_collate.h"
#include "parser/parse_cte.h"
#include "parser/parse_expr.h"
#include "parser/parse_func.h"
#include "parser/parse_merge.h"
#include "parser/parse_oper.h"
#include "parser/parse_param.h"
#include "parser/parse_relation.h"
#include "parser/parse_target.h"
#include "parser/parse_type.h"
#include "parser/parsetree.h"
#include "parser/parse_node.h"
#include "rewrite/rewriteManip.h"
#include "utils/backend_status.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/queryjumble.h"
#include "utils/rel.h"
#include "utils/syscache.h"

#include "../include/ivorysql_ora.h"


/*
 * IvyOraGetAttrno
 *
 * Handling alias-qualified columns.
 */
int
IvyOraGetAttrno(ParseState *pstate, ResTarget  *col)
{
	char	   *colname_temp = NULL;
	RangeTblEntry	   *alias_temp = NULL;
	int 		attrno = InvalidAttrNumber;

	if (col->indirection && list_length(col->indirection) == 1 &&
		IsA(linitial(col->indirection), String))
	{
		/* Get real column names */
		colname_temp = strVal(lfirst(list_head(col->indirection)));
		alias_temp = lfirst(list_head(pstate->p_rtable));

		if (alias_temp->alias)
		{
			if (alias_temp->alias->aliasname)
			{
				if (strcmp(col->name, alias_temp->alias->aliasname))
				{
					ereport(ERROR,
							(errcode(ERRCODE_UNDEFINED_COLUMN),
							errmsg("Perhaps you meant to reference the table alias \"%s\"",
									alias_temp->alias->aliasname)));
				}
				else
				{
					if (colname_temp)
					{
						attrno = attnameAttNum(pstate->p_target_relation, colname_temp, true);
						col->name = colname_temp;
						col->indirection = NIL;
					}
				}
			}
		}
		else
		{
			if (col->name && strcmp(col->name, RelationGetRelationName(pstate->p_target_relation)))
			{
				ereport(ERROR,
						(errcode(ERRCODE_UNDEFINED_COLUMN),
						errmsg("Perhaps you meant to assign the table alias \"%s\"",
								col->name)));
			}
			else
			{
				if (colname_temp)
				{
					attrno = attnameAttNum(pstate->p_target_relation, colname_temp, true);
					col->name = colname_temp;
					col->indirection = NIL;
				}
			}
		}
	}

	return attrno;
}
