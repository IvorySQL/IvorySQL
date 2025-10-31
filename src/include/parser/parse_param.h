/*-------------------------------------------------------------------------
 *
 * parse_param.h
 *	  handle parameters in parser
 *
 * Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/parser/parse_param.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PARSE_PARAM_H
#define PARSE_PARAM_H

#include "parser/parse_node.h"

extern void setup_parse_fixed_parameters(ParseState *pstate,
										 const Oid *paramTypes, int numParams);
extern void setup_parse_variable_parameters(ParseState *pstate,
											Oid **paramTypes, int *numParams);
extern void check_variable_parameters(ParseState *pstate, Query *query);
extern bool query_contains_extern_params(Query *query);

/*
 * The oid type has a total of 32 bits, and the highest 3 bits are used as:
 * first is arg of '{? = call}',
 * second means OUT mode, 
 * third means IN modes. 
 * left 29 bits for value of type.
 */
#define IsLeftCall(typeoid) ((typeoid) & 0x80000000)
#define IsModeOut(typeoid) ((typeoid) & 0x40000000)
#define SetModeOut(typeoid) ((typeoid) |= 0x40000000)
#define UnSetModeOut(typeoid) ((typeoid) &= 0x1FFFFFFF)
#define IsModeIn(typeoid) ((typeoid) & 0x20000000)
#define SetModeIn(typeoid) ((typeoid) |= 0x20000000)

extern Node *ParseParamVariable(Node *arg);
extern void ParseVarParamState(void *arg, Node *param, bool *isOut,
				bool *isIn, bool *isLeftCall);
extern void GetParamMode(Oid *paramTypes, int numParams, char *modes);

extern int push_oraparam_stack(void);
extern void pop_oraparam_stack(int top, int cur);
extern void get_oraparam_level(int *top, int *cur);
extern void SetVarParamState(void *arg, Param *param, int index);

extern void forward_oraparam_stack(void);
extern void backward_oraparam_stack(void);

extern bool calculate_oraparamnumbers(List *parsetree_list);
extern  int calculate_oraparamnumber(const char* name);
extern bool get_ParseDynSql(void);
extern void set_ParseDynSql(bool value);
extern void check_variables_does_match(int variables);
extern void set_haspgparam(bool value);
extern bool get_doStmtCheckVar(void);
extern void set_doStmtCheckVar(bool values);
extern void set_parseDynDoStmt(bool value);
extern bool get_bindByName(void);
extern void set_bindByName(bool value);
extern void setdynamic_callparser(bool value);
extern int calculate_oraparamname(char ***paramnames);
extern int calculate_oraparamname_position(Node *parsetree, char ***paramnames);

#endif							/* PARSE_PARAM_H */
