/*-------------------------------------------------------------------------
 *
 * parse_param.h
 *	  handle parameters in parser
 *
 * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group
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
 * type oid (32bits), 3 highest bits; 1st is arg of '{? = call}',
 * second means OUT mode, third means IN modes. left 29 bits for
 * value of type.
 */
#define IsLeftCall(typeoid) ((typeoid) & 0x80000000)
#define IsModeOut(typeoid) ((typeoid) & 0x40000000)
#define SetModeOut(typeoid) ((typeoid) |= 0x40000000)
#define IsModeIn(typeoid) ((typeoid) & 0x20000000)
#define SetModeIn(typeoid) ((typeoid) |= 0x20000000)
#define UnSetModeOut(typeoid) ((typeoid) &= 0x1FFFFFFF)

extern Node *ParseParamVariable(Node *arg);
extern void GetParamMode(Oid *paramTypes, int numParams, char *modes);
extern void ParseVarParamState(void *arg, Node *param, bool *isOut,
						bool *isIn, bool *isLeftCall);
extern void SetVarParamState(void *arg, Param *param, int index);
extern int push_oraparam_stack(void);
extern void pop_oraparam_stack(int top, int cur);
extern void get_oraparam_level(int *top, int *cur);

extern void forward_oraparam_stack(void);
extern void backward_oraparam_stack(void);

extern  int calculate_oraparamnumber(const char* name);
extern bool calculate_oraparamnumbers(List	   *parsetree_list);
extern void setdynamic_parser(bool value);
extern bool getdynamic_parser(void);
extern void check_variables_does_match(int variables);
extern void setdynamic_haspgparam(bool value);
extern void setdynamic_docheckvar(bool values);
extern bool getdynmaic_docheckvar(void);
extern void setdynamic_doparser(bool value);
extern void set_bindbyname(bool value);
extern bool get_bindbyname(void);
extern int calculate_oraparamname_position(Node *parsetree, char ***paramnames);
extern int calculate_oraparamname(char ***paramnames);

#endif							/* PARSE_PARAM_H */
