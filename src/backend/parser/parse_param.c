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

static OraParamNumbers *TopOraParamNode = NULL;
static OraParamNumbers *CurrentOraParamNode = NULL;

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
static bool			IsDynCallStmt = false;

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
							tree_walker_callback walker,
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
		IsDynCallStmt = false;
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
				/* ORA-06578: output parameter cannot be a duplicate bind */
			 	if (IsDynCallStmt)
					ereport(ERROR,
							(errcode(ERRCODE_AMBIGUOUS_PARAMETER),
							 errmsg("output parameter cannot be a duplicate bind")));
				else
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

		if (nodeTag(parsetree) == T_RawStmt &&
			nodeTag(((RawStmt *)parsetree)->stmt) == T_CallStmt &&
			CurrentOraParamNode &&
			CurrentOraParamNode->param_count == 0)
			setdynamic_callparser(true);
		else
			/* In any case, it should't affect other statements in the list */
			setdynamic_callparser(false);

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
					tree_walker_callback walker,
					void *context)
{
	ListCell   *temp = NULL;

#define WALK(n) walker((Node *) (n), context)

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
			if (WALK(stmt->domainname))
				return true;
			if (WALK(stmt->typeName))
				return true;
			if (WALK(stmt->constraints))
				return true;
		}
			break;
		case T_AlterDomainStmt:
		{
			AlterDomainStmt    *stmt = (AlterDomainStmt *)node;
			if (WALK(stmt->typeName))
				return true;
			if (WALK(stmt->def))
				return true;
		}	
			break;
		case T_CreatePolicyStmt:
		{
			CreatePolicyStmt    *stmt = (CreatePolicyStmt *)node;
			if (WALK(stmt->table))
				return true;
			if (WALK(stmt->roles))
				return true;
			if (WALK(stmt->qual))
				return true;
			if (WALK(stmt->with_check))
				return true;
		}
			break;
		case T_AlterPolicyStmt:
		{
			AlterPolicyStmt    *stmt = (AlterPolicyStmt *)node;
			if (WALK(stmt->table))
				return true;
			if (WALK(stmt->roles))
				return true;
			if (WALK(stmt->qual))
				return true;
			if (WALK(stmt->with_check))
				return true;
		}
			break;
		case T_CreateTrigStmt:
		{
			CreateTrigStmt    *stmt = (CreateTrigStmt *)node;
			if (WALK(stmt->relation))
				return true;
			if (WALK(stmt->whenClause))
				return true;
			if (WALK(stmt->funcname))
				return true;
			if (WALK(stmt->args))
				return true;
			if (WALK(stmt->columns))
				return true;
			if (WALK(stmt->constrrel))
				return true;
		
		}
			break;
		case T_IndexStmt:
		{
			IndexStmt    *stmt = (IndexStmt *)node;
			if (WALK(stmt->relation))
				return true;
			if (WALK(stmt->indexParams))
				return true;
			if (WALK(stmt->options))
				return true;
			if (WALK(stmt->whereClause))
				return true;
			if (WALK(stmt->excludeOpNames))
				return true;		
		}
			break;
		case T_RuleStmt:
		{
			RuleStmt    *stmt = (RuleStmt *)node;
			if (WALK(stmt->relation))
				return true;
			if (WALK(stmt->whereClause))
				return true;
			if (WALK(stmt->actions))
				return true;		
		}
			break;
		case T_DeleteStmt:
		{
			DeleteStmt    *stmt = (DeleteStmt *)node;
			if (WALK(stmt->relation))
				return true;
			if (WALK(stmt->usingClause))
				return true;
			if (WALK(stmt->whereClause))
				return true;
			if (WALK(stmt->returningClause))
				return true;		
			if (WALK(stmt->withClause))
				return true;		
		}
			break;
		case T_UpdateStmt:
		{
			UpdateStmt    *stmt = (UpdateStmt *)node;
			if (WALK(stmt->relation))
				return true;
			if (WALK(stmt->targetList))
				return true;
			if (WALK(stmt->fromClause))
				return true;
			if (WALK(stmt->whereClause))
				return true;		
			if (WALK(stmt->returningClause))
				return true;		
			if (WALK(stmt->withClause))
				return true;		
		}
			break;
		case T_AlterTableStmt:
		{
			AlterTableStmt    *stmt = (AlterTableStmt *)node;
			if (WALK(stmt->relation))
				return true;
			if (WALK(stmt->cmds))
				return true;			
		}
			break;
		case T_AlterTableCmd:
		{
			AlterTableCmd    *stmt = (AlterTableCmd *)node;
			if (WALK(stmt->newowner))
				return true;
			if (WALK(stmt->def))
				return true;
			
		}
			break;
		case T_CreateFunctionStmt:
		{
			CreateFunctionStmt *stmt = (CreateFunctionStmt*)node;
			if (WALK(stmt->funcname))
				return true;
			if (WALK(stmt->parameters))
				return true;
			if (WALK(stmt->returnType))
				return true;
			if (WALK(stmt->options))
				return true;
		}
			break;
		case T_SelectStmt:
		{
			 SelectStmt *stmt = (SelectStmt *)node;

			 if (WALK(stmt->distinctClause))
				 return true;
			 if (WALK(stmt->intoClause))
				 return true;
			 if (WALK(stmt->targetList))
				 return true;
			 if (WALK(stmt->fromClause))
				 return true;
			 if (WALK(stmt->whereClause))
				 return true;		 
			 if (WALK(stmt->groupClause))
				 return true;		 
			 if (WALK(stmt->havingClause))
				 return true;
			 if (WALK(stmt->windowClause))
				 return true;
			 if (WALK(stmt->valuesLists))
				 return true;
			 if (WALK(stmt->sortClause))
				 return true;
			 if (WALK(stmt->limitOffset))
				 return true;
			 if (WALK(stmt->lockingClause))
				 return true;
			 if (WALK(stmt->withClause))
				 return true;
			 if (WALK(stmt->larg))
				 return true;
			 if (WALK(stmt->rarg))
				 return true;
		}
			break;
		case T_InsertStmt:
		{
			 InsertStmt *stmt = (InsertStmt *)node;

			 if (WALK(stmt->relation))
				 return true;
			 if (WALK(stmt->cols))
				 return true;
			 if (WALK(stmt->selectStmt))
				 return true;
			 if (WALK(stmt->onConflictClause))
				 return true;
			 if (WALK(stmt->returningClause))
				 return true;
			 if (WALK(stmt->withClause))
				 return true;
		}
			break;
		case T_CreateSchemaStmt:
		{
			 CreateSchemaStmt *stmt = (CreateSchemaStmt *)node;
	
			 if (WALK(stmt->authrole))
		  		 return true;
			 if (WALK(stmt->schemaElts))
				 return true;
		}
			break;
		case T_AlterObjectSchemaStmt:
		{
			 AlterObjectSchemaStmt *stmt = (AlterObjectSchemaStmt *)node;
	
			if (WALK(stmt->relation))
				return true;
			 if (WALK(stmt->object))
				 return true;
		}
			break;
		case T_ExecuteStmt:
			return WALK(((ExecuteStmt *)node)->params);
		case T_CreateTableAsStmt:
		{
			 CreateTableAsStmt *stmt = (CreateTableAsStmt *)node;
	
			 if (WALK(stmt->query))
				 return true;
			 if (WALK(stmt->into))
				 return true;
		}
			break;
		case T_CreateStmt:
		{
			 CreateStmt *stmt = (CreateStmt *)node;

			 if (WALK(stmt->relation))
				 return true;
			 if (WALK(stmt->tableElts))
				 return true;
			 if (WALK(stmt->inhRelations))
				 return true;
			 if (WALK(stmt->ofTypename))
				 return true;
			 if (WALK(stmt->constraints))
				 return true;
			 if (WALK(stmt->options))
				 return true;
		}
			break;			
		case T_CreateForeignTableStmt:
		{
			 CreateForeignTableStmt *stmt = (CreateForeignTableStmt *)node;

			 if (WALK(stmt->base.relation))
				 return true;
			 if (WALK(stmt->base.tableElts))
				 return true;
			 if (WALK(stmt->base.inhRelations))
				 return true;
			 if (WALK(stmt->base.ofTypename))
				 return true;
			 if (WALK(stmt->base.constraints))
				 return true;
			 if (WALK(stmt->base.options))
				 return true;
			 if (WALK(stmt->options))
				 return true;
		}
			break;			
		case T_AlterExtensionContentsStmt:
		{
			 AlterExtensionContentsStmt *stmt = (AlterExtensionContentsStmt *)node;

			 if (WALK(stmt->object))
				 return true;
		}
			break;			
		case T_CreateOpClassStmt:
		{
			 CreateOpClassStmt *stmt = (CreateOpClassStmt *)node;

			 if (WALK(stmt->opclassname))
				 return true;
			 if (WALK(stmt->datatype))
				 return true;
			 if (WALK(stmt->opfamilyname))
				 return true;
			 if (WALK(stmt->items))
				 return true;
		}
			break;			
		case T_AlterOpFamilyStmt:
		{
			 AlterOpFamilyStmt *stmt = (AlterOpFamilyStmt *)node;

			 if (WALK(stmt->opfamilyname))
				 return true;
			 if (WALK(stmt->items))
				 return true;
		}
			break;			
		case T_DropStmt:
		{
			 DropStmt *stmt = (DropStmt *)node;

			 if (WALK(stmt->objects))
				 return true;
		}
			break;			
		case T_CommentStmt:
		{
			 CommentStmt *stmt = (CommentStmt *)node;

			 if (WALK(stmt->object))
				 return true;
		}
			break;			
		case T_SecLabelStmt:
		{
			 SecLabelStmt *stmt = (SecLabelStmt *)node;

			 if (WALK(stmt->object))
				 return true;
		}
			break;			
		case T_CreateCastStmt:
		{
			 CreateCastStmt *stmt = (CreateCastStmt *)node;

			 if (WALK(stmt->sourcetype))
				 return true;
			 if (WALK(stmt->targettype))
				 return true;
			 if (WALK(stmt->func))
				 return true;
		}
			break;			
		case T_CreateTransformStmt:
		{
			 CreateTransformStmt *stmt = (CreateTransformStmt *)node;

			 if (WALK(stmt->type_name))
				 return true;
			 if (WALK(stmt->fromsql))
				 return true;
			 if (WALK(stmt->tosql))
				 return true;
		}
			break;			
		case T_DefineStmt:
		{
			 DefineStmt *stmt = (DefineStmt *)node;

			 if (WALK(stmt->defnames))
				 return true;
			 if (WALK(stmt->args))
				 return true;
			 if (WALK(stmt->definition))
				 return true;
		}
			break;			
		case T_AlterOwnerStmt:
		{
			 AlterOwnerStmt *stmt = (AlterOwnerStmt *)node;

			if (WALK(stmt->relation))
				 return true;
			 if (WALK(stmt->object))
				 return true;
			 if (WALK(stmt->newowner))
				 return true;
		}
			break;			
		case T_PrepareStmt:
		{
			 PrepareStmt *stmt = (PrepareStmt *)node;

			 if (WALK(stmt->argtypes))
				 return true;
			 if (WALK(stmt->query))
				 return true;
		}
			break;			
		case T_CreateTableSpaceStmt:
		{
			 CreateTableSpaceStmt *stmt = (CreateTableSpaceStmt *)node;

			 if (WALK(stmt->owner))
				 return true;
			 if (WALK(stmt->options))
				 return true;
		}
			break;					
		case T_ViewStmt:
		{
			 ViewStmt *stmt = (ViewStmt *)node;

			if (WALK(stmt->view))
				 return true;
			 if (WALK(stmt->aliases))
				 return true;
			 if (WALK(stmt->query))
				 return true;
			 if (WALK(stmt->options))
				 return true;
		}
			break;			
		case T_RenameStmt:
		{
			 RenameStmt *stmt = (RenameStmt *)node;

			if (WALK(stmt->relation))
				 return true;
			 if (WALK(stmt->object))
				 return true;
		}
			break;			
		case T_AlterFunctionStmt:
		{
			 AlterFunctionStmt *stmt = (AlterFunctionStmt *)node;

			 if (WALK(stmt->func))
				 return true;
			 if (WALK(stmt->actions))
				 return true;
		}
			break;			
		case T_AlterTableSpaceOptionsStmt:
		{
			 AlterTableSpaceOptionsStmt *stmt = (AlterTableSpaceOptionsStmt *)node;

			 if (WALK(stmt->options))
				 return true;
		}
			break;			
		case T_AlterTSDictionaryStmt:
		{
			 AlterTSDictionaryStmt *stmt = (AlterTSDictionaryStmt *)node;

			 if (WALK(stmt->dictname))
				 return true;
			 if (WALK(stmt->options))
				 return true;
		}
			break;			
		case T_GrantStmt:
		{
			 GrantStmt *stmt = (GrantStmt *)node;

			 if (WALK(stmt->objects))
				 return true;
			 if (WALK(stmt->privileges))
				 return true;
			 if (WALK(stmt->grantees))
				 return true;
		}
			break;		
		case T_GrantRoleStmt:
		{
			 GrantRoleStmt *stmt = (GrantRoleStmt *)node;

			 if (WALK(stmt->granted_roles))
				 return true;
			 if (WALK(stmt->grantee_roles))
				 return true;
			 if (WALK(stmt->grantor))
				 return true;
		}
			break;	
		case T_AlterDefaultPrivilegesStmt:
		{
			 AlterDefaultPrivilegesStmt *stmt = (AlterDefaultPrivilegesStmt *)node;

			 if (WALK(stmt->options))
				 return true;
			 if (WALK(stmt->action))
				 return true;		
		}
			break;			
		case T_AccessPriv:
		{
			 AccessPriv *stmt = (AccessPriv *)node;
	
			 if (WALK(stmt->cols))
				 return true;
		}
			break;		
		case T_GroupingFunc:
		{
			 GroupingFunc *stmt = (GroupingFunc *)node;
	
			 if (WALK(stmt->args))
				 return true;
			 if (WALK(stmt->refs))
				 return true;
			 if (WALK(stmt->cols))
				 return true;
		}
			break;	
		case T_Query:
		{
			Query *stmt = (Query*)node;

			if (WALK(stmt->utilityStmt))
				return true;
			 if (WALK(stmt->cteList))
				 return true;
			 if (WALK(stmt->rtable))
				 return true;
			 if (WALK(stmt->jointree))
				 return true;		
			if (WALK(stmt->targetList))
				return true;
			if (WALK(stmt->onConflict))
				return true;
			if (WALK(stmt->returningList))
				return true;
			if (WALK(stmt->groupClause))
				return true;
			if (WALK(stmt->groupingSets))
				return true;
			if (WALK(stmt->havingQual))
				return true;
			if (WALK(stmt->windowClause))
				return true;
			if (WALK(stmt->distinctClause))
				return true;
			if (WALK(stmt->sortClause))
				return true;
			if (WALK(stmt->limitOffset))
				return true;
			if (WALK(stmt->limitCount))
				return true;		
			if (WALK(stmt->rowMarks))
				return true;
			if (WALK(stmt->setOperations))
				return true;
			if (WALK(stmt->constraintDeps))
				return true;
			if (WALK(stmt->withCheckOptions))
				return true;
		}
			break;
		case T_TypeName:
		{
			TypeName *stmt = (TypeName*)node;

			if (WALK(stmt->names))
				return true;
			 if (WALK(stmt->typmods))
				 return true;
			 if (WALK(stmt->arrayBounds))
				 return true;
		}
			break;
		case T_ColumnRef:
		{
			ColumnRef *stmt = (ColumnRef*)node;

			if (WALK(stmt->fields))
				return true;		 
		}
			break;
		case T_A_Expr:
		{
			A_Expr *stmt = (A_Expr*)node;

			if (WALK(stmt->name))
				return true;
			if (WALK(stmt->lexpr))
				return true;
			if (WALK(stmt->rexpr))
				return true;		 
		}
			break;
		case T_TypeCast:
		{
		   TypeCast   *stmt = (TypeCast *)node;

		   if (WALK(stmt->arg))
			   return true;
		   if (WALK(stmt->typeName))
			   return true;
		}
			break;
		case T_CollateClause:
		{
		   CollateClause   *stmt = (CollateClause *)node;
	
		   if (WALK(stmt->arg))
			   return true;
		   if (WALK(stmt->collname))
			   return true;
		}
			break;
		case T_FuncCall:
		{
			FuncCall   *stmt = (FuncCall *)node;
	
			if (WALK(stmt->funcname))
				return true;
			if (WALK(stmt->args))
				return true;
			if (WALK(stmt->agg_order))
				return true;
			if (WALK(stmt->agg_filter))
				return true;
			if (WALK(stmt->over))
				return true;
		}
			break;
		case T_A_Indices:
		{
		   A_Indices   *stmt = (A_Indices *)node;
	
		   if (WALK(stmt->lidx))
			   return true;
		   if (WALK(stmt->uidx))
			   return true;
		}
			break;
		case T_A_Indirection:
		{
		   A_Indirection   *stmt = (A_Indirection *)node;
	
		   if (WALK(stmt->arg))
			   return true;
		   if (WALK(stmt->indirection))
			   return true;
		}
			break;
		case T_A_ArrayExpr:
		{
		   A_ArrayExpr   *stmt = (A_ArrayExpr *)node;
	
		   if (WALK(stmt->elements))
			   return true;
		}
			break;
		case T_ResTarget:
		{
		   ResTarget   *stmt = (ResTarget *)node;
	
		   if (WALK(stmt->indirection))
			   return true;
		   if (WALK(stmt->val))
			   return true;
		}
			break;
		case T_MultiAssignRef:
		{
		   MultiAssignRef   *stmt = (MultiAssignRef *)node;
	
		   if (WALK(stmt->source))
			   return true;	   
		}
			break;
		case T_SortBy:
		{
		   SortBy   *stmt = (SortBy *)node;
	
		   if (WALK(stmt->node))
			   return true;
		   if (WALK(stmt->useOp))
			   return true;
		}
			break;
		case T_WindowDef:
		{
		   WindowDef   *stmt = (WindowDef *)node;
	
		   if (WALK(stmt->partitionClause))
			   return true;
		   if (WALK(stmt->orderClause))
			   return true;
		   if (WALK(stmt->startOffset))
			   return true;
		   if (WALK(stmt->endOffset))
			   return true;
		}
			break;
		case T_RangeSubselect:
		{
			 RangeSubselect *rs = (RangeSubselect *)node;

			 if (WALK(rs->subquery))
				 return true;
			 if (WALK(rs->alias))
				 return true;
		}
			break;
		case T_RangeFunction:
		{
			RangeFunction *rf = (RangeFunction *)node;

			if (WALK(rf->functions))
				return true;
			if (WALK(rf->alias))
				return true;
			if (WALK(rf->coldeflist))
				return true;
		}
			break;
		case T_RangeTableSample:
		{
			RangeTableSample *rts = (RangeTableSample *)node;

			if (WALK(rts->relation))
				return true;
			/* method name is deemed uninteresting */
			if (WALK(rts->method))
				return true;
			if (WALK(rts->args))
				return true;
			if (WALK(rts->repeatable))
				return true;
		}
			break;
		case T_ColumnDef:
		{
			ColumnDef  *coldef = (ColumnDef *)node;

			if (WALK(coldef->typeName))
				return true;
			if (WALK(coldef->raw_default))
				return true;
			if (WALK(coldef->cooked_default))
				return true;
			if (WALK(coldef->collClause))
				return true;
			if (WALK(coldef->constraints))
				return true;
			if (WALK(coldef->fdwoptions))
				return true;							
		}
			break;
		case T_TableLikeClause:
		{
			TableLikeClause  *stmt = (TableLikeClause *)node;

			if (WALK(stmt->relation))
				return true;						
		}
			break;
		case T_IndexElem:
		{
			IndexElem  *stmt = (IndexElem *)node;

			if (WALK(stmt->expr))
				return true;
			if (WALK(stmt->collation))
				return true;
			if (WALK(stmt->opclass))
				return true;		
		}
			break;
		case T_DefElem:
		{
			DefElem  *stmt = (DefElem *)node;

			if (WALK(stmt->arg))
				return true;						
		}
			break;
		case T_LockingClause:
		{
			LockingClause  *stmt = (LockingClause *)node;

			if (WALK(stmt->lockedRels))
				return true;						
		}
			break;
		case T_XmlSerialize:
		{
			XmlSerialize  *stmt = (XmlSerialize *)node;

			if (WALK(stmt->expr))
				return true;
			if (WALK(stmt->typeName))
				return true;						
		}
			break;
		case T_RangeTblEntry:
		{
			RangeTblEntry  *stmt = (RangeTblEntry *)node;
	
			if (WALK(stmt->tablesample))
				return true;
			if (WALK(stmt->subquery))
				return true;
			if (WALK(stmt->joinaliasvars))
				return true;
			if (WALK(stmt->functions))
				return true;
			if (WALK(stmt->values_lists))
				return true;
			if (WALK(stmt->coltypes))
				return true;
			if (WALK(stmt->coltypmods))
				return true;
			if (WALK(stmt->colcollations))
				return true;
			if (WALK(stmt->alias))
				return true;
			if (WALK(stmt->eref))
				return true;
			if (WALK(stmt->securityQuals))
				return true;
		}
			break;
		case T_RangeTblFunction:
		{
			RangeTblFunction  *stmt = (RangeTblFunction *)node;
	
			if (WALK(stmt->funcexpr))
				return true;
			if (WALK(stmt->funccolnames))
				return true;
			if (WALK(stmt->funccoltypes))
				return true;
			if (WALK(stmt->funccoltypmods))
				return true;
			if (WALK(stmt->funccolcollations))
				return true;
		}
			break;
		case T_TableSampleClause:
		{
			TableSampleClause  *stmt = (TableSampleClause *)node;
	
			if (WALK(stmt->args))
				return true;
			if (WALK(stmt->repeatable))
				return true;
		}
			break;
		case T_WithCheckOption:
		{
			WithCheckOption  *stmt = (WithCheckOption *)node;
	
			if (WALK(stmt->qual))
				return true;
		}
			break;		
		case T_GroupingSet:
			return WALK(((GroupingSet *)node)->content);
		case T_WindowClause:
		{
			WindowClause  *stmt = (WindowClause *)node;
	
			if (WALK(stmt->partitionClause))
				return true;
			if (WALK(stmt->orderClause))
				return true;
			if (WALK(stmt->startOffset))
				return true;
			if (WALK(stmt->endOffset))
				return true;		
		}
			break;
		case T_WithClause:
		{
			WithClause *stmt = (WithClause *)node;

			if (WALK(stmt->ctes))
				return true;
		}
			break;	
		case T_InferClause:
		{
			InferClause *stmt = (InferClause *)node;

			if (WALK(stmt->indexElems))
				return true;
			if (WALK(stmt->whereClause))
				return true;
		}
			break;
		case T_OnConflictClause:
		{
			OnConflictClause *stmt = (OnConflictClause *)node;

			if (WALK(stmt->infer))
				return true;
			if (WALK(stmt->targetList))
				return true;
			if (WALK(stmt->whereClause))
				return true;
		}
			break;
		case T_CommonTableExpr:
		{
			CommonTableExpr *stmt = (CommonTableExpr *)node;

			if (WALK(stmt->aliascolnames))
				return true;
			if (WALK(stmt->ctequery))
				return true;
			if (WALK(stmt->ctecolnames))
				return true;
			if (WALK(stmt->ctecoltypes))
				return true;
			if (WALK(stmt->ctecoltypmods))
				return true;
			if (WALK(stmt->ctecolcollations))
				return true;
		}
			break;		
		case T_SetOperationStmt:
		{
		   SetOperationStmt *stmt = (SetOperationStmt *)node;	
						
			if (WALK(stmt->larg))
				return true;
			if (WALK(stmt->rarg))
				return true;
			if (WALK(stmt->colTypes))
				return true;
			if (WALK(stmt->colTypmods))
				return true;
			if (WALK(stmt->colCollations))
				return true;
			if (WALK(stmt->groupClauses))
				return true;		
		}
			break;		
		case T_CopyStmt:
		{
		   CopyStmt *stmt = (CopyStmt *)node;
						
			if (WALK(stmt->relation))
				return true;
			if (WALK(stmt->query))
				return true;
			if (WALK(stmt->attlist))
				return true;
			if (WALK(stmt->options))
				return true;
		}
			break;				
		case T_VariableSetStmt:
		{
		   VariableSetStmt *stmt = (VariableSetStmt *)node;	
						
			if (WALK(stmt->args))
				return true;	
		}
			break;				
		case T_Constraint:
		{
		   Constraint *stmt = (Constraint *)node;	
						
			if (WALK(stmt->raw_expr))
				return true;
			if (WALK(stmt->keys))
				return true;
			if (WALK(stmt->exclusions))
				return true;
			if (WALK(stmt->options))
				return true;	
			if (WALK(stmt->where_clause))
				return true;
			if (WALK(stmt->pktable))
				return true;
			if (WALK(stmt->fk_attrs))
				return true;
			if (WALK(stmt->pk_attrs))
				return true;
			if (WALK(stmt->old_conpfeqop))
				return true;
		}
			break;	
		case T_AlterTableMoveAllStmt:
		{
		   AlterTableMoveAllStmt *stmt = (AlterTableMoveAllStmt *)node;	
						
			if (WALK(stmt->roles))
				return true;		
		}
			break;	
		case T_CreateExtensionStmt:
		{
		   CreateExtensionStmt *stmt = (CreateExtensionStmt *)node;	
						
			if (WALK(stmt->options))
				return true;		
		}
			break;	
		case T_AlterExtensionStmt:
		{
		   AlterExtensionStmt *stmt = (AlterExtensionStmt *)node;	
						
			if (WALK(stmt->options))
				return true;		
		}
			break;	
		case T_CreateFdwStmt:
		{
		   CreateFdwStmt *stmt = (CreateFdwStmt *)node;	
						
			if (WALK(stmt->func_options))
				return true;
			if (WALK(stmt->options))
				return true;		
		}
			break;	
		case T_AlterFdwStmt:
		{
		   AlterFdwStmt *stmt = (AlterFdwStmt *)node;	
						
			if (WALK(stmt->func_options))
				return true;
			if (WALK(stmt->options))
				return true;		
		}
			break;				
		case T_CreateForeignServerStmt:
		{
		   CreateForeignServerStmt *stmt = (CreateForeignServerStmt *)node;	
						
			if (WALK(stmt->options))
				return true;		
		}
			break;	
		case T_AlterForeignServerStmt:
		{
		   AlterForeignServerStmt *stmt = (AlterForeignServerStmt *)node;	
						
			if (WALK(stmt->options))
				return true;		
		}
			break;	
		case T_CreateUserMappingStmt:
		{
		   CreateUserMappingStmt *stmt = (CreateUserMappingStmt *)node;						

			if (WALK(stmt->user))
				return true;
			if (WALK(stmt->options))
				return true;		
		}
			break;		
		case T_AlterUserMappingStmt:
		{
		   AlterUserMappingStmt *stmt = (AlterUserMappingStmt *)node;						
	
			if (WALK(stmt->user))
				return true;
			if (WALK(stmt->options))
				return true;		
		}
			break;		
		case T_DropUserMappingStmt:
		{
		   DropUserMappingStmt *stmt = (DropUserMappingStmt *)node;						
	
			if (WALK(stmt->user))
				return true;	
		}
			break;		
		case T_ImportForeignSchemaStmt:
		{
		   ImportForeignSchemaStmt *stmt = (ImportForeignSchemaStmt *)node;						
	
			if (WALK(stmt->table_list))
				return true;
			if (WALK(stmt->options))
				return true;		
		}
			break;	
		case T_CreateEventTrigStmt:
		{
		   CreateEventTrigStmt *stmt = (CreateEventTrigStmt *)node;						
	
			if (WALK(stmt->whenclause))
				return true;
			if (WALK(stmt->funcname))
				return true;		
		}
			break;	
		case T_CreatePLangStmt:
		{
		   CreatePLangStmt *stmt = (CreatePLangStmt *)node;						
	
			if (WALK(stmt->plhandler))
				return true;
			if (WALK(stmt->plinline))
				return true;
			if (WALK(stmt->plvalidator))
				return true;	
		}
			break;	
		case T_CreateRoleStmt:
		{
		   CreateRoleStmt *stmt = (CreateRoleStmt *)node;	
						
			if (WALK(stmt->options))
				return true;		
		}
			break;	
		case T_AlterRoleStmt:
		{
		   AlterRoleStmt *stmt = (AlterRoleStmt *)node;	
						
			if (WALK(stmt->role))
				return true;
			if (WALK(stmt->options))
				return true;		
		}
			break;	
		case T_AlterRoleSetStmt:
		{
		   AlterRoleSetStmt *stmt = (AlterRoleSetStmt *)node;						
	
			if (WALK(stmt->role))
				return true;
			if (WALK(stmt->setstmt))
				return true;		
		}
			break;	
		case T_DropRoleStmt:
		{
		   DropRoleStmt *stmt = (DropRoleStmt *)node;						
	
			if (WALK(stmt->roles))
				return true;	
		}
			break;			
		case T_CreateSeqStmt:
		{
		   CreateSeqStmt *stmt = (CreateSeqStmt *)node;	
						
			if (WALK(stmt->sequence))
				return true;
			if (WALK(stmt->options))
				return true;		
		}
			break;		
		case T_CreateOpClassItem:
		{
		   CreateOpClassItem *stmt = (CreateOpClassItem *)node;	
						
			if (WALK(stmt->name))
				return true;
			if (WALK(stmt->order_family))
				return true;
			if (WALK(stmt->class_args))
				return true;
			if (WALK(stmt->storedtype))
				return true;		
		}
			break;		
		case T_CreateOpFamilyStmt:
		{
		   CreateOpFamilyStmt *stmt = (CreateOpFamilyStmt *)node;	
						
			if (WALK(stmt->opfamilyname))
				return true;	
		}
			break;			
		case T_TruncateStmt:
		{
		   TruncateStmt *stmt = (TruncateStmt *)node;	
						
			if (WALK(stmt->relations))
				return true;
		}
			break;		
		case T_DeclareCursorStmt:
		{
		   DeclareCursorStmt *stmt = (DeclareCursorStmt *)node;	
						
			if (WALK(stmt->query))
				return true;		
		}
			break;		
		case T_FunctionParameter:
		{
			FunctionParameter *stmt = (FunctionParameter*)node;
			if (WALK(stmt->defexpr))
				return true;
		}
			break;
		case T_DoStmt:
		{
		   DoStmt *stmt = (DoStmt *)node;	
						
			if (WALK(stmt->args))
				return true;
		}
			break;		
		case T_InlineCodeBlock:
		{
		   InlineCodeBlock *stmt = (InlineCodeBlock *)node;	
						
			if (WALK(stmt->params))
				return true;		
		}
			break;		
		case T_TransactionStmt:
		{
		   TransactionStmt *stmt = (TransactionStmt *)node;	

			if (WALK(stmt->options))
				return true;		
		}
			break;		
		case T_CompositeTypeStmt:
		{
		   CompositeTypeStmt *stmt = (CompositeTypeStmt *)node;	
	
			if (WALK(stmt->typevar))
				return true;
			if (WALK(stmt->coldeflist))
				return true;		
		}
			break;		
		case T_CreateEnumStmt:
		{
		   CreateEnumStmt *stmt = (CreateEnumStmt *)node;	
	
			if (WALK(stmt->typeName))
				return true;
			if (WALK(stmt->vals))
				return true;		
		}
			break;		
		case T_CreateRangeStmt:
		{
		   CreateRangeStmt *stmt = (CreateRangeStmt *)node;	
	
			if (WALK(stmt->typeName))
				return true;
			if (WALK(stmt->params))
				return true;		
		}
			break;		
		case T_AlterEnumStmt:
		{
		   AlterEnumStmt *stmt = (AlterEnumStmt *)node;	
	
			if (WALK(stmt->typeName))
				return true;		
		}
			break;		
		case T_CreatedbStmt:
		{
		   CreatedbStmt *stmt = (CreatedbStmt *)node;	
	
			if (WALK(stmt->options))
				return true;		
		}
			break;		
		case T_AlterDatabaseStmt:
		{
		   AlterDatabaseStmt *stmt = (AlterDatabaseStmt *)node;	
	
			if (WALK(stmt->options))
				return true;		
		}
			break;		
		case T_AlterDatabaseSetStmt:
		{
		   AlterDatabaseSetStmt *stmt = (AlterDatabaseSetStmt *)node;	
	
			if (WALK(stmt->setstmt))
				return true;		
		}
			break;		
		case T_AlterSystemStmt:
		{
		   AlterSystemStmt *stmt = (AlterSystemStmt *)node;	
	
			if (WALK(stmt->setstmt))
				return true;		
		}
			break;		
		case T_ClusterStmt:
		{
		   ClusterStmt *stmt = (ClusterStmt *)node;	
	
			if (WALK(stmt->relation))
				return true;		
		}
			break;		
		case T_VacuumStmt:
		{
		   VacuumStmt *stmt = (VacuumStmt *)node;	
	
			if (WALK(stmt->options))
				return true;
			if (WALK(stmt->rels))
				return true;		
		}
			break;		
		case T_ExplainStmt:
		{
		   ExplainStmt *stmt = (ExplainStmt *)node;	
	
			if (WALK(stmt->query))
				return true;
			if (WALK(stmt->options))
				return true;		
		}
			break;		
		case T_RefreshMatViewStmt:
		{
		   RefreshMatViewStmt *stmt = (RefreshMatViewStmt *)node;	
	
			if (WALK(stmt->relation))
				return true;
		}
			break;		

		case T_LockStmt:
		{
		   LockStmt *stmt = (LockStmt *)node;	
	
			if (WALK(stmt->relations))
				return true;
		}
			break;		

		case T_ConstraintsSetStmt:
		{
		   ConstraintsSetStmt *stmt = (ConstraintsSetStmt *)node;	
	
			if (WALK(stmt->constraints))
				return true;		
		}
			break;	
		case T_ReindexStmt:
		{
		   ReindexStmt *stmt = (ReindexStmt *)node;	
	
			if (WALK(stmt->relation))
				return true;	
		}
			break;				
		
		case T_CreateConversionStmt:
		{
		   CreateConversionStmt *stmt = (CreateConversionStmt *)node;	
	
			if (WALK(stmt->conversion_name))
				return true;
			if (WALK(stmt->func_name))
				return true;
		}
			break;					
		case T_DropOwnedStmt:
		{
		   DropOwnedStmt *stmt = (DropOwnedStmt *)node;	
	
			if (WALK(stmt->roles))
				return true;	
		}
			break;					
		case T_ReassignOwnedStmt:
		{
		   ReassignOwnedStmt *stmt = (ReassignOwnedStmt *)node;	
	
			if (WALK(stmt->roles))
				return true;
			if (WALK(stmt->newrole))
				return true;	
		}
			break;		
		case T_AlterTSConfigurationStmt:
		{
		   AlterTSConfigurationStmt *stmt = (AlterTSConfigurationStmt *)node;	
	
			if (WALK(stmt->cfgname))
				return true;
			if (WALK(stmt->tokentype))
				return true;
			if (WALK(stmt->dicts))
				return true;	
		}
			break;					
		case T_Alias:
		{
		   Alias *stmt = (Alias *)node;	
	
			if (WALK(stmt->colnames))
				return true;
		}
			break;		
		case T_RangeVar:
		{
		   RangeVar *stmt = (RangeVar *)node;	
	
			if (WALK(stmt->alias))
				return true;
		}
			break;		
		case T_Aggref:
		{
		   Aggref *stmt = (Aggref *)node;	
	
			if (WALK(stmt->aggdirectargs))
				return true;
			if (WALK(stmt->args))
				return true;
			if (WALK(stmt->aggorder))
				return true;
			if (WALK(stmt->aggdistinct))
				return true;
			if (WALK(stmt->aggfilter))
				return true;
		}
			break;		
		case T_WindowFunc:
		{
		   WindowFunc *stmt = (WindowFunc *)node;

			if (WALK(stmt->args))
				return true;
			if (WALK(stmt->aggfilter))
				return true;
		}
			break;		
		case T_SubscriptingRef:
		{
		   SubscriptingRef *stmt = (SubscriptingRef *)node;

			if (WALK(stmt->refupperindexpr))
				return true;
			if (WALK(stmt->reflowerindexpr))
				return true;
			if (WALK(stmt->refexpr))
				return true;
			if (WALK(stmt->refassgnexpr))
				return true;
		}
			break;		
		case T_NamedArgExpr:
		{
			NamedArgExpr *stmt = (NamedArgExpr *)node;

			if (WALK(stmt->arg))
				return true;		
		}
			break;		
		case T_FuncExpr:
		{
		   FuncExpr *stmt = (FuncExpr *)node;

			if (WALK(stmt->args))
				return true;
		}
			break;		
		case T_OpExpr:
		{
			OpExpr *stmt = (OpExpr *)node;

			 if (WALK(stmt->args))
				 return true;
		}
			break;		
		case T_ScalarArrayOpExpr:
		{
			ScalarArrayOpExpr *stmt = (ScalarArrayOpExpr *)node;

			 if (WALK(stmt->args))
				 return true;
		}
			break;		
		case T_BoolExpr:
		{
			BoolExpr *stmt = (BoolExpr *)node;
		
			 if (WALK(stmt->args))
				 return true;
		}
			break;		
		case T_SubLink:
		{
			SubLink    *sublink = (SubLink *)node;

			if (WALK(sublink->testexpr))
				return true;
			if (WALK(sublink->operName))
				return true;
			if (WALK(sublink->subselect))
				return true;
		}
			break;
		case T_SubPlan:
		{
		   SubPlan *stmt = (SubPlan *)node;
	
			if (WALK(stmt->testexpr))
				return true;
			if (WALK(stmt->paramIds))
				return true;
			if (WALK(stmt->setParam))
				return true;
			if (WALK(stmt->parParam))
				return true;
			if (WALK(stmt->args))
				return true;
		}
			break;		
		case T_AlternativeSubPlan:
		{
		   AlternativeSubPlan *stmt = (AlternativeSubPlan *)node;

			if (WALK(stmt->subplans))
				return true;
		}
			break;		
		case T_FieldSelect:
		{
		   FieldSelect *stmt = (FieldSelect *)node;

			if (WALK(stmt->arg))
				return true;
		}
			break;		
		case T_FieldStore:
		{
		   FieldStore *stmt = (FieldStore *)node;
	
			if (WALK(stmt->arg))
				return true;
			if (WALK(stmt->newvals))
				return true;
			if (WALK(stmt->fieldnums))
				return true;
		}
			break;		
		case T_RelabelType:
		{
		   RelabelType *stmt = (RelabelType *)node;
	
			if (WALK(stmt->arg))
				return true;
		}
			break;		
		case T_CoerceViaIO:
		{
		   CoerceViaIO *stmt = (CoerceViaIO *)node;
	
			if (WALK(stmt->arg))
				return true;
		}
			break;		
		case T_ArrayCoerceExpr:
		{
		   ArrayCoerceExpr *stmt = (ArrayCoerceExpr *)node;
	
			if (WALK(stmt->arg))
				return true;
		}
			break;		
		case T_ConvertRowtypeExpr:
		{
		   ConvertRowtypeExpr *stmt = (ConvertRowtypeExpr *)node;
	
			if (WALK(stmt->arg))
				return true;
		}
			break;		
		case T_CollateExpr:
		{
		   CollateExpr *stmt = (CollateExpr *)node;
	
			if (WALK(stmt->arg))
				return true;
		}
			break;		
		case T_CaseWhen:
		{
			CaseWhen   *when = (CaseWhen *)node;
		  
		   if (WALK(when->expr))
			   return true;
		   if (WALK(when->result))
			   return true;
		}
			break;		
		case T_CaseExpr:
		{
		   CaseExpr   *caseexpr = (CaseExpr *)node;

		   if (WALK(caseexpr->arg))
			   return true;
		   if (WALK(caseexpr->args))
			   return true;
		   if (WALK(caseexpr->defresult))
			   return true;
		}
			break;
		case T_RowExpr:
		{
		   RowExpr   *stmt = (RowExpr *)node;
	
		   if (WALK(stmt->args))
			   return true;
		   if (WALK(stmt->colnames))
			   return true;
		}
			break;
		case T_RowCompareExpr:
		{
		   RowCompareExpr *stmt = (RowCompareExpr *)node;
	
			if (WALK(stmt->opnos))
				return true;
			if (WALK(stmt->opfamilies))
				return true;
			if (WALK(stmt->inputcollids))
				return true;
			if (WALK(stmt->largs))
				return true;
			if (WALK(stmt->rargs))
				return true;
		}
			break;		
		case T_CoalesceExpr:
			return WALK(((CoalesceExpr *)node)->args);
		case T_MinMaxExpr:
			return WALK(((MinMaxExpr *)node)->args);
		case T_XmlExpr:
		{
			XmlExpr    *xexpr = (XmlExpr *)node;

			if (WALK(xexpr->named_args))
				return true;
			if (WALK(xexpr->arg_names))
				return true;
			if (WALK(xexpr->args))
				return true;
		}
			break;
		case T_NullTest:
			return WALK(((NullTest *)node)->arg);
		case T_BooleanTest:
			return WALK(((BooleanTest *)node)->arg);
		case T_CoerceToDomain:
			return WALK(((CoerceToDomain *)node)->arg);
		case T_InferenceElem:
			return WALK(((InferenceElem *)node)->expr);
		case T_TargetEntry:
			return WALK(((TargetEntry *)node)->expr);
		case T_FromExpr:
		{
  		    FromExpr *stmt = (FromExpr *)node;
			if (WALK(stmt->fromlist))
				return true;
			if (WALK(stmt->quals))
				return true;
		}
			break;				
		case T_JoinExpr:
		{
		   JoinExpr   *join = (JoinExpr *)node;

		   if (WALK(join->larg))
			   return true;
		   if (WALK(join->rarg))
			   return true;
		   if (WALK(join->usingClause))
			   return true;
		   if (WALK(join->quals))
			   return true;
		   if (WALK(join->alias))
			   return true;
		}
			break;
		case T_OnConflictExpr:
		{
		   OnConflictExpr *stmt = (OnConflictExpr *)node;
	
			if (WALK(stmt->arbiterElems))
				return true;
			if (WALK(stmt->arbiterWhere))
				return true;
			if (WALK(stmt->onConflictSet))
				return true;
			if (WALK(stmt->onConflictWhere))
				return true;
			if (WALK(stmt->exclRelTlist))
				return true;
		}
			break;				
		case T_IntoClause:
		{
			IntoClause *into = (IntoClause *)node;

			if (WALK(into->rel))
				return true;
			if (WALK(into->colNames))
				return true;
			if (WALK(into->options))
				return true;
			if (WALK(into->viewQuery))
				return true;
		}
			break;
		case T_List:
		foreach(temp, (List *)node)
		{
			if (WALK((Node *) lfirst(temp)))
				return true;
		}
			break;
		case T_RawStmt:
		{
			RawStmt *raw = (RawStmt *)node;

			if (WALK(raw->stmt))
				return true;
		}
			break;
		case T_PLAssignStmt:
		{
			PLAssignStmt *assign = (PLAssignStmt *)node;

			if (WALK(assign->indirection))
				return true;
			if (WALK(assign->val))
				return true;
		}
			break;
		case T_CallStmt:
			{
				CallStmt *callstmt = (CallStmt *)node;

				if (WALK(callstmt->funccall))
					return true;
				if (WALK(callstmt->hostvariable))
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

/*
 * set dynamic CallStmt parser status
 */
void
setdynamic_callparser(bool value)
{
	IsDynCallStmt = value;
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

#undef WALK

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
