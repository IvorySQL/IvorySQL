/*-------------------------------------------------------------------------
 *
 * parse_param.c
 *	  handle parameters in parser
 *
 * This code covers two cases that are used within the core backend:
 *		* a fixed list of parameters with known types
 *		* an expandable list of parameters whose types can optionally
 *		  be determined from context
 * In both cases, only explicit $n references (ParamRef nodes) are supported.
 *
 * Note that other approaches to parameters are possible using the parser
 * hooks defined in ParseState.
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 *
 * IDENTIFICATION
 *	  src/backend/parser/parse_param.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include <limits.h>

#include "catalog/pg_type.h"
#include "nodes/nodeFuncs.h"
#include "parser/parse_param.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "catalog/pg_proc.h"
#include "miscadmin.h"
#include "utils/memutils.h"


typedef struct FixedParamState
{
	const Oid  *paramTypes;		/* array of parameter type OIDs */
	int			numParams;		/* number of array entries */
} FixedParamState;

/*
 * In the varparams case, the caller-supplied OID array (if any) can be
 * re-palloc'd larger at need.  A zero array entry means that parameter number
 * hasn't been seen, while UNKNOWNOID means the parameter has been used but
 * its type is not yet known.
 */
typedef struct VarParamState
{
	Oid		  **paramTypes;		/* array of parameter type OIDs */
	int		   *numParams;		/* number of array entries */
	Oid		  *paramTypeWithMask; 	/* array of parameter type OIDs with mask */
} VarParamState;

typedef struct OraParamNumber
{
	int 	number;
	char*	name;
}OraParamNumber;

typedef struct OraParamNumbers
{
	int  			param_max;
	int   			param_count;
	int             level;
	OraParamNumber* params;
	MemoryContext   mcontext;
	struct OraParamNumbers* prev;
}OraParamNumbers;

OraParamNumbers *TopOraParamNode = NULL;
OraParamNumbers *CurrentOraParamNode = NULL;

/*
 * dynamic sql stmt parse information
 * IsParseDynSql: grammer is parsing dynamic sql.
 * IsParseDynDoStmt: grammer is parsing dynamic sql that is DoStmt.
 * HasPgParam: grammer found pg model variables like $1...$n.
 * DoStmtCheckVar: wether should check bound var matching.
 * Should not check var bound match for grammer:
 *     'select xxx; begin xxx end;begin xxx end;'
 * IsBindByName: the paramter is bound by name.
 * When compile DoStmt, DoStmt always gets compiled after other stmt.
 */
static bool			IsParseDynSql = false;
static bool			IsParseDynDoStmt = true;
static bool			HasPgParam = false;
static bool			DoStmtCheckVar = false;
static bool			IsBindByName = false;

/*
 * store the OraParam name and position
 */
typedef struct OraParamState
{
	int maxparams;		/* max size of paramNames */
	int numParams;		/* real size of params */
	char **paramNames;	/* store the parameter'name */
}OraParamState;


static Node *fixed_paramref_hook(ParseState *pstate, ParamRef *pref);
static Node *variable_paramref_hook(ParseState *pstate, ParamRef *pref);
static Node *variable_coerce_param_hook(ParseState *pstate, Param *param,
										Oid targetTypeId, int32 targetTypeMod,
										int location);
static bool check_parameter_resolution_walker(Node *node, ParseState *pstate);
static bool query_contains_extern_params_walker(Node *node, void *context);
static bool calculate_oraparamnumbers_walker(Node *node, void *context);
static bool raw_calculate_oraparamnumbers_walker(Node *node,
							bool(*walker) (),
							void *context);
static bool calculate_oraparamname_walker(Node *node, void *state);


/*
 * Set up to process a query containing references to fixed parameters.
 */
void
setup_parse_fixed_parameters(ParseState *pstate,
							 const Oid *paramTypes, int numParams)
{
	FixedParamState *parstate = palloc(sizeof(FixedParamState));

	parstate->paramTypes = paramTypes;
	parstate->numParams = numParams;
	pstate->p_ref_hook_state = parstate;
	pstate->p_paramref_hook = fixed_paramref_hook;
	/* no need to use p_coerce_param_hook */
}

/*
 * Set up to process a query containing references to variable parameters.
 */
void
setup_parse_variable_parameters(ParseState *pstate,
								Oid **paramTypes, int *numParams)
{
	VarParamState *parstate = palloc(sizeof(VarParamState));

	/*
	 * get the real paramTypes(reset 32nd-30nd bit of 32 bit Oid)
	 */
	Oid 		  *paramTypeWithMask = NULL;
	int 		   i;

	if (*numParams > 0)
		paramTypeWithMask = palloc0(sizeof(Oid) * (*numParams));

	for (i = 0; i < *numParams; i++)
	{
		paramTypeWithMask[i] = (*paramTypes)[i];
		UnSetModeOut((*paramTypes)[i]);
	}
	parstate->paramTypeWithMask = paramTypeWithMask;
	pstate->p_isVarParamState = true;

	parstate->paramTypes = paramTypes;
	parstate->numParams = numParams;
	pstate->p_ref_hook_state = parstate;
	pstate->p_paramref_hook = variable_paramref_hook;
	pstate->p_coerce_param_hook = variable_coerce_param_hook;
}

/*
 * Transform a ParamRef using fixed parameter types.
 */
static Node *
fixed_paramref_hook(ParseState *pstate, ParamRef *pref)
{
	FixedParamState *parstate = (FixedParamState *) pstate->p_ref_hook_state;
	int			paramno = pref->number;
	Param	   *param;

	/* Check parameter number is valid */
	if (paramno <= 0 || paramno > parstate->numParams ||
		!OidIsValid(parstate->paramTypes[paramno - 1]))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_PARAMETER),
				IsA(pref, OraParamRef) ? errmsg("there is no parameter %s", ((OraParamRef*)pref)->name) :
				 errmsg("there is no parameter $%d", pref->number),
				 parser_errposition(pstate, pref->location)));

	param = makeNode(Param);
	param->paramkind = PARAM_EXTERN;
	param->paramid = paramno;
	param->paramtype = parstate->paramTypes[paramno - 1];
	param->paramtypmod = -1;
	param->paramcollid = get_typcollation(param->paramtype);
	param->location = pref->location;

	return (Node *) param;
}

/*
 * Transform a ParamRef using variable parameter types.
 *
 * The only difference here is we must enlarge the parameter type array
 * as needed.
 */
static Node *
variable_paramref_hook(ParseState *pstate, ParamRef *pref)
{
	VarParamState *parstate = (VarParamState *) pstate->p_ref_hook_state;
	int			paramno = pref->number;
	Oid		   *pptype;
	Param	   *param;

	/* Check parameter number is in range */
	if (paramno <= 0 || paramno > MaxAllocSize / sizeof(Oid))
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_PARAMETER),
				 errmsg("there is no parameter $%d", paramno),
				 parser_errposition(pstate, pref->location)));
	if (paramno > *parstate->numParams)
	{
		/* Need to enlarge param array */
		if (*parstate->paramTypes)
			*parstate->paramTypes = repalloc0_array(*parstate->paramTypes, Oid,
													*parstate->numParams, paramno);
		else
			*parstate->paramTypes = palloc0_array(Oid, paramno);
		*parstate->numParams = paramno;
	}

	/* Locate param's slot in array */
	pptype = &(*parstate->paramTypes)[paramno - 1];

	/* If not seen before, initialize to UNKNOWN type */
	if (*pptype == InvalidOid)
		*pptype = UNKNOWNOID;

	/*
	 * If the argument is of type void and it's procedure call, interpret it
	 * as unknown.  This allows the JDBC driver to not have to distinguish
	 * function and procedure calls.  See also another component of this hack
	 * in ParseFuncOrColumn().
	 */
	if (*pptype == VOIDOID && pstate->p_expr_kind == EXPR_KIND_CALL_ARGUMENT)
		*pptype = UNKNOWNOID;

	param = makeNode(Param);
	param->paramkind = PARAM_EXTERN;
	param->paramid = paramno;
	param->paramtype = *pptype;
	param->paramtypmod = -1;
	param->paramcollid = get_typcollation(param->paramtype);
	param->location = pref->location;

	return (Node *) param;
}

/*
 * Coerce a Param to a query-requested datatype, in the varparams case.
 */
static Node *
variable_coerce_param_hook(ParseState *pstate, Param *param,
						   Oid targetTypeId, int32 targetTypeMod,
						   int location)
{
	if (param->paramkind == PARAM_EXTERN && param->paramtype == UNKNOWNOID)
	{
		/*
		 * Input is a Param of previously undetermined type, and we want to
		 * update our knowledge of the Param's type.
		 */
		VarParamState *parstate = (VarParamState *) pstate->p_ref_hook_state;
		Oid		   *paramTypes = *parstate->paramTypes;
		int			paramno = param->paramid;

		if (paramno <= 0 ||		/* shouldn't happen, but... */
			paramno > *parstate->numParams)
			ereport(ERROR,
					(errcode(ERRCODE_UNDEFINED_PARAMETER),
					 errmsg("there is no parameter $%d", paramno),
					 parser_errposition(pstate, param->location)));

		if (paramTypes[paramno - 1] == UNKNOWNOID)
		{
			/* We've successfully resolved the type */
			paramTypes[paramno - 1] = targetTypeId;
		}
		else if (paramTypes[paramno - 1] == targetTypeId)
		{
			/* We previously resolved the type, and it matches */
		}
		else
		{
			/* Oops */
			ereport(ERROR,
					(errcode(ERRCODE_AMBIGUOUS_PARAMETER),
					 errmsg("inconsistent types deduced for parameter $%d",
							paramno),
					 errdetail("%s versus %s",
							   format_type_be(paramTypes[paramno - 1]),
							   format_type_be(targetTypeId)),
					 parser_errposition(pstate, param->location)));
		}

		param->paramtype = targetTypeId;

		/*
		 * Note: it is tempting here to set the Param's paramtypmod to
		 * targetTypeMod, but that is probably unwise because we have no
		 * infrastructure that enforces that the value delivered for a Param
		 * will match any particular typmod.  Leaving it -1 ensures that a
		 * run-time length check/coercion will occur if needed.
		 */
		param->paramtypmod = -1;

		/*
		 * This module always sets a Param's collation to be the default for
		 * its datatype.  If that's not what you want, you should be using the
		 * more general parser substitution hooks.
		 */
		param->paramcollid = get_typcollation(param->paramtype);

		/* Use the leftmost of the param's and coercion's locations */
		if (location >= 0 &&
			(param->location < 0 || location < param->location))
			param->location = location;

		return (Node *) param;
	}

	/* Else signal to proceed with normal coercion */
	return NULL;
}

/*
 * Check for consistent assignment of variable parameters after completion
 * of parsing with parse_variable_parameters.
 *
 * Note: this code intentionally does not check that all parameter positions
 * were used, nor that all got non-UNKNOWN types assigned.  Caller of parser
 * should enforce that if it's important.
 */
void
check_variable_parameters(ParseState *pstate, Query *query)
{
	VarParamState *parstate = (VarParamState *) pstate->p_ref_hook_state;

	/* If numParams is zero then no Params were generated, so no work */
	if (*parstate->numParams > 0)
		(void) query_tree_walker(query,
								 check_parameter_resolution_walker,
								 pstate, 0);
}

/*
 * Traverse a fully-analyzed tree to verify that parameter symbols
 * match their types.  We need this because some Params might still
 * be UNKNOWN, if there wasn't anything to force their coercion,
 * and yet other instances seen later might have gotten coerced.
 */
static bool
check_parameter_resolution_walker(Node *node, ParseState *pstate)
{
	if (node == NULL)
		return false;
	if (IsA(node, Param))
	{
		Param	   *param = (Param *) node;

		if (param->paramkind == PARAM_EXTERN)
		{
			VarParamState *parstate = (VarParamState *) pstate->p_ref_hook_state;
			int			paramno = param->paramid;

			if (paramno <= 0 || /* shouldn't happen, but... */
				paramno > *parstate->numParams)
				ereport(ERROR,
						(errcode(ERRCODE_UNDEFINED_PARAMETER),
						 errmsg("there is no parameter $%d", paramno),
						 parser_errposition(pstate, param->location)));

			if (param->paramtype != (*parstate->paramTypes)[paramno - 1])
				ereport(ERROR,
						(errcode(ERRCODE_AMBIGUOUS_PARAMETER),
						 errmsg("could not determine data type of parameter $%d",
								paramno),
						 parser_errposition(pstate, param->location)));
		}
		return false;
	}
	if (IsA(node, Query))
	{
		/* Recurse into RTE subquery or not-yet-planned sublink subquery */
		return query_tree_walker((Query *) node,
								 check_parameter_resolution_walker,
								 pstate, 0);
	}
	return expression_tree_walker(node, check_parameter_resolution_walker,
								  pstate);
}

/*
 * Check to see if a fully-parsed query tree contains any PARAM_EXTERN Params.
 */
bool
query_contains_extern_params(Query *query)
{
	return query_tree_walker(query,
							 query_contains_extern_params_walker,
							 NULL, 0);
}

static bool
query_contains_extern_params_walker(Node *node, void *context)
{
	if (node == NULL)
		return false;
	if (IsA(node, Param))
	{
		Param	   *param = (Param *) node;

		if (param->paramkind == PARAM_EXTERN)
			return true;
		return false;
	}
	if (IsA(node, Query))
	{
		/* Recurse into RTE subquery or not-yet-planned sublink subquery */
		return query_tree_walker((Query *) node,
								 query_contains_extern_params_walker,
								 context, 0);
	}
	return expression_tree_walker(node, query_contains_extern_params_walker,
								  context);
}


Node *
ParseParamVariable(Node *arg)
{
	Node *result = arg;
	if (IsA(arg, Param))
	{
		return result;
	}

	if (IsA(arg, RelabelType))
	{
		result = (Node *)((RelabelType *)arg)->arg;
		return ParseParamVariable(result);
	}

	if (IsA(arg, FuncExpr))
	{
		List *args = ((FuncExpr *)arg)->args;
		if (((FuncExpr*)arg)->funcformat != COERCE_EXPLICIT_CALL)
			return ParseParamVariable((Node *)linitial(args));
	}
	else if (IsA(arg, CoerceViaIO))
	{
		result = (Node *) ((CoerceViaIO *)arg)->arg;
		return ParseParamVariable(result);
	}
	else if (IsA(arg, ArrayCoerceExpr))
	{
		result = (Node *) ((ArrayCoerceExpr *)arg)->arg;
		return ParseParamVariable(result);
	}

	return result;
}

/*
 * get the parameter type mode 
 */
void
GetParamMode(Oid *paramTypes, int numParams, char *modes)
{
	int	i;

	for (i = 0; i < numParams; i++)
	{
		if (IsModeIn(paramTypes[i]) && IsModeOut(paramTypes[i]))
			modes[i] = PROARGMODE_INOUT;
		else if (IsModeOut(paramTypes[i]))
			modes[i] = PROARGMODE_OUT;
		else
			modes[i] = PROARGMODE_IN;
	}

	return;
}

void
ParseVarParamState(void *arg, Node *param, bool *isOut,
			bool *isIn, bool *isLeftCall)
{
	int 		   index;
	Oid 		   type;
	VarParamState 	*vps = (VarParamState *) arg;
	Oid 	  	*ptypes = vps->paramTypeWithMask;

	if (!ptypes)
		return;

	index = ((Param *) param)->paramid - 1;
	type = ptypes[index];

	*isOut = IsModeOut(type);
	*isIn = IsModeIn(type);
	*isLeftCall = IsLeftCall(type);

	/* If parameter type oid is UNKNOWNOID, reset it to be VOIDOID */
	if (*isLeftCall && (*vps->paramTypes)[index] == UNKNOWNOID)
	{
		(*vps->paramTypes)[index] = VOIDOID;
	}

	return;
}

/*
 * SetVarParamState
 */
void
SetVarParamState(void *arg, Param *param, int index)
{
	VarParamState *vps = (VarParamState *) arg;

	/* set mask mode for parameter type */
	if (vps && vps->paramTypeWithMask)
	{
		if (IsModeIn(vps->paramTypeWithMask[index]))
			SetModeIn(param->paramtype);
		if (IsModeOut(vps->paramTypeWithMask[index]))
			SetModeOut(param->paramtype);
	}

	return;
}

void
get_oraparam_level(int *top_level, int *cur_level)
{
	if (top_level != NULL)
	{
		if (TopOraParamNode == NULL)
			*top_level = 0;
		else
			*top_level = TopOraParamNode->level;
	}
	if (cur_level != NULL)
	{
		if (CurrentOraParamNode == NULL)
			*cur_level = 0;
		else
			*cur_level = CurrentOraParamNode->level;
	}

	return;
}


int
push_oraparam_stack(void)
{
	OraParamNumbers *new;

	new = palloc0(sizeof(OraParamNumbers));
	new->params = palloc0(sizeof(OraParamNumber)* 8);
	new->param_max = 8;
	new->mcontext = CurrentMemoryContext;

	if (TopOraParamNode == NULL)
	{
		IsParseDynSql = false;
		IsParseDynDoStmt = true;
		HasPgParam = false;
		DoStmtCheckVar = false;
		new->level = 1;
	}
	else
	{
		new->level = TopOraParamNode->level + 1;
	}

	new->prev = TopOraParamNode;
	TopOraParamNode = new;

	return new->level;
}

void
pop_oraparam_stack(int top, int cur)
{
	Assert(top >= cur);

	while (TopOraParamNode != NULL && top >= 0 && TopOraParamNode->level > top)
	{
		int i;
		OraParamNumbers *node = TopOraParamNode;
		TopOraParamNode = TopOraParamNode->prev;

		for (i = 0; i < node->param_count; ++i)
		{
			pfree(node->params[i].name);
		}
		
		pfree(node->params);
		pfree(node);		
	}

	CurrentOraParamNode = TopOraParamNode;

	while (CurrentOraParamNode != NULL && cur >= 0 && CurrentOraParamNode->level > cur)
	{		
		CurrentOraParamNode = CurrentOraParamNode->prev;		
	}
	
	return;
}

void
forward_oraparam_stack(void)
{
	CurrentOraParamNode = TopOraParamNode;

	if (CurrentOraParamNode != NULL)
	{
		CurrentOraParamNode->param_count = 0;
	}

	return;
}

void
backward_oraparam_stack(void)
{	
	if (CurrentOraParamNode != NULL)
	{
		CurrentOraParamNode = CurrentOraParamNode->prev;
	}

	return;
}

int
calculate_oraparamnumber(const char* name)
{
	 int i = 0;
	 int number = 0;
	 MemoryContext oldcontext;

	 if (CurrentOraParamNode == NULL)
		 return 0;
	 
	 if (IsParseDynDoStmt)
	 {
		 for (i = 0; i < CurrentOraParamNode->param_count; ++i)
		 {
			 if (strcmp(CurrentOraParamNode->params[i].name, name) == 0)
			 {			 
				 return CurrentOraParamNode->params[i].number;
			 }
		 }
	 }
	 
	 if (CurrentOraParamNode->param_count >= CurrentOraParamNode->param_max)
	 {
		 CurrentOraParamNode->params = (OraParamNumber*) repalloc(CurrentOraParamNode->params, 
							sizeof(OraParamNumber)*CurrentOraParamNode->param_max * 2);
		 CurrentOraParamNode->param_max *= 2;
	 }
	 
	 number = CurrentOraParamNode->param_count + 1;
	 
	 oldcontext = MemoryContextSwitchTo(CurrentOraParamNode->mcontext);
	 CurrentOraParamNode->params[CurrentOraParamNode->param_count].name = pstrdup(name);
	 MemoryContextSwitchTo(oldcontext);
	 
	 CurrentOraParamNode->params[CurrentOraParamNode->param_count++].number = number;	 
	 return number;  
}

bool
calculate_oraparamnumbers(List *parsetree_list)
{
	ListCell *parsetree_item = NULL;

	foreach(parsetree_item, parsetree_list)
	{
		Node *parsetree = (Node *)lfirst(parsetree_item);

		if (calculate_oraparamnumbers_walker(parsetree, NULL) == true)
			return true;
	}

	return false;
}

static bool
calculate_oraparamnumbers_walker(Node *node, void *context)
{
	if (node == NULL)
		return false;

	if (IsA(node, OraParamRef))
	{	
		OraParamRef *pref = (OraParamRef*)node;
		int number = calculate_oraparamnumber(pref->name);

		if (pref->number <= 0)
		{
			pref->number = number;
		}
		else
		{
			Assert(pref->number == number);
		}

		return false;
	
	}
	else if (!HasPgParam && IsA(node, ParamRef))
	{
		HasPgParam = true;
	}
	else
	{
		return raw_calculate_oraparamnumbers_walker(node, 
				calculate_oraparamnumbers_walker,
				context);
	}

	return false;
}

static bool
raw_calculate_oraparamnumbers_walker(Node *node,
					bool(*walker) (),
					void *context)
{
	ListCell   *temp = NULL;

	/*
	* recurse into any sub-nodes that current node has.
	*/
	if (node == NULL)
		return false;

	check_stack_depth();

	switch (nodeTag(node))
	{
		case T_CreateDomainStmt:
		{
			CreateDomainStmt    *stmt = (CreateDomainStmt *)node;
			if (walker(stmt->domainname, context))
				return true;
			if (walker(stmt->typeName, context))
				return true;
			if (walker(stmt->constraints, context))
				return true;
		}
			break;
		case T_AlterDomainStmt:
		{
			AlterDomainStmt    *stmt = (AlterDomainStmt *)node;
			if (walker(stmt->typeName, context))
				return true;
			if (walker(stmt->def, context))
				return true;
		}	
			break;
		case T_CreatePolicyStmt:
		{
			CreatePolicyStmt    *stmt = (CreatePolicyStmt *)node;
			if (walker(stmt->table, context))
				return true;
			if (walker(stmt->roles, context))
				return true;
			if (walker(stmt->qual, context))
				return true;
			if (walker(stmt->with_check, context))
				return true;
		}
			break;
		case T_AlterPolicyStmt:
		{
			AlterPolicyStmt    *stmt = (AlterPolicyStmt *)node;
			if (walker(stmt->table, context))
				return true;
			if (walker(stmt->roles, context))
				return true;
			if (walker(stmt->qual, context))
				return true;
			if (walker(stmt->with_check, context))
				return true;
		}
			break;
		case T_CreateTrigStmt:
		{
			CreateTrigStmt    *stmt = (CreateTrigStmt *)node;
			if (walker(stmt->relation, context))
				return true;
			if (walker(stmt->whenClause, context))
				return true;
			if (walker(stmt->funcname, context))
				return true;
			if (walker(stmt->args, context))
				return true;
			if (walker(stmt->columns, context))
				return true;
			if (walker(stmt->constrrel, context))
				return true;
		
		}
			break;
		case T_IndexStmt:
		{
			IndexStmt    *stmt = (IndexStmt *)node;
			if (walker(stmt->relation, context))
				return true;
			if (walker(stmt->indexParams, context))
				return true;
			if (walker(stmt->options, context))
				return true;
			if (walker(stmt->whereClause, context))
				return true;
			if (walker(stmt->excludeOpNames, context))
				return true;		
		}
			break;
		case T_RuleStmt:
		{
			RuleStmt    *stmt = (RuleStmt *)node;
			if (walker(stmt->relation, context))
				return true;
			if (walker(stmt->whereClause, context))
				return true;
			if (walker(stmt->actions, context))
				return true;		
		}
			break;
		case T_DeleteStmt:
		{
			DeleteStmt    *stmt = (DeleteStmt *)node;
			if (walker(stmt->relation, context))
				return true;
			if (walker(stmt->usingClause, context))
				return true;
			if (walker(stmt->whereClause, context))
				return true;
			if (walker(stmt->returningClause, context))
				return true;		
			if (walker(stmt->withClause, context))
				return true;		
		}
			break;
		case T_UpdateStmt:
		{
			UpdateStmt    *stmt = (UpdateStmt *)node;
			if (walker(stmt->relation, context))
				return true;
			if (walker(stmt->targetList, context))
				return true;
			if (walker(stmt->fromClause, context))
				return true;
			if (walker(stmt->whereClause, context))
				return true;		
			if (walker(stmt->returningClause, context))
				return true;		
			if (walker(stmt->withClause, context))
				return true;		
		}
			break;
		case T_AlterTableStmt:
		{
			AlterTableStmt    *stmt = (AlterTableStmt *)node;
			if (walker(stmt->relation, context))
				return true;
			if (walker(stmt->cmds, context))
				return true;			
		}
			break;
		case T_AlterTableCmd:
		{
			AlterTableCmd    *stmt = (AlterTableCmd *)node;
			if (walker(stmt->newowner, context))
				return true;
			if (walker(stmt->def, context))
				return true;
			
		}
			break;
		case T_CreateFunctionStmt:
		{
			CreateFunctionStmt *stmt = (CreateFunctionStmt*)node;
			if (walker(stmt->funcname,context))
				return true;
			if (walker(stmt->parameters,context))
				return true;
			if (walker(stmt->returnType,context))
				return true;
			if (walker(stmt->options,context))
				return true;
		}
			break;
		case T_SelectStmt:
		{
			 SelectStmt *stmt = (SelectStmt *)node;

			 if (walker(stmt->distinctClause, context))
				 return true;
			 if (walker(stmt->intoClause, context))
				 return true;
			 if (walker(stmt->targetList, context))
				 return true;
			 if (walker(stmt->fromClause, context))
				 return true;
			 if (walker(stmt->whereClause, context))
				 return true;		 
			 if (walker(stmt->groupClause, context))
				 return true;		 
			 if (walker(stmt->havingClause, context))
				 return true;
			 if (walker(stmt->windowClause, context))
				 return true;
			 if (walker(stmt->valuesLists, context))
				 return true;
			 if (walker(stmt->sortClause, context))
				 return true;
			 if (walker(stmt->limitOffset, context))
				 return true;
			 if (walker(stmt->lockingClause, context))
				 return true;
			 if (walker(stmt->withClause, context))
				 return true;
			 if (walker(stmt->larg, context))
				 return true;
			 if (walker(stmt->rarg, context))
				 return true;
		}
			break;
		case T_InsertStmt:
		{
			 InsertStmt *stmt = (InsertStmt *)node;

			 if (walker(stmt->relation, context))
				 return true;
			 if (walker(stmt->cols, context))
				 return true;
			 if (walker(stmt->selectStmt, context))
				 return true;
			 if (walker(stmt->onConflictClause, context))
				 return true;
			 if (walker(stmt->returningClause, context))
				 return true;
			 if (walker(stmt->withClause, context))
				 return true;
		}
			break;
		case T_CreateSchemaStmt:
		{
			 CreateSchemaStmt *stmt = (CreateSchemaStmt *)node;
	
			 if (walker(stmt->authrole, context))
		  		 return true;
			 if (walker(stmt->schemaElts, context))
				 return true;
		}
			break;
		case T_AlterObjectSchemaStmt:
		{
			 AlterObjectSchemaStmt *stmt = (AlterObjectSchemaStmt *)node;
	
			if (walker(stmt->relation, context))
				return true;
			 if (walker(stmt->object, context))
				 return true;
		}
			break;
		case T_ExecuteStmt:
			return walker(((ExecuteStmt *)node)->params, context);
		case T_CreateTableAsStmt:
		{
			 CreateTableAsStmt *stmt = (CreateTableAsStmt *)node;
	
			 if (walker(stmt->query, context))
				 return true;
			 if (walker(stmt->into, context))
				 return true;
		}
			break;
		case T_CreateStmt:
		{
			 CreateStmt *stmt = (CreateStmt *)node;

			 if (walker(stmt->relation, context))
				 return true;
			 if (walker(stmt->tableElts, context))
				 return true;
			 if (walker(stmt->inhRelations, context))
				 return true;
			 if (walker(stmt->ofTypename, context))
				 return true;
			 if (walker(stmt->constraints, context))
				 return true;
			 if (walker(stmt->options, context))
				 return true;
		}
			break;			
		case T_CreateForeignTableStmt:
		{
			 CreateForeignTableStmt *stmt = (CreateForeignTableStmt *)node;

			 if (walker(stmt->base.relation, context))
				 return true;
			 if (walker(stmt->base.tableElts, context))
				 return true;
			 if (walker(stmt->base.inhRelations, context))
				 return true;
			 if (walker(stmt->base.ofTypename, context))
				 return true;
			 if (walker(stmt->base.constraints, context))
				 return true;
			 if (walker(stmt->base.options, context))
				 return true;
			 if (walker(stmt->options, context))
				 return true;
		}
			break;			
		case T_AlterExtensionContentsStmt:
		{
			 AlterExtensionContentsStmt *stmt = (AlterExtensionContentsStmt *)node;

			 if (walker(stmt->extname, context))
				 return true;
			 if (walker(stmt->object, context))
				 return true;
		}
			break;			
		case T_CreateOpClassStmt:
		{
			 CreateOpClassStmt *stmt = (CreateOpClassStmt *)node;

			 if (walker(stmt->opclassname, context))
				 return true;
			 if (walker(stmt->datatype, context))
				 return true;
			 if (walker(stmt->opfamilyname, context))
				 return true;
			 if (walker(stmt->items, context))
				 return true;
		}
			break;			
		case T_AlterOpFamilyStmt:
		{
			 AlterOpFamilyStmt *stmt = (AlterOpFamilyStmt *)node;

			 if (walker(stmt->opfamilyname, context))
				 return true;
			 if (walker(stmt->items, context))
				 return true;
		}
			break;			
		case T_DropStmt:
		{
			 DropStmt *stmt = (DropStmt *)node;

			 if (walker(stmt->objects, context))
				 return true;
		}
			break;			
		case T_CommentStmt:
		{
			 CommentStmt *stmt = (CommentStmt *)node;

			 if (walker(stmt->object, context))
				 return true;
		}
			break;			
		case T_SecLabelStmt:
		{
			 SecLabelStmt *stmt = (SecLabelStmt *)node;

			 if (walker(stmt->object, context))
				 return true;
		}
			break;			
		case T_CreateCastStmt:
		{
			 CreateCastStmt *stmt = (CreateCastStmt *)node;

			 if (walker(stmt->sourcetype, context))
				 return true;
			 if (walker(stmt->targettype, context))
				 return true;
			 if (walker(stmt->func, context))
				 return true;
		}
			break;			
		case T_CreateTransformStmt:
		{
			 CreateTransformStmt *stmt = (CreateTransformStmt *)node;

			 if (walker(stmt->type_name, context))
				 return true;
			 if (walker(stmt->fromsql, context))
				 return true;
			 if (walker(stmt->tosql, context))
				 return true;
		}
			break;			
		case T_DefineStmt:
		{
			 DefineStmt *stmt = (DefineStmt *)node;

			 if (walker(stmt->defnames, context))
				 return true;
			 if (walker(stmt->args, context))
				 return true;
			 if (walker(stmt->definition, context))
				 return true;
		}
			break;			
		case T_AlterOwnerStmt:
		{
			 AlterOwnerStmt *stmt = (AlterOwnerStmt *)node;

			if (walker(stmt->relation, context))
				 return true;
			 if (walker(stmt->object, context))
				 return true;
			 if (walker(stmt->newowner, context))
				 return true;
		}
			break;			
		case T_PrepareStmt:
		{
			 PrepareStmt *stmt = (PrepareStmt *)node;

			 if (walker(stmt->argtypes, context))
				 return true;
			 if (walker(stmt->query, context))
				 return true;
		}
			break;			
		case T_CreateTableSpaceStmt:
		{
			 CreateTableSpaceStmt *stmt = (CreateTableSpaceStmt *)node;

			 if (walker(stmt->owner, context))
				 return true;
			 if (walker(stmt->options, context))
				 return true;
		}
			break;					
		case T_ViewStmt:
		{
			 ViewStmt *stmt = (ViewStmt *)node;

			if (walker(stmt->view, context))
				 return true;
			 if (walker(stmt->aliases, context))
				 return true;
			 if (walker(stmt->query, context))
				 return true;
			 if (walker(stmt->options, context))
				 return true;
		}
			break;			
		case T_RenameStmt:
		{
			 RenameStmt *stmt = (RenameStmt *)node;

			if (walker(stmt->relation, context))
				 return true;
			 if (walker(stmt->object, context))
				 return true;
		}
			break;			
		case T_AlterFunctionStmt:
		{
			 AlterFunctionStmt *stmt = (AlterFunctionStmt *)node;

			 if (walker(stmt->func, context))
				 return true;
			 if (walker(stmt->actions, context))
				 return true;
		}
			break;			
		case T_AlterTableSpaceOptionsStmt:
		{
			 AlterTableSpaceOptionsStmt *stmt = (AlterTableSpaceOptionsStmt *)node;

			 if (walker(stmt->options, context))
				 return true;
		}
			break;			
		case T_AlterTSDictionaryStmt:
		{
			 AlterTSDictionaryStmt *stmt = (AlterTSDictionaryStmt *)node;

			 if (walker(stmt->dictname, context))
				 return true;
			 if (walker(stmt->options, context))
				 return true;
		}
			break;			
		case T_GrantStmt:
		{
			 GrantStmt *stmt = (GrantStmt *)node;

			 if (walker(stmt->objects, context))
				 return true;
			 if (walker(stmt->privileges, context))
				 return true;
			 if (walker(stmt->grantees, context))
				 return true;
		}
			break;		
		case T_GrantRoleStmt:
		{
			 GrantRoleStmt *stmt = (GrantRoleStmt *)node;

			 if (walker(stmt->granted_roles, context))
				 return true;
			 if (walker(stmt->grantee_roles, context))
				 return true;
			 if (walker(stmt->grantor, context))
				 return true;
		}
			break;	
		case T_AlterDefaultPrivilegesStmt:
		{
			 AlterDefaultPrivilegesStmt *stmt = (AlterDefaultPrivilegesStmt *)node;

			 if (walker(stmt->options, context))
				 return true;
			 if (walker(stmt->action, context))
				 return true;		
		}
			break;			
		case T_AccessPriv:
		{
			 AccessPriv *stmt = (AccessPriv *)node;
	
			 if (walker(stmt->cols, context))
				 return true;
		}
			break;		
		case T_GroupingFunc:
		{
			 GroupingFunc *stmt = (GroupingFunc *)node;
	
			 if (walker(stmt->args, context))
				 return true;
			 if (walker(stmt->refs, context))
				 return true;
			 if (walker(stmt->cols, context))
				 return true;
		}
			break;	
		case T_Query:
		{
			Query *stmt = (Query*)node;

			if (walker(stmt->utilityStmt, context))
				return true;
			 if (walker(stmt->cteList, context))
				 return true;
			 if (walker(stmt->rtable, context))
				 return true;
			 if (walker(stmt->jointree, context))
				 return true;		
			if (walker(stmt->targetList, context))
				return true;
			if (walker(stmt->onConflict, context))
				return true;
			if (walker(stmt->returningList, context))
				return true;
			if (walker(stmt->groupClause, context))
				return true;
			if (walker(stmt->groupingSets, context))
				return true;
			if (walker(stmt->havingQual, context))
				return true;
			if (walker(stmt->windowClause, context))
				return true;
			if (walker(stmt->distinctClause, context))
				return true;
			if (walker(stmt->sortClause, context))
				return true;
			if (walker(stmt->limitOffset, context))
				return true;
			if (walker(stmt->limitCount, context))
				return true;		
			if (walker(stmt->rowMarks, context))
				return true;
			if (walker(stmt->setOperations, context))
				return true;
			if (walker(stmt->constraintDeps, context))
				return true;
			if (walker(stmt->withCheckOptions, context))
				return true;
		}
			break;
		case T_TypeName:
		{
			TypeName *stmt = (TypeName*)node;

			if (walker(stmt->names, context))
				return true;
			 if (walker(stmt->typmods, context))
				 return true;
			 if (walker(stmt->arrayBounds, context))
				 return true;
		}
			break;
		case T_ColumnRef:
		{
			ColumnRef *stmt = (ColumnRef*)node;

			if (walker(stmt->fields, context))
				return true;		 
		}
			break;
		case T_A_Expr:
		{
			A_Expr *stmt = (A_Expr*)node;

			if (walker(stmt->name, context))
				return true;
			if (walker(stmt->lexpr, context))
				return true;
			if (walker(stmt->rexpr, context))
				return true;		 
		}
			break;
		case T_TypeCast:
		{
		   TypeCast   *stmt = (TypeCast *)node;

		   if (walker(stmt->arg, context))
			   return true;
		   if (walker(stmt->typeName, context))
			   return true;
		}
			break;
		case T_CollateClause:
		{
		   CollateClause   *stmt = (CollateClause *)node;
	
		   if (walker(stmt->arg, context))
			   return true;
		   if (walker(stmt->collname, context))
			   return true;
		}
			break;
		case T_FuncCall:
		{
			FuncCall   *stmt = (FuncCall *)node;
	
			if (walker(stmt->funcname, context))
				return true;
			if (walker(stmt->args, context))
				return true;
			if (walker(stmt->agg_order, context))
				return true;
			if (walker(stmt->agg_filter, context))
				return true;
			if (walker(stmt->over, context))
				return true;
		}
			break;
		case T_A_Indices:
		{
		   A_Indices   *stmt = (A_Indices *)node;
	
		   if (walker(stmt->lidx, context))
			   return true;
		   if (walker(stmt->uidx, context))
			   return true;
		}
			break;
		case T_A_Indirection:
		{
		   A_Indirection   *stmt = (A_Indirection *)node;
	
		   if (walker(stmt->arg, context))
			   return true;
		   if (walker(stmt->indirection, context))
			   return true;
		}
			break;
		case T_A_ArrayExpr:
		{
		   A_ArrayExpr   *stmt = (A_ArrayExpr *)node;
	
		   if (walker(stmt->elements, context))
			   return true;
		}
			break;
		case T_ResTarget:
		{
		   ResTarget   *stmt = (ResTarget *)node;
	
		   if (walker(stmt->indirection, context))
			   return true;
		   if (walker(stmt->val, context))
			   return true;
		}
			break;
		case T_MultiAssignRef:
		{
		   MultiAssignRef   *stmt = (MultiAssignRef *)node;
	
		   if (walker(stmt->source, context))
			   return true;	   
		}
			break;
		case T_SortBy:
		{
		   SortBy   *stmt = (SortBy *)node;
	
		   if (walker(stmt->node, context))
			   return true;
		   if (walker(stmt->useOp, context))
			   return true;
		}
			break;
		case T_WindowDef:
		{
		   WindowDef   *stmt = (WindowDef *)node;
	
		   if (walker(stmt->partitionClause, context))
			   return true;
		   if (walker(stmt->orderClause, context))
			   return true;
		   if (walker(stmt->startOffset, context))
			   return true;
		   if (walker(stmt->endOffset, context))
			   return true;
		}
			break;
		case T_RangeSubselect:
		{
			 RangeSubselect *rs = (RangeSubselect *)node;

			 if (walker(rs->subquery, context))
				 return true;
			 if (walker(rs->alias, context))
				 return true;
		}
			break;
		case T_RangeFunction:
		{
			RangeFunction *rf = (RangeFunction *)node;

			if (walker(rf->functions, context))
				return true;
			if (walker(rf->alias, context))
				return true;
			if (walker(rf->coldeflist, context))
				return true;
		}
			break;
		case T_RangeTableSample:
		{
			RangeTableSample *rts = (RangeTableSample *)node;

			if (walker(rts->relation, context))
				return true;
			/* method name is deemed uninteresting */
			if (walker(rts->method, context))
				return true;
			if (walker(rts->args, context))
				return true;
			if (walker(rts->repeatable, context))
				return true;
		}
			break;
		case T_ColumnDef:
		{
			ColumnDef  *coldef = (ColumnDef *)node;

			if (walker(coldef->typeName, context))
				return true;
			if (walker(coldef->raw_default, context))
				return true;
			if (walker(coldef->cooked_default, context))
				return true;
			if (walker(coldef->collClause, context))
				return true;
			if (walker(coldef->constraints, context))
				return true;
			if (walker(coldef->fdwoptions, context))
				return true;							
		}
			break;
		case T_TableLikeClause:
		{
			TableLikeClause  *stmt = (TableLikeClause *)node;

			if (walker(stmt->relation, context))
				return true;						
		}
			break;
		case T_IndexElem:
		{
			IndexElem  *stmt = (IndexElem *)node;

			if (walker(stmt->expr, context))
				return true;
			if (walker(stmt->collation, context))
				return true;
			if (walker(stmt->opclass, context))
				return true;		
		}
			break;
		case T_DefElem:
		{
			DefElem  *stmt = (DefElem *)node;

			if (walker(stmt->arg, context))
				return true;						
		}
			break;
		case T_LockingClause:
		{
			LockingClause  *stmt = (LockingClause *)node;

			if (walker(stmt->lockedRels, context))
				return true;						
		}
			break;
		case T_XmlSerialize:
		{
			XmlSerialize  *stmt = (XmlSerialize *)node;

			if (walker(stmt->expr, context))
				return true;
			if (walker(stmt->typeName, context))
				return true;						
		}
			break;
		case T_RangeTblEntry:
		{
			RangeTblEntry  *stmt = (RangeTblEntry *)node;
	
			if (walker(stmt->tablesample, context))
				return true;
			if (walker(stmt->subquery, context))
				return true;
			if (walker(stmt->jointype, context))
				return true;
			if (walker(stmt->joinaliasvars, context))
				return true;
			if (walker(stmt->functions, context))
				return true;
			if (walker(stmt->values_lists, context))
				return true;
			if (walker(stmt->ctename, context))			
				return true;
			if (walker(stmt->coltypes, context))
				return true;
			if (walker(stmt->coltypmods, context))
				return true;
			if (walker(stmt->colcollations, context))
				return true;
			if (walker(stmt->alias, context))
				return true;
			if (walker(stmt->eref, context))
				return true;
			if (walker(stmt->securityQuals, context))
				return true;
		}
			break;
		case T_RangeTblFunction:
		{
			RangeTblFunction  *stmt = (RangeTblFunction *)node;
	
			if (walker(stmt->funcexpr, context))
				return true;
			if (walker(stmt->funccolnames, context))
				return true;
			if (walker(stmt->funccoltypes, context))
				return true;
			if (walker(stmt->funccoltypmods, context))
				return true;
			if (walker(stmt->funccolcollations, context))
				return true;
		}
			break;
		case T_TableSampleClause:
		{
			TableSampleClause  *stmt = (TableSampleClause *)node;
	
			if (walker(stmt->args, context))
				return true;
			if (walker(stmt->repeatable, context))
				return true;
		}
			break;
		case T_WithCheckOption:
		{
			WithCheckOption  *stmt = (WithCheckOption *)node;
	
			if (walker(stmt->qual, context))
				return true;
		}
			break;		
		case T_GroupingSet:
			return walker(((GroupingSet *)node)->content, context);
		case T_WindowClause:
		{
			WindowClause  *stmt = (WindowClause *)node;
	
			if (walker(stmt->partitionClause, context))
				return true;
			if (walker(stmt->orderClause, context))
				return true;
			if (walker(stmt->startOffset, context))
				return true;
			if (walker(stmt->endOffset, context))
				return true;		
		}
			break;
		case T_WithClause:
		{
			WithClause *stmt = (WithClause *)node;

			if (walker(stmt->ctes, context))
				return true;
		}
			break;	
		case T_InferClause:
		{
			InferClause *stmt = (InferClause *)node;

			if (walker(stmt->indexElems, context))
				return true;
			if (walker(stmt->whereClause, context))
				return true;
		}
			break;
		case T_OnConflictClause:
		{
			OnConflictClause *stmt = (OnConflictClause *)node;

			if (walker(stmt->infer, context))
				return true;
			if (walker(stmt->targetList, context))
				return true;
			if (walker(stmt->whereClause, context))
				return true;
		}
			break;
		case T_CommonTableExpr:
		{
			CommonTableExpr *stmt = (CommonTableExpr *)node;

			if (walker(stmt->aliascolnames, context))
				return true;
			if (walker(stmt->ctequery, context))
				return true;
			if (walker(stmt->ctecolnames, context))
				return true;
			if (walker(stmt->ctecoltypes, context))
				return true;
			if (walker(stmt->ctecoltypmods, context))
				return true;
			if (walker(stmt->ctecolcollations, context))
				return true;
		}
			break;		
		case T_SetOperationStmt:
		{
		   SetOperationStmt *stmt = (SetOperationStmt *)node;	
						
			if (walker(stmt->larg, context))
				return true;
			if (walker(stmt->rarg, context))
				return true;
			if (walker(stmt->colTypes, context))
				return true;
			if (walker(stmt->colTypmods, context))
				return true;
			if (walker(stmt->colCollations, context))
				return true;
			if (walker(stmt->groupClauses, context))
				return true;		
		}
			break;		
		case T_CopyStmt:
		{
		   CopyStmt *stmt = (CopyStmt *)node;
						
			if (walker(stmt->relation, context))
				return true;
			if (walker(stmt->query, context))
				return true;
			if (walker(stmt->attlist, context))
				return true;
			if (walker(stmt->options, context))
				return true;
		}
			break;				
		case T_VariableSetStmt:
		{
		   VariableSetStmt *stmt = (VariableSetStmt *)node;	
						
			if (walker(stmt->args, context))
				return true;	
		}
			break;				
		case T_Constraint:
		{
		   Constraint *stmt = (Constraint *)node;	
						
			if (walker(stmt->raw_expr, context))
				return true;
			if (walker(stmt->keys, context))
				return true;
			if (walker(stmt->exclusions, context))
				return true;
			if (walker(stmt->options, context))
				return true;	
			if (walker(stmt->where_clause, context))
				return true;
			if (walker(stmt->pktable, context))
				return true;
			if (walker(stmt->fk_attrs, context))
				return true;
			if (walker(stmt->pk_attrs, context))
				return true;
			if (walker(stmt->old_conpfeqop, context))
				return true;
		}
			break;	
		case T_AlterTableMoveAllStmt:
		{
		   AlterTableMoveAllStmt *stmt = (AlterTableMoveAllStmt *)node;	
						
			if (walker(stmt->roles, context))
				return true;		
		}
			break;	
		case T_CreateExtensionStmt:
		{
		   CreateExtensionStmt *stmt = (CreateExtensionStmt *)node;	
						
			if (walker(stmt->options, context))
				return true;		
		}
			break;	
		case T_AlterExtensionStmt:
		{
		   AlterExtensionStmt *stmt = (AlterExtensionStmt *)node;	
						
			if (walker(stmt->options, context))
				return true;		
		}
			break;	
		case T_CreateFdwStmt:
		{
		   CreateFdwStmt *stmt = (CreateFdwStmt *)node;	
						
			if (walker(stmt->func_options, context))
				return true;
			if (walker(stmt->options, context))
				return true;		
		}
			break;	
		case T_AlterFdwStmt:
		{
		   AlterFdwStmt *stmt = (AlterFdwStmt *)node;	
						
			if (walker(stmt->func_options, context))
				return true;
			if (walker(stmt->options, context))
				return true;		
		}
			break;				
		case T_CreateForeignServerStmt:
		{
		   CreateForeignServerStmt *stmt = (CreateForeignServerStmt *)node;	
						
			if (walker(stmt->options, context))
				return true;		
		}
			break;	
		case T_AlterForeignServerStmt:
		{
		   AlterForeignServerStmt *stmt = (AlterForeignServerStmt *)node;	
						
			if (walker(stmt->options, context))
				return true;		
		}
			break;	
		case T_CreateUserMappingStmt:
		{
		   CreateUserMappingStmt *stmt = (CreateUserMappingStmt *)node;						

			if (walker(stmt->user, context))
				return true;
			if (walker(stmt->options, context))
				return true;		
		}
			break;		
		case T_AlterUserMappingStmt:
		{
		   AlterUserMappingStmt *stmt = (AlterUserMappingStmt *)node;						
	
			if (walker(stmt->user, context))
				return true;
			if (walker(stmt->options, context))
				return true;		
		}
			break;		
		case T_DropUserMappingStmt:
		{
		   DropUserMappingStmt *stmt = (DropUserMappingStmt *)node;						
	
			if (walker(stmt->user, context))
				return true;	
		}
			break;		
		case T_ImportForeignSchemaStmt:
		{
		   ImportForeignSchemaStmt *stmt = (ImportForeignSchemaStmt *)node;						
	
			if (walker(stmt->table_list, context))
				return true;
			if (walker(stmt->options, context))
				return true;		
		}
			break;	
		case T_CreateEventTrigStmt:
		{
		   CreateEventTrigStmt *stmt = (CreateEventTrigStmt *)node;						
	
			if (walker(stmt->whenclause, context))
				return true;
			if (walker(stmt->funcname, context))
				return true;		
		}
			break;	
		case T_CreatePLangStmt:
		{
		   CreatePLangStmt *stmt = (CreatePLangStmt *)node;						
	
			if (walker(stmt->plhandler, context))
				return true;
			if (walker(stmt->plinline, context))
				return true;
			if (walker(stmt->plvalidator, context))
				return true;	
		}
			break;	
		case T_CreateRoleStmt:
		{
		   CreateRoleStmt *stmt = (CreateRoleStmt *)node;	
						
			if (walker(stmt->options, context))
				return true;		
		}
			break;	
		case T_AlterRoleStmt:
		{
		   AlterRoleStmt *stmt = (AlterRoleStmt *)node;	
						
			if (walker(stmt->role, context))
				return true;
			if (walker(stmt->options, context))
				return true;		
		}
			break;	
		case T_AlterRoleSetStmt:
		{
		   AlterRoleSetStmt *stmt = (AlterRoleSetStmt *)node;						
	
			if (walker(stmt->role, context))
				return true;
			if (walker(stmt->setstmt, context))
				return true;		
		}
			break;	
		case T_DropRoleStmt:
		{
		   DropRoleStmt *stmt = (DropRoleStmt *)node;						
	
			if (walker(stmt->roles, context))
				return true;	
		}
			break;			
		case T_CreateSeqStmt:
		{
		   CreateSeqStmt *stmt = (CreateSeqStmt *)node;	
						
			if (walker(stmt->sequence, context))
				return true;
			if (walker(stmt->options, context))
				return true;		
		}
			break;		
		case T_CreateOpClassItem:
		{
		   CreateOpClassItem *stmt = (CreateOpClassItem *)node;	
						
			if (walker(stmt->name, context))
				return true;
			if (walker(stmt->order_family, context))
				return true;
			if (walker(stmt->class_args, context))
				return true;
			if (walker(stmt->storedtype, context))
				return true;		
		}
			break;		
		case T_CreateOpFamilyStmt:
		{
		   CreateOpFamilyStmt *stmt = (CreateOpFamilyStmt *)node;	
						
			if (walker(stmt->opfamilyname, context))
				return true;	
		}
			break;			
		case T_TruncateStmt:
		{
		   TruncateStmt *stmt = (TruncateStmt *)node;	
						
			if (walker(stmt->relations, context))
				return true;
		}
			break;		
		case T_DeclareCursorStmt:
		{
		   DeclareCursorStmt *stmt = (DeclareCursorStmt *)node;	
						
			if (walker(stmt->query, context))
				return true;		
		}
			break;		
		case T_FunctionParameter:
		{
			FunctionParameter *stmt = (FunctionParameter*)node;
			if (walker(stmt->defexpr,context))
				return true;
		}
			break;
		case T_DoStmt:
		{
		   DoStmt *stmt = (DoStmt *)node;	
						
			if (walker(stmt->args, context))
				return true;
		}
			break;		
		case T_InlineCodeBlock:
		{
		   InlineCodeBlock *stmt = (InlineCodeBlock *)node;	
						
			if (walker(stmt->params, context))
				return true;		
		}
			break;		
		case T_TransactionStmt:
		{
		   TransactionStmt *stmt = (TransactionStmt *)node;	

			if (walker(stmt->options, context))
				return true;		
		}
			break;		
		case T_CompositeTypeStmt:
		{
		   CompositeTypeStmt *stmt = (CompositeTypeStmt *)node;	
	
			if (walker(stmt->typevar, context))
				return true;
			if (walker(stmt->coldeflist, context))
				return true;		
		}
			break;		
		case T_CreateEnumStmt:
		{
		   CreateEnumStmt *stmt = (CreateEnumStmt *)node;	
	
			if (walker(stmt->typeName, context))
				return true;
			if (walker(stmt->vals, context))
				return true;		
		}
			break;		
		case T_CreateRangeStmt:
		{
		   CreateRangeStmt *stmt = (CreateRangeStmt *)node;	
	
			if (walker(stmt->typeName, context))
				return true;
			if (walker(stmt->params, context))
				return true;		
		}
			break;		
		case T_AlterEnumStmt:
		{
		   AlterEnumStmt *stmt = (AlterEnumStmt *)node;	
	
			if (walker(stmt->typeName, context))
				return true;		
		}
			break;		
		case T_CreatedbStmt:
		{
		   CreatedbStmt *stmt = (CreatedbStmt *)node;	
	
			if (walker(stmt->options, context))
				return true;		
		}
			break;		
		case T_AlterDatabaseStmt:
		{
		   AlterDatabaseStmt *stmt = (AlterDatabaseStmt *)node;	
	
			if (walker(stmt->options, context))
				return true;		
		}
			break;		
		case T_AlterDatabaseSetStmt:
		{
		   AlterDatabaseSetStmt *stmt = (AlterDatabaseSetStmt *)node;	
	
			if (walker(stmt->setstmt, context))
				return true;		
		}
			break;		
		case T_AlterSystemStmt:
		{
		   AlterSystemStmt *stmt = (AlterSystemStmt *)node;	
	
			if (walker(stmt->setstmt, context))
				return true;		
		}
			break;		
		case T_ClusterStmt:
		{
		   ClusterStmt *stmt = (ClusterStmt *)node;	
	
			if (walker(stmt->relation, context))
				return true;		
		}
			break;		
		case T_VacuumStmt:
		{
		   VacuumStmt *stmt = (VacuumStmt *)node;	
	
			if (walker(stmt->options, context))
				return true;
			if (walker(stmt->rels, context))
				return true;		
		}
			break;		
		case T_ExplainStmt:
		{
		   ExplainStmt *stmt = (ExplainStmt *)node;	
	
			if (walker(stmt->query, context))
				return true;
			if (walker(stmt->options, context))
				return true;		
		}
			break;		
		case T_RefreshMatViewStmt:
		{
		   RefreshMatViewStmt *stmt = (RefreshMatViewStmt *)node;	
	
			if (walker(stmt->relation, context))
				return true;
		}
			break;		

		case T_LockStmt:
		{
		   LockStmt *stmt = (LockStmt *)node;	
	
			if (walker(stmt->relations, context))
				return true;
		}
			break;		

		case T_ConstraintsSetStmt:
		{
		   ConstraintsSetStmt *stmt = (ConstraintsSetStmt *)node;	
	
			if (walker(stmt->constraints, context))
				return true;		
		}
			break;	
		case T_ReindexStmt:
		{
		   ReindexStmt *stmt = (ReindexStmt *)node;	
	
			if (walker(stmt->relation, context))
				return true;	
		}
			break;				
		
		case T_CreateConversionStmt:
		{
		   CreateConversionStmt *stmt = (CreateConversionStmt *)node;	
	
			if (walker(stmt->conversion_name, context))
				return true;
			if (walker(stmt->func_name, context))
				return true;
		}
			break;					
		case T_DropOwnedStmt:
		{
		   DropOwnedStmt *stmt = (DropOwnedStmt *)node;	
	
			if (walker(stmt->roles, context))
				return true;	
		}
			break;					
		case T_ReassignOwnedStmt:
		{
		   ReassignOwnedStmt *stmt = (ReassignOwnedStmt *)node;	
	
			if (walker(stmt->roles, context))
				return true;
			if (walker(stmt->newrole, context))
				return true;	
		}
			break;		
		case T_AlterTSConfigurationStmt:
		{
		   AlterTSConfigurationStmt *stmt = (AlterTSConfigurationStmt *)node;	
	
			if (walker(stmt->cfgname, context))
				return true;
			if (walker(stmt->tokentype, context))
				return true;
			if (walker(stmt->dicts, context))
				return true;	
		}
			break;					
		case T_Alias:
		{
		   Alias *stmt = (Alias *)node;	
	
			if (walker(stmt->colnames, context))
				return true;
		}
			break;		
		case T_RangeVar:
		{
		   RangeVar *stmt = (RangeVar *)node;	
	
			if (walker(stmt->alias, context))
				return true;
		}
			break;		
		case T_Aggref:
		{
		   Aggref *stmt = (Aggref *)node;	
	
			if (walker(stmt->aggdirectargs, context))
				return true;
			if (walker(stmt->args, context))
				return true;
			if (walker(stmt->aggorder, context))
				return true;
			if (walker(stmt->aggdistinct, context))
				return true;
			if (walker(stmt->aggfilter, context))
				return true;
		}
			break;		
		case T_WindowFunc:
		{
		   WindowFunc *stmt = (WindowFunc *)node;

			if (walker(stmt->args, context))
				return true;
			if (walker(stmt->aggfilter, context))
				return true;
		}
			break;		
		case T_SubscriptingRef:
		{
		   SubscriptingRef *stmt = (SubscriptingRef *)node;

			if (walker(stmt->refupperindexpr, context))
				return true;
			if (walker(stmt->reflowerindexpr, context))
				return true;
			if (walker(stmt->refexpr, context))
				return true;
			if (walker(stmt->refassgnexpr, context))
				return true;
		}
			break;		
		case T_NamedArgExpr:
		{
			NamedArgExpr *stmt = (NamedArgExpr *)node;

			if (walker(stmt->arg, context))
				return true;		
		}
			break;		
		case T_FuncExpr:
		{
		   FuncExpr *stmt = (FuncExpr *)node;

			if (walker(stmt->args, context))
				return true;
		}
			break;		
		case T_OpExpr:
		{
			OpExpr *stmt = (OpExpr *)node;

			 if (walker(stmt->args, context))
				 return true;
		}
			break;		
		case T_ScalarArrayOpExpr:
		{
			ScalarArrayOpExpr *stmt = (ScalarArrayOpExpr *)node;

			 if (walker(stmt->args, context))
				 return true;
		}
			break;		
		case T_BoolExpr:
		{
			BoolExpr *stmt = (BoolExpr *)node;
		
			 if (walker(stmt->args, context))
				 return true;
		}
			break;		
		case T_SubLink:
		{
			SubLink    *sublink = (SubLink *)node;

			if (walker(sublink->testexpr, context))
				return true;
			if (walker(sublink->operName, context))
				return true;
			if (walker(sublink->subselect, context))
				return true;
		}
			break;
		case T_SubPlan:
		{
		   SubPlan *stmt = (SubPlan *)node;
	
			if (walker(stmt->testexpr, context))
				return true;
			if (walker(stmt->paramIds, context))
				return true;
			if (walker(stmt->setParam, context))
				return true;
			if (walker(stmt->parParam, context))
				return true;
			if (walker(stmt->args, context))
				return true;
		}
			break;		
		case T_AlternativeSubPlan:
		{
		   AlternativeSubPlan *stmt = (AlternativeSubPlan *)node;

			if (walker(stmt->subplans, context))
				return true;
		}
			break;		
		case T_FieldSelect:
		{
		   FieldSelect *stmt = (FieldSelect *)node;

			if (walker(stmt->arg, context))
				return true;
		}
			break;		
		case T_FieldStore:
		{
		   FieldStore *stmt = (FieldStore *)node;
	
			if (walker(stmt->arg, context))
				return true;
			if (walker(stmt->newvals, context))
				return true;
			if (walker(stmt->fieldnums, context))
				return true;
		}
			break;		
		case T_RelabelType:
		{
		   RelabelType *stmt = (RelabelType *)node;
	
			if (walker(stmt->arg, context))
				return true;
		}
			break;		
		case T_CoerceViaIO:
		{
		   CoerceViaIO *stmt = (CoerceViaIO *)node;
	
			if (walker(stmt->arg, context))
				return true;
		}
			break;		
		case T_ArrayCoerceExpr:
		{
		   ArrayCoerceExpr *stmt = (ArrayCoerceExpr *)node;
	
			if (walker(stmt->arg, context))
				return true;
		}
			break;		
		case T_ConvertRowtypeExpr:
		{
		   ConvertRowtypeExpr *stmt = (ConvertRowtypeExpr *)node;
	
			if (walker(stmt->arg, context))
				return true;
		}
			break;		
		case T_CollateExpr:
		{
		   CollateExpr *stmt = (CollateExpr *)node;
	
			if (walker(stmt->arg, context))
				return true;
		}
			break;		
		case T_CaseWhen:
		{
			CaseWhen   *when = (CaseWhen *)node;
		  
		   if (walker(when->expr, context))
			   return true;
		   if (walker(when->result, context))
			   return true;
		}
			break;		
		case T_CaseExpr:
		{
		   CaseExpr   *caseexpr = (CaseExpr *)node;

		   if (walker(caseexpr->arg, context))
			   return true;
		   if (walker(caseexpr->args, context))
			   return true;
		   if (walker(caseexpr->defresult, context))
			   return true;
		}
			break;
		case T_RowExpr:
		{
		   RowExpr   *stmt = (RowExpr *)node;
	
		   if (walker(stmt->args, context))
			   return true;
		   if (walker(stmt->colnames, context))
			   return true;
		}
			break;
		case T_RowCompareExpr:
		{
		   RowCompareExpr *stmt = (RowCompareExpr *)node;
	
			if (walker(stmt->opnos, context))
				return true;
			if (walker(stmt->opfamilies, context))
				return true;
			if (walker(stmt->inputcollids, context))
				return true;
			if (walker(stmt->largs, context))
				return true;
			if (walker(stmt->rargs, context))
				return true;
		}
			break;		
		case T_CoalesceExpr:
			return walker(((CoalesceExpr *)node)->args, context);
		case T_MinMaxExpr:
			return walker(((MinMaxExpr *)node)->args, context);
		case T_XmlExpr:
		{
			XmlExpr    *xexpr = (XmlExpr *)node;

			if (walker(xexpr->named_args, context))
				return true;
			if (walker(xexpr->arg_names, context))
				return true;
			if (walker(xexpr->args, context))
				return true;
		}
			break;
		case T_NullTest:
			return walker(((NullTest *)node)->arg, context);
		case T_BooleanTest:
			return walker(((BooleanTest *)node)->arg, context);
		case T_CoerceToDomain:
			return walker(((CoerceToDomain *)node)->arg, context);
		case T_InferenceElem:
			return walker(((InferenceElem *)node)->expr, context);
		case T_TargetEntry:
			return walker(((TargetEntry *)node)->expr, context);
		case T_FromExpr:
		{
  		    FromExpr *stmt = (FromExpr *)node;
			if (walker(stmt->fromlist, context))
				return true;
			if (walker(stmt->quals, context))
				return true;
		}
			break;				
		case T_JoinExpr:
		{
		   JoinExpr   *join = (JoinExpr *)node;

		   if (walker(join->larg, context))
			   return true;
		   if (walker(join->rarg, context))
			   return true;
		   if (walker(join->usingClause, context))
			   return true;
		   if (walker(join->quals, context))
			   return true;
		   if (walker(join->alias, context))
			   return true;
		}
			break;
		case T_OnConflictExpr:
		{
		   OnConflictExpr *stmt = (OnConflictExpr *)node;
	
			if (walker(stmt->arbiterElems, context))
				return true;
			if (walker(stmt->arbiterWhere, context))
				return true;
			if (walker(stmt->onConflictSet, context))
				return true;
			if (walker(stmt->onConflictWhere, context))
				return true;
			if (walker(stmt->exclRelTlist, context))
				return true;
		}
			break;				
		case T_IntoClause:
		{
			IntoClause *into = (IntoClause *)node;

			if (walker(into->rel, context))
				return true;
			if (walker(into->colNames, context))
				return true;
			if (walker(into->options, context))
				return true;
			if (walker(into->viewQuery, context))
				return true;
		}
			break;
		case T_List:
		foreach(temp, (List *)node)
		{
			if (walker((Node *)lfirst(temp), context))
				return true;
		}
			break;
		case T_RawStmt:
		{
			RawStmt *raw = (RawStmt *)node;

			if (walker(raw->stmt, context))
				return true;
		}
			break;
		case T_PLAssignStmt:
		{
			PLAssignStmt *assign = (PLAssignStmt *)node;

			if (walker(assign->indirection, context))
				return true;
			if (walker(assign->val, context))
				return true;
		}
			break;
		case T_CallStmt:
			{
				CallStmt *callstmt = (CallStmt *)node;

				if (walker(callstmt->funccall, context))
					return true;
			}
			break;

		default:		
			break;
	}
	return false;
}

void
set_ParseDynSql(bool value)
{
	IsParseDynSql = value;
}

bool
get_ParseDynSql(void)
{
	return IsParseDynSql;
}

void
check_variables_does_match(int variables)
{
	if (CurrentOraParamNode != NULL &&
		CurrentOraParamNode->param_count > 0 &&
		HasPgParam)
	{
		ereport(ERROR,
			(errcode(ERRCODE_SYNTAX_ERROR),
			errmsg("$n and :x bindvar model cannot be used at the same time")));
	}

	if (!HasPgParam)
	{
		if (NULL == CurrentOraParamNode)
		{
			if (variables > 0)
				ereport(ERROR,
					(errcode(ERRCODE_SYNTAX_ERROR),
					errmsg("bind variable does not exist")));
		}
		else if (CurrentOraParamNode->param_count > variables)
		{
			ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				errmsg("not all variables bound")));
		}
		else if (CurrentOraParamNode->param_count < variables)
		{
			ereport(ERROR,
				(errcode(ERRCODE_SYNTAX_ERROR),
				errmsg("bind variable does not exist")));
		}
	}

	return;
}

void
set_haspgparam(bool value)
{
	HasPgParam = value;
}

void
set_parseDynDoStmt(bool value)
{
	IsParseDynDoStmt = value;
}

void
set_doStmtCheckVar(bool values)
{
	DoStmtCheckVar = values;
}

void
set_bindByName(bool value)
{
	IsBindByName = value;
}

bool
get_doStmtCheckVar(void)
{
	return DoStmtCheckVar;
}

bool
get_bindByName(void)
{
	return IsBindByName;
}

int
calculate_oraparamname_position(Node *parsetree, char ***paramnames)
{
	OraParamState state;
	int	i;

	/* init parameters */
	state.numParams = 0;
	state.maxparams = 4;
	state.paramNames = palloc0(sizeof(char *) * state.maxparams);

	calculate_oraparamname_walker(parsetree, &state);

	/*
	 * Check if the parameter is correct,
	 * make sure all the parameters should have a name.
	 */
	for (i = 1; i <= state.numParams; i++)
	{
		if (state.paramNames[i] == NULL)
			elog(ERROR, "placeholdvar at the position %d has no name", i);
	}

	*paramnames = state.paramNames;
	return state.numParams;
}

static bool
calculate_oraparamname_walker(Node *node, void *state)
{
	if (node == NULL)
		return false;

	if (IsA(node, OraParamRef))
	{
		OraParamRef *pref = (OraParamRef*)node;
		OraParamState *orastate = (OraParamState *) state;

		if (pref->number >= orastate->maxparams)
		{
			int i;

			orastate->maxparams = orastate->maxparams * 2;
			orastate->paramNames = repalloc(orastate->paramNames, sizeof(char *) * orastate->maxparams);

			for (i = orastate->maxparams / 2; i < orastate->maxparams; i++)
			{
				orastate->paramNames[i] = NULL;
			}

			orastate->paramNames[pref->number] = pref->name;
			orastate->numParams++;
		}
		else if (orastate->paramNames[pref->number] == NULL)
		{
			orastate->paramNames[pref->number] = pref->name;
			orastate->numParams++;
		}
		else if (strcmp(orastate->paramNames[pref->number], pref->name) != 0)
		{
			elog(ERROR, "same position %d, different name", pref->number);
		}

		return false;
	}
	else
	{
		return raw_calculate_oraparamnumbers_walker(node, 
					calculate_oraparamname_walker,
					state);
	}

	return false;
}

int
calculate_oraparamname(char ***paramnames)
{
	OraParamState state;
	int	i;

	state.numParams = CurrentOraParamNode->param_count;
	state.maxparams = CurrentOraParamNode->param_count;
	state.paramNames = palloc0(sizeof(char *) * (state.maxparams + 1));

	for (i = 0; i < CurrentOraParamNode->param_count; ++i)
	{
		state.paramNames[i + 1] = pstrdup(CurrentOraParamNode->params[i].name);
	}

	*paramnames = state.paramNames;

	return state.numParams;
}

