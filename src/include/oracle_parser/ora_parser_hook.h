/*-------------------------------------------------------------------------
 *
 * ora_parser_hook.h
 *		Variable Declarations shown as below are used to
 *	 	for the Hook function's definitions.
 *
 *
 * Portions Copyright (c) 2023-2025, IvorySQL Global Development Team
 *
 * src/include/oracle_parser/ora_parser_hook.h
 *
 * add the file for requirement "SQL PARSER"
 *
 *-------------------------------------------------------------------------
 */

#ifndef ORA_PARSER_HOOK_H
#define ORA_PARSER_HOOK_H

/* Hook for plugins to get control in get_keywords() */
typedef Datum (*get_keywords_hook_type)(PG_FUNCTION_ARGS);
extern PGDLLIMPORT get_keywords_hook_type get_keywords_hook;

/* Hook for plugins to get control in fill_in_constant_lengths() */
typedef void (*fill_in_constant_lengths_hook_type)(void *jstate, const char *query, int query_loc);
extern PGDLLIMPORT fill_in_constant_lengths_hook_type fill_in_constant_lengths_hook;

//fill_in_constant_lengths_hook_type fill_in_constant_lengths_hook = NULL;

/* Hook for plugins to get control in quote_identifier() */
typedef const char *(*quote_identifier_hook_type)(const char *ident);
extern PGDLLIMPORT quote_identifier_hook_type quote_identifier_hook;

#endif							/* ORA_PARSER_HOOK_H */
